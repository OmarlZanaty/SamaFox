"""Synthesises the gift sound effects.

Same approach as generate_plinko_sounds.py: generated rather than sourced, so the
assets stay small, license-free and reproducible. Run from this directory:

    python generate_gift_sounds.py

Consumed by app/lib/gifts/widgets/gift_animation_overlay.dart.

  gift_send.wav  — short sparkle chime, plays for EVERY gift for everyone in
                   the room, fired off the broadcast socket event.
  vip_gift.wav   — longer fanfare for LEGENDARY-tier gifts (the overlay used to
                   reference a vip_gift.mp3 that was never shipped, so the VIP
                   sound silently failed on every device).
"""

import numpy as np
import wave

RATE = 44100


def write(name, samples, fade_ms=4, gain=0.89):
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
        f.writeframes((x * 32767).astype(np.int16).tobytes())
    print("wrote", name, f"({len(x) / RATE:.2f}s)")


def tone(freq, dur, decay=6.0, shimmer=0.0):
    """A decaying sine with a touch of second harmonic for sparkle."""
    t = np.linspace(0, dur, int(RATE * dur), endpoint=False)
    env = np.exp(-decay * t)
    x = np.sin(2 * np.pi * freq * t)
    x += 0.35 * np.sin(2 * np.pi * freq * 2 * t)
    if shimmer:
        x += shimmer * np.sin(2 * np.pi * freq * 3.01 * t)
    return x * env


def place(buf, start_s, chunk):
    """Mix `chunk` into `buf` at `start_s` seconds."""
    i = int(RATE * start_s)
    end = min(len(buf), i + len(chunk))
    buf[i:end] += chunk[: end - i]


def gift_send():
    """~0.6s rising three-note sparkle. Deliberately short so a x50 send does
    not turn into noise, and so it lands well inside one second on every phone."""
    total = 0.62
    buf = np.zeros(int(RATE * total))
    for i, freq in enumerate((1046.5, 1396.9, 2093.0)):  # C6, F6, C7
        place(buf, i * 0.075, tone(freq, total - i * 0.075, decay=9.0, shimmer=0.18))
    return buf


def vip_gift():
    """~1.6s fanfare for LEGENDARY gifts: a rising major arpeggio that opens
    out into a sustained chord."""
    total = 1.6
    buf = np.zeros(int(RATE * total))
    arpeggio = (523.25, 659.25, 783.99, 1046.5)  # C5 E5 G5 C6
    for i, freq in enumerate(arpeggio):
        start = i * 0.11
        place(buf, start, tone(freq, total - start, decay=3.4, shimmer=0.22) * 0.8)
    # Sustained chord landing on the last arpeggio note.
    for freq in (523.25, 659.25, 783.99, 1046.5, 1318.5):
        place(buf, 0.44, tone(freq, total - 0.44, decay=2.1) * 0.45)
    return buf


if __name__ == "__main__":
    write("gift_send.wav", gift_send())
    write("vip_gift.wav", vip_gift())
