# أستيريون — Citadel of Asterion: artwork brief

Original 6×5 pay-anywhere tumbling game for SamaFox. The game ships playable with
its artwork **drawn in code** (`app/lib/screens/games/asterion_art.dart`), so
nothing below blocks release — this brief exists so commissioned art can replace
the painted version without redesigning the game.

Run `flutter test test/asterion_render_test.dart` to write current renders of
every screen to `build/asterion-preview/`, or
`flutter run -d chrome -t lib/dev/asterion_preview.dart` to poke at them live.

---

## 1. Creative distinction

The game is inspired by the genre conventions of Greek-myth cascade slots —
celestial temple, storm deity, tumbling symbols, additive multipliers,
scatter-triggered free spins. It is **not** a reproduction of any published
title, and nothing below may borrow one.

Specifically off-limits, for the artist and for anyone editing the code:

- Zeus, or any recognisable likeness of a published game's deity. Asterion is an
  invented character with his own identifying marks (see §3).
- Another game's name, logo, typography, symbol silhouettes, Greek-letter marks,
  UI composition, colour skin, soundtrack cues or exact interface phrases.
- "BIG WIN" / "MEGA WIN" as celebration wording. Ours are ومضة / اندفاع الرعد /
  عاصفة الآلهة / صاعقة أستيريون.

It is also deliberately a **different machine from أثيرفول**, which shares only
the 6×5 pay-anywhere shape:

| | أثيرفول | أستيريون |
|---|---|---|
| Win threshold | 9 matching | 8 matching |
| Wild | Prism Wild | none |
| Multiplier | Ember Charge, a **percentage** boost | Storm Orb, an **additive** multiplier that pins to the board |
| Feature | Skyfire Vault, tumbles + Constellation Locks | Skyfall Trials, 15 free spins on a meter that never resets |
| Palette | indigo / cyan / ember orange / copper | midnight indigo / cyan / moon-silver / amber, magenta accents |

Do not let the two games converge visually. أثيرفول is a warm observatory;
أستيريون is a cold storm citadel at dawn.

---

## 2. Art direction

- **Palette** — midnight indigo `#141A47`, deep night `#06071A`, electric cyan
  `#5EE0F5`, pale cyan `#BFF4FF`, moon-silver `#E7EEF8` / `#A9B8CE`, warm amber
  `#FFC46B`, magenta accent `#C061E8` (reserved for Storm Orbs and the trial).
- **Key light is upper-left** on every object, so shadows fall to the lower
  right. This is the single rule that keeps a symbol set from looking like it
  came from three artists.
- **Materials** — crystal, storm-blue metal, pale marble. Outlines are cool and
  thin; highlights are sharp. (القط الجشع is the opposite: warm, heavy outlines.)
- **Readability first.** Every symbol has to be told apart at ~48px on a 360px
  phone, in a grid of thirty. Tiny decorative detail turns to noise the moment
  the board tumbles.
- The centre of any background plate stays quiet: the board sits on it.

---

## 3. Asterion

An invented sky guardian, not a classical thunder god. Three marks identify him
at thumbnail size and must survive any redraw:

1. a **segmented crescent halo** — separate crystal arcs with gaps, spanning the
   top of the head, never a solid hoop;
2. a **silver braid** over his left shoulder;
3. a **two-pronged staff**, held in the right hand, clear of his face.

Supporting: storm-blue layered armour, moon-silver shoulder plates angled down
and out, a pale mantle that tapers to a collar and flares at the hem, an amber
sash. Bright cyan eyes, used sparingly. Dignified, not snarling.

He must never cover the board or the controls, and he must read at 150px wide.

### Moods the code already drives

`GuardianMood` in `asterion_art.dart`: `calm`, `attentive` (a near miss),
`strike` (an orb is being collected — staff raised, a bolt leaves the prongs),
`exultant` (a win), `trial` (the free-spin feature is running — a portal ring
stays open behind him). Any delivered art needs a frame for each.

---

## 4. Symbols

Twelve drawables. Names are original and are what the paytable shows.

| Id | Name | Concept |
|---|---|---|
| L1 | شظية المنشور | faceted cyan prism shard, star at its heart |
| L2 | قرص الشمس | amber hexagonal sun-disc, engraved radial rays |
| L3 | ختم المذنّب | violet rounded-diamond seal, comet with a sweeping tail |
| L4 | حجر المدّ | emerald teardrop tide stone, two wave glyphs |
| H1 | تاج الهلال | moon-silver diadem, glowing crescent set into the band |
| H2 | جرّة النجوم | blue astral amphora, silver constellation, glowing mouth |
| H3 | قيثارة العاصفة | dark-metal lyre with lit cyan strings |
| H4 | بوصلة الشمس | gold-and-silver compass rose, four radiant points |
| CREST | شعار أستيريون | scatter: silver medallion, segmented halo, two-pronged staff, amber star points |
| ORB | كرة العاصفة | multiplier: crystal core, four asymmetric wing fins, magenta shell, large readable numeral |

The scatter has to be spotted in a glance across thirty cells: symmetrical,
brighter than everything else, unmistakable at a distance. The orb's numeral is
drawn by the widget over the shell, so one shell serves 2x through 250x — keep
the core clear enough for four characters.

---

## 5. Prompts

Each asset is a standalone deliverable in the shared direction above.
Transparent background where stated, and no accidental lettering, watermarks,
logos or recognisable existing characters anywhere.

**A. Master style frame.** Wide landscape concept frame for an original mobile
game, "Citadel of Asterion": a 6-column by 5-row crystal-and-stone symbol grid
at centre-left, an original silver-haired storm guardian at the right holding a
two-pronged lightning staff, floating pale-marble observatory arches, layered
dawn clouds, indigo sky, cyan electricity, moon-silver metal, amber highlights,
restrained magenta accents. Premium 3D game art, crisp readable silhouettes,
cinematic but uncluttered lighting. No casino branding, no logos, no known
characters, no watermark, no small unreadable text.

**B. Asterion character sheet.** Front, three-quarter and side views plus pose
callouts for calm, attentive, staff-raised strike, exultant and portal-opening.
Adult celestial guardian: long silver braid over the left shoulder, segmented
crystal crescent halo, storm-blue layered armour, pale mantle, moon-silver
shoulder plates, amber sash, two-pronged lightning staff. Distinct silhouette,
dignified expression, bright cyan eyes used sparingly. No resemblance to Zeus or
any existing game character. Clean studio background, no text.

**C. Citadel background plate.** Wide, text-free environment: floating
pale-marble platforms, angular observatory arches, translucent cloud layers, a
distant dawn horizon, slow star field, suspended crystal constellations, indigo
and cyan atmosphere, restrained amber illumination. Leave the centre-left
quieter and darker for a 6×5 grid and keep a clear stage at the right for a
character. Layered for parallax. No people, no symbols, no words, no watermark.

**D. Storm-sky variant.** The same plate during the free-spin feature: darker,
colder, magenta-tinged, distant lightning behind the architecture, clouds
spiralling. Same camera, same composition, so the two can cross-fade.

**E. Symbol pack.** Ten original symbols as separate, clearly spaced objects on
a neutral dark ground, per the table in §4. Polished 3D materials, strong
bevels, consistent three-quarter camera, upper-left key light, readable at small
size. No Greek letters copied from another game, no brand marks, no words.

**F. Storm Orb set.** Six transparent-background orbs — 2x, 5x, 10x, 25x, 50x,
100x. Luminous crystal core, four asymmetric wing-like fins, cyan-to-magenta
energy shell, one restrained electrical arc, a clean centred numeral. Identical
silhouette and lighting across all six. Transparent background, clean alpha
edges, no logos.

**G. Scatter crest.** Single transparent-background emblem: circular moon-silver
medallion, segmented crescent halo around a stylised two-pronged staff, thin
cyan energy ring, four small amber star points. Symmetrical enough to read
instantly. No face, no deity likeness, no text.

**H. Button and HUD kit.** Large circular start control and its busy state, auto
and turbo toggles, plus/minus bet controls, help, settings, sound and fullscreen
icons, a coin-balance capsule, a sequence-win capsule and a free-spin counter.
Dark indigo glass, moon-silver borders, cyan energy highlights, amber active
states, high-contrast numerals, generous touch targets. Show default, hover,
pressed, disabled and active states. Arabic labels are drawn by the app — deliver
the components unlettered.

**I. Celebration overlay.** Wide transparent-background celebration frame:
crystal shards, star fragments, soft celestial discs and controlled radial
energy around a clear centre where a rapidly counting number sits. The four tier
names are typeset by the app, so leave the title area empty. Dramatic but clean.
No "BIG WIN", no logos, no watermark.

**J. Trial transition.** Cinematic frame for the free-spin entry: the crest
opening into a vertical cyan portal above a floating marble observatory, the
guardian in silhouette raising the two-pronged staff, clouds spiralling inward,
restrained lightning. Leave a clear central band for UI. No text.

**K. VFX sheet.** Text-free reference of the effects the screen needs: symbol
burst into crystal dust, vertical fall trails, cyan lightning arc from staff to
orb, orb-collection beam, win ring, cloud puff, small celestial discs, large
shard burst, screen-edge energy bloom. Each effect separated on a dark ground.

---

## 6. Where delivered art goes

Drop PNGs into `app/assets/images/asterion/` using the stems in
`AsterionArt.assetFor` (`symbol_l1.png` … `symbol_orb.png`). Nothing in the game
requires them: every call site paints its own version, and the painted symbol
stays as the fallback for a missing or unreadable file — the same contract as
بلينكو's peg and ball art.

Sound follows the same rule. `AsterionSfx` names every cue it would play
(`sounds/asterion_*.wav`); a missing file is silently skipped and never
interrupts a spin.

---

## 7. What the artwork must not contradict

The rules are server-side and the help panel states them in the player's
language. Art that implies different mechanics is wrong art:

- 8 or more matching symbols anywhere on 30 cells pays; there are no paylines.
- Storm Orbs never pay alone, never count toward a match, and never fall — they
  pin where they land until the tumbles stop.
- Orb values are **added**, never multiplied together: 4x + 6x + 25x is 35x.
- 4 crests in the opening deal award 15 free spins; 3 during the feature add 5.
- Inside the feature the multiplier meter never resets, and every win is
  multiplied by the whole meter.
- One spin cannot pay more than 5,000× the bet.
