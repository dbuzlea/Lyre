#!/usr/bin/env python3
"""Synthesises placeholder sound effects for the Gramophone player.

These stand in for the sounds with no recording yet: the needle lifting, the crank's
ratchet and the spring wound. The rest are cut from recordings by
prepare_gramophone_sounds.sh; when a recording comes for one of these, cut it there and
take it out of here. Each is built from two ingredients:

  * clicks: very short bursts of noise, one part striking another;
  * modes: decaying sine partials, the ring of the part that was struck.

Run from anywhere:

    python3 Lyre/Scripts/make_gramophone_sounds.py

It writes 44.1 kHz mono 16-bit WAVs into Lyre/Lyre/Sounds, which the app bundles and
plays as system sounds. Standard library only.
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Lyre", "Sounds")

random.seed(1906)


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(into, sound, at=0.0, gain=1.0):
    start = int(at * RATE)
    if len(into) < start + len(sound):
        into.extend([0.0] * (start + len(sound) - len(into)))
    for i, s in enumerate(sound):
        into[start + i] += s * gain
    return into


def click(length=0.004, brightness=0.6, gain=1.0):
    """A hard contact: noise with a fast decay, thinned by `brightness`."""
    n = int(length * RATE)
    out, prev = [], 0.0
    for i in range(n):
        x = random.uniform(-1, 1)
        y = x - brightness * prev
        prev = x
        out.append(y * math.exp(-6.0 * i / max(n, 1)) * gain)
    return out


def modes(partials, length):
    """Struck resonances: [(frequency, level, decay seconds)]."""
    n = int(length * RATE)
    out = [0.0] * n
    for freq, level, decay in partials:
        phase = random.uniform(0, 2 * math.pi)
        for i in range(n):
            t = i / RATE
            out[i] += level * math.exp(-t / decay) * math.sin(2 * math.pi * freq * t + phase)
    fade = max(1, n // 5)
    for i in range(fade):
        out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade)
    return out


def hiss(length, high=0.35, low=0.05, level=1.0, envelope=None):
    """Band-limited noise, the sound of a groove under the needle."""
    n = int(length * RATE)
    out, lp_hi, lp_lo = [], 0.0, 0.0
    for i in range(n):
        x = random.uniform(-1, 1)
        lp_hi += high * (x - lp_hi)
        lp_lo += low * (x - lp_lo)
        e = envelope(i / n) if envelope else 1.0
        out.append((lp_hi - lp_lo) * e * level)
    return out


def finish(sound, peak=0.85, tail=0.006, head=0.0):
    top = max(abs(s) for s in sound) or 1.0
    out = [s / top * peak for s in sound]
    fade = int(tail * RATE)
    for i in range(min(fade, len(out))):
        out[-1 - i] *= i / fade
    lead = int(head * RATE)
    for i in range(min(lead, len(out))):
        out[i] *= i / lead
    return out


def write(name, sound):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in sound))
    print(f"{path}  {len(sound) / RATE * 1000:.0f} ms")


# The needle lifted: a short scrape off the groove and the arm's light knock on its rest.
def needle_lift():
    s = silence(0.22)
    mix(s, hiss(0.06, high=0.6, low=0.2, envelope=lambda t: 1 - t), 0.0, 0.5)
    mix(s, click(0.002, 0.9), 0.0, 0.6)
    mix(s, modes([(900, 0.4, 0.02), (2300, 0.2, 0.008), (180, 0.3, 0.03)], 0.12), 0.09)
    mix(s, click(0.003, 0.7), 0.09, 0.5)
    return finish(s, 0.55)


# One tooth of the crank's ratchet: the pawl snapping over it, a bright metal tick.
def ratchet():
    s = silence(0.08)
    mix(s, click(0.0015, 0.95), 0.0, 1.0)
    mix(s, modes([(2900, 0.5, 0.012), (5200, 0.3, 0.006), (1300, 0.3, 0.015)], 0.07), 0.0003)
    return finish(s, 0.5)


# The spring fully wound: a heavier clunk and the spring's ring.
def wound():
    s = silence(0.5)
    mix(s, click(0.004, 0.6), 0.0, 1.0)
    mix(s, modes([(160, 0.9, 0.05), (480, 0.5, 0.03), (1240, 0.3, 0.02)], 0.2), 0.0)
    mix(s, modes([(1460, 0.18, 0.15), (1510, 0.14, 0.14), (2920, 0.05, 0.06)], 0.45), 0.01)
    return finish(s, 0.75)


if __name__ == "__main__":
    for name, make in [
        ("gramophone_needle_lift", needle_lift),
        ("gramophone_ratchet", ratchet),
        ("gramophone_wound", wound),
    ]:
        write(name, make())
