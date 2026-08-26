"""Synthesises the بلينكو (Plinko) sound effects.

Same approach as generate_crash_sounds.py: generated rather than sourced, so the
assets stay small, license-free and reproducible. Run from this directory:

    python generate_plinko_sounds.py

Consumed by app/lib/screens/games/plinko_screen.dart.
"""

import numpy as np
import wave

RATE = 44100


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
    print("%-26s %5.3fs" % (name, len(x) / RATE))


def t(dur):
    return np.linspace(0, dur, int(RATE * dur), endpoint=False)


def peg_tick(freq=2400, dur=0.055):
    """A short marimba-ish click for a ball striking a peg.

    This one fires up to sixteen times per drop and several drops overlap during
    auto-bet, so it has to be soft, brief, and pitched high enough to cut through
    without ever becoming a rattle.
    """
    x = t(dur)
    env = np.exp(-x * 95)
    body = np.sin(2 * np.pi * freq * x) * env
    # A touch of inharmonic partial gives it a struck-metal edge.
    body += 0.35 * np.sin(2 * np.pi * freq * 2.76 * x) * np.exp(-x * 150)
    # Tiny noise transient for the contact itself.
    noise = np.random.default_rng(7).normal(0, 1, len(x)) * np.exp(-x * 700) * 0.25
    return body * 0.8 + noise


def land_low(dur=0.35):
    """Neutral soft thud — the ball landed under 1x."""
    x = t(dur)
    env = np.exp(-x * 14)
    tone = np.sin(2 * np.pi * (200 - 70 * x / dur) * x) * env
    thud = np.random.default_rng(11).normal(0, 1, len(x)) * np.exp(-x * 55) * 0.3
    return tone + thud


def land_win(dur=0.75):
    """Bright chime for a paying slot: a major triad with a shimmer tail."""
    x = t(dur)
    env = np.exp(-x * 5.0)
    out = np.zeros_like(x)
    for i, f in enumerate((784.0, 988.0, 1175.0, 1568.0)):  # G5 B5 D6 G6
        delay = i * 0.045
        d = np.clip(x - delay, 0, None)
        voice = np.sin(2 * np.pi * f * d) * np.exp(-d * 5.5)
        voice[x < delay] = 0
        out += voice * (0.9 - 0.13 * i)
    shimmer = np.sin(2 * np.pi * 3136 * x) * np.exp(-x * 11) * 0.16
    return (out + shimmer) * env


def land_big(dur=1.5):
    """Celebration for 10x and above: rising arpeggio, then a sparkle wash."""
    x = t(dur)
    out = np.zeros_like(x)
    notes = (523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0)
    for i, f in enumerate(notes):
        delay = i * 0.075
        d = np.clip(x - delay, 0, None)
        voice = np.sin(2 * np.pi * f * d) + 0.3 * np.sin(4 * np.pi * f * d)
        voice *= np.exp(-d * 3.4)
        voice[x < delay] = 0
        out += voice

    rng = np.random.default_rng(3)
    sparkle = rng.normal(0, 1, len(x))
    # Band-limit the noise into a shimmer rather than a hiss.
    sparkle = np.convolve(sparkle, np.hanning(24), mode="same")
    sparkle *= np.exp(-np.clip(x - 0.25, 0, None) * 3.0) * 0.22
    sparkle[x < 0.25] = 0
    return out * 0.5 + sparkle


def ui_click(dur=0.045):
    """Small dry click for buttons and toggles."""
    x = t(dur)
    env = np.exp(-x * 160)
    return (np.sin(2 * np.pi * 1250 * x) + 0.4 * np.sin(2 * np.pi * 2500 * x)) * env


def drop_whoosh(dur=0.22):
    """Air movement as the ball is released."""
    x = t(dur)
    rng = np.random.default_rng(5)
    noise = rng.normal(0, 1, len(x))
    noise = np.convolve(noise, np.hanning(64), mode="same")
    env = np.sin(np.pi * x / dur) ** 1.5
    return noise * env


if __name__ == "__main__":
    # Three pitches of tick, picked per row so a descent sounds like a descent
    # instead of the same sample sixteen times.
    write("plinko_peg_1.wav", peg_tick(2600))
    write("plinko_peg_2.wav", peg_tick(2200))
    write("plinko_peg_3.wav", peg_tick(1850))
    write("plinko_land_low.wav", land_low())
    write("plinko_land_win.wav", land_win())
    write("plinko_land_big.wav", land_big())
    write("plinko_click.wav", ui_click())
    write("plinko_drop.wav", drop_whoosh())
