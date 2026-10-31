// Client 31/10 — «نظام ايموجي من لوحة التحكم ... زي الهدايا» plus private
// lists: one that opens only for VIP, one that opens only for the IDs he sets.
import prisma from '../utils/prisma';

export interface EmojiListRow {
  id: number;
  nameAr: string;
  imageUrl: string | null;
  sortOrder: number;
  isActive: boolean;
  minVip: number;
  userIds: number[];
  emojis: { id: number; name: string; imageUrl: string; sortOrder: number; isActive: boolean }[];
}

/** A list with no VIP floor and no user list is public; otherwise either the
 *  VIP floor or being on the list opens it. */
export function canUseEmojiList(list: Pick<EmojiListRow, 'isActive' | 'minVip' | 'userIds'>, userId: number, vip: number): boolean {
  if (!list.isActive) return false;
  const ids = list.userIds ?? [];
  if (list.minVip <= 0 && ids.length === 0) return true;
  return (list.minVip > 0 && vip >= list.minVip) || ids.includes(userId);
}

let cache: { at: number; lists: EmojiListRow[] } | null = null;
const CACHE_MS = 30_000;

export function invalidateEmojiLists() {
  cache = null;
}

async function allLists(): Promise<EmojiListRow[]> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.lists;
  const lists = (await prisma.emojiList.findMany({
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    include: { emojis: { orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] } },
  })) as EmojiListRow[];
  cache = { at: Date.now(), lists };
  return lists;
}

async function userVip(userId: number): Promise<number> {
  const u = await prisma.user.findUnique({ where: { id: userId }, select: { vipLevel: true, vipExpiresAt: true } });
  if (!u) return 0;
  return !u.vipExpiresAt || u.vipExpiresAt.getTime() > Date.now() ? u.vipLevel ?? 0 : 0;
}

/** The lists this user may open, each with its active emoji only. */
export async function emojiListsFor(userId: number) {
  const [lists, vip] = await Promise.all([allLists(), userVip(userId)]);
  return lists
    .filter((l) => canUseEmojiList(l, userId, vip))
    .map((l) => ({
      id: l.id,
      nameAr: l.nameAr,
      imageUrl: l.imageUrl,
      emojis: l.emojis.filter((e) => e.isActive).map((e) => ({ id: e.id, name: e.name, imageUrl: e.imageUrl })),
    }))
    .filter((l) => l.emojis.length > 0);
}

/** The emoji to broadcast for `c:<itemId>`, or null when this user may not
 *  send it (unknown, hidden, or in a list that is closed to him). */
export async function customEmojiForSend(userId: number, itemId: number): Promise<{ id: number; imageUrl: string; name: string } | null> {
  const lists = await allLists();
  for (const l of lists) {
    const e = l.emojis.find((x) => x.id === itemId);
    if (!e) continue;
    if (!e.isActive || !canUseEmojiList(l, userId, await userVip(userId))) return null;
    return { id: e.id, imageUrl: e.imageUrl, name: e.name };
  }
  return null;
}
