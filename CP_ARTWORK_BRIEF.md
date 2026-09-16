# CP / علاقة الارتباط — artwork brief (v2, the couple card)

The card is built from **10 layered PNGs**. The app draws everything else —
names, IDs, ♂/♀, the ribbon text, the level and the day count — so **no text,
no faces and no numbers in any asset** except the "CP" letters on the emblem.

Drop the files in `app/assets/images/cp/` with the exact filenames below. Each
one is wired already: the card renders today with painted stand-ins, and every
file that lands simply replaces its stand-in. Send them in any order.

**Order of impact:** ring frames (3, 4) → emblem (2) → background (1) →
plates (5, 6, 7) → link heart (8) → podium (9) → ribbon (10).

---

## The style block — paste this at the START of every prompt

> Ornate mobile-game UI asset, luxurious fantasy style. Polished gold filigree
> metal with fine engraved scrollwork, faceted gemstones, strong neon glow,
> soft bloom, clean sharp edges. Colours: gold `#E3B84A` / pale gold `#FFE082`,
> hot pink `#FF3FA4`, magenta `#E91E63`, electric blue `#3D8BFF`, violet
> `#7B1FA2`. Lighting from the top-left, consistent across the set. Front view,
> perfectly symmetrical. Isolated on a fully transparent background, no drop
> shadow, no backdrop, no text, no watermark, ~4% empty margin inside the
> canvas so the glow is not clipped.

Rules for every file:

- **PNG with a real alpha channel.** Never a white or black backing — it shows
  as a box on the card. (For the one background asset, opaque is correct.)
- **Same lighting and same gold** in every file or the set looks like stickers
  from five different games.
- **No baked drop shadow** — the app adds it and a baked one doubles up.
- Export at the sizes given, then run through a PNG optimiser (TinyPNG /
  `oxipng`). Whole set should land **under 1.5 MB**, not 15.

---

## 1. `cp_scene_bg.png` — the night scene (opaque)

**1024 × 1024, opaque.** The only asset with no transparency.

> Fantasy background for a mobile-game card: a dreamy night sky in deep violet
> and magenta with soft stars and bokeh, a glowing ornate palace with pink and
> gold lanterns blurred in the far distance, drifting rose petals, a mirror-
> calm reflective floor in the lower third fading to dark purple. Very soft,
> low contrast, no sharp objects in the centre, no characters, no text.
> Cinematic bloom, the whole image slightly dark so bright elements can sit on
> top of it.

Keep it **dark and quiet in the middle**: the rings, plates and text are
printed over it and must stay readable.

---

## 2. `cp_emblem.png` — the winged CP heart with the crown

**768 × 512, transparent.** The top of the card.

> *(style block)* A heraldic emblem: a large glossy magenta-to-hot-pink
> gemstone heart at the centre, wrapped in gold scrollwork, with the letters
> **"CP"** in bold white diamond-encrusted 3D lettering across the heart's face.
> An ornate gold crown with a purple gem rests on top of the heart. A pair of
> feathered golden wings spread symmetrically to the far left and right edges
> of the canvas, glowing warm pink at the tips. Two tiny pink heart gems float
> beside the wings.

This is the **only** asset allowed to carry text, and only the two letters
"CP". Wings must reach the canvas edges so it reads wide.

---

## 3. `cp_ring_blue.png` — the male ring frame

**640 × 640, transparent.** The most important asset: it holds the photo.

> *(style block)* A round jewelled picture frame. A thick circular gold ring
> with engraved filigree, glowing **electric blue** neon light around its
> outer edge. A small ornate gold crown with a blue sapphire sits on top of the
> ring. A pair of translucent glowing **blue crystal wings** spread out
> symmetrically to the left and right of the ring. A faceted **blue sapphire
> heart** in a gold setting sits at the bottom of the ring, overlapping it.
> **The inside of the ring is completely empty and fully transparent — it is
> a window for a photograph.**

**Delivered 16/09/2026.** Measured window: centre (0.498, 0.533), diameter
0.44 of the canvas — wired as `CpArt.ringPhotoCenter(CpSide.blue)`. If the
ring is ever redrawn, re-measure and update those two numbers.

---

## 4. `cp_ring_pink.png` — the female ring frame

**640 × 640, transparent.** Identical composition to #3 — same ring, same
crown position, same wing spread, same window — with the colours swapped:

> … glowing **hot-pink** neon light around its outer edge … crown with a
> **pink gem** … translucent glowing **pink crystal wings** … a faceted **pink
> gemstone heart** in a gold setting at the bottom …

**Delivered 16/09/2026.** Its window differs from the blue ring's — centre
(0.496, 0.487), diameter 0.50 — so the geometry is per side in `CpArt`.

---

## 5. `cp_plate_blue.png` — the male name plate

**512 × 112, transparent.**

> *(style block)* A horizontal name-plate for a mobile-game UI: a rounded
> capsule with a thin polished gold border and small gold flourishes at both
> ends, filled with a glossy **electric-blue to violet** gradient enamel. The
> centre of the plate is flat and clear so a name can be printed over it.

The app prints **♂ + name** over the centre. Keep the flourishes to the outer
12% of each end; the middle 70% must be plain.

---

## 6. `cp_plate_pink.png` — the female name plate

**512 × 112, transparent.** Same shape as #5, filled with a glossy
**hot-pink to magenta** gradient enamel. The app prints **♀ + name** over it.

---

## 7. `cp_id_plate.png` — the ID plate

**384 × 100, transparent.**

> *(style block)* A small horizontal plaque: a rounded rectangle with a thin
> polished gold border and tiny gold corner accents, filled with a very dark
> navy-purple `#1A0B2E` glossy enamel. The centre is flat and clear so a short
> label can be printed over it.

The app prints **ID: 123456** in pale gold over the centre. (The delivered
file had the sample text baked in; it was painted out in place.)

---

## 8. `cp_link_heart.png` — the heart that joins the pair

**1024 × 288, transparent.** Sits **behind** both rings at photo height.

> *(style block)* A glowing faceted pink gemstone heart in a gold setting at
> the exact centre, with two thin ribbons of neon light streaming out
> horizontally to the far left and far right edges of the canvas — the left
> ribbon **electric blue**, the right ribbon **hot pink** — each ribbon curling
> into a soft loop with a few floating sparkles and tiny hearts along it. The
> ribbons fade out completely at the canvas edges.

The heart must be centred **exactly** at x = 512. The outer ~20% of each side
is hidden behind the rings, so nothing important out there.

---

## 9. `cp_podium.png` — the heart podium at the foot of the card

**1024 × 512, transparent.** Profile page only (the room sheet is too short).

> *(style block)* A circular glowing stage seen from a low three-quarter
> angle: three stacked flat discs of dark purple glass with gold rims and
> concentric rings of pink and magenta neon light, a mirror-like reflection
> beneath. A large faceted pink gemstone heart in a gold setting floats just
> above the top disc with a ring of light around it, glowing brightly. Small
> pink hearts and sparkles drift up. The very bottom fades out to transparent.

Width fills the canvas; heart centred at x = 512.

---

## 10. `cp_ribbon.png` — the banner under the emblem

**512 × 128, transparent.**

> *(style block)* An ornate curved ribbon banner with forked, folded ends,
> glossy **magenta** satin with a thin gold trim along both edges. The centre
> face is flat and clear so a short title can be printed over it. No text.

The app prints **علاقة الارتباط** over it. The middle 65% must be plain.

---

## Testing a delivery

Drop the file in, `flutter run`, open any profile that has a CP. The card
shows the file instantly in place of its painted stand-in. If a ring's photo
is off-centre, send me the window's centre + diameter and I adjust
`CpArt.ringPhotoCenter` / `CpArt.ringPhotoDiameter`.

**Don't reuse another operator's artwork.** These prompts describe the same
*kind* of object as the reference without copying its specific design.
