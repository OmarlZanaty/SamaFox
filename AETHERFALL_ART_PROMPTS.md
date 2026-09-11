# Aetherfall — copy-paste art prompts

Paste the **Global rules** block once at the start of your image session, then
one numbered prompt at a time. Save each result under the exact `Path` given —
symbols and the hub tile then appear with no code change.

**Do not** feed the model a screenshot of any existing slot game, or name *Gates
of Olympus*, Pragmatic Play, or Zeus. These prompts are already original; keep
them that way.

---

## Global rules (paste once, at the top)

```
For every image in this session:
- Transparent background (PNG-32) unless I say "opaque".
- No text, no numbers, no watermarks, no logos anywhere in the image.
- The art sits on a deep indigo to near-black background (#0F1638 to #07030F),
  so give every silhouette a soft light rim; avoid dark outlines that vanish.
- Palette: deep indigo, petrol blue, cyan, ember orange, pale mint, brushed
  copper. Gold only as a restrained accent, never dominant.
- Consistent three-quarter camera angle, consistent lighting direction, premium
  glass-and-metal material language, clean alpha edges.
- Centre the subject with about 8% padding so glows are not clipped.
- No Greek temples, columns, marble, thunderbolts, lightning gods, or casino
  branding.
```

---

## Priority 1 — symbols (seen every spin)

All 11 go in `app/assets/images/aetherfall/` at **300×300 px, transparent**.

**1. `symbol_l1.png`**
```
An original small glowing cyan glass prism marked with a simple three-line rune
etched into its face, clean triangular faceted glass, soft internal refraction,
gentle cyan-white bloom.
```

**2. `symbol_l2.png`**
```
An original small six-point crystal shard glowing warm ember-orange, dark etched
glyph on its surface, faceted glass material, soft orange bloom.
```

**3. `symbol_l3.png`**
```
An original small organic spiral seed pod glowing pale mint-green, luminous
spiral ridges, soft green aura, faintly translucent shell.
```

**4. `symbol_l4.png`**
```
An original small deep blue-black orbit stone with one thin rotating cyan ring
around its equator, polished mineral surface, subtle starlight glints.
```

**5. `symbol_h1.png`**
```
An original small brushed-copper astrolabe instrument with fine engraved arcs
and a tiny rotating needle, no Greek motifs, warm metallic highlights, faint
cyan glow from its centre gem.
```

**6. `symbol_h2.png`**
```
An original small heart-shaped meteor capsule: a glowing orange-red molten core
sealed inside faceted translucent containment glass, warm inner light, cool
glass rim.
```

**7. `symbol_h3.png`**
```
An original small four-colour aurora compass disc with cyan, mint, ember and
violet segments and a thin glowing needle, brushed copper bezel, soft
aurora-light bloom.
```

**8. `symbol_h4.png`**
```
An original small floating angular crystal crown made of pale icy-cyan crystal
shards with fine copper trim at the base. Not a royal or Greek crown — more like
a floating ice-crystal formation. Restrained warm gold only as a thin accent
line.
```

**9. `symbol_wild.png`**
```
An original rotating translucent hexagonal glass prism with a bright white
glowing core and faint rainbow internal refraction at its edges, premium glass
material.
```

**10. `symbol_key.png`**
```
An original hexagonal brass and copper key with a glowing cyan core set into its
head, fine mechanical engraving on the shaft, warm metal rim light.
```

**11. `symbol_charge.png`**
```
An original small glowing meteor capsule in warm ember-orange — simpler,
rounder and more compact than the heart-shaped one — with a clean flat-ish front
face. Keep that front area readable and uncluttered; a number will be overlaid
on it later. No text or numbers in the image.
```

---

## Priority 2 — hub tile (the games list)

**12. `app/assets/images/cards/card_aetherfall.png` — 1440×720 px, opaque**
```
Key art for an original fantasy arcade game: a circular celestial compass
interface with a 6x5 grid of glowing translucent falling-symbol chambers at its
centre, seen at a slight angle. Behind it, floating dark basalt islands, a deep
indigo sky, cyan aurora ribbons, and scattered meteor fragments with light
trails. A small original silver-blue-haired winged guardian figure is visible in
silhouette in the upper corner, not the focal point. Palette: indigo, petrol
blue, cyan, ember orange, brushed copper, restrained gold accent only. Premium,
cinematic, dramatic lighting, like a modern arcade-game banner. Keep the bottom
third darker and simpler — a title is overlaid there. No text, no logos, no
Greek architecture, no lightning-god imagery.
```

---

## Priority 3 — Ilyra, the hero

Generate **13 first** and feed it back as a style reference for 14–16 so the
face stays consistent.

**13. `app/assets/images/aetherfall/hero_sheet.png` — 1600×1000 px**
```
An original character reference sheet for Ilyra, Warden of the Skyfire, a
fictional celestial guardian for a fantasy arcade game. Show front,
three-quarter and side views. Short silver-blue hair, angular face, teal eyes,
asymmetric bronze-and-charcoal armour, a translucent meteor-glass shoulder cape,
a crescent-shaped staff, small constellation tattoos, practical boots, athletic
non-exaggerated proportions. Pose variations: neutral, curious, focused,
celebrating, casting a skyfire ribbon. Distinct silhouette — no beard, no toga,
no thunderbolt, no Greek deity styling. Clean studio background, consistent
lighting, production concept-art quality, no text.
```

**14–16.** Each **400×400 px, transparent**, face centred with shoulders cropped
so it reads inside a circular frame.

- `hero_portrait_idle.png`
```
A close, chest-up original portrait of Ilyra, Warden of the Skyfire, inside a
small circular observatory-window framing. Calm, confident half-smile, looking
slightly off-camera. Soft rim light, painterly-but-clean fantasy game-art style,
transparent background, no text.
```
- `hero_portrait_win.png`
```
Same character and framing. Bright delighted expression, one hand raised, a
small skyfire spark near her fingers.
```
- `hero_portrait_bonus.png`
```
Same character and framing. Focused and intense, staff raised, faint cyan-ember
glow reflecting on her face.
```

---

## Priority 4 — backgrounds

Both **1440×2560 px portrait, opaque**, in `app/assets/images/aetherfall/`.

**17. `bg_observatory.png`**
```
An original fantasy arcade game background: floating dark basalt islands above a
cloud ocean, deep indigo sky, cyan aurora ribbons, distant meteor fragments with
light trails, faint observatory structures on the horizon. Large calm empty
centre — the middle 65% must stay visually quiet so a game board and UI can sit
on top. Cinematic, high detail, no text, no characters, no Greek temples.
```

**18. `bg_bonus_vault.png`**
```
An original bonus-round environment: a floating observatory chamber above a dark
cloud ocean, a circular aperture in the architecture, aurora ribbons, ember
particles drifting upward, suspended copper instruments, thin glowing cyan
constellation lines connecting distant points, a ringed planet far in the
background. Leave the centre readable for a game board and the lower area clean
for counters. Cinematic but functional, high contrast, no Greek architecture, no
marble, no text.
```

---

## Priority 5 — effects and UI chrome (optional polish)

**19–23.** Particle textures, **512×512 px, transparent**, in
`app/assets/images/aetherfall/`.

- `fx_particle_spark.png` — `A small soft cyan-white radial light spark, clean edges, additive-blend friendly on black.`
- `fx_particle_ember.png` — `A small glowing ember-orange meteor fragment with a short light trail.`
- `fx_ribbon_compass.png` — `A thin glowing compass-line ribbon trail, cyan fading to transparent at both ends, gentle curve.`
- `fx_constellation_thread.png` — `A thin glowing mint-cyan constellation line with a small star-point node at each end.`
- `fx_key_unlock.png` — `A radial burst of cyan-white light: bright core fading outward, a few small copper sparks.`

**24–25.** Buttons, **720×220 px, transparent, rounded-pill shape**.

- `btn_ignite.png`
```
A polished pill-shaped fantasy-arcade action button in glowing cyan-white with a
bright top highlight, soft cyan glow beneath, thin brushed-copper inner border.
Empty centre — no text or icon. Front-on view.
```
- `btn_auto.png`
```
A polished pill-shaped button in brushed copper with a warm glossy highlight,
soft copper glow beneath, thin cyan inner border. Empty centre — no text or
icon. Front-on view.
```

**26. `meter_frame.png` — 480×160 px, transparent**
```
A slim glassy meter gauge frame for a fantasy arcade HUD, cyan-and-copper trim,
dark translucent glass centre panel. Empty centre — the fill bar and text are
drawn by the app. No text.
```

---

## After you deliver

- **Priorities 1–2 need no code.** Drop the files in the listed paths and they
  appear on the next build.
- **Priorities 3–5 need one short wiring pass** — the app currently paints those
  placeholders itself. Say the word once any are ready.
- Partial deliveries are fine. Send the 11 symbols first; they are on screen
  every spin.
