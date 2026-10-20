# Batch C6 — Gift engine: unified gift event, idempotent transactions, all-mics targeting, reliable video gifts
Spec items: 45, 46, 16, 24 (+ 44/51 for the gift path). Read `docs/spec52/RULES.md`, then AUDIT.md
sections 45, 46, 16, 24, 44, 51.
Migration dir: `backend/prisma/migrations/20261020000070_gift_engine/`.
Main files: `backend/src/gifts/{giftService.ts,controller.ts,routes.ts,videoValidate.ts}`,
`backend/src/middlewares/idempotency.middleware.ts`, `backend/src/utils/mediaOptimize.ts`,
`app/lib/gifts/**` (models/gift.dart GiftSendEvent, services/gift_socket_service.dart,
gift_repository.dart, widgets/gift_animation_overlay.dart, video_gift_player.dart,
gift_picker_sheet.dart), `app/lib/services/idempotency_interceptor.dart`, and the gift-recipient
builders in `app/lib/screens/room_screen.dart` (edit surgically).
NOTE: another developer is concurrently changing in gift_picker_sheet.dart the lucky-gift repeat
button and in gift_animation_overlay.dart / video_gift_player.dart the room-mute + effects
switches — keep your edits in those files minimal and localized.

## 45 — One gift event contract
- One serializer `buildGiftEvent(tx, gift, ctx)` in the gift module used by single, batch, CP and
  lucky sends. Payload (keep ALL existing fields for old apps, add): `giftId, giftType
  ('svg'|'video'|'image'|'lottie'|…), senderId, receiverId (=recipientId), roomId, seatId
  (recipient seat number at commit time or null), animationUrl, soundUrl (null for image gifts),
  durationMs, effectType ('flight'|'fullscreen'|'banner'|'none'), cpActivate (bool, outcome),
  cpXp (int, outcome), targetType ('user'|'seat'|'all_mics'|'all_room'), createdAt,
  transactionId, eventVersion: 2`. Sender/receiver also carry `nameColor` (vipStyle.service
  `nameColorSync(vipLevel)`).
- `gift_legendary_incoming` keeps its small payload but Flutter must parse it with its own small
  parser (it currently goes through the full GiftSendEvent parser and throws).
- Flutter: `GiftSendEvent` reads the new fields with fallbacks; overlay dispatches by giftType /
  effectType; dedupe by transactionId (room + user + global deliveries apply once).

## 46 — Idempotent gift transactions
- Client request key → `GiftTransaction.clientRequestId` (unique, nullable for old rows) +
  batch `operationId`. `/gifts/send` and `/gifts/send-batch`: require `Idempotency-Key` header
  from new clients (keep accepting missing keys from old builds — log them). Inside the SAME
  Serializable transaction as the debit, insert the gift rows with that key; on unique violation
  return the stored result (same response body) — no second debit, no second commission/XP/CP.
- The middleware's "processing" key left by a crash must not block or re-run: if a key is
  processing for > 30 s and a committed gift exists with that clientRequestId, return that result.
- Batch: one operation id; either commit all recipients atomically in one transaction (preferred)
  or deterministic child ids `${key}:${recipientId}` so a retry never re-charges succeeded children.
- Flutter: the gift picker generates ONE key per user intent and reuses it on retries
  (IdempotencyInterceptor keeps the header on retried RequestOptions).
- Unit tests: same key twice → one debit; concurrent same key → one debit; different body same
  key → 409.

## 16 — Gifts to all mics
- Build recipients for the picker from `room_seats_state` (every seat with an occupant, in seat
  order, with seatNumber), plus the room OWNER even when absent (labelled "صاحب الغرفة") — the
  owner is a real account, so gifts to him credit his account normally. Empty seats are not
  recipients. Keep self handling consistent (if I'm seated, I appear with my seat).
- "الجميع" = all occupied mic seats + absent owner (no duplicates). Unify the 3 places in
  room_screen.dart that build GiftRecipient lists into one helper.
- Server: `/gifts/send-batch` accepts `targetType:'all_mics'` + `roomId` and resolves the targets
  itself from the live seat state (+ owner) at commit time (ignore client ids for that mode),
  validates each target exists, and records `seatNumber`/`targetType` on GiftTransaction
  (nullable columns). Explicit recipient ids keep working.

## 24 — Video gifts that always play
- Server: on upload (both admin upload paths), keep the original and generate a fallback rendition
  H.264 Baseline profile, level ≤ 3.1, yuv420p, ≤ 720p, 30 fps, AAC 44.1/48 kHz, +faststart
  (ffmpeg via the existing helpers); store `Gift.videoFallbackUrl` + `videoMeta` (codec, w, h,
  durationMs, hasAlpha/hasAudio). Backfill script for existing video gifts (dry-run flag), not run
  automatically.
- Client: choose fallback rendition on DeviceTier lite/ultra-lite or after a decode error;
  preload (download to cache) before showing; never initialise the player on the critical path of
  a frame (no sync work in build); bounded queue (max 1 playing, max 5 queued, drop oldest
  non-mine); timeout → show the gift icon fallback animation instead of nothing; respect
  `gift.hasSound`/room mute; don't paint an opaque full-screen backdrop over the mics — play in a
  centered area ≤ 70% of the screen height, mics remain visible (unless the gift is configured
  fullscreen); dispose controllers on completion/room leave; log failures with codec info.

Notes file: `docs/spec52/notes-C6.md`.
