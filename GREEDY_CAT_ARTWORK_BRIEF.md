# القط الجشع — Artwork Brief

Unlike بلينكو, this game **already ships finished art**: every icon, the mascot
and the whole wooden wheel are drawn in code
(`app/lib/screens/games/greedy_cat_art.dart`). Nothing here is blocking, and
there are no grey placeholders on screen today.

This brief is for **upgrading** that painted art to commissioned illustration.
Deliver whatever you like of it — each file is picked up independently, and any
file that is missing or unreadable falls back to the painted version, so the
game keeps working throughout a partial delivery.

**Global rules for every prompt**
- Transparent background (PNG-32) unless the asset is explicitly a background.
- No text, no numbers, no watermarks, no logos baked into the image — every
  number and label is drawn by the app so it stays crisp and translatable.
  In particular **do not draw the «مضاعفة 5» capsules**; the app draws those.
- Light-UI friendly: these assets sit on a bright cyan background
  (`#3DD7F4` → `#20BCEB`) and inside cream plaques (`#FFF3D2`). Every shape
  needs a thick warm dark-brown outline (`#6D2D1E`, roughly 4.5% of the icon
  width) or it will disappear against the cream.
- One consistent light direction: top-left key light, soft contact shadow
  bottom-right, a single candy glint per solid object.
- Deliver at the stated pixel size (already 3× for mobile). Square assets must
  be perfectly centred with ~6% padding so outlines and glints are not clipped.
- **Originality is a hard requirement.** No existing branded cat, no character
  resembling one from another live-social or jackpot game, no ripped sprites.

**House palette** — do not invent colours outside this set:

| Role | Hex |
| --- | --- |
| Wood outline | `#6D2D1E` |
| Wood midtone | `#A94F28` |
| Wood highlight | `#D98A3C` |
| Cream panel | `#FFF3D2` |
| Warm pale | `#FFE6A4` |
| Gold | `#FFD83D` |
| Orange | `#F58B24` |
| Jackpot red | `#E93D4F` |
| Deep red | `#B51F3D` |
| Success green | `#70E5A5` |
| Mascot lavender | `#C9B6F5` / `#8E74D4` |
| Dark text | `#402019` |

---

## 1. The eight food icons

**Paths:** `app/assets/images/greedy/<key>.png`
**Size:** 300 × 300 px each (transparent)

The filename **must** be the symbol key, because the app looks them up by key:

| File | Food | Multiplier | Category |
| --- | --- | --- | --- |
| `chicken.png` | white hen | 45× | pizza (meat) |
| `fish.png` | blue-and-orange fish | 25× | pizza |
| `goat.png` | brown-and-white goat head | 15× | pizza |
| `shrimp.png` | curled pink-orange shrimp | 10× | pizza |
| `corn.png` | corn cob in a green husk | 5× | salad |
| `tomato.png` | glossy tomato with green crown | 5× | salad |
| `pepper.png` | **long curved red chilli** | 5× | salad |
| `carrot.png` | orange carrot with leaf tops | 5× | salad |

> Create eight separate standalone transparent food illustrations for a kawaii jackpot wheel: a white hen with a red comb, a blue-and-orange fish, a cute brown-and-white goat head with horns, a curled pink-orange shrimp, a yellow corn cob in a split green husk, a glossy red tomato with a green crown, a long curved red chilli with a green stem, and an orange carrot with green leaf tops. Each object centred, fully visible, outlined in warm dark brown, rendered with glossy highlights and simple readable shapes, consistent scale and lighting across all eight, clean 2D vector illustration with subtle dimensional shading. No text, no plate, no background, no watermark.

**Two things that will get an icon sent back:**

1. **`pepper.png` must not be a round bell pepper.** Tomato is already a red
   circle. At the 40 px these render at on a wheel card the two were the same
   picture, and they are separate bets — the painted version was redrawn as a
   long chilli for exactly this reason. Keep the tapering curved silhouette.
2. **Readable at 27 px.** The same file is used for the wheel card (~90 px), the
   results history token (27 px) and the result modal (66 px). Test the
   silhouette small before delivering; fine detail is wasted.

### Alternate theme set (optional, not wired up)
Same style and sizes, for a future re-theme:
`cabbage, apple, pumpkin, mushroom, hotdog, bbq_skewer, lamb_chop, steak,
watermelon, burger, pizza, salad_bowl`. **Do not change a multiplier when
changing artwork** — the weights and payouts are locked together in the service.

---

## 2. Cat mascot

**Path:** `app/assets/images/greedy/cat_<mood>.png`
**Size:** 600 × 600 px (transparent)
**Moods:** `cat_idle.png`, `cat_alert.png`, `cat_win.png`, `cat_lose.png`

> Create a standalone original kawaii jackpot-game cat mascot on a transparent background. The cat is fluffy white with lavender ear interiors and a lavender chest marking, a rounded head, tiny triangular ears, large glossy violet eyes, a small pink nose, soft paws and a compact seated body. Thick warm-brown outlines, soft cream highlights, subtle lavender shadows, polished 2D vector-plus-paint style, front three-quarter view, clear silhouette. No text, no logo, no resemblance to any existing branded cat.

Deliver the four moods as the **same cat in the same pose and scale**, so the app
can cross-fade between them without the character appearing to jump:

- `idle` — relaxed, small smile, eyes open.
- `alert` — eyes wider, leaning forward slightly (used in the last 5 s and the spin).
- `win` — both paws raised, eyes sparkling, mouth open in delight.
- `lose` — gentle disappointment. **Not** sad-crying, not frightened; this fires
  on ordinary losing rounds many times an hour and must never feel punishing.

---

## 3. Wheel chrome

**Path:** `app/assets/images/greedy/wheel_frame.png`
**Size:** 1200 × 1200 px (transparent)

> Create a standalone portrait-game wheel frame: a large central wooden hub with a gold rim and evenly spaced round gold studs, eight thick wooden spokes radiating to the edge with small cream rivets along them, and two wooden support legs descending from behind the hub. Warm orange-brown wood with visible grain, thick dark-brown outlines, subtle dimensional shading. Front-facing and symmetrical. Leave the centre of the hub empty — a cat mascot sits there — and leave the eight spoke ends empty, the food plaques are drawn separately. No text, no watermark.

**Critical:** the spokes must be at 0°, 45°, 90° … measured from 12 o'clock, and
the image must be perfectly square and centred, because the app rotates this
image about its centre during the spin and lays the food cards on the spoke ends
by angle. A frame that is off-centre will visibly wobble.

**Path:** `app/assets/images/greedy/card_plaque.png` — 400 × 400 px
> A single round wooden-framed plaque: dark-brown outer rim, lighter orange inner rim, flat cream face. Empty centre. Front-facing, centred, transparent background.

**Path:** `app/assets/images/greedy/pointer.png` — 200 × 260 px
> A downward-pointing carnival wheel marker: a rounded red teardrop with a thick dark-brown outline and a small cream bead at its top. Tip at the bottom of the frame.

---

## 4. UI furniture

**Path:** `app/assets/images/greedy/coin.png` — 200 × 200 px
> A glossy gold coin seen face-on, with a stylised orange crown emblem embossed in the centre, thick dark-brown outline, bright specular highlight upper-left.

**Path:** `app/assets/images/greedy/chest_open.png` — 400 × 400 px
**Path:** `app/assets/images/greedy/chest_locked.png` — 400 × 400 px
> An open wooden treasure chest with the lid thrown back, overflowing with gold coins and a few coloured gems, gold banding and a gold lock plate. And a matching closed version in desaturated grey-brown wood with grey banding, for the locked state.

The open chest's lid must be **thrown fully back** so the coins read clearly at
24 px — the milestone markers on the jackpot bar are that small.

**Path:** `app/assets/images/greedy/hot_badge.png` — 300 × 140 px
> A small red-orange rounded tag with a little flame at one end, thick dark-brown outline. No text — the app draws «ساخن» over it.

**Path:** `app/assets/images/greedy/bg_pattern.png` — 512 × 512 px (opaque, **tileable**)
> A seamless low-contrast cyan mobile-game background pattern with tiny abstract leaves, four-point sparkles, curved strokes and faint food doodles. Subtle enough that Arabic text and a wheel stay readable on top. Seamless on all four edges. No text, no logo.

---

## 5. Hub tile (games list artwork)

**Path:** `app/assets/images/cards/card_greedy.png`
**Size:** 1200 × 600 px (2:1, opaque)

**This one already exists.** It is generated from the game's own painters by
`flutter test test/greedy_cat_art_test.dart`, so the card can never drift from
the screen it opens. Replace it only if you want illustrated key art:

> A 2:1 banner for a kawaii food-wheel jackpot game: a fluffy white-and-lavender cartoon cat sitting at the centre of a warm wooden eight-spoke wheel ringed with cream plaques of colourful food, on a bright cyan patterned background with gold sparkles. Cheerful arcade energy, thick dark-brown outlines, clean 2D vector illustration with subtle 3D shading. Leave the left third visually calm — a title is drawn over it. No text, no watermark.

The hub already points at this path, so dropping a replacement in is the whole job.

---

## 6. Avatars (optional)

**Path:** `app/assets/images/greedy/avatar_<1..6>.png` — 200 × 200 px

Only needed if the leaderboard should show generated faces for players with no
avatar; today it falls back to the player's initial on a cream disc, which is
fine.

> Six original circular social-game player avatars: diverse fictional cartoon faces and animals, distinct colours and silhouettes, friendly expressions, clean circular crop, consistent kawaii vector style. No real people, no celebrity resemblance, no logos.

---

## 7. Sound

**Already done — do not source anything.** All twelve effects *and* the looping
background music bed are synthesised by
`app/assets/sounds/generate_greedy_sounds.py` (marimba, plucked bass, soft
shaker, a wooden ratchet for the spin, and a 16-second I-vi-IV-V carnival loop),
so they are original, license-free and reproducible. Re-run that script to
regenerate any of them.

If you would rather replace the music bed with a professionally produced track,
it must be properly licensed for commercial use — drop it at
`app/assets/sounds/greedy_theme.wav`, same name, and it is picked up with no
code change.

---

## What I do once you deliver

1. `app/assets/images/greedy/` is already declared in `app/pubspec.yaml`, and
   the food icons are already looked up by key — those eight files need **no
   code change at all**, they just start appearing.
2. Point the mascot, wheel frame, plaque, pointer, coin, chest and hot badge at
   the sprites in `app/lib/screens/games/greedy_cat_art.dart`, keeping the
   painted versions as the fallback branch.
3. Drop `card_greedy.png` in and the hub tile picks it up.
4. Swap in a replacement music bed if one arrives — same filename, no code change.

Partial deliveries are fine and expected — anything you do not send stays
painted, and the two look consistent enough to mix.
