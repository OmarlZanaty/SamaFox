import { RoomServiceClient, TrackType } from 'livekit-server-sdk';
import type { ParticipantInfo } from 'livekit-server-sdk';

/**
 * Only a seated user may be heard in a LiveKit room.
 *
 * The voice token grants canPublish to everyone in the room and the app decides
 * when to publish — while it holds a seat. That trusted the phone's own idea of
 * its seat, and on 16/10 a user whose phone still believed it was on a mic
 * talked into room 100000 with no seat on anyone's screen ("في حد على المايك
 * مش ظاهر، بيتكلم بس مش ظاهر"). The seat map on this server is the truth, so
 * the server now enforces it on the SFU itself:
 *
 *   - a participant publishing audio without a seat loses canPublish (LiveKit
 *     unpublishes the track and refuses a new one);
 *   - a seated participant who had lost it gets it back before the room is
 *     told about the seat, so the phone's goLive() succeeds.
 *
 * Listeners who publish nothing are never touched. Runs on every seat change
 * and on a sweep, which also catches a phone that rejoins with a fresh token.
 */

export interface LiveKitRoomApi {
  listRooms(): Promise<Array<{ name: string }>>;
  listParticipants(room: string): Promise<ParticipantInfo[]>;
  updateParticipant(
    room: string,
    identity: string,
    options: { permission: { canPublish: boolean; canSubscribe: boolean; canPublishData: boolean } },
  ): Promise<unknown>;
}

export interface PublishGuardDeps {
  api: LiveKitRoomApi | null;
  /** Read at run time, never at schedule time: the latest seat state wins. */
  seatedUserIds(rid: number): Set<number>;
  isLiveKitRoom(rid: number): boolean;
  log?: (msg: string, extra?: unknown) => void;
}

const ROOM_PREFIX = 'room-';

/** Same grants as the voice token, except canPublish. */
function permission(canPublish: boolean) {
  return { canPublish, canSubscribe: true, canPublishData: false };
}

function publishesAudio(p: ParticipantInfo): boolean {
  return (p.tracks ?? []).some((t) => t.type === TrackType.AUDIO);
}

export function createPublishGuard(deps: PublishGuardDeps) {
  const log = deps.log ?? ((msg, extra) => console.log(msg, extra ?? ''));
  // One sync per room at a time, so a grant and a stale revoke never cross.
  const chains = new Map<number, Promise<void>>();

  async function syncNow(rid: number): Promise<void> {
    const api = deps.api;
    if (!api || !deps.isLiveKitRoom(rid)) return;
    const room = `${ROOM_PREFIX}${rid}`;
    let participants: ParticipantInfo[];
    try {
      participants = await api.listParticipants(room);
    } catch {
      return; // no such LiveKit room (nobody in voice) — nothing to enforce
    }
    const seated = deps.seatedUserIds(rid);
    for (const p of participants) {
      const uid = Number(p.identity);
      if (!Number.isInteger(uid) || uid <= 0) continue;
      const onSeat = seated.has(uid);
      const canPublish = p.permission?.canPublish !== false;
      let next: boolean | null = null;
      if (!onSeat && canPublish && publishesAudio(p)) next = false;
      else if (onSeat && !canPublish) next = true;
      if (next === null) continue;
      try {
        await api.updateParticipant(room, p.identity, { permission: permission(next) });
        log(next ? '[lk guard] publish restored' : '[lk guard] unseated speaker silenced', { rid, uid });
      } catch (e) {
        log('[lk guard] update failed', { rid, uid, error: (e as Error).message });
      }
    }
  }

  /** Bring one room's LiveKit permissions in line with its seats. */
  function sync(rid: number): Promise<void> {
    const prev = chains.get(rid) ?? Promise.resolve();
    const run = prev.then(() => syncNow(rid)).catch(() => {});
    chains.set(rid, run);
    void run.finally(() => {
      if (chains.get(rid) === run) chains.delete(rid);
    });
    return run;
  }

  /**
   * [sync], but never holds a seat claim up longer than [ms]: a slow SFU must
   * not stop people sitting down.
   */
  function syncWithin(rid: number, ms = 1500): Promise<void> {
    return Promise.race([sync(rid), new Promise<void>((r) => setTimeout(r, ms).unref?.())]);
  }

  /** Every LiveKit room that currently exists. */
  async function sweep(): Promise<void> {
    const api = deps.api;
    if (!api) return;
    let rooms: Array<{ name: string }>;
    try {
      rooms = await api.listRooms();
    } catch (e) {
      log('[lk guard] listRooms failed', (e as Error).message);
      return;
    }
    for (const r of rooms) {
      if (!r.name.startsWith(ROOM_PREFIX)) continue;
      const rid = Number(r.name.slice(ROOM_PREFIX.length));
      if (Number.isInteger(rid) && rid > 0) await sync(rid);
    }
  }

  return { sync, syncWithin, sweep };
}

/**
 * The SFU's admin API. LiveKit runs on the same box as the API (port 7880);
 * LIVEKIT_API_URL overrides it. Null when the keys are not configured.
 */
export function liveKitRoomApiFromEnv(): LiveKitRoomApi | null {
  const key = (process.env.LIVEKIT_API_KEY ?? '').trim();
  const secret = (process.env.LIVEKIT_API_SECRET ?? '').trim();
  if (!key || !secret) return null;
  const url = (process.env.LIVEKIT_API_URL ?? 'http://127.0.0.1:7880').trim();
  return new RoomServiceClient(url, key, secret);
}
