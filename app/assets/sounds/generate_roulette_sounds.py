"""Synthesises the الروليت (ROULETTE) sound effects.

Same approach as the other generate_*_sounds.py scripts: generated rather than
sourced, so the files stay small, license-free and reproducible.

    python generate_roulette_sounds.py

Consumed by app/lib/screens/games/roulette_sfx.dart.

Sound design brief: a quiet casino table — clay chips, an ivory ball on a
wooden track, soft bells in D major.
"""

import numpy as np
import wave

RATE = 22050
RNG = np.random.default_rng(23)

D5, FS5, A5, B5 = 587.33, 739.99, 880.00, 987.77
D6, FS6, A6, D7 = 1174.66, 1479.98, 1760.00, 2349.32
D4, A4 = 293.66, 440.00


def write(name, samples, fade_ms=3, gain=0.85):
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
    print("%-30s %5.2fs" % (name, len(x) / RATE))


def t(dur):
    return np.linspace(0, dur, int(RATE * dur), endpoint=False)


def env(dur, attack, decay):
    x = t(dur)
    return np.minimum(1, x / attack) * np.exp(-x * decay)


def place(base, sig, at):
    i = int(at * RATE)
    end = min(len(base), i + len(sig))
    base[i:end] += sig[: end - i]


def bell(freq, dur=0.8, decay=5.0):
    x = t(dur)
    partials = [(1, 1), (2.76, .4), (5.40, .2)]
    tone = sum(a * np.sin(2 * np.pi * freq * r * x) * np.exp(-x * decay * r ** .5) for r, a in partials)
    return tone * np.minimum(1, x / 0.002)


def noise(dur):
    return RNG.uniform(-1, 1, int(RATE * dur))


def lowpass(x, alpha):
    # [alpha] may be a per-sample array, for a filter that opens over time.
    a = np.broadcast_to(alpha, np.shape(x))
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a[i] * (v - acc)
        y[i] = acc
    return y



def clack(dur=0.07, pitch=2400):
    x = t(dur)
    body = np.sin(2 * np.pi * pitch * x) * env(dur, 0.0005, 90) + np.sin(2 * np.pi * pitch * 1.6 * x) * env(dur, 0.0005, 140) * 0.5
    return body + noise(dur) * env(dur, 0.0003, 220) * 0.6


def chip():
    out = np.zeros(int(RATE * 0.16))
    place(out, clack(0.07, 2300), 0)
    place(out, clack(0.06, 2700) * 0.6, 0.045)
    return out


def click():
    return clack(0.05, 1500)


def lock():
    x = t(0.35)
    thud = np.sin(2 * np.pi * (140 - 60 * x) * x) * env(0.35, 0.002, 12)
    return thud + bell(A4, 0.35, 9) * 0.25


def tick():
    return clack(0.03, 3200) * 0.8


def spin():
    # The ball rolling on the wooden track: filtered noise with a slow rumble.
    dur = 2.4
    x = t(dur)
    roll = lowpass(noise(dur), 0.08) * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * x))
    rumble = np.sin(2 * np.pi * 70 * x) * 0.3
    return (roll * 1.8 + rumble) * np.minimum(1, x / 0.2) * np.minimum(1, (dur - x) / 0.6)


def stop():
    out = np.zeros(int(RATE * 0.8))
    for i, (at, p) in enumerate([(0, 2600), (0.09, 2200), (0.16, 2900), (0.21, 2400), (0.25, 2700)]):
        place(out, clack(0.05, p) * (1 - i * 0.15), at)
    place(out, bell(D6, 0.5, 7) * 0.3, 0.3)
    return out


def win():
    out = np.zeros(int(RATE * 1.1))
    for i, f in enumerate((D6, FS6, A6)):
        place(out, bell(f, 0.7, 5), i * 0.12)
    return out


def big_win():
    out = np.zeros(int(RATE * 2.0))
    for i, f in enumerate((D5, FS5, A5, D6, FS6, A6, D7)):
        place(out, bell(f, 0.9, 4) * (0.6 + 0.06 * i), i * 0.09)
    for k in range(10):
        place(out, chip() * 0.4, 0.6 + k * 0.07)
    return out


def clear():
    out = np.zeros(int(RATE * 0.5))
    for k in range(6):
        place(out, clack(0.05, 2000 + 150 * k) * (0.9 - k * 0.1), k * 0.05)
    return out


if __name__ == "__main__":
    for name, fn in [("chip", chip), ("click", click), ("lock", lock), ("tick", tick), ("spin", spin),
                     ("stop", stop), ("win", win), ("big_win", big_win), ("clear", clear)]:
        write("roulette_%s.wav" % name, fn(), fade_ms=1 if name in ("tick", "click") else 3)
