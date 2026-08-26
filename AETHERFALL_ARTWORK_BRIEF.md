# أثيرفول — Aetherfall: Vaults of the Skyfire — Artwork Brief

The game is fully built and playable right now with painted placeholder
glyphs (coloured glass tiles + icons) standing in for every symbol, so
nothing is blocked on art. Drop the files below into the listed paths with
the listed names and I will wire them in automatically — the app already
falls back to the painted glyph for anything missing, so partial deliveries
are completely fine.

**Legal/creative guardrail — read before generating.** This is an original
fictional game and must stay that way. Do not reference, name, or ask an
image model to imitate *Gates of Olympus*, Pragmatic Play, Zeus, Greek
temples/columns/lightning-god iconography, or any specific published slot's
logo, layout, or screenshots. Every prompt below already describes an
original character (Ilyra), an original pantheon-free sky/meteor/observatory
world, and original symbol names — use these prompts as written, or vary
them further, but don't feed them a reference screenshot to "match."

**Global rules for every prompt**
- Transparent background (PNG-32) for every symbol/icon/character asset,
  unless it's explicitly a background or hub tile (those are opaque).
- No text, no numbers, no watermarks, no logos baked into any image — all
  text and numbers are drawn by the app so they stay crisp and translatable.
- Dark-UI friendly: assets sit over a deep indigo → near-black gradient
  (`#0F1638` → `#07030F`). Avoid dark outlines that vanish against it —
  give every silhouette a soft light rim.
- Palette: deep indigo, petrol blue, cyan, ember orange, pale mint, brushed
  copper. Gold appears only as a restrained accent, never dominant.
- Deliver symbol/icon assets at 3× mobile size (see sizes below), centred
  with ~8% padding so glows aren't clipped.

---

## 1. Symbols — required first (these are already wired in code)

Every file goes in `app/assets/images/aetherfall/`. **Size: 300×300 px,
transparent.**

### Standard symbols (8)

| Path | Prompt |
|---|---|
| `symbol_l1.png` | An original small glowing cyan glass prism marked with a simple three-line rune etched into its face, clean triangular faceted glass, soft internal refraction, gentle cyan-white bloom. Centred, isolated on transparent background, no text. |
| `symbol_l2.png` | An original small six-point crystal shard glowing warm ember-orange, dark etched glyph on its surface, faceted glass material, soft orange bloom. Centred, isolated on transparent background, no text. |
| `symbol_l3.png` | An original small organic spiral seed pod glowing pale mint-green, luminous spiral ridges, soft green aura, faintly translucent shell. Centred, isolated on transparent background, no text. |
| `symbol_l4.png` | An original small deep blue-black orbit stone with one thin rotating cyan ring around its equator, polished mineral surface, subtle starlight glints. Centred, isolated on transparent background, no text. |
| `symbol_h1.png` | An original small brushed-copper astrolabe instrument with fine engraved arcs and a tiny rotating needle, no Greek motifs, warm metallic highlights, faint cyan glow from its centre gem. Centred, isolated on transparent background, no text. |
| `symbol_h2.png` | An original small heart-shaped meteor capsule: a glowing orange-red molten core sealed inside faceted translucent containment glass, warm inner light, cool glass rim. Centred, isolated on transparent background, no text. |
| `symbol_h3.png` | An original small four-colour aurora compass disc (cyan/mint/ember/violet segments) with a thin glowing needle, brushed copper bezel, soft aurora-light bloom. Centred, isolated on transparent background, no text. |
| `symbol_h4.png` | An original small floating angular crystal crown made of pale icy-cyan crystal shards with fine copper trim at the base — NOT a royal/Greek crown, more like a floating ice-crystal formation — restrained warm gold only as a thin accent line. Centred, isolated on transparent background, no text. |

### Special symbols (3)

| Path | Prompt |
|---|---|
| `symbol_wild.png` | An original rotating translucent hexagonal glass prism with a bright white glowing core and faint rainbow internal refraction at its edges, premium glass material. Centred, isolated on transparent background, no text. |
| `symbol_key.png` | An original hexagonal brass/copper key with a glowing cyan core set into its head, fine mechanical engraving on the shaft, warm metal rim light. Centred, isolated on transparent background, no text. |
| `symbol_charge.png` | An original small glowing meteor capsule (distinct from symbol_h2 — simpler, rounder, more compact) in warm ember-orange, with a clean flat-ish front face where the app overlays a "+N%" number — keep that front area readable and not too busy. Centred, isolated on transparent background, no text or numbers baked in. |

---

## 2. Hub tile (games list artwork)

**Path:** `app/assets/images/cards/card_aetherfall.png`
**Size:** 1440×720 px (2:1, opaque — this one is cropped, a title is drawn
over the bottom third by the app)

> Key art for an original fantasy arcade game: a circular celestial compass
> interface with a 6×5 grid of glowing translucent falling-symbol chambers
> at its centre, seen at a slight angle. Behind it, floating dark basalt
> islands, a deep indigo sky, cyan aurora ribbons, and scattered meteor
> fragments with light trails. A small original silver-blue-haired winged
> guardian figure (see Section 3) is visible in silhouette in the upper
> corner, not the focal point. Palette: indigo, petrol blue, cyan, ember
> orange, brushed copper, restrained gold accent only. Premium, cinematic,
> dramatic lighting, like a modern arcade-game banner. Keep the bottom third
> darker and simpler — a title is overlaid there by the app. No text, no
> logos, no Greek architecture, no lightning-god imagery.

---

## 3. Ilyra, Warden of the Skyfire (hero)

Not wired into code yet — this needs a short follow-up pass once delivered
(the observatory-window portrait above the playfield currently shows a
mood-tinted painted icon). Send these whenever ready; they're not blocking.

**Path:** `app/assets/images/aetherfall/hero_sheet.png` (reference only,
doesn't need to be wired — useful for consistency across the other prompts)
**Size:** 1600×1000 px

> Create an original character reference sheet for Ilyra, Warden of the
> Skyfire, a fictional celestial guardian for a fantasy arcade game. Show
> front, three-quarter, and side views. Short silver-blue hair, angular
> face, teal eyes, asymmetric bronze-and-charcoal armor, a translucent
> meteor-glass shoulder cape, a crescent-shaped staff, small constellation
> tattoos, practical boots, athletic non-exaggerated proportions. Pose
> variations: neutral, curious, focused, celebrating, casting a skyfire
> ribbon. Distinct silhouette — no beard, no toga, no thunderbolt, no Greek
> deity styling. Clean studio background, consistent lighting, production
> concept-art quality, no text.

**Path:** `app/assets/images/aetherfall/hero_portrait_idle.png`,
`hero_portrait_win.png`, `hero_portrait_bonus.png`
**Size:** 400×400 px each, transparent, circular-safe (face centred, shoulders
cropped so it reads well inside a circular frame)

> A close, chest-up original portrait of Ilyra, Warden of the Skyfire (per
> the character sheet above), inside a small circular observatory-window
> framing. Idle version: calm, confident half-smile, looking slightly
> off-camera. [Win version: bright delighted expression, one hand raised,
> a small skyfire spark near her fingers.] [Bonus version: focused and
> intense, staff raised, faint cyan-ember glow reflecting on her face.]
> Soft rim light, painterly-but-clean fantasy game-art style, transparent
> background so it can sit inside a circular UI frame, no text.

---

## 4. Backgrounds & bonus environment

Not wired into code yet (the screen currently uses a flat indigo gradient) —
also a follow-up pass, not blocking.

**Path:** `app/assets/images/aetherfall/bg_observatory.png`
**Size:** 1440×2560 px (portrait, opaque)

> An original fantasy arcade game background: floating dark basalt islands
> above a cloud ocean, deep indigo sky, cyan aurora ribbons, distant meteor
> fragments with light trails, faint observatory structures on the horizon.
> Large calm empty centre area (the middle 65% must stay visually quiet) so
> a 6×5 game board and UI can sit on top of it. Cinematic, high detail, no
> text, no characters, no Greek temples or columns.

**Path:** `app/assets/images/aetherfall/bg_bonus_vault.png`
**Size:** 1440×2560 px (portrait, opaque)

> An original Skyfire Vault bonus environment: a floating observatory
> chamber above a dark cloud ocean, a circular aperture in the architecture,
> aurora ribbons, ember particles drifting upward, suspended copper
> instruments, thin glowing cyan constellation lines connecting distant
> points, a ringed planet visible far in the background. Leave the centre
> readable for a 6×5 game board and the lower area clean for HUD counters.
> Cinematic but functional, high contrast, no Greek architecture, no marble,
> no text.

---

## 5. Celebration & feature effects

Optional — the app currently draws these procedurally (particle dots, glow
text). Sending these lets me swap in real particle textures for a richer
look; not blocking.

**Size:** 512×512 px each, transparent

| Path | Prompt |
|---|---|
| `fx_particle_spark.png` | A small soft cyan-white radial light spark/sparkle, clean edges, additive-blend friendly on black, isolated on transparent background, no text. |
| `fx_particle_ember.png` | A small glowing ember-orange meteor fragment with a short light trail, isolated on transparent background, no text. |
| `fx_ribbon_compass.png` | A thin glowing compass-line ribbon trail, cyan fading to transparent at both ends, gentle curve, isolated on transparent background, no text. |
| `fx_constellation_thread.png` | A thin glowing mint-cyan constellation line with two small star-point nodes at each end, isolated on transparent background, no text. |
| `fx_key_unlock.png` | A radial burst of cyan-white light for a Vault Key trigger moment: bright core fading outward, a few small copper sparks, isolated on transparent background, no text. |

---

## 6. UI chrome (buttons, meters, frame)

Optional — the app currently draws these as solid-colour rounded buttons.
Send these for a fully "skinned" UI in a follow-up pass; not blocking.

**Size:** 720×220 px each, transparent, rounded-pill shape

| Path | Prompt |
|---|---|
| `btn_ignite.png` | A polished pill-shaped fantasy-arcade action button in glowing cyan-white with a bright top highlight, soft cyan glow beneath, thin brushed-copper inner border. Empty centre — no text or icon. Front-on view, isolated on transparent background. |
| `btn_auto.png` | A polished pill-shaped button in brushed copper with a warm glossy highlight, soft copper glow beneath, thin cyan inner border. Empty centre — no text or icon. Front-on view, isolated on transparent background. |

**Path:** `app/assets/images/aetherfall/meter_frame.png`
**Size:** 480×160 px, transparent

> A slim glassy meter/gauge frame for a fantasy arcade HUD, cyan-and-copper
> trim, dark translucent glass centre panel where the app overlays its own
> fill bar and text. Empty centre, no text, isolated on transparent
> background.

---

## 7. Sound (optional — if you can source or generate these too)

All under `app/assets/sounds/`, short and layerable (per the direction:
calm/percussive in base play, an added aurora-harmonic layer in the bonus).

| Path | What it is |
|---|---|
| `aetherfall_ignite.wav` | Short mechanical activation click/thunk when IGNITE is pressed. |
| `aetherfall_populate.wav` | Soft granular whoosh as the grid populates. |
| `aetherfall_win.wav` | Bright crystalline chime when a win is discovered — needs to layer cleanly if multiple symbols win at once. |
| `aetherfall_dissolve.wav` | Quick glassy shatter/dissolve tick for winning symbols clearing. |
| `aetherfall_refill.wav` | Soft falling/settling tick as new symbols drop in. |
| `aetherfall_charge.wav` | A brighter granular "power-up" tick when an Ember Charge is collected. |
| `aetherfall_wild.wav` | A short shimmer when a Prism Wild activates in a win. |
| `aetherfall_key.wav` | A mechanical lock-turning + pressure-release sound for Vault Key collection/retrigger. |
| `aetherfall_bonus_transition.wav` | A 2.5–3.5s rising, airy transition sweep into the Skyfire Vault. |
| `aetherfall_lock.wav` | A short chime when a Constellation Lock cell locks in. |
| `aetherfall_starburst.wav` | A bright rising sparkle burst for a Starburst Tumble. |
| `aetherfall_celebrate_low.wav` | Short celebratory sting for BRIGHT HIT. |
| `aetherfall_celebrate_mid.wav` | Bigger sting for SKYFIRE SURGE. |
| `aetherfall_celebrate_high.wav` | Bigger still for CELESTIAL BREAK. |
| `aetherfall_celebrate_top.wav` | The biggest, most dramatic sting for AETHERFALL. |
| `aetherfall_bonus_summary.wav` | A settling chime for the bonus summary screen. |
| `aetherfall_click.wav` | Small neutral UI click for buttons/toggles. |
| `aetherfall_error.wav` | A short, non-harsh low tone for a disabled/invalid action. |

No orchestral fanfares, no thunderclaps, no lightning zaps — crystalline
pulses, granular meteor impacts, airy synth pads, soft choir-like textures.

---

## What I do once you deliver

1. Symbols (`symbol_*.png`) and the hub tile (`card_aetherfall.png`) need
   **no code changes** — they're already wired with graceful fallback in
   `aetherfall_symbols.dart` and `games_hub_screen.dart`. Drop the files in
   and they appear on next hot-reload/build.
2. Hero portraits, backgrounds, UI chrome and particle textures need one
   short follow-up pass to wire in (swap the painted placeholders for
   `Image.asset`) — say the word once any of those are ready and I'll do it.
3. Sounds get wired into `aetherfall_sfx.dart`'s existing calls.

Partial deliveries are completely fine — send symbols first since those are
seen on every single spin.
