# Batch C1 — Host agencies, charging-agency branches, Google ↔ phone linking
Spec items: 35, 36, 37. Read `docs/spec52/RULES.md` first, then AUDIT.md sections 35, 36, 37.
Migration dir: `backend/prisma/migrations/20261020000020_agencies_branches_phone_link/`.
Already done on this branch (reuse, don't redo): `requireOwnerPermission(perm)` in
`backend/src/services/ownerPermissions.service.ts` (perms `finance.charging_agency`, …) and
`recordAdminAuditStrict(tx, …)` in `adminAudit.service.ts` (AUDIT_ACTIONS has
`AGENCY_PROFILE_UPDATE`). Dashboard pages can be added through `backend/public/spec52-admin.js`
(`window.spec52Register('<section>', loaderFn)` + a `<section id="section-<name>">` and nav item in
`admin-dashboard.html`).

## 35 — Host agency name/image + invitation state machine
- Agency owner (and dashboard admins) can change Agency Name and Agency Image.
  New table `agency_profile_changes` (id, agencyId, field 'name'|'image', oldValue, newValue,
  changedBy, changedAt) + AdminAuditLog row (AGENCY_PROFILE_UPDATE) for dashboard edits. Respect
  the existing `nameLocked` (owner can't rename a locked agency; dashboard can).
  Routes: `PATCH /api/v1/agencies/:id/profile {agencyName?, agencyImageUrl?}` (owner of that
  agency only), dashboard `PATCH /api/v1/admin-dashboard/agencies/:id` extended with image.
  `GET /api/v1/agencies/:id/profile-history` (owner + admins).
- Invitations: `AgencyInvite` statuses pending/accepted/rejected/expired/cancelled. Remove the
  `@@unique([agencyId, inviteeId])` WITHOUT deleting rows (migration drops that unique index,
  adds a non-unique index and a partial unique index `WHERE status='pending'`). Each invite has its
  own id. rejected/expired/cancelled → a NEW row can be created. pending → no second row; the API
  returns `{ status:'pending', canResend:true, inviteId }` and a `POST /agencies/invites/:id/resend`
  re-sends (bump `resentAt`/`resendCount`, re-notify, extend expiry). `POST
  /agencies/invites/:id/cancel` (inviter/owner). Expire lazily on read and in the existing expiry
  job. Accept/reject keep the current guarded logic (single hosting agency etc.). Fix the old
  "Error after rejected then re-invite" path.
- Flutter: `app/lib/services/agency_service.dart`, `screens/my_agencies_screen.dart` /
  agency panel: edit name/image for the owner (image via existing upload endpoint), invite flow
  shows "إعادة إرسال" for pending, and a cancel action. Arabic messages.

## 36 — Charging agency branches
- New model `AgencyBranch` (table `agency_branches`): id, parentAgencyId (ChargingAgency),
  name, ownerUserId, status ACTIVE|SUSPENDED|CLOSED, createdAt, updatedAt. Backfill one branch per
  existing `AgencyMember role='BRANCH'` row (name = user name, owner = that user), idempotently.
  Keep the existing BRANCH membership logic working (cap 3 can stay).
- Every charge (agent→user coin transfer, both code paths `agency.controller.ts::sendCoinsToUser`
  and `charging-agency.controller.ts::agencyTransferCoins`, and top-up requests) records:
  parentAgencyId, branchId (null when the owner charges), actor userId, target userId, amount,
  coins, timestamp, transactionId (the `Transaction` row id). Add nullable `branchId`,
  `actorUserId`, `transactionId` columns to `AgencyTransfer` (and `branchId` to
  `AgencyTopupRequest`). Branch is resolved from the authenticated membership — never from the
  request body.
- Isolation: a branch owner sees only their branch's transfers/stats; the parent owner sees all
  branches (filter by branch); sibling branches never see each other. Enforce in
  `myAgencyTransfers` and any agency stats/list endpoint. Routes: `GET /agencies/:id/branches`,
  `POST /agencies/:id/branches {name, ownerUserId}` (parent owner), `PATCH
  /agencies/:id/branches/:branchId {name?, status?}`, `GET /agencies/:id/branches/:branchId/transfers`.
  Audit branch create/status changes. Dashboard: branch list per charging agency (read-only list +
  status change for owners with `finance.charging_agency`).
- Flutter `charging_agent_screen.dart`: branch selector/list for the parent owner, branch badge on
  transfers. Do not move balances: branches keep using their own agent wallets as today.

## 37 — Link phone number to a Google account
- New model `UserAuthMethod` (table `user_auth_methods`): id, userId, provider ('google'|'phone'|
  'email'|'facebook'), providerUserId?, phoneNumber?, verified, createdAt. Unique
  (provider, providerUserId) and unique phoneNumber (partial: where phoneNumber is not null).
  Backfill google rows from `users.googleId` (verified=true). Do NOT mark existing `users.phone`
  as verified (no backfill of phone rows).
- OTP: model `PhoneOtpChallenge` (table `phone_otp_challenges`): id, userId, phoneNumber, codeHash
  (sha256 + per-row salt), expiresAt (5 min), attempts (max 5), consumedAt, createdAt. Rate
  limit: max 3 sends / 10 min per user and per number, 60 s cooldown.
  SMS provider abstraction `backend/src/services/sms.service.ts`: if `TWILIO_ACCOUNT_SID`,
  `TWILIO_AUTH_TOKEN`, `TWILIO_VERIFY_SERVICE_SID` are set → use Twilio Verify REST API via fetch
  (no new npm dependency); else if NODE_ENV !== 'production' → log the code and also return it as
  `devCode` in the response; else → 503 "خدمة رسائل التحقق غير مفعّلة حالياً".
- Routes (auth required): `POST /api/v1/auth/phone/send-otp {phone}`,
  `POST /api/v1/auth/phone/verify {phone, code}`. Normalize to E.164 (default country from
  user.countryCode, Egypt +20 fallback). Verify runs in ONE Serializable transaction: check the
  number isn't linked to another user (users.phone or user_auth_methods) → error 409
  "هذا الرقم مرتبط بحساب آخر."; insert/upsert the phone auth method for THIS user, set
  users.phone, consume the challenge. Never create a new account. Remove phone changes from the
  generic `PUT /users/me` (ignore `phone` there, keep backward compatibility silently).
- Flutter: Settings → الحساب → "ربط رقم الهاتف" screen (enter number → send OTP → enter code →
  verify), shows linked number when done, Arabic errors, resend countdown 60s.

Notes file: `docs/spec52/notes-C1.md`.
