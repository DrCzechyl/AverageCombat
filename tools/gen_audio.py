"""Generates placeholder chiptune-ish SFX for Average Combat.

    .venv/bin/python tools/gen_audio.py

Pure stdlib (wave + math). Swap any of these WAVs for real recordings later;
scripts/autoload/sfx.gd just loads by filename.
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
RATE = 22050


def write_wav(name: str, samples) -> None:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        f.writeframes(bytes(frames))


def env(i: int, n: int, attack=0.005, decay=1.0, power=2.0) -> float:
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = max(0.0, 1.0 - (i / n) ** power)
    return a * d * decay


def square(t: float, freq: float) -> float:
    return 1.0 if (t * freq) % 1.0 < 0.5 else -1.0


def saw(t: float, freq: float) -> float:
    return 2.0 * ((t * freq) % 1.0) - 1.0


def noise(rng: random.Random) -> float:
    return rng.uniform(-1.0, 1.0)


def lowpass(samples, alpha=0.25):
    out = []
    prev = 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def hit_light():
    rng = random.Random(1)
    n = int(RATE * 0.14)
    out = []
    for i in range(n):
        t = i / RATE
        body = math.sin(math.tau * (150 - 70 * t) * t) * 0.7
        crack = noise(rng) * 0.45 * max(0.0, 1.0 - t / 0.045)
        out.append((body + crack) * env(i, n, 0.001, 1.0, 2.4) * 0.8)
    return out


def hit_heavy():
    rng = random.Random(2)
    n = int(RATE * 0.28)
    out = []
    for i in range(n):
        t = i / RATE
        body = math.sin(math.tau * (95 - 45 * t) * t) * 0.9
        crack = noise(rng) * 0.5 * max(0.0, 1.0 - t / 0.07)
        out.append((body + crack) * env(i, n, 0.001, 1.0, 2.0) * 0.9)
    return out


def block():
    rng = random.Random(3)
    n = int(RATE * 0.18)
    out = []
    for i in range(n):
        t = i / RATE
        click = square(t, 1400) * 0.25 * max(0.0, 1.0 - t / 0.05)
        metal = math.sin(math.tau * 720 * t) * 0.35
        air = noise(rng) * 0.2 * max(0.0, 1.0 - t / 0.08)
        out.append((click + metal + air) * env(i, n, 0.001, 1.0, 2.2) * 0.6)
    return out


def swing():
    rng = random.Random(4)
    n = int(RATE * 0.16)
    raw = [noise(rng) for _ in range(n)]
    filtered = lowpass(raw, 0.12)
    out = []
    for i in range(n):
        t = i / n
        out.append(filtered[i] * (0.5 + 0.5 * t) * env(i, n, 0.01, 1.0, 1.8) * 0.55)
    return out


def ko():
    rng = random.Random(5)
    n = int(RATE * 0.9)
    out = []
    for i in range(n):
        t = i / RATE
        p = i / n
        freq = 320 * (1.0 - p) + 60
        tone = saw(t, freq) * 0.35
        crash = noise(rng) * 0.25 * max(0.0, 1.0 - p * 2.0)
        out.append((tone + crash) * env(i, n, 0.005, 1.0, 1.6) * 0.9)
    return out


def round_start():
    n = int(RATE * 0.7)
    out = []
    for i in range(n):
        t = i / RATE
        f = 220 if i < n * 0.45 else 330
        tone = square(t, f) * 0.25 + math.sin(math.tau * f * 2 * t) * 0.2
        out.append(tone * env(i, n, 0.01, 1.0, 1.4) * 0.6)
    return out


def bell():
    n = int(RATE * 1.0)
    out = []
    for i in range(n):
        t = i / RATE
        s = (math.sin(math.tau * 880 * t) * 0.4 + math.sin(math.tau * 1320 * t) * 0.2
             + math.sin(math.tau * 1760 * t) * 0.1)
        out.append(s * env(i, n, 0.002, 1.0, 3.0) * 0.7)
    return out


def whoosh():
    rng = random.Random(6)
    n = int(RATE * 0.22)
    raw = [noise(rng) for _ in range(n)]
    filtered = lowpass(raw, 0.35)
    out = []
    for i in range(n):
        p = i / n
        out.append(filtered[i] * (0.15 + 0.85 * p) * env(i, n, 0.02, 1.0, 2.0) * 0.6)
    return out


def thud():
    n = int(RATE * 0.16)
    out = []
    for i in range(n):
        t = i / RATE
        out.append(math.sin(math.tau * (90 - 30 * t) * t) * env(i, n, 0.001, 1.0, 2.5) * 0.7)
    return out


def menu_move():
    n = int(RATE * 0.06)
    out = []
    for i in range(n):
        t = i / RATE
        out.append(square(t, 880) * env(i, n, 0.001, 1.0, 2.0) * 0.22)
    return out


def menu_confirm():
    n = int(RATE * 0.16)
    out = []
    for i in range(n):
        t = i / RATE
        f = 660 if i < n * 0.5 else 990
        out.append(square(t, f) * env(i, n, 0.001, 1.0, 1.6) * 0.25)
    return out


def menu_back():
    n = int(RATE * 0.14)
    out = []
    for i in range(n):
        t = i / RATE
        f = 440 if i < n * 0.5 else 300
        out.append(square(t, f) * env(i, n, 0.001, 1.0, 1.8) * 0.22)
    return out


def main():
    write_wav("hit_light.wav", hit_light())
    write_wav("hit_heavy.wav", hit_heavy())
    write_wav("block.wav", block())
    write_wav("swing.wav", swing())
    write_wav("ko.wav", ko())
    write_wav("round_start.wav", round_start())
    write_wav("bell.wav", bell())
    write_wav("projectile.wav", whoosh())
    write_wav("land.wav", thud())
    write_wav("menu_move.wav", menu_move())
    write_wav("menu_confirm.wav", menu_confirm())
    write_wav("menu_back.wav", menu_back())
    print("audio done ->", OUT)


if __name__ == "__main__":
    main()
