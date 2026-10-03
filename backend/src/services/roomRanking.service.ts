import prisma from '../utils/prisma';
import { getLiveRoomCounts } from './socket.service';

const db = prisma as any;

/**
 * ترتيب الغرف (2026-09-27). The client:
 *   "احدد ID معين غرفته تتصدر اول غرفه وغيره تاني غرفه وهكذا — بعد كده الغرفه
 *    اللي فيها ناس اكتر تكون بعد اللي انا حددته"
 *
 * Order of the room list:
 *   1. غرفة الإدارة (FEATURED_ROOM_ID) — the big card, as before;
 *   2. the rooms the dashboard pinned, in the order it gave;
 *   3. everything else by how many people are in it RIGHT NOW;
 *   4. ties (mostly empty rooms) newest first, as the list used to be.
 *
 * A pin is the ID people see: the owner's displayId (the room screen shows it
 * as "ID"). A number that is no user's displayId is read as a room id, so an
 * admin who types either gets what he meant.
 */
export const ROOM_PIN_KEY = 'room_pin_order';
export const MAX_ROOM_PINS = 50;

let pinCache: { at: number; ids: number[] } | null = null;
const PIN_TTL_MS = 30_000;

export function parsePins(raw: unknown): number[] {
  let arr: unknown = raw;
  if (typeof raw === 'string') {
    try {
      arr = JSON.parse(raw);
    } catch {
      return [];
    }
  }
  if (!Array.isArray(arr)) return [];
  const seen = new Set<number>();
  const out: number[] = [];
  for (const v of arr) {
    const n = Math.floor(Number(v));
    if (!Number.isFinite(n) || n <= 0 || seen.has(n)) continue;
    seen.add(n);
    out.push(n);
  }
  return out.slice(0, MAX_ROOM_PINS);
}

export async function getRoomPins(): Promise<number[]> {
  if (pinCache && Date.now() - pinCache.at < PIN_TTL_MS) return pinCache.ids;
  const row = await db.appSetting.findUnique({ where: { key: ROOM_PIN_KEY } });
  const ids = parsePins(row?.value ?? '[]');
  pinCache = { at: Date.now(), ids };
  return ids;
}

export function invalidateRoomPins() {
  pinCache = null;
}

type Row = { id: number; ownerId: number; createdAt: Date; owner: { displayId: number | null } | null };

/**
 * Resolve each pin to one room among [rows]: the owner's newest room for a
 * displayId, else the room with that id. Returns roomId -> rank (0-based).
 */
export function resolvePinRanks(pins: number[], rows: Row[]): Map<number, number> {
  const byDisplay = new Map<number, Row>();
  const byId = new Map<number, Row>();
  for (const r of rows) {
    byId.set(r.id, r);
    const d = r.owner?.displayId;
    if (d == null) continue;
    const cur = byDisplay.get(d);
    if (!cur || r.createdAt > cur.createdAt) byDisplay.set(d, r);
  }
  const ranks = new Map<number, number>();
  pins.forEach((pin, i) => {
    const room = byDisplay.get(pin) ?? byId.get(pin);
    if (room && !ranks.has(room.id)) ranks.set(room.id, i);
  });
  return ranks;
}

/** Pure ordering, so it can be tested without a database or sockets. */
export function orderRooms(
  rows: Row[],
  opts: { featuredId: number; pinRanks: Map<number, number>; live: Map<number, number> },
): number[] {
  const bucket = (r: Row) => (r.id === opts.featuredId ? 0 : opts.pinRanks.has(r.id) ? 1 : 2);
  return [...rows]
    .sort((a, b) => {
      const ba = bucket(a);
      const bb = bucket(b);
      if (ba !== bb) return ba - bb;
      if (ba === 1) return opts.pinRanks.get(a.id)! - opts.pinRanks.get(b.id)!;
      const la = opts.live.get(a.id) ?? 0;
      const lb = opts.live.get(b.id) ?? 0;
      if (la !== lb) return lb - la;
      return b.createdAt.getTime() - a.createdAt.getTime() || b.id - a.id;
    })
    .map((r) => r.id);
}

/** Every room matching [where], in list order, plus the live counts used. */
export async function rankedRoomIds(where: any, featuredId: number) {
  const rows: Row[] = await db.room.findMany({
    where,
    select: { id: true, ownerId: true, createdAt: true, owner: { select: { displayId: true } } },
  });
  const pins = await getRoomPins();
  const pinRanks = resolvePinRanks(pins, rows);
  const live = getLiveRoomCounts();
  return { ids: orderRooms(rows, { featuredId, pinRanks, live }), live, pinRanks };
}
