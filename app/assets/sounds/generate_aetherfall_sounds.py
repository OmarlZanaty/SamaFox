"""Synthesises the أثيرفول (Aetherfall) sound effects.

Same approach as generate_plinko_sounds.py and generate_crash_sounds.py:
generated rather than sourced, so the assets stay small, license-free and
reproducible. Run from this directory:

    python generate_aetherfall_sounds.py

Consumed by app/lib/screens/games/aetherfall_sfx.dart.
"""

import numpy as np
import wave

RATE = 44100

# Every pitched cue is drawn from one bright pentatonic set (D major pentatonic
# plus octaves). A cascade fires several cues on top of each other, so they have
# to agree harmonically or a long tumble turns into mush.
D5, E5, FS5, A5, B5 = 587.33, 659.25, 739.99, 880.00, 987.77
D6, E6, FS6, A6, D7 = 1174.66, 1318.51, 1479.98, 1760.00, 2349.32


def write(name, samples, fade_ms=3, gain=0.89):
    """Normalise, de-click the edges and write a 16-bit mono WAV."""
    x = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * gain

    n = int(RATE * fade_ms / 1000)
    if n > 0 and len(x) > 2 * n:
        ramp = np.linspace(0, 1, n)
        x[:n] *= ramp
        x[-n:] *= ramp[::-1]

    with wave.open(name, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype("<i2").tobytes())
    print("%-36s %5.3fs" % (name, len(x) / RATE))


def t(dur):
    return np.linspace(0, dur, int(RATE * dur), endpoint=False)


def place(base, sig, at):
    """Mix sig into base starting at `at` seconds, clipped to fit."""
    i = int(RATE * at)
    n = min(len(sig), len(base) - i)
    if n > 0:
        base[i:i + n] += sig[:n]
    return base


def air(dur, smooth=64, seed=0):
    """Band-limited noise — a breath of shimmer rather than a hiss."""
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, int(RATE * dur))
    return np.convolve(n, np.hanning(smooth), mode="same")


def sweep(dur, f0, f1, curve=1.0):
    """Sine glide f0 to f1. Phase is integrated so the pitch move never clicks."""
    x = t(dur)
    freq = f0 + (f1 - f0) * (x / dur) ** curve
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def bell(freq, dur, decay=6.0, shimmer=0.18, seed=0):
    """Glass-bell voice: inharmonic partials that die faster than the fundamental.

    The whole game is meant to sound like struck crystal, so this one voice does
    most of the work and the cues differ mainly in pitch and decay.
    """
    x = t(dur)
    out = np.zeros_like(x)
    for mult, amp, dmul in ((1.0, 1.0, 1.0), (2.01, 0.45, 1.5),
                            (3.03, 0.22, 2.2), (4.78, 0.11, 3.0)):
        out += amp * np.sin(2 * np.pi * freq * mult * x) * np.exp(-x * decay * dmul)
    if shimmer:
        out += air(dur, 18, seed) * np.exp(-x * decay * 2.5) * shimmer
    return out


def arpeggio(notes, dur, spacing=0.07, decay=3.6):
    """Notes entering one after another and ringing on together."""
    x = t(dur)
    out = np.zeros_like(x)
    for i, f in enumerate(notes):
        delay = i * spacing
        d = np.clip(x - delay, 0, None)
        voice = np.sin(2 * np.pi * f * d) + 0.34 * np.sin(4 * np.pi * f * d)
        voice *= np.exp(-d * decay)
        voice[x < delay] = 0
        out += voice
    return out


# --- spin loop -------------------------------------------------------------

def ignite(dur=0.55):
    """Spin start: air rushes into the chamber, then the chamber strikes."""
    x = t(dur)
    rush = air(dur, 96, 2) * np.clip(x / 0.3, 0, 1) ** 2
    rush *= np.exp(-np.clip(x - 0.3, 0, None) * 9) * 0.5
    out = rush + sweep(dur, 180, 900, 1.6) * np.exp(-x * 3.2) * 0.35
    return place(out, bell(D6, 0.27, decay=7.0, seed=3) * 0.9, 0.28)


def populate(dur=0.42):
    """Symbols settling in — five soft blips walking up the scale."""
    out = np.zeros(int(RATE * dur))
    for i, f in enumerate((D5, E5, FS5, A5, B5)):
        blip = bell(f * 1.5, 0.10, decay=26, shimmer=0.05, seed=10 + i)
        place(out, blip * (0.55 - 0.06 * i), 0.012 + i * 0.055)
    return out


def win_discovery(dur=0.30):
    """Fires once per paying cluster, and several overlap inside one cascade —
    so it stays short, quiet and consonant: a fifth, struck twice."""
    out = np.zeros(int(RATE * dur))
    place(out, bell(A6, 0.26, decay=13, seed=21) * 0.9, 0.0)
    place(out, bell(E6, 0.22, decay=15, seed=22) * 0.55, 0.035)
    return out


def dissolve(dur=0.45):
    """Winning tiles crumble: a downward glide under thinning dust."""
    x = t(dur)
    return (sweep(dur, 1500, 260, 0.8) * np.exp(-x * 6.5) * 0.5
            + air(dur, 20, 5) * np.exp(-x * 8.5) * 0.4)


def refill(dur=0.38):
    """Replacements drop into the gaps — three quick descending taps."""
    out = np.zeros(int(RATE * dur))
    for i, f in enumerate((FS6, E6, D6)):
        tap = bell(f, 0.13, decay=22, shimmer=0.08, seed=30 + i)
        place(out, tap * (0.7 - 0.12 * i), 0.01 + i * 0.075)
    return out


# --- features --------------------------------------------------------------

def charge(dur=0.5):
    """A charge orb lands: electric, with a tremolo that reads as stored power."""
    x = t(dur)
    tone = sum(np.sin(2 * np.pi * 220 * k * x) / k for k in range(1, 7))
    tone *= (0.65 + 0.35 * np.sin(2 * np.pi * 27 * x)) * np.exp(-x * 4.0) * 0.45
    return place(tone, air(0.03, 6, 7) * np.exp(-t(0.03) * 180) * 0.6, 0.0)


def wild(dur=0.55):
    """Wild activation: a bright rising figure with a metallic edge."""
    x = t(dur)
    return (arpeggio((A5, D6, FS6, A6), dur, spacing=0.045, decay=5.0) * 0.5
            + sweep(dur, 700, 2600, 1.4) * np.exp(-x * 7.0) * 0.18)


def key_collect(dur=0.62):
    """Key pickup: one clean high bell with a long, quiet tail."""
    x = t(dur)
    sparkle = air(dur, 14, 42) * np.exp(-np.clip(x - 0.05, 0, None) * 5.5) * 0.16
    return bell(D7, dur, decay=4.2, shimmer=0.22, seed=41) * 0.85 + sparkle


def bonus_transition(dur=1.7):
    """Into the bonus: an accelerating riser that blooms into a chord.

    The riser is faded rather than cut at the bloom — a hard gate on a 2 kHz
    sweep clicks loudly enough to hear over the chord.
    """
    x = t(dur)
    gate = np.clip((1.16 - x) / 0.04, 0, 1)
    riser = sweep(dur, 150, 2000, 2.6) * np.clip(x / 1.1, 0, 1) ** 1.5 * 0.4
    wind = air(dur, 40, 51) * np.clip(x / 1.1, 0, 1) ** 2 * 0.35
    out = (riser + wind) * gate
    bloom = arpeggio((D5, A5, D6, FS6, A6), dur - 1.1, spacing=0.03, decay=2.6)
    return place(out, bloom * 0.42, 1.1)


def constellation_lock(dur=0.42):
    """A star locks into place: a low seat plus a high confirm."""
    x = t(dur)
    out = np.sin(2 * np.pi * 140 * x) * np.exp(-x * 22) * 0.6
    place(out, air(0.05, 10, 61) * np.exp(-t(0.05) * 90) * 0.5, 0.0)
    return place(out, bell(B5 * 2, 0.3, decay=14, seed=62) * 0.5, 0.045)


def starburst(dur=0.95):
    """Starburst: a burst, then sparks scattering upward at random."""
    x = t(dur)
    out = (air(dur, 8, 71) * np.exp(-x * 13) * 0.55
           + sweep(dur, 400, 1500, 0.5) * np.exp(-x * 9) * 0.3)
    rng = np.random.default_rng(72)
    for i in range(9):
        f = float(rng.choice((E6, FS6, A6, D7)))
        spark = bell(f, 0.28, decay=17, shimmer=0.06, seed=80 + i)
        place(out, spark * 0.28, 0.06 + rng.random() * 0.5)
    return out


# --- celebrations ----------------------------------------------------------

def celebrate(notes, dur, spacing, decay, wash_at, wash_amt, seed):
    """Shared shape for the lower three tiers: arpeggio up, then a shimmer wash."""
    x = t(dur)
    wash = air(dur, 24, seed) * np.exp(-np.clip(x - wash_at, 0, None) * 2.6) * wash_amt
    wash[x < wash_at] = 0
    return arpeggio(notes, dur, spacing=spacing, decay=decay) * 0.45 + wash


def celebrate_top(dur=2.6):
    """Top tier: a fanfare over a sustained chord, with a long shimmer tail."""
    x = t(dur)
    out = arpeggio((D5, FS5, A5, D6, FS6, A6, D7), dur, spacing=0.065, decay=1.9) * 0.4
    chord = sum(np.sin(2 * np.pi * f * x) for f in (D5, A5, D6))
    wash = air(dur, 26, 91) * np.exp(-np.clip(x - 0.35, 0, None) * 1.5) * 0.24
    wash[x < 0.35] = 0
    out += chord * np.exp(-x * 1.1) * 0.18 + wash
    return place(out, bell(D7, 1.2, decay=2.2, shimmer=0.25, seed=92) * 0.35, 0.5)


def bonus_summary(dur=1.2):
    """Bonus total reveal: a warm chord that resolves rather than excites."""
    x = t(dur)
    out = np.zeros_like(x)
    for i, f in enumerate((D5, FS5, A5, D6)):
        d = np.clip(x - i * 0.02, 0, None)
        out += np.sin(2 * np.pi * f * d) * np.exp(-d * 2.2) * (0.9 - 0.13 * i)
    return (out + air(dur, 30, 101) * np.exp(-x * 3.0) * 0.1) * 0.5


# --- UI --------------------------------------------------------------------

def ui_click(dur=0.045):
    """Small dry click for buttons and the mute toggle."""
    x = t(dur)
    env = np.exp(-x * 165)
    return (np.sin(2 * np.pi * 1400 * x) + 0.4 * np.sin(2 * np.pi * 2800 * x)) * env


def error(dur=0.26):
    """Rejected action: a dull two-step down, deliberately off the scale."""
    out = np.zeros(int(RATE * dur))
    x = t(0.12)
    for i, f in enumerate((233.08, 185.00)):
        v = (np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * f * 2.02 * x))
        place(out, v * np.exp(-x * 16) * 0.8, i * 0.10)
    return out


if __name__ == "__main__":
    write("aetherfall_ignite.wav", ignite())
    write("aetherfall_populate.wav", populate())
    write("aetherfall_win.wav", win_discovery())
    write("aetherfall_dissolve.wav", dissolve())
    write("aetherfall_refill.wav", refill())

    write("aetherfall_charge.wav", charge())
    write("aetherfall_wild.wav", wild())
    write("aetherfall_key.wav", key_collect())
    write("aetherfall_bonus_transition.wav", bonus_transition())
    write("aetherfall_lock.wav", constellation_lock())
    write("aetherfall_starburst.wav", starburst())

    # Tiers step up in length and brightness so the size of a win is audible
    # before the number on screen finishes counting.
    write("aetherfall_celebrate_low.wav",
          celebrate((D5, FS5, A5, D6), 0.9, 0.070, 4.2, 0.22, 0.14, 110))
    write("aetherfall_celebrate_mid.wav",
          celebrate((D5, FS5, A5, D6, E6, FS6), 1.3, 0.070, 3.4, 0.30, 0.18, 111))
    write("aetherfall_celebrate_high.wav",
          celebrate((D5, A5, D6, FS6, A6, D7), 1.9, 0.075, 2.6, 0.34, 0.22, 112))
    write("aetherfall_celebrate_top.wav", celebrate_top())
    write("aetherfall_bonus_summary.wav", bonus_summary())

    write("aetherfall_click.wav", ui_click())
    write("aetherfall_error.wav", error())
