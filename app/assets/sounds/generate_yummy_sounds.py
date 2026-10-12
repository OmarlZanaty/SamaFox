"""Synthesises the يمي (YUMMY) sound effects.

Same approach as the other generate_*_sounds.py scripts: generated rather than
sourced, so the files stay small, license-free and reproducible.

    python generate_yummy_sounds.py

Consumed by app/lib/screens/games/yummy_sfx.dart.

Sound design brief: a sunny candy shop — marimba, glockenspiel and soft plucks,
all in C major so tumbles that stack several cues still agree with each other.
22.05 kHz mono keeps the whole set under a megabyte.
"""

import numpy as np
import wave

RATE = 22050
RNG = np.random.default_rng(7)

C4, D4, E4, F4, G4, A4, B4 = 261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88
C5, D5, E5, F5, G5, A5, B5 = 523.25, 587.33, 659.25, 698.46, 783.99, 880.00, 987.77
C6, E6, G6, C7 = 1046.50, 1318.51, 1567.98, 2093.00
C3, F3, G3, A3 = 130.81, 174.61, 196.00, 220.00


def write(name, samples, fade_ms=3, gain=0.85, loop=False):
    """Normalise, de-click the edges (not for loops) and write 16-bit mono."""
    x = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * gain
    n = int(RATE * fade_ms / 1000)
    if not loop and n > 0 and len(x) > 2 * n:
        ramp = np.linspace(0, 1, n)
        x[:n] *= ramp
        x[-n:] *= ramp[::-1]
    with wave.open(name, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype("<i2").tobytes())
    print("%-28s %5.2fs" % (name, len(x) / RATE))


def t(dur):
    return np.linspace(0, dur, int(RATE * dur), endpoint=False)


def place(base, sig, at):
    i = int(RATE * at)
    n = min(len(sig), len(base) - i)
    if n > 0:
        base[i:i + n] += sig[:n]
    return base


def env(dur, attack=0.004, decay=6.0):
    x = t(dur)
    return np.minimum(1, x / attack) * np.exp(-x * decay)


def marimba(freq, dur=0.5, decay=9.0):
    x = t(dur)
    tone = np.sin(2 * np.pi * freq * x) + 0.35 * np.sin(2 * np.pi * freq * 4 * x) * np.exp(-x * 30)
    return tone * env(dur, 0.002, decay)


def bell(freq, dur=1.0, decay=4.0):
    x = t(dur)
    partials = [(1, 1), (2.76, .45), (5.40, .25), (8.93, .12)]
    tone = sum(a * np.sin(2 * np.pi * freq * r * x) * np.exp(-x * decay * r ** .5) for r, a in partials)
    return tone * np.minimum(1, x / 0.002)


def pluck(freq, dur=0.3):
    x = t(dur)
    saw = 2 * ((freq * x) % 1) - 1
    # A soft low-pass by blending with the fundamental keeps it round.
    return (0.35 * saw + np.sin(2 * np.pi * freq * x)) * env(dur, 0.003, 11)


def noise(dur):
    return RNG.uniform(-1, 1, int(RATE * dur))


def lowpass(x, alpha):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def spin_loop():
    # 1.2 s loop: reel ticks at 15 Hz over a filtered whoosh. Every component
    # is periodic in 1.2 s so the loop point is seamless.
    dur = 1.2
    x = t(dur)
    out = np.zeros_like(x)
    tick = marimba(1800, 0.03, 120) * 0.5 + noise(0.03) * env(0.03, 0.001, 160) * 0.4
    for k in range(18):
        place(out, tick * (0.8 + 0.2 * (k % 3 == 0)), k / 15)
    whoosh = lowpass(noise(dur), 0.06) * (0.6 + 0.4 * np.sin(2 * np.pi * x / dur * 2) ** 2)
    hum = 0.25 * np.sin(2 * np.pi * 110 * x) + 0.1 * np.sin(2 * np.pi * 220 * x)
    out += whoosh * 1.4 + hum * 0.4
    return out


def reel_stop():
    x = t(0.16)
    thunk = np.sin(2 * np.pi * (180 - 80 * x / 0.16) * x) * env(0.16, 0.001, 30)
    click = noise(0.16) * env(0.16, 0.0005, 120) * 0.5
    return thunk + click + marimba(G5, 0.16, 26) * 0.35


def anticipation():
    dur = 1.6
    x = t(dur)
    freq = 500 + 900 * (x / dur) ** 1.5
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * (8 + 10 * x / dur) * x)
    tone = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * trem
    shimmer = sum(np.sin(2 * np.pi * f * x) for f in (C6, E6, G6)) * 0.15 * (x / dur)
    return (tone * 0.6 + shimmer) * np.minimum(1, x / 0.1) * np.minimum(1, (dur - x) / 0.1)


def tumble_pop():
    dur = 0.28
    x = t(dur)
    sweep = np.sin(2 * np.pi * np.cumsum(900 * np.exp(-x * 9) + 250) / RATE) * env(dur, 0.001, 14)
    fizz = lowpass(noise(dur), 0.35) * env(dur, 0.001, 25) * 0.6
    return sweep + fizz + marimba(E6, dur, 20) * 0.25


def win_small():
    out = np.zeros(int(RATE * 0.9))
    for i, f in enumerate((C5, E5, G5, C6)):
        place(out, marimba(f, 0.5), i * 0.07)
    place(out, bell(C6, 0.6, 5) * 0.4, 0.28)
    return out


def win_big():
    out = np.zeros(int(RATE * 2.4))
    seq = (C5, E5, G5, C6, E6, G6, C7)
    for i, f in enumerate(seq):
        place(out, marimba(f, 0.8) + bell(f, 0.8, 4) * 0.3, i * 0.075)
    for f in (C4, E4, G4, C5):
        place(out, pluck(f, 1.6) * 0.5, 0.55)
    place(out, bell(C6, 1.8, 2.2) * 0.6, 0.55)
    place(out, bell(G6, 1.6, 2.6) * 0.4, 0.75)
    return out


def coins():
    out = np.zeros(int(RATE * 1.1))
    for k in range(16):
        f = RNG.uniform(2600, 4200)
        place(out, bell(f, 0.25, 18) * RNG.uniform(.4, 1), k * 0.055 + RNG.uniform(0, .02))
    return out


def click():
    return marimba(C6, 0.06, 60) + noise(0.06) * env(0.06, 0.0005, 150) * 0.3


def fs_intro():
    dur = 1.8
    x = t(dur)
    gliss = np.sin(2 * np.pi * np.cumsum(300 + 1500 * (x / dur) ** 2) / RATE) * np.exp(-((x - .7) ** 2) * 6) * 0.4
    out = gliss.copy()
    for f in (C5, E5, G5, C6):
        place(out, bell(f, 1.1, 2.5) * 0.5, 0.8)
    for f in (C4, G4, E5):
        place(out, pluck(f, 1.0) * 0.5, 0.8)
    return out


def expand():
    out = np.zeros(int(RATE * 0.8))
    for i, f in enumerate((G5, A5, B5, C6, E6, G6, C7)):
        place(out, bell(f, 0.35, 9) * 0.6, i * 0.045)
    return out


def bonus_land():
    return bell(E6, 0.6, 5) + bell(G6, 0.6, 6) * 0.6 + marimba(C6, 0.6) * 0.5


def fs_music():
    # 8 s loop at 120 BPM: four bars of I–vi–IV–V with a bouncy pluck lead,
    # a marimba bass and a soft shaker. Notes are placed on an exact beat grid
    # inside the loop so the loop point lands on a downbeat.
    beat = 0.5
    dur = 16 * beat
    out = np.zeros(int(RATE * dur) + RATE)
    chords = [(C3, (C5, E5, G5)), (A3, (A4, C5, E5)), (F3, (F4, A4, C5)), (G3, (G4, B4, D5))]
    melody = [E5, G5, A5, G5, E5, D5, C5, D5, C5, E5, F5, E5, D5, B4, C5, D5]
    for bar, (root, triad) in enumerate(chords):
        start = bar * 4 * beat
        for b in range(4):
            place(out, marimba(root if b % 2 == 0 else root * 1.5, 0.45, 7) * 0.8, start + b * beat)
            place(out, sum(pluck(f, 0.22) for f in triad) * 0.18, start + b * beat + beat / 2)
    for i, f in enumerate(melody):
        place(out, marimba(f * 2, 0.35, 10) * 0.45, i * beat)
        if i % 2 == 1:
            place(out, bell(f * 2, 0.3, 10) * 0.12, i * beat + beat * 0.75)
    shaker = lowpass(noise(0.07), 0.6) * env(0.07, 0.002, 60) * 0.18
    for k in range(32):
        place(out, shaker * (1.0 if k % 2 else 0.6), k * beat / 2)
    # Fold the tail that ran past the loop point back onto the start.
    loop = out[:int(RATE * dur)].copy()
    tail = out[int(RATE * dur):]
    loop[:len(tail)] += tail
    return loop


if __name__ == "__main__":
    write("yummy_spin_loop.wav", spin_loop(), gain=0.5, loop=True)
    write("yummy_reel_stop.wav", reel_stop())
    write("yummy_anticipation.wav", anticipation(), gain=0.6)
    write("yummy_tumble_pop.wav", tumble_pop())
    write("yummy_win_small.wav", win_small())
    write("yummy_win_big.wav", win_big())
    write("yummy_coins.wav", coins(), gain=0.7)
    write("yummy_click.wav", click(), gain=0.6)
    write("yummy_fs_intro.wav", fs_intro())
    write("yummy_expand.wav", expand())
    write("yummy_bonus_land.wav", bonus_land(), gain=0.75)
    write("yummy_fs_music.wav", fs_music(), gain=0.55, loop=True)
