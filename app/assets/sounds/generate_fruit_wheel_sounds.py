"""Synthesises the عجلة الفواكه (FRUIT WHEEL) sound effects.

Same approach as the other generate_*_sounds.py scripts: generated rather than
sourced, so the files stay small, license-free and reproducible.

    python generate_fruit_wheel_sounds.py

Consumed by app/lib/screens/games/fruit_wheel_sfx.dart.

Sound design brief: a royal fairground wheel — wooden pointer ticks, a soft
rising whoosh, glockenspiel chimes in D major.
"""

import numpy as np
import wave

RATE = 22050
RNG = np.random.default_rng(11)

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


def click():
    x = t(0.06)
    return np.sin(2 * np.pi * 1400 * x) * env(0.06, 0.001, 70) + noise(0.06) * env(0.06, 0.0005, 200) * 0.3


def tick():
    x = t(0.035)
    knock = np.sin(2 * np.pi * (900 - 4000 * x) * x) * env(0.035, 0.0005, 110)
    return knock + noise(0.035) * env(0.035, 0.0003, 260) * 0.5


def spin_start():
    dur = 1.1
    x = t(dur)
    whoosh = lowpass(noise(dur), 0.03 + 0.12 * x / dur) * np.minimum(1, x / 0.25) * np.exp(-x * 1.2)
    rise = np.sin(2 * np.pi * np.cumsum(180 + 260 * x / dur) / RATE) * 0.25 * np.exp(-x * 2)
    return whoosh * 1.6 + rise


def stop():
    out = np.zeros(int(RATE * 0.9))
    place(out, bell(A5, 0.9, 4) * 0.8, 0)
    place(out, bell(D6, 0.8, 5) * 0.5, 0.05)
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
    x = t(1.4)
    shimmer = sum(np.sin(2 * np.pi * f * x) for f in (D6, FS6, A6)) * np.exp(-x * 2.2) * 0.25
    place(out, shimmer, 0.6)
    return out


def bonus():
    dur = 1.2
    x = t(dur)
    freq = 400 + 900 * (x / dur) ** 1.3
    sweep = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.minimum(1, x / 0.05) * np.minimum(1, (dur - x) / 0.2)
    out = sweep * 0.5
    for i, f in enumerate((A5, D6, FS6, A6)):
        place(out, bell(f, 0.5, 6) * 0.6, 0.55 + i * 0.12)
    return out


def orb():
    x = t(0.5)
    pop = np.sin(2 * np.pi * np.cumsum(300 + 1500 * np.exp(-x * 12)) / RATE) * env(0.5, 0.001, 9)
    return pop + bell(D7, 0.5, 8) * 0.4


if __name__ == "__main__":
    write("fruitwheel_click.wav", click())
    write("fruitwheel_tick.wav", tick(), fade_ms=1)
    write("fruitwheel_spin.wav", spin_start())
    write("fruitwheel_stop.wav", stop())
    write("fruitwheel_win.wav", win())
    write("fruitwheel_big_win.wav", big_win())
    write("fruitwheel_bonus.wav", bonus())
    write("fruitwheel_orb.wav", orb())
