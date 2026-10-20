export const SEAT_LEASE_MS = 300_000;
export const SEAT_STALE_MS = 45_000;
export interface SeatLease {
  userId: number;
  sessionId: string;
  status: 'occupied' | 'held';
  lastHeartbeat: number;
  leaseExpiresAt: number;
}

/** Seat ownership remains in the room map; this metadata has the same lifetime. */
export class LeasedSeats extends Map<number, number> {
  readonly leases = new Map<number, SeatLease>();
  constructor(private session: (uid: number) => string, private changed: (uid: number, seat: number | null) => void = () => {}) {
    super();
  }
  override set(seat: number, uid: number): this {
    if (this.get(seat) !== uid) {
      this.leases.set(seat, {
        userId: uid, sessionId: this.session(uid), status: 'occupied',
        lastHeartbeat: Date.now(), leaseExpiresAt: Date.now() + SEAT_LEASE_MS,
      });
    }
    super.set(seat, uid);
    this.changed(uid, seat);
    return this;
  }
  override delete(seat: number): boolean {
    const uid = this.get(seat);
    this.leases.delete(seat);
    const removed = super.delete(seat);
    if (removed && uid != null) this.changed(uid, null);
    return removed;
  }
  override clear(): void {
    for (const seat of this.keys()) this.delete(seat);
  }
  renew(uid: number, sessionId: string, now = Date.now()): boolean {
    for (const lease of this.leases.values()) {
      if (lease.userId !== uid || lease.leaseExpiresAt <= now) continue;
      lease.sessionId = sessionId;
      lease.status = 'occupied';
      lease.lastHeartbeat = now;
      lease.leaseExpiresAt = now + SEAT_LEASE_MS;
      return true;
    }
    return false;
  }
  hold(uid: number): boolean {
    const lease = [...this.leases.values()].find(l => l.userId === uid);
    if (!lease || lease.status === 'held') return false;
    lease.status = 'held';
    lease.leaseExpiresAt = lease.lastHeartbeat + SEAT_LEASE_MS;
    return true;
  }
}
