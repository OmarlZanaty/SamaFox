"""Prepares generated artwork for بوابات أوليمبوس (Gates of Olympus).

Image models do not give you what the game needs. They give you a square JPEG
with an opaque background, a caption baked into a corner, and — if you generated
five gems in five separate calls — five different lighting rigs. This closes
that gap.

    # 1. Audit what you have against what the game loads.
    python tools/olympus_art_prep.py check

    # 2. Slice a contact sheet into the individual symbol files.
    python tools/olympus_art_prep.py sheet gems_sheet.png --set gems
    python tools/olympus_art_prep.py sheet artefacts_sheet.png --set artefacts

    # 3. Process a single asset (cuts background to alpha, resizes to spec).
    python tools/olympus_art_prep.py one zeus_raw.png --name zeus

Everything writes into app/assets/images/olympus/ with the exact filenames the
game loads, so a processed file is live on the next run with no code change.

Nothing here is destructive: existing files are backed up to .bak before being
overwritten, and --dry-run shows what would happen without writing.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

# The Windows console defaults to cp1252, which raises UnicodeEncodeError on the
# arrows in this script's output and on the Arabic in its --help text. Force
# UTF-8 and degrade gracefully rather than crashing a run half way through.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "app" / "assets" / "images" / "olympus"
CARD_DIR = ROOT / "app" / "assets" / "images" / "cards"

# How each asset is treated.
#   cutout  — flat background is removed to alpha, then trimmed and padded
#   opaque  — resized only; the background is the artwork
#   additive— light on black; the black IS the transparency, so alpha is left
#             alone and only the size is corrected
TRANSPARENT, OPAQUE, ADDITIVE = "cutout", "opaque", "additive"

SPEC: dict[str, tuple[int, int, str]] = {
    # Low symbols
    "symbol_gem_blue": (300, 300, TRANSPARENT),
    "symbol_gem_green": (300, 300, TRANSPARENT),
    "symbol_gem_yellow": (300, 300, TRANSPARENT),
    "symbol_gem_purple": (300, 300, TRANSPARENT),
    "symbol_gem_red": (300, 300, TRANSPARENT),
    # Premium symbols
    "symbol_ring": (300, 300, TRANSPARENT),
    "symbol_chalice": (300, 300, TRANSPARENT),
    "symbol_hourglass": (300, 300, TRANSPARENT),
    "symbol_crown": (300, 300, TRANSPARENT),
    # Specials
    "symbol_scatter_zeus": (300, 300, TRANSPARENT),
    "symbol_mult_orb": (300, 300, TRANSPARENT),
    # Character
    "zeus": (900, 1200, TRANSPARENT),
    "zeus_strike": (900, 1200, TRANSPARENT),
    "zeus_celebrate": (900, 1200, TRANSPARENT),
    "zeus_pedestal": (700, 400, TRANSPARENT),
    # Scene
    "bg_olympus": (1920, 1080, OPAQUE),
    "bg_olympus_bonus": (1920, 1080, OPAQUE),
    "cloud_far": (2048, 512, TRANSPARENT),
    "cloud_near": (2048, 512, TRANSPARENT),
    # Effects
    "fx_win_flame": (256, 256, ADDITIVE),
    "fx_explosion": (256, 256, ADDITIVE),
    "fx_lightning_bolt": (512, 512, ADDITIVE),
    "fx_particle_spark": (128, 128, ADDITIVE),
    "fx_coin": (128, 128, ADDITIVE),
    "fx_burst_green": (1024, 1024, ADDITIVE),
    "fx_trumpet": (512, 256, ADDITIVE),
    # Frame and ornament
    "fx_tumble_banner": (768, 192, TRANSPARENT),
    "frame_grid": (1200, 1000, TRANSPARENT),
    "ornament_owl": (400, 900, TRANSPARENT),
    "logo": (1024, 512, TRANSPARENT),
}

CARD = ("card_olympus", 1200, 600, OPAQUE)

# Sets whose cells must share one frame rather than each being normalised on its
# own. A character sheet is the case that matters: the strike pose is taller (arm
# overhead) and the celebrate pose is wider (arms spread), so per-cell trimming
# would scale each one differently and the body would change size between poses.
# The app cross-fades them on a single rect, so that reads as Zeus jumping.
UNIFORM_SETS = {"zeus"}

# Assets with background trapped inside them, which a border flood fill cannot
# reach. frame_grid is a picture frame: its whole centre is background.
HOLLOW_ASSETS = {"frame_grid"}

# Contact sheets: generating a whole set in ONE image is the only reliable way
# to get consistent lighting and colour across it. Order is left-to-right,
# top-to-bottom, matching the sheet prompts in OLYMPUS_ARTWORK_BRIEF.md.
SHEETS: dict[str, tuple[int, int, list[str]]] = {
    # name: (cols, rows, filenames in reading order)
    "gems": (5, 1, [
        "symbol_gem_blue",
        "symbol_gem_green",
        "symbol_gem_yellow",
        "symbol_gem_purple",
        "symbol_gem_red",
    ]),
    "artefacts": (4, 1, [
        "symbol_ring",
        "symbol_chalice",
        "symbol_hourglass",
        "symbol_crown",
    ]),
    "specials": (2, 1, ["symbol_scatter_zeus", "symbol_mult_orb"]),
    "zeus": (3, 1, ["zeus", "zeus_strike", "zeus_celebrate"]),
}


# ── Background removal ───────────────────────────────────────────────────────

def cut_background(img: Image.Image, tolerance: int = 32,
                   enclosed: bool = False) -> Image.Image:
    """Removes a flat background by flood-filling inward from the four corners.

    This is deliberately conservative: it only clears pixels reachable from an
    edge whose colour is close to that corner's, so an object that happens to
    contain the background colour internally keeps it. It works well on the
    "plain neutral background" the prompts ask for and poorly on a busy or
    gradient one — if the result looks chewed, cut it by hand in an editor
    instead and re-run with --no-cut.
    """
    img = img.convert("RGBA")
    rgb = np.asarray(img, dtype=np.int16)[:, :, :3]
    h, w = rgb.shape[:2]

    # Seed from whichever corners agree with each other, so a corner that
    # happens to land on artwork does not poison the fill.
    corners = [rgb[0, 0], rgb[0, w - 1], rgb[h - 1, 0], rgb[h - 1, w - 1]]
    key = np.median(np.stack(corners), axis=0)

    close = (np.abs(rgb - key).sum(axis=2) <= tolerance)

    # Flood fill from the border across `close`, iteratively. A simple dilation
    # loop is fast enough at these sizes and avoids a scipy dependency.
    reach = np.zeros((h, w), dtype=bool)
    reach[0, :] |= close[0, :]
    reach[-1, :] |= close[-1, :]
    reach[:, 0] |= close[:, 0]
    reach[:, -1] |= close[:, -1]

    while True:
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= close
        if np.array_equal(grown, reach):
            break
        reach = grown

    # A hollow asset - a picture frame, a ring - has background in its middle
    # that no flood fill from the edge can ever reach, because the artwork
    # encloses it. For those, clear every background-coloured pixel regardless
    # of connectivity. Only safe when the artwork contains nothing near the
    # background colour, which is why it is opt-in.
    if enclosed:
        reach = close

    alpha = np.asarray(img, dtype=np.uint8)[:, :, 3].copy()
    alpha[reach] = 0

    out = img.copy()
    out.putalpha(Image.fromarray(alpha))
    # A one-pixel feather kills the hard jaggies the flood fill leaves behind.
    a = out.getchannel("A").filter(ImageFilter.GaussianBlur(0.6))
    out.putalpha(a)
    return out


def trim_and_pad(img: Image.Image, size: tuple[int, int], pad_frac: float = 0.08) -> Image.Image:
    """Crops to the visible content, then centres it in the target box.

    The game draws every symbol inside a square cell, so a symbol that is
    off-centre or inconsistently scaled in its own file looks wrong on the board
    no matter how good the artwork is. This normalises that.
    """
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    tw, th = size
    inner_w = int(tw * (1 - pad_frac * 2))
    inner_h = int(th * (1 - pad_frac * 2))
    img.thumbnail((inner_w, inner_h), Image.LANCZOS)

    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(img, ((tw - img.width) // 2, (th - img.height) // 2), img)
    return canvas


def fit_exact(img: Image.Image, size: tuple[int, int], mode: str) -> Image.Image:
    """Covers the target box and centre-crops, for backgrounds and banners."""
    tw, th = size
    scale = max(tw / img.width, th / img.height)
    resized = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    left = (resized.width - tw) // 2
    top = (resized.height - th) // 2
    out = resized.crop((left, top, left + tw, top + th))
    return out.convert("RGB") if mode == OPAQUE else out.convert("RGBA")


# ── Pipeline ─────────────────────────────────────────────────────────────────

def process(img: Image.Image, name: str, size: tuple[int, int], mode: str,
            cut: bool = True, tolerance: int = 32, trim: bool = True,
            enclosed: bool | None = None) -> Image.Image:
    if mode == OPAQUE:
        return fit_exact(img, size, OPAQUE)
    if mode == ADDITIVE:
        # Light on black: the black is the transparency, so never cut it.
        return fit_exact(img.convert("RGB"), size, ADDITIVE)
    img = img.convert("RGBA")
    if cut:
        hollow = name in HOLLOW_ASSETS if enclosed is None else enclosed
        img = cut_background(img, tolerance, enclosed=hollow)
    # Tall/wide framing pieces are covered, not padded — they are meant to fill.
    if name in {"frame_grid", "cloud_far", "cloud_near", "fx_tumble_banner"}:
        return fit_exact(img, size, TRANSPARENT)
    if not trim:
        return fit_contain(img, size)
    return trim_and_pad(img, size)


def detect_cells(img: Image.Image, cols: int, rows: int, tolerance: int = 40,
                 split_tolerance: int = 150):
    """Finds each object's real bounding box instead of dividing evenly.

    An image model never spaces a contact sheet perfectly. On the first gem sheet
    the green triangle overhung the even-fifth boundary by 35px, so naive slicing
    would have clipped it and dropped the sliver into the blue gem's cell.

    Two thresholds, because one is not enough. `split_tolerance` is strict and
    sees only solid artwork - that is what separates the objects, and it is what
    makes this work on the Zeus sheet, where the figures' lightning glows overlap
    and a single loose threshold merges all three into one blob. `tolerance` is
    loose and sees the faint glow too - that is what measures each object once
    the split points are known, so no halo gets clipped.

    Returns boxes in reading order, or None if the layout does not resolve to
    exactly cols*rows objects, in which case the caller falls back to even
    division and says so.
    """
    a = np.asarray(img.convert("RGB"), dtype=np.int16)
    h, w = a.shape[:2]
    key = np.median(
        np.stack([a[0, 0], a[0, w - 1], a[h - 1, 0], a[h - 1, w - 1]]), axis=0
    )
    diff = np.abs(a - key).sum(axis=2)
    solid = diff > split_tolerance
    loose = diff > tolerance

    def runs(mask_1d, min_len):
        out, start = [], None
        for i, on in enumerate(mask_1d):
            if on and start is None:
                start = i
            elif not on and start is not None:
                if i - start >= min_len:
                    out.append((start, i - 1))
                start = None
        if start is not None and len(mask_1d) - start >= min_len:
            out.append((start, len(mask_1d) - 1))
        return out

    def bands(solid_1d, loose_1d, count, min_len):
        """Splits an axis into `count` regions, cutting midway between objects."""
        found = runs(solid_1d, min_len)
        if len(found) != count:
            return None
        edges = [0]
        for i in range(len(found) - 1):
            edges.append((found[i][1] + found[i + 1][0]) // 2)
        edges.append(len(solid_1d))
        out = []
        for i in range(count):
            lo, hi = edges[i], edges[i + 1]
            idx = np.where(loose_1d[lo:hi])[0]
            if idx.size == 0:
                return None
            out.append((lo + idx[0], lo + idx[-1]))
        return out

    row_bands = bands(solid.any(axis=1), loose.any(axis=1), rows, max(8, h // 40))
    if row_bands is None:
        return None

    boxes = []
    for (y0, y1) in row_bands:
        col_bands = bands(
            solid[y0:y1 + 1, :].any(axis=0),
            loose[y0:y1 + 1, :].any(axis=0),
            cols,
            max(8, w // 60),
        )
        if col_bands is None:
            return None
        for (x0, x1) in col_bands:
            sub = loose[y0:y1 + 1, x0:x1 + 1]
            ys = np.where(sub.any(axis=1))[0]
            boxes.append((x0, y0 + ys[0], x1 + 1, y0 + ys[-1] + 1))
    return boxes


def detect_cells_by_minima(img: Image.Image, cols: int, rows: int,
                           tolerance: int = 40, split_tolerance: int = 150):
    """Splits a sheet where it is thinnest, for objects that genuinely touch.

    The gap-based detector needs a column of clean background between objects.
    A character sheet often has none: on the Zeus sheet the lightning from each
    pose reaches into the next, and at no threshold is there a clear vertical
    gap anywhere across the full width.

    So instead of looking for emptiness, this looks for the *thinnest* column
    near each expected boundary and cuts there. The search window is narrow
    enough that it cannot wander into the middle of a figure.
    """
    a = np.asarray(img.convert("RGB"), dtype=np.int16)
    h, w = a.shape[:2]
    key = np.median(
        np.stack([a[0, 0], a[0, w - 1], a[h - 1, 0], a[h - 1, w - 1]]), axis=0
    )
    diff = np.abs(a - key).sum(axis=2)
    solid = diff > split_tolerance
    loose = diff > tolerance

    if rows != 1:
        return None  # only the single-row case is needed, and it is the safe one

    density = solid.sum(axis=0)
    edges = [0]
    window = max(4, w // (cols * 4))
    for i in range(1, cols):
        centre = round(i * w / cols)
        lo = max(1, centre - window)
        hi = min(w - 1, centre + window)
        edges.append(lo + int(np.argmin(density[lo:hi])))
    edges.append(w)

    ys = np.where(loose.any(axis=1))[0]
    if ys.size == 0:
        return None
    y0, y1 = int(ys[0]), int(ys[-1])

    boxes = []
    for i in range(cols):
        lo, hi = edges[i], edges[i + 1]
        idx = np.where(loose[y0:y1 + 1, lo:hi].any(axis=0))[0]
        if idx.size == 0:
            return None
        boxes.append((lo + int(idx[0]), y0, lo + int(idx[-1]) + 1, y1 + 1))
    return boxes


def unify_boxes(boxes):
    """Gives every box a common top, bottom and width.

    Top and bottom are shared so the figures keep one baseline; the width is the
    widest object's, centred on each object's own centre, so nothing is clipped.
    A box may extend past the sheet edge - that is fine, the background has
    already been cut to transparency, so the overhang is empty pixels.

    Returns (unified boxes, each object's own x-span), because widening a box
    makes it overlap its neighbours and the caller has to mask that bleed off.
    """
    y0 = min(b[1] for b in boxes)
    y1 = max(b[3] for b in boxes)
    w = max(b[2] - b[0] for b in boxes)
    out, spans = [], []
    for (x0, _, x1, _) in boxes:
        cx = (x0 + x1) // 2
        left = cx - w // 2
        out.append((left, y0, left + w, y1))
        spans.append((x0, x1))
    return out, spans


def mask_to_span(cell: Image.Image, box, span) -> Image.Image:
    """Clears anything outside this object's own horizontal extent.

    A unified box is as wide as the widest pose, so for the narrower poses it
    reaches into the next figure along and drags in a stray hand or foot. The
    object's own bounding box already includes its glow and its lightning, so
    clipping to exactly that removes the neighbour and nothing else.
    """
    left = box[0]
    keep0 = max(0, span[0] - left)
    keep1 = min(cell.width, span[1] - left + 1)
    out = cell.convert("RGBA")
    a = np.asarray(out, dtype=np.uint8)[:, :, 3].copy()
    a[:, :keep0] = 0
    a[:, keep1:] = 0
    out.putalpha(Image.fromarray(a))
    return out


def fit_contain(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scales to fit inside the box and centres, without trimming to content.

    Trimming is what breaks a shared frame, so uniform sets take this path.
    """
    tw, th = size
    out = img.copy()
    out.thumbnail((tw, th), Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(out, ((tw - out.width) // 2, (th - out.height) // 2), out)
    return canvas


def drop_specks(img: Image.Image, keep_ratio: float = 0.06) -> Image.Image:
    """Removes small disconnected fragments, keeping the main figure.

    Splitting a character sheet where the poses touch leaves a crumb of the
    neighbour behind - a stray hand, a chip of lightning. Those are separate
    blobs, far smaller than the figure, so anything under `keep_ratio` of the
    largest blob's area is cleared.

    Labelling runs on a quarter-scale mask (a few thousand cells rather than a
    million) and the decision is scaled back up, which is accurate enough for
    "is this a crumb or a god" and fast enough to not be noticed.
    """
    from collections import deque

    rgba = img.convert("RGBA")
    alpha = np.asarray(rgba, dtype=np.uint8)[:, :, 3]
    small = alpha[::4, ::4] > 24
    h, w = small.shape

    labels = np.zeros((h, w), dtype=np.int32)
    sizes = [0]
    current = 0
    for sy in range(h):
        for sx in range(w):
            if not small[sy, sx] or labels[sy, sx]:
                continue
            current += 1
            count = 0
            q = deque([(sy, sx)])
            labels[sy, sx] = current
            while q:
                y, x = q.popleft()
                count += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and small[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        q.append((ny, nx))
            sizes.append(count)

    if current <= 1:
        return rgba

    biggest = max(sizes)
    keep = {i for i, n in enumerate(sizes) if i and n >= biggest * keep_ratio}
    keep_small = np.isin(labels, list(keep))

    # Scale the keep-mask back to full resolution.
    keep_full = np.repeat(np.repeat(keep_small, 4, axis=0), 4, axis=1)
    keep_full = keep_full[:alpha.shape[0], :alpha.shape[1]]
    if keep_full.shape != alpha.shape:
        pad = np.zeros(alpha.shape, dtype=bool)
        pad[:keep_full.shape[0], :keep_full.shape[1]] = keep_full
        keep_full = pad

    out_alpha = alpha.copy()
    out_alpha[~keep_full] = 0
    rgba.putalpha(Image.fromarray(out_alpha))
    return rgba


def dest_for(name: str) -> Path:
    return (CARD_DIR if name == CARD[0] else OUT_DIR) / f"{name}.png"


# Backups live OUTSIDE the asset folders. pubspec.yaml declares
# assets/images/olympus/ as a whole directory, so anything left in there - a
# .bak included - gets bundled into the shipped app.
BACKUP_DIR = ROOT / ".olympus-art-backups"


def save(img: Image.Image, name: str, dry: bool) -> Path:
    path = dest_for(name)
    if dry:
        print(f"  would write {path.relative_to(ROOT)}  {img.width}x{img.height}")
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, BACKUP_DIR / f"{name}.png")
    img.save(path)
    print(f"  wrote {path.relative_to(ROOT)}  {img.width}x{img.height}")
    return path


def spec_for(name: str) -> tuple[int, int, str]:
    if name == CARD[0]:
        return CARD[1], CARD[2], CARD[3]
    if name not in SPEC:
        sys.exit(f"unknown asset '{name}'. Known: {', '.join(sorted(SPEC))}, {CARD[0]}")
    return SPEC[name]


# ── Commands ─────────────────────────────────────────────────────────────────

def cmd_check(_args) -> None:
    """Audits the asset folder against what the game actually loads."""
    print(f"\n  {OUT_DIR.relative_to(ROOT)}\n")
    missing, ok, wrong = [], [], []

    for name in list(SPEC) + [CARD[0]]:
        w, h, mode = spec_for(name)
        path = dest_for(name)
        if not path.exists():
            missing.append(name)
            continue
        try:
            with Image.open(path) as im:
                size_ok = (im.width, im.height) == (w, h)
                has_alpha = im.mode in ("RGBA", "LA")
                notes = []
                if not size_ok:
                    notes.append(f"is {im.width}x{im.height}, want {w}x{h}")
                if mode == TRANSPARENT and not has_alpha:
                    notes.append("no alpha channel")
                if mode == TRANSPARENT and has_alpha:
                    a = np.asarray(im.convert("RGBA"))[:, :, 3]
                    if (a > 250).all():
                        notes.append("alpha is fully opaque (background not cut)")
                if notes:
                    wrong.append((name, "; ".join(notes)))
                else:
                    ok.append(name)
        except Exception as e:  # noqa: BLE001 - report, never crash an audit
            wrong.append((name, f"unreadable: {e}"))

    for n in ok:
        print(f"  OK       {n}")
    for n, why in wrong:
        print(f"  FIX      {n}  - {why}")
    for n in missing:
        w, h, mode = spec_for(n)
        print(f"  missing  {n}  ({w}x{h}, {mode})")

    total = len(SPEC) + 1
    print(f"\n  {len(ok)}/{total} ready, {len(wrong)} need fixing, {len(missing)} not delivered.")
    if missing or wrong:
        print("  Missing or broken files fall back to painted art — the game still runs.\n")


def cmd_sheet(args) -> None:
    """Slices a contact sheet into the individual asset files."""
    if args.set not in SHEETS:
        sys.exit(f"unknown set '{args.set}'. Known: {', '.join(SHEETS)}")
    cols, rows, names = SHEETS[args.set]

    src = Image.open(args.image)
    print(f"\n  {args.image}: {src.width}x{src.height} -> {cols}x{rows} cells")

    boxes = None if args.even else detect_cells(src, cols, rows)
    if boxes is None and not args.even:
        # Objects that touch have no gap to find; cut where they are thinnest.
        boxes = detect_cells_by_minima(src, cols, rows)
    if boxes:
        print("  located each object by its own bounds\n")
    else:
        if not args.even:
            print(f"  could not resolve {cols}x{rows} objects; dividing evenly\n")
        cw, ch = src.width // cols, src.height // rows
        boxes = [
            ((i % cols) * cw, (i // cols) * ch, (i % cols) * cw + cw, (i // cols) * ch + ch)
            for i in range(cols * rows)
        ]

    # Cut the background from the WHOLE sheet before slicing, not per cell.
    # detect_cells crops tight to each object, which leaves almost no background
    # border for the flood fill to start from - so a baked-in drop shadow
    # survives no matter how high the tolerance goes. The full sheet has a wide
    # clean border, and its background is all one connected region, so one pass
    # here clears every object's surround at once.
    sliceable = src
    if not args.no_cut:
        sliceable = cut_background(src, args.tolerance)

    uniform = args.set in UNIFORM_SETS
    spans = None
    if uniform and boxes:
        boxes, spans = unify_boxes(boxes)
        print("  shared frame: one baseline and one scale across the set\n")

    for i, (name, box) in enumerate(zip(names, boxes)):
        cell = sliceable.crop(box)
        if spans is not None:
            cell = mask_to_span(cell, box, spans[i])
            cell = drop_specks(cell)
        w, h, mode = spec_for(name)
        save(process(cell, name, (w, h), mode, cut=False,
                     tolerance=args.tolerance, trim=not uniform),
             name, args.dry_run)
    print()


def cmd_one(args) -> None:
    """Processes a single generated image into one asset file."""
    w, h, mode = spec_for(args.name)
    src = Image.open(args.image)
    print(f"\n  {args.image}: {src.width}x{src.height} → {args.name} ({w}x{h}, {mode})\n")
    save(process(src, args.name, (w, h), mode, cut=not args.no_cut,
                 tolerance=args.tolerance,
                 enclosed=True if args.enclosed else None),
         args.name, args.dry_run)
    print()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", help="audit the asset folder against the spec")
    c.set_defaults(func=cmd_check)

    s = sub.add_parser("sheet", help="slice a contact sheet into asset files")
    s.add_argument("image")
    s.add_argument("--set", required=True, choices=sorted(SHEETS))
    s.add_argument("--even", action="store_true",
                   help="divide into equal cells instead of locating each object")
    s.set_defaults(func=cmd_sheet)

    o = sub.add_parser("one", help="process a single image into one asset file")
    o.add_argument("image")
    o.add_argument("--name", required=True)
    o.add_argument("--enclosed", action="store_true",
                   help="also clear background trapped inside the artwork "
                        "(frames, rings); automatic for frame_grid")
    o.set_defaults(func=cmd_one)

    for sp in (s, o):
        sp.add_argument("--tolerance", type=int, default=32,
                        help="background colour tolerance, 0-255 (default 32)")
        sp.add_argument("--no-cut", action="store_true",
                        help="skip background removal (the file already has alpha)")
        sp.add_argument("--dry-run", action="store_true", help="show, do not write")

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
