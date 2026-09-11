# بوابات أوليمبوس — the remaining 15 assets

16 of 31 delivered. Everything below is what is left. Generate in any order, save
to Downloads, send them over — each one drops straight in.

**Every prompt already carries the three rules we learned the hard way:**

1. **Style-lock** — "stylised semi-flat 3D game-icon style, NOT photorealistic".
   Photoreal art beside the delivered gems reads as two different games.
2. **No shadows** — "no cast shadow, no drop shadow". A baked-in shadow becomes a
   grey smudge when the background is cut out.
3. **No baked text** — the app draws every word and number itself.

Backgrounds and effects are the exception to rule 2: they are not cut out.

---

## Group A — scene (2)

### 1. `bg_olympus_bonus` — storm backdrop for free spins

```text
A wide landscape 3D background for a Greek mythology mobile game: a grand white
marble temple above luminous clouds, tall fluted columns with ornate gold
capitals, flaming golden braziers atop the nearest columns, and a polished
reflective floor across the foreground. A violent storm: deep indigo and violet
sky, heavy dark storm clouds, several forks of electric-blue lightning striking
behind the temple, the braziers burning bright against the dark, rain-slicked
marble, and a faint green-teal aurora above the columns. The centre of the frame
is calm, open and uncluttered with no architecture in it; the right side is more
open, the left side quiet. Stylised semi-flat 3D game-art style, NOT
photorealistic. Slightly soft focus, low contrast, nothing sharp or busy. Premium
mobile-game key art. No text, no logos, no watermark, no characters, no people.
```

> Same camera and composition as the daytime one you already sent — it swaps in
> when free spins start, so a matching layout makes the change read as weather
> rather than a different place.

**16:9, highest resolution.** → `one bg.png --name bg_olympus_bonus`

### 2. `zeus_pedestal` — the column Zeus stands on

```text
An ornate white marble column capital seen from slightly below: a wide fluted
Greek pedestal with gold trim and carved acanthus detailing around its top edge,
luminous white clouds curling around its base, warm golden light from above.
Stylised semi-flat 3D game-icon style, NOT photorealistic, clean surfaces, vivid
saturated colour, thin bright rim light. Plain flat mid-grey background. No cast
shadow, no drop shadow. No text, no watermark.
```

**16:9 or square.** → `one ped.png --name zeus_pedestal --tolerance 90`

---

## Group B — board frame and UI (4)

### 3. `frame_grid` — ornate frame drawn over the board

```text
An ornate rectangular game-board frame in polished gold, slightly wider than it is
tall, with a Greek meander key pattern running along the top and bottom rails,
twisted rope moulding along the left and right sides, and a decorative rosette at
each of the four corners. The entire centre is completely empty - only the border
is drawn, nothing crosses the middle. Stylised semi-flat 3D game-icon style, NOT
photorealistic, warm gold with deep shadow contact and bright specular highlights.
Plain flat mid-grey background. No cast shadow, no drop shadow. No text, no
watermark.
```

> The empty centre is not optional — the board shows through it.

**4:3 (it is 1200×1000).** → `one frame.png --name frame_grid --tolerance 90`

### 4. `fx_tumble_banner` — plaque behind the win readout

```text
An ornate wide horizontal plaque: a deep polished dark-wood centre panel framed in
scrolled gold metal, with a small decorative rosette at each end, viewed straight
on. The centre panel is flat, dark and completely uncluttered so text can sit on
it. Stylised semi-flat 3D game-icon style, NOT photorealistic, warm gold with
bright specular highlights. Plain flat mid-grey background. No cast shadow, no
drop shadow. No text, no watermark.
```

**4:1 wide.** → `one banner.png --name fx_tumble_banner --tolerance 90`

### 5. `ornament_owl` — left-side ornament

```text
A tall ornate golden owl statue with spread wings and glowing blue jewelled eyes,
perched on a small fluted marble column, Greek-inspired detailing, facing forward,
designed to stand along the left edge of a game screen. Stylised semi-flat 3D
game-icon style, NOT photorealistic, polished gold with warm ambient light, thin
bright rim light. Plain flat mid-grey background. No cast shadow, no drop shadow.
No text, no watermark.
```

**Portrait, roughly 2:4.** → `one owl.png --name ornament_owl --tolerance 90`

### 6. `logo` — your own logo plate, empty

```text
An ornate game logo emblem: a wide gold-framed shield-shaped cartouche with
scrolled edges and a deep royal-purple centre panel, a small golden lightning bolt
crossed with a laurel sprig set at the top centre, warm gold bevels, bright
specular highlights and a soft outer glow. The purple centre panel is left
completely empty - no letters, no words, no numbers anywhere in the image.
Stylised semi-flat 3D game-icon style, NOT photorealistic. Plain flat mid-grey
background. No cast shadow, no drop shadow. No text of any kind, no watermark.
```

> **The empty panel is deliberate.** The app draws the name over it, so it
> renders in Arabic and English, stays crisp, and can be renamed in two lines.
> This is also the reason there is no prompt here for the commercial game's
> logo — that lockup is Pragmatic Play's trademark and artwork.

**2:1 wide.** → `one logo.png --name logo --tolerance 90`

---

## Group C — effects (5)

All five are **light on pure black**, not transparent. They composite additively,
so black reads as invisible. Never ask for a transparent background on these.

### 7. `fx_lightning_bolt`

```text
A single jagged forked lightning bolt travelling from top to bottom, a blazing
white-hot core wrapped in an electric-blue glow, with small branching arcs along
its length, on a pure black background. Glowing additive light effect, vivid and
high energy. No text, no watermark.
```
**1:1.** → `one bolt.png --name fx_lightning_bolt`

### 8. `fx_explosion`

```text
A bright golden-white burst of light and sparks radiating outward from the centre,
with shattered gem fragments and glowing embers flying outward in all directions,
on a pure black background. Glowing additive light effect. No text, no watermark.
```
**1:1.** → `one boom.png --name fx_explosion`

### 9. `fx_particle_spark`

```text
A single small four-point star spark, brilliant white at the centre fading through
pale gold to black at the edges, with a soft round bloom around it, centred on a
pure black background. Glowing additive light effect. No text, no watermark.
```
**1:1.** → `one spark.png --name fx_particle_spark`

### 10. `fx_coin`

```text
A single polished gold coin tilted at a slight three-quarter angle, thick milled
edge, warm specular highlights and a bright glowing rim, centred on a pure black
background. Blank faces - no embossed design. Glowing additive light effect. No
text, no numbers, no watermark.
```
**1:1.** → `one coin.png --name fx_coin`

### 11. `fx_burst_green`

```text
A wide emerald-green radial light burst: a brilliant white-green core with long
soft god-rays radiating outward in all directions, fading smoothly to pure black
at the edges, on a pure black background. Glowing additive light effect, cinematic
and dramatic. No text, no watermark.
```
**1:1, highest resolution** (this one fills the screen). → `one burst.png --name fx_burst_green`

### 12. `fx_trumpet`

```text
An ornate golden ceremonial horn pointing to the right: a long tapering body with
a wide flared bell, fine engraved detailing along its length, warm metallic
highlights and a bright glowing rim, on a pure black background. No banner, no
ribbon hanging from it. Glowing additive light effect. No text, no watermark.
```
**2:1 wide.** → `one horn.png --name fx_trumpet`

---

## Group D — clouds (2)

### 13 & 14. `cloud_far` and `cloud_near`

**These are the hard ones.** They must tile seamlessly left-to-right, and image
models are bad at that. Two honest options:

- **Skip them.** They are a parallax nicety. Nothing breaks; the code draws
  nothing when they are missing.
- **Buy a seamless cloud strip** from a texture library instead of generating it.

If you want to try anyway:

```text
A wide horizontal band of soft wispy high-altitude clouds, pale pink and cream,
thin and translucent, fading to fully transparent at the top and bottom edges of
the frame. The left and right edges match each other exactly so the band repeats
seamlessly. Stylised semi-flat 3D game-art style, NOT photorealistic. Plain flat
mid-grey background. No text, no watermark.
```
**4:1 wide.** → `one cloudfar.png --name cloud_far --tolerance 90`

For `cloud_near`, same prompt but: *thick billowing cumulus clouds, warm peach and
gold lit from above, more opaque and higher contrast*.
→ `one cloudnear.png --name cloud_near --tolerance 90`

---

## Group E — hub card (1)

### 15. `card_olympus` — the tile in the games list

```text
A wide 2:1 banner for a Greek thunder-god mobile game: Zeus standing on the right
above luminous clouds raising a golden thunderbolt, a grand marble temple with
gold columns and flaming braziers behind him, a warm peach and gold sunset sky,
and coloured gems and gold coins scattered through the lower composition. The left
third of the frame is calm and relatively empty. Stylised semi-flat 3D game-art
style, NOT photorealistic. Premium mobile-game key art. No text, no logo, no
watermark.
```

**2:1.** → `one card.png --name card_olympus`

> After this lands, edit the بوابات أوليمبوس entry in
> `app/lib/screens/games_hub_screen.dart`: remove `drawTitle: true` and add
> `art: 'assets/images/cards/card_olympus.png'`.

---

## Running them

```bash
python tools/olympus_art_prep.py one <file> --name <asset>   # process one
python tools/olympus_art_prep.py check                        # audit all 31
```

`--tolerance` only matters for cut-out assets (Groups A2, B, D). Effects and
backgrounds ignore it. If a cut-out keeps a grey halo, raise it; if it starts
eating the artwork's own edges, lower it.

## Priority

1. **`frame_grid`** — the painted board frame is now the weakest thing on screen.
2. **`bg_olympus_bonus`** — free spins currently reuse the daytime sky.
3. **`fx_burst_green` + `fx_coin` + `fx_trumpet`** — the BIG WIN celebration.
4. `fx_lightning_bolt`, `fx_explosion`, `fx_particle_spark` — Zeus's strike.
5. `logo`, `ornament_owl`, `fx_tumble_banner`, `zeus_pedestal`, `card_olympus`.
6. Clouds last, or never.
