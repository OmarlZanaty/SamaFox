القط الجشع (Greedy Cat) artwork drops here.

The game currently paints all of its art in code
(lib/screens/games/greedy_cat_art.dart), so this folder being empty is the
normal state, not a missing dependency.

To swap in commissioned artwork, drop transparent PNGs named after the symbol
key and the screen picks them up automatically, falling back to the painted
version for any file that is absent or unreadable:

    corn.png  chicken.png  tomato.png  goat.png
    pepper.png  fish.png  carrot.png  shrimp.png

See GREEDY_CAT_ARTWORK_BRIEF.md in the repo root for sizes, style and the full
prompt set.
