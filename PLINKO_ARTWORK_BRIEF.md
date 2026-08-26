# بلينكو — Artwork Brief

Every asset below is required before the code switches from painted shapes to
artwork. Drop the files into the listed paths with the listed names and I will
wire them in; nothing else needs to change on your side.

**Global rules for every prompt**
- Transparent background (PNG-32) unless the asset is explicitly a background.
- No text, no numbers, no watermarks, no logos baked into the image — all
  numbers are drawn by the app so they stay crisp and translatable.
- Dark-UI friendly: assets sit on a near-black purple background (`#07030F` →
  `#1B0B3A`). Avoid dark outlines that disappear against it.
- Deliver at the stated pixel size (already 3× for mobile). Square assets must
  be perfectly centred with ~6% padding so glows are not clipped.

---

## 1. Background

**Path:** `app/assets/images/plinko/bg_board.png`
**Size:** 1440 × 2560 px (portrait, PNG, opaque)

> A dark futuristic casino interior background, deep violet and near-black gradient from top to bottom, subtle neon rim lighting in magenta and cyan along the edges, soft volumetric haze, a faint circular spotlight glow in the upper centre where a ball would drop from. Clean and uncluttered with a large empty centre area — the middle 70% must stay visually calm so a peg board can sit on top of it. No text, no characters, no furniture. Cinematic 3D render, high detail, 4k.

---

## 2. Pegs

**Path:** `app/assets/images/plinko/peg.png`
**Size:** 96 × 96 px (transparent)

> A single small glowing sphere peg for a Plinko board, polished chrome-white with a soft white bloom around it, bright specular highlight top-left, subtle blue-white rim light. Photorealistic 3D render, centred, isolated on transparent background. No shadow cast on the ground.

**Path:** `app/assets/images/plinko/peg_hit.png`
**Size:** 96 × 96 px (transparent)

> The same chrome-white glowing Plinko peg, but flaring bright on impact: intense white-hot core, strong radial bloom, a faint expanding ring of light around it. Photorealistic 3D render, centred, isolated on transparent background.

---

## 3. Balls (one per risk level)

**Size:** 128 × 128 px each (transparent)

| Path | Prompt |
|---|---|
| `app/assets/images/plinko/ball_low.png` | A small glossy emerald-green glowing sphere, like a polished gemstone marble, bright specular highlight top-left, soft green bloom radiating outward, subtle inner glow. Photorealistic 3D render, centred, isolated on transparent background. |
| `app/assets/images/plinko/ball_medium.png` | A small glossy golden-amber glowing sphere, like a polished gemstone marble, bright specular highlight top-left, soft warm gold bloom radiating outward, subtle inner glow. Photorealistic 3D render, centred, isolated on transparent background. |
| `app/assets/images/plinko/ball_high.png` | A small glossy crimson-red glowing sphere, like a polished gemstone marble, bright specular highlight top-left, soft red bloom radiating outward, subtle molten inner glow. Photorealistic 3D render, centred, isolated on transparent background. |

---

## 4. Multiplier slot tiles

Seven tiers, coloured by payout size. Each is a **wide rounded tile** the app
prints a number onto, so keep the centre flat and readable.

**Size:** 240 × 160 px each (transparent, rounded corners baked in)

| Path | Prompt |
|---|---|
| `app/assets/images/plinko/slot_1.png` | A rounded rectangular casino payout tile in soft lime green, glossy plastic finish with a subtle top highlight and a thin brighter inner border, flat readable centre. Front-on view, isolated on transparent background. No text. |
| `app/assets/images/plinko/slot_2.png` | Same tile in pale yellow-green. |
| `app/assets/images/plinko/slot_3.png` | Same tile in warm golden yellow. |
| `app/assets/images/plinko/slot_4.png` | Same tile in bright orange. |
| `app/assets/images/plinko/slot_5.png` | Same tile in deep orange-red. |
| `app/assets/images/plinko/slot_6.png` | Same tile in vivid crimson red with a faint outer glow. |
| `app/assets/images/plinko/slot_7.png` | Same tile in deep blood red shading to violet at the edges, with a strong menacing outer glow — the jackpot tile. |

**Path:** `app/assets/images/plinko/slot_flash.png`
**Size:** 320 × 240 px (transparent)

> A bright radial burst of light for a winning slot: white-hot centre fading to warm gold, soft outward rays, a few small glowing particles scattered upward. Additive-blend friendly on black. Isolated on transparent background.

---

## 5. Risk icons

**Size:** 192 × 192 px each (transparent)

| Path | Prompt |
|---|---|
| `app/assets/images/plinko/risk_low.png` | A modern minimal shield icon, emerald green with a soft glow, subtle glassy 3D bevel, clean flat-vector silhouette. Centred, isolated on transparent background. No text. |
| `app/assets/images/plinko/risk_medium.png` | A modern minimal balanced scales icon, golden amber with a soft glow, subtle glassy 3D bevel, clean flat-vector silhouette. Centred, isolated on transparent background. No text. |
| `app/assets/images/plinko/risk_high.png` | A modern minimal flame icon, crimson red with an intense inner glow, subtle glassy 3D bevel, clean flat-vector silhouette. Centred, isolated on transparent background. No text. |

---

## 6. Buttons

**Size:** 720 × 200 px each (transparent, rounded pill shape)

| Path | Prompt |
|---|---|
| `app/assets/images/plinko/btn_drop.png` | A polished pill-shaped casino action button in vivid emerald green, glossy 3D finish with a bright top highlight, soft green glow beneath, thin light inner border. Empty centre — no text or icon. Front-on view, isolated on transparent background. |
| `app/assets/images/plinko/btn_auto.png` | A polished pill-shaped casino button in deep violet-purple, glossy 3D finish with a bright top highlight, soft purple glow beneath, thin light inner border. Empty centre — no text or icon. Front-on view, isolated on transparent background. |

---

## 7. Hub tile (games list artwork)

**Path:** `app/assets/images/plinko/tile_plinko.png`
**Size:** 720 × 900 px (portrait, opaque — this one is cropped and scrimmed)

> Key art for a Plinko casino game tile: a glowing triangular grid of chrome pegs seen at a slight angle, a single bright golden ball mid-bounce with a light trail behind it, deep violet and teal neon lighting, dark cinematic background. Dramatic and premium, like a modern casino app banner. Composition should keep the bottom third darker and simpler — a title is overlaid there. No text.

---

## 8. Sound (optional — if you can source these too)

| Path | What it is |
|---|---|
| `app/assets/sounds/plinko/peg.wav` | Short soft tick, ~60 ms, for each peg hit. Needs to be pleasant when 16 fire in a row. |
| `app/assets/sounds/plinko/land_low.wav` | Neutral soft thud for a sub-1x landing. |
| `app/assets/sounds/plinko/land_big.wav` | Bright celebratory chime + sparkle for 10x and above. |
| `app/assets/sounds/plinko/click.wav` | Small UI click for buttons and toggles. |

---

## What I do once you deliver

1. Add the paths to `app/pubspec.yaml` under `assets:`.
2. Swap the painter's drawn circles/rects for the sprites in
   `app/lib/screens/games/plinko_screen.dart` — pegs, balls, slot tiles, flash.
3. Replace the emoji risk icons and the two buttons in the betting panel.
4. Point the hub tile at `tile_plinko.png` in
   `app/lib/screens/games_hub_screen.dart` (طيّار already works this way).
5. Wire the sounds to peg hits and landings if you send them.

Partial deliveries are fine — I will wire in whatever exists and leave the rest
painted, so the game keeps working throughout.
