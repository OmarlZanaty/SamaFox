import prisma from './prisma';

/**
 * C6 — a user's equipped chat-bubble design.
 *
 * The room chat looked this up inline and the private messages did not look it
 * up at all, so a bubble the user had bought showed inside a room and vanished
 * in the DMs — the client's *"الفقاعه شغاله في الغرفه لكن مش موجوده في الرسائل
 * الخاصه"*. One helper, used by both, is what stops the two surfaces drifting
 * apart again.
 *
 * `meta` carries the dashboard's inner-box and 9-slice guides, which is how the
 * text ends up inside the empty middle of the artwork instead of over its
 * decoration.
 *
 * Expiry is handled by the `expiresAt` filter rather than by a sweeper: a
 * bubble whose term has run out must stop rendering in BOTH places at the same
 * moment ("تختفي من الاتنين لما مدتها تخلص").
 */
export interface ChatBubble {
  bubbleUrl: string | null;
  bubbleMeta: unknown | null;
}

const NONE: ChatBubble = { bubbleUrl: null, bubbleMeta: null };

export async function getChatBubble(userId: number): Promise<ChatBubble> {
  if (!userId) return NONE;
  try {
    const active = await (prisma as any).userItem.findFirst({
      where: {
        userId,
        isActive: true,
        item: { type: 'CHAT_BUBBLE' },
        OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
      },
      include: { item: { select: { assetUrl: true, meta: true } } },
    });
    return {
      bubbleUrl: active?.item?.assetUrl ?? null,
      bubbleMeta: active?.item?.meta ?? null,
    };
  } catch (e) {
    // Decoration only — a lookup failure must never stop a message being sent.
    console.warn('[chatBubble] lookup failed:', (e as Error).message);
    return NONE;
  }
}

/** Bubbles for several senders at once, for a page of messages. */
export async function getChatBubbles(
  userIds: number[],
): Promise<Map<number, ChatBubble>> {
  const ids = [...new Set(userIds.filter((n) => Number.isFinite(n) && n > 0))];
  const out = new Map<number, ChatBubble>();
  if (ids.length === 0) return out;

  try {
    const rows = await (prisma as any).userItem.findMany({
      where: {
        userId: { in: ids },
        isActive: true,
        item: { type: 'CHAT_BUBBLE' },
        OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
      },
      include: { item: { select: { assetUrl: true, meta: true } } },
    });
    for (const r of rows) {
      out.set(r.userId, {
        bubbleUrl: r.item?.assetUrl ?? null,
        bubbleMeta: r.item?.meta ?? null,
      });
    }
  } catch (e) {
    console.warn('[chatBubble] batch lookup failed:', (e as Error).message);
  }
  return out;
}
