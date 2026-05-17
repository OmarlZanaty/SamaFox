import { prisma } from '../lib/prisma';
import { createNotification } from './notification.service';
import { io } from '../index';

// NOTE: After Gift System unification (V2 -> V1 rename), the Gift model uses
// String cuid IDs and a different field shape (coinCost / iconUrl / format).
// The "relation ring" is now identified by category === 'RELATION_RING' in
// the unified Gift catalog. The previous ensureRelationRingGift bootstrap
// has been removed — admins seed/create the gift via /api/v1/admin/gifts.

export const RELATION_RING_CATEGORY = 'RELATION_RING';

/**
 * Optionally trigger a relation request when a RELATION_RING-category gift is
 * sent. Wire this into the gift send flow if relation rings should still
 * upgrade to active relationships automatically.
 */
export const maybeCreateRelationRequestFromRing = async ({
  senderId,
  receiverId,
  giftId,
}: {
  senderId: number;
  receiverId: number;
  giftId: string;
}) => {
  if (!receiverId || senderId === receiverId) return;

  const gift = await prisma.gift.findUnique({ where: { id: giftId } });
  if (!gift || gift.category !== RELATION_RING_CATEGORY) return;

  const [sender, receiver] = await Promise.all([
    prisma.user.findUnique({
      where: { id: senderId },
      select: { id: true, name: true, avatarUrl: true, displayId: true, relationId: true },
    }),
    prisma.user.findUnique({ where: { id: receiverId }, select: { id: true, relationId: true } }),
  ]);

  if (!sender || !receiver) return;
  if (sender.relationId || receiver.relationId) return;

  const existing = await prisma.relation.findFirst({
    where: {
      OR: [{ user1Id: senderId, user2Id: receiverId }, { user1Id: receiverId, user2Id: senderId }],
      status: { in: ['PENDING', 'ACTIVE'] },
    },
  });

  if (existing) return;

  const relation = await prisma.relation.create({
    data: {
      user1Id: senderId,
      user2Id: receiverId,
      status: 'PENDING',
    },
  });

  await createNotification({
    userId: receiverId,
    actorId: senderId,
    type: 'relation_request',
    title: 'Relationship request',
    body: `${sender.name} sent you a relation ring. Accept or refuse?`,
    data: {
      relationId: relation.id,
      giftId,
      fromUser: sender,
    },
  });

  io.to(`user:${receiverId}`).emit('relation_request', {
    relationId: relation.id,
    fromUser: sender,
    viaGiftId: giftId,
  });
};
