# FRUIT WHEEL (77) — back to ×2 / ×8 with the crown (no-win slice), 70% return

Owner decision 2026-10-21 (client: «ليه قللت المضاعف … كدا بتختلف عن سيستم البرامج التانيه»).
×2/×2/×8 with no losing slice cannot hold a 70% return (77 would return 100%), so the crown comes back.

## Server (`backend/src/services/fruitWheelRound.math.ts`, `gameConfig.service.ts`, tests, sim script)
- Restore exactly the pre-2026-10-19 table (it is still what apps ≤1.0.57 draw):
  watermelon ×2 weight 3500, plum ×2 weight 3500, sevens ×8 weight 875, crown ×0 weight 2125
  (TOTAL 10000; each card returns exactly 70%). Use `git show e2f20d9^:backend/src/services/fruitWheelRound.math.ts`
  as the reference; keep WHEEL_ORDER with crown at index 9 (installed apps use these indices) and keep
  the existing multiplierX10 representation (20/20/80) so the integer payout code stays as is.
  `assertBalancedTable` must again require 70% per card.
- gameConfig natural max multiplier for fruitwheel back to 8.
- Engine start log text back to "three cards and crown, 70% return".
- Bonus rounds (already implemented in this branch, see docs/fruitwheel-bonus-rounds.md): a bonus round
  must never be a crown. When the round is a bonus round (roundsToBonus === 0, bonusEnabled, has players)
  and the rolled primary is 'crown', replace the primary with a card chosen deterministically from
  sha256(`${seed}:${roundNumber}:bonus-primary`) weighted by the card weights (3500/3500/875), BEFORE
  prepareBonus runs; then prepareBonus works as now. If funding then downgrades to plain, the round stays
  on that card (a normal single win), never back to crown. Plain rounds are unchanged (crown possible).
- Update/extend tests: table returns 70% per card, crown reachable in plain rounds, bonus round never crown,
  payouts ×2/×8, simulation script `backend/scripts/fruit-wheel-round-sim.ts` back to the old table.

## App (`app/lib/screens/games/fruit_wheel_*.dart`, tests)
- Wheel back to TEN slots matching server WHEEL_ORDER (crown at index 9). Restore the crown slot art
  (fruit_wheel_art.dart still has a 'crown' case — reuse it) and the crown result presentation that
  existed before e2f20d9 (`git show e2f20d9^:app/lib/screens/games/` for reference) — a crown result means
  «لا يوجد فائز في هذه الجولة» (no card wins), shown clearly, history chip shows the crown.
- `result == 'crown'` must parse as a valid outcome (today it becomes null and the wheel never stops).
- Card labels keep reading multipliers from the server table config (fallback ×2 / ×8).
- Keep everything the bonus work added (results/bonus/roundsToBonus, banner, counter).
- Rules/odds sheet: crown odds 21.25%, cards 35% / 35% / 8.75%, ×2 / ×2 / ×8.
- `flutter analyze` clean for touched files; update app/test/fruit_wheel_test.dart.

## Version
- app/pubspec.yaml version → 1.0.59+2067.

UTF-8 Arabic via apply_patch only; no `????`. Write notes to docs/fruitwheel-crown-back-notes.md.
