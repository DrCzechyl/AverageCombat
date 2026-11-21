"""Drawing helpers shared by the asset generators.

Includes:
- High-resolution graphic-novel illustration primitives (tapered anatomical
  limbs, directional 3-tone painterly shading, unified tinted-ink silhouette
  contours, clipped detail passes) used by the 2x-supersampled fighter & FX
  renderer.
- Legacy 1x pixel-art helpers kept for optional --stages / icon generation.
"""

from __future__ import annotations

import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# Color & Painterly Illustration Helpers
# ---------------------------------------------------------------------------


def rgba(color, alpha: int = 255) -> tuple[int, int, int, int]:
    return (int(color[0]), int(color[1]), int(color[2]), int(alpha))


def mix_color(c1, c2, t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (
        int(round(c1[0] + (c2[0] - c1[0]) * t)),
        int(round(c1[1] + (c2[1] - c1[1]) * t)),
        int(round(c1[2] + (c2[2] - c1[2]) * t)),
    )


def shift_tone(color, factor: float, warm: float = 0.0) -> tuple[int, int, int]:
    """Scale brightness with subtle warm/cool hue shift (natural painterly shading).

    Positive `warm` warms highlights; negative `warm` cools shadows.
    """
    r = color[0] * factor + warm * 14.0
    g = color[1] * factor + warm * 5.0
    b = color[2] * factor - warm * 12.0
    return (
        max(0, min(255, int(round(r)))),
        max(0, min(255, int(round(g)))),
        max(0, min(255, int(round(b)))),
    )


def lerp_pt(p0, p1, t: float) -> tuple[float, float]:
    return (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)


def rot_pt(pt, origin, angle_rad: float) -> tuple[float, float]:
    ca = math.cos(angle_rad)
    sa = math.sin(angle_rad)
    dx = pt[0] - origin[0]
    dy = pt[1] - origin[1]
    return (origin[0] + dx * ca - dy * sa, origin[1] + dx * sa + dy * ca)


def tapered_limb_polygon(
    p0: tuple[float, float],
    p1: tuple[float, float],
    r0: float,
    r1: float,
    bulge_pos: float = 0.36,
    bulge_front: float = 0.14,
    bulge_back: float = 0.10,
    steps: int = 8,
    cap_start: float = 0.72,
    cap_end: float = 0.65,
) -> list[tuple[float, float]]:
    """Build an anatomically tapered muscular/clothed limb polygon from p0 to p1.

    Uses smooth sinusoidal muscle/cloth fullness along the front (+normal) and
    back (-normal) profiles and rounded anatomical end caps so adjoining
    segments fuse seamlessly with zero cartoon capsule rings.
    """
    dx = p1[0] - p0[0]
    dy = p1[1] - p0[1]
    length = math.hypot(dx, dy)
    if length < 1e-3:
        length = 1.0
        ux, uy = 0.0, 1.0
    else:
        ux, uy = dx / length, dy / length
    # Perpendicular normal (pointing roughly "front" / right-of-axis)
    nx, ny = -uy, ux

    front_pts: list[tuple[float, float]] = []
    back_pts: list[tuple[float, float]] = []

    for i in range(steps + 1):
        t = i / steps
        cx = p0[0] + dx * t
        cy = p0[1] + dy * t
        base_r = r0 + (r1 - r0) * t
        # Smooth asymmetric bell curve centered at bulge_pos
        if t <= bulge_pos:
            u = t / max(1e-3, bulge_pos)
            bell = math.sin(u * math.pi * 0.5)
        else:
            u = (1.0 - t) / max(1e-3, 1.0 - bulge_pos)
            bell = math.sin(u * math.pi * 0.5)
        bell = bell * bell
        rf = base_r * (1.0 + bulge_front * bell)
        rb = base_r * (1.0 + bulge_back * bell)
        front_pts.append((cx + nx * rf, cy + ny * rf))
        back_pts.append((cx - nx * rb, cy - ny * rb))

    # Smooth rounded end cap at p1
    end_cap: list[tuple[float, float]] = []
    if cap_end > 0.0:
        for k in (1, 2, 3):
            ang = k * math.pi / 4.0
            ca = math.cos(ang)
            sa = math.sin(ang)
            ex = p1[0] + (nx * ca + ux * sa * cap_end) * r1
            ey = p1[1] + (ny * ca + uy * sa * cap_end) * r1
            end_cap.append((ex, ey))

    # Smooth rounded start cap at p0
    start_cap: list[tuple[float, float]] = []
    if cap_start > 0.0:
        for k in (1, 2, 3):
            ang = k * math.pi / 4.0
            ca = math.cos(ang)
            sa = math.sin(ang)
            sx = p0[0] + (-nx * ca - ux * sa * cap_start) * r0
            sy = p0[1] + (-ny * ca - uy * sa * cap_start) * r0
            start_cap.append((sx, sy))

    return front_pts + end_cap + list(reversed(back_pts)) + start_cap


def draw_clipped_overlay(base_img: Image.Image, draw_fn) -> None:
    """Run `draw_fn(draw)` on a temp RGBA image and composite strictly inside base_img's alpha."""
    overlay = Image.new("RGBA", base_img.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(overlay))
    base_a = base_img.getchannel("A")
    ov_a = overlay.getchannel("A")
    clipped_a = ImageChops.darker(base_a, ov_a)
    overlay.putalpha(clipped_a)
    base_img.alpha_composite(overlay)


def shade_and_ink_layer(
    layer: Image.Image,
    ink_color: tuple[int, int, int] = (24, 20, 22),
    shadow_tint: tuple[int, int, int] = (24, 28, 44),
    highlight_tint: tuple[int, int, int] = (255, 246, 232),
    rim_tint: tuple[int, int, int] = (232, 238, 248),
    shadow_strength: float = 0.36,
    highlight_strength: float = 0.22,
    rim_strength: float = 0.20,
    key_offset: tuple[int, int] = (7, 5),
    shadow_offset: tuple[int, int] = (-11, -7),
    ink_alpha: int = 235,
    ink_thick: bool = False,
) -> Image.Image:
    """Apply directional 3-tone painterly shading + unified tinted-ink silhouette contour.

    - Key light: warm-neutral from top-left (`key_offset`).
    - Core shadow: cool-tinted on bottom-right (`shadow_offset`), soft + graphic edge.
    - Rim highlight: subtle catchlight on the leading (+x) silhouette edge.
    - Silhouette contour: smooth anti-aliased tinted-ink outline ONLY around the
      unified outer alpha silhouette (zero internal joint rings!).
    """
    bbox = layer.getbbox()
    if bbox is None:
        return layer

    # Pad bbox for filter margin & ink dilation so we only process the active region
    pad = 16
    w, h = layer.size
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(w, bbox[2] + pad)
    y1 = min(h, bbox[3] + pad)
    crop = layer.crop((x0, y0, x1, y1))
    cw, ch = crop.size
    alpha = crop.getchannel("A")

    # 1. Core shadow band (bottom-right)
    if shadow_strength > 0.0:
        sh_shift = ImageChops.offset(alpha, shadow_offset[0], shadow_offset[1])
        # Soft form shadow + crisp cel edge blend
        raw_sh = ImageChops.subtract(alpha, sh_shift)
        soft_sh = raw_sh.filter(ImageFilter.GaussianBlur(2.2))
        combined_sh = ImageChops.lighter(
            raw_sh.point(lambda v: int(v * 0.65)),
            soft_sh,
        )
        sh_mask = ImageChops.darker(combined_sh, alpha).point(
            lambda v: int(v * shadow_strength)
        )
        sh_img = Image.new("RGBA", (cw, ch), (shadow_tint[0], shadow_tint[1], shadow_tint[2], 255))
        sh_img.putalpha(sh_mask)
        crop.alpha_composite(sh_img)

    # 2. Key-light highlight band (top-left)
    if highlight_strength > 0.0:
        hi_shift = ImageChops.offset(alpha, key_offset[0], key_offset[1])
        raw_hi = ImageChops.subtract(alpha, hi_shift)
        soft_hi = raw_hi.filter(ImageFilter.GaussianBlur(1.4))
        hi_mask = ImageChops.darker(soft_hi, alpha).point(
            lambda v: int(v * highlight_strength)
        )
        hi_img = Image.new(
            "RGBA", (cw, ch), (highlight_tint[0], highlight_tint[1], highlight_tint[2], 255)
        )
        hi_img.putalpha(hi_mask)
        crop.alpha_composite(hi_img)

    # 3. Subtle leading-edge (+x) rim light
    if rim_strength > 0.0:
        rim_shift = ImageChops.offset(alpha, -3, 1)
        raw_rim = ImageChops.subtract(alpha, rim_shift)
        rim_mask = ImageChops.darker(raw_rim, alpha).point(
            lambda v: int(v * rim_strength)
        )
        rim_img = Image.new("RGBA", (cw, ch), (rim_tint[0], rim_tint[1], rim_tint[2], 255))
        rim_img.putalpha(rim_mask)
        crop.alpha_composite(rim_img)

    # 4. Unified tinted dark-ink silhouette contour (1.2-1.6px at 2x -> crisp 0.7-0.9px at 1x)
    dilated_1 = alpha.filter(ImageFilter.MaxFilter(3))
    if ink_thick:
        dilated_2 = alpha.filter(ImageFilter.MaxFilter(5))
        contour_a = ImageChops.lighter(
            dilated_1,
            dilated_2.point(lambda v: int(v * 0.55)),
        )
    else:
        contour_a = dilated_1.filter(ImageFilter.GaussianBlur(0.55)).point(
            lambda v: min(255, int(v * 1.9))
        )
    contour_a = contour_a.point(lambda v: int(v * ink_alpha / 255))

    ink_img = Image.new("RGBA", (cw, ch), (ink_color[0], ink_color[1], ink_color[2], 255))
    ink_img.putalpha(contour_a)
    ink_img.alpha_composite(crop)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(ink_img, (x0, y0))
    return out


def darken_layer(layer: Image.Image, factor: float = 0.90) -> Image.Image:
    """Slightly darken RGB channels (preserving alpha) for rear-depth limb separation."""
    bbox = layer.getbbox()
    if bbox is None:
        return layer
    r, g, b, a = layer.split()
    lut = [max(0, min(255, int(i * factor))) for i in range(256)]
    # Slight cool depth tint on rear limbs
    lut_b = [max(0, min(255, int(i * min(1.0, factor + 0.03)))) for i in range(256)]
    return Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut_b), a))


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
# Legacy Shapes (used by optional --stages / icon generation)
# ---------------------------------------------------------------------------


def disc(draw, cx, cy, r, fill) -> None:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def capsule(draw, p1, p2, fill, width, outline=None, outline_w=2) -> None:
    """A thick round-capped line."""
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
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    out = []
    for x, y in points:
        dx, dy = x - cx, y - cy
        length = math.hypot(dx, dy) or 1.0
        out.append((x - dx / length * amount, y - dy / length * amount))
    return out


def dither_gradient(img: Image.Image, box, top, bottom, pattern=4):
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


def color_bands(draw: ImageDraw.ImageDraw, box, colors) -> None:
    x0, y0, x1, y1 = box
    n = len(colors)
    if n == 0 or y1 <= y0 or x1 <= x0:
        return
    h = y1 - y0
    for i, col in enumerate(colors):
        by0 = y0 + (h * i) // n
        by1 = y0 + (h * (i + 1)) // n
        if by1 > by0:
            draw.rectangle([x0, by0, x1 - 1, by1 - 1], fill=col)


def stepped_glow(img: Image.Image, center, radius, color, rings=3, max_alpha=40) -> None:
    if radius <= 0 or rings <= 0:
        return
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    cx, cy = int(center[0]), int(center[1])
    for i in range(rings, 0, -1):
        r = max(1, int(round(radius * i / rings)))
        a = int(round(max_alpha * (1.0 - (i - 1) / rings) * 0.65 + max_alpha * 0.25))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(color[0], color[1], color[2], a))
    img.alpha_composite(overlay)
