import { randomUUID } from 'crypto';
import prisma from '../utils/prisma';

export type LeaveReason = 'leave' | 'kick' | 'ban' | 'lease_expired' | 'room_closed' | 'switch_room' | 'server_restart';
const voiceStates = new Set(['listening', 'publishing', 'muted', 'reconnecting', 'failed']);
type Session = {
  id: string; userId: number; roomId: number; socketId: string;
  joinedAt: Date; lastHeartbeat: Date; wsState: string; voiceState: string;
  seatNumber: number | null; lastApi: string | null; disconnectReason: string | null;
  reconnectCount: number; leftAt: Date | null; leaveReason: LeaveReason | null;
  flushedAt: number;
};
const active = new Map<number, Session>();
const lastApis = new Map<number, string>();
const writes = new Map<string, Promise<unknown>>();
export function rememberRoomApi(uid: number, api: string) {
  if (lastApis.size >= 10_000) lastApis.clear();
  lastApis.set(uid, api.slice(0, 250));
}
function flush(s: Session) {
  s.flushedAt = Date.now();
  const { socketId, flushedAt, ...data } = s;
  const write = (writes.get(s.id) ?? Promise.resolve()).then(() =>
    prisma.roomSession.upsert({ where: { id: s.id }, create: data, update: data }),
  ).catch(e => console.warn('[room session]', (e as Error).message));
  writes.set(s.id, write);
  void write.finally(() => { if (writes.get(s.id) === write) writes.delete(s.id); });
}
export function sessionFor(uid: number) { return active.get(uid); }
export function endRoomSession(uid: number, reason: LeaveReason) {
  const s = active.get(uid);
  if (!s) return;
  s.leftAt = new Date(); s.leaveReason = reason; s.wsState = 'disconnected';
  flush(s); active.delete(uid); lastApis.delete(uid);
}
export function joinRoomSession(uid: number, rid: number, socketId: string, count: unknown, reason: unknown) {
  const old = active.get(uid);
  if (old?.roomId === rid && old.socketId === socketId) return old;
  const reconnectCount = Math.max(old?.reconnectCount ?? 0, Math.min(1_000_000, Math.max(0, Math.floor(Number(count) || 0))));
  if (old) endRoomSession(uid, old.roomId === rid ? 'leave' : 'switch_room');
  const now = new Date();
  const s: Session = {
    id: randomUUID(), userId: uid, roomId: rid, socketId, joinedAt: now, lastHeartbeat: now,
    wsState: 'connected', voiceState: 'listening', seatNumber: null,
    lastApi: lastApis.get(uid) ?? null,
    disconnectReason: typeof reason === 'string' ? reason.slice(0, 200) : null,
    reconnectCount, leftAt: null, leaveReason: null, flushedAt: 0,
  };
  active.set(uid, s); flush(s); return s;
}
export function sessionSeat(uid: number, seatNumber: number | null) {
  const s = active.get(uid);
  if (!s || s.seatNumber === seatNumber) return;
  s.seatNumber = seatNumber; flush(s);
}
export function sessionDisconnected(uid: number, socketId: string, reason: string) {
  const s = active.get(uid);
  if (!s || s.socketId !== socketId) return false;
  s.wsState = 'disconnected'; s.disconnectReason = reason.slice(0, 200);
  s.voiceState = 'reconnecting'; flush(s); return true;
}
export function sessionHeartbeat(uid: number, socketId: string, voiceState: unknown) {
  const s = active.get(uid);
  if (!s || s.socketId !== socketId) return;
  const voice = typeof voiceState === 'string' && voiceStates.has(voiceState) ? voiceState : s.voiceState;
  const changed = voice !== s.voiceState || s.wsState !== 'connected';
  s.voiceState = voice; s.wsState = 'connected'; s.lastHeartbeat = new Date();
  s.lastApi = lastApis.get(uid) ?? s.lastApi;
  if (changed || Date.now() - s.flushedAt >= 60_000) flush(s);
}
/** Await before admitting new sessions, so the restart reconciliation cannot close them. */
export async function reconcileRoomSessions() {
  await prisma.roomSession.updateMany({
    where: { leftAt: null },
    data: { leftAt: new Date(), leaveReason: 'server_restart', wsState: 'disconnected' },
  });
}
