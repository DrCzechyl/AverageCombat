"""Tiny pixel-art drawing helpers shared by the asset generators.

Everything is drawn at 1x into small PNGs; the game scales sprites up with
nearest-neighbour filtering, so honesty at this resolution matters.
"""

from __future__ import annotations

import math
import random

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# A hand-built 5x7 bitmap font so in-world signage stays crisp at 1x.
# ---------------------------------------------------------------------------

GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ",": ["00000", "00000", "00000", "00000", "00110", "00110", "01100"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    "&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
    "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
}

FONT_CHAR_W = 5
FONT_CHAR_H = 7
FONT_TRACKING = 1


def text_width(text: str, scale: int = 1) -> int:
    if not text:
        return 0
    return (len(text) * (FONT_CHAR_W + FONT_TRACKING) - FONT_TRACKING) * scale


def draw_text(draw: ImageDraw.ImageDraw, text: str, x: int, y: int, color, scale: int = 1,
              shadow=None) -> None:
    """Draw uppercase pixel text with an optional 1px (scaled) drop shadow."""
    text = text.upper()
    if shadow is not None:
        draw_text(draw, text, x + scale, y + scale, shadow, scale)
    cx = x
    for ch in text:
        glyph = GLYPHS.get(ch, GLYPHS[" "])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    draw.rectangle(
                        [cx + gx * scale, y + gy * scale,
                         cx + (gx + 1) * scale - 1, y + (gy + 1) * scale - 1],
                        fill=color,
                    )
        cx += (FONT_CHAR_W + FONT_TRACKING) * scale


def text_sprite(text: str, color, scale: int = 1, shadow=None, pad: int = 0) -> Image.Image:
    w = text_width(text, scale) + pad * 2
    h = FONT_CHAR_H * scale + pad * 2
    img = Image.new("RGBA", (max(1, w), max(1, h)), (0, 0, 0, 0))
    draw_text(ImageDraw.Draw(img), text, pad, pad, color, scale, shadow)
    return img


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------


def disc(draw, cx, cy, r, fill) -> None:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def capsule(draw, p1, p2, fill, width, outline=None, outline_w=2) -> None:
    """A thick round-capped line - the workhorse for limbs."""
    if outline is not None:
        capsule(draw, p1, p2, outline, width + outline_w, None)
    draw.line([p1, p2], fill=fill, width=max(1, width))
    r = max(1, width // 2)
    disc(draw, int(p1[0]), int(p1[1]), r, fill)
    disc(draw, int(p2[0]), int(p2[1]), r, fill)


def poly(draw, points, fill, outline=None):
    if outline is not None:
        draw.polygon(points, fill=outline)
        inner = _shrink_polygon(points, 1.0)
        draw.polygon(inner, fill=fill)
    else:
        draw.polygon(points, fill=fill)


def _shrink_polygon(points, amount):
    """Rough inward offset: move each point toward the centroid."""
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    out = []
    for x, y in points:
        dx, dy = x - cx, y - cy
        length = math.hypot(dx, dy) or 1.0
        out.append((x - dx / length * amount, y - dy / length * amount))
    return out


def dither_gradient(img: Image.Image, box, top, bottom, pattern=4):
    """Bayer-ish dithered vertical gradient, clipped to box = (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = box
    px = img.load()
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    h = max(1, y1 - y0)
    for y in range(y0, y1):
        t = (y - y0) / h
        for x in range(x0, x1):
            threshold = (bayer[y % 4][x % 4] + 0.5) / 16.0
            use_bottom = t > threshold
            c = bottom if use_bottom else top
            px[x, y] = (c[0], c[1], c[2], 255 if len(c) == 3 else c[3])


def speckle(img: Image.Image, box, color, count=200, seed=7, alpha_min=20, alpha_max=70):
    """Add subtle noise inside a box to fight flat banding."""
    rng = random.Random(seed)
    x0, y0, x1, y1 = box
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for _ in range(count):
        x = rng.randrange(x0, x1)
        y = rng.randrange(y0, y1)
        a = rng.randrange(alpha_min, alpha_max)
        d.point((x, y), fill=(color[0], color[1], color[2], a))
    img.alpha_composite(overlay)


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color[:3])


def checker(draw, box, c1, c2, size=16, offset=0):
    x0, y0, x1, y1 = box
    for y in range(y0, y1, size):
        for x in range(x0, x1, size):
            color = c1 if ((x // size + y // size + offset) % 2 == 0) else c2
            draw.rectangle([x, y, min(x + size, x1) - 1, min(y + size, y1) - 1], fill=color)


def outline_rect(draw, box, fill, line, width=1):
    draw.rectangle(box, fill=fill, outline=line, width=width)


def glow(img: Image.Image, center, radius, color, strength=1.0):
    """Additive-ish soft glow baked into the background."""
    if radius <= 0:
        return
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    steps = 10
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(10 * strength * (1.0 - i / steps) + 4)
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r],
                  fill=(color[0], color[1], color[2], a))
    img.alpha_composite(overlay)
