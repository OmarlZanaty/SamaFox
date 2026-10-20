# Batch C2 — Store categories + special ID purchase, private room backgrounds, social system, profile frame types
Spec items: 41, 22, 12, 40. Read `docs/spec52/RULES.md` first, then AUDIT.md sections 41, 22, 12, 40.
Migration dir: `backend/prisma/migrations/20261020000030_store_backgrounds_social/`.
Already on this branch: `requireOwnerPermission('store.products')` (ownerPermissions.service.ts),
`recordAdminAuditStrict(tx, …)`, AUDIT_ACTIONS STORE_CATEGORY_*, PRODUCT_*. New dashboard pages go
through `backend/public/spec52-admin.js` (`window.spec52Register('<section>', fn)`, helpers in
`window.spec52Helpers`) + a section + nav item in `admin-dashboard.html`.

## 41 — Custom store categories and special IDs (Owner only, separate from admin roles)
- `StoreCategory` (table `store_categories`): id, name, imageUrl, sortOrder, isActive,
  createdAt, updatedAt. `Item` gets nullable `storeCategoryId`, `currency` ('coins' default),
  `stock Int?` (null = unlimited), keep `isAvailable`/price/duration fields. Special-ID products:
  `Item.type = 'SPECIAL_ID'` with `meta.displayId` (the number for sale).
- Purchase flow `POST /api/v1/store/special-id/:itemId/buy` (idempotent middleware + unique order
  key): create `StoreOrder` (table `store_orders`: id, userId, itemId, status
  PENDING|COMPLETED|FAILED, priceCoins, oldDisplayId, newDisplayId, idempotencyKey unique,
  failureReason, createdAt, completedAt) → in ONE Serializable transaction: lock the item row
  (`SELECT … FOR UPDATE` via $queryRaw), check available + stock, check the display id is not
  used by any user and not reserved (also guard the normal displayId allocator
  `utils/displayId.ts` from handing out numbers that are listed for sale), guarded coin decrement,
  `Transaction` ledger row, set `users.displayId`, decrement stock, mark sold
  (`isAvailable=false` for single-ID items), record `display_id_history` (userId, oldId, newId,
  orderId, createdAt) and release the old id (policy: old id becomes free again — document it).
  Any failure → rollback, order FAILED with reason, no coins taken. Retry with same key returns the
  same result. Notify the buyer (purchase record).
- Also fix the generic `/store/buy` and `/store/send`: guarded decrement + one transaction +
  ledger row (see AUDIT 41 gap); don't change prices/behaviour otherwise.
- Admin (requires `store.products`): CRUD categories (name, image, order, active), CRUD products
  inside a category (name, image, price, currency, duration days, stock, available, delete, edit
  price), bulk add special IDs (list of numbers + price). Every change audited with before/after.
  Dashboard section "قوائم المتجر".
- Flutter store screen: dynamic category tabs from `GET /api/v1/store/categories` (active, ordered,
  with their products), special-ID cards (big number, price, buy button, sold/unavailable state),
  purchase confirmation dialog, clear Arabic errors (رصيد غير كافٍ / الرقم لم يعد متاحاً).

## 22 — "خلفياتي" (private room backgrounds)
- Reuse `Item`/`UserItem` as the ownership authority for room backgrounds (type
  `ROOM_BACKGROUND`); extend `UserItem` with `source` ('purchase'|'gift'|'grant'), `grantedBy`,
  `status` ('active'|'expired'|'revoked'), keep acquiredAt/expiresAt. If an explicit
  `room_backgrounds` / `user_background_inventory` view is wanted, create SQL VIEWs with those names
  over items/user_items (no duplicated data). Free backgrounds = `Item.priceCoins = 0` + public.
- `GET /api/v1/rooms/:roomId/backgrounds/mine` → free + owned (active, not expired) by the
  CALLER only. `updateRoomBackground` / `updateRoom backgroundImageUrl`: the server only accepts
  a background id the caller may use (free or owned) — never an arbitrary URL from a normal user
  (admins keep raw URL upload as today); any rental charge is computed server-side from the item,
  not a client flag, in one idempotent transaction.
- Grants from the dashboard set source='grant', grantedBy; gifts set 'gift'. Purchases 'purchase'.
  A granted/bought background is never listed for anyone else.
- Flutter room background picker (`room_screen.dart::_openStoreBackgroundPicker` area): tabs
  "خلفياتي" (free + mine) and "المتجر" (buyable). Keep the edit surgical in room_screen.dart.

## 12 — Social system
- New `Friendship` (table `friendships`): id, requesterId, receiverId, status
  pending|accepted|rejected|blocked, createdAt, acceptedAt, blockedAt, updatedAt; unique pair
  (least(a,b), greatest(a,b)) via a unique index on two generated/normalized columns (userLowId,
  userHighId). Backfill accepted friendships from existing MUTUAL accepted follows (they were
  shown as friends already) — idempotent.
- Routes: `POST /api/v1/friends/requests {userId}`, `POST /api/v1/friends/requests/:id/accept|reject`,
  `DELETE /api/v1/friends/:userId` (unfriend), `POST /api/v1/friends/:userId/block`,
  `GET /api/v1/friends`, `GET /api/v1/friends/requests?direction=in|out`. Notifications + socket
  events `friend_request`, `friend_accepted` (Flutter listeners).
- Follows stay one-way (`Follow`): following = my follows, followers = reverse query. Keep the
  existing follow routes working.
- Visitors: `ProfileVisit` → record every profile open from any entry point (not only home):
  self-visits ignored, one row per (visitor, owner) updated with `lastVisitAt` + `visitCount`
  (upsert, atomic) instead of millions of rows. `GET /api/v1/users/:id/visitors` (owner only).
- Counts endpoint `GET /api/v1/users/:id/social-counts` → friends, followers, following, visitors —
  real DB counts; include them in profile responses. No mock numbers anywhere in Flutter
  (`profile_screen.dart`, `relations_screen.dart`, follow service): replace any hard-coded numbers.
- Flutter: relations screen tabs الأصدقاء / أتابعه / يتابعني / الزوار, friend request
  accept/reject UI, "إضافة صديق" button on profiles (states: إضافة / تم الإرسال / أصدقاء).
- `dmAccess.service.ts` "friends" privacy → use accepted Friendship (keep mutual-follow as
  fallback during rollout).

## 40 — Profile decoration frame vs avatar frame vs room frame
- Keep the existing PROFILE_DECOR pipeline (it already frames the profile page). Enforce product
  types at create/equip: `PROFILE_DECOR` (profile page frame), `FRAME` (avatar/mic frame),
  `ROOM_FRAME` (new, reserved; room-level frame). Equip of one never sets the others' columns.
  Admin product form shows the three as distinct types with help text. Profile page: decoration
  frame drawn around the profile header area only; mic seats only use FRAME. Make sure tapping a
  user in a room opens the profile with the decoration (not the room).

Notes file: `docs/spec52/notes-C2.md`.
