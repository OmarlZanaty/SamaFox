# Batch C3 — Room gift Rocket, PK battles, game-win strip
Spec items: 28, 29, 39. Read `docs/spec52/RULES.md`, then AUDIT.md sections 28, 29, 39.
Migration dir: `backend/prisma/migrations/20261020000040_rocket_pk_gamewin/`.
Already on this branch: `requireOwnerPermission('economy.settings')`, `recordAdminAuditStrict`,
AUDIT_ACTIONS ROCKET_CONFIG_UPDATE / ROCKET_REWARD / PK_CONFIG_UPDATE / PK_RESULT, dashboard module
`backend/public/spec52-admin.js` (`window.spec52Register`, `window.spec52Helpers`). In the room,
`app/lib/widgets/room/room_left_rail.dart` has `pk:` and `rocket:` slots (top-left column, PK
above rocket above games) — fill them from `room_screen.dart` (surgical edit where `RoomLeftRail(`
is built). `RoomChatPanel` area / header: there is room for a thin strip under the header.

## 28 — Gift Rocket (per room)
- Models: `RocketConfig` (single active config row + history: targetCoins, roomCupPercent (bp,
  share of each gift's coin value that counts toward the rocket), durationMinutes,
  winnersCount, maxRewardPerUserCoins, claimWindowSeconds (default 90), rewards Json list of
  {type:'coins'|'item', itemId?, coins?, weight, quantity}, isActive, updatedBy);
  `RocketEvent` (id, roomId, configSnapshot Json, targetCoins, currentCoins, status
  ACTIVE|LAUNCHED|EXPIRED, startedAt, endsAt, launchedAt); `RocketContribution` (eventId,
  giftTransactionId UNIQUE, userId, coins); `RocketClaim` (rocketEventId, userId, rewardJson,
  claimedAt) with UNIQUE(rocketEventId, userId).
- Progress: after a gift commits in a room (hook where `evaluateRoomCupRewards` is called in
  `giftService.ts`, post-commit), add `floor(giftCoins * roomCupPercent/10000)` to the room's ACTIVE
  event (create one lazily when none active; expire by endsAt) — idempotent by giftTransactionId.
  Emit `rocket_state {roomId, eventId, current, target, endsAt}` to the room (throttled 1/s).
- Launch when current ≥ target (atomic status flip ACTIVE→LAUNCHED with updateMany guard):
  emit `rocket_launched {roomId, roomName, eventId}` to EVERYONE (global), and to the room.
- Claim `POST /api/v1/rockets/:eventId/claim` (idempotent): only within claimWindow after launch,
  only users currently in that room (server room state), at most winnersCount claims total, one per
  user (unique). Reward drawn SERVER-SIDE by weights from the snapshot; coins paid from an economy
  pool account `ROCKET_POOL` (reuse economyAccounts.service / EconomyLedger patterns like
  GAME_POOL; refuse when the pool can't cover); items granted via UserItem with expiry. Cap per user
  by maxRewardPerUserCoins. Every result → AdminAuditLog ROCKET_REWARD (adminId = 0 / system) and
  ledger. Pool funding endpoint like the game pool fund (owner permission `economy.settings`).
- Admin page "الصاروخ": config form (target, %, duration, winners, max per user, claim window,
  rewards list with weights from products), pool balance + fund, recent events + claims.
- Flutter: `RocketButton` in the rail (rocket icon + progress ring + "650K/1M" compact text),
  tap → sheet with progress, time left, rewards preview. On `rocket_launched` in this room: launch
  animation (lightweight: rocket flying up + particles with CustomPainter, ≤ 2.5 s) then a "استلم
  الجائزة" button calling claim → show reward. Global `rocket_launched` from another room: a small
  top banner "🚀 صاروخ انطلق في غرفة X" — tap → confirm dialog → navigate to that room (reuse the
  existing room navigation used by gift banners).
- Artwork: use the files in `app/assets/images/spec52/` if present (`rocket.png`,
  `rocket_flame.png`); otherwise draw with icons/CustomPainter. Don't add pubspec asset lines for
  missing files.

## 29 — PK
- Extend existing `PkBattle` (or add `PkMatch` if PkBattle is unusable): id, type ROOM|GLOBAL,
  roomId (ROOM: both sides in this room; sides are two seated users A/B), opponentRoomId (GLOBAL:
  room vs room), sideAUserId?, sideBUserId?, status PENDING|ACTIVE|FINISHED|CANCELLED, startedAt,
  endsAt, durationSec, configSnapshot Json, scoreA, scoreB, winner 'A'|'B'|'TIE', createdBy.
  `PkContribution` (pkId, giftTransactionId UNIQUE, side, points).
- `PkConfig` (owner, `economy.settings`): allowed durations (e.g. [180,300,600]), countedGiftIds
  (empty = all coin gifts), pointsPerCoin, winCondition 'HIGHER_SCORE', tieRule 'TIE'|'FIRST_TO_REACH',
  rewards Json {winner:{coins?|itemId?}, loser?} (optional; coins from ROCKET_POOL-like
  `PK_POOL`), enabled.
- Start: room owner/admin `POST /api/v1/pk/start {type, durationSec, sideAUserId, sideBUserId}`
  (ROOM) or `{type:'GLOBAL', opponentRoomId}` → other room's owner gets `pk_invite`, accepts via
  `POST /api/v1/pk/:id/accept` (GLOBAL). Only one active PK per room.
- Scoring: post-commit gift hook: gift to sideA/sideB user (ROOM) or any gift inside room A / room B
  (GLOBAL) adds points (idempotent by giftTransactionId). Emit `pk_state {pkId, scoreA, scoreB,
  endsAt}` (throttled). Settlement: a server timer + boot recovery finishes at endsAt
  (updateMany status guard), decides winner by config, pays rewards, writes PK_RESULT audit,
  emits `pk_result`. Client never decides.
- Flutter: PK icon in the rail (above rocket) → start sheet for owner/admin (choose type, A/B from
  seated users or room ID, duration). During PK: compact bar under the header: avatars A VS B,
  scores, progress bar split, countdown from server endsAt. Result card on `pk_result`.
- Admin page "PK": config + history.

## 39 — Game win strip in room header
- `gameBroadcast.service.ts::broadcastGameWin` add `gameId`, `gameName` (Arabic display name),
  `winCoins`, `roomId` (from the request when the game is opened from a room — add optional
  `roomId` param to game spin/bet routes the app already calls, validated against the user's
  current room on the server), `ts`. Call it post-commit in every game settlement service that
  pays (incl. Olympus `olympus.service.ts::resolveSpin`) with the real payout, only when win > 0.
  Also persist `GameWinEvent` (table `game_win_events`: id, userId, roomId?, gameId, gameName,
  winCoins, createdAt) for the latest-wins query `GET /api/v1/games/wins/recent?roomId=`.
- Flutter: a thin sliding ticker under the room header ("🎮 محمد فاز في Olympic بـ 20,000 كوينز"),
  room-filtered first then global, light slide animation, never fake data (empty when none).

Notes file: `docs/spec52/notes-C3.md`.
