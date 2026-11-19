// Pure seat rules shared by the socket handlers (kept free of I/O so they can be unit tested).

/** [seat, uid] pairs sitting above the room's current mic count. */
export function seatsAboveMax(seats: Iterable<[number, number]>, maxSeats: number): Array<[number, number]> {
  return Array.from(seats).filter(([sn]) => sn > maxSeats);
}

export interface MoveCheckInput {
  seats: Map<number, number>;
  locked: Set<number>;
  uid: number;
  from: number;
  to: number;
  maxSeats: number;
}

/** Returns an Arabic rejection message, or null when the move is allowed. */
export function moveRejection(i: MoveCheckInput): string | null {
  if (!Number.isInteger(i.to) || i.to < 1 || i.to > i.maxSeats) return 'رقم المايك غير صالح';
  if (i.seats.get(i.from) !== i.uid) return 'هذا ليس مايكك';
  if (i.from === i.to) return 'أنت على هذا المايك بالفعل';
  if (i.locked.has(i.to)) return 'هذا المايك مقفول';
  if (i.seats.has(i.to)) return 'هذا المايك مشغول';
  return null;
}

/** Grace period after a server-side mute change during which the phone's report is ignored. */
export const MUTE_RECONCILE_GRACE_MS = 15_000;

/**
 * Should a heartbeat-carried mic state overwrite the server's? Only on a real
 * change. Muting (micMuted === true) is always safe, so it ignores admin/force
 * mutes and voiceState; unmuting needs a live phone (voiceState 'publishing'),
 * no admin/force mute, and no server-side change in the last 15 s.
 */
export function shouldReconcileMute(i: {
  micMuted: unknown;
  seated: boolean;
  adminMuted: boolean;
  forceMuted: boolean;
  current: boolean | undefined;
  voiceState?: unknown;
  msSinceServerChange?: number;
}): boolean {
  if (typeof i.micMuted !== 'boolean') return false;
  if (!i.seated) return false;
  if (i.msSinceServerChange != null && i.msSinceServerChange < MUTE_RECONCILE_GRACE_MS) return false;
  if ((i.current ?? true) === i.micMuted) return false;
  if (i.micMuted) return true;
  return !i.adminMuted && !i.forceMuted && i.voiceState === 'publishing';
}
