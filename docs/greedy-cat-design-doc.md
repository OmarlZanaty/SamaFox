# القط الجشع — Greedy Cat Jackpot

Design, economy and configuration reference, plus the QA report for the initial
build.

- Engine: `backend/src/services/greedyCat.service.ts`
- REST: `backend/src/controllers/greedyCat.controller.ts`, routes under `games/greedy/*`
- Client: `app/lib/screens/games/greedy_cat_screen.dart`
- Artwork: `app/lib/screens/games/greedy_cat_art.dart`, brief in `GREEDY_CAT_ARTWORK_BRIEF.md`
- Simulator: `backend/scripts/greedy-cat-sim.ts` (`npm run sim:greedy`)
- Design harness: `tools/greedy-cat-mock/server.js` + `app/lib/dev/greedy_cat_preview.dart`

---

## 1. What it is

Eight food cards ring a wooden hub with a cat mascot at its centre. During a 30
second selection window a player stacks coins on any card, or on a whole
category via the سلطة / بيتزا buttons. The wheel then turns and stops with the
winning card under a fixed 12 o'clock pointer.

It follows عجلة الحظ rather than the halal model used by skillWheel/skillDice:
it is a bet-on-an-outcome format, built to the client's spec. Every coin
movement is in one file so the planned halal conversion stays a change to the
payout helpers and nowhere else.

**Server-authoritative, like every other game here.** The service owns the round
timer, the RNG and every payout; the Flutter screen places bets over REST,
listens to `greedy_state`, and animates the symbol the server already rolled. A
tampered client can change nothing but its own animation.

---

## 2. The table

Ring order is clockwise from 12 o'clock, which is the order the client draws.

| # | Symbol | Arabic | Category | Multiplier | Weight | Probability |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | chicken | دجاجة | pizza | 45× | 10 | 2.16% |
| 1 | tomato | طماطم | salad | 5× | 90 | 19.44% |
| 2 | goat | ماعز | pizza | 15× | 30 | 6.48% |
| 3 | pepper | فلفل | salad | 5× | 90 | 19.44% |
| 4 | fish | سمكة | pizza | 25× | 18 | 3.89% |
| 5 | carrot | جزرة | salad | 5× | 90 | 19.44% |
| 6 | shrimp | روبيان | pizza | 10× | 45 | 9.72% |
| 7 | corn | ذرة | salad | 5× | 90 | 19.44% |

**Weights are proportional to 1/multiplier**, which is the central design
decision:

```
1/45 : 1/25 : 1/15 : 1/10 : 1/5   ×450   →   10 : 18 : 30 : 45 : 90
```

Total weight 463, so every symbol returns `450/463 = 97.19%` of stake and the
house keeps a flat 2.81% no matter what the player backs. That equality is what
lets the rules modal say, truthfully, that no bet on the table is better than
any other.

`assertBalancedTable()` runs at engine start and **throws** if a multiplier is
ever changed without its weight, so this property cannot silently rot.

### Category bets

`سلطة` and `بيتزا` are **shortcuts, not separate payouts**: the stake is split
evenly across that category's four symbols and settles as four ordinary symbol
bets. A category stake must divide by 4.

> **Deviation from the original spec, on purpose.** The spec asked for a flat 2×
> on a category. That cannot ship. Salad covers 360/463 of the ring, so a flat
> 2× returns `0.7775 × 2 = 155%` of stake — an unbounded money printer, and the
> single most expensive bug this game could have had. Splitting keeps a category
> bet at the same 97.19% as everything else, and it is what the reference screen
> already shows visually ("distribute the wager to the four associated cards").

### Payout

```
gross return = stake on the winning symbol × that symbol's multiplier
net profit   = gross return − everything staked this round
```

The stake is **included** in the multiplier: 100 on a 5× symbol returns 500, of
which 400 is profit. Every bet on a non-winning symbol is lost. This is stated
in the rules modal.

### Provable fairness

The winning symbol is derived from the round seed, so the `seedHash` published
when the round opens commits to the outcome **before any bet is placed**, and
the seed revealed at the result lets a player recompute it:

```
roll  = sha256(seed + ':' + roundId) → first 52 bits → mod 463
index = the symbol whose cumulative weight window contains roll
```

---

## 3. Round cycle

| Phase | Default | UI label | Behaviour |
| --- | --- | --- | --- |
| `betting` | 30 s | «وقت الاختيار» | Cards and denominations live |
| `closing` | 5 s | «النتيجة قادمة» | Betting shut, timer pulses red |
| `spinning` | 6 s | «وقت العرض» | Wheel turns to the rolled symbol |
| `result` | 6 s | «وقت العرض» | Settled, result card raised |

A round with no players restarts the betting window instead of burning a spin,
so an idle table does not fill the history strip with phantom rounds.

The client animates the spin by **orbiting the cards around the hub** rather
than rotating a canvas: Arabic multiplier labels and food icons stay upright
through the whole turn, which a rotate-then-counter-rotate widget tree cannot
guarantee at speed. Quartic ease-out with a sub-degree settle-back.

---

## 4. Configuration reference

Everything below is a named constant in `greedyCat.service.ts` and is served to
the client in the `layout` block, so the client never hard-codes a payout.

| Value | Default | Notes |
| --- | --- | --- |
| `BETTING_MS` | 30 000 | Selection window |
| `CLOSING_MS` | 5 000 | Bets shut, pre-spin |
| `SPINNING_MS` | 6 000 | Must match `_spinDuration` in the screen |
| `RESULT_MS` | 6 000 | Result card display |
| `DENOMINATIONS` | 100 / 1 000 / 5 000 / 20 000 / 100 000 / 500 000 | Per the Arabic reference screen |
| `MIN_BET` | 100 | |
| `MAX_BET_PER_SYMBOL` | 5 000 000 | Checked per symbol, after the category split |
| `CATEGORY_SPLIT` | 4 | Category stake must divide by this |
| `SYMBOLS[].multiplier` | see table | **Never change without the weight** |
| `SYMBOLS[].weight` | see table | **Never change without the multiplier** |
| `RTP` | 0.9719 | Derived, not set. Shown in the rules modal |
| `JACKPOT_MILESTONES` | 500K / 1M / 2M / 5M / 10M | Activity-bar markers |
| `MILESTONE_AWARD` | **0** | See below |
| history length | 100 kept, 15 sent | |
| leaderboard rows | 20 | Reset at UTC midnight |

Client-side, persisted per device in `SharedPreferences`: music, sound effects,
reduced motion, selected denomination, ranking scope.

### The jackpot bar is not a prize

`MILESTONE_AWARD` is deliberately `0`. The bar tracks **coins staked at the
table** — a live activity meter, nothing more, and the rules modal says so in as
many words. Paying a milestone out has to be funded by a rake off the stakes,
which means dropping the 97.19% RTP by exactly that much. Wire the rake first,
or the pot pays out coins the table never took in.

The refund path in `clearBets` also removes the stake from the meter, so a
player cannot pump the bar by betting and clearing in a loop.

### «ساخن»

The hot badge marks whichever symbol the table has backed hardest this round. It
is a social indicator only — the roll is weight-based and never looks at where
the money went. The rules modal states this explicitly, because the reference
material this game was based on contains a lot of folklore about result
"patterns".

---

## 5. Wire format

`GET games/greedy/state` → `{ state, balance, countryCode, layout }`
`POST games/greedy/bet` `{ target, amount }` — target is a symbol key, `salad` or `pizza`
`POST games/greedy/clear`, `POST games/greedy/repeat`
`GET games/greedy/history`, `GET games/greedy/ranking?scope=region|global`

Socket: `greedy_join_table` / `greedy_leave_table`; server pushes `greedy_state`
(shared view, no `me` block), `greedy_result` and `greedy_milestone`.

Rate limit: 120 req/min per user, same as عجلة الحظ.

---

## 6. QA report

Everything below was actually executed, not reasoned about.

### Economy — `npm run sim:greedy`
500 000 rounds × 3 independent seeds, replaying the **shipped** `rollFromSeed`:

```
symbol      mult   weight   expected hit   measured hit    measured RTP
chicken      45×     10         2.16%         2.17%          97.51%
tomato        5×     90        19.44%        19.48%          97.41%
goat         15×     30         6.48%         6.47%          97.13%
pepper        5×     90        19.44%        19.40%          97.02%
fish         25×     18         3.89%         3.88%          97.10%
carrot        5×     90        19.44%        19.43%          97.17%
shrimp       10×     45         9.72%         9.73%          97.34%
corn          5×     90        19.44%        19.42%          97.10%

salad  (tomato, pepper, carrot, corn)              97.17%
pizza  (chicken, goat, fish, shrimp)               97.27%

widest drift across all ten bets: 0.32 points — PASS
```

Measured hit rates match the weights, and all ten placeable bets converge on the
same 97.19%.

### Compilation
- `npx tsc --noEmit` on the backend — clean.
- `flutter analyze` on all six new/changed Dart files — 0 errors, 0 warnings.
  (80 `info` lints remain: `withOpacity` deprecations and trailing commas, both
  of which match the surrounding codebase.)

### Layout — `flutter test test/greedy_cat_layout_test.dart`
Six tests, all passing: no RenderFlex overflow at 320×700, 390×844, 720×1600 and
834×1194; the dashboard scrolls rather than compressing the wheel; the rules
sheet opens and scrolls without overflow.

Four real overflows were found and fixed by this test: the header row, the
jackpot bar's label row, the LuckyDrop teaser, and the milestone chest row. All
four were on narrow screens only.

### Artwork — `flutter test test/greedy_cat_art_test.dart`
Renders every painter to `build/greedy_cat_contact_sheet.png` and fails if any
throws. Reviewing that sheet caught four defects, all fixed:

1. `pepper` was a red circle indistinguishable from `tomato` at card size —
   redrawn as a long chilli. These are separate bets, so this was functional.
2. `shrimp` read as a fish, from a self-intersecting outline — rebuilt as a
   stroked C-curve.
3. Goat horns were cream-on-cream and invisible against the plaque — darkened.
4. The open treasure chest painted its lid over its own coins — paint order
   corrected.

### End-to-end — mock harness + Flutter web
Run against `tools/greedy-cat-mock/server.js`, which speaks the real wire
format, in a 400×880 portrait viewport. Verified live:

- Betting: eight cards with multipliers, per-card table totals, gold «أنت»
  stake badges visually distinct from the dark table-total pills, «ساخن» badge,
  timer counting down, denominations with the selected tile ringed **and**
  ticked (not colour alone).
- Category split: one 100 bet on a category produced «أنت 25» on each of its
  four cards and «أنت 100» on the button — the split behaving exactly as designed.
- Settlement: 25 staked on a 15× winner paid 375, against 300 total staked, and
  the stats row showed «أرباح اليوم +75» and «سجلي 375». Correct.
- Win result: fish 25×, stake 25 000, return 500 000, net +475 000, gold-edged
  card, confetti, winning card highlighted behind the modal.
- Loss result: chicken 45×, stake 6 000, return 0, net −6 000 in red, no
  confetti, respectful copy.
- Disabled states: cards, denominations and category buttons all dim and stop
  accepting input outside the betting window.

Two bugs were found and fixed this way: the timer ring cut through the 12
o'clock card's stake badge, and signed numbers rendered as `475,000+` because a
leading ASCII sign gets reordered inside an RTL paragraph (fixed by forcing
those runs LTR). A third, `_compact` printing `-6000` instead of `-6.0K` for
negatives, was fixed at the same time.

### Not verified
- **On-device.** Everything above is Flutter web plus widget tests. Audio in
  particular is unverified — the twelve effects and the 16-second music loop
  were generated and the wiring compiles, but nobody has heard them on a
  handset. The loop's seam in particular wants an ear on it.
- **Against the real backend.** The engine is wired into `index.ts` and
  typechecks, but this machine has no Postgres, so the live path was exercised
  through the mock. The first run against a real database should confirm the
  charge/refund path in `placeBet` and the payout loop in `settle`.
- **Concurrency.** Multi-player behaviour — several users betting into one round
  — has not been load-tested.
- **Reduced motion** is implemented and honours `MediaQuery.disableAnimations`,
  but was only exercised through code paths, not visually.

### Open assumptions
1. `MILESTONE_AWARD = 0`. The jackpot bar celebrates but pays nothing until a
   rake is wired and the RTP is dropped to fund it. This is a product decision.
2. The daily leaderboard is **in-memory** and resets on process restart as well
   as at UTC midnight. If it needs to survive a deploy it wants a Prisma table.
3. Regional ranking filters on `User.countryCode`; users with none fall back to
   the global board rather than seeing an empty region.
4. Round IDs start at `900000 + (days since epoch mod 50000)` purely so the
   header reads like a live table. They are not persisted and restart with the
   process.
5. The hub banner `card_greedy.png` and the music bed are both *generated*
   (by `test/greedy_cat_art_test.dart` and `generate_greedy_sounds.py`
   respectively) rather than commissioned. They are real, original and in the
   house style, but an illustrator and a composer would both do better; the
   artwork brief says how to swap either one in.
6. The hub's `_open` now dispatches on entry title rather than list index. It
   previously switched on position, which meant two games in flight collided on
   `case 4` — نيون فورتشن had claimed it without adding its card. Its branch is
   preserved and goes live the moment its `_GameEntry` is added.
