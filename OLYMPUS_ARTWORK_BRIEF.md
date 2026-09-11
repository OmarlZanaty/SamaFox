# بوابات أوليمبوس — Gates of Olympus: Artwork Prompt Pack

**31 assets.** Every one has an exact filename, size and a copy-pasteable prompt.
Drop the files into the listed folders with the listed names and they wire
themselves in — the code loads each by name and falls back to painted art for
anything missing, so **partial deliveries are safe** and you can upload one file
at a time.

The game is **fully playable right now** with painted placeholders. None of this
blocks anything; all of it makes it look finished.

Two things to run:

```bash
# Audit what you have delivered against what the game loads
python tools/olympus_art_prep.py check

# Eyeball a delivery in the real widgets - no backend or login needed
flutter run -d chrome -t lib/dev/olympus_preview.dart
```

**Read section 0 before generating anything** - it is the difference between a
set that looks like one game and five images that do not match.

---

## Read this first

You sent reference screenshots of the commercial game. Two rules when generating:

1. **Do not upload those screenshots to the image model**, and never ask it to
   "match", "copy" or "recreate" them. Prompt from the text below only. The
   prompts describe Zeus, Olympus, marble, gems and gold — all public-domain
   subject matter that anyone may draw.
2. **There is no prompt here for the `GATES of OLYMPUS™` cartouche logo.** That
   purple-and-gold banner lockup is Pragmatic Play's trademark *and* their
   artwork. Asset 25 below is an original logo for your game instead.

Same reason no prompt says "Pragmatic Play", references a published slot, or
bakes text into an image.

### Baked-in text: never

No text, numbers, watermarks or logos inside any image — with the single
exception of the logo asset. The app draws every label, every multiplier value
and the word SCATTER itself, so they stay crisp, translatable, and yours.

---

## Palette decision — read before generating

Your reference images are **warm**: peach and pink sky, golden floor, gold
temple. The written brief said "purple and royal blue", which is what is built
today. **The prompts below target the warm look**, because that is what the
references show.

If you go warm, retune two constants in
`app/lib/screens/games/olympus_screen.dart`:

```dart
const _violetDeep = Color(0xFF12052B);   // → Color(0xFF3B1B3A)
const _violetTop  = Color(0xFF3A1A72);   // → Color(0xFFB86A5E)
```

Want to stay violet instead? Then replace every "warm peach and gold sky,
sunset tones" phrase below with "deep violet and indigo celestial sky" and
change nothing in code.

### Global rules for every prompt

- **Transparent background (PNG-32)** for every symbol, character and UI piece.
  Backgrounds and the hub card are the only opaque files.
- Effect textures marked *additive* are **light on pure black** — they are
  composited with `BlendMode.plus`, so the black contributes nothing and they
  need no alpha matte.
- Deliver symbols at 3× mobile size, centred, with ~8% padding so glows are not
  clipped.
- Consistent camera angle and lighting per set: the five gems must look like one
  cut set, the four artefacts like one treasury.

---

## 0 — How to actually get a consistent set

**Generating the five gems as five separate images will not work.** You will get
five different lighting rigs, five different golds and five different camera
angles, and the board will look like five games glued together. The same is true
of the four artefacts and the three Zeus poses.

**Generate each set as one contact sheet, then slice it.** One image means one
lighting setup, so the set is internally consistent by construction.

```bash
# Slice a sheet into correctly-named, correctly-sized, transparent files
python tools/olympus_art_prep.py sheet gems_sheet.png      --set gems
python tools/olympus_art_prep.py sheet artefacts_sheet.png --set artefacts
python tools/olympus_art_prep.py sheet specials_sheet.png  --set specials
python tools/olympus_art_prep.py sheet zeus_sheet.png      --set zeus

# Anything generated on its own
python tools/olympus_art_prep.py one bg_raw.png --name bg_olympus

# Audit the folder against what the game loads
python tools/olympus_art_prep.py check
```

The tool cuts the flat background to alpha, trims to the artwork, centres it,
resizes to the exact spec and writes the exact filename. Existing files are
backed up to `.bak`. Add `--dry-run` to see what it would do.

> Ask for the sheet on a **plain flat mid-grey background** — that is what makes
> the automatic cutout clean. A busy or gradient background will need cutting by
> hand, then run the tool with `--no-cut`.
>
> If the model bakes in a drop shadow anyway, raise `--tolerance` until it goes
> (the artefact sheet needed `--tolerance 150`; the default 32 was enough for the
> gems). Check the result before moving on — too high a tolerance starts eating
> the artwork's own edges.

### Sheet prompt A — the five gems (slice with `--set gems`)

> A contact sheet of five glossy 3D cut gemstones for a mobile game, arranged in a single horizontal row, evenly spaced, all at identical scale, identical camera angle and identical studio lighting, on a plain flat mid-grey background. Left to right: a sapphire-blue gem in a tall diamond/kite silhouette; an emerald-green gem in a triangular silhouette; a golden-yellow citrine gem in a hexagonal silhouette; a violet amethyst gem in a pentagonal silhouette; a ruby-red gem in a rounded-square silhouette. Every stone has brilliant faceting, a glowing internal core, crisp facet edges and a thin luminous rim light. Premium casino-game icon art, high detail, consistent across all five. No text, no numbers, no labels, no watermark.

### Sheet prompt B — the four artefacts (slice with `--set artefacts`)

> A contact sheet of four ornate gold Greek treasure objects for a mobile game, arranged in a single horizontal row, evenly spaced, all at identical scale, identical three-quarter camera angle and identical studio lighting, on a plain flat mid-grey background. Left to right: a polished gold ring set with one large faceted blue jewel; a gold goblet with a fluted bowl and coloured faceted gemstones set around the rim; an hourglass with a blue-and-gold frame and glowing pale-blue sand; a gold crown with tall peaks set with deep red faceted rubies. Rendered in a stylised semi-flat 3D game-icon style, NOT photorealistic: clean hard-edged surfaces, vivid saturated colour, a bright luminous inner glow at the centre of every gemstone, a thin bright rim light tracing each silhouette, and strong specular highlights on the gold. No cast shadow and no drop shadow on the background - each object floats free, because these are cut out to transparency and a baked-in shadow becomes a grey smudge on the game board. All four share the same polished metal treatment and the same Greek meander and laurel engraving style. Premium casino-game icon art, high detail, perfectly consistent across all four. No text, no numbers, no labels, no watermark.

> **Style-lock line:** the phrase "stylised semi-flat 3D game-icon style, NOT
> photorealistic ... luminous inner glow ... thin bright rim light" is there to
> match the gem sheet that was already delivered. Keep it in every later prompt —
> a photoreal artefact set beside stylised gems reads as two different games on
> one board.
>
> **Always say "no cast shadow, no drop shadow".** The first artefact sheet was
> generated with one and the shadow had to be cut back out at
> `--tolerance 150`; on a dark board a surviving shadow reads as dirt under the
> symbol. The game draws its own glow behind every tile.

### Sheet prompt C — the two specials (slice with `--set specials`)

> A contact sheet of two premium game icons side by side, at identical scale and identical lighting, on a plain flat mid-grey background. Left: a dramatic close-up portrait of Zeus with a long white beard, gold laurel crown and glowing pale-blue eyes, set inside an ornate circular gold frame with blue electricity arcing around it, the lower fifth of the frame kept simple and uncluttered. Right: a glowing golden orb with a luminous blue gem core, an ornate gold ring frame with small wing-like fins at its sides and blue-white electrical arcs around it, the very centre of the orb smooth and uncluttered. Premium 3D casino-game icons, strong rim light. No text, no numbers, no labels, no watermark.

### Sheet prompt D — the three Zeus poses (slice with `--set zeus`)

> A character sheet of the same Greek god Zeus in three full-body poses, arranged in a single horizontal row, evenly spaced, at identical scale, identical proportions and identical lighting, on a plain flat mid-grey background. The character is a muscular mature man with a long white beard and flowing white hair, a white toga draped over one shoulder, ornate gold armbands and shoulder armour, and a gold laurel crown. Left: standing calmly in three-quarter view, thunderbolt lowered at his side, eyes softly glowing pale blue. Centre: mid-strike, the thunderbolt arm raised high overhead, the bolt blazing white-hot, eyes burning electric blue, hair and beard blown back, electric arcs around his hand. Right: roaring in triumph, both arms spread wide and raised, chin lifted, eyes glowing bright. The same character in all three, consistent face, build and costume. Premium 3D game character art, warm gold rim light. No text, no logo, no watermark.

> The single-asset prompts in sections 1-4 below are still here, for regenerating
> one file when a sheet gives you four good symbols and one bad one. Reach for
> the sheets first.

---

## 1 — Low symbols: the five gems

`app/assets/images/olympus/` · **300×300 px · transparent**

Each is a distinct convex silhouette so the board stays readable by shape alone
— that is also what makes it legible to players who cannot separate the colours.
**Keep the silhouettes exactly as described**; the painted fallbacks use the same
shapes and the paytable depends on them being distinguishable.

**1. `symbol_gem_blue.png`**
> A glossy 3D cut sapphire-blue gemstone in a tall diamond/kite silhouette, brilliant faceting with crisp edges, bright internal refraction, deep blue core fading to pale blue at the tips, thin luminous white-blue rim light. Premium mobile-game icon, centred, isolated on a transparent background, no text, no watermark.

**2. `symbol_gem_green.png`**
> A glossy 3D cut emerald-green gemstone in a triangular silhouette, flat top facet with radiating step cuts, glowing green interior, thin pale-gold rim light. Premium mobile-game icon, centred, isolated on a transparent background, no text, no watermark.

**3. `symbol_gem_yellow.png`**
> A glossy 3D cut golden-yellow citrine gemstone in a hexagonal silhouette, honeycomb faceting, warm amber internal glow, bright white specular highlight on the upper-left face. Premium mobile-game icon, centred, isolated on a transparent background, no text, no watermark.

**4. `symbol_gem_purple.png`**
> A glossy 3D cut violet amethyst gemstone in a pentagonal silhouette, deep purple core with lilac highlights, crisp facet edges, soft violet bloom around the stone. Premium mobile-game icon, centred, isolated on a transparent background, no text, no watermark.

**5. `symbol_gem_red.png`**
> A glossy 3D cut ruby-red gemstone in a rounded-square silhouette, step-cut facets, glowing crimson interior, warm white specular highlight, thin gold rim. Premium mobile-game icon, centred, isolated on a transparent background, no text, no watermark.

---

## 2 — Premium symbols: the four artefacts

`app/assets/images/olympus/` · **300×300 px · transparent**

These read *above* the gems: ornate, metallic, busier silhouettes.

**6. `symbol_ring.png`**
> An ornate polished gold ring set with one large faceted blue jewel flanked by two small red stones, fine Greek meander engraving around the band, three-quarter view, strong metallic highlights, warm rim light. Premium 3D game icon, centred, isolated on a transparent background, no text, no watermark.

**7. `symbol_chalice.png`**
> An ornate gold Greek goblet with a wide fluted bowl and a slender stem, coloured gemstones set around the rim, laurel-leaf engraving on the body, glossy polished metal, three-quarter view, warm highlights. Premium 3D game icon, centred, isolated on a transparent background, no text, no watermark.

**8. `symbol_hourglass.png`**
> An ornate hourglass with a deep blue and gold frame, glowing pale-blue sand caught mid-fall, ornate gold caps with fine engraving, soft inner light glowing through the glass, three-quarter view. Premium 3D game icon, centred, isolated on a transparent background, no text, no watermark.

**9. `symbol_crown.png`**
> An ornate gold Greek crown with tall pointed peaks, set with deep red rubies, a laurel motif around the band, polished metal with strong specular highlights, three-quarter view. Premium 3D game icon, centred, isolated on a transparent background, no text, no watermark.

---

## 3 — Special symbols

`app/assets/images/olympus/` · **300×300 px · transparent**

**10. `symbol_scatter_zeus.png`** — *leave the lower 22% visually calm; the app draws the word SCATTER there*
> A dramatic close-up portrait of Zeus — a mature man with a long flowing white beard and hair, a gold laurel crown, and glowing pale-blue eyes — set inside an ornate circular gold frame, bright blue electricity arcing around the frame, a warm golden glow behind him. Premium 3D casino-game icon, centred composition, strong rim light. The lower fifth of the tile is kept simple and uncluttered. No text of any kind, no logo, no watermark.

**11. `symbol_mult_orb.png`** — *keep the centre clean; the app draws ×25 etc. over it*
> A glowing golden orb with a luminous blue gem core, framed by an ornate gold ring with small wing-like decorative fins at its sides, blue-white electrical arcs crackling around the outside. The very centre of the orb is smooth, bright and uncluttered. Premium 3D game icon, centred, isolated on a transparent background. No numbers, no text, no watermark.

---

## 4 — Zeus

`app/assets/images/olympus/` · **900×1200 px · transparent · portrait**

Zeus stands to the **right** of the board and must never overlap it, so the
silhouette has to read in a tall narrow column.

> **All three poses must share framing, scale and lighting exactly.** The app
> swaps between them on the same rectangle, so any drift in size or position
> reads as a jump.

**12. `zeus.png`** — neutral idle
> A premium 3D game-art Zeus, Greek god of thunder, standing in a powerful three-quarter pose facing slightly left. A muscular mature man with a long white beard and flowing white hair, a white toga draped over one shoulder, ornate gold armbands and shoulder armour, a gold laurel crown, and calm glowing pale-blue eyes. One hand rests at his side; the other holds a golden thunderbolt lowered. Warm gold rim light, soft peach and gold ambient glow. Full body, centred, isolated on a transparent background. No modern clothing, no other characters, no text, no logo, no watermark.

**13. `zeus_strike.png`** — mid-strike
> The same Zeus character in the same framing, scale and lighting, now mid-strike: the thunderbolt arm raised high above his head, the bolt blazing white-hot, his eyes burning bright electric blue, hair and beard blown back by the discharge, and forked electric-blue arcs crackling around his raised hand. Full body, centred, isolated on a transparent background. No text, no logo, no watermark.

**14. `zeus_celebrate.png`** — reacting to a win
> The same Zeus character in the same framing, scale and lighting, now reacting in triumph: both arms spread wide and raised, chin lifted, mouth open in a roar, eyes glowing bright, gold coins and sparks catching the light around him, robe and beard swept by the motion. Full body, centred, isolated on a transparent background. No text, no logo, no watermark.

**15. `zeus_pedestal.png`** — **700×400 px · transparent**
> An ornate white marble column capital seen from slightly below, a wide fluted Greek pedestal with gold trim and carved acanthus detailing at its top edge, luminous clouds curling around its base, warm golden light from above. Isolated on a transparent background, no text, no watermark.

---

## 5 — Backgrounds

`app/assets/images/olympus/` · **1920×1080 px · opaque**

These render at 60% opacity under a gradient, so keep them relatively
low-contrast — they must never compete with the symbols.

**16. `bg_olympus.png`** — *calm centre for the 6×5 grid, open right side for Zeus, quiet left for a UI panel*
> A wide landscape 3D background of Mount Olympus above luminous clouds: a grand white marble temple with tall fluted columns and ornate gold capitals, flaming golden braziers atop the nearest columns, a polished reflective golden floor in the foreground, and a warm peach-and-gold sunset sky with soft pink clouds. Distant lightning on the horizon. The centre of the frame is calm and uncluttered, the right side more open, the left side quiet. Premium modern mobile-game art, warm gold and rose palette, high production value. No text, no logos, no watermark.

**17. `bg_olympus_bonus.png`** — *same composition, storm version*
> The same Mount Olympus temple location in the same style, composition and camera angle, now during a storm: a deep indigo and violet sky, heavy dark storm clouds, several forks of electric-blue lightning striking behind the temple, the golden braziers burning brighter against the dark, rain-slicked marble, and a faint green-teal aurora above the columns. The centre of the frame stays calm and uncluttered and the right side stays open. Premium modern mobile-game art. No text, no logos, no watermark.

**18. `cloud_far.png`** — **2048×512 px · transparent · must tile horizontally**
> A wide horizontal band of soft wispy high-altitude clouds, pale pink and cream, thin and translucent, fading to fully transparent at the top and bottom edges. The left and right edges match seamlessly so the band can repeat. Isolated on a transparent background, no text, no watermark.

**19. `cloud_near.png`** — **2048×512 px · transparent · must tile horizontally**
> A wide horizontal band of thick billowing cumulus clouds, warm peach and gold lit from above, more opaque and higher-contrast than thin high cloud, fading to fully transparent at the top and bottom edges. The left and right edges match seamlessly so the band can repeat. Isolated on a transparent background, no text, no watermark.

---

## 6 — Effects

`app/assets/images/olympus/` · **transparent, or additive light on black where noted**

**20. `fx_win_flame.png`** — **256×256 · additive on black** — *the burning outline on winning symbols in your screenshot*
> A ring of bright golden-orange flames burning around the empty centre of a square frame, licking inward from the edges, hot white at the base of each flame fading to deep orange at the tips, rendered as glowing light on a pure black background. The middle of the image is empty black. Additive light effect, no text, no watermark.

**21. `fx_explosion.png`** — **256×256 · additive on black**
> A bright golden-white burst of light and sparks radiating from the centre, with shattered gem fragments and glowing embers flying outward, on a pure black background. Additive light effect, no text, no watermark.

**22. `fx_lightning_bolt.png`** — **512×512 · additive on black**
> A single jagged forked lightning bolt travelling top to bottom, a blazing white core wrapped in an electric-blue glow, small branching arcs along its length, on a pure black background. Additive light effect, no text, no watermark.

**23. `fx_particle_spark.png`** — **128×128 · additive on black**
> A small four-point star spark, brilliant white at the centre fading through pale gold to transparent, with a soft bloom, on a pure black background. Additive light effect, no text, no watermark.

**24. `fx_coin.png`** — **128×128 · additive on black**
> A single polished gold coin tilted at a slight three-quarter angle, thick milled edge, warm specular highlights and a bright rim, on a pure black background. No embossed design, no text, no numbers, no watermark.

**25. `fx_burst_green.png`** — **1024×1024 · additive on black**
> A wide emerald-green radial light burst with soft god-rays radiating from a brilliant white-green centre, fading smoothly to pure black at the edges, on a black background. Additive light effect, no text, no watermark.

**26. `fx_trumpet.png`** — **512×256 · additive on black**
> An ornate golden ceremonial horn pointing to the right, long tapering body with a wide flared bell, fine engraved detailing, warm metallic highlights against a pure black background. No banner, no ribbon, no text, no watermark.

**27. `fx_tumble_banner.png`** — **768×192 · transparent** — *the plaque behind the tumble-win readout*
> An ornate horizontal plaque with a deep polished wood centre panel framed in scrolled gold metal, small decorative rosettes at each end, warm highlights, viewed straight on. The centre panel is flat, dark and uncluttered so text can sit on it. Isolated on a transparent background, no text, no watermark.

---

## 7 — Frame, ornament and logo

**28. `frame_grid.png`** — **1200×1000 px · transparent** — *drawn over the board; replaces the painted meander*
> An ornate rectangular game-board frame in polished gold, wider than it is tall, with a Greek meander key pattern running along the top and bottom rails, twisted-rope moulding along the sides, and a decorative rosette at each of the four corners. The entire centre is completely empty and transparent — only the border is drawn. Warm gold with deep shadow and bright specular highlights. Isolated on a transparent background, no text, no watermark.

**29. `ornament_owl.png`** — **400×900 px · transparent**
> A tall ornate golden owl statue with spread wings and glowing blue jewelled eyes, perched on a small fluted marble column, Greek-inspired detailing, polished gold with warm ambient light, facing forward. Designed to stand along the left edge of a game screen. Isolated on a transparent background, no text, no watermark.

**30. `logo.png`** — **1024×512 px · transparent** — **your own logo, not theirs**
> An ornate game logo emblem: a wide gold-framed shield-shaped cartouche with scrolled edges and a deep royal-purple centre panel, a small golden lightning bolt crossed with a laurel sprig set at the top centre, warm gold bevels, bright specular highlights and a soft outer glow. **The purple centre panel is left completely empty** — no letters, no words, no numbers anywhere in the image. Premium mobile-game logo emblem, isolated on a transparent background, no watermark.

> **Why empty:** the app draws the game's name over this plate, from
> `OlympusStrings.title` — so it renders in Arabic *and* English, stays crisp at
> any density, and can be renamed in two lines without touching artwork.

---

## 8 — Hub card

**31. `app/assets/images/cards/card_olympus.png`** — **1200×600 px · opaque**
> A wide 2:1 banner for a Greek thunder-god mobile game: Zeus standing on the right above luminous clouds, raising a golden thunderbolt, a grand marble temple with gold columns and flaming braziers behind him, a warm peach-and-gold sunset sky, and coloured gems and gold coins scattered through the lower composition. The left third of the frame is calm and relatively empty. Premium mobile-game key art. No text, no logo, no watermark.

Once delivered, edit the بوابات أوليمبوس entry in
`app/lib/screens/games_hub_screen.dart`: drop `drawTitle: true` and add
`art: 'assets/images/cards/card_olympus.png'`.

---

## Not generated, and why

**Buy Free Spins / Ante Bet ("Double Chance") panels.** Your last screenshot has
both. They are not in this list because **the feature does not exist** — the
server has no bonus-buy endpoint and no ante-bet stake multiplier, so the art
would sit unused. They are also the two features most likely to attract
gambling-regulator attention in a coins-only social app. Say the word and I will
scope the backend work; the art prompts are trivial once the feature is real.

**Anything carrying the commercial game's name or logo lockup.** See the top.

---

## Complete file checklist

```
app/assets/images/olympus/
  symbol_gem_blue.png       300×300    transparent
  symbol_gem_green.png      300×300    transparent
  symbol_gem_yellow.png     300×300    transparent
  symbol_gem_purple.png     300×300    transparent
  symbol_gem_red.png        300×300    transparent
  symbol_ring.png           300×300    transparent
  symbol_chalice.png        300×300    transparent
  symbol_hourglass.png      300×300    transparent
  symbol_crown.png          300×300    transparent
  symbol_scatter_zeus.png   300×300    transparent   calm lower 22%
  symbol_mult_orb.png       300×300    transparent   clean centre
  zeus.png                  900×1200   transparent  ┐
  zeus_strike.png           900×1200   transparent  ├ identical framing
  zeus_celebrate.png        900×1200   transparent  ┘
  zeus_pedestal.png         700×400    transparent
  bg_olympus.png           1920×1080   opaque        calm centre
  bg_olympus_bonus.png     1920×1080   opaque        calm centre
  cloud_far.png            2048×512    transparent   tiles horizontally
  cloud_near.png           2048×512    transparent   tiles horizontally
  fx_win_flame.png          256×256    additive on black
  fx_explosion.png          256×256    additive on black
  fx_lightning_bolt.png     512×512    additive on black
  fx_particle_spark.png     128×128    additive on black
  fx_coin.png               128×128    additive on black
  fx_burst_green.png       1024×1024   additive on black
  fx_trumpet.png            512×256    additive on black
  fx_tumble_banner.png      768×192    transparent
  frame_grid.png           1200×1000   transparent   hollow centre
  ornament_owl.png          400×900    transparent
  logo.png                 1024×512    transparent   empty centre panel

app/assets/images/cards/
  card_olympus.png         1200×600    opaque        calm left third
```

### Priority, if you are generating in batches

1. **Symbols 1–11** — the board is 80% of what the player looks at.
2. **Zeus 12–14** — the character that makes it recognisable.
3. **Backgrounds 16–17** and **frame 28**.
4. Effects 20–27, clouds 18–19, then ornament, logo and card.

---

## Audio — already done

All 18 cues ship. They are **synthesised**, not sourced, by
`app/assets/sounds/generate_olympus_sounds.py` — original, licence-free, and
impossible to confuse with the commercial game's soundtrack. Regenerate with:

```bash
cd app/assets/sounds && python generate_olympus_sounds.py
```

The palette is struck bronze and thunder, drawn from a single minor pentatonic
set so a long cascade layering five or six cues still agrees with itself.
