"""Synthesises the crash game (طيّار) sound effects.

The assets are generated rather than sourced so they stay small, license-free
and reproducible. Run from this directory:

    python generate_crash_sounds.py

Consumed by app/lib/screens/games/crash_game_screen.dart.
"""

import math
import wave

import numpy as np

RATE = 44100


def write(name, samples, fade_ms=4):
    """Normalise, de-click the edges and write a 16-bit mono WAV."""
    x = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * 0.89

    # A hard start/end edge on any sample reads as a click.
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
    print("%-22s %5.2fs" % (name, len(x) / RATE))


def periodic_noise(n, seed, tilt=1.0):
    """Noise that loops perfectly: built in the frequency domain, so the last
    sample flows back into the first. `tilt` > 0 darkens it (1/f^tilt)."""
    rng = np.random.default_rng(seed)
    spectrum = np.zeros(n // 2 + 1, dtype=complex)
    freqs = np.arange(len(spectrum))
    mag = np.ones(len(spectrum))
    mag[1:] = 1.0 / freqs[1:] ** tilt
    phase = rng.uniform(0, 2 * math.pi, len(spectrum))
    spectrum = mag * np.exp(1j * phase)
    spectrum[0] = 0
    return np.fft.irfft(spectrum, n)


def one_pole_lowpass(x, cutoff_hz):
    """Time-varying one-pole low pass; `cutoff_hz` may be an array."""
    cutoff = np.broadcast_to(np.asarray(cutoff_hz, dtype=np.float64), x.shape)
    a = 1.0 - np.exp(-2.0 * math.pi * cutoff / RATE)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y += a[i] * (x[i] - y)
        out[i] = y
    return out


def bell(t, freq, decay, harmonics=(1.0, 2.01, 3.03), gains=(1.0, 0.42, 0.18)):
    """A struck-metal partial stack with an exponential decay."""
    out = np.zeros_like(t)
    for ratio, gain in zip(harmonics, gains):
        out += gain * np.sin(2 * math.pi * freq * ratio * t)
    return out * np.exp(-decay * t)


# ── crash_engine.wav ─────────────────────────────────────────
# Looping propeller. The screen raises playback rate and volume with the
# multiplier, so this is deliberately flat and mid-low: a steady drone with the
# blade-pass throb on top. Every frequency is a multiple of 1/duration so the
# loop point is seamless.
def engine(duration=2.0, fundamental=90.0, blade_hz=25.0):
    n = int(RATE * duration)
    t = np.arange(n) / RATE

    tone = np.zeros(n)
    for h in range(1, 13):  # sawtooth-ish, engine-like buzz
        tone += np.sin(2 * math.pi * fundamental * h * t) / h

    # The propeller "chop" — amplitude modulation at the blade-pass rate.
    blade = 1.0 + 0.55 * np.sin(2 * math.pi * blade_hz * t)
    rumble = 0.5 * periodic_noise(n, seed=11, tilt=1.6)

    return (tone * 0.55 + rumble) * blade


# ── crash_cashout.wav ────────────────────────────────────────
# Bright rising three-note flourish — unmistakably "you won".
def cashout(duration=0.75):
    n = int(RATE * duration)
    out = np.zeros(n)
    for i, freq in enumerate((784.0, 1046.5, 1568.0)):  # G5 C6 G6
        start = int(RATE * 0.075 * i)
        seg = np.arange(n - start) / RATE
        out[start:] += bell(seg, freq, decay=7.0) * (0.85 ** i)
    return out


# ── crash_whoosh.wav ─────────────────────────────────────────
# The plane leaving: noise swelling then tearing away, with the filter opening
# up and slamming shut.
def whoosh(duration=0.7):
    n = int(RATE * duration)
    t = np.arange(n) / RATE
    p = t / duration

    noise = periodic_noise(n, seed=5, tilt=0.35)
    cutoff = 400 + 6000 * np.sin(np.pi * p) ** 0.7  # open then close
    body = one_pole_lowpass(noise, cutoff)

    # Fast swell, abrupt cut — the plane is gone, not fading.
    env = np.sin(np.pi * p) ** 1.4 * np.exp(-2.2 * p)
    return body * env


# ── crash_bet.wav ────────────────────────────────────────────
# Tiny confirmation click.
def bet_click(duration=0.07):
    n = int(RATE * duration)
    t = np.arange(n) / RATE
    click = np.sin(2 * math.pi * 1750 * t) + 0.5 * np.sin(2 * math.pi * 2600 * t)
    return click * np.exp(-55 * t)


# ── crash_rain.wav ───────────────────────────────────────────
# Soft pentatonic chime for the Rain drop — gentle, not a win fanfare.
def rain(duration=1.3):
    n = int(RATE * duration)
    out = np.zeros(n)
    for i, freq in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):  # C6 E6 G6 C7
        start = int(RATE * 0.09 * i)
        seg = np.arange(n - start) / RATE
        out[start:] += bell(seg, freq, decay=3.6, gains=(1.0, 0.3, 0.1)) * (0.8 ** i)
    return out * 0.8


if __name__ == "__main__":
    write("crash_engine.wav", engine(), fade_ms=0)  # fades would break the loop
    write("crash_cashout.wav", cashout())
    write("crash_whoosh.wav", whoosh())
    write("crash_bet.wav", bet_click(), fade_ms=1)
    write("crash_rain.wav", rain())
