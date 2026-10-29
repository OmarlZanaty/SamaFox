# HANDOFF — agency wallet + branch approval (2026-10-29)

Branch `feat/agency-wallet-20261029`, base 3d7c650 (= what prod runs). Backend only in this worktree.
The app lives on `feat/i18n-2026-10-23` (main checkout) — separate task.

## Client request (Arabic, verbatim intent)
1. Charging agency has its OWN wallet ("رصيد وكالة الشحن خاص بالوكاله فقط"). Selling/charging users comes out of it,
   never out of the personal wallet, so an agent who plays/gifts can't burn his trade stock by mistake.
2. Agent moves coins agency → personal ("هشحن علي محفظتي مليون من وكالتي") to play/gift. ONE-WAY only.
3. Admin dashboard: freeze ALL charging-agency wallets, or freeze one agency by ID.
4. When an owner charges one of his branches he chooses: «إضافة كوينزات وكالة شحن» (branch's agency wallet)
   or «إضافة كوينزات محفظة شخصية» (branch's personal wallet).
4b. (22:40 update) The choice applies to ANY recipient who is a charging agent (OWNER or BRANCH seat of an approved
   CHARGING agency), not only own branches: «شحن وكالة شحن» → their agency wallet, «شحن حساب شخصي» → personal.
   Recipient not a charging agent → personal only (no choice shown; server ignores wallet:'agency').
4c. (22:48 FINAL, client: «الاسهل معاك اعمله») NO choice in the app: a charge to a charging agent goes AUTOMATICALLY
   to his agency wallet; he moves it to personal himself (withdraw). Anyone else → personal wallet. Server ignores `wallet`.
5. Adding a branch (HOSTING and CHARGING) needs the user's قبول/رفض — no branch without consent.

## Owner decisions (2026-10-29)
- Agency wallet starts at 0 for everyone. Personal balances are NOT touched. Admin top-ups go to the agency wallet from now on.
- Each BRANCH has its own agency wallet (not shared with the owner).
- Branch approval ships in the same update.

## Design
- Wallet lives on the seat: `AgencyMember.agencyWalletCoins BigInt @default(0)` (OWNER seat = agency wallet,
  BRANCH seat = that branch's wallet). Do NOT reuse `ChargingAgency.balanceCoins` (holds stale pre-2026-08 values).
- Freeze: `ChargingAgency.walletFrozen Boolean @default(false)` + a global flag in app_settings
  (key `charging_wallets_frozen`, follow how other app_settings flags are read/cached).
  Frozen ⇒ no sale/charge, no agency→personal withdraw, no owner→branch move. Admin top-up still allowed.
  Message: «رصيد الوكالة مجمّد من الإدارة».
- Insufficient agency wallet: 409 «رصيد الوكالة غير كافٍ — المتاح N كوينز».
- Every debit/credit: atomic (`updateMany` with `gte` guard, like the current personal debit) inside one tx,
  plus the existing ledger/transaction rows pattern so the admin can audit.
- Invite for a branch: `AgencyInvite.role String @default("MEMBER")` ('MEMBER' | 'BRANCH'). Accept on a BRANCH invite
  creates/upgrades the BRANCH seat (one-agency rule, MAX_BRANCHES, AgencyBranch row where the charging path needs it).
- Migration: one additive SQL file `backend/prisma/migrations/20261029120000_agency_wallet/migration.sql`
  (prod applies by hand — no data rewrites, defaults only).

## Tasks
- [x] A backend wallet + freeze + withdraw + admin endpoints + tests (883cb2c)
- [x] B backend branch invites (accept/reject) + 4c automatic routing (WIP commit)
- [ ] FAILING: backend/src/agencies/__tests__/branchConsent.test.ts(46,70) TS2345 `Row | undefined` in the upsert fake
      → whole file fails to compile (452/453 pass). Minimal typed fix only. Codex limit until 23:57 2026-10-29.
- [ ] C admin-dashboard.html: wallet column, top-up into agency wallet, freeze one / freeze all
- [ ] D app (feat/i18n branch): show both balances, withdraw button, branch-charge wallet choice, branch invite accept/reject, show server error messages
