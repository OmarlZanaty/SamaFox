# نظام الإدارة والصلاحيات — Build brief (2026-10-04)

This is the implementation brief for the SamaFox staff system (Manager / Super Admin /
Admin / Ban system). Part A is the client's specification, verbatim in substance.
Part B is the binding engineering decisions that fill its gaps. Part C maps it onto
the existing code. Part D is the API contract shared by backend, web dashboard and app.

Everything in Part A must be implemented. Where Part A and Part B disagree, Part A wins
unless Part B explicitly says it is resolving an ambiguity.

---

## Part A — Client specification (summary of every requirement, nothing dropped)

Goal: a professional admin system inside the SAMAFOX app with REAL server-side
permissions — not hiding buttons in Flutter.

Roles: 👑 Manager, 💎 Super Admin, 🛡️ Admin, 🚫 Ban system (an independent permission
that can be granted/withdrawn).

Each role appears for its holder **inside the app's Settings** (Settings → نظام الإدارة),
showing only the panels for permissions they hold. No external link, no browser, no WebView.
When the role is withdrawn or expires, the entry disappears from Settings automatically.

### 1. MANAGER (top level)
- Appoint a Super Admin (any user); set the duration; base duration = 1 month; renew;
  extend as he sees fit; cancel any time; stop immediately; see start date, end date,
  who appointed, status (نشطة / منتهية / ملغاة).
- When the month ends, automatically: remove the Super Admin role, remove its
  permissions, hide نظام الإدارة from settings, block Super Admin functions, log it.

### 2. Manager manages Admins
Appoint Admin; set duration (base 1 month); renew; extend; cancel any time; stop
immediately; see start/end. On expiry: auto-cancel and hide from settings.

### 3. Manager grants VIP and Level
VIP 1→5, Level 1→20, duration 7 days only. After 7 days: grant ends automatically,
granted VIP and Level withdrawn, logged. MUST NOT destroy the user's original value:
create a Temporary Entitlement. Example: user has VIP 3; Manager grants VIP 5 for 7
days; after 7 days the user is back to VIP 3, not VIP 0.

### 4. Temporary products
Manager grants 🖼️ frame, 🚪 entrance (دخولية), 💬 chat bubble — chosen from the list of
allowed products in the control panel; 7 days only; Manager chooses which frame /
entrance / bubble. After 7 days the products are withdrawn automatically.

### 5. Hosting agencies by Manager
Create/assign a hosting agency; choose who runs it (the owner); assign a Super Admin or
Admin to follow it; see the agencies he created; see the staff member responsible for
each; follow the production and activity of agencies within his scope.
FORBIDDEN: hosting agencies only — no charging agencies, money or coins management.

### 6. Following the staff he appointed — section 👥 الإداريون
Table: ID | الاسم | النوع | بداية الإدارة | نهاية الإدارة | الحالة (🟢 نشط / 🔴 منتهي / ملغى).
Manager can: open the staff member's file, see his permissions, extend, withdraw,
edit his permissions, see his agencies, see the operations he performed.

### 7. 🔐 صلاحيات الإدارة (Manager panel)
Pick a staff member (by ID) → shows his role and a checklist:
☑ نظام Super Admin ☑ تعيين Admin ☑ منح VIP ☑ منح Level ☑ منح إطار ☑ منح دخولية
☑ منح فقاعة دردشة ☑ تعيين وكالة مضيفين ☑ متابعة الوكالات ☐ نظام الحظر.
Manager can switch any permission on/off.

### 8. SUPER ADMIN (appointed by Manager)
- Appoint Admin within his scope; cannot appoint Super Admin.
- Grant VIP 1→5 for 7 days (auto-withdrawn).
- Grant Level 1→20 for 7 days (auto-withdrawn).
- Grant frame / entrance / bubble — only the products the Manager pre-selected for him
  (e.g. Frame 10, Frame 15, Entry 5, Bubble 3); nothing else.

### 9. Hosting agencies by Super Admin
Create a hosting agency; follow the agencies he created; follow those created by Admins
under him. Scope: his agencies + his Admins' agencies only.

### 10. ADMIN (appointed by Manager or Super Admin)
- Activate a hosting agency within his scope; follow the agency he created/activated;
  follow its hosts.
- Follow: agencies he created, their hosts, activity / production / allowed reports.

### 11. Admin rewards
Admin gets special admin products defined in the control panel: 🛡️ Admin Frame,
🏅 Admin Badge, 🎁 Admin Products (extra products chosen in the Manager panel).
Selectable from: control panel → صلاحيات الإدارة → Admin → المنتجات المسموحة.

### 12–14. Ban system 🚫 نظام الحظر
- Independent section in app Settings; shown to nobody unless granted.
- Controlled from: Manager panel → صلاحيات الإدارة → نظام الحظر.
- Manager can: grant ban permission to a specific person; withdraw it any time; set the
  duration of that ban permission; see who holds it.
- Durations: يوم (1 Day), أسبوع (7 Days), شهر (30 Days), سنة (365 Days), أبدي (Permanent).
- Ban form shows: user ID, user name, duration, reason → «تأكيد الحظر».
- When withdrawn: shows "نظام الحظر: مسحوب", disappears from Settings immediately, and the
  ban API refuses him even through an indirect/modified app.

### 15. Placement inside the app
Settings shows only what he holds: 👑 نظام إدارة Manager / 💎 نظام إدارة Super Admin /
🛡️ نظام إدارة Admin / 🚫 نظام الحظر.

### 16. When a role is withdrawn — immediately
1 cancel role · 2 cancel admin permissions · 3 cancel role-linked systems · 4 end the
current admin session if possible · 5 refresh permissions from the server · 6 hide نظام
الإدارة · 7 hide نظام الحظر if it was tied to the role · 8 block every admin API ·
9 write the Audit Log.

### 17. When a term ends
No manual action: server flips Active → Expired, removes role, permissions, hides the
system, blocks the API, logs the expiry.

### 18. Renewal
Manager: الإداريون → user → تمديد الإدارة. Logged: old term, new term, who renewed,
date/time.

### 19. Audit Log
Every operation logged, e.g. "Manager ID 100001 appointed User 20001 as Super Admin,
1 month, date, expiry", "Super Admin 20001 granted User 50001 VIP 5, Level 15, 7 days",
"Manager 100001 withdrew ban permission from Admin 30001". Never deleted.

### 20–22. Server-side enforcement on every request
Authentication → Role → Permission → Scope → Expiration → Action → Audit Log.
Missing permission ⇒ 403 Forbidden, even with a modified app — for grant VIP, assign
agency, appoint Admin, grant products, ban, edit any permission.
Scope: server knows who appointed whom, which agencies belong to whom, which users he
may act on. Manager → Super Admin A → Admin B → Agency 1001: Admin B cannot reach
Agency 1002.

### 23. Products
Manager picks which products each staff member may grant. Staff can never edit a
product (price, name, image, value, delete, create) — only grant allowed ones.

### 24. Separation from money (mandatory)
These roles get NO: edit/add/deduct coins, edit balance, perform charging, manage a
charging agency, change charging commission, edit app prices, financially edit products.

### 25. Database (at least)
admins, admin_permissions, admin_scopes, temporary_entitlements, bans, admin_audit_logs
(admin_id, action, target_user_id, target_agency_id, old_value, new_value, created_at,
ip, device).

### 26. Dynamic settings from the server
E.g. user 20001: role=SUPER_ADMIN, manage_admin=true, grant_vip=true, grant_level=true,
grant_frame=true, manage_host_agency=true, ban_users=false → Settings shows
"💎 نظام إدارة Super Admin" and NOT "🚫 نظام الحظر". Granting ban_users adds it; revoking
hides it immediately.

### 27. Result
Manager controls Super Admin / Admin / permissions / agencies; Super Admin controls his
Admins, agencies, hosts and granted permissions within scope; Admin works with hosting
agencies and hosts and his assigned functions only; Ban System independent; every
permission grantable/revocable individually; every temporary thing expires on the server;
everything audited; the server is the final authority.

---

## Part B — Engineering decisions (binding)

1. **Separate from platform roles.** `User.isAdmin` / `User.isSuperAdmin` stay exactly as
   they are (the platform owner's dashboard staff, which do touch money). The new roles live
   only in the new tables and NEVER pass `adminMiddleware`, `requireAdminDashboard` or any
   coin/charging route. Nothing in the new code writes coinsBalance, totalRecharge (except
   see B7), prices, items or charging agencies.

2. **Who appoints Managers.** The platform dashboard (web, `public/admin-dashboard.html`),
   by a dashboard super admin (`requireSuperAdmin`). Several Managers may exist; each owns
   his own subtree. The dashboard also sees/extends/revokes every staff member, edits the
   global grantable-products pool and the role reward products, and reads the full staff
   audit log.

3. **Roles and rank.** MANAGER (3) > SUPER_ADMIN (2) > ADMIN (1). Ban-only holder (no role) = 0.
   A user has at most one ACTIVE `staff_roles` row (DB partial unique index exists).
   `parentUserId` is the staff member he reports to:
   - Manager appointed from dashboard: parent null.
   - Super Admin appointed by a Manager: parent = that Manager.
   - Admin appointed by a Manager: parent = Manager. By a Super Admin: parent = that SA.

4. **Who may appoint / manage whom.**
   - Manager: appoint SUPER_ADMIN and ADMIN; manage (extend, renew, revoke, permissions,
     allowed products, reward products) any staff in his subtree (transitively).
   - Super Admin: appoint ADMIN only, needs permission `manage_admins`; manage only Admins
     whose parent is him.
   - Admin: appoints nobody.
   - Nobody appoints himself, and nobody acts on himself (no self-extend, self-grant, self-ban).
   - Target must not be banned. Target must not already hold an ACTIVE role (409 with
     message telling to extend or revoke first).

5. **Durations of roles.** Default 30 days ("شهر"). Manager may choose 1–365 days for
   appointment and each extension. Super Admin 1–30 days. Extension adds to
   max(now, current expiry). Renewal of an EXPIRED/REVOKED appointment creates a NEW row
   (history kept) copying role, permissions, allowed products and reward products.
   Every extension/renewal audit row stores old expiry, new expiry, actor, time.

6. **Permission keys** (stored in `staff_permissions.permission`):

   | key | Arabic label | roles that may hold it | default on appointment |
   |---|---|---|---|
   | `role_panel` | نظام {role} (e.g. نظام Super Admin) | SA, ADMIN | on |
   | `manage_admins` | تعيين Admin | SA (Manager has it inherently) | on for SA |
   | `grant_vip` | منح VIP | SA, ADMIN | on for SA, off for ADMIN |
   | `grant_level` | منح Level | SA, ADMIN | on for SA, off for ADMIN |
   | `grant_frame` | منح إطار | SA, ADMIN | on for SA, off for ADMIN |
   | `grant_entry` | منح دخولية | SA, ADMIN | on for SA, off for ADMIN |
   | `grant_bubble` | منح فقاعة دردشة | SA, ADMIN | on for SA, off for ADMIN |
   | `manage_host_agency` | تعيين وكالة مضيفين | SA, ADMIN | on |
   | `follow_agencies` | متابعة الوكالات | SA, ADMIN | on |
   | `ban_users` | نظام الحظر | anyone (incl. users with no role) | off |

   - A MANAGER holds every permission inherently, `ban_users` included (he controls the ban
     system); no permission rows are needed for him.
   - `role_panel` off ⇒ the role panel entry disappears from Settings and every role API
     answers 403 (role is "suspended" without being revoked).
   - Permission rows tied to a role (`staffRoleId` set) end with the role. `ban_users`
     granted to someone with no role is a standalone row (`staffRoleId` null) that survives.
     `ban_users` granted to a staff member is tied to his role (hidden with the role, spec 16.7).
   - Any permission row may carry its own `expiresAt` (the spec requires it for ban
     permission: "تحديد مدة صلاحية الإدارة الخاصة بالحظر"). Choices: 1, 7, 30, 365 days or
     until the role ends / permanent.
   - Who may edit permissions: Manager on his subtree (any key); Super Admin on his own
     Admins, and only keys he himself holds. ONLY Managers grant or revoke `ban_users`
     (spec 12–14).

7. **Temporary VIP / Level (7 days, fixed).**
   - VIP value 1..5, Level 1..20. Requires `grant_vip` / `grant_level`.
   - "Real" (base) value = what the user holds in his own right:
     - VIP: max(previousValue of the active VIP entitlement chain, computeVipLevelWithOverrides(totalRecharge)).
     - Level: max(previousValue chain, calculateLevelWithOverrides(xp)).
   - Refuse with 400 if the requested value ≤ the user's real base value
     ("المستخدم لديه مستوى أعلى أو مساوٍ"). Re-granting the same value while a grant is active
     is allowed (it extends: a new entitlement row with a later expiry).
   - On grant: previousValue = (earliest ACTIVE entitlement of same type).previousValue if one
     exists, else the user's current column value. Then set column = max(current column, value).
   - On expiry or revoke: remaining = other ACTIVE entitlements of that type;
     base = max(previousValue, natural value computed now);
     column = max(base, max(remaining values)). Then re-grant tier rewards idempotently for
     (previousValue, natural] (vip.service grantVipRewardsForRange / xp.service
     grantLevelRewards) so levels earned naturally during the grant are not missed.
   - A temporary grant does NOT hand over the tier's reward items (those belong to earned
     levels) and does not touch totalRecharge or xp.
   - Patch `expiry.service.ts` VIP sweep: the lapsed-purchase recompute must become
     max(earned, max ACTIVE temporary VIP value) so it never cancels a staff grant.
   - Patch `vip.routes.ts` /buy: compare the purchase against the user's REAL base level
     (not the temporarily raised column) and, if a temporary grant is active, write
     vipLevel = max(level, active grant value).

8. **Temporary products (7 days, fixed).**
   - Types: frame = Item.type `FRAME`; دخولية = `ENTRANCE_BANNER` or `ENTRANCE_EFFECT`;
     bubble = `CHAT_BUBBLE`. Permission per type: grant_frame / grant_entry / grant_bubble.
   - Global pool: app setting `staff_grantable_items` (JSON array of Item.ids), edited only
     in the web dashboard ("قائمة المنتجات المسموح بها داخل لوحة التحكم").
   - Manager may grant any item in the pool. SA/Admin may grant only items in their
     `staff_roles.allowedItemIds` (which must be ⊆ pool). Manager sets allowedItemIds for
     anyone in his subtree; an SA sets it for his Admins ⊆ his own allowedItemIds.
   - Apply: no UserItem → create with expiresAt = now+7d, previousValue `none`;
     UserItem permanent (expiresAt null) → nothing changes, previousValue `permanent`
     (record the grant, tell the actor the user already owns it permanently);
     UserItem expiring later than now+7d → nothing changes, previousValue `later:<iso>`;
     UserItem expiring sooner → set expiresAt=now+7d, previousValue `until:<iso>`.
   - Natural expiry: the existing 15-minute item sweep deletes the row; the staff job marks
     the entitlement EXPIRED. Early revoke: only if the UserItem.expiresAt still equals the
     grant's expiry — `none` → delete the row (and clear activeFrameId/avatarFrameUrl if it was
     the equipped frame, same as expiry.service); `until:<iso>` → restore that expiry.
   - Staff can never create/edit/delete/price an item (no such endpoint exists for them).

9. **Role reward products (spec 11).** App setting `staff_role_rewards`
   = `{"MANAGER":[ids],"SUPER_ADMIN":[ids],"ADMIN":[ids]}` (Admin Frame, Admin Badge, …),
   edited in the web dashboard AND by a Manager in the app ("المنتجات المسموحة" under
   صلاحيات الإدارة → Admin). Per-staff extras: `staff_roles.rewardItemIds`, set by whoever
   manages him. On appointment / renewal / reward change, each reward item is granted as a
   TemporaryEntitlement (type ITEM, source ROLE_REWARD, staffRoleId, expiresAt = role expiry)
   with the same apply rules as B8; extended with the role; removed when the role ends.

10. **Hosting agencies.**
    - Create: permission `manage_host_agency`. Body: owner user (id or displayId), agency
      name. Reuse the logic of `adminAssignAgency` in adminDashboard.controller.ts but HOSTING
      only: refuse if the owner already has a non-rejected HOSTING agency. Creates
      ChargingAgency(type HOSTING, status approved) + AgencyMember OWNER + notification, and a
      `staff_agency_scopes` row (kind CREATED) for the actor. `assignedByAdminId` stays null
      (that column belongs to dashboard admins).
    - Scope of a staff member = agencies with a scope row for him (CREATED or ASSIGNED)
      ∪ the scope of every staff member in his subtree (SA: his Admins; Manager: whole subtree).
    - Assign follower: Manager (or SA for his Admins) puts a staff member from his subtree on
      an agency in his own scope → `staff_agency_scopes` kind ASSIGNED. Removing it is allowed
      too.
    - Follow: permission `follow_agencies`. List agencies in scope with owner, members count,
      production (agency.controller `computeAgencyEarnedCoins`), creator, followers, created
      date. Detail: hosts (members) with each member's target (`memberTargetEarned`) and
      broadcast hours this month (`getBroadcastSeconds`).
    - "تفعيل" for Admin = creating it active. No charging agencies, no coin/target edits,
      no ownership transfer, no member removal.
    - An agency outside the actor's scope ⇒ 403.

11. **Ban system.**
    - Permission `ban_users`; Manager holds it inherently; only Managers grant/revoke it (for
      a staff member: tied to his role; for anyone else: standalone) with optional term.
    - Durations exactly: `1d` يوم, `7d` أسبوع, `30d` شهر, `365d` سنة, `permanent` أبدي.
    - Ban: reason required (non-empty). Target cannot be: self, a platform admin
      (isAdmin/isSuperAdmin), or an active staff member of rank ≥ actor's rank (ban-only
      holders have rank 0 ⇒ cannot ban any staff). Already-banned target ⇒ 409.
    - Write User ban fields `{isBanned:true, bannedAt, banReason, banExpiresAt, banSource:'staff'}`,
      a `ban_records` row, `invalidateBanCache`, `kickBannedUser` (socket.service), audit.
    - Unban: permission `ban_users`; only bans whose User.banSource is 'staff'; allowed for the
      issuer, any staff above the issuer in the tree, or any Manager. Marks the record LIFTED.
    - The job marks records EXPIRED once `expiresAt` passes (enforcement already lifts via
      banGuard).
    - Lookup endpoint returns the target's id, displayId, name, avatar, VIP, level, banned
      state — for the confirm form.

12. **Expiry & revocation.**
    - Every guard checks `status='ACTIVE' AND (expiresAt IS NULL OR expiresAt > now)` live, so
      access ends at the exact second even between job runs.
    - A job every 60 s (`startStaffExpiryJob`, wired in index.ts next to startExpirySweep):
      expire roles (+ their permissions + their ROLE_REWARD entitlements), expire standalone
      permissions, expire temporary entitlements (VIP/LEVEL restore per B7, items per B8),
      mark ban records EXPIRED. Every automatic expiry writes an audit row with adminId 0
      (system) and an `*_EXPIRED` action.
    - When a Super Admin's role ends (expired or revoked), his Admins are re-parented to the
      SA's own parent (the Manager) and stay active (audit STAFF_REPARENT). His scope rows are
      kept for history, and copied to his parent as kind ASSIGNED so no agency falls out of
      anyone's scope.
    - When a Manager's role ends: his direct subordinates get parentUserId = null and are
      visible to the dashboard only (until a dashboard super admin re-attaches them via
      the dashboard "change manager" action).
    - After ANY change to a user's access (appoint, extend, revoke, expire, permission
      change, reward change) emit socket event `staff_access_changed` to room `user:<id>`
      with `{userId}`; the app refetches `/staff/me` and closes any panel it no longer has
      (spec 16.4 "إنهاء جلسة الإدارة الحالية").
    - Notifications (createNotification) to the affected user on appointment, extension,
      revocation, expiry, permission change, and to the grantee of VIP/Level/products.

13. **Audit.** Use the existing `admin_audit_logs` via `recordAdminAudit` (append-only; no
    delete endpoint anywhere). Actions (prefix `STAFF_`):
    STAFF_APPOINT, STAFF_EXTEND, STAFF_RENEW, STAFF_REVOKE, STAFF_EXPIRED,
    STAFF_PERMISSION_GRANT, STAFF_PERMISSION_REVOKE, STAFF_PERMISSION_EXPIRED,
    STAFF_ALLOWED_ITEMS_SET, STAFF_REWARD_ITEMS_SET, STAFF_ROLE_REWARDS_CONFIG,
    STAFF_GRANTABLE_POOL_SET, STAFF_REPARENT,
    STAFF_GRANT_VIP, STAFF_GRANT_LEVEL, STAFF_GRANT_ITEM, STAFF_GRANT_REVOKE, STAFF_GRANT_EXPIRED,
    STAFF_AGENCY_CREATE, STAFF_AGENCY_FOLLOWER_ADD, STAFF_AGENCY_FOLLOWER_REMOVE,
    STAFF_BAN, STAFF_UNBAN, STAFF_BAN_EXPIRED.
    Fields: adminId (actor; 0 = system/expiry), targetUserId, targetType ('user'|'staff'|'agency'|
    'grant'|'ban'|'setting'), targetId (agency id for agency actions — this is
    target_agency_id), before/after JSON (old_value/new_value), reason, ip (req ip),
    userAgent (device: `x-device-id` header + user-agent).
    Reading: Manager sees rows whose actor or target is in his subtree (incl. himself);
    SA sees himself + his Admins; Admin sees his own. Paginated, newest first, filter by
    actor user id and action.

14. **Money separation is enforced structurally**: the staff router imports nothing that
    moves coins; add a unit test asserting the staff module never references
    `coinsBalance`, `totalRecharge` writes, `chargingAgency.update` on CHARGING, or price
    fields (simple source scan test like coinFreezeWiring.test.ts).

---

## Part C — Existing code to reuse (read before writing)

- Prisma models already added (schema.prisma bottom + migration
  `prisma/migrations/20261004120000_staff_roles/migration.sql`): StaffRole, StaffPermission,
  StaffAgencyScope, TemporaryEntitlement, BanRecord. Client already generated. Do not
  change table names; you may add columns only with a new migration file.
- Auth: `middlewares/auth.middleware.ts` → `authMiddleware` sets `req.userId`.
- Audit: `services/adminAudit.service.ts` → `recordAdminAudit(input)` never throws.
- Bans: `utils/banGuard.ts` (`invalidateBanCache`), `services/socket.service.ts`
  (`kickBannedUser(userId, reason, expiresAt)`), see `controllers/admin.controller.ts`
  `toggleUserBan` for field conventions.
- Socket emit to a user: add `export function emitToUser(userId, event, payload)` in
  socket.service.ts using the module's `_io` (`_io.to(\`user:${userId}\`).emit(...)`).
- Notifications: `services/notification.service.ts` `createNotification({userId,type,title,body,data})`.
- VIP: `services/vip.service.ts` (computeVipLevelWithOverrides, getVipThresholdOverrides,
  grantVipRewardsForRange). Level: `services/xp.service.ts` (calculateLevelWithOverrides,
  getLevelThresholdOverrides, grantLevelRewards). awardUserXP never demotes and evaluateVip
  never demotes — a raised column survives gifts/recharges.
- Items: `services/expiry.service.ts` (item sweep deletes lapsed UserItems every 15 min and
  clears activeFrameId/avatarFrameUrl). UserItem unique (userId,itemId).
- Agencies: `agencies/agency.controller.ts` exports `computeAgencyEarnedCoins`,
  `memberTargetEarned`; `services/broadcast.service.ts` `getBroadcastSeconds`;
  `controllers/adminDashboard.controller.ts` `adminAssignAgency` (pattern to copy, HOSTING only).
- App settings table: `prisma.appSetting` (key/value strings).
- Dashboard: `routes/adminDashboard.routes.ts` (router.use(authenticate) then
  requireAdminDashboard; `requireSuperAdmin` for owner-only), `public/admin-dashboard.html`
  + `public/app.js` (sections via `.nav-item[data-section]`).
- Tests: node:test + ts-node, in-memory fakes, `npm test`
  (`src/**/__tests__/*.test.ts`); keep pure rules in an import-free module so tests don't
  boot the server (see `services/roomStateSnapshot.ts` + its test).
- Style: match surrounding code — explanatory comments on WHY, Arabic user-facing messages,
  `{ success, message, data }` JSON envelopes.

---

## Part D — API contract (`/api/v1/staff`, all behind authMiddleware)

Error envelope: `{ success:false, message:'<Arabic>' , code? }` with 401/403/404/400/409.
Success: `{ success:true, data }`.

- `GET  /me` → `{ role: 'MANAGER'|'SUPER_ADMIN'|'ADMIN'|null, roleId, status, startedAt, expiresAt,
  assignedBy:{id,name,displayId}|null, permissions:[key...], banSystem:bool,
  panels:{ manager:bool, superAdmin:bool, admin:bool, ban:bool }, allowedItemIds:[...],
  rank }`. panels.manager = role MANAGER; panels.superAdmin = role SA && role_panel;
  panels.admin = role ADMIN && role_panel; panels.ban = holds ban_users.
- `GET  /permissions/catalog` → keys with Arabic labels and which roles may hold them.
- `GET  /users/lookup?id=` (id or displayId) → target summary + his active staff role if any.
- Staff management:
  - `GET  /members?status=&role=` → subtree list (الإداريون table).
  - `GET  /members/:roleId` → file: user, role row, permissions (with expiry), allowedItemIds,
    rewardItemIds, agencies in his scope, last 50 audit rows by him.
  - `POST /members` `{ userId|displayId, role:'SUPER_ADMIN'|'ADMIN', days?, permissions?:{key:bool},
    allowedItemIds?, rewardItemIds? }` → appoint.
  - `POST /members/:roleId/extend` `{ days }` (ACTIVE) ; `POST /members/:roleId/renew` `{ days }`
    (EXPIRED/REVOKED → new row).
  - `POST /members/:roleId/revoke` `{ reason? }`.
  - `PUT  /members/:roleId/permissions` `{ permissions: { key: bool }, expiresInDays?: {key: n|null} }`.
  - `PUT  /members/:roleId/allowed-items` `{ itemIds }` ; `PUT /members/:roleId/reward-items` `{ itemIds }`.
- Ban permission for non-staff (Manager only):
  - `GET  /ban-holders` ; `POST /ban-holders` `{ userId|displayId, days? }` ; `DELETE /ban-holders/:userId`.
- Products:
  - `GET  /items/grantable?type=frame|entry|bubble` → items the caller may grant (pool for
    Manager; allowedItemIds for others) `{id,name,type,assetUrl,previewUrl}`.
  - `GET  /items/pool` (Manager) → the dashboard pool, for choosing allowed/reward items.
  - `GET  /config/role-rewards` / `PUT /config/role-rewards` (Manager) `{ MANAGER?, SUPER_ADMIN?, ADMIN? }`.
- Grants:
  - `POST /grants/vip` `{ userId|displayId, level }` ; `POST /grants/level` `{ userId|displayId, level }` ;
    `POST /grants/item` `{ userId|displayId, itemId }`.
  - `GET  /grants?status=` → grants by caller (+subtree for Manager/SA).
  - `POST /grants/:id/revoke` → issuer or any superior in tree.
- Agencies:
  - `GET  /agencies` ; `GET /agencies/:id` ; `POST /agencies` `{ ownerUserId|ownerDisplayId, agencyName }` ;
    `POST /agencies/:id/followers` `{ staffUserId }` ; `DELETE /agencies/:id/followers/:staffUserId`.
- Bans:
  - `POST /bans` `{ userId|displayId, duration, reason }` ; `POST /bans/:userId/unban` ;
    `GET /bans?status=` (own + subtree).
- Audit: `GET /audit?actorId=&action=&page=`.

Dashboard (`/api/v1/admin-dashboard/staff`, dashboard auth; mutations requireSuperAdmin):
- `GET /` all staff (filters) ; `GET /:roleId` (staff file) ; `POST /managers` `{userId|displayId, days}` ;
  `POST /:roleId/extend` `{days}` ; `POST /:roleId/renew` `{days}` ; `POST /:roleId/revoke` `{reason?}` ;
  `POST /:roleId/parent` `{ parentUserId|null }` ;
  `GET/PUT /pool` (staff_grantable_items, body `{itemIds}`) ; `GET/PUT /role-rewards` ; `GET /audit` (all STAFF_* rows) ;
  `GET /grants` ; `GET /bans` ; `GET /ban-holders`.
- Staff whose Manager ended keep their own term with parentUserId null; the dashboard re-attaches
  them with `/:roleId/parent`.

Socket: server emits `staff_access_changed` `{userId}` to `user:<id>`.
