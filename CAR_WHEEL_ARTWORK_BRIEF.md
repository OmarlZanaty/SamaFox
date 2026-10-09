# CAR WHEEL — artwork brief

Original artwork for عجلة السيارات (CAR WHEEL), a shared 8-segment betting wheel on the
coin system. Look: dark social-game backdrop (near-black navy → deep purple), a big glossy
crimson/pink wheel with a thick purple + gold rim, green/blue/purple/red chips, gold accents.
Glossy 3D casual mobile game finish, consistent top-left lighting. Generated with Codex
(ChatGPT image generation, gpt-6-astra), then normalized by `tools/car_wheel_art_prep.cjs`
into `app/assets/images/games/car_wheel/`.

**Hard rule — originality.** Every car brand here is FICTIONAL. No emblem may resemble a real
manufacturer's badge (Bugatti, BMW, Mercedes-Benz, Ferrari, Lamborghini, Volkswagen, Porsche,
Bentley, Jaguar, Land Rover or any other): no prancing horse, no charging bull, no three-pointed
star, no blue/white roundel, no VW letters, no Porsche crest, no winged B, no leaping cat. No
real car models, no people, no currency symbols, no text except where a row asks for it.

The wedges, multipliers, totals and timer are painted in code; only the pieces below are images.

Cutouts: transparent background, single centered object, no shadow plate.

| file | content |
|---|---|
| background | Portrait 9:16 game backdrop: near-black navy at the top (#07080d) fading to deep purple (#281052), soft magenta/purple light blooms in the middle where a big wheel sits, faint neon edge lines, tiny bokeh sparkles. No text, no wheel, no cars, no UI. |
| rim | The OUTER RING ONLY of a big prize wheel seen straight from above: thick glossy royal-purple ring, an inner thin electric-blue glowing band and a thin gold inner edge, small gold studs evenly around it. The whole centre inside the ring is fully TRANSPARENT (it is a frame, not a disc). Perfectly circular and centered. Cutout. |
| pointer | A gold arrow-shaped wheel pointer with a red faceted gem at its top, pointing straight DOWN. Cutout. |
| hub | Centre cap of the wheel seen from above: round glossy deep-purple dome with a gold ring and a soft pink glow, completely BLANK centre (no text, no symbol). Cutout. |
| chip_100 | Casino chip seen from above, bright green (#1faf49) with white dashed edge inserts, blank centre. Cutout. |
| chip_1k | Casino chip seen from above, blue (#1989d7) with white dashed edge inserts, blank centre. Cutout. |
| chip_10k | Casino chip seen from above, purple (#8a3dc3) with white dashed edge inserts, blank centre. Cutout. |
| chip_100k | Casino chip seen from above, crimson red (#bb2d43) with gold edge inserts, blank centre. Cutout. |
| emblem_aurelia | Fictional car badge "Aurelia": a crimson shield with a bold gold geometric letter A, gold rim. Cutout. |
| emblem_bavaro | Fictional car badge "Bavaro": a black hexagon badge with three small silver diamonds in a row, silver rim. Cutout. |
| emblem_stellaro | Fictional car badge "Stellaro": a gold eight-pointed geometric star inside a dark-red ring. Cutout. |
| emblem_ferrarion | Fictional car badge "Ferrarion": a yellow-gold oval with two abstract swept wings forming a stylised letter F, dark red outline. Cutout. |
| emblem_lambrex | Fictional car badge "Lambrex": a black pointed shield with an abstract gold falcon head in sharp geometric facets. Cutout. |
| emblem_voltara | Fictional car badge "Voltara": a round steel-blue badge with a stylised lightning-bolt letter V in silver. Cutout. |
| emblem_porsenna | Fictional car badge "Porsenna": a red rounded shield split diagonally by a gold band with a bold letter P. Cutout. |
| emblem_bentara | Fictional car badge "Bentara": a dark round badge with a chrome numeral 8 inside a laurel ring of thin chrome leaves. Cutout. |
| trophy | Gold trophy cup with a small pink gem. Cutout. |
| logo | Title logo "CAR WHEEL" in chunky gold 3D letters with a small red wheel and a silhouette of a generic (unbranded) sports car behind it. Cutout. |
| card | 2:1 games-hub banner: a glossy crimson prize wheel with a purple/gold rim, colourful chips and a sleek generic unbranded supercar in front, on a dark purple glowing background. No text (the hub draws the title), no real brands. |

## v2 redesign (2026-10-09)

| file | content |
|---|---|
| velvet_atrium | Portrait backdrop: a dark crimson-and-gold palace atrium with tall arches, a nebula glow in the upper middle and a reflective marble stage floor. No text, no wheel, no cars. (Codex gpt-6-astra.) |

The wedges, gloss, rim lights, countdown ring, pointer kick, coin burst and bet cards are painted in
code (`car_wheel_wheel.dart`, `car_wheel_effects.dart`, `car_wheel_widgets.dart`). The rim lights sit
on the 14 studs of `rim.png` (angles listed in `_BulbPainter.studs`); a new rim must keep those
positions or update the list.
