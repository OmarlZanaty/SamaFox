/**
 * Random PK — rooms that opted in wait here until another opted-in room shows
 * up; the two are then paired (client @383: «انا بفعل pk عشوائي … وهقابل ناس
 * بتفعل عشوائي بردوا … وندخل pk مع بعض … وكل واحد في غرفته»).
 *
 * In memory: the API runs as one process, like the socket maps. A waiting
 * entry lapses after [RANDOM_PK_WAIT_MS]; the app re-joins if still searching.
 */
export const RANDOM_PK_WAIT_MS = 120_000;

export interface RandomPkEntry {
  roomId: number;
  userId: number;
  durationSec: number;
  /** Player the initiator picked for this PK (null = room owner). */
  sideUserId?: number | null;
  at: number;
}

export class PkMatchQueue {
  private readonly waiting = new Map<number, RandomPkEntry>();

  constructor(private readonly now: () => number = Date.now) {}

  private prune() {
    const cutoff = this.now() - RANDOM_PK_WAIT_MS;
    for (const [roomId, e] of this.waiting) if (e.at < cutoff) this.waiting.delete(roomId);
  }

  /**
   * Pairs [entry] with the longest-waiting other room (skipping rooms that
   * [busy] reports as already in a PK), removing it from the queue. With no
   * partner the entry waits (replacing an earlier entry of the same room) and
   * null is returned.
   */
  take(entry: Omit<RandomPkEntry, 'at'>, busy: (roomId: number) => boolean = () => false): RandomPkEntry | null {
    this.prune();
    this.waiting.delete(entry.roomId);
    for (const [roomId, other] of this.waiting) {
      if (busy(roomId)) {
        this.waiting.delete(roomId);
        continue;
      }
      this.waiting.delete(roomId);
      return other;
    }
    this.waiting.set(entry.roomId, { ...entry, at: this.now() });
    return null;
  }

  /** Puts a partner back at the head after a failed pairing. */
  restore(entry: RandomPkEntry) {
    this.waiting.set(entry.roomId, entry);
  }

  cancel(roomId: number): boolean {
    return this.waiting.delete(roomId);
  }

  isWaiting(roomId: number): boolean {
    this.prune();
    return this.waiting.has(roomId);
  }
}
