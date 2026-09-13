# CP / العلاقة — artwork brief

Five assets. Everything else on the card (names, level text, day count, the
partners' photos) is drawn by the app, so **no text, no faces and no numbers in
the artwork**.

All files: **PNG with a real alpha channel**, transparent outside the artwork.
Never a white or black backing — it will show as a box on the profile.

Drop them in `app/assets/images/cp/` with the exact filenames below and tell me;
wiring each one is a few lines.

---

## Rules that apply to every asset

- **Style:** ornate mobile-game UI. Polished gold metal, gemstones, soft inner
  glow, subtle bevels. Rich but readable at small size.
- **Palette:** gold `#E3B84A` / `#FFE082` for metal, rose `#E91E63` and deep
  red `#8E0000` for hearts, violet `#4A148C` for shadow.
- **Lighting:** from the top-left, consistent across all five, or they will look
  like a set of stickers from different games.
- **Margin:** leave ~4% empty padding inside the canvas so the glow isn't
  clipped.
- **No drop shadow baked in** — the app adds it, and a baked one doubles up.

---

## 1. `cp_heart_frame.png` — the avatar frame

**512 × 512.** The single most important asset: it appears beside the photo and
twice on the card.

> An ornate heart-shaped picture frame for a mobile app, front view, perfectly
> symmetrical. Polished gold filigree border with small rose-pink gemstones set
> along the top curves and a single larger ruby at the bottom point. The inside
> of the heart is completely empty and transparent — it is a window for a
> photograph. Soft warm rim-light from the top left, gentle inner bevel on the
> gold. Clean vector-like edges, no text, no face, no background.

**Critical:** the heart's interior must be **fully transparent**, not filled
with colour. The app clips the user's photo into it. The gold border should
occupy roughly the outer 10–12% of the shape.

---

## 2. `cp_emblem.png` — the centrepiece between the two avatars

**512 × 384** (wider than tall).

> A heraldic emblem for a mobile app: a deep red heart at the centre, wrapped in
> polished gold scrollwork, with a small ornate gold crown resting on top and a
> pair of stylised feathered wings spreading symmetrically to the left and
> right. Jewel accents in rose pink. Front view, perfectly symmetrical, warm
> top-left lighting. Transparent background, no text, no characters.

Sits between the partners on the العلاقة card. Wings should reach the left and
right edges of the canvas so it reads as wide.

---

## 3. `cp_card_frame.png` — the العلاقة card border

**1024 × 640.** This is a **nine-slice** frame, which constrains the design:

> An ornate rectangular frame for a mobile game panel. Gold filigree border with
> corner flourishes — small roses and scroll leaves at each of the four corners.
> The four straight edges between the corners are a simple repeating gold
> moulding with no unique detail. The entire centre is empty and transparent.
> Warm top-left lighting, rich but not cluttered. No text, no background fill.

**Critical for nine-slicing:** all the character must live in the **corners**.
The straight runs get stretched to fit the card, so anything distinctive along
an edge (a crest, a gem, a bow) will smear. Keep the border ≤ 90px thick on a
1024-wide canvas.

---

## 4. `cp_pill.png` — the "CP" badge plate

**256 × 96.**

> A small ornate horizontal plaque for a mobile game UI. Rounded capsule shape
> in polished gold with a rose-pink enamel centre panel, a tiny heart motif at
> each end. The centre panel is flat and clear so a short label can be printed
> over it. Front view, symmetrical, transparent background, no text.

The app prints **CP** over the centre, so leave that panel plain.

---

## 5. `cp_tier_glow.png` — optional tier backdrop

**1024 × 640.** Only if you want the higher tiers to look different from the
first; skip it and the card uses a painted gradient.

> A soft abstract glow for a mobile game card background: warm radiating light
> from the centre, faint sparkles and drifting embers, edges fading completely
> to transparent. No objects, no text, no hard edges.

Kept low-contrast — names and numbers are printed over it.

---

## If you'd rather send fewer

Order of impact: **1 → 3 → 2 → 4 → 5.**

Asset 1 alone changes how the feature looks more than the other four combined,
because it appears three times on the page. Send that one first and I'll wire it
while you work on the rest.

---

## Two notes

**Don't reuse the reference video's artwork.** That's another operator's asset
and it carries real legal risk. These prompts deliberately describe the same
*kind* of object without copying their specific design.

**Size matters for this app.** The bundle is already 61 MB of artwork, which is
the open half of the G1 performance item. Export each of these at the sizes
above and run them through a PNG optimiser — five assets should land under
400 KB total, not 4 MB.
