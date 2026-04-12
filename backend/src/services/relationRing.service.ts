import { prisma } from '../lib/prisma';
import { createNotification } from './notification.service';
import { io } from '../index';

const RELATION_RING_IMAGE_URL = '/uploads/gifts/relation-ring.png';

export const RELATION_RING = {
  name: 'Relation Ring',
  nameAr: 'خاتم العلاقة',
  category: 'RELATION_RING',
  coinsValue: 20000,
  sortOrder: 999,
};

export const ensureRelationRingGift = async () => {
  const existing = await prisma.gift.findFirst({
    where: {
      OR: [
        { category: RELATION_RING.category },
        { name: RELATION_RING.name },
        { nameAr: RELATION_RING.nameAr },
      ],
    },
  });

  if (existing) {
    if (!existing.isActive || existing.coinsValue !== RELATION_RING.coinsValue) {
      await prisma.gift.update({
        where: { id: existing.id },
        data: {
          isActive: true,
          coinsValue: RELATION_RING.coinsValue,
          priceCoins: RELATION_RING.coinsValue,
          category: RELATION_RING.category,
        },
      });
    }
    return existing.id;
  }

  const created = await prisma.gift.create({
    data: {
      name: RELATION_RING.name,
      nameAr: RELATION_RING.nameAr,
      imageUrl: RELATION_RING_IMAGE_URL,
      animationUrl: null,
      category: RELATION_RING.category,
      coinsValue: RELATION_RING.coinsValue,
      priceCoins: RELATION_RING.coinsValue,
      sortOrder: RELATION_RING.sortOrder,
      isActive: true,
    },
  });

  return created.id;
};

export const maybeCreateRelationRequestFromRing = async ({
  senderId,
  receiverId,
  giftId,
}: {
  senderId: number;
  receiverId: number;
  giftId: number;
}) => {
  if (!receiverId || senderId === receiverId) return;

  const relationRingGift = await prisma.gift.findUnique({ where: { id: giftId } });
  if (!relationRingGift || relationRingGift.category !== RELATION_RING.category) return;

  const [sender, receiver] = await Promise.all([
    prisma.user.findUnique({ where: { id: senderId }, select: { id: true, name: true, avatarUrl: true, displayId: true, relationId: true } }),
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
