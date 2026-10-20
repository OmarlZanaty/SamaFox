# Batch C4 — Mic seat lease (5 min), bounded reconnect + session recovery, room session monitoring
Spec items: 5, 47, 48. Read `docs/spec52/RULES.md`, then AUDIT.md sections 5, 47, 48 carefully
(socket.service.ts is the room-state authority: `roomSeats`, `holdForReconnect`,
`ROOM_DISCONNECT_GRACE_MS` default 12 h, `performLeaveRoom`, `releaseUserFromRooms`,
`roomStateSnapshot.ts`, `livekitPublishGuard.ts`; Flutter `room_controller_provider.dart`,
`socket_service.dart`, `livekit_voice_engine.dart`, `app_config.dart`).
Migration dir: `backend/prisma/migrations/20261020000050_seat_lease_sessions/`.
Production note: a pm2 reload snapshots and restores room state (<3 min old); keep that working.

## 5 — Seat lease
- Seat state per occupied seat gets: status `occupied|held`, `lastHeartbeat`, `leaseExpiresAt`
  (absolute), `sessionId` (server-generated per socket join). Include `status` and
  `leaseExpiresAt` in `room_seats_state` seat objects (additive fields).
- Client sends `seat_heartbeat {roomId}` every 12 s while in a room (also while retained/PiP and
  in background as long as the socket lives). Server renews only the caller's own seat:
  lastHeartbeat=now, leaseExpiresAt=now+300 s, status=occupied.
- Socket disconnect / no heartbeat (sweep every 15 s: lastHeartbeat older than 45 s) → status
  `held`, keep the user on the seat (others see him as "reconnecting", mic muted server-side and
  LiveKit publish permission revoked through the existing guard), leaseExpiresAt = lastHeartbeat +
  300 s. Return within the lease (join_room by the same user) → atomically reclaim the SAME seat,
  status occupied, mute state preserved, emit room_seats_state. Lease expired → release the seat
  (same code path as leave_seat), log reason `lease_expired`.
- Explicit `leave_room` / leave via the X "مغادرة" → release immediately (already). Kick/ban →
  immediate. App force-stop = socket drop → the 5-minute path.
- Set the disconnect grace for room membership to the same 300 s for seated users (listeners can
  keep the current behaviour or 300 s too — document the choice). Keep the snapshot/restore:
  restored seats come back as `held` with their original absolute leaseExpiresAt (not a fresh
  timer).
- Optional durable mirror table `room_seat_leases` (roomId, seatNumber, userId, sessionId, status,
  lastHeartbeat, leaseExpiresAt, updatedAt; unique roomId+seatNumber) written on change (throttled)
  — only if cheap; in-memory + snapshot stays the authority.

## 47 — Reconnect
- Flutter socket: bounded cycle of 5 attempts with exponential backoff (1,2,4,8,16 s, jitter),
  then show a banner "انقطع الاتصال" with "إعادة المحاولة" (a new cycle); also start a new cycle
  automatically on connectivity regained / app resumed. Remove the unconditional infinite forced
  restart that bypasses the limit (`reconnect_failed` handler) — replace with the cycle logic.
  `app_config.dart socketReconnectionAttempts` → 5.
- On reconnect: rejoin room (existing cached admission/PIN), server reclaims the held seat (5),
  client resyncs `room_seats_state`, and the voice engine resumes: if the seat is mine and not
  muted → ensure publishing (existing LiveKit recovery); if the lease expired → listener only,
  never resurrect the mic. Reconnect count and last disconnect reason are sent with join_room
  (`reconnectCount`, `lastDisconnectReason`).

## 48 — Room session monitoring
- `RoomSession` table (`room_sessions`): id (sessionId), userId, roomId, joinedAt, lastHeartbeat,
  wsState ('connected'|'disconnected'), voiceState (client-reported: 'listening'|'publishing'|
  'muted'|'reconnecting'|'failed'), seatNumber?, lastApi (method+path, from a tiny express
  middleware that remembers the last API per user in memory and flushes on heartbeat),
  disconnectReason?, reconnectCount, leftAt?, leaveReason ('leave'|'kick'|'ban'|'lease_expired'|
  'room_closed'|'switch_room'|'server_restart'). Writes throttled (heartbeat updates at most every
  60 s per session; state changes immediately). Retention: delete rows older than 30 days in the
  existing scheduled cleanup.
- Client sends voice state changes with the heartbeat payload (`voiceState`).
- Admin: extend `client-health.html` or add a "جلسات الغرف" table (filter by user/room/date)
  in the dashboard via `spec52-admin.js`; read-only, admin only.

Tests: unit tests for lease transitions (occupied→held→reclaimed, held→expired, leave→immediate)
with fake timers, in the existing `services/__tests__` style.
Notes file: `docs/spec52/notes-C4.md`.
