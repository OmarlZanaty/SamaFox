# Hotfix — charging no longer credits the charging agent's target

Client rule (confirmed 2026-10-21, replaces our earlier reading of "B6"):
> تارجيت وكيل الشحن: لما يترمي عليه كوينزات تنزل في التارجيت بقيمتها الحقيقيه فقط بدون نسبة وكيل
> وتسمع معاه قيمتها بالدولار. لو اشتري تارجيت ينزل عنده في التارجيت وقيمته بالدولار.

So a charging agent's (وكيل شحن / فرع) target is fed ONLY by:
1. gifts received (full value, no agency commission on top) — already how memberTargetEarnedRaw works;
2. target he buys (sale_in movements) — already works.
Charging a user (selling coins) must NOT add anything to his target. Today it does, at face value,
in TWO places:
- `backend/src/agencies/agency.controller.ts` — sendCoinsToUser: the block commented "B6 — charging
  credits the seller's TARGET" (agencyMember.update targetAdjustmentCoins increment + recordTargetMovement kind 'charge').
- `backend/src/controllers/charging-agency.controller.ts` — agencyTransferCoins: the block commented
  "B6 — وكيل الشحن لما يشحن حد ينزله تارجيت" (sellerMembership lookup + update + recordTargetMovement kind 'charge').

## Do
- Remove both target-credit blocks (keep everything else in those transactions: wallet debit, stats,
  recipient credit, Transaction row, notifications). Replace each with a short comment stating the
  client rule above and the date 2026-10-21 so nobody re-adds it.
- Keep `'charge'` in the TargetMovementKind type (historical rows use it) and keep the dashboard able
  to display old 'charge' rows; add `'charge_reversal'` as a new kind (used by the script below).
- Add a script `backend/src/tools/reverseChargeTarget.ts` (compiled to dist/tools, run with node):
  - finds every target_movements row with kind 'charge' that has no matching reversal;
  - dry run by default: prints userId, displayId, name, memberId, agency, coins per member and totals;
  - with `--apply`: in ONE transaction per member, decrement AgencyMember.targetAdjustmentCoins by the
    sum of its charge movements and insert one target_movements row kind 'charge_reversal',
    amountCoins = -sum, actorId = the admin id passed as `--admin <id>` (required with --apply),
    note 'إلغاء تارجت الشحن (قاعدة العميل 2026-10-21)'; idempotent (a member that already has a
    charge_reversal covering those movements is skipped).
  - import ONLY prisma and small helpers — never anything that reaches src/index.ts (that boots a
    second server).
- Update any backend test that asserted charging credits the target so it now asserts it does NOT.
- Must compile with `npx tsc` and `npm test` must pass (you cannot run them; the reviewer will).
- UTF-8 Arabic only; use apply_patch; no `????`.
