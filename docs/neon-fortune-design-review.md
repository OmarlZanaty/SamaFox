# نيون فورتشن — Neon Fortune: Tiger City
## Design review, and what was built from it

**Status: built and playable.** This began as the pre-build design review §18 of
the brief asks for. The decisions in §8 were then answered — D1 = option A, D2–D6
as recommended — and the game was implemented against them. Sections 0–8 are the
review as written; §9 records what shipped and how it measures.

It is written against **this repository**, not against a blank project, because
SamaFox already has a games hub, a coin economy, an XP/level system, quests,
achievements, and — most importantly — a shipped 5-reel-class slot
(*أثيرفول / Aetherfall*) whose delivery audit already ran into the central
problem this brief raises.

**Source of truth for every number below:**
`backend/src/services/neonFortune.service.ts`. Client behaviour:
`app/lib/screens/games/neon_fortune_*.dart`. Art:
[`../NEON_FORTUNE_ARTWORK_BRIEF.md`](../NEON_FORTUNE_ARTWORK_BRIEF.md).
Companion documents: [`aetherfall-design-doc.md`](aetherfall-design-doc.md),
[`../AETHERFALL_ARTWORK_BRIEF.md`](../AETHERFALL_ARTWORK_BRIEF.md).

---

## 0. Findings that change the brief

### 0.1 "Virtual points only" cannot be said on top of `coinsBalance` — BLOCKING

The brief requires, repeatedly (§1, §6, §10, §15), that every reward be labelled
virtual points and that no screen imply monetary value. Every existing game in
this app — بلينكو, طيّار, عجلة الحظ, أثيرفول — debits and credits
`User.coinsBalance`, and coins are acquired through **charging agents**
(`backend/src/controllers/charging-agency.controller.ts`), i.e. they are bought
with real money from a human reseller.

This is the identical conflict recorded in `aetherfall-design-doc.md` §0.2:
Aetherfall shipped a `DEMO / FREE PLAY — no monetary value` badge while
decrementing purchasable coins. That badge was removed in `abf8c3d` — *"aetherfall:
say it costs coins, because it does"* — so the house has already answered this
question once, in favour of option A. Shipping a second game with the old
contradiction would re-open what was just closed. (The design doc's §0.2 still
reads "open" and is now stale.)

Three coherent products; pick one before milestone 1:

| Option | What it means | Cost |
|---|---|---|
| **A. Coin economy, honest copy** *(chosen)* | Neon Fortune uses `coinsBalance` like its siblings. Every "virtual points only / no monetary value" line from the brief is dropped. The rules screen says plainly: coins, obtained by top-up or play, not withdrawable — the same line Aetherfall now takes. | Loses the brief's marketing-safe framing; needs a decision on store positioning. |
| **B. Separate non-purchasable balance** | New `neonPoints` column, seeded and refilled only by free sources (daily gift, missions, level-up). Zero contact with `coinsBalance`. The brief's copy becomes true as written. | A second economy to balance, and the game will feel disconnected from the hub — players will ask why their coins don't work. |
| **C. Coins, but no jackpot meters** | Pools that grow from real-money-derived coins are the part most likely to read as gambling. | Removes the brief's headline feature. |

I cannot pick this for you: it is a product and compliance call, not an
engineering one. **Everything below is written for option A**, with the points
noted where option B would change it.

### 0.2 The brief assumes a standalone app; this is a cabinet inside a social app

§12 asks for five bottom-nav destinations (Home, Games, Missions, Collection,
Settings), a header level bar, an inbox, a shop plus-button and a games
carousel. SamaFox already owns all of that at app level:
`lib/screens/games_hub_screen.dart` is the carousel, `xp.service.ts` is the level
system, `UserQuest`/`UserAchievement` are missions, `profile_screen.dart` is
top-up. Rebuilding them inside one game would give the player two of everything.

**Recommendation:** Neon Fortune ships as the **fifth card in the games hub**,
reusing the app's shell. Inside the cabinet we keep only what the spin loop
needs: balance, bet, spin, jackpot meters, feature counters, paytable, rules,
sound. Missions and daily gift point at the app's existing systems rather than
new ones. Collection/cosmetics (§11) is deferred — see §7.

### 0.3 Originality risk is concentrated, and it is fixable

The brief's own combination — a tiger head as top symbol, purple-and-gold neon,
four tiers named MINI/MINOR/MAJOR/GRAND, a "Lucky Drop" chest and a win ticker —
is precisely the reference's signature silhouette. Individually each element is
an unprotectable genre convention; together, at a glance, they reproduce the
reference's *look*, which is the thing that actually draws a takedown.

Divergence levers I intend to apply, none of which cost gameplay:

- **Composition:** the reference stacks banner → reels → controls in flat bands.
  We use the Aetherfall house move instead — a centred arched cabinet with the
  jackpot meters as a *curved crown* over the reels and the mascot in a window
  above the board, not beside it.
- **Palette:** keep midnight violet and magenta, but let **cyan carry the
  interactive states** and restrict gold to numbers and frames. The reference is
  gold-dominant.
- **Tier names:** MINI / MINOR / MAJOR / GRAND is the exact reference set. I
  propose **شرارة / وهج / منارة / مدينة** (Spark / Glow / Beacon / City) —
  themed, translatable, not a copied ladder. Keeping the four generic English
  words for player familiarity is a conscious call to log, not a default.
- **No reference screenshots** are used at any stage, and the art prompts name
  no third-party title, as with the Aetherfall brief.

### 0.4 The simulated win feed should be real data instead

§5 asks for a feed of fictional aliases and wins, disclosed as simulated. This
app is genuinely multiplayer and already stores spin history per game. A feed of
**real, anonymised wins** (display name + amount, opt-out honoured) is more
truthful, cheaper to defend, and no harder to build. Recommend real data, and
rejecting the fabricated feed outright rather than disclosing it. If the game is
new and the feed would be empty on day one, it shows recent wins from all games,
or nothing — never invented ones.

### 0.5 Two smaller mismatches

- **Language.** The brief wants EN + AR with true RTL. Every existing game
  screen is **hardcoded Arabic** (`aetherfall_screen.dart` has zero `AppStrings`
  references). Doing this game bilingually makes it the odd one out and costs
  real time; doing it Arabic-only matches the app but breaks the brief. See D4.
- **RTP claim.** The brief forbids claiming an RTP that has not been measured.
  Agreed, and this repo has the machinery: the target is **~97% (3% house edge)
  to match طيّار and the retuned Aetherfall**, proven by a committed simulator
  that fails the build, not by a comment.

---

## 1. Information architecture

```
Games hub  (existing)
└── نيون فورتشن  (new card)
    └── Cabinet screen  ── the only always-on screen
        ├─ Paytable sheet        (symbols, line pays, wild/scatter, features)
        ├─ Rules & fairness      (trigger conditions, tier logic, seeds, verify)
        ├─ Jackpot detail sheet  (exact pool values, contribution rule)
        ├─ Skyline Rush          (free-spin takeover, returns to cabinet)
        ├─ Vault of Lights       (bonus takeover, returns to cabinet)
        └─ Settlement panels     (feature totals, dismissible, never a dead end)
```

Everything else the brief lists — missions, daily gift, level, inbox, top-up,
settings — resolves to the app's existing screens via a link, not a copy.

## 2. Screen map and responsive layout, in plain language

One portrait screen, designed at 720×1600 and expressed in fractions of the
available height so it holds from 9:16 to 9:20 without reflowing. Safe areas are
subtracted first; the reel cabinet absorbs the slack.

| Band | Share | Contents | When height is tight |
|---|---|---|---|
| Header | 8% | Balance + top-up link, back, sound, help | Fixed, never shrinks |
| Event strip | 9% | Lucky Drop claim, real win ticker | First to drop below 640dp |
| Jackpot crown | 10% | Four tier meters on a curved band | Meters shrink to icon + value |
| Cabinet | 46% | 5×3 reels, frame, win-line overlay | Absorbs all remaining space |
| Ribbon | 7% | Last win, feature progress, line count | Collapses into the control bar |
| Controls | 16% | Bet −/+, Spin, Auto, paytable | Fixed, never shrinks |
| Footer | 4% | Rules, fairness, "coins are not withdrawable" | Always present |

Non-negotiable in review: the spin target stays ≥56dp; reels never overlap
header or controls at any tested aspect; a win animation never covers the
balance; every modal is dismissible with a visible control.

## 3. Symbol hierarchy and starting math

5 reels × 3 rows, **20 fixed paylines**, left-to-right from reel 1, highest win
per line only. Bet presets are **total bet**: 50 / 100 / 250 / 500 / 1000 coins;
line bet = total ÷ 20. Payouts below are **× line bet** and are a *starting
point for the simulator*, not a claim:

| Tier | Symbol | ×3 | ×4 | ×5 |
|---|---|---|---|---|
| Top | Tiger guardian | 10 | 50 | 250 |
| High | Crystal panther | 8 | 30 | 150 |
| High | Fortune crane | 6 | 20 | 100 |
| Mid | Neon koi | 4 | 12 | 60 |
| Mid | Lucky lantern | 3 | 10 | 50 |
| Mid | Star coin | 3 | 8 | 40 |
| Low | A / K | 2 | 5 | 25 |
| Low | Q / J | 1.5 | 4 | 20 |
| Low | 10 | 1 | 3 | 15 |

- **Wild** substitutes for the nine symbols above; never for Scatter or Jackpot
  Token. In Skyline Rush it carries a ×2 or ×3 multiplier, printed on its face.
- **Scatter** pays nothing on its own; 3+ anywhere triggers Skyline Rush
  (10 free spins, base bet locked, +spins capped, no purchase option).
- **Jackpot Token** appears on reels 1/3/5 only; 3 tokens trigger Vault of
  Lights. Token frequency is independent of bet size — bet does not buy odds.

**Budget:** ~97% total return = ~95.8% base + feature, ~1.2% routed into the
jackpot pools (Spark 0.15 / Glow 0.25 / Beacon 0.35 / City 0.45 percentage
points of every bet). Pools have seeded floors, reset to the floor on a win, and
are credited in the same database transaction that pays the player, so two
simultaneous winners cannot both take one pool.

## 4. Reward state diagram

The server resolves the **entire** spin — base result, free-spin round and vault
outcome — in one response before any reel moves. The client renders a decided
outcome, exactly as `aetherfall.service.ts` works today.

```
IDLE
 └─ player taps SPIN, balance ≥ bet
    → BET_LOCKED (debit via atomic conditional update)
      → SERVER_RESOLVED (seeded RNG: grid, lines, features, jackpot draw)
        → REELS_SPINNING → stops reel 1..5 in sequence
          → EVALUATE
            ├─ no win ───────────────→ SETTLE
            ├─ line wins → COUNT_UP → tier banner (5× / 20× / 100×) → SETTLE
            ├─ scatter ≥3 ──────────→ SKYLINE_RUSH (10 spins, no debit)
            │                           → SETTLEMENT_PANEL → SETTLE
            └─ tokens ≥3 ───────────→ VAULT_OF_LIGHTS (≤9 picks; match 3 tiers
                                        or guaranteed consolation)
                                        → CELEBRATION → SETTLE
              → SETTLE (credit once, update meters, write history row) → IDLE
```

Failure paths that must be explicit, not implicit: insufficient balance (no
debit, calm modal, link to free sources), network failure after debit (server
refunds the unresolved spin, as `resolveSpin` already does), and app kill
mid-feature (feature state is server-side and resumes on reopen).

## 5. Art inventory

All under `app/assets/images/neon/`, PNG-32, transparent unless noted, 300×300
for symbols (3× mobile size), no baked text or numbers — the app draws all type
so it stays crisp and translatable. Painted placeholder glyphs ship first, so no
milestone is ever blocked on art, matching the Aetherfall approach.

| Path | Asset |
|---|---|
| `symbol_tiger.png` … `symbol_10.png` | 11 regular symbols per §3 |
| `symbol_wild.png`, `symbol_scatter.png` | Specials; word layer drawn by the app |
| `token_t1..t4.png` | Four tier tokens, shared frame, distinct accent |
| `cabinet_frame.png` | Portrait cabinet with an empty 5×3 well |
| `crown_banner.png` | Curved jackpot crown, no lettering |
| `bg_city.png`, `bg_rush.png`, `bg_vault.png` | Three backgrounds, opaque |
| `chest_drop.png` | Lucky Drop chest, readable at 64px |
| `mascot_sheet.png` | Tiger guardian: idle, blink, cheer, surprise, jackpot |
| `vfx_sheet.png` | Coins, prism shards, sparkles, rays, padded |
| `cards/card_neon.png` | Games-hub card art |

Full generation prompts ship as `NEON_FORTUNE_ARTWORK_BRIEF.md` in the repo
root, same format as the Aetherfall brief and carrying the same guardrail.

## 6. Test plan

**Math.** `backend/scripts/neon-fortune-sim.ts`, run as
`npm run sim:neon-fortune`. It replays the real `computeSpin` — re-implementing
nothing — over ≥1M spins across 3 seeds and reports hit rate, average win,
feature frequency, jackpot frequency, longest loss streak, and the
base/feature/jackpot return split. **It exits non-zero if RTP reaches 100%, if
any jackpot pool trends negative, or if the paytable and the disclosed rules
disagree.** Re-run after touching any weight or payout.

**Unit.** Payline evaluation against hand-built grids (wild substitution,
highest-win-per-line, scatter counting, token reel positions); pool contribution
and atomic claim under concurrent winners; refund on unresolved spin.

**Acceptance** (from brief §16, each verified on a portrait build): a new player
identifies balance, bet, spin and last win within ten seconds; no overlap of
reels with header or footer on 9:16 and 9:20; every reel stop visible and the
grid stable before the win animation; balance never negative; low balance offers
free routes; 3 scatters always yields the documented 10 spins and a correct
settlement total; the Vault always exits and never dead-ends; reduced motion
removes shake and heavy particles; sound-off loses no information; Arabic does
not clip and mirrors correctly (English too, if D4 says bilingual); no screen
implies cash-out; the debug inspector is compiled out of release.

## 7. Milestones

Each ends with a playable checkpoint, an implemented-behaviour list, remaining
risks, and a diff against this review.

1. **Decisions closed** (§8) — no code.
2. **Server math + simulator.** `neonFortune.service.ts`, provably-fair seeds
   matching the house pattern, sim green at ~97%.
3. **Visual shell + static cabinet** with placeholder glyphs, hub card.
4. **Deterministic spin + win evaluation** wired to the server result.
5. **Jackpot meters and pool ledger**, including the concurrent-claim test.
6. **Skyline Rush.**
7. **Vault of Lights.**
8. **Rules, paytable, fairness verify screen, responsible-play controls.**
9. **Audio, haptics, reduced motion, accessibility.**
10. **Localization pass** (scope per D4) and final QA against §6.

Deferred by recommendation: Collection/cosmetics (brief §11) and the themed
alternate cabinets (Moonlit Garden, Rocket Relay, Ocean Prism). Both are
separate products' worth of work, and neither is needed to prove the loop.

## 8. Decisions, and how they were answered

| # | Decision | Answer |
|---|---|---|
| **D1** | Currency: coins with honest copy (A), separate free points (B), or coins without jackpots (C)? | **A** — coins, and the interface says so |
| **D2** | Integrated hub cabinet, or standalone app shell with its own nav? | **Integrated** — a card in the existing games hub |
| **D3** | Win feed: real anonymised wins, or none? | **Real wins only** — no fabricated feed, empty until someone wins |
| **D4** | Arabic-only (matches every sibling game) or AR + EN with RTL mirroring? | **Arabic for v1**; English extraction deferred |
| **D5** | Tier names: themed شرارة/وهج/منارة/مدينة, or generic MINI/MINOR/MAJOR/GRAND? | **Themed** — the cheapest large step away from the reference |
| **D6** | Jackpot pools funded from live play only, or seeded with a liability cap? | **Self-funding pools** — a tier can only pay what it has collected; see §9.3 |

---

## 9. What shipped

### 9.1 Files

| Area | Path |
|---|---|
| Game math, seeds, pools | `backend/src/services/neonFortune.service.ts` |
| REST surface | `backend/src/controllers/neonFortune.controller.ts`, routes under `/games/neon/*` |
| RTP simulator | `backend/scripts/neon-fortune-sim.ts` — `npm run sim:neon-fortune` |
| Rule checks | `backend/scripts/neon-fortune-check.ts` — `npm run check:neon-fortune` |
| API client | `app/lib/repositories/neon_fortune_repository.dart` |
| Cabinet, features, HUD | `app/lib/screens/games/neon_fortune_screen.dart` |
| Symbols and palette | `app/lib/screens/games/neon_fortune_symbols.dart` |
| Arabic + English strings | `app/lib/screens/games/neon_fortune_strings.dart` |
| Vault of Lights | `app/lib/screens/games/neon_fortune_vault.dart` |
| Paytable, rules, money copy | `app/lib/screens/games/neon_fortune_help.dart` |
| Sound, with graceful fallback | `app/lib/screens/games/neon_fortune_sfx.dart` |
| Hub entry | `app/lib/screens/games_hub_screen.dart` |

### 9.2 Measured math

From `npm run sim:neon-fortune -- --spins 400000 --seeds 3` — 1.2M spins
replaying the shipped `computeSpin`/`settleSpin`. Measured, not estimated.

| | Measured |
|---|---|
| **Steady-state RTP** | **97.06%** (house edge 2.94%) |
| RTP at a 5,000-coin stake | 97.02% |
| Base game | 87.62% |
| Skyline Rush | 5.85% |
| Jackpot pools | 3.50% — the contribution rate; all of it returns long-run |
| Vault consolation | 0.09% |
| Hit rate | 32.42% |
| Skyline Rush frequency | 1 in 369 spins |
| Vault of Lights frequency | 1 in 1,453 spins |
| Spark / Glow / Beacon / City | 1 in 3.4k / 7.7k / 29k / 133k spins |
| Longest loss streak | 33 spins |

The simulator prints two figures and the second is the honest one: a finite run
reads ~98% because it is still paying out the one-time launch seed. The gate
fails the build if steady-state RTP reaches 100%, or if any pool trends negative.

**The §3 starting paytable did not survive the simulator** — it returned **6.4%**.
Eleven near-flat symbol weights make three-of-a-kind far rarer than a real reel
strip does, so the same nominal payouts return a fraction of what they look like
they should. The fix was to concentrate the low symbols (weights now run TEN 34
down to TIGER 1.2) and to restate the paytable as multiples of the **total** bet
rather than the line bet, which is also the convention أثيرفول already uses.
Payouts now run from 0.65× bet for three tens to 140× bet for five tigers.

### 9.3 Jackpot pools, and why they cannot overdraw

Every bet sends 3.5% to the pools (Spark 0.45, Glow 0.75, Beacon 1.00, City 1.30
percentage points). 85% of each slice grows the live meter; 15% goes to a reserve
that re-seeds the meter after a win. A pool therefore only pays out what it has
already collected — the sole house money in the system is the one-time launch
seed of 514,000 coins across four tiers. `npm run check:neon-fortune` runs 5,000
consecutive claims to prove neither a pool nor a reserve can go negative.

Pools persist in `AppSetting['neon_fortune_jackpots']` and the backend runs
single-process (`ecosystem.config.js`: `instances: 1`), so the in-memory ledger
has exactly one writer. That assumption is worth re-checking before anyone moves
the API to cluster mode.

### 9.4 Deviations from the review

- **Vault order-independence is enforced by construction**, not by trusting the
  client: a layout never holds three of more than one tier, so tap order cannot
  change the result. The check script samples hundreds of live layouts to prove
  it, and the consolation path is verified to be reachable.
- **Skyline Rush is a replay of server-computed frames**, retriggers included —
  the client never asks for an individual free spin.
- **The event strip shows real wins or nothing at all.** It stays empty until a
  player actually wins five times their bet; there is no fabricated fallback.
- **Collection/cosmetics and the three alternate cabinets remain deferred**, as
  the review recommended.

### 9.5 Added after the first pass

- **Lucky Drop.** A free coin chest on a six-hour server-owned cooldown, 250
  coins a claim. It sits at the head of the event strip, and the two numbers live
  alone at the top of the service because they *mint* coins into a purchasable
  balance — that is a business decision, not a game-design one. The claim is
  recorded before the credit, so ten simultaneous taps pay exactly once
  (verified). Cooldowns persist in `AppSetting`, pruned to the last six hours so
  the stored map stays proportional to active players rather than to the user
  table.
- **Skip control.** `_skipFeature` was read in seven places but nothing ever set
  it — the brief's skip button was missing. Skyline Rush now carries one, and it
  drops the pauses between frames without hiding a single result.
- **Arabic and English.** Every string in the cabinet, the vault, the settlement
  panels and the rules sheet now comes from `neon_fortune_strings.dart`, and the
  screen takes its `textDirection` from the locale instead of pinning itself to
  RTL. This makes it the first bilingual game screen in the app; the others stay
  hardcoded Arabic (D4 revisited).
- **Sound.** Fourteen cues now exist in `app/assets/sounds/neon_*.wav`, generated
  as tones and filtered noise on one pentatonic scale (622 KB total). They are
  **placeholders**, not composed audio, and are meant to be replaced per
  `NEON_FORTUNE_ARTWORK_BRIEF.md` §6.

### 9.6 Still open

- **Artwork — symbols delivered.** All fourteen reel symbols are real art now,
  generated from the prompts in `NEON_FORTUNE_ARTWORK_BRIEF.md` and processed for
  the app: cropped, squared, resized to 300×300 and cut off their black field
  (24.4 MB → 1.7 MB). Still outstanding: the hub card `cards/card_neon.png`,
  which falls back to a gradient and the 🐯 emoji until it lands, plus the
  optional backgrounds, cabinet frame, tier tokens and mascot — none of which are
  wired to code, so they change nothing until someone hooks them up.
  Worth a look at reel size: the star coin and the jackpot token share a
  four-point-star-in-a-gold-ring silhouette and are told apart mainly by colour
  (gold against cyan).
- **No run against a real database.** This machine has no Postgres — and `.env`
  points `DATABASE_URL` at a SQLite file while the schema is Postgres — so every
  endpoint has been exercised against an in-memory stand-in for the two Prisma
  models the game touches, not against the real one. The jackpot and Lucky Drop
  rows in `AppSetting` have never been written by Prisma itself.
- **Not deployed.** The routes are not on the server and no app build has
  shipped.
- **Deferred scope from the brief** — the collection/cosmetics system, the daily
  missions tie-in, and the three alternate cabinets (Moonlit Garden, Rocket
  Relay, Ocean Prism) — remains deferred. Each alternate cabinet is a game in its
  own right.
