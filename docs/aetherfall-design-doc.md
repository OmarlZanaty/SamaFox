# Aetherfall: Vaults of the Skyfire — Design Document & Delivery Audit

**Status: built and playable.** This document is not a pre-build plan — the game
was implemented in `da99b35` / `e8ab8e2` and is wired into the games hub, the
backend routes and the coin economy. It records what actually shipped, measured
rather than assumed, and lists the gaps between the production brief and the
build.

Companion document: [`AETHERFALL_ARTWORK_BRIEF.md`](../AETHERFALL_ARTWORK_BRIEF.md)
— every art asset, path, size and generation prompt.

**Source of truth for every number below:** `backend/src/services/aetherfall.service.ts`.
Client behaviour: `app/lib/screens/games/aetherfall_*.dart`.

---

## 0. Findings

### 0.1 The game paid out more than it took in — fixed

The service comment claimed the paytable was *"Calibrated by Monte-Carlo
simulation (2,000,000 spins) to ~94% RTP"*. No harness was committed, so the
figure was unverifiable. Replaying the shipped `verifySpin` math showed the
opposite: **~102.5% RTP**, i.e. the game lost coins on every spin, and the loss
scaled with a 20,000-coin max bet. It held across seeds and at both small and
large stakes, so it was neither a seed nor a rounding artefact.

**Resolved.** The paytable was scaled to ~0.945× and rounded back to clean
values, retuning the game to a **3% house edge, matching طيّار**.

| | Before | After |
|---|---|---|
| RTP at 20-coin min bet | 102.53% | **96.98%** |
| RTP at 5,000-coin bet | ~103.5% | **97.65%** |
| House edge | −2.5% | **+3.0%** |
| Base / bonus split | 83.2 / 19.4 pts | 78.5 / 18.4 pts |
| Hit rate | 34.20% | 34.20% |
| Bonus rate | 1 in 116 | 1 in 115 |
| Avg bonus pay | 22.4× bet | 21.2× bet |

Verified over 1.2M spins (3 seeds × 400k), seed spread 96.45–97.54%.

Both base play and the bonus read the same `PAYTABLE`, and every payout is
linear in it, so scaling the whole table scales RTP by the same factor. That
made it the safest lever available: **hit rate, bonus frequency and the shape of
the game are all unchanged** — only the size of each win moved. The alternatives
(cutting bonus weights or free-tumble count) would have bought the same points
by making the feature rarer or stingier, which costs more in feel.

RTP drifts up slightly with stake — 96.98% at the minimum, 97.65% at 5,000 —
because payouts are floored to whole coins and that rounding bites
proportionally harder on small wins. The edge is therefore widest exactly where
exposure is smallest. This is inherent to integer currency and is documented
rather than tuned away.

**The measurement is now repeatable and enforced:**

```bash
npm run sim:aetherfall
```

`backend/scripts/aetherfall-sim.ts` replays the real `verifySpin` — it
re-implements nothing, so it measures whatever the weights and paytable
currently say — and **exits non-zero if RTP reaches 100%**. Re-run it after
touching `PAYTABLE`, `WEIGHTS_BASE`, `WEIGHTS_BONUS` or any vault tunable.
Flags: `--spins`, `--bet`, `--seeds`.

Read the spread across seeds, not a single number: the bonus fires ~1 in 115 and
pays ~21× bet, so a fifth of the return arrives from a thin tail and one short
run can land a point off on bonus draw alone.

### 0.2 The "free play / no monetary value" notice was not true — fixed

The help panel used to show:

> DEMO / FREE PLAY — Aetherfall uses virtual credits only. It has no monetary
> value, implies no real odds or RTP, and is entertainment only.

while `resolveSpin` decremented the player's real `coinsBalance` — the same
purchasable currency used by بلينكو and طيّار — between `MIN_BET` 20 and
`MAX_BET` 20,000. The header badge read `DEMO / FREE PLAY` and autoplay was
labelled `AUTO DEMO`.

The production brief specified a free-play prototype on virtual credits; the
build followed the house pattern of the other coin games instead. **Resolved in
favour of the coin economy** — Aetherfall is a real coin game like its siblings,
and the interface now says so:

| Was | Now |
|---|---|
| `DEMO / FREE PLAY` header badge | removed |
| `AUTO DEMO` button and help section | `AUTO` |
| "تم إيقاف AUTO DEMO — الرصيد غير كافٍ" | "تم إيقاف اللعب التلقائي — الرصيد غير كافٍ" |
| "Set your **virtual** bet and tap IGNITE" | "Set your bet and tap IGNITE" |
| `TOTAL VIRTUAL CREDITS` on the bonus summary | `TOTAL COINS WON` |
| "virtual credits only… no monetary value" | states the coin cost, the bet range and the provably-fair guarantee |

The replacement disclaimer only claims what the code actually does:

> Aetherfall is played with coins from your balance. Each IGNITE deducts your
> bet (20–20,000 coins) before the spin resolves, and any win is credited
> straight back. Every spin — including the whole Skyfire Vault — is decided by
> the server from a seed pair you can check, so no result is influenced by the
> app on your device.

The bet range is interpolated from the served layout, so it tracks `MIN_BET` /
`MAX_BET` without a client release. The internal `_autoDemo` and `totalCredits`
identifiers were renamed to `_auto` and `totalCoins` to match.

**Deliberately not claimed:** anything about cash-out or monetary value in
either direction. Nothing in the backend establishes whether coins can be
withdrawn, so the text stays silent on it rather than guessing. If coins do have
an exit path, that is a legal and compliance question well beyond a wording fix
— see the escalation clause in §7.

**Made true since:** the new text tells players they can check a spin, and at
first there was no in-app way to do so — the client fetched the seed data and no
screen showed it. Settings now opens a fairness sheet with the committed
server-seed hash, the client seed and the nonce (§10).

---

## 1. Creative position & visual-difference audit

The brief required this audit before delivery. It is answered against the
shipped build.

**Original to this game.** The title *Aetherfall: Vaults of the Skyfire*; the
Ilyra character concept (silver-blue hair, asymmetric bronze armour, crescent
staff — no beard, no toga, no thunderbolt); all eight symbol families (rune
prism, ember shard, spiral seed, orbit stone, copper astrolabe, meteor-heart
capsule, aurora compass, skyfire crown); the three specials (Prism Wild, Vault
Key, Ember Charge); every feature name (Skyfire Vault, Ember Charge,
Constellation Lock, Starburst Tumble); all four celebration tiers (BRIGHT HIT,
SKYFIRE SURGE, CELESTIAL BREAK, AETHERFALL); the entire paytable and every
tunable; the indigo / petrol-blue / cyan / mint / ember / copper palette; the
centred-compass composition with the hero in an observatory window *above* the
board rather than beside it; the charge-as-percentage math; and the audio
identity of crystalline pulses and granular impacts.

**Broad genre conventions retained** — non-exclusive mechanics, not protected
expression: a 6×5 board, pay-anywhere scoring on 9+ matching symbols, tumbling
removal-and-refill, a collectible multiplier-type symbol, a scatter-triggered
free-round feature, and a bet / autoplay / spin control bar.

**Deliberately excluded:** the reference title, logo and typography; Zeus or any
bearded lightning deity; Greek temples, marble columns, gates and thunderbolts;
the purple-and-gold Greek-casino palette; the character-beside-the-reels layout;
gold-coin fountains and orchestral trumpets; "BIG / MEGA / SUPER WIN"
terminology; and any published paytable, multiplier ladder or max-win claim.

No reference screenshots, extracted frames or provider assets were used at any
point. The art brief carries the same guardrail for whoever generates the
artwork.

---

## 2. Game design document

### 2.1 Board and scoring

- 6 columns × 5 rows = 30 cells. Symbol weights are uniform across columns —
  this is a pay-anywhere board, not payline reels.
- A win is **9 or more** matching symbols anywhere on the board (`MIN_MATCH`).
  Adjacency is irrelevant. Symbols are counted before removal.
- Prism Wild counts toward every standard symbol simultaneously; it never counts
  toward the Vault Key.
- Multiple symbol families can win on the same grid; each pays independently.

### 2.2 Paytable

Payout as a multiple of total bet, in three count bands.

| Symbol | 9–11 | 12–14 | 15+ |
|---|---|---|---|
| L1 rune prism | 0.95× | 2.3× | 5.5× |
| L2 ember shard | 1.15× | 2.85× | 6.5× |
| L3 spiral seed | 1.3× | 3.2× | 7.6× |
| L4 orbit stone | 1.8× | 4.5× | 11× |
| H1 copper astrolabe | 2.75× | 6.8× | 18× |
| H2 meteor-heart capsule | 4.5× | 11× | 32× |
| H3 aurora compass | 9× | 22× | 72× |
| H4 skyfire crown | 18× | 45× | 135× |

Data-driven: the table is a single exported constant served to the client via
`/aetherfall/state`, so the help panel always renders the live values — no client
release is needed to retune the game.

### 2.3 Symbol weights

| Symbol | Base | Bonus |
|---|---|---|
| L1 / L2 / L3 / L4 | 17 / 16 / 15 / 13 | 14 / 13 / 12 / 11 |
| H1 / H2 / H3 / H4 | 10 / 8 / 6 / 4 | 11 / 9 / 7 / 5 |
| Prism Wild | 3 | 5 |
| Vault Key | 2.6 | 2.6 |
| Ember Charge | 5.4 | 8.4 |

### 2.4 Ember Charge

Values `+2, +3, +5, +8, +12, +20, +35, +60` with weights
`30, 25, 20, 12, 7, 3.5, 1.8, 0.7`. A charge only resolves on a tumble that
already produced a symbol win; charges on losing grids are ignored and stay on
the board.

- **Base play:** every charge collected across the cascade is summed, then
  applied once — `floor(baseWin × (1 + charge/100))`.
- **Skyfire Vault:** charge accumulates in a persistent Charge Bank across all
  free tumbles and is applied once to the whole bonus total at the end.

Deliberately capped and percentage-based rather than an uncapped orb multiplier,
so per-spin exposure stays bounded.

### 2.5 Skyfire Vault bonus

- Trigger: **4+ Vault Keys on the first grid of a spin** (`VAULT_KEY_TRIGGER`).
  Only the opening deal can trigger; keys arriving mid-cascade cannot.
- Award: **12 free tumbles**.
- Retrigger: **3+ keys on a single free tumble adds 3 tumbles**.
- Runs on the richer bonus weight table (more wilds, more charges, more highs).
- A 400-iteration guard bounds a pathological retrigger chain.

Measured: triggers roughly **1 in 115 spins**, averages **~21× bet**, and
supplies ~18 of the ~97 points of total RTP.

### 2.6 Constellation Lock

Skyfire Vault only. Each winning tumble pins one random standard-symbol cell.
A pinned cell keeps both its symbol and its row while everything else falls
around it, and the pin carries into the next free tumble — `refill` writes only
to unpinned rows. A pin resists gravity, not scoring: a pinned cell can still
form part of a win, and clearing it releases the pin, which is what stops a
pinned winning symbol from being re-counted forever. Once
`CONSTELLATION_LOCK_TARGET` (3) cells are pinned the threads connect, the pins
are spent, and a **Starburst Tumble with a guaranteed Prism Wild** is inserted.

The board draws each pinned cell with a mint border, a glow, a pin badge and a
constellation thread across its foot, and the HUD shows the count.

**This was previously a lie.** The original build incremented a counter per
winning tumble and awarded the Starburst, but pinned nothing — `refill` ran
normally and no cell was ever held — while the help panel claimed cells were
locked. Implementing it for real **cost about 1.3 points of RTP**, because a
pinned symbol reduces the refill churn that generates fresh wins. That is why
`VAULT_BONUS_START_TUMBLES` is 13 rather than 12: the tumble buys the value back
where it was lost, rather than inflating the paytable for everyone.

### 2.7 Celebration tiers

On grand total ÷ bet: **BRIGHT HIT** ≥10×, **SKYFIRE SURGE** ≥25×, **CELESTIAL
BREAK** ≥50×, **AETHERFALL** ≥100×. Below 10× there is no celebration, only the
sequence-win readout.

### 2.8 Fairness and integrity

- Provably fair, same contract as بلينكو and طيّار:
  `HMAC-SHA256(serverSeed, "clientSeed:nonce:block")` expanded block by block, so
  an open-ended cascade can keep drawing bytes.
- `getFairness` publishes the server-seed hash; `setClientSeed` and
  `rotateServerSeed` (which reveals the previous seed) are exposed; `verifySpin`
  recomputes any past spin from revealed seeds.
- Server-authoritative: one request resolves the entire spin including the whole
  bonus, and the client only replays pre-computed frames. It never decides a
  symbol, a tumble or a payout.
- The stake is deducted with an atomic conditional `updateMany` so parallel spins
  cannot overdraw, and is refunded if resolution throws.
- Rate-limited per user at the route layer.
- **Caveat:** seeds and history live in in-process `Map`s, so both reset on every
  backend restart or deploy and neither survives horizontal scaling. A player
  mid-verification loses the ability to check a spin after a restart.

---

## 3. Interaction specification

**Composition (portrait, mobile-first).** Top bar: `AETHERFALL` title, coin
balance, mute, settings, help. Above the board: the
observatory-window hero portrait, which changes mood (`idle` / `win` / `bonus`).
Centre: the 6×5 chamber grid inside a compass ring. Left rail: Skyfire Charge
meter and tumble count. Right rail: sequence win and Star Shards. Bottom: the
bet − / + selector, the large `IGNITE` button, and `AUTO`, which swaps to a red
`STOP` while running.

**Spin loop.** IGNITE → button depresses with the ignite cue → grid populates →
each cascade frame highlights winners, shows a floating count/reward label,
dissolves winners into the charge meter, drops survivors and refills → repeats
until a frame produces no win. At the end the math is shown explicitly:
`baseWin × (1 + charge%) = baseTotal`. The bonus summary (total, highest charge,
cascade count) follows if the vault ran, then the celebration overlay if a tier
was reached.

**Autoplay.** Repeats at the current bet with a fixed 450 ms gap. `STOP` is
visible the whole time and ends it immediately. It self-stops on insufficient
balance with an Arabic notice.

**Failure states.** A bet outside 20–20,000 and an insufficient balance both
return a typed error code and an Arabic message; the error cue is a short low
tone, never a harsh fail sound.

---

## 4. Animation timing sheet (as built)

All values are the shipped constants. Reduced Motion multiplies every sequenced
wait by **0.4** and drops the celebration particle layer entirely.

| State | Duration | Cue | Notes |
|---|---|---|---|
| IGNITE press | 200 ms | `ignite` | Button scale |
| Grid population | 420 ms | `chamberPopulate` | Staggered drop |
| Symbol landing / tile | 260 ms container, 220 ms scale | `refill` | Per tile |
| Win highlight + reward label | 700 ms | `winDiscovery` | Label readable at rest |
| Winner dissolve | 260 ms | `dissolve` | Shards travel to the charge meter |
| Gravity fall + refill | 240 ms | `refill` | 500 ms total between grid states |
| Inter-frame stagger | 180 ms | — | Between cascade frames |
| Math banner | 1,100 ms | — | base → charge → total |
| Autoplay gap | 450 ms fixed | — | Not scaled by reduced motion |
| Bonus transition | 3,000 ms (900 ms reduced) | `bonusTransition` | **Skip at 800 ms** |
| Celebration counter | 1,400 ms (400 ms reduced) | tiered sting | **Skip at 500 ms** |
| Celebration particles | 3,200 ms | — | Suppressed in reduced motion |
| Bonus summary | user-dismissed | `bonusSummary` | Totals + replay |

The 260 + 240 ms grid-state rhythm sits inside the 450–650 ms band the brief
asked for, and the 700 ms win-label hold matches its stated readability target.

---

## 5. Audio cue sheet

18 cues, all present in `app/assets/sounds/`, generated by
`generate_aetherfall_sounds.py`. Playback runs through four channels in
`aetherfall_sfx.dart` — UI, landing, feature, and a round-robin pool of tumble
players so simultaneous win discoveries layer instead of cutting each other off.

| Cue | Asset | Vol | Channel |
|---|---|---|---|
| Button activation | `aetherfall_ignite.wav` | 0.50 | UI |
| Chamber population | `aetherfall_populate.wav` | 0.35 | UI |
| Win discovery | `aetherfall_win.wav` | 0.50 | tumble pool |
| Symbol dissolve | `aetherfall_dissolve.wav` | 0.40 | landing |
| Refill | `aetherfall_refill.wav` | 0.30 | landing |
| Charge landing | `aetherfall_charge.wav` | 0.45 | feature |
| Wild activation | `aetherfall_wild.wav` | 0.50 | feature |
| Key collection | `aetherfall_key.wav` | 0.55 | feature |
| Bonus transition | `aetherfall_bonus_transition.wav` | 0.70 | feature |
| Constellation lock | `aetherfall_lock.wav` | 0.45 | feature |
| Starburst tumble | `aetherfall_starburst.wav` | 0.65 | feature |
| BRIGHT HIT | `aetherfall_celebrate_low.wav` | 0.80 | feature |
| SKYFIRE SURGE | `aetherfall_celebrate_mid.wav` | 0.80 | feature |
| CELESTIAL BREAK | `aetherfall_celebrate_high.wav` | 0.80 | feature |
| AETHERFALL | `aetherfall_celebrate_top.wav` | 0.80 | feature |
| Bonus summary | `aetherfall_bonus_summary.wav` | 0.60 | UI |
| Mute toggle / UI click | `aetherfall_click.wav` | 0.40 | UI |
| Error / disabled input | `aetherfall_error.wav` | 0.40 | UI |

**Not built:** the master volume slider, independent music-vs-SFX toggles, and
the separate reduced-intensity audio mode. There is one combined Sound switch,
and no music bed — only these one-shots.

---

## 6. Asset list & delivery status

Every path, size and generation prompt lives in `AETHERFALL_ARTWORK_BRIEF.md`.

| Group | Files | Status | Wiring |
|---|---|---|---|
| Sound | 18 wavs | **Delivered** | Wired |
| Standard symbols | `symbol_l1…h4` | **Delivered** | Wired |
| Special symbols | `symbol_wild`, `symbol_key`, `symbol_charge` | **Delivered** (regenerated) | Wired |
| Hub tile | `cards/card_aetherfall.png` | **Delivered** | Wired |
| Hero portraits | 3 × `hero_portrait_*` | **Delivered** | Wired |
| Backgrounds | `bg_observatory`, `bg_bonus_vault` | **Delivered** | Wired |
| FX textures | 5 particle / ribbon PNGs | **Delivered** | Wired |
| UI chrome | `btn_ignite`, `btn_auto` | **Delivered** | Wired |
| UI chrome | `meter_frame` | **Delivered** | Wired — the charge readout is now a real meter |

### What arrived, and what had to be repaired

The renders came back at ~1,250 px and 1–2.8 MB each, **42 MB in total**, every
filename doubled (`symbol_l1.png.png`), and 19 of the 22 assets that needed a
transparent background were flat RGB with the background baked in.

Repaired in one pass (`app/assets/images/aetherfall/`, now **7.2 MB**):

- Filenames de-doubled.
- Alpha lifted out of the baked background. Two strategies, because one does not
  fit both kinds of art: **glow assets** (the five FX textures, drawn on black)
  take alpha from luminance, which is the physically correct matte for additive
  light and keeps the soft falloff; **solid objects** get a flood fill inward
  from the corners so only the *connected* background is cut, leaving dark
  detail inside the object intact, then a 2 px erode to eat the resample fringe.
- `symbol_l1`–`l3` came on **white**, which left a bright rim that read badly on
  the dark board. Keying alone could not fix it, so those three are matted by
  distance-from-white and then un-premultiplied — `obj = (observed − (1−a)·white) / a`
  — which recovers the true edge colour and removes the halo.
- Everything resized to the sizes the app draws at and recompressed.
- `hero_sheet.png` moved to `docs/aetherfall-hero-sheet.png`. It is reference art
  for future consistency, and `pubspec.yaml` bundles that directory wholesale, so
  leaving it there would have shipped 2.3 MB of concept art in the APK.

The pristine 42 MB originals are kept outside the repo in the session scratchpad,
so any of this can be redone without re-generating.

### The three scene renders, redone

`symbol_wild`, `symbol_key` and `symbol_charge` first came back as **scenes**
rather than isolated objects — a studio backdrop with a floor and a cast shadow,
soil, and sand respectively. No keying separates an object from a floor it is
standing on, so they were regenerated with the scene explicitly forbidden:
*plain solid pure-black background, object floating, nothing beneath it, no
ground, no floor, no surface, no cast shadow, no backdrop, no scene.*

They came back correct, and a black plate allows a better matte than the first
batch got: the flood fill establishes what is background, then luminance is
folded back in, so the glow each object throws survives as partial alpha instead
of being cut to a hard silhouette.

They also arrived 1536×1024 landscape with the object floating in the middle, so
each is cropped to its own bounding box and re-centred on a square canvas —
otherwise they would sit on the board at roughly two-thirds the size of every
other symbol.

**Every symbol on the board is now cleanly isolated.** One cosmetic leftover:
the Vault Key is a tall, slim shape, so squaring it leaves more empty margin
than the chunkier symbols have and it reads slightly smaller in its chamber.

---

## 7. Risk plan

| # | Risk | Severity | State | Action |
|---|---|---|---|---|
| 1 | RTP >100% — the game drains coins at scale | **Critical** | **Closed** | Retuned to 97%; harness committed and fails the run at 100% (§0.1) |
| 2 | Free-play disclaimer over a real coin economy | **High** | **Closed** | Coin economy kept; every free-play label removed (§0.2) |
| 3 | Help panel overstates Constellation Lock | Medium | **Closed** | Implemented for real; RTP re-measured (§2.6) |
| 3b | Help text says a spin can be checked, but no fairness UI exists | Medium | **Closed** | Fairness sheet in Settings (§10) |
| 4 | Seeds and history in process memory | Medium | **Open, deliberately** | Shared with بلينكو and نيون فورتشن; needs one cross-game change plus a migration (§10) |
| 5 | All artwork undelivered | Medium | Open | Generate per the art brief; symbols first |
| 6 | Accessibility below the brief's bar | Medium | **Closed** | Volume, high contrast, symbol markers, left-handed, semantics (§10) |
| 7 | No deterministic QA mode | Medium | **Closed** | `npm run sim:aetherfall -- --scenarios` (§10) |
| 8 | No landscape / desktop layout | Low | Open | Portrait only; fine if mobile-only is accepted |
| 9 | Creative / IP distinctness | Low | **Controlled** | §1 audit; guardrail repeated in the art brief |
| 10 | Coin over- or under-draw on parallel spins | Low | **Controlled** | Atomic conditional decrement, refund on failure |

**Escalation clause, unchanged from the brief:** if a product owner asks to turn
this into real-money gambling, stop and require separate legal, jurisdictional,
certification and responsible-gambling review.

---

## 8. Acceptance checklist

| Criterion | Result |
|---|---|
| Play loop understandable without external instructions | **Pass** |
| Every win visually and numerically explainable | **Pass** — base → charge → total shown explicitly |
| Bonus state clearly distinct | **Pass** — transition, palette shift, dedicated HUD |
| Autoplay stops on request | **Pass** — STOP always visible, self-stops on low balance |
| Mute works immediately | **Pass** |
| Reduced motion removes shake and flashing | **Pass** — 0.4× timing, particle layer dropped |
| Skip on celebration (500 ms) and bonus transition (800 ms) | **Pass** |
| Art original, no copied protected assets | **Pass** — see §1 |
| Help panel accurately describes current rules | **Pass** — Constellation Lock now does what the text says (§2.6) |
| On-screen text matches what the code charges | **Pass** — states the coin cost and bet range (§0.2) |
| RTP measurable and regression-guarded | **Pass** — `npm run sim:aetherfall` |
| Bounded, non-exploitable economics | **Pass** — 97% RTP, measured and enforced (§0.1) |
| Runs smoothly on a mid-range device | **Untested** — still no device (§10) |
| No important text overlaps symbols at 360 px | **Pass** — 360px renders assert against layout overflow |
| Deterministic demo mode for QA | **Pass** — reproducible scenario table (§10) |
| Screen-reader labels on controls | **Pass** — symbols, controls, settings and the fairness sheet are labelled |
| High-contrast mode | **Pass** |
| Colour-blind symbol markers | **Pass** — per-family glyph, so colour is not the only difference |
| Left-handed control option | **Pass** — mirrors the bet/spin row |
| Language placeholder support | **Not built** — English labels with Arabic error strings |
| Master volume slider | **Pass** — one Sound switch plus a volume slider; there is no music bed, so a music/SFX split would control nothing |
| Session-play reminder | **Pass** — every 50 spins, a notice; never blocks play |
| Reset demo progress | **Partial** — resets Star Shards only, not the balance |

---

## 9. Recommended order of work

1. ~~Retune the paytable and commit the simulation harness.~~ **Done** — 97% RTP,
   `npm run sim:aetherfall` (§0.1).
2. ~~Decide free-play vs coin economy, and make the on-screen text match.~~
   **Done** — coin economy kept, labels corrected (§0.2).
3. Reword the Constellation Lock help text, or build the real lock (§2.6).
4. Generate and drop in the symbol PNGs and the hub tile — no code needed (§6).
5. Accessibility pass: `Semantics` labels, high contrast, colour-blind outlines,
   split audio toggles (§8).
6. Move seeds and history out of process memory (§7, risk 4).
7. Device pass at 360 px and on mid-range hardware; record the results.

---

## 10. Closing out the punch list

### Fairness, surfaced

`aetherfall_fairness.dart` is reachable from Settings and shows the committed
server-seed hash, the player's client seed and the current nonce, with copy
buttons and a field to set a new client seed. The help text already told players
a spin could be checked; now it can be. The nonce rides back on every spin
response, so the sheet stays current without another round trip.

### Accessibility

- **Volume slider** scaling every cue, alongside the Sound switch. There is
  deliberately no music/SFX split: the game has no music bed, only one-shot
  cues, so the second toggle would control nothing.
- **High Contrast** — near-black chambers with strong symbol outlines.
- **Symbol Markers** — a per-family glyph in the corner of each tile, so the
  symbols can be told apart without relying on colour.
- **Left-handed Controls** — mirrors the bet/spin row so IGNITE falls under the
  other thumb.
- **Session reminder** — a notice every 50 spins. A nudge, not a limit; it never
  blocks play.
- **Semantics** on symbols (name, charge value, selected state), the spin
  button, every settings control and the fairness sheet.

### Deterministic QA

```bash
npm run sim:aetherfall -- --scenarios
```

Prints the first nonce that produces each interesting outcome — a plain loss, a
single tumble, a 3+ cascade, a charge resolution, a vault trigger, a
Constellation Lock, a Starburst Tumble, and each of the four celebration tiers —
then the exact `/aetherfall/verify` call that replays it.

Nothing is rigged: a spin is a pure function of the seed pair and the nonce, so
this is a search, not a debug path. It replays through the verification
endpoint rather than live play, because the server seed on a real account is
generated server-side and cannot be set — which is the property that makes the
commitment worth anything in the first place.

### The 360px sweep

`flutter test test/aetherfall_render_test.dart` renders base play, the vault, a
celebration and an accessibility pass at both 400px and **360px**, the narrowest
supported width, writing PNGs to `build/aetherfall-preview/`. A `RenderFlex`
overflow throws during layout, so these are assertions, not just screenshots.
This is what caught the bonus HUD overflowing when the constellation threads
were added, and it caught the lock indicator being too faint to see.

### Two things still open

**Seeds and history in process memory — open on purpose.** بلينكو, نيون فورتشن
and أثيرفول all keep their seed state in a module-level `Map`. That is a
platform-wide choice, not an Aetherfall bug, and the fix is one shared store
plus a Prisma migration against Postgres. Doing it for this game alone would
leave the three inconsistent, and a migration cannot be verified from here.
It deserves its own change across all three.

**No real-device pass — blocked.** There is no Android device or emulator
attached and no system images installed, and the screen needs a backend, a login
and a coin balance before it draws. The 360px render sweep covers the layout
risk; it does not cover frame rate, touch targets under a real thumb, or memory
on a mid-range phone. Someone has to run it on hardware.
