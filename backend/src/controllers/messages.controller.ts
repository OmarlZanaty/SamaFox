import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { createNotification } from '../services/notification.service';

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

    const out = convs.map((c) => {
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

    // return oldest->newest
    return res.json(msgs.reverse().map((m) => ({
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      text: m.text,
      imageUrl: m.imageUrl,
      type: m.type,
      audioUrl: (m as any).audioUrl ?? null,
      createdAt: m.createdAt.toISOString(),
      sender: m.sender,
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

  // ensure participant
  const part = await prisma.conversationParticipant.findUnique({
    where: { conversationId_userId: { conversationId, userId: me } },
    select: { id: true },
  });
  if (!part) return res.status(403).json({ message: 'Not a participant' });

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
