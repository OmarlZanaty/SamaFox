# Fruit Wheel bonus rounds

Implemented for the shared Fruit Wheel table. The legacy single-player engine is unchanged.

## Timing and funding

- Defaults: bonus enabled, every 20 occupied rounds, triple threshold 15,000,000 coins.
- The spec's prose says a bonus follows N settled rounds, but its explicit test requirement says the Nth player round. This implementation follows the test requirement: rounds 20, 40, etc. are due by default. `roundsToBonus` starts at 19, reaches 0 for the due round, and resets on the following round.
- Only settled rounds with positive stakes advance the counter. Empty/fully cleared rounds do not consume a due bonus. The counter starts at zero on process boot. A due round downgraded for funding still consumes that scheduled bonus. Disabled rounds remain plain; occupied rounds still count.
- Settings are snapshotted at the start of each round, so dashboard changes apply to the next round without changing an open round's countdown.
- The primary weighted result and wheel landing are unchanged. Double uses the full SHA-256 hash of `seed:roundNumber:bonus` modulo two to select one other card, in segment-table order. Triple includes all three cards, primary first.
- Triple eligibility uses free pool balance after stake splitting and subtracts all outstanding reservations for the game, including reservations from other engines.
- Each player's extra reservation is the summed payout minus `min(existing reserved, primary payout)`. Reservations use the existing game/stake/cap rules. Each failed attempt releases every extra it acquired before retrying triple -> double -> plain. A pool-read error safely leaves a plain round.
- Settlement sums `payoutFor` for the winning set and pays through the existing pooled-token `payPrize`. Round/daily/ratio caps, ledgers, winners, daily statistics, and actual credited payouts retain their existing behavior. No new coin credit path was introduced. The 70% base-card return excludes additional bonus wins.

## Settings and API compatibility

`game_config.fruitwheel` gains:

| Field | Default | Validation |
| --- | --- | --- |
| `bonusEnabled` | `true` | Boolean |
| `bonusEveryRounds` | `20` | Integer, 2..1000 |
| `tripleMinPool` | `15000000` | Finite number >= 0 |

Null/absent means default. The economy dashboard uses its existing `PATCH /admin-dashboard/games-economy/fruitwheel` endpoint, super-admin check, required reason, and before/after admin audit. Controls are in `economy-admin.js` and `admin-dashboard.html` (not `app.js`). No new endpoints or permissions.

- Shared state (`GET /games/fruitwheel/shared/state` and `fruitwheel_state`), `fruitwheel_result`, and personal history (`GET /games/fruitwheel/shared/history`) add `results` and `bonus` (`double`, `triple`, or null).
- `results` is always an array: empty before the result is revealed, one primary card for a revealed plain round, two/three for a funded bonus. No future outcomes leak during betting/closing.
- State also adds `roundsToBonus`, `bonusEveryRounds`, and `bonusEnabled` (to hide the countdown while disabled).
- State's original `history: string[]` stays unchanged. Additive `historyRows` carries `{ round, result, results, bonus }` for richer ticker chips. Both ticker and personal history survive restarts through stored bonus metadata. Old/null/malformed bonus metadata falls back to the primary result.
- Existing event names, `result`, wheel segment/offset, balances, and payout fields are preserved for installed apps.

## App and migration

The app parses additive fields with legacy fallbacks, lands on the primary, highlights every winning card after stopping, displays the Arabic double/triple banner and countdown, and shows all cards in ticker/history chips. Displayed winnings still come from the server payout. Disabled/older servers do not show a misleading bonus countdown. Rules describe bonus funding and the current 15-second betting phase.

Migration: `backend/prisma/migrations/20261021000000_fruitwheel_bonus/migration.sql` adds nullable TEXT `fruit_wheel_shared_rounds.bonus` using `ADD COLUMN IF NOT EXISTS`; the Prisma model adds `bonus String?`. Store the winning-set JSON only for bonus rounds; plain rounds store null. Apply the migration and regenerate Prisma before starting the updated backend. No live database was migrated in this task.

## Validation

- Backend: all 28 test files passed when launched individually, 289 tests; the subsequently extended dashboard test file passed both tests (290 total). Fruit Wheel has 35 tests covering timing/empties/reset, disabled settings, deterministic selection, free-pool threshold boundaries, summed payouts, caps, persistence, rollback/downgrade, pool-read failure, and reservation cleanup.
- Normal `npm test` was attempted but Windows sandbox child-process spawning returns `EPERM` before any test runs. Equivalent isolated per-file executions used `node --require ./scripts/test-env.js --require ts-node/register/transpile-only <file>`; test types are included in the separate TypeScript check.
- The shared `backend/node_modules` is a junction outside the writable worktree. Normal Prisma generation is denied there. A fresh client was generated from a copy of the updated schema under ignored `backend/build/fruitwheel-check`, and a temporary tsconfig resolves `@prisma/client` to that client. This is verification scaffolding, not a product change.
- Full TypeScript checking, including tests, passed with `node node_modules/typescript/bin/tsc --noEmit --preserveSymlinks -p build/fruitwheel-check/tsconfig.json`. `--preserveSymlinks` avoids existing declaration-portability errors caused by the external dependency junction. Dashboard JavaScript syntax and `git diff --check` also passed.
- Dart analysis was run directly through the installed analysis server because Flutter/Dart launchers cannot spawn their child tools in this sandbox. All six changed Dart files have no analyzer errors or warnings; existing informational style/deprecation notices remain.
- Flutter widget tests were added for old-server parsing, both banners, primary landing, all winners, payout preservation, multi-card history, and 360x640 / 393x873 / 412x915 layouts. Execution is blocked by the SDK/child-process restrictions; run `flutter test test/fruit_wheel_test.dart` in a normal Flutter environment and verify animations on a device.
