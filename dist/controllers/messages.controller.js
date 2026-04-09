"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getConversations = getConversations;
exports.getOrCreateConversation = getOrCreateConversation;
exports.getMessages = getMessages;
exports.sendMessage = sendMessage;
exports.markConversationRead = markConversationRead;
const prisma_1 = __importDefault(require("../utils/prisma"));
function toInt(v) {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : null;
}
async function getConversations(req, res) {
    const me = req.userId;
    if (!me)
        return res.status(401).json({ message: 'Unauthorized' });
    const convs = await prisma_1.default.conversation.findMany({
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
        return {
            id: c.id,
            partnerId: partner.id,
            partnerName: partner.name,
            partnerAvatar: partner.avatarUrl,
            lastMessage: c.lastMessage?.text ?? null,
            lastMessageTime: c.lastMessage?.createdAt?.toISOString?.() ?? c.lastMessageAt?.toISOString?.() ?? null,
            unreadCount: 0,
            muted: myPart?.muted ?? false,
        };
    });
    return res.json(out);
}
async function getOrCreateConversation(req, res) {
    const me = req.userId;
    if (!me)
        return res.status(401).json({ message: 'Unauthorized' });
    const partnerId = toInt(req.body?.partnerId ?? req.params?.partnerId);
    if (!partnerId)
        return res.status(400).json({ message: 'partnerId is required' });
    if (partnerId === me)
        return res.status(400).json({ message: 'Cannot message yourself' });
    const userAId = Math.min(me, partnerId);
    const userBId = Math.max(me, partnerId);
    const conv = await prisma_1.default.conversation.upsert({
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
}
async function getMessages(req, res) {
    const me = req.userId;
    if (!me)
        return res.status(401).json({ message: 'Unauthorized' });
    const conversationId = toInt(req.params.conversationId ?? req.query.conversationId);
    if (!conversationId)
        return res.status(400).json({ message: 'conversationId is required' });
    const limit = Math.min(50, Math.max(1, Number(req.query.limit ?? 30)));
    const beforeId = toInt(req.query.beforeId);
    const part = await prisma_1.default.conversationParticipant.findUnique({
        where: { conversationId_userId: { conversationId, userId: me } },
        select: { id: true },
    });
    if (!part)
        return res.status(403).json({ message: 'Not a participant' });
    const msgs = await prisma_1.default.directMessage.findMany({
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
    return res.json(msgs.reverse().map((m) => ({
        id: m.id,
        conversationId: m.conversationId,
        senderId: m.senderId,
        text: m.text,
        imageUrl: m.imageUrl,
        type: m.type,
        audioUrl: m.audioUrl ?? null,
        createdAt: m.createdAt.toISOString(),
        sender: m.sender,
    })));
}
async function sendMessage(req, res) {
    const me = req.userId;
    if (!me)
        return res.status(401).json({ message: 'Unauthorized' });
    const conversationId = toInt(req.body?.conversationId);
    const text = (req.body?.text ?? '').toString().trim();
    const imageUrl = req.body?.imageUrl ? req.body.imageUrl.toString() : null;
    const audioUrl = req.body?.audioUrl ? req.body.audioUrl.toString() : null;
    let type = (req.body?.type ?? '').toString().trim().toLowerCase();
    if (!type) {
        type = audioUrl ? 'voice' : imageUrl ? 'image' : 'text';
    }
    if (type === 'audio')
        type = 'voice';
    if (!conversationId)
        return res.status(400).json({ message: 'conversationId is required' });
    if (!text && !imageUrl && !audioUrl) {
        return res.status(400).json({ message: 'text, imageUrl, or audioUrl is required' });
    }
    const part = await prisma_1.default.conversationParticipant.findUnique({
        where: { conversationId_userId: { conversationId, userId: me } },
        select: { id: true },
    });
    if (!part)
        return res.status(403).json({ message: 'Not a participant' });
    const created = await prisma_1.default.$transaction(async (tx) => {
        const data = {
            conversationId,
            senderId: me,
            text: text || null,
            imageUrl: type === 'image' ? imageUrl : null,
            type,
        };
        if (type === 'voice') {
            data.audioUrl = audioUrl || null;
        }
        const msg = await tx.directMessage.create({ data });
        await tx.conversation.update({
            where: { id: conversationId },
            data: {
                lastMessageId: msg.id,
                lastMessageAt: msg.createdAt,
            },
        });
        const full = await tx.directMessage.findUnique({
            where: { id: msg.id },
            include: {
                sender: { select: { id: true, name: true, avatarUrl: true } },
            },
        });
        return full;
    });
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
    return res.json({
        id: created.id,
        conversationId: created.conversationId,
        senderId: created.senderId,
        text: created.text,
        imageUrl: created.imageUrl,
        audioUrl: created.audioUrl ?? null,
        type: created.type,
        createdAt: created.createdAt.toISOString(),
        sender: created.sender,
    });
}
async function markConversationRead(req, res) {
    const me = req.userId;
    if (!me)
        return res.status(401).json({ message: 'Unauthorized' });
    const conversationId = toInt(req.body?.conversationId ?? req.params?.conversationId);
    if (!conversationId)
        return res.status(400).json({ message: 'conversationId is required' });
    await prisma_1.default.conversationParticipant.update({
        where: { conversationId_userId: { conversationId, userId: me } },
        data: { lastReadAt: new Date() },
    });
    return res.json({ ok: true });
}
//# sourceMappingURL=messages.controller.js.map