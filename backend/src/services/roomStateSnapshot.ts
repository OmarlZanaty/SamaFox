import fs from 'fs';
import path from 'path';

/**
 * Room state that survives a server restart (04/10).
 *
 * Seats, mute flags, locked seats and the mic queue live only in memory, so
 * every deploy (pm2 reload) emptied every room's mics at once. The complaint
 * that surfaced it: "في حساب اتعمله كتم مايك تلقائي" — on 03/10 at 19:34 a
 * deploy dropped user 100455 off his seat; he sat again and, like any new
 * seat, came up muted.
 *
 * The state is written to a file every few seconds and on SIGINT/SIGTERM, and
 * read back on boot if it is recent. Kept free of socket.io and Prisma so its
 * test does not boot the server.
 */

export const SNAPSHOT_VERSION = 1;
/** Older than this, the rooms have moved on: start empty as before. */
export const SNAPSHOT_MAX_AGE_MS = 3 * 60 * 1000;

export interface RoomSnapshot {
  rid: number;
  seats: [number, number][]; // [seatNumber, userId]
  muted: [number, boolean][]; // [userId, muted]
  locked: number[];
  adminMuted: number[];
  queue: number[];
}

export interface StateSnapshot {
  v: number;
  at: number;
  rooms: RoomSnapshot[];
  /** [userId, roomId, hidden] — who is inside which room. */
  users: [number, number, boolean][];
}

export interface RoomStateMaps {
  roomSeats: Map<number, Map<number, number>>;
  roomMuted: Map<number, Map<number, boolean>>;
  roomLockedSeats: Map<number, Set<number>>;
  roomAdminMutedSeats: Map<number, Set<number>>;
  roomMicQueue: Map<number, number[]>;
  userCurrentRoom: Map<number, number>;
  hiddenInRoom: Map<number, Set<number>>;
}

const posInt = (v: unknown): v is number => Number.isInteger(v) && (v as number) > 0;

export function buildSnapshot(m: RoomStateMaps, now = Date.now()): StateSnapshot {
  const rids = new Set<number>([
    ...m.roomSeats.keys(),
    ...m.roomLockedSeats.keys(),
    ...m.roomAdminMutedSeats.keys(),
    ...m.roomMicQueue.keys(),
  ]);
  const rooms: RoomSnapshot[] = [];
  for (const rid of rids) {
    const seats = Array.from(m.roomSeats.get(rid)?.entries() ?? []);
    const seated = new Set(seats.map(([, uid]) => uid));
    const room: RoomSnapshot = {
      rid,
      seats,
      // Only the people on a seat: a mute flag means nothing off the mic.
      muted: Array.from(m.roomMuted.get(rid)?.entries() ?? []).filter(([uid]) => seated.has(uid)),
      locked: Array.from(m.roomLockedSeats.get(rid) ?? []),
      adminMuted: Array.from(m.roomAdminMutedSeats.get(rid) ?? []),
      queue: [...(m.roomMicQueue.get(rid) ?? [])],
    };
    if (room.seats.length || room.locked.length || room.adminMuted.length || room.queue.length) {
      rooms.push(room);
    }
  }
  const users: [number, number, boolean][] = Array.from(m.userCurrentRoom.entries()).map(
    ([uid, rid]) => [uid, rid, m.hiddenInRoom.get(rid)?.has(uid) ?? false],
  );
  return { v: SNAPSHOT_VERSION, at: now, rooms, users };
}

/**
 * Put a snapshot back into the (empty, freshly booted) maps. Returns the
 * users restored into a room, or null when the snapshot is unusable or stale.
 * Malformed entries are skipped one by one; they never fail the boot.
 */
export function applySnapshot(
  raw: unknown,
  m: RoomStateMaps,
  now = Date.now(),
): { users: number[]; seats: number } | null {
  const s = raw as StateSnapshot;
  if (!s || s.v !== SNAPSHOT_VERSION || typeof s.at !== 'number') return null;
  if (now - s.at > SNAPSHOT_MAX_AGE_MS || s.at > now + 60_000) return null;

  const restoredUsers = new Set<number>();
  for (const u of Array.isArray(s.users) ? s.users : []) {
    const [uid, rid, hidden] = Array.isArray(u) ? u : [];
    if (!posInt(uid) || !posInt(rid)) continue;
    m.userCurrentRoom.set(uid, rid);
    if (hidden === true) {
      if (!m.hiddenInRoom.has(rid)) m.hiddenInRoom.set(rid, new Set());
      m.hiddenInRoom.get(rid)!.add(uid);
    }
    restoredUsers.add(uid);
  }

  let seatCount = 0;
  for (const r of Array.isArray(s.rooms) ? s.rooms : []) {
    if (!r || !posInt(r.rid)) continue;
    const seats = new Map<number, number>();
    const seatedUsers = new Set<number>();
    for (const e of Array.isArray(r.seats) ? r.seats : []) {
      const [sn, uid] = Array.isArray(e) ? e : [];
      if (!posInt(sn) || !posInt(uid) || seats.has(sn) || seatedUsers.has(uid)) continue;
      // A seat belongs to someone inside the room; never hold one for a user
      // the snapshot places elsewhere.
      if (m.userCurrentRoom.get(uid) !== r.rid) continue;
      seats.set(sn, uid);
      seatedUsers.add(uid);
    }
    if (seats.size) {
      m.roomSeats.set(r.rid, seats);
      seatCount += seats.size;
      const muted = new Map<number, boolean>();
      for (const e of Array.isArray(r.muted) ? r.muted : []) {
        const [uid, flag] = Array.isArray(e) ? e : [];
        if (posInt(uid) && seatedUsers.has(uid)) muted.set(uid, flag === true);
      }
      // Anyone seated without a flag starts muted, as a new seat does.
      for (const uid of seatedUsers) if (!muted.has(uid)) muted.set(uid, true);
      m.roomMuted.set(r.rid, muted);
    }
    const locked = (Array.isArray(r.locked) ? r.locked : []).filter(posInt);
    if (locked.length) m.roomLockedSeats.set(r.rid, new Set(locked));
    const adminMuted = (Array.isArray(r.adminMuted) ? r.adminMuted : []).filter(posInt);
    if (adminMuted.length) m.roomAdminMutedSeats.set(r.rid, new Set(adminMuted));
    const queue = (Array.isArray(r.queue) ? r.queue : []).filter(
      (uid) => posInt(uid) && m.userCurrentRoom.get(uid) === r.rid,
    );
    if (queue.length) m.roomMicQueue.set(r.rid, queue);
  }
  return { users: Array.from(restoredUsers), seats: seatCount };
}

export const SNAPSHOT_FILE = path.join(
  process.env.ROOM_STATE_SNAPSHOT_DIR ?? process.cwd(),
  'room-state.snapshot.json',
);

/** Synchronous on purpose: it also runs inside a signal handler. */
export function writeSnapshotFile(snapshot: StateSnapshot, file = SNAPSHOT_FILE): void {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(snapshot));
  fs.renameSync(tmp, file);
}

/** Read and remove the file, so a crash loop cannot replay it twice. */
export function takeSnapshotFile(file = SNAPSHOT_FILE): unknown {
  let text: string;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return null;
  }
  try {
    fs.renameSync(file, `${file}.used`);
  } catch {
    /* read-only is fine: the age check still retires it */
  }
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
