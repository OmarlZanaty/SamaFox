"""Synthesises the القط الجشع (Greedy Cat) sound effects.

Same approach as generate_plinko_sounds.py: generated rather than sourced, so the
assets stay small, license-free and reproducible. Run from this directory:

    python generate_greedy_sounds.py

Consumed by app/lib/screens/games/greedy_cat_sfx.dart.

The kit is deliberately warm and wooden — marimba, plucked strings, a soft
carnival bell — to match the food-fair art direction. Nothing here uses the
bright casino-metal timbre the other wager games lean on.
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
    print("%-28s %5.3fs" % (name, len(x) / RATE))


def t(dur):
    return np.linspace(0, dur, int(RATE * dur), endpoint=False)


def marimba(freq, dur, decay=13.0, seed=3):
    """A struck wooden bar: strong fundamental, quick inharmonic partials."""
    x = t(dur)
    env = np.exp(-x * decay)
    body = np.sin(2 * np.pi * freq * x) * env
    body += 0.30 * np.sin(2 * np.pi * freq * 3.9 * x) * np.exp(-x * decay * 2.4)
    body += 0.12 * np.sin(2 * np.pi * freq * 9.2 * x) * np.exp(-x * decay * 4.0)
    mallet = np.random.default_rng(seed).normal(0, 1, len(x)) * np.exp(-x * 480) * 0.18
    return body + mallet


def click(dur=0.07):
    """Denomination tile tap — a small wooden knock, felt more than heard."""
    return marimba(1180, dur, decay=70, seed=5) * 0.85


def coin_pop(dur=0.26):
    """A coin landing on a food card: a bright two-note pop with a gold ring."""
    x = t(dur)
    a = marimba(1568, dur, decay=22, seed=9)
    b = np.sin(2 * np.pi * 2350 * x) * np.exp(-x * 30) * 0.4
    shimmer = np.sin(2 * np.pi * 3136 * x) * np.exp(-x * 46) * 0.22
    return a + b + shimmer


def tick(dur=0.09):
    """Final-five-seconds countdown tick. Dry and wooden so it reads as urgency
    rather than alarm."""
    x = t(dur)
    body = marimba(880, dur, decay=58, seed=13)
    knock = np.random.default_rng(17).normal(0, 1, len(x)) * np.exp(-x * 620) * 0.3
    return body + knock


def segment_tick(dur=0.045):
    """Fires once per food card as the highlight sweeps past it during the spin,
    so it must be very short and very quiet — it plays eight times a second at
    the top of the spin."""
    x = t(dur)
    return np.sin(2 * np.pi * 2050 * x) * np.exp(-x * 130) * 0.7


def spin(dur=6.0):
    """The wheel itself: a wooden ratchet whose rate follows the same ease-out
    the animation uses, so the audio decelerates with the picture."""
    x = t(dur)
    # Matches Curves.easeOutQuart on the client: position = 1-(1-t)^4.
    u = x / dur
    position = 1 - (1 - u) ** 4
    # 34 clicks over the spin, spaced by that easing.
    phase = position * 34.0
    frac = phase - np.floor(phase)
    # Each click is a sharp attack decaying across its own slot.
    clicks = np.exp(-frac * 26) * np.sin(2 * np.pi * 1450 * x)
    clicks += 0.4 * np.exp(-frac * 40) * np.sin(2 * np.pi * 2600 * x)
    # A low wooden rumble that fades as the wheel slows.
    rumble = np.sin(2 * np.pi * 62 * x) * (1 - position) * 0.35
    rumble += np.random.default_rng(23).normal(0, 1, len(x)) * (1 - position) * 0.06
    return clicks * 0.55 + rumble


def result_chime(dur=0.9):
    """Neutral 'the wheel has stopped' bell, before win or loss is known."""
    out = np.zeros(int(RATE * dur))
    for i, f in enumerate([784, 1047]):
        seg = marimba(f, dur, decay=6.5, seed=29 + i)
        out += seg * (1.0 if i == 0 else 0.6)
    return out


def win_fanfare(dur=1.5):
    """Rising major arpeggio with a shimmer tail. Cheerful, not triumphal —
    this fires on ordinary 5x wins many times an hour."""
    out = np.zeros(int(RATE * dur))
    notes = [(523, 0.00), (659, 0.09), (784, 0.18), (1047, 0.27)]
    for i, (freq, start) in enumerate(notes):
        seg = marimba(freq, dur - start, decay=4.2, seed=31 + i)
        offset = int(RATE * start)
        out[offset:offset + len(seg)] += seg * (0.75 + 0.25 * (i == len(notes) - 1))
    x = t(dur)
    out += np.sin(2 * np.pi * 2093 * x) * np.exp(-x * 3.4) * 0.16
    return out


def lose_tone(dur=0.55):
    """Soft descending third. Never a buzzer — the player is told the round
    ended, not that they did something wrong."""
    out = np.zeros(int(RATE * dur))
    for i, (freq, start) in enumerate([(440, 0.0), (349, 0.13)]):
        seg = marimba(freq, dur - start, decay=7.0, seed=41 + i)
        offset = int(RATE * start)
        out[offset:offset + len(seg)] += seg * 0.7
    return out


def sparkle(dur=1.0):
    """Jackpot milestone: a fast upward run of bells."""
    out = np.zeros(int(RATE * dur))
    for i, freq in enumerate([1047, 1319, 1568, 2093, 2637]):
        start = i * 0.055
        seg = marimba(freq, dur - start, decay=9.0, seed=53 + i)
        offset = int(RATE * start)
        out[offset:offset + len(seg)] += seg * (0.9 - i * 0.1)
    return out


def modal(dur=0.22, up=True):
    """Panel open/close — a short wooden slide."""
    x = t(dur)
    f0, f1 = (520, 940) if up else (940, 520)
    freq = f0 + (f1 - f0) * (x / dur)
    return np.sin(2 * np.pi * freq * x) * np.exp(-x * 16) * 0.8


def meow(dur=0.5):
    """The cat, used sparingly — once per winning result at most."""
    x = t(dur)
    u = x / dur
    # A vowel-ish glide: fundamental bends up then down, with two formants.
    f0 = 620 + 240 * np.sin(np.pi * u)
    phase = 2 * np.pi * np.cumsum(f0) / RATE
    body = np.sin(phase)
    body += 0.45 * np.sin(2 * phase)
    body += 0.22 * np.sin(3 * phase)
    env = np.sin(np.pi * u) ** 1.4
    return body * env


def write_loop(name, samples, gain=0.62):
    """Write a seamlessly-looping WAV — no edge fades, which would click.

    `write` ramps the first and last few milliseconds to zero to de-click
    one-shots. That is exactly wrong for a loop: the ramp becomes an audible
    dip every time the track wraps. Instead the caller folds the reverb tail
    back over the head (see `theme`), so the join is already continuous.
    """
    x = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * gain
    with wave.open(name, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype("<i2").tobytes())
    print("%-28s %5.3fs  (loop)" % (name, len(x) / RATE))


# ── Background music ────────────────────────────────────────
# 8 bars of 4/4 at 120 BPM = 16 s. Cheerful carnival: marimba arpeggios over a
# I-vi-IV-V turnaround, a plucked bass and a soft shaker. No vocals, nothing
# above ~2.6 kHz, and mixed to sit under the effects rather than compete.
BPM = 120.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
LOOP = BAR * 8

# I - vi - IV - V, twice.
PROGRESSION = [
    (261.63, [261.63, 329.63, 392.00]),   # C
    (220.00, [220.00, 261.63, 329.63]),   # Am
    (174.61, [174.61, 220.00, 261.63]),   # F
    (196.00, [196.00, 246.94, 293.66]),   # G
] * 2


def _place(buf, seg, start_s):
    i = int(RATE * start_s)
    n = min(len(seg), len(buf) - i)
    if n > 0:
        buf[i:i + n] += seg[:n]


def pluck(freq, dur, decay=6.0, seed=101):
    """Plucked-string bass: fundamental plus a soft second partial."""
    x = t(dur)
    env = np.exp(-x * decay)
    body = np.sin(2 * np.pi * freq * x) * env
    body += 0.28 * np.sin(2 * np.pi * freq * 2 * x) * np.exp(-x * decay * 1.8)
    return body


def shaker(dur=0.09, seed=7):
    """High-passed noise burst, very quiet — this plays 128 times per loop."""
    x = t(dur)
    noise = np.random.default_rng(seed).normal(0, 1, len(x))
    # Crude high-pass: subtract a running mean.
    k = 12
    smooth = np.convolve(noise, np.ones(k) / k, mode="same")
    return (noise - smooth) * np.exp(-x * 60)


def theme():
    # Render into a buffer with 2 s of headroom, then fold that tail back over
    # the start so decaying notes carry across the loop point seamlessly.
    tail = 2.0
    buf = np.zeros(int(RATE * (LOOP + tail)))

    for bar, (root, chord) in enumerate(PROGRESSION):
        bar_start = bar * BAR

        # Bass: root on beat 1, fifth-ish on beat 3.
        _place(buf, pluck(root / 2, 1.1, decay=4.5) * 0.55, bar_start)
        _place(buf, pluck(root / 2, 0.9, decay=5.5) * 0.38, bar_start + 2 * BEAT)

        # Marimba: eight 8th notes walking up and back down the chord.
        pattern = [0, 1, 2, 1, 2, 1, 0, 1]
        for step, degree in enumerate(pattern):
            freq = chord[degree] * 2
            # Lift the last bar's final note an octave to signal the turnaround.
            if bar == len(PROGRESSION) - 1 and step >= 6:
                freq *= 2
            vel = 0.5 if step % 2 == 0 else 0.32
            _place(buf, marimba(freq, 0.8, decay=9.0, seed=200 + step) * vel,
                   bar_start + step * (BEAT / 2))

        # Shaker on every 8th, accented on the offbeat.
        for step in range(8):
            vel = 0.05 if step % 2 == 0 else 0.085
            _place(buf, shaker(seed=300 + bar * 8 + step) * vel,
                   bar_start + step * (BEAT / 2))

        # Soft kick on 1 and 3.
        for beat in (0, 2):
            x = t(0.16)
            thump = np.sin(2 * np.pi * (95 - 45 * x / 0.16) * x) * np.exp(-x * 26)
            _place(buf, thump * 0.30, bar_start + beat * BEAT)

    n = int(RATE * LOOP)
    head = buf[:n].copy()
    overhang = buf[n:]
    head[:len(overhang)] += overhang
    return head


if __name__ == "__main__":
    write("greedy_click.wav", click())
    write("greedy_coin.wav", coin_pop())
    write("greedy_tick.wav", tick())
    write("greedy_segment.wav", segment_tick())
    write("greedy_spin.wav", spin())
    write("greedy_result.wav", result_chime())
    write("greedy_win.wav", win_fanfare())
    write("greedy_lose.wav", lose_tone())
    write("greedy_milestone.wav", sparkle())
    write("greedy_modal_open.wav", modal(up=True))
    write("greedy_modal_close.wav", modal(up=False))
    write("greedy_meow.wav", meow())
    write_loop("greedy_theme.wav", theme())
