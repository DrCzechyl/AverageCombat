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


def armor():
    """Crisp metallic clang + low thump (~0.24s) for super-armor absorption."""
    rng = random.Random(10)
    n = int(RATE * 0.24)
    raw = [noise(rng) for _ in range(n)]
    burst = lowpass(raw, 0.45)
    out = []
    for i in range(n):
        t = i / RATE
        p = i / n
        # Low punchy absorption thump
        thump_freq = 115.0 - 65.0 * min(1.0, t / 0.08)
        thump = math.sin(math.tau * thump_freq * t) * 0.55 * max(0.0, 1.0 - t / 0.11) ** 1.6
        # Crisp inharmonic metallic clang partials
        ring_env = math.exp(-t * 14.0)
        clang = (
            math.sin(math.tau * 640.0 * t) * 0.34
            + math.sin(math.tau * 972.0 * t) * 0.26
            + math.sin(math.tau * 1510.0 * t) * 0.20 * math.exp(-t * 8.0)
            + math.sin(math.tau * 2240.0 * t) * 0.14 * math.exp(-t * 18.0)
        ) * ring_env
        # Short metallic impact transient
        spark = burst[i] * 0.40 * max(0.0, 1.0 - t / 0.028)
        sample = (thump + clang + spark) * env(i, n, 0.001, 1.0, 2.2) * 0.85
        out.append(sample)
    return out


def throw_sfx():
    """Punchy grab/shove thud + cloth snap (~0.26s)."""
    rng = random.Random(11)
    n = int(RATE * 0.26)
    raw = [noise(rng) for _ in range(n)]
    lp_hi = lowpass(raw, 0.48)
    lp_lo = lowpass(raw, 0.12)
    cloth_band = [lp_hi[i] - lp_lo[i] for i in range(n)]
    out = []
    for i in range(n):
        t = i / RATE
        # Phase 1: quick cloth grab + tight clinch bump (0.00 - 0.09s)
        grab_env = math.exp(-((t - 0.022) / 0.022) ** 2)
        grab_cloth = cloth_band[i] * 0.55 * grab_env
        grab_bump = math.sin(math.tau * (135.0 - 40.0 * t) * t) * 0.32 * max(0.0, 1.0 - t / 0.075)
        # Phase 2: heavier shove release thud + crisp cloth snap (0.075 - 0.26s)
        ts = max(0.0, t - 0.072)
        shove_active = 1.0 if t >= 0.072 else 0.0
        shove_thud = (
            math.sin(math.tau * (112.0 - 58.0 * min(1.0, ts / 0.14)) * ts)
            * 0.78
            * math.exp(-ts * 16.0)
            * shove_active
        )
        snap_env = math.exp(-((t - 0.088) / 0.018) ** 2)
        cloth_snap = cloth_band[i] * 0.72 * snap_env
        sample = (grab_cloth + grab_bump + shove_thud + cloth_snap) * env(i, n, 0.002, 1.0, 2.4) * 0.9
        out.append(sample)
    return out


def tech_sfx():
    """Bright resonant clash chord (~0.22s) for throw tech escapes."""
    rng = random.Random(12)
    n = int(RATE * 0.22)
    out = []
    for i in range(n):
        t = i / RATE
        # Bright shimmering fifth + octave + ninth clash chord
        decay_fast = math.exp(-t * 16.0)
        decay_slow = math.exp(-t * 10.5)
        chord = (
            math.sin(math.tau * 880.0 * t) * 0.30 * decay_slow
            + math.sin(math.tau * 1320.0 * t) * 0.28 * decay_slow
            + math.sin(math.tau * 1760.0 * t) * 0.24 * decay_fast
            + math.sin(math.tau * 2200.0 * t) * 0.18 * decay_fast
            + math.sin(math.tau * 2640.0 * t) * 0.12 * math.exp(-t * 22.0)
        )
        # Crisp metallic chime click at onset
        sparkle = (square(t, 1980.0) * 0.14 + noise(rng) * 0.18) * max(0.0, 1.0 - t / 0.022)
        sample = (chord + sparkle) * env(i, n, 0.001, 1.0, 2.2) * 0.8
        out.append(sample)
    return out


def _seamless_crossfade(raw, n: int, overlap: int):
    """Wrap raw[n : n + overlap] seamlessly into raw[0 : overlap] with cosine crossfade."""
    out = list(raw[:n])
    for i in range(overlap):
        w = 0.5 * (1.0 - math.cos(math.pi * i / overlap))
        out[i] = raw[i] * w + raw[n + i] * (1.0 - w)
    return out


def _normalize_ambience(samples, target_peak: float = 0.10):
    """Remove DC offset and scale cleanly to target_peak (<= 0.12)."""
    if not samples:
        return samples
    mean = sum(samples) / len(samples)
    centered = [s - mean for s in samples]
    peak = max(abs(s) for s in centered) or 1.0
    scale = min(target_peak, 0.115) / peak
    return [s * scale for s in centered]


def ambience_breakroom():
    """2.0s seamless loopable soft fluorescent 60/120Hz hum + gentle room tone."""
    rng = random.Random(101)
    n = RATE * 2
    overlap = int(RATE * 0.25)
    raw_noise = [noise(rng) for _ in range(n + overlap)]
    room_lp = lowpass(lowpass(raw_noise, 0.06), 0.10)
    room_tone = _seamless_crossfade(room_lp, n, overlap)

    out = []
    for i in range(n):
        t = i / RATE
        # Exact integer cycles over 2.0s so phase matches at t=0 and t=2.0
        drift = 1.0 + 0.06 * math.sin(math.tau * 0.5 * t)
        hum = (
            math.sin(math.tau * 60.0 * t) * 0.22
            + math.sin(math.tau * 120.0 * t) * 0.42
            + math.sin(math.tau * 240.0 * t) * 0.14
            + math.sin(math.tau * 360.0 * t) * 0.05
        ) * drift
        out.append(hum * 0.55 + room_tone[i] * 0.95)
    return _normalize_ambience(out, target_peak=0.095)


def ambience_parkinglot():
    """2.0s seamless loopable soft dusk air + subtle rhythmic cricket chirp."""
    rng = random.Random(102)
    n = RATE * 2
    overlap = int(RATE * 0.25)
    raw_noise = [noise(rng) for _ in range(n + overlap)]
    air_lp = lowpass(lowpass(raw_noise, 0.08), 0.12)
    dusk_air = _seamless_crossfade(air_lp, n, overlap)

    # Two subtle cricket chirp phrases well inside the 2.0s loop
    chirp_centers = (0.45, 1.45)
    out = []
    for i in range(n):
        t = i / RATE
        breeze_mod = 0.85 + 0.15 * math.sin(math.tau * 0.5 * t)
        air = dusk_air[i] * breeze_mod * 1.15

        cricket = 0.0
        for c0 in chirp_centers:
            # 3 gentle pulses per chirp phrase
            for p_idx in range(3):
                pt = t - (c0 + p_idx * 0.048)
                if -0.022 <= pt <= 0.022:
                    pulse_env = 0.5 * (1.0 + math.cos(math.pi * pt / 0.022))
                    cricket += (
                        math.sin(math.tau * 4180.0 * t) * 0.65
                        + math.sin(math.tau * 4320.0 * t) * 0.35
                    ) * pulse_env * 0.11

        out.append(air + cricket)
    return _normalize_ambience(out, target_peak=0.10)


def ambience_backyard():
    """2.0s seamless loopable gentle warm grill crackle/sizzle + soft breeze."""
    rng = random.Random(103)
    n = RATE * 2
    overlap = int(RATE * 0.25)
    total = n + overlap

    raw_breeze = [noise(rng) for _ in range(total)]
    breeze_lp = lowpass(lowpass(raw_breeze, 0.09), 0.14)

    raw_sizzle = [noise(rng) for _ in range(total)]
    sizzle_lp_lo = lowpass(raw_sizzle, 0.22)
    sizzle_lp_hi = lowpass(raw_sizzle, 0.65)
    sizzle = [sizzle_lp_hi[i] - sizzle_lp_lo[i] for i in range(total)]

    # Sparse gentle charcoal crackles
    crackle = [0.0] * total
    for _ in range(22):
        start = rng.randrange(0, total - 120)
        amp = rng.uniform(0.18, 0.42)
        dur = rng.randrange(45, 110)
        for k in range(dur):
            decay = math.exp(-k / (dur * 0.25))
            crackle[start + k] += noise(rng) * amp * decay

    combined = []
    for i in range(total):
        t = i / RATE
        breeze_mod = 0.82 + 0.18 * math.sin(math.tau * 0.5 * t)
        combined.append(breeze_lp[i] * breeze_mod * 1.1 + sizzle[i] * 0.28 + crackle[i] * 0.42)

    looped = _seamless_crossfade(combined, n, overlap)
    return _normalize_ambience(looped, target_peak=0.105)


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
    write_wav("armor.wav", armor())
    write_wav("throw.wav", throw_sfx())
    write_wav("tech.wav", tech_sfx())
    write_wav("ambience_breakroom.wav", ambience_breakroom())
    write_wav("ambience_parkinglot.wav", ambience_parkinglot())
    write_wav("ambience_backyard.wav", ambience_backyard())
    print("audio done ->", OUT)


if __name__ == "__main__":
    main()
