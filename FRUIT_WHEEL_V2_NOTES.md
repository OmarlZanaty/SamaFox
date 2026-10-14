# Fruit Wheel v2 — review notes

Implemented the shared table by adapting Car Wheel: 30s betting → 1s closing → 6s spinning → 5s results, including idle rounds. The new client keeps the existing artwork/layout, shows the hub countdown and last-five-second red pulse/ticks, and uses immediate server-side chips, undo, clear and repeat. It includes top-three winners plus viewer bet/win, ten recent results, daily ranking, history, reconnect recovery and Arabic-first rules. “77” pays ×8; crown is a losing result, with no bonus/orb flow.

The committed draw weights are watermelon 3500, plum 3500, sevens 875 and crown 2125. Each card returns 70%. Both client and server enforce two cards and a per-card dashboard max (1,000,000 fallback). Money follows the existing helper path: transactional charge/chip rows, per-player locks, maximum-outcome reservation, grantStakeValue at close, pool-only payPrize/releasePrize at settlement, and open-chip refunds on boot. History stores actual paid amounts, including dashboard caps.

## Manual migration / deployment order

Apply `backend/prisma/migrations/20261014000000_fruit_wheel_shared/migration.sql` by hand **before starting the updated backend**, then regenerate Prisma Client (`npx prisma generate`). This adds `fruit_wheel_shared_rounds` and `fruit_wheel_stakes`; it does not modify the legacy table. The user foreign key is declared in SQL; the existing Prisma User model is untouched to honor the new-models-only scope. The engine refuses startup if boot recovery fails. Like Car Wheel, run one authoritative engine process.

No migration was applied, no production access, no builds, no commits. Existing legacy service/math and all legacy endpoints remain unchanged.

## API

Under `/games/fruitwheel/shared`: GET `state`, `history`, `ranking`; POST `bet` (`key`, `amount`), `undo`, `clear`, `repeat`. Mutations use the existing authenticated/idempotent middleware. Keeping the new namespace preserves installed clients’ state/history/spin contracts.

Socket events: `fruitwheel_join_table`, `fruitwheel_leave_table`, `fruitwheel_state`, `fruitwheel_result`. Subscription handlers live in the new service, leaving the shared socket service untouched. State supplies server-selected `segment`/`offset` and a process `tableId` for reconnects after idle round numbers reset. Public broadcasts omit private stakes/payouts; REST supplies them.

## Validation / remaining checks

- `npx tsc --noEmit`: passed; Prisma Client generation passed.
- `npm test`: sandbox blocks Node test-worker creation (`spawn EPERM`). All 27 test files passed when run separately with `node --require ./scripts/test-env.js --require ts-node/register/transpile-only <file>`; TypeScript was checked separately. The new suite now has 22 passing tests, including close/charge races, pool accounting, caps, two-card limits and idle rounds. Existing Fruit Wheel and Car Wheel suites passed.
- `node --require ts-node/register scripts/fruit-wheel-round-sim.ts`: 2M rounds; watermelon **69.920%**, plum **69.904%**, 77 **70.233%** RTP.
- Flutter CLI analysis/test could not complete in this sandbox: SDK cache lock access is denied; a temporary writable cache mirror gets as far as the test compiler, whose child-process launch is also denied. Direct SDK analysis-server checks finished with **zero issues in all Fruit Wheel Dart files**, including the preview and tests. The broader requested directories have 836 existing diagnostics in unrelated files.
- **Claude still needs to run the requested Flutter analyze/test commands and visually check countdown sound/pulse, a full shared round, reconnect, and the winners popup on a device.** Nine client tests are supplied, but their runtime pass status is unverified here. No application build was run.
