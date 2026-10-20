# Batch B1 — Owner permissions, audit log, animated-avatar VIP gate, VIP name colours
Spec items: 42, 43, 6, 7. Read `docs/spec52/RULES.md` first, then AUDIT.md sections 42, 43, 6, 7.
Migration dir: `backend/prisma/migrations/20261020000010_owner_permissions_name_colors/`.

## 42 — Owner + explicit permissions (foundation other batches will use)
- Add `User.isOwner Boolean @default(false)`. Owner = full control.
- Bootstrap so production is never locked out: if NO user has `isOwner = true`, users with
  `isSuperAdmin = true` are treated as owner (log a one-time warning). Document in notes how to
  set the real owner (`UPDATE users SET is_owner = true WHERE id = …`).
- Add model `AdminPermissionGrant` (table `admin_permission_grants`): id, userId, permission
  (string key), grantedBy, createdAt, revokedAt?, revokedBy?; partial-unique active grant per
  (userId, permission).
- Permission catalog constant (backend/src/services/ownerPermissions.service.ts, new):
  `finance.coins` (grant/deduct coins, wallets), `finance.recharge` (recharge/top-up settings and
  requests), `finance.charging_agency` (charging agency financial settings, balances),
  `store.products` (create/edit/delete products, prices, store categories), `gifts.prices`
  (gift create/edit price/delete, gift categories), `economy.settings` (game/lucky/rocket/PK pools
  and economy config), `vip.config` (VIP levels config, name colours, animated-avatar gate),
  `admin.permissions` (owner-only: grant/revoke these permissions).
- Middleware `requireOwnerPermission(perm)`: allow if owner (incl. bootstrap rule) or active grant.
  Managers/Super Admins/Admins/staff roles NEVER inherit these automatically (do not add them to
  the staff MANAGER "all permissions" set).
- Apply it to every existing endpoint that changes: product prices/CRUD (`adminProduct.routes.ts`),
  gift CRUD/prices/categories (`gifts/admin.routes.ts`, gift routes in `adminDashboard.routes.ts`
  and `admin.routes.ts`), coin grants/deductions, recharge, charging-agency financial ops in
  `charging-agency.controller.ts`/dashboard, economy config (`adminEconomy.routes.ts`), VIP level
  config. Read-only endpoints keep the current admin check.
- Endpoints (owner only): `GET /api/v1/admin-dashboard/permissions/catalog`,
  `GET /api/v1/admin-dashboard/permissions/grants`, `POST …/grants {userId, permission}`,
  `DELETE …/grants/:id`. Audit every grant/revoke. Add `capabilities` (owner flag + granted
  permission keys) to the dashboard's current-admin/me response.
- Dashboard UI (`admin-dashboard.html` + `app.js`): a "الصلاحيات المالية" page (owner only) to
  grant/revoke per admin; hide/disable financial buttons when the capability is missing, and show
  the server's 403 message ("هذه العملية تحتاج صلاحية من المالك").

## 43 — Audit log completeness
- Extend `AdminAuditLog` additively with `device String?` (parsed from User-Agent / `X-Device`
  header) if missing; keep existing fields (adminId, action, targetType, targetId, before, after,
  ip, userAgent, createdAt).
- Add a strict variant `recordAdminAuditStrict(tx, …)` that throws (so the mutation rolls back)
  — use it for permission grants, VIP config, name colours, prices, coin ops you touch here.
- Make sure these produce rows with real before/after: VIP change for a user, VIP level config,
  name colour, granting frame/gift/item to a user, agency name change, gift category add/delete,
  store product add/price change, CP gift flag change, VIP requirement (gates) change. Fix any of
  these paths that currently skip audit or log `before: null` (check `adminDashboard.routes.ts`
  generic logger, `adminDashboard.controller.ts`, `adminProduct.controller.ts`,
  `gifts/admin.controller.ts`, `cpAdmin.service.ts`).
- Dashboard audit viewer: filters by action, targetType, adminId, date; show before/after diff,
  ip, device.

## 6 — Animated avatar permission (server-side)
- Existing `VipLevelConfig.allowAnimatedAvatar` + `animatedAvatar.service.ts`. Add an explicit
  owner setting in the dashboard VIP page: checkboxes per VIP level (exact tiers allowed; keep the
  existing per-level flag as the source of truth) and make `canUseAnimatedAvatar` use "user's
  active VIP level has allowAnimatedAvatar = true".
- Close the bypass: `user.controller.ts::updateProfile` (and any other avatar assignment) must
  reject an animated avatarUrl (gif/apng/animated webp by extension, MIME, or uploaded-file
  metadata; detect animated WebP/PNG by reading the file header when it is one of our uploads)
  when the user isn't allowed. Error message Arabic: "الصورة المتحركة متاحة لمستوى VIP المحدد فقط".
- Flutter: edit_profile_screen shows the lock state from a server capability
  (`canUseAnimatedAvatar` in /me or settings) instead of guessing.

## 7 — VIP name colours
- Add `VipLevelConfig.nameColor String?` (HEX `#RRGGBB` or `#AARRGGBB`, validated) and reserve
  `nameGradient Json?` (array of hex, optional, not required in UI now but accepted/validated).
  Defaults when migrating: VIP1 #FFFFFF, VIP2 #4CAF50, VIP3 #2196F3, VIP4 #9C27B0, VIP5 #FFD700,
  higher levels null (owner sets). Only fill rows whose nameColor is NULL.
- Server resolves `nameColor` from the user's ACTIVE VIP (respect vipExpiresAt / staff
  entitlements via vip.service). Include `nameColor` in: /auth/me, /users/:id, room users
  (`room_users`, `user_joined`), `room_seats_state` seat occupants, `new_message` payloads, gift
  events (sender/recipient), leaderboards/supporters, DM conversation lists, follow/relations
  lists, search results. Cache config in memory with invalidation on admin change.
- Owner edits colours in the dashboard VIP page (colour picker + HEX input + preview); requires
  `vip.config`; audited with before/after.
- Flutter: add `nameColor` (String?) to the User model and to the seat/message/gift models; add a
  shared widget `app/lib/widgets/user_name_text.dart` (`UserNameText(name, nameColor, style)` that
  parses hex safely, falls back to the default style colour, supports gradient via ShaderMask if a
  gradient list is present). Use it in NON-room screens in this batch: profile_screen,
  messages_screen / conversation list, chat_screen header, relations_screen, leaderboard_screen,
  supporters_board_screen, search_screen, notifications where a username shows. (Room screen,
  seat cards and room chat will be done by another batch — do NOT edit room_screen.dart,
  seat_card.dart, seats_grid.dart, room_chat_panel.dart.)
