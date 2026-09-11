"""Generates the بوابات أوليمبوس effect textures and cloud bands procedurally.

Same reasoning as assets/sounds/generate_olympus_sounds.py: these are simple,
mathematical images - a spark, a coin, a radial burst, a horn - and generating them is cheaper,
reproducible and licence-free.

    python tools/olympus_fx_gen.py            # write everything
    python tools/olympus_fx_gen.py --only fx_coin fx_trumpet

The effect textures are additive light on pure black: the game composites them
with BlendMode.plus, so the black contributes nothing and no alpha is needed.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "assets" / "images" / "olympus"

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass


def _grid(w: int, h: int):
    """Normalised coordinates: x,y in [-1,1], plus radius and angle."""
    y, x = np.mgrid[0:h, 0:w]
    x = (x - (w - 1) / 2) / ((w - 1) / 2)
    y = (y - (h - 1) / 2) / ((h - 1) / 2)
    return x, y, np.hypot(x, y), np.arctan2(y, x)


def _save_rgb(name: str, rgb: np.ndarray) -> None:
    """Writes additive light on black - clipped, never normalised per-channel."""
    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB")
    path = OUT / f"{name}.png"
    img.save(path)
    print(f"  wrote {path.relative_to(ROOT)}  {img.width}x{img.height}")


def _save_rgba(name: str, rgb: np.ndarray, alpha: np.ndarray) -> None:
    a = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    c = np.clip(rgb * 255, 0, 255).astype(np.uint8)
    img = Image.fromarray(np.dstack([c, a]), "RGBA")
    path = OUT / f"{name}.png"
    img.save(path)
    print(f"  wrote {path.relative_to(ROOT)}  {img.width}x{img.height}")


# ── Effects ──────────────────────────────────────────────────────────────────

def fx_particle_spark(size: int = 128) -> None:
    """A four-point star with a soft bloom. White core, pale gold tips."""
    x, y, r, _ = _grid(size, size)

    core = np.exp(-(r / 0.10) ** 2)
    bloom = np.exp(-(r / 0.42) ** 2) * 0.45

    # Two crossed needles. Each is bright where the *other* axis is near zero,
    # falling off along its own length - which is what makes a star rather than
    # a plus sign with hard ends.
    def needle(across, along, width, length):
        return np.exp(-(across / width) ** 2) * np.exp(-(np.abs(along) / length) ** 1.4)

    rays = needle(y, x, 0.035, 0.55) + needle(x, y, 0.035, 0.55)

    v = np.clip(core + bloom + rays * 0.8, 0, 1.6)
    warm = np.stack([v, v * 0.93, v * 0.72], axis=-1)   # white core, gold falloff
    white = np.stack([core, core, core], axis=-1)
    _save_rgb("fx_particle_spark", np.clip(warm * 0.85 + white, 0, 1))


def fx_coin(size: int = 128) -> None:
    """A gold coin at a slight tilt, with a milled edge and a bright rim."""
    x, y, _, _ = _grid(size, size)

    rx, ry = 0.62, 0.80                      # tilted: narrower than it is tall
    e = np.hypot(x / rx, y / ry)
    face = (e <= 1.0).astype(float)
    edge = np.clip(1 - np.abs(e - 1.0) / 0.09, 0, 1)   # the rim band

    # Lit from the upper left, so the disc reads as a solid object.
    shade = np.clip(0.55 + 0.55 * (-x * 0.7 - y * 0.7), 0.15, 1.25)
    body = face * shade

    # A specular sweep across the upper-left face.
    spec = face * np.exp(-(((x + 0.28) ** 2 + (y + 0.34) ** 2) / 0.055))

    # Milling: ticks around the rim.
    _, _, _, ang = _grid(size, size)
    mill = edge * (0.55 + 0.45 * np.sin(ang * 34))

    v = np.clip(body * 0.85 + mill * 0.5 + spec * 0.9, 0, 1.4)
    gold = np.stack([v, v * 0.78, v * 0.30], axis=-1)
    gold += np.stack([spec, spec, spec * 0.85], axis=-1) * 0.5
    glow = np.exp(-((e - 1.0) / 0.35) ** 2) * 0.18
    gold += np.stack([glow, glow * 0.8, glow * 0.35], axis=-1)
    _save_rgb("fx_coin", np.clip(gold, 0, 1))


def fx_burst_green(size: int = 1024) -> None:
    """An emerald radial burst with long god-rays, for the celebration."""
    _, _, r, ang = _grid(size, size)

    core = np.exp(-(r / 0.085) ** 2)
    halo = np.exp(-(r / 0.55) ** 2) * 0.55

    # Rays at two frequencies so they do not look mechanically regular, each
    # fading out with radius.
    rays = (0.55 + 0.45 * np.sin(ang * 24)) * (0.5 + 0.5 * np.sin(ang * 7 + 1.2))
    rays = rays ** 2.2 * np.exp(-(r / 0.85) ** 2) * np.clip(1 - np.exp(-(r / 0.05) ** 2), 0, 1)

    v = np.clip(core * 1.3 + halo + rays * 0.85, 0, 1.6)
    emerald = np.stack([v * 0.30, v * 1.00, v * 0.55], axis=-1)
    white = np.stack([core, core, core], axis=-1) * 0.85
    _save_rgb("fx_burst_green", np.clip(emerald + white, 0, 1))


def fx_trumpet(w: int = 512, h: int = 256) -> None:
    """A ceremonial horn pointing right: tapering body into a flared bell."""
    y, x = np.mgrid[0:h, 0:w]
    xn = x / (w - 1)
    yn = (y - (h - 1) / 2) / ((h - 1) / 2)

    # Half-thickness along the length: a slim tube that flares hard at the end.
    tube = 0.085 + 0.02 * xn
    flare = np.clip((xn - 0.68) / 0.32, 0, 1) ** 2.1 * 0.72
    half = tube + flare

    body = (np.abs(yn) <= half).astype(float)
    rim = np.clip(1 - np.abs(np.abs(yn) - half) / 0.045, 0, 1)

    # Cylindrical shading across the tube, brightest just above the centreline.
    across = np.divide(yn, np.maximum(half, 1e-6))
    shade = np.clip(1.15 - 0.95 * np.abs(across + 0.25) ** 1.5, 0.1, 1.2) * body

    # Engraved bands along the body.
    bands = body * (0.5 + 0.5 * np.sin(xn * 70)) * (xn < 0.66) * 0.16

    # The mouthpiece.
    mouth = ((xn < 0.055) & (np.abs(yn) < 0.16)).astype(float)

    v = np.clip(shade * 0.9 + rim * 0.75 + bands + mouth * 0.7, 0, 1.4)
    gold = np.stack([v, v * 0.76, v * 0.28], axis=-1)
    glow = np.clip(body + rim, 0, 1) * 0.12
    gold += np.stack([glow, glow * 0.85, glow * 0.4], axis=-1)
    _save_rgb("fx_trumpet", np.clip(gold, 0, 1))


# ── Clouds: not generated ────────────────────────────────────────────────────
#
# cloud_far and cloud_near are deliberately absent. FFT-filtered noise tiles
# seamlessly, which is the hard part, but two tuning passes produced soft pale
# rectangles rather than anything that reads as cloud - the spectrum that wraps
# cleanly is also too smooth to give puffy silhouettes. Shipping those would
# have looked worse than shipping nothing.
#
# The game draws no cloud layer when the files are missing, so this costs
# nothing. If the parallax is ever wanted, buy a seamless cloud strip from a
# texture library rather than prompting or generating one.

GENERATORS = {
    "fx_particle_spark": fx_particle_spark,
    "fx_coin": fx_coin,
    "fx_burst_green": fx_burst_green,
    "fx_trumpet": fx_trumpet,
}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--only", nargs="*", choices=sorted(GENERATORS),
                   help="generate just these")
    args = p.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    names = args.only or list(GENERATORS)
    print()
    for n in names:
        GENERATORS[n]()
    print(f"\n  {len(names)} asset(s) written.\n")


if __name__ == "__main__":
    main()
