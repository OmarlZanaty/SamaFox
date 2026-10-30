import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { createNotification } from '../services/notification.service';
import { isBlockedBetween, blockedUserIds } from '../utils/blockGuard';
import { checkDmAccess, unlockConversationWithFee, DmUnlockError } from '../services/dmAccess.service';
import { getChatBubble, getChatBubbles } from '../utils/chatBubble';

/**
 * C18 — minimum VIP tier allowed to send images in a DM, set from لوحة التحكم.
 * 0 / unset = everyone may. Lives in AppSetting so it ships without a migration.
 */
export const MESSAGE_IMAGE_MIN_VIP_KEY = 'message_image_min_vip';

export async function getMessageImageMinVip(): Promise<number> {
  try {
    const row = await (prisma as any).appSetting.findUnique({
      where: { key: MESSAGE_IMAGE_MIN_VIP_KEY },
    });
    const n = Number(row?.value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  } catch {
    // Fail OPEN: a settings blip must not stop everyone from sending images.
    return 0;
  }
}

/**
 * Same gate for pictures in ROOM chat. Separate key so the dashboard can open
 * one without the other — a room is public, a DM is not.
 */
export const ROOM_IMAGE_MIN_VIP_KEY = 'room_image_min_vip';

export async function getRoomImageMinVip(): Promise<number> {
  try {
    const row = await prisma.appSetting.findUnique({ where: { key: ROOM_IMAGE_MIN_VIP_KEY } });
    const n = Number(row?.value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  } catch {
    return 0; // fail open, as the DM gate does
  }
}

export async function setRoomImageMinVip(level: number): Promise<number> {
  const value = String(Math.max(0, Math.floor(level)));
  await prisma.appSetting.upsert({
    where: { key: ROOM_IMAGE_MIN_VIP_KEY },
    update: { value },
    create: { key: ROOM_IMAGE_MIN_VIP_KEY, value },
  });
  return Number(value);
}

/**
 * SPEC52 #17 — "إرسال صورة كهدية" (the picture button in room chat) uses the
 * room_image_min_vip bar above as its "Image Gift Minimum VIP". What a user
 * BELOW the bar sees is the owner's choice: 'lock' (icon shown with a lock) or
 * 'hide' (no icon). The send itself is re-checked on the server every time.
 */
export const IMAGE_GIFT_MODE_KEY = 'image_gift_locked_mode';

export async function getImageGiftMode(): Promise<'lock' | 'hide'> {
  try {
    const row = await prisma.appSetting.findUnique({ where: { key: IMAGE_GIFT_MODE_KEY } });
    return row?.value === 'hide' ? 'hide' : 'lock';
  } catch {
    return 'lock';
  }
}

export async function setImageGiftMode(mode: string): Promise<'lock' | 'hide'> {
  const value = mode === 'hide' ? 'hide' : 'lock';
  await prisma.appSetting.upsert({
    where: { key: IMAGE_GIFT_MODE_KEY },
    update: { value },
    create: { key: IMAGE_GIFT_MODE_KEY, value },
  });
  return value;
}

/**
 * «الصور في الرسايل … تكون محكومه ب lv معين احدده من لوحة التحكم» — next to the
 * VIP bar, a LEVEL bar (the user's ليفل الداعم) per scope. 0 / unset = off.
 */
export const MESSAGE_IMAGE_MIN_LEVEL_KEY = 'message_image_min_level';
export const ROOM_IMAGE_MIN_LEVEL_KEY = 'room_image_min_level';

async function readMinSetting(key: string): Promise<number> {
  try {
    const row = await prisma.appSetting.findUnique({ where: { key } });
    const n = Number(row?.value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  } catch {
    return 0; // fail open, like the VIP bars
  }
}

export async function setMinSetting(key: string, level: number): Promise<number> {
  const value = String(Math.max(0, Math.floor(level)));
  await prisma.appSetting.upsert({ where: { key }, update: { value }, create: { key, value } });
  return Number(value);
}

export const getMessageImageMinLevel = () => readMinSetting(MESSAGE_IMAGE_MIN_LEVEL_KEY);
export const getRoomImageMinLevel = () => readMinSetting(ROOM_IMAGE_MIN_LEVEL_KEY);

/**
 * May [userId] send a picture in a DM / the room chat? null = yes; otherwise
 * the refusal. An expired VIP counts as no VIP («مخصصه ل vip معين مش شغاله»:
 * the old check read vipLevel alone, so a lapsed VIP still passed).
 */
export async function pictureDenial(userId: number, scope: 'dm' | 'room') {
  const [minVip, minLevel] = await Promise.all(scope === 'dm'
    ? [getMessageImageMinVip(), getMessageImageMinLevel()]
    : [getRoomImageMinVip(), getRoomImageMinLevel()]);
  if (minVip <= 0 && minLevel <= 0) return null;
  const me = await prisma.user.findUnique({ where: { id: userId }, select: { vipLevel: true, vipExpiresAt: true, level: true } });
  const vipActive = !me?.vipExpiresAt || me.vipExpiresAt.getTime() > Date.now();
  const myVip = vipActive ? me?.vipLevel ?? 0 : 0;
  const where = scope === 'dm' ? 'إرسال الصور' : 'إرسال الصور في الغرفة';
  if (minVip > 0 && myVip < minVip) {
    return { code: 'VIP_REQUIRED', minVip, minLevel, message: `${where} متاح من VIP ${minVip} فما فوق` };
  }
  if (minLevel > 0 && (me?.level ?? 0) < minLevel) {
    return { code: 'LEVEL_REQUIRED', minVip, minLevel, message: `${where} متاح من ليفل ${minLevel} فما فوق` };
  }
  return null;
}

/** GET /messages/room-image-policy — what the picture button should look like for me. */
export const getRoomImagePolicy = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number;
    const [minVip, minLevel, mode, denial] = await Promise.all([
      getRoomImageMinVip(),
      getRoomImageMinLevel(),
      getImageGiftMode(),
      pictureDenial(userId, 'room'),
    ]);
    return res.json({ success: true, data: { minVip, minLevel, mode, allowed: denial == null, message: denial?.message ?? null } });
  } catch (e) {
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};

export async function setMessageImageMinVip(level: number): Promise<number> {
  const value = String(Math.max(0, Math.floor(level)));
  await (prisma as any).appSetting.upsert({
    where: { key: MESSAGE_IMAGE_MIN_VIP_KEY },
    update: { value },
    create: { key: MESSAGE_IMAGE_MIN_VIP_KEY, value },
  });
  return Number(value);
}


type AuthedRequest = Request & { userId?: number };

function toInt(v: any): number | null {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

// ✅ Get conversations list for current user (Messenger inbox)
export async function getConversations(req: AuthedRequest, res: Response) {
  try {
    const me = req.userId;
    if (!me) return res.status(401).json({ message: 'Unauthorized' });

    const convs = await prisma.conversation.findMany({
      where: {
        OR: [{ userAId: me }, { userBId: me }],
        participants: { some: { userId: me } },
      },
      orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
      include: {
        userA: { select: { id: true, name: true, avatarUrl: true } },
        userB: { select: { id: true, name: true, avatarUrl: true } },
        participants: {
          where: { userId: me },
          select: { lastReadAt: true, muted: true },
        },
        lastMessage: {
          select: { id: true, text: true, type: true, createdAt: true, senderId: true },
        },
      },
    });

    // Blocked people drop out of the inbox in both directions, so a block
    // actually removes the thread instead of leaving it sitting there.
    const blocked = await blockedUserIds(me);

    const out = convs
      .filter((c) => !blocked.has(c.userAId === me ? c.userBId : c.userAId))
      .map((c) => {
      const partner = c.userAId === me ? c.userB : c.userA;
      const myPart = c.participants[0] ?? null;

      // unread count: messages after my lastReadAt
      // if lastReadAt is null => all messages are unread (we count by query later; here send 0 and compute endpoint if you want)
      return {
        id: c.id,
        partnerId: partner.id,
        partnerName: partner.name,
        partnerAvatar: partner.avatarUrl,
        lastMessage: c.lastMessage?.text ?? null,
        lastMessageTime: c.lastMessage?.createdAt?.toISOString?.() ?? c.lastMessageAt?.toISOString?.() ?? null,
        unreadCount: 0, // optional: compute with a second query for speed, see note below
        muted: myPart?.muted ?? false,
      };
    });

    return res.json(out);
  } catch (err) {
    console.error('[messages.getConversations]', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// ✅ Create or get conversation with partner
export async function getOrCreateConversation(req: AuthedRequest, res: Response) {
  try {
    const me = req.userId;
    if (!me) return res.status(401).json({ message: 'Unauthorized' });

    const partnerId = toInt(req.body?.partnerId ?? req.params?.partnerId);
    if (!partnerId) return res.status(400).json({ message: 'partnerId is required' });
    if (partnerId === me) return res.status(400).json({ message: 'Cannot message yourself' });

    // Don't even open the thread when a block is in place either way.
    if (await isBlockedBetween(me, partnerId)) {
      return res.status(403).json({
        code: 'BLOCKED',
        message: 'لا يمكن بدء محادثة — يوجد حظر بينكما',
      });
    }

    // enforce unique pair ordering to match @@unique([userAId,userBId])
    const userAId = Math.min(me, partnerId);
    const userBId = Math.max(me, partnerId);

    const conv = await prisma.conversation.upsert({
      where: { userAId_userBId: { userAId, userBId } },
      create: {
        userAId,
        userBId,
        participants: {
          create: [
            { userId: me },
            { userId: partnerId },
          ],
        },
      },
      update: {},
      include: {
        userA: { select: { id: true, name: true, avatarUrl: true } },
        userB: { select: { id: true, name: true, avatarUrl: true } },
      },
    });

    const partner = conv.userAId === me ? conv.userB : conv.userA;

    return res.json({
      conversationId: conv.id,
      partnerId: partner.id,
      partnerName: partner.name,
      partnerAvatar: partner.avatarUrl,
    });
  } catch (err) {
    console.error('[messages.getOrCreateConversation]', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// ✅ Get messages for a conversation (simple pagination with beforeId)
export async function getMessages(req: AuthedRequest, res: Response) {
  try {
    const me = req.userId;
    if (!me) return res.status(401).json({ message: 'Unauthorized' });

    const conversationId = toInt(req.params.conversationId ?? req.query.conversationId);
    if (!conversationId) return res.status(400).json({ message: 'conversationId is required' });

    const limit = Math.min(50, Math.max(1, Number(req.query.limit ?? 30)));
    const beforeId = toInt(req.query.beforeId);

    // ensure user is participant
    const part = await prisma.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId, userId: me } },
      select: { id: true },
    });
    if (!part) return res.status(403).json({ message: 'Not a participant' });

    const msgs = await prisma.directMessage.findMany({
      where: {
        conversationId,
        ...(beforeId ? { id: { lt: beforeId } } : {}),
      },
      orderBy: { id: 'desc' },
      take: limit,
      include: {
        sender: { select: { id: true, name: true, avatarUrl: true } },
      },
    });

    // C6 — the sender's equipped chat bubble, batched for the whole page. The
    // DM list never carried this, so a bubble the user had bought rendered in a
    // room and disappeared in the private messages.
    const bubbles = await getChatBubbles(msgs.map((m) => m.senderId));

    // return oldest->newest
    return res.json(msgs.reverse().map((m) => ({
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      text: m.text,
      imageUrl: m.imageUrl,
      type: m.type,
      metadata: m.metadata,
      audioUrl: (m as any).audioUrl ?? null,
      createdAt: m.createdAt.toISOString(),
      sender: m.sender,
      bubbleUrl: bubbles.get(m.senderId)?.bubbleUrl ?? null,
      bubbleMeta: bubbles.get(m.senderId)?.bubbleMeta ?? null,
    })));
  } catch (err) {
    console.error('[messages.getMessages]', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// ✅ Send message
// ✅ Send message (text / image / voice)
export async function sendMessage(req: AuthedRequest, res: Response) {
  try {
  const me = req.userId;
  if (!me) return res.status(401).json({ message: 'Unauthorized' });

  const conversationId = toInt(req.body?.conversationId);
  const text = (req.body?.text ?? '').toString().trim();
  const imageUrl = req.body?.imageUrl ? req.body.imageUrl.toString() : null;
  const audioUrl = req.body?.audioUrl ? req.body.audioUrl.toString() : null;

  // normalize type
  let type = (req.body?.type ?? '').toString().trim().toLowerCase();
  if (!type) {
    type = audioUrl ? 'voice' : imageUrl ? 'image' : 'text';
  }
  if (type === 'audio') type = 'voice';

  if (!conversationId) return res.status(400).json({ message: 'conversationId is required' });

  // ✅ Accept: text OR imageUrl OR audioUrl
  if (!text && !imageUrl && !audioUrl) {
    return res.status(400).json({ message: 'text, imageUrl, or audioUrl is required' });
  }

  // C18 — "تحديد من أي VIP يُسمح بإرسال الصور من لوحة التحكم". Enforced on the
  // server, not just hidden in the app: the picker being invisible is a
  // courtesy, this is the rule. Voice notes are deliberately ungated — the
  // client only ever asked for the image restriction.
  if (imageUrl) {
    const denial = await pictureDenial(me, 'dm');
    if (denial) return res.status(403).json(denial);
  }

  // ensure participant
  const part = await prisma.conversationParticipant.findUnique({
    where: { conversationId_userId: { conversationId, userId: me } },
    select: { id: true },
  });
  if (!part) return res.status(403).json({ message: 'Not a participant' });

  // القائمة السوداء — a block in either direction stops the DM. Without this
  // the block table was write-only and blocking someone changed nothing.
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    select: { userAId: true, userBId: true },
  });
  const otherId = conv ? (conv.userAId === me ? conv.userBId : conv.userAId) : null;
  if (otherId && (await isBlockedBetween(me, otherId))) {
    return res.status(403).json({
      code: 'BLOCKED',
      message: 'لا يمكن إرسال رسالة — يوجد حظر بينكما',
    });
  }

  // قفل الرسائل الخاصة — friends-only / paid (see dmAccess.service).
  if (otherId) {
    const access = await checkDmAccess(me, otherId);
    if (!access.allowed) {
      return res.status(access.code === 'DM_FEE_REQUIRED' ? 402 : 403).json({
        code: access.code,
        message: access.message,
        priceCoins: access.priceCoins,
        conversationId,
      });
    }
  }

  const created = await prisma.$transaction(async (tx) => {
    // Build data without triggering TS "unknown property" errors
    const data: any = {
      conversationId,
      senderId: me,
      text: text || null,
      imageUrl: type === 'image' ? imageUrl : null,
      type,
    };

    if (type === 'voice') {
      data.audioUrl = audioUrl || null;
    }

    // 1) Create message (no include)
    const msg = await tx.directMessage.create({ data });

    // 2) Update conversation lastMessage pointers
    await tx.conversation.update({
      where: { id: conversationId },
      data: {
        lastMessageId: msg.id,
        lastMessageAt: msg.createdAt,
      },
    });

    // 3) Re-fetch with sender (so API returns sender)
    const full = await tx.directMessage.findUnique({
      where: { id: msg.id },
      include: {
        sender: { select: { id: true, name: true, avatarUrl: true } },
      },
    });

    return full as any;
  });

  const conversation = await prisma.conversation.findUnique({
    where: { id: conversationId },
    select: { userAId: true, userBId: true },
  });
  const targetUserId = conversation
      ? (conversation.userAId === me ? conversation.userBId : conversation.userAId)
      : null;
  if (targetUserId != null) {
    await createNotification({
      userId: targetUserId,
      actorId: me,
      type: 'message_received',
      title: 'New message',
      body: created.type === 'text' ? (created.text || 'You received a new message') : 'You received a media message',
      data: {
        conversationId: created.conversationId,
        messageId: created.id,
        messageType: created.type,
      },
    });
  }

  // C6 — the echoed message carries the bubble too, so the sender's own copy
  // is drawn the same way as the one the recipient receives.
  const myBubble = await getChatBubble(created.senderId);

  return res.json({
    id: created.id,
    conversationId: created.conversationId,
    senderId: created.senderId,
    text: created.text,
    imageUrl: created.imageUrl,
    audioUrl: created.audioUrl ?? null,
    type: created.type,
    createdAt: created.createdAt.toISOString(),
    sender: created.sender ?? null,
    bubbleUrl: myBubble.bubbleUrl,
    bubbleMeta: myBubble.bubbleMeta,
  });
  } catch (err) {
    console.error('[messages.sendMessage]', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// ✅ Mark read (updates lastReadAt)
export async function markConversationRead(req: AuthedRequest, res: Response) {
  try {
    const me = req.userId;
    if (!me) return res.status(401).json({ message: 'Unauthorized' });

    const conversationId = toInt(req.body?.conversationId ?? req.params?.conversationId);
    if (!conversationId) return res.status(400).json({ message: 'conversationId is required' });

    await prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId, userId: me } },
      data: { lastReadAt: new Date() },
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error('[messages.markConversationRead]', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// ✅ GET /messages/access/:partnerId — may I message this person right now,
// and if not, what stands in the way (friends-only, or a fee and its price).
// The chat screen asks this on open so the gate is shown before typing.
export async function getDmAccess(req: AuthedRequest, res: Response) {
  try {
    const me = req.userId;
    if (!me) return res.status(401).json({ message: 'Unauthorized' });
    const partnerId = toInt(req.params.partnerId);
    if (!partnerId) return res.status(400).json({ message: 'partnerId is required' });
    if (await isBlockedBetween(me, partnerId)) {
      return res.json({ allowed: false, reason: 'blocked', code: 'BLOCKED', message: 'يوجد حظر بينكما', partnerPrivacy: 'public', priceCoins: 0, conversationId: null });
    }
    return res.json(await checkDmAccess(me, partnerId));
  } catch (err) {
    console.error('[messages.getDmAccess]', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// ✅ POST /messages/conversations/:conversationId/unlock — pay the receiver's
// fee once. Coins go to the platform (DM_FEE), not to the receiver.
export async function unlockConversation(req: AuthedRequest, res: Response) {
  try {
    const me = req.userId;
    if (!me) return res.status(401).json({ message: 'Unauthorized' });
    const conversationId = toInt(req.params.conversationId);
    if (!conversationId) return res.status(400).json({ message: 'conversationId is required' });
    const out = await unlockConversationWithFee(me, conversationId);
    return res.json({ success: true, ...out });
  } catch (err) {
    if (err instanceof DmUnlockError) {
      return res.status(err.status).json({ success: false, code: err.code, message: err.message });
    }
    console.error('[messages.unlockConversation]', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
}
