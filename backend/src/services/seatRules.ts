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

/** Should a heartbeat-carried mic state overwrite the server's? Only on a real change. */
export function shouldReconcileMute(i: {
  micMuted: unknown;
  seated: boolean;
  adminMuted: boolean;
  forceMuted: boolean;
  current: boolean | undefined;
}): boolean {
  if (typeof i.micMuted !== 'boolean') return false;
  if (!i.seated || i.adminMuted || i.forceMuted) return false;
  return (i.current ?? true) !== i.micMuted;
}
