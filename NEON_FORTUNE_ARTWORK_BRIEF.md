# نيون فورتشن — Neon Fortune: Tiger City — Artwork Brief

The game is built and playable right now with painted placeholder glyphs
(neon plates with icons, letters and numerals) standing in for every symbol, so
nothing is blocked on art. Drop the files below into the listed paths with the
listed names and they are picked up automatically — the app already falls back
to the painted glyph for anything missing, so partial deliveries are completely
fine.

**Legal/creative guardrail — read before generating.** This is an original
fictional game and must stay that way. Do not reference, name, or ask an image
model to imitate *Jackpot Frenzy*, *Frenzy Spin*, or any specific published
slot's logo, layout, mascot or screenshots, and never feed a reference
screenshot to "match". The genre's stock combination — a tiger head, purple and
gold, and a MINI/MINOR/MAJOR/GRAND ladder — is exactly where this game has to
look different, so the prompts below deliberately push elsewhere:

- **Cyan carries the light, gold is an accent.** The reference is gold-dominant;
  this game is violet and magenta with cyan rim light, and gold appears only on
  numbers, frames and the jackpot tokens.
- **The tiers are named** <span dir="rtl">شرارة / وهج / منارة / مدينة</span>
  (Spark / Glow / Beacon / City), not the genre ladder.
- **The mascot sits in a window above the board**, not beside the reels.

**Global rules for every prompt**

- Transparent background (PNG-32) for every symbol/icon asset; backgrounds and
  the cabinet frame are opaque.
- No text, no numbers, no watermarks, no logos baked into any image — all text
  and numbers are drawn by the app so they stay crisp and translatable, and so
  Arabic and English share one asset.
- Dark-UI friendly: assets sit on a midnight violet ground (`#17062E` →
  `#250A46`). Avoid dark outlines that vanish against it — give every silhouette
  a soft light rim.
- Palette: midnight violet `#17062E`, deep plum `#250A46`, electric purple
  `#8B22E8`, hot magenta `#EA35D7`, cyan `#3CD7FF`, gold `#FFC928`, lime
  `#93E832` (positive actions only), coral `#FF6D54` (warnings only).
- Deliver symbol assets at 3× mobile size (300×300), centred with ~8% padding so
  glows are not clipped.

---

## 1. Symbols — required first (these are already wired in code)

Every file goes in `app/assets/images/neon/`. **Size: 300×300 px, transparent.**

### Picture symbols (6)

| Path | Prompt |
|---|---|
| `symbol_tiger.png` | An original stylized tiger guardian head, confident and friendly rather than snarling, deep amber fur with charcoal striping, sapphire eyes, a slim violet-and-cyan energy ring behind the head, front three-quarter view, polished 3D game art, strong readable silhouette. Centred, isolated on transparent background, no text. Not based on any existing game character. |
| `symbol_panther.png` | An original faceted crystal panther mask carved from translucent violet gemstone, cyan edge lighting along the facets, subtle internal refraction, front-facing, premium 3D game art. Centred, isolated on transparent background, no text. |
| `symbol_crane.png` | An original pearl-white origami-influenced crane head and neck with a magenta crest, thin gold trim on the beak, cool cyan rim light, elegant and calm. Centred, isolated on transparent background, no text. |
| `symbol_koi.png` | An original turquoise koi fish curving through a thin magenta light halo, luminous scales, soft cyan bloom, gentle motion in the pose. Centred, isolated on transparent background, no text. |
| `symbol_lantern.png` | An original hanging city lantern in warm coral-orange glass with a cyan tassel and slim gold frame, warm inner light, cool rim. Centred, isolated on transparent background, no text. |
| `symbol_coin.png` | An original gold medallion stamped with a simple four-point city-star emblem — a geometric star, not a currency mark, not a national symbol — brushed gold face, violet shadow in the relief. Centred, isolated on transparent background, no text. |

### Card ranks (5)

| Path | Prompt |
|---|---|
| `symbol_a.png` | The letter A as an original beveled gold slot symbol with a magenta neon edge glow, chunky rounded geometry, deep violet inner shadow. Centred, isolated on transparent background, no other text. |
| `symbol_k.png` | The letter K, same construction, cyan neon edge. |
| `symbol_q.png` | The letter Q, same construction, electric-violet neon edge. |
| `symbol_j.png` | The letter J, same construction, cool blue neon edge. |
| `symbol_10.png` | The numerals 10, same construction, magenta neon edge, slightly wider footprint than the single letters. |

*(These five are the one exception to "no text in artwork" — the glyph **is** the
symbol. Keep them as clean letterforms with no additional wording.)*

### Specials (3)

| Path | Prompt |
|---|---|
| `symbol_wild.png` | An original circular medallion holding a polished tiger-eye gemstone, gold and violet frame, small electric arcs crossing the rim, luminous centre. Centred, isolated on transparent background, **no lettering** — the app draws the WILD label so it stays translatable. |
| `symbol_scatter.png` | An original luminous faceted prism ticket floating inside a magenta-and-cyan halo, three small star flares, thin gold bevel along the edges. Centred, isolated on transparent background, no text. |
| `symbol_token.png` | An original coin-like jackpot token: cyan luminous core inside a gold-and-violet frame, a simple geometric city-star relief, clean flat front face where the app can overlay a tier colour. Centred, isolated on transparent background, no text. |

## 2. Jackpot tier tokens (4)

`app/assets/images/neon/token_t1.png` … `token_t4.png`, 200×200, transparent.
One shared frame, four distinct accents, so they read as a ladder:

> "Four original jackpot token medallions sharing one gold-and-violet frame,
> each with a different luminous core colour — lime, cyan, magenta, gold — and a
> different simple geometric emblem inside: a spark, a soft glow orb, a beacon
> lamp, a city skyline. Consistent perspective, scale and lighting across all
> four. Transparent background, no text, no currency signs, no cash imagery."

Order: `token_t1` = Spark (lime), `token_t2` = Glow (cyan), `token_t3` = Beacon
(magenta), `token_t4` = City (gold).

## 3. Cabinet and banner

| Path | Size | Prompt |
|---|---|---|
| `cabinet_frame.png` | 1080×760, transparent | "A tall portrait slot-cabinet frame in midnight violet metal, rounded corners, slim gold micro-ornaments at the corners only, electric-purple and cyan rim tubes running the inside edge, deep plum reel well, empty centre sized for a five-by-three grid. Premium arcade style, restrained rather than busy. No logos, no text." |
| `crown_banner.png` | 1080×260, transparent | "A wide curved crown band for the top of a slot cabinet — an arc, not a rectangle — in deep plum with an electric-violet rim tube and four evenly spaced recessed panels for jackpot meters. Magenta-to-violet inner light, thin gold edging. No lettering of any kind." |

## 4. Backgrounds (opaque)

| Path | Size | Prompt |
|---|---|---|
| `bg_city.png` | 1080×1920 | "A vertical portrait night-city background: layered violet skyscraper silhouettes, small cyan windows, magenta atmospheric haze, a soft radial glow behind the centre where the cabinet sits. Decorative but low contrast — it must frame a game board, not compete with it. No real-world landmark, no readable text, no logo." |
| `bg_rush.png` | 1080×1920 | "A vertical rooftop background above a futuristic violet city at night, a large magenta moon low on the horizon, cyan light trails between towers, drifting gold prism particles. Celebratory, uncluttered, with an open central area for reels and counters. No text, no logo." |
| `bg_vault.png` | 1080×1920 | "A portrait interior of an elegant dark rooftop vault: violet stone walls, cyan edge lighting, gold trim, deep magenta atmosphere, and a clear flat central area where a three-by-three grid of capsules will be drawn. Premium and calm rather than cluttered. No text, no logo." |

## 5. Characters, effects and card art

| Path | Size | Prompt |
|---|---|---|
| `mascot_sheet.png` | 1536×1024, transparent | "An animation reference sheet for an original friendly tiger guardian mascot in a neon city game: idle, blink, celebratory fist pump, surprised, gentle wave, and a jackpot celebration pose. Six poses, consistent proportions and lighting, front three-quarter view, amber fur, violet-and-cyan rim light. Clean transparent background, no text. Not based on any existing character." |
| `chest_drop.png` | 256×256, transparent | "A compact gold-and-violet treasure chest with a glowing cyan prism visible inside the lid gap, small sparkles, friendly premium 3D icon that stays readable at 64 pixels. Transparent background, no text, no currency symbols." |
| `vfx_sheet.png` | 1536×1024, transparent | "A transparent VFX asset sheet for a neon slot game: gold coin-like geometric tokens carrying a four-point star emblem, cyan prism shards, magenta sparkles, soft violet light rays, and small controlled confetti bursts. Separate elements with generous padding between them. No real currency markings, no text." |
| `cards/card_neon.png` | 1080×540, opaque | "A wide 2:1 key-art banner for a neon-city slot game: the tiger guardian's head to one side, a violet cabinet silhouette behind, magenta and cyan light streaks, gold particles, deep violet ground. Leave the opposite third visually calm — the app draws the game's name over it. No text baked in, no logo." |

## 6. Sound — placeholders are in, replace them

`app/assets/sounds/neon_*.wav` already contains all fourteen cues, synthesized as
tones and filtered noise on a single pentatonic scale so nothing is silent and the
mix can be judged. They are **placeholders, not composed audio** — replace them
with the real thing at the same filenames. Every cue is decoration: a missing file
never interrupts a spin, and no result is ever communicated by sound alone.

`neon_spin.wav`, `neon_reel_stop.wav`, `neon_line_win.wav`, `neon_click.wav`,
`neon_scatter.wav`, `neon_token.wav`, `neon_rush_start.wav`, `neon_vault.wav`,
`neon_capsule.wav`, `neon_error.wav`, `neon_celebrate_low.wav`,
`neon_celebrate_mid.wav`, `neon_celebrate_high.wav`, `neon_celebrate_top.wav`.

Direction: an original upbeat electronic loop — soft synth bass, glassy
arpeggios, light percussion, warm marimba-like accents. Reel stops are short and
dry; the jackpot sting is a brief ascending motif with a bright chime. Nothing
should imitate a recognisable melody from an existing game.
