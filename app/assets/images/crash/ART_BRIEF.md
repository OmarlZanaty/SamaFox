# طيّار (Crash) — art brief & generation prompts

Everything below is for the crash game screen. Generate each asset in ChatGPT
(image generation), download as PNG, and drop it into
`app/assets/images/crash/` using the exact filename given.

---

## 0. Why the current screen looks cheap

The palette is grey (`#1B1B1B`) plus a muted maroon (`#9B1C31`). Desaturated
grey reads as "unfinished" on a phone — real games in this genre use a
saturated dark **indigo/violet** base with hot neon accents. Grey has no hue to
catch light, so every glow drawn on top of it looks like dirt.

### New palette (use these exact values in every prompt)

| Role | Hex | Notes |
|---|---|---|
| Deep base | `#0B0A1F` | near-black indigo, never grey |
| Mid sky | `#16123A` | violet-navy |
| Horizon glow | `#FF6B35` | warm orange |
| Curve hot | `#FFB020` | gold, at the plane |
| Curve mid | `#FF3D7F` | hot magenta |
| Curve cool | `#7B2FF7` | violet, at the origin |
| Positive / cash out | `#3BE8B0` | mint-cyan (replaces the dull green) |
| Accent | `#22E6D3` | cyan |
| Gold / coins | `#FFC634` | |
| Danger / crash | `#FF2D55` | vivid, not maroon |
| Primary text | `#FFFFFF` | |
| Secondary text | `#A9A6C9` | lavender-grey, not plain white70 |

---

## 1. STYLE PREAMBLE — paste this at the top of EVERY prompt

> Modern mobile game art, premium casino-arcade style. Clean vector-illustration
> look with soft volumetric lighting and subtle neon rim-light. Rich saturated
> colours on a deep indigo-violet palette (#0B0A1F, #16123A) with hot magenta
> (#FF3D7F), gold (#FFB020) and cyan (#22E6D3) accents. Smooth gradients, gentle
> bloom, no harsh outlines, no flat cartoon shading, no photorealism, no text or
> letters anywhere in the image. Crisp edges suitable for game sprites.

Consistency matters more than any single asset — if one comes back in a
different style, regenerate it rather than accepting it.

---

## 2. Assets

### `plane.png` — the hero asset (most important)
Square 1024×1024, **transparent background**.

> [STYLE PREAMBLE]
> A single-engine propeller aeroplane seen from the side at a slight 3/4 rear
> angle, nose pointed up-right as if climbing. Glossy crimson-to-magenta metallic
> fuselage (#FF2D55 to #FF3D7F) with gold trim (#FFB020) along the edges, a
> tinted cyan glass cockpit canopy (#22E6D3), swept wings and a raised tail fin.
> Warm rim-light along the top edge, cool violet reflected light underneath.
> The propeller hub is visible at the nose but **the propeller blades are NOT
> drawn** — leave the space in front of the hub empty. Centred, filling about 70%
> of the frame, fully transparent background, no shadow on the ground, no text.

Blades are separate so the code can spin them.

---

### `propeller.png`
Square 512×512, **transparent background**.

> [STYLE PREAMBLE]
> A two-blade aircraft propeller seen head-on, centred, forming a vertical
> two-blade shape with a small gold hub (#FFC634) at the centre. Pale silver-white
> blades with a faint cyan edge glow, slight motion softness at the blade tips.
> Perfectly centred so it can be rotated around the image centre. Transparent
> background, no text.

---

### `sky_low.png`, `sky_mid.png`, `sky_high.png`
Portrait 1024×1536 each, opaque. These are the three altitude backgrounds.

**sky_low.png**
> [STYLE PREAMBLE]
> A vertical night-sky game background. Deep indigo-violet at the top (#16123A)
> fading to a warm orange-magenta glow along the bottom horizon (#FF6B35 into
> #FF3D7F). A few faint stars in the upper half. Soft, clean, uncluttered — this
> is a background layer, so keep the centre area calm and low-contrast with no
> focal objects. No ground, no aircraft, no text.

**sky_mid.png**
> [STYLE PREAMBLE]
> A vertical high-altitude sky game background. Deep violet-navy (#16123A) at the
> top fading to a cooler blue-violet at the bottom, with a thin band of distant
> magenta glow near the lower edge and scattered stars becoming denser toward the
> top. Calm, low-contrast centre. No ground, no aircraft, no text.

**sky_high.png**
> [STYLE PREAMBLE]
> A vertical outer-space game background. Near-black indigo (#0B0A1F) with a rich
> field of stars and two soft aurora ribbons in mint-cyan (#3BE8B0) and violet
> (#7B2FF7) drifting horizontally across the upper third. Deep, luxurious, calm
> in the centre. No planets, no aircraft, no text.

---

### `clouds.png`
Wide 1536×1024, **transparent background**.

> [STYLE PREAMBLE]
> Four separate soft stylised cloud formations arranged in a horizontal row with
> clear empty space between them, each cloud a different shape and size. Soft
> volumetric puffy shapes in dark violet-grey with magenta rim-light on top and
> cyan bounce light underneath. Semi-translucent, wispy edges. Transparent
> background between and around the clouds, no text.

I will slice the four clouds apart in code.

---

### `explosion.png` — sprite sheet
Square 1024×1024, **transparent background**.

> [STYLE PREAMBLE]
> A 4x4 grid sprite sheet of an explosion animation, 16 equal square frames read
> left-to-right, top-to-bottom. The explosion starts as a small white-hot core,
> expands into a gold and magenta fireball (#FFB020, #FF3D7F), then dissipates
> into violet smoke wisps and fades out by the final frame. Each frame perfectly
> centred in its own cell with even margins, transparent background, no grid
> lines, no borders, no text.

---

### `coin.png`
Square 512×512, **transparent background**.

> [STYLE PREAMBLE]
> A single glossy gold coin (#FFC634) seen face-on, with a bright specular
> highlight on the upper-left, a warm darker gold rim, and a subtle cyan rim-light
> on the lower-right edge. Smooth and premium looking. Centred, transparent
> background, completely blank face with no symbol, no letters, no numbers.

---

### `rain_cloud.png`
Square 512×512, **transparent background**.

> [STYLE PREAMBLE]
> A stylised glowing cloud with gold coins falling from it like rain. The cloud is
> soft violet with cyan rim-light and a gentle inner glow; three or four gold
> coins (#FFC634) fall beneath it with faint motion trails. Playful, celebratory,
> premium. Centred, transparent background, no text.

---

### `runway.png`
Wide 1536×512, **transparent background**.

> [STYLE PREAMBLE]
> A stylised airport runway strip seen from a low side angle, stretching
> horizontally across the frame and receding slightly to the right. Dark violet
> tarmac with a dashed centreline, glowing gold edge lights (#FFC634) along both
> sides, and soft cyan ground haze drifting across the surface. The top half of
> the image is fully transparent. No aircraft, no buildings, no text.

---

### `tile_crash.png` — games-list tile art
Wide 1024×768, opaque.

> [STYLE PREAMBLE]
> A dramatic game thumbnail: a crimson-magenta propeller aeroplane climbing steeply
> from the lower-left toward the upper-right, leaving a glowing gold-to-magenta
> vapour trail behind it. Deep indigo-violet night sky background (#0B0A1F to
> #16123A) with stars and a warm magenta glow at the horizon. Cinematic, premium,
> high contrast. Leave the lower-left third relatively empty and uncluttered for a
> title overlay. No text, no letters, no logos.

---

## 3. Icons (optional, lower priority)

Each square 256×256, **transparent background**, generate as one set for
consistency:

> [STYLE PREAMBLE]
> A set of four matching mobile game UI icons arranged in a row on a transparent
> background, all in the same style: (1) a hamburger menu of three rounded
> horizontal bars, (2) a shield with a checkmark, (3) a rounded speech bubble,
> (4) a bar-chart of three ascending bars. All in soft white with a subtle cyan
> glow (#22E6D3), simple, clean, evenly sized and evenly spaced. No text.

---

## 4. Delivery

Put every PNG in `app/assets/images/crash/`. The folder is already covered by
the `assets/images/` entry in pubspec.yaml, so no pubspec change is needed.

Tell me once the files are in and I will:
- swap the palette across the whole screen to the values in section 0,
- replace the polygon plane, procedural clouds, circle explosion and gradient sky
  with these assets,
- slice the cloud strip and the explosion sheet in code,
- keep the bloom, camera, trail and parallax working on top of the new art.

If any asset comes back with text baked in, or in a mismatched style, regenerate
it — mixing styles will look worse than the current placeholder art.
