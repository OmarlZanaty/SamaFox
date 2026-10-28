# BRIDGE_LOG / CHANGES

## 2026-10-28 — job 20261028-samafox-agent-share-bug — client SamaFox
- **Request:** the 20% agent share (نسبة وكيل) must go only to the hosts-agency agent; a person appointed over a hosts-agency branch must not get it.
- **Root cause:** NOT reproduced by reading code. Every credit path (`gifts/giftService.ts`) pays the 20% only to a seat with `role='OWNER'`; a BRANCH row never receives it. The owner lookup was unordered `findFirst({agencyId, role:'OWNER'})` and did not check the agency type or that the seat belongs to the registered agent (`ChargingAgency.userId`), so a second/stray OWNER seat (e.g. an appointee made OWNER by an admin/staff/ownership-transfer path) would have taken it. Hardened to the registered agent only.
- **Files:** `backend/src/gifts/agencyCommission.ts` (new), `backend/src/gifts/giftService.ts`, `backend/src/gifts/__tests__/agentShare.test.ts` (new), `BRIDGE_REPORTS/20261028-samafox-agent-share-bug/audit-wrong-agent-share.sql` (new, read-only audit).
- **Tested:** 4 unit tests via `node --test` (pass). Full backend suite / tsc / browser NOT run: worktree has no node_modules and no DB.
- **Result:** PARTIAL.
