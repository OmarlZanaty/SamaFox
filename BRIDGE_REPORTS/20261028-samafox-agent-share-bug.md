STATUS: PARTIAL

**What was requested:** the 20% agent share must go only to the hosts-agency agent (وكيل المضيفين); a person appointed over a hosts-agency branch must not receive it. Money-related, urgent.

**What I did**
- Traced every place the share is computed or credited. The only credit point is `backend/src/gifts/giftService.ts` (every gift/game/lucky path goes through it). It adds 20% of the host's gift to the agency owner's `commissionTargetCoins` (target only, not wallet coins). Reads of it: `agency.controller.ts` (`buildTargetBalance`, `convertTarget`, `sellTarget`, `computeCommissionSplit`), `adminDashboard.controller.ts` roster. All of those read the seat's own column; none of them credit anyone.
- **I could not reproduce "a BRANCH gets 20%" from code.** A فرع of a hosts agency is `AgencyMember.role='BRANCH'` (`agency.controller.ts:addBranch`) and the credit query required `role='OWNER'`, so a pure BRANCH row never receives it. The paths that can produce a second person with the agent's rights are different: admin `adminAssignAgency` / `adminDashboardUpdateAgencyStatus` / staff `agencyCreate` (a user appointed as OWNER of a HOSTING agency), and `transferOwnership` (new OWNER). Any user made OWNER of a hosting agency is, by design, "the agent" and gets 20% on his hosts.
- Hardening (smallest safe change): `backend/src/gifts/agencyCommission.ts` (new) `findAgencyCommissionOwner()`; `giftService.ts` now uses it. The share is paid only if the agency is HOSTING and the recipient is the OWNER seat whose user is the registered agent (`ChargingAgency.userId`). A BRANCH, a member, or a stray second OWNER seat gets nothing; if no such seat exists nobody gets it.
- Test: `backend/src/gifts/__tests__/agentShare.test.ts` (4 cases: agent gets it; BRANCH/member never; stray OWNER seat ignored; charging agency never).
- Audit SQL (read-only, NOT run): `BRIDGE_REPORTS/20261028-samafox-agent-share-bug/audit-wrong-agent-share.sql`.
- Flutter app and admin panel only display/forward values (`agency_bell.dart`, `economy-admin.js`); they compute nothing. No app change.

**How I tested**
- `node --test src/gifts/__tests__/agentShare.test.ts` (Node 24 type stripping): 4/4 pass.
- NOT done: full `npm test`, `tsc`, browser flow, screenshots. The worktree has no `node_modules`, no database and no server, and I was not allowed to link the main checkout's modules. The edit is a drop-in swap of one `findFirst` call, but please run `npm test` and `tsc` before deploy.

**Regression check:** reviewed all other readers/writers of `commissionTargetCoins` / `commissionGeneratedCoins` by grep and reading; unchanged. The helper returns the same seat as before for every normal agency (OWNER seat == `ChargingAgency.userId`).

**Assumptions / things Omar must decide**
1. **The key open question:** who exactly is the person the client "appointed", and how? If it is a real BRANCH (button الفروع inside the agent's panel), the current code already did not pay him and the client's observation probably comes from (a) legacy rows in the DB, (b) the appointee being made OWNER of a new/transferred hosts agency by admin/staff, or (c) him seeing the target card that includes his own hosts' gifts (full value, 0 coins) and reading it as agent share. Ask the client for the appointee's ID and an example gift, then run Q1–Q4 of the SQL.
2. If the client wants "only ONE hosts agency agent, and admin/staff-appointed agents must not get 20%", that is a product rule I cannot infer from code (there is no parent/child link between hosting agencies). Needs a decision, then a small additional change.
3. Strict rule side effect: an agency whose OWNER seat user differs from `ChargingAgency.userId` (data drift) stops accruing until fixed. Q2 finds these before deploy.

**Already-credited wrong amounts:** run the SQL file read-only. Q1 (non-OWNER seats with commission), Q2 (seat/agent mismatch), Q3 (per-user sum from AGENCY_COMMISSION notifications paid to a non-agent), Q4 (all holders on hosting agencies), Q5 (how much was already cashed out via تبديل/بيع). Correcting balances (zero `commissionTargetCoins`, reverse cashed-out coins) needs Omar's approval after seeing results; model on `ops/reverse-charge-target-2026-10-21.sql`.

**Server vs app:** server only. No app build needed.

**Deploy steps (server, after Omar approves; do NOT do now)**
1. Merge/cherry-pick branch `bridge/20261028-samafox-agent-share-bug` (2 backend source files + 1 test).
2. In `backend`: `npm ci && npx tsc --noEmit && npm test` must pass.
3. Run the audit SQL read-only; review Q2 first (fix any seat/agent drift or expect those agencies to stop accruing).
4. `ops/deploy-backend.sh` in the night window (dist-only deploy, no migration needed, no schema change).
5. Verify: send a test gift to a host in a hosting agency; owner's `commissionTargetCoins` rises by 20%, BRANCH seat's stays 0.
6. Rollback: redeploy previous dist.

**Earlier pending SamaFox requests (status only, not implemented, not investigated in depth)**
- Double tag x2/x8: git history shows fruit wheel was set "back to ×2/×8 with the crown" (commit 8393bb1); the duplicate tag was not checked.
- Square centered games in the room: app-side layout, not checked.
- No max cap on bet amount: server games each have `maxBet` config (`gameConfig.service.ts` and per-game services), so removing it is a per-game config/code change. Not checked in detail.

**Risks before sending to the client:** the exact leak was not reproduced; this change may not alter what the client saw. Do not tell the client it is fixed until the DB check (Q1–Q4) shows what happened.

**Short message draft for the client**
راجعنا الموضوع وهنأكد إن نسبة الوكيل 20% تروح لوكيل المضيفين المسجل بس ومفيش حد غيره ياخدها. محتاجين منك رقم ID الشخص اللي اتعين وهدية مثال عشان نتأكد من الحالة بالظبط. وهنراجع الحسابات القديمة ونصلحها لو لقينا حاجة غلط.
