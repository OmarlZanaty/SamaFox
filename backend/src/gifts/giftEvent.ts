import { nameColorSync } from '../services/vipStyle.service';

/** One additive wire contract, frozen with the financial transaction. */
export async function buildGiftEvent(tx: any, gift: any, ctx: any) {
  const users = await tx.user.findMany({
    where: { id: { in: [ctx.senderId, ctx.recipientId] } },
    select: { id: true, name: true, avatarUrl: true, vipLevel: true },
  });
  const user = (id: number) => {
    const u = users.find((u: any) => u.id === id);
    return u ? { ...u, nameColor: nameColorSync(u.vipLevel) } : null;
  };
  const giftType = gift.format === 'VIDEO' ? 'video'
    : gift.animationHtml ? 'svg' : 'image';
  const createdAt = new Date(ctx.createdAt ?? Date.now()).toISOString();
  return {
    ...ctx,
    gift,
    sender: user(ctx.senderId),
    recipient: user(ctx.recipientId),
    receiver: user(ctx.recipientId),
    giftId: gift.id,
    giftType,
    receiverId: ctx.recipientId,
    roomId: ctx.roomId ?? null,
    seatId: ctx.seatNumber ?? null,
    animationUrl: gift.animationUrl ?? null,
    soundUrl: giftType === 'image' || gift.hasSound === false ? null : gift.soundUrl ?? null,
    durationMs: gift.animationMs,
    effectType: gift.effectType ?? 'flight',
    cpActivate: ctx.cpActivate === true,
    cpXp: Math.max(0, Math.floor(ctx.cpXp ?? 0)),
    targetType: ctx.targetType ?? 'user',
    createdAt,
    ts: Date.parse(createdAt),
    eventVersion: 2,
  };
}
