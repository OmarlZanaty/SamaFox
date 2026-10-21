# FRUIT WHEEL (لعبة الـ 77) — bonus rounds: double / triple win

Client 2026-10-21: «بالنسبة للعبة 77 بعد كل عدد لفات معين تجيب اختيار 2 مكسب واحيانا ال 3 مكسب لما صندوقها يتملي».
Owner: use sensible defaults, editable from the dashboard.

Code: `backend/src/services/fruitWheelRound.service.ts`, `fruitWheelRound.math.ts`,
`gameConfig.service.ts`, `halalGames.service.ts` (reservePrize/payPrize/releasePrize — read, reuse, do not
change their semantics), tests in `backend/src/services/__tests__/fruitWheelRound.test.ts`,
app `app/lib/screens/games/fruit_wheel_*.dart`, dashboard `backend/public/app.js` games-economy settings
(only if per-game settings are edited there). Read RULES: UTF-8 Arabic via apply_patch only; no `????`.

## Behaviour (server is the only authority)
- New per-game settings in game_config (defaults for 'fruitwheel'; null/absent = default; validated):
  `bonusEnabled: true`, `bonusEveryRounds: 20` (integer 2..1000), `tripleMinPool: 15_000_000` (>= 0).
- A round counter (rounds settled since the last bonus; in memory is fine, start at 0 on boot) decides:
  when it reaches `bonusEveryRounds`, the next round is a BONUS round and the counter resets after it.
  Count only rounds that had at least one player (empty rounds do not advance it).
- At 'closing' (where `r.result = rollFromSeed(...)` happens today): primary result is unchanged.
  If bonus: kind = 'triple' when the pool's FREE balance (balance minus all outstanding reservations;
  use/introduce a helper in halalGames.service that already knows `held.pool`) >= tripleMinPool, else 'double'.
  Winning set: double = primary + ONE other card chosen deterministically from
  sha256(`${seed}:${roundNumber}:bonus`) among the two non-primary cards; triple = all three cards.
- Funding (no minting, ever): for every player compute payout = Σ payoutFor(stakes, card) over the winning
  set; extra = payout − (what their existing reservations cover for the primary). Reserve each extra with
  reservePrize (same game, stake = their staked) and append the token to the player's tokens so payPrize
  pools it. If ANY reservation fails, release all extras of this round and downgrade (triple → double →
  plain) and retry once per step. The final kind is what is announced and paid.
- settle(): payout = Σ over the winning set (payoutFor per card). Everything else unchanged
  (payPrize, stake rows, winners, daily stats, broadcast of big wins).
- DB: migration `backend/prisma/migrations/20261021000000_fruitwheel_bonus/migration.sql`:
  `ALTER TABLE "fruit_wheel_shared_rounds" ADD COLUMN IF NOT EXISTS "bonus" TEXT;` (JSON text like
  '["watermelon","plum"]', null for plain rounds) + the Prisma schema field. Keep `result` = primary card
  (installed apps read it and history uses it).
- Public state + `fruitwheel_result` + history rows gain additive fields: `results: string[]` (winning set,
  always present, length 1 on plain rounds), `bonus: 'double' | 'triple' | null`, and in state
  `roundsToBonus: number` (how many more player rounds until the next bonus; 0 = this round is one) and
  `bonusEveryRounds`. Never remove or rename existing fields.
- Admin audit when settings change goes through the existing settings path.

## App (next build; installed apps must keep working with only `result`)
- Parse `results`, `bonus`, `roundsToBonus` with fallbacks.
- Wheel still lands on the primary `result`. Then highlight every winning card; banner over the wheel:
  double «🎉 مكسب مزدوج!», triple «🔥 مكسب ثلاثي!»; history chips show all winning cards.
- Small label near the countdown: «المكسب المزدوج بعد N لفة» (when N > 0) / «لفة المكسب المزدوج!» (N = 0).
- Win amount shown = server payout (unchanged path).

## Tests (backend, node:test like the existing file)
- counter: bonus exactly on the Nth player round; empty rounds don't count; resets after.
- double/triple selection deterministic from seed; triple only when free pool >= tripleMinPool.
- payout = sum over winning set; a player on two winning cards gets both.
- pool too small for the extra → downgrade, nothing paid beyond reservations, pool never negative,
  all extra reservations released.
- bonusEnabled=false → never a bonus.
Must compile (`npx tsc`) and `npm test` must pass (reviewer runs them). Write notes to
`docs/fruitwheel-bonus-notes.md` (what changed, new fields, settings, migration).
