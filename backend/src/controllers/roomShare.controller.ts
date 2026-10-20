import { randomBytes } from 'crypto';
import { Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import prisma from '../utils/prisma';
import { checkDmAccess } from '../services/dmAccess.service';
import { isBlockedBetween } from '../utils/blockGuard';
import { emitToUser, isUserInRoom } from '../services/socket.service';
import { ANDROID_PACKAGE, ROOM_SHARE_ORIGIN, escapeHtml, roomAdmission, safePreviewUrl, unavailable, validShareToken } from '../services/roomShare.service';

export const shareRateLimit = rateLimit({ windowMs: 60_000, max: 20, standardHeaders: true, legacyHeaders: false });

export async function createRoomShare(req: Request, res: Response) {
  const userId = req.userId!;
  const roomId = Number(req.params.roomId);
  const channel = req.body?.channel;
  const raw = req.body?.recipientIds;
  if (!Number.isSafeInteger(roomId) || roomId <= 0 || !['dm', 'external'].includes(channel) ||
      (channel === 'dm' && (!Array.isArray(raw) || raw.length < 1 || raw.length > 30 ||
        raw.some((id: unknown) => !Number.isSafeInteger(id) || Number(id) <= 0 || id === userId)))) {
    return res.status(400).json({ ok: false, message: 'طلب المشاركة غير صالح' });
  }
  const { room, error } = await roomAdmission(roomId, userId);
  if (!room) return res.status(error?.code === 'BANNED' ? 403 : 404).json(error);
  // A private/locked room can only be shared by its owner or an admitted user.
  if ((room.isLocked || room.type !== 'public') && room.ownerId !== userId && !isUserInRoom(userId, roomId)) {
    return res.status(403).json({ ok: false, message: 'ادخل الغرفة أولاً لمشاركتها' });
  }
  const recipients: number[] = channel === 'dm' ? [...new Set<number>(raw)] : [];
  for (const recipient of recipients) {
    if (await isBlockedBetween(userId, recipient)) {
      return res.status(403).json({ ok: false, code: 'BLOCKED', recipientId: recipient, message: 'يوجد حظر بينكما' });
    }
    const access = await checkDmAccess(userId, recipient);
    if (!access.allowed) return res.status(403).json({ ok: false, ...access, recipientId: recipient });
  }
  const inviter = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { id: true, name: true, avatarUrl: true } });
  const result = await prisma.$transaction(async (tx) => {
    const share = await tx.roomShareToken.create({ data: {
      token: randomBytes(24).toString('base64url'), roomId, inviterId: userId,
      roomName: room.name, roomImageUrl: room.coverImageUrl,
    } });
    const metadata = { token: share.token, roomId, roomName: room.name, roomImageUrl: room.coverImageUrl,
      roomDisplayId: String(room.id), inviterId: userId, inviterName: inviter.name };
    const messages = [];
    for (const recipientId of recipients) {
      const pair = { userAId: Math.min(userId, recipientId), userBId: Math.max(userId, recipientId) };
      const conversation = await tx.conversation.upsert({
        where: { userAId_userBId: pair }, create: pair, update: {},
      });
      for (const participantId of [userId, recipientId]) {
        await tx.conversationParticipant.upsert({
          where: { conversationId_userId: { conversationId: conversation.id, userId: participantId } },
          create: { conversationId: conversation.id, userId: participantId }, update: {},
        });
      }
      const message = await tx.directMessage.create({ data: {
        conversationId: conversation.id, senderId: userId, type: 'room_invite', metadata,
        // Older clients still receive a useful, real HTTPS link.
        text: `${inviter.name} يدعوك للانضمام إلى غرفة: ${room.name}\n${ROOM_SHARE_ORIGIN}/room/${share.token}`,
      } });
      await tx.conversation.update({ where: { id: conversation.id }, data: { lastMessageId: message.id, lastMessageAt: message.createdAt } });
      messages.push({ recipientId, message });
    }
    return { share, messages };
  });
  for (const { recipientId, message } of result.messages) {
    const payload = { ...message, createdAt: message.createdAt.toISOString(), sender: inviter };
    for (const target of [userId, recipientId]) {
      emitToUser(target, 'dm_new_message', payload);
      emitToUser(target, 'dm_conversation_updated', { conversationId: message.conversationId,
        partnerId: target === userId ? recipientId : userId, lastMessage: message.text,
        lastMessageTime: message.createdAt.toISOString() });
    }
  }
  return res.json({ ok: true, token: result.share.token, url: `${ROOM_SHARE_ORIGIN}/room/${result.share.token}` });
}

export async function resolveRoomShare(req: Request, res: Response) {
  const token = req.params.token;
  if (!validShareToken(token)) return res.status(404).json(unavailable);
  const share = await prisma.roomShareToken.findUnique({ where: { token } });
  if (!share || share.revokedAt || share.expiresAt <= new Date()) return res.status(404).json(unavailable);
  const { room, error } = await roomAdmission(share.roomId, req.userId!);
  if (!room) return res.status(error?.code === 'BANNED' ? 403 : 404).json(error);
  const used = await prisma.roomShareToken.updateMany({
    where: { id: share.id, revokedAt: null, expiresAt: { gt: new Date() } },
    data: { useCount: { increment: 1 }, lastUsedAt: new Date() },
  });
  if (!used.count) return res.status(404).json(unavailable);
  res.setHeader('Cache-Control', 'no-store');
  return res.json({ ok: true, roomId: room.id, inviterId: share.inviterId });
}

export function assetLinks(_req: Request, res: Response) {
  const fingerprints = (process.env.ANDROID_APP_SHA256 || '').split(',').map((s) => s.trim().toUpperCase())
    .filter((s) => /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(s));
  res.json(fingerprints.length ? [{ relation: ['delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name: ANDROID_PACKAGE, sha256_cert_fingerprints: fingerprints } }] : []);
}

export async function roomShareLanding(req: Request, res: Response) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('Content-Security-Policy', "default-src 'none'; img-src https:; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
  const token = req.params.token;
  const share = validShareToken(token) ? await prisma.roomShareToken.findUnique({ where: { token } }) : null;
  const room = share ? await prisma.room.findUnique({ where: { id: share.roomId } }) : null;
  if (!share || share.revokedAt || share.expiresAt <= new Date() || !room?.isActive) {
    return res.status(404).type('html').send('<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SamaFox</title><p>الغرفة غير متاحة حالياً</p></html>');
  }
  const url = `${ROOM_SHARE_ORIGIN}/room/${share.token}`;
  const play = `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE}&referrer=${encodeURIComponent(`room_token=${share.token}`)}`;
  const intent = `intent://samafox.almobarmg.com/room/${share.token}#Intent;scheme=https;package=${ANDROID_PACKAGE};S.browser_fallback_url=${encodeURIComponent(play)};end`;
  // Locked/private rooms reveal no presentation to unauthenticated browsers.
  const privateRoom = room.isLocked || room.type !== 'public';
  const name = privateRoom ? 'دعوة إلى غرفة SamaFox' : share.roomName;
  const image = privateRoom ? null : safePreviewUrl(share.roomImageUrl);
  return res.type('html').send(`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(name)}</title><meta property="og:title" content="${escapeHtml(name)}">${image ? `<meta property="og:image" content="${escapeHtml(image)}">` : ''}<style>body{margin:0;background:#170d30;color:white;font:18px sans-serif;text-align:center}main{max-width:480px;margin:auto;padding:32px 20px}img{width:100%;max-width:240px;border-radius:24px}a{display:block;padding:16px;margin:16px 0;background:#7c3aed;color:white;border-radius:16px;text-decoration:none;overflow-wrap:anywhere}</style></head><body><main>${image ? `<img alt="صورة الغرفة" src="${escapeHtml(image)}">` : ''}<h1>${escapeHtml(name)}</h1><a href="${escapeHtml(intent)}">فتح في SamaFox</a><a href="${escapeHtml(url)}">فتح رابط التطبيق</a><a href="${escapeHtml(play)}">تحميل من Google Play</a></main></body></html>`);
}
