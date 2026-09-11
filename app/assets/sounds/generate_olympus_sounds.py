"""Synthesises the بوابات أوليمبوس (Gates of Olympus) sound effects.

Same approach as generate_aetherfall_sounds.py and generate_plinko_sounds.py:
generated rather than sourced, so the assets stay small, license-free and
reproducible — and so nothing here can be mistaken for the commercial game's
soundtrack, which the brief explicitly rules out copying.

    python generate_olympus_sounds.py

Consumed by app/lib/screens/games/olympus_sfx.dart.

Sound design brief: struck bronze and thunder rather than أثيرفول's glass.
Every pitched cue is drawn from one minor set so a long cascade layering five
or six of them still agrees with itself.
"""

import numpy as np
import wave

RATE = 44100

# A minor pentatonic — darker than أثيرفول's major set, which is what makes the
# same cascade structure read as a storm instead of an observatory.
A4, C5, D5, E5, G5 = 440.00, 523.25, 587.33, 659.25, 783.99
A5, C6, D6, E6, G6 = 880.00, 1046.50, 1174.66, 1318.51, 1567.98
A6, C7, E7 = 1760.00, 2093.00, 2637.02


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
    print("%-38s %5.3fs" % (name, len(x) / RATE))


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
    """Band-limited noise. Wide smoothing gives rumble, narrow gives crackle."""
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, int(RATE * dur))
    return np.convolve(n, np.hanning(smooth), mode="same")


def sweep(dur, f0, f1, curve=1.0):
    """Sine glide f0 to f1, phase-integrated so the pitch move never clicks."""
    x = t(dur)
    freq = f0 + (f1 - f0) * (x / dur) ** curve
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def bronze(freq, dur, decay=5.0, seed=0, ring=0.2):
    """Struck-bronze voice — the house sound of this game.

    Partials are stretched further from harmonic than a glass bell and the
    upper ones hang on longer, which is what separates a temple gong from a
    wine glass.
    """
    x = t(dur)
    out = np.zeros_like(x)
    for mult, amp, dmul in ((1.0, 1.0, 1.0), (2.76, 0.52, 0.85),
                            (5.40, 0.28, 1.1), (8.93, 0.14, 1.6)):
        out += amp * np.sin(2 * np.pi * freq * mult * x) * np.exp(-x * decay * dmul)
    if ring:
        out += air(dur, 14, seed) * np.exp(-x * decay * 3.0) * ring
    return out


def gem(freq, dur, decay=24, seed=0):
    """A cut stone landing: bright, very short, barely any tail."""
    x = t(dur)
    out = np.sin(2 * np.pi * freq * x) + 0.4 * np.sin(2 * np.pi * freq * 2.02 * x)
    return out * np.exp(-x * decay) + air(dur, 8, seed) * np.exp(-x * decay * 2) * 0.25


def thunder(dur, seed=0, boom=55.0):
    """Distant-to-close thunder: a low body under a wide crack."""
    x = t(dur)
    body = air(dur, 420, seed) * np.exp(-x * 3.2)
    body += np.sin(2 * np.pi * boom * x) * np.exp(-x * 4.5) * 0.6
    crack = air(dur, 6, seed + 1) * np.exp(-x * 16) * 0.5
    return body + crack


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


def horn(freq, dur, decay=2.2):
    """A brass-ish tone for the celebration fanfare: odd harmonics, slow attack."""
    x = t(dur)
    out = np.zeros_like(x)
    for mult, amp in ((1.0, 1.0), (2.0, 0.55), (3.0, 0.38), (4.0, 0.2), (5.0, 0.12)):
        out += amp * np.sin(2 * np.pi * freq * mult * x)
    attack = np.clip(x / 0.045, 0, 1)
    return out * attack * np.exp(-x * decay)


# --- spin loop -------------------------------------------------------------

def spin(dur=0.5):
    """Spin start: a gate swings, a low gong under it."""
    x = t(dur)
    out = air(dur, 140, 2) * np.clip(x / 0.22, 0, 1) ** 2 * np.exp(-np.clip(x - 0.22, 0, None) * 8) * 0.45
    out += sweep(dur, 150, 620, 1.5) * np.exp(-x * 3.6) * 0.3
    return place(out, bronze(A4, 0.4, decay=5.5, seed=3) * 0.75, 0.18)


def deal(dur=0.46):
    """Thirty symbols land: five stones walking down the scale, fast."""
    out = np.zeros(int(RATE * dur))
    for i, f in enumerate((A6, G6, E6, D6, C6)):
        place(out, gem(f, 0.11, decay=30, seed=10 + i) * (0.6 - 0.06 * i), 0.01 + i * 0.055)
    return out


def win(dur=0.32):
    """Fires once per paying symbol group, and groups overlap inside a cascade —
    so it stays short and consonant: a fifth on struck bronze."""
    out = np.zeros(int(RATE * dur))
    place(out, bronze(A6, 0.28, decay=11, seed=21) * 0.9, 0.0)
    place(out, bronze(E6, 0.24, decay=13, seed=22) * 0.5, 0.03)
    return out


def burst(dur=0.42):
    """Winning symbols shatter: a downward glide under thinning debris."""
    x = t(dur)
    return (sweep(dur, 1700, 240, 0.8) * np.exp(-x * 7.0) * 0.5
            + air(dur, 16, 5) * np.exp(-x * 9.0) * 0.45)


def tumble(dur=0.36):
    """Replacements fall into the gaps — three quick descending stone taps."""
    out = np.zeros(int(RATE * dur))
    for i, f in enumerate((E6, D6, C6)):
        place(out, gem(f, 0.12, decay=26, seed=30 + i) * (0.72 - 0.12 * i), 0.01 + i * 0.07)
    return out


# --- features --------------------------------------------------------------

def orb(dur=0.5):
    """A lightning orb lands: electric tremolo over a bright stone."""
    x = t(dur)
    trem = 1 + 0.35 * np.sin(2 * np.pi * 26 * x)
    elec = air(dur, 5, 41) * np.exp(-x * 6.5) * 0.55 * trem
    return place(elec, gem(C7, 0.2, decay=17, seed=42) * 0.6, 0.0)


def strike(dur=0.85):
    """Zeus throws the bolt and it hits the board. The loudest cue in the game."""
    x = t(dur)
    out = sweep(dur, 2600, 300, 0.55) * np.exp(-x * 9.0) * 0.5
    out += air(dur, 4, 51) * np.exp(-x * 13) * 0.6
    return place(out, thunder(0.7, seed=52, boom=48) * 0.95, 0.06)


def collect(dur=0.6):
    """Multipliers add up and fly to the meter: a rising minor arpeggio."""
    return arpeggio((A5, C6, E6, A6), dur, spacing=0.055, decay=5.2) * 0.55


def scatter(dur=0.55):
    """A Zeus scatter lands. Distinct from every other cue on purpose — four of
    these in one deal is the best thing that can happen in base play."""
    x = t(dur)
    out = air(dur, 7, 61) * np.exp(-x * 7) * 0.35
    return place(out, bronze(D6, 0.5, decay=4.0, seed=60) * 0.85, 0.0)


def bonus_transition(dur=1.8):
    """Into free spins: a storm gathers, then the gates open on a fanfare."""
    x = t(dur)
    out = air(dur, 500, 70) * np.clip(x / 0.7, 0, 1) * np.exp(-np.clip(x - 0.9, 0, None) * 2.4) * 0.55
    place(out, thunder(0.9, seed=71, boom=42) * 0.8, 0.55)
    place(out, arpeggio((A4, C5, E5, A5, C6, E6), 1.0, spacing=0.075, decay=2.6) * 0.4, 0.85)
    return out


def bonus_summary(dur=1.1):
    """The feature's total, settled."""
    return arpeggio((A5, E6, A6, C7), dur, spacing=0.1, decay=2.2) * 0.6


def retrigger(dur=0.6):
    """Five more spins."""
    return arpeggio((E6, G6, A6), dur, spacing=0.06, decay=4.5) * 0.6


# --- celebration -----------------------------------------------------------

def celebrate(notes, dur, thunder_at=None, seed=80):
    """Shared fanfare shape: horns over a thunder bed."""
    out = np.zeros(int(RATE * dur))
    for i, f in enumerate(notes):
        place(out, horn(f, dur - i * 0.09, decay=2.0) * (0.55 - 0.04 * i), i * 0.09)
    if thunder_at is not None:
        place(out, thunder(0.8, seed=seed, boom=45) * 0.55, thunder_at)
    return out


def celebrate_low(dur=1.1):
    return celebrate((A4, E5, A5), dur)


def celebrate_mid(dur=1.5):
    return celebrate((A4, C5, E5, A5), dur, thunder_at=0.05, seed=81)


def celebrate_high(dur=2.0):
    return celebrate((A4, C5, E5, A5, C6), dur, thunder_at=0.05, seed=82)


def celebrate_top(dur=2.6):
    out = celebrate((A4, C5, E5, A5, C6, E6), dur, thunder_at=0.04, seed=83)
    place(out, bronze(A4, 2.0, decay=1.4, seed=84) * 0.45, 0.0)
    return out


# --- ui --------------------------------------------------------------------

def click(dur=0.09):
    return gem(E6, dur, decay=48, seed=90) * 0.6


def error(dur=0.3):
    x = t(dur)
    return (np.sin(2 * np.pi * 155 * x) + 0.4 * np.sin(2 * np.pi * 118 * x)) * np.exp(-x * 9) * 0.6


CUES = {
    "olympus_spin.wav": spin,
    "olympus_deal.wav": deal,
    "olympus_win.wav": win,
    "olympus_burst.wav": burst,
    "olympus_tumble.wav": tumble,
    "olympus_orb.wav": orb,
    "olympus_strike.wav": strike,
    "olympus_collect.wav": collect,
    "olympus_scatter.wav": scatter,
    "olympus_bonus_transition.wav": bonus_transition,
    "olympus_bonus_summary.wav": bonus_summary,
    "olympus_retrigger.wav": retrigger,
    "olympus_celebrate_low.wav": celebrate_low,
    "olympus_celebrate_mid.wav": celebrate_mid,
    "olympus_celebrate_high.wav": celebrate_high,
    "olympus_celebrate_top.wav": celebrate_top,
    "olympus_click.wav": click,
    "olympus_error.wav": error,
}


if __name__ == "__main__":
    for name, fn in CUES.items():
        write(name, fn())
    print("\n%d cues written." % len(CUES))
