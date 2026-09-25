# CP system — current-state analysis and design for "CP permissions & admin"

Date: 2026-09-22 · Branch: `feat/cp-permissions-admin`

This document was written BEFORE any code was changed, as the spec demands
("قبل تنفيذ التعديلات، يجب مراجعة طريقة عمل نظام CP الحالي وتحديد مصدر
البيانات الذي يعتمد عليه العرض"). Part 1 is the trace of what exists today with
file paths and line numbers (as of commit `07143fc` on `main`). Part 2 is the
design that the implementation on this branch follows.

---

## Part 1 — What exists today

### 1.1 Stack

| Layer | Technology | Where |
|---|---|---|
| Backend | Node 24 · TypeScript · Express 5 · Socket.io 4 | `backend/src/index.ts` |
| DB | PostgreSQL via Prisma 6.17 (`schema.prisma`, SQL migrations under `backend/prisma/migrations/`) | `backend/prisma/schema.prisma` |
| Auth | JWT bearer (or `access_token` cookie) → `req.userId` | `backend/src/middlewares/auth.middleware.ts:31-72` |
| Admin gate | `User.isAdmin` / `User.isSuperAdmin` booleans on the `users` row | `backend/src/middlewares/admin.middleware.ts:8-27`, `adminDashboard.middleware.ts:4-19` |
| Admin panel | A static vanilla-JS single page served by Express: `backend/public/admin-dashboard.html` (1438 lines) + `backend/public/app.js` (3174 lines); talks to `/api/v1/admin-dashboard/*` and `/api/v1/admin-products/*` | `backend/src/routes/adminDashboard.routes.ts`, `adminProduct.routes.ts` |
| Mobile app | Flutter (Dart), Dio HTTP client, Riverpod, SharedPreferences | `app/lib/` |
| Tests | Flutter has a few widget/render tests in `app/test/`. The backend has NO test runner (no jest/vitest/mocha in `backend/package.json`). | |
| Audit today | Only gifts have an audit table: `GiftAdminAudit` + `recordGiftAudit()` (`backend/src/gifts/audit.ts`). Everything else on the dashboard is unaudited. | `schema.prisma:1303-1316` |

There is a second, older admin gate (`adminProduct.routes.ts:9-20`) that
duplicates `adminMiddleware` inline; both check `isAdmin` server-side.

### 1.2 What "CP" means in this app

Two unrelated things share the letters "CP" (the schema itself warns about it,
`schema.prisma:1371-1374`):

1. **Account power** — `User.cpPoints` (`schema.prisma:33`) and
   `Gift.cpEligible` (`schema.prisma:1234`), incremented in
   `sendGiftAtomic` (`backend/src/gifts/giftService.ts:103-115`) using the
   `cp_per_coin` app setting. Legacy, not the feature the client talks about.
2. **CP = Couple Pairing (نظام الـ CP / العلاقة)** — the client's feature
   (spec quoted verbatim in `backend/src/services/cp.service.ts:6-24`). This
   is what this task is about. A pair is two users bonded by a CP gift that
   the other side accepted, shown on the profile as a heart-framed card.

### 1.3 Data model (DB)

| Model / table | Purpose | File:line |
|---|---|---|
| `CpPair` → `cp_pairs` | One row per pair, `userAId < userBId` (unique), `giftId` of the gift that created it, `createdAt`. **No level, no value, no "featured" flag.** | `schema.prisma:1386-1402` |
| `CpRequest` → `cp_requests` | Pending/accepted/rejected/cancelled invitations; `totalCoins` snapshotted at request time. | `schema.prisma:1404-1424` |
| `Gift.category = 'cp'` | A gift is a "CP gift" purely because its category key is `cp` (seeded in migration `20260825000000`, `gift_categories` row `cat_cp`). | `backend/prisma/migrations/20260825000000_cp_categories_supporters_reset/migration.sql:41` |
| `User.coinsBalance` | The only coin wallet. `Int`. | `schema.prisma:27` |
| `Transaction` | Ledger rows (`type`, `amountCoins`, `status`). CP writes `CP_REJECT_FEE` here. | `schema.prisma:363-384` |
| `AppSetting` | Key/value settings the dashboard edits (`cp_per_coin`, forced-update keys, …). | `schema.prisma:648-654`, `backend/src/controllers/settings.controller.ts:5-27` |

### 1.4 Backend flow (API)

Routes are mounted at `/api/v1/cp` (`backend/src/index.ts:208`) from
`backend/src/routes/cp.routes.ts`:

| Endpoint | Handler | Behaviour |
|---|---|---|
| `POST /cp/requests` | `createCpRequest` (`cp.service.ts:49-121`) | Validates gift (must be active), recipient, sender balance ≥ price (**verified, not charged**), no existing pair, one open request per direction → creates `CpRequest`, notifies recipient (`cp_request`). |
| `GET /cp/requests/pending` | `listPendingCpRequests` (`cp.service.ts:353-377`) | Recipient's inbox, includes `rejectFeeCoins` (30 %). |
| `POST /cp/requests/:id/accept` | `acceptCpRequest` (`cp.service.ts:136-221`) | Runs the normal `sendGiftAtomic` (full price off sender, credit to recipient/target), upserts `CpPair`, marks request accepted, emits `gift:sent` + announcement, notifies sender. |
| `POST /cp/requests/:id/reject` | `rejectCpRequest` (`cp.service.ts:228-274`) | Guarded decrement of 30 % of `totalCoins` from the sender (`updateMany where coinsBalance >= fee`), `Transaction(type=CP_REJECT_FEE)`. |
| `DELETE /cp/requests/:id` | `cancelCpRequest` | Sender withdraws, no charge. |
| `GET /cp/partners` / `GET /cp/partners/:userId` | `listCpPartners` (`cp.service.ts:292-326`) | Every pair of a user with partner summary + the creating gift (icon/animation). **This is the data source of the profile CP display.** `/partners/:userId` is public (no auth). |
| `DELETE /cp/partners/:userId` | `removeCpPair` | Deletes the pair, notifies the partner. |

**There is no "unlock/open CP" step today**: any user can send a CP gift as
long as they can afford it. There is no per-user permission, no fee to open
CP, and no admin endpoint that touches `cp_pairs` or `cp_requests`.

Coins are only moved by `sendGiftAtomic` (Serializable transaction, guarded
`updateMany` decrement — `giftService.ts:91-302`) and by the reject fee.

### 1.5 Display in the Flutter app — and its data source

| Surface | Widget | Data source |
|---|---|---|
| Profile header hearts (me ♥ partner + "CP" pill) | `_CpProfileCard` in `app/lib/screens/profile_screen.dart:2391-2480` → `CpHeartPair` (`app/lib/widgets/cp_relationship.dart:154-216`) | `CpRepository().partners(userId)` → `GET /cp/partners/:userId`, then `CpFeatured.pick(...)` |
| Profile "العلاقة" card (avatars, tier name, `LV.n`, days) | `_CpRelationshipSection` (`profile_screen.dart:2330-2389`) → `CpRelationshipCard` (`cp_relationship.dart:219-410`) | same list + `CpFeatured` |
| Home-page CP box | `app/lib/widgets/cp_box.dart` | `GET /cp/partners` |
| CP list (cancel, choose featured) | `app/lib/screens/cp_list_screen.dart` | `GET /cp/partners[/:id]`, `DELETE /cp/partners/:id` |
| Sending a CP gift | `gift_picker_sheet.dart:129-132, 502, 709-752` — a gift whose `category == 'cp'` goes to `POST /cp/requests` instead of the normal send. | |
| Incoming request dialog | `app/lib/main.dart:100-130` + `cp_request_dialog.dart` | socket `notification:new` of type `cp_request` |

Two findings that matter for the spec:

* **The "featured" CP partner (مستخدم CP الظاهر) is NOT stored on the server.**
  `CpFeatured` (`app/lib/repositories/cp_repository.dart:187-221`) keeps the
  chosen partner id in `SharedPreferences` on the device. Consequences: an
  admin cannot set or see it; it is lost on reinstall; and because the same
  device key is read on *every* profile (`profile_screen.dart:2370, 2467`), a
  visitor's own preference is applied to other people's pages.
* **The CP level is NOT stored on the server either.** `CpTier.forDays()`
  (`cp_relationship.dart:21-50`) derives `LV.1..LV.5` and the tier name purely
  from `days since CpPair.createdAt` on the client. Gifts do not raise it; there
  is no admin control over it; and it cannot be trusted because it is computed
  on the device.

### 1.6 Backgrounds (الخلفيات) today

Backgrounds are ordinary **store items** with `Item.type = 'PROFILE_BACKGROUND'`
(the dashboard's select value `profile_background` is mapped at
`backend/src/controllers/adminProduct.controller.ts:115-117`).

| Concern | Where |
|---|---|
| Catalogue (add / edit / delete / price / free-or-paid) | `adminProduct.controller.ts` — `createProduct` (price via `price_coins`, private store via `is_private`), `setProductVisibility` (PATCH: name, price, `is_private`, duration), `deleteProduct` (cascades: clears `users.profileBgUrl` matching the asset, deletes `user_items`). Routes: `adminProduct.routes.ts:39-48`, all behind `isAdmin`. |
| Ownership | `UserItem` (`userId`,`itemId`, `expiresAt`, `isActive`) — `schema.prisma:780-798`. |
| Purchase | `POST /store/buy` (`backend/src/routes/store.routes.ts:19-101`) — transaction, balance check, decrement, `userItem.create`. |
| Admin grant | `POST /admin-products/grant` (`adminProduct.controller.ts:265-368`) by `displayId` or to everyone. **No revoke endpoint exists.** No audit row. |
| Equip | `POST /store/activate` mirrors the asset onto `users.profileBgUrl/profileBgType` (`store.routes.ts:245-297`) — the profile is painted from the USER row (`profile_screen.dart:1095-1103`), never from the inventory. |
| Per-user list | `GET /store/inventory` for the caller only; the dashboard has no "what does user X own" view. |
| **Hole:** `PUT /users/me` accepts an arbitrary `profileBgUrl` (`backend/src/controllers/user.controller.ts:164-205`) — intended for a self-uploaded picture, but nothing checks that the URL is not a paid store asset, so the app can equip a background it does not own. |

Free vs paid today = `priceCoins == 0` vs `> 0`; there is no explicit flag.

### 1.7 Coins

`User.coinsBalance` is decremented only inside Prisma transactions with a
guarded `updateMany({ where: { coinsBalance: { gte: amount } } })`
(`giftService.ts`, `store.routes.ts:45-49`, `cp.service.ts:237-240`). No app
endpoint lets a user set their own balance. Admin top-ups go through agencies
(`adminTopupAgency`, `adminDashboardReviewTopupRequest`).

### 1.8 Existing admin/audit mechanisms

* Dashboard auth: `/api/v1/admin-dashboard-auth` (login → JWT); every
  `/admin-dashboard/*` route runs `authenticate` + `requireAdminDashboard`
  (`adminDashboard.routes.ts:100-101`).
* Super-admin only for roster changes and the global target-sell freeze.
* Audit: `GiftAdminAudit` only. No generic audit log.
* Settings: `PATCH /admin-dashboard/settings` upserts `AppSetting` rows
  (`settings.controller.ts:76-97`).
* Dashboard "Settings" section already has a "CP/target" card that edits the
  *account-power* keys — not the couple feature.

---

## Part 2 — Design

### 2.1 Interpretation of the spec

* **"فتح CP"** = *unlocking the CP feature on an account*: the right to send a
  CP invitation (and thereby create a pair). Today it is implicitly free for
  everyone. After this change every `POST /cp/requests` is gated by a
  server-side check `resolveCpUnlockPolicy(userId)`:
  1. a per-user grant (`cp_unlock_grants`, one active row per user) wins:
     `mode = FREE` → no fee, `mode = FEE` → its `feeCoins`;
  2. otherwise the system policy in `AppSetting`:
     `cp_unlock_mode` = `free` | `fee` (default **`free`**, so nothing changes
     for existing users until an admin decides), `cp_unlock_fee_coins`
     (default `0`).
  3. If a fee applies and the user has not yet paid it, the app must call
     `GET /cp/unlock/status` (returns the fee and the balance so it can be
     shown *before* confirmation) and then `POST /cp/unlock/confirm`, which
     deducts the fee atomically, writes a `Transaction(type=CP_UNLOCK_FEE)` and
     a `cp_unlocks` row. Insufficient balance → HTTP 402 with `shortfall`,
     nothing deducted. Free → `POST /cp/unlock/confirm` records the unlock at
     zero cost.
  4. `POST /cp/requests` returns `403 CP_LOCKED` (with the fee) when the
     user is not unlocked, so the check is enforced on the server no matter
     what the app does.
* Users who **already have a CP pair** are treated as unlocked (the migration
  backfills a `cp_unlocks` row with `source = 'legacy'`, `paidCoins = 0`) so
  no existing pair or level is lost.
* The cut-off sentence "بعد موافقة…" is implemented as: after the user
  confirms, coins are deducted atomically, CP is opened, a transaction is
  recorded; on insufficient balance the shortfall is shown and nothing moves.
* **"تحديد مستخدم CP الظاهر"** moves from the device to the server:
  `User.cpFeaturedPartnerId`. The user can still set it from the app
  (`PATCH /cp/featured`), the admin can set/clear it from the dashboard, and
  visitors see the *owner's* choice.
* **CP level** moves to the server: `CpPair.cpValue` (coins exchanged between
  the two partners, starting with the accepting gift) + `CpPair.levelOverride`
  (admin). Level is computed by `computeCpLevel()` from `cp_level_step_coins`
  ("قيمة رفع مستوى CP"). Default `0` = keep today's days-based ladder, so the
  visible level of every existing pair is unchanged until the admin sets a
  value. `listCpPartners` now returns `level`, `levelName`, `cpValue`, `days`
  and the app prefers the server value.
* **"إدارة هدايا CP"** = the gifts whose `category = 'cp'`. The panel lists
  them and allows toggling active / editing price through the existing gift
  admin endpoints (`adminUpdateGift`), now recorded in the new audit log too.
* **Backgrounds** = `Item.type = 'PROFILE_BACKGROUND'`. Add / edit / delete /
  free-or-paid / price already exist; this branch adds a dedicated panel, an
  explicit `isFree` toggle (price 0), grant, **revoke**, and a per-user
  ownership list — all audited.
* **Security** — new `admin_audit_logs` table written by every admin action
  above (who, action, target user, before/after, timestamp, IP). App-side
  endpoints cannot change ownership, coins, `cpValue`, level or the unlock
  state except through the paid flows. `PUT /users/me` refuses a
  `profileBgUrl` that equals a store asset the caller does not own.

### 2.2 Schema changes (all additive; migration `20260922000000_cp_permissions_admin`)

```prisma
model CpUnlockGrant {        // "فتح CP مجانًا" / "فتح CP برسوم" per user
  id          Int      @id @default(autoincrement())
  userId      Int      @unique             // one live grant per user
  mode        String                       // FREE | FEE
  feeCoins    Int      @default(0)
  note        String?
  grantedById Int
  grantedAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}
model CpUnlockGrantHistory { // every grant / change / revoke, never deleted
  id, userId, mode, feeCoins, action (GRANT|UPDATE|REVOKE), adminId, createdAt
}
model CpUnlock {             // the account has opened CP
  id, userId @unique, paidCoins, source (free_policy|fee_policy|grant_free|grant_fee|admin|legacy),
  transactionId Int?, grantedById Int?, createdAt
}
model AdminAuditLog {        // generic audit for every admin action on this branch
  id, adminId, action, targetUserId?, targetType?, targetId?, before Json?, after Json?, ip?, createdAt
}
User  += cpFeaturedPartnerId Int?
CpPair += cpValue Int @default(0), levelOverride Int?, updatedAt
AppSetting keys: cp_unlock_mode, cp_unlock_fee_coins, cp_level_step_coins, cp_level_max, cp_level_names
```

Migration strategy:

* `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` with defaults — no existing row
  is rewritten, `user_items` (background ownership) is untouched.
* Backfill `cp_pairs.cpValue` from the accepting `cp_requests.totalCoins`
  (best effort; 0 when unknown). With `cp_level_step_coins = 0` the level is
  still days-based, so no user sees a different level after deploy.
* Backfill `cp_unlocks` for every user that appears in `cp_pairs` or has an
  accepted `cp_requests` row (`source = 'legacy'`).
* Default policy `cp_unlock_mode = free` — behaviour identical to today until
  an admin changes it.

### 2.3 Endpoints

App (all `authMiddleware`):

| Method | Path | Purpose |
|---|---|---|
| GET | `/cp/unlock/status` | `{ unlocked, mode, feeCoins, balance, shortfall, source }` — the fee shown before confirmation. |
| POST | `/cp/unlock/confirm` | Deduct (if fee) + open. 402 `INSUFFICIENT_COINS` with `shortfall`. Idempotent when already unlocked. |
| PATCH | `/cp/featured` | `{ partnerId | null }` — must be an existing partner. |
| POST | `/cp/requests` | now returns 403 `CP_LOCKED` + fee when not unlocked. |
| GET | `/cp/partners[/:id]` | now includes `level`, `levelName`, `cpValue`, `days`, `featured`. |

Dashboard (`authenticate` + `requireAdminDashboard`, mounted at
`/api/v1/admin-dashboard/cp/...` and `/api/v1/admin-dashboard/backgrounds/...`):

| Method | Path | Purpose |
|---|---|---|
| GET | `/cp/policy` · PATCH `/cp/policy` | system unlock mode / fee, level step, max, names |
| GET | `/cp/grants` · POST `/cp/grants` · DELETE `/cp/grants/:userId` | list / grant (FREE or FEE+coins, by displayId or id) / revoke |
| GET | `/cp/users/:id` | everything CP about one user: unlock state, grant, pairs (with level/value), featured, pending requests |
| POST | `/cp/users/:id/unlock` | admin opens CP for free (source `admin`) |
| DELETE | `/cp/users/:id/unlock` | admin closes CP again (does not delete pairs) |
| PATCH | `/cp/users/:id/featured` | set/clear the featured partner |
| PATCH | `/cp/pairs/:pairId` | set `cpValue` / `levelOverride` |
| DELETE | `/cp/pairs/:pairId` | dissolve a pair |
| GET | `/cp/gifts` · PATCH `/cp/gifts/:id` | CP-category gifts: active / price / order |
| GET | `/cp/audit` | audit log, filterable by user / action |
| GET | `/backgrounds` · POST · PATCH `/:id` · DELETE `/:id` | catalogue (multipart upload for POST) |
| POST | `/backgrounds/:id/grant` · POST `/backgrounds/:id/revoke` | ownership by displayId / id |
| GET | `/backgrounds/users/:id` | backgrounds owned by a user |

### 2.4 Audit log shape

`admin_audit_logs(adminId, action, targetUserId, targetType, targetId, before, after, ip, createdAt)`
written through `recordAdminAudit()` (`backend/src/services/adminAudit.service.ts`),
never throws (a failed audit must not break the action — same rule as
`recordGiftAudit`). Actions are string constants like `CP_GRANT_FREE`,
`CP_GRANT_FEE`, `CP_GRANT_REVOKE`, `CP_POLICY_UPDATE`, `CP_UNLOCK_ADMIN`,
`CP_LOCK_ADMIN`, `CP_FEATURED_SET`, `CP_PAIR_UPDATE`, `CP_PAIR_DELETE`,
`CP_GIFT_UPDATE`, `BG_CREATE`, `BG_UPDATE`, `BG_DELETE`, `BG_GRANT`, `BG_REVOKE`.

### 2.5 Tests

`backend/src/cp/__tests__/*.test.ts` run with Node's built-in `node:test`
through `ts-node/register` (`npm test`). The services take their Prisma client
as an injectable dependency so the tests use an in-memory fake and need no
database.
