"""Generates all placeholder art for Average Combat.

Run from the repo root:
    .venv/bin/python tools/gen_art.py

Outputs:
    assets/sprites/fighters/<id>.png   (6 x 11 grid of 64x96 frames)
    assets/stages/<id>.png             (1280x720)
    assets/sprites/fx/*.png
    icon.png

The fighter sheet layout is the contract with scripts/data/character_db.gd.
If you redraw a fighter by hand, keep the same grid and row order.
"""

from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

from pixel_art import (
    capsule, checker, disc, dither_gradient, draw_text, glow, outline_rect,
    shade, speckle, text_width,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")

CELL_W, CELL_H = 64, 96
COLS = 6
GROUND_Y = 600.0

OUTLINE = (28, 24, 26, 255)

# ---------------------------------------------------------------------------
# Palettes
# ---------------------------------------------------------------------------

FIGHTERS = {
    "dave": {
        "label": "DAVE",
        "skin": (232, 186, 148),
        "skin_shade": (198, 148, 112),
        "hair": (88, 62, 44),
        "shirt": (222, 228, 236),
        "shirt_dark": (176, 186, 200),
        "pants": (172, 152, 112),
        "pants_dark": (140, 122, 88),
        "shoes": (72, 52, 40),
        "accent": (182, 54, 54),
        "accent2": (236, 236, 240),
        "bulk": 1.0,
        "style": "short",
        "sleeve": "long",
        "glasses": True,
        "prop": "box",
        "height": 0.0,
    },
    "karen": {
        "label": "KAREN",
        "skin": (238, 197, 166),
        "skin_shade": (204, 158, 126),
        "hair": (216, 186, 108),
        "shirt": (150, 96, 158),
        "shirt_dark": (112, 68, 122),
        "pants": (58, 56, 68),
        "pants_dark": (42, 40, 50),
        "shoes": (38, 34, 40),
        "accent": (216, 186, 108),
        "accent2": (240, 236, 226),
        "bulk": 0.94,
        "style": "bob",
        "sleeve": "long",
        "glasses": False,
        "prop": "clipboard",
        "height": -1.0,
    },
    "tony": {
        "label": "TONY",
        "skin": (214, 160, 122),
        "skin_shade": (176, 124, 92),
        "hair": (58, 48, 44),
        "shirt": (120, 96, 72),
        "shirt_dark": (90, 70, 52),
        "pants": (78, 82, 94),
        "pants_dark": (58, 60, 70),
        "shoes": (48, 42, 38),
        "accent": (196, 154, 78),
        "accent2": (206, 198, 176),
        "bulk": 1.2,
        "style": "bald",
        "sleeve": "rolled",
        "glasses": False,
        "prop": "plunger",
        "height": 1.0,
    },
    "chad": {
        "label": "CHAD",
        "skin": (226, 176, 138),
        "skin_shade": (192, 144, 110),
        "hair": (58, 46, 40),
        "shirt": (70, 122, 118),
        "shirt_dark": (50, 94, 92),
        "pants": (96, 106, 128),
        "pants_dark": (76, 84, 104),
        "shoes": (228, 228, 232),
        "accent": (238, 208, 92),
        "accent2": (88, 84, 80),
        "bulk": 0.9,
        "style": "cap",
        "sleeve": "long",
        "glasses": False,
        "prop": "laptop",
        "height": -1.0,
    },
}


def c(color, alpha=255):
    return (color[0], color[1], color[2], alpha)


def base_pose(pal) -> dict:
    bulk = pal["bulk"]
    h = pal["height"]
    shoulder = 8.6 * bulk
    hip = 5.4 * bulk
    return {
        "dy": h * 0.0,
        "lean": 0.0,
        "head": (33.0, 19.0 + h),
        "bs": (33.0 - shoulder, 33.0 + h),
        "fs": (33.0 + shoulder, 33.0 + h),
        "bh": (33.0 - hip, 57.0 + h),
        "fh": (33.0 + hip, 57.0 + h),
        "be": (33.0 - shoulder - 3.0, 44.0 + h),
        "bhand": (33.0 - shoulder - 4.0, 55.0 + h),
        "fe": (33.0 + shoulder + 3.0, 45.0 + h),
        "fhand": (33.0 + shoulder + 4.0, 56.0 + h),
        "bk": (33.0 - hip - 2.0, 72.0 + h),
        "bfoot": (33.0 - hip - 4.0, 91.0 + h),
        "fk": (33.0 + hip + 2.0, 73.0 + h),
        "ffoot": (33.0 + hip + 4.0, 91.0 + h),
        "prop": None,
        "prop_hand": "front",
        "legs_flip": False,
    }


def shift_body(p, dx=0.0, dy=0.0):
    for key in ("head", "bs", "fs", "bh", "fh", "be", "bhand", "fe", "fhand", "bk", "fk"):
        x, y = p[key]
        p[key] = (x + dx, y + dy)
    # feet follow only dx
    for key in ("bfoot", "ffoot"):
        x, y = p[key]
        p[key] = (x + dx, y)


def set_leg(p, side, foot, knee=None):
    hip = p["bh"] if side == "b" else p["fh"]
    if knee is None:
        knee = ((hip[0] + foot[0]) / 2.0 + 2.0, (hip[1] + foot[1]) / 2.0)
    p["bk" if side == "b" else "fk"] = knee
    p["bfoot" if side == "b" else "ffoot"] = foot


# ---------------------------------------------------------------------------
# Fighter rendering
# ---------------------------------------------------------------------------


def draw_head(d: ImageDraw.ImageDraw, p, pal):
    hx, hy = p["head"]
    r = 8.0
    style = pal["style"]
    hair = c(pal["hair"])
    skin = c(pal["skin"])
    outline = OUTLINE

    # Hair mass behind the head for bob styles
    if style == "bob":
        d.ellipse([hx - 10, hy - 10, hx + 9, hy + 12], fill=hair, outline=outline)
    elif style == "cap":
        pass

    # Face
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=skin, outline=outline)

    if style == "short":
        d.pieslice([hx - r - 1, hy - r - 2, hx + r + 1, hy + r], 180, 360, fill=hair)
        d.rectangle([hx - r - 1, hy - 4, hx - r + 1, hy + 2], fill=hair)
        d.rectangle([hx + r - 2, hy - 5, hx + r, hy - 1], fill=hair)
    elif style == "bob":
        d.pieslice([hx - 10, hy - 11, hx + 10, hy + 8], 180, 360, fill=hair)
        d.rectangle([hx - 10, hy - 4, hx - 6, hy + 10], fill=hair)
        d.rectangle([hx + 4, hy - 6, hx + 9, hy + 2], fill=hair)
    elif style == "bald":
        # bald crown + a beard that still leaves the face readable
        d.arc([hx - r, hy - r, hx + r, hy + r], 30, 150, fill=c(pal["skin_shade"]))
        d.pieslice([hx - r + 2, hy + 4, hx + r - 2, hy + r + 2], 0, 180, fill=hair)
        d.rectangle([hx - r + 2, hy + r - 3, hx + r - 2, hy + r], fill=hair)
        d.rectangle([hx + 5, hy - 2, hx + 8, hy], fill=shade(hair, 1.4))
    elif style == "cap":
        d.pieslice([hx - r - 1, hy - r - 3, hx + r + 1, hy + 4], 180, 360,
                   fill=c(pal["shirt_dark"]))
        d.rectangle([hx - r - 6, hy - 4, hx - r + 2, hy - 1], fill=c(pal["shirt_dark"]),
                    outline=OUTLINE)
        d.rectangle([hx - 1, hy - r - 3, hx + 1, hy - r - 1], fill=c(pal["accent"]))

    # Face details (facing right)
    d.point([(hx + 3, hy - 1), (hx + 6, hy - 1)], fill=OUTLINE)
    d.point([(hx + 7, hy + 2)], fill=c(pal["skin_shade"]))
    d.line([(hx + 3, hy + 4), (hx + 5, hy + 4)], fill=c(pal["skin_shade"]))
    # brow
    d.line([(hx + 2, hy - 3), (hx + 4, hy - 3)], fill=shade(pal["hair"], 0.9))
    d.line([(hx + 5, hy - 3), (hx + 7, hy - 3)], fill=shade(pal["hair"], 0.9))
    # ear
    d.rectangle([hx - r - 1, hy, hx - r, hy + 2], fill=c(pal["skin_shade"]))

    if pal.get("glasses"):
        d.rectangle([hx + 1, hy - 2, hx + 4, hy + 1], outline=OUTLINE)
        d.rectangle([hx + 6, hy - 2, hx + 9, hy + 1], outline=OUTLINE)
        d.line([(hx + 4, hy - 1), (hx + 6, hy - 1)], fill=OUTLINE)


def draw_prop(d: ImageDraw.ImageDraw, hand, kind, hide=False):
    if kind is None or hide:
        return
    hx, hy = hand
    if kind == "clipboard":
        outline_rect(d, [hx - 5, hy - 7, hx + 6, hy + 8], (222, 214, 196, 255), OUTLINE, 1)
        d.rectangle([hx - 3, hy - 8, hx + 4, hy - 6], fill=(96, 96, 104, 255), outline=OUTLINE)
        for i in range(3):
            d.line([(hx - 3, hy - 2 + i * 3), (hx + 4, hy - 2 + i * 3)], fill=(120, 118, 112, 255))
    elif kind == "plunger":
        d.line([(hx, hy + 2), (hx + 2, hy - 16)], fill=(120, 88, 54, 255), width=2)
        d.ellipse([hx - 3, hy - 24, hx + 8, hy - 14], fill=(188, 62, 56, 255), outline=OUTLINE)
    elif kind == "laptop":
        outline_rect(d, [hx - 5, hy - 12, hx + 7, hy - 1], (72, 76, 86, 255), OUTLINE, 1)
        d.rectangle([hx - 3, hy - 10, hx + 5, hy - 3], fill=(96, 158, 186, 255))
        d.rectangle([hx - 7, hy - 1, hx + 9, hy + 2], fill=(104, 108, 118, 255), outline=OUTLINE)
    elif kind == "box":
        outline_rect(d, [hx - 8, hy - 10, hx + 8, hy + 6], (168, 128, 84, 255), OUTLINE, 1)
        d.line([(hx - 8, hy - 10), (hx, hy - 16)], fill=OUTLINE)
        d.line([(hx + 8, hy - 10), (hx, hy - 16)], fill=OUTLINE)
        d.line([(hx, hy - 16), (hx, hy - 10)], fill=OUTLINE)
        d.rectangle([hx - 3, hy - 6, hx + 3, hy - 1], fill=(230, 226, 214, 255))


def draw_shoe(d, foot, pal, facing=1):
    x, y = foot
    d.ellipse([x - 5, y - 3, x + 7, y + 3], fill=c(pal["shoes"]), outline=OUTLINE)
    d.rectangle([x - 3, y - 2, x + 6, y + 1], fill=c(pal["shoes"]))
    d.line([(x - 4, y + 2), (x + 7, y + 2)], fill=shade(pal["shoes"], 0.7))


def draw_fighter_frame(pal, pose) -> Image.Image:
    img = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    skin = c(pal["skin"])
    shirt = c(pal["shirt"])
    shirt_d = c(pal["shirt_dark"])
    pants = c(pal["pants"])
    pants_d = c(pal["pants_dark"])
    sleeve = pal["sleeve"]

    p = pose

    # --- back arm -----------------------------------------------------------
    if sleeve == "long":
        capsule(d, p["bs"], p["be"], shirt_d, 6, OUTLINE, 2)
        capsule(d, p["be"], p["bhand"], shirt_d, 5, OUTLINE, 2)
    else:
        capsule(d, p["bs"], p["be"], shirt if sleeve == "short" else shirt_d, 6, OUTLINE, 2)
        capsule(d, p["be"], p["bhand"], skin, 5, OUTLINE, 2)
    disc(d, int(p["bhand"][0]), int(p["bhand"][1]), 3, skin)

    # --- back leg -----------------------------------------------------------
    capsule(d, p["bh"], p["bk"], pants_d, 8, OUTLINE, 2)
    capsule(d, p["bk"], p["bfoot"], pants_d, 7, OUTLINE, 2)
    draw_shoe(d, p["bfoot"], pal)

    # --- front leg ----------------------------------------------------------
    capsule(d, p["fh"], p["fk"], pants, 8, OUTLINE, 2)
    capsule(d, p["fk"], p["ffoot"], pants, 7, OUTLINE, 2)
    draw_shoe(d, p["ffoot"], pal)

    # --- torso --------------------------------------------------------------
    torso = [
        (p["bs"][0] - 3.5, p["bs"][1] - 2),
        (p["fs"][0] + 3.5, p["fs"][1] - 2),
        (p["fh"][0] + 3.0, p["fh"][1] + 2),
        (p["bh"][0] - 3.0, p["bh"][1] + 2),
    ]
    d.polygon(torso, fill=shirt, outline=OUTLINE)
    # neck
    d.rectangle([p["head"][0] - 2, p["head"][1] + 7, p["head"][0] + 2, p["bs"][1] + 1],
                fill=c(pal["skin_shade"]))
    # belt
    d.rectangle([p["bh"][0] - 3, p["bh"][1] - 1, p["fh"][0] + 3, p["bh"][1] + 2],
                fill=shade(pal["pants"], 0.55))

    # --- character-specific torso details -----------------------------------
    if pal["prop"] == "box" or pal["label"] == "DAVE":
        # tie
        d.polygon([(p["head"][0] - 2, p["bs"][1] + 1), (p["head"][0] + 2, p["bs"][1] + 1),
                   (p["head"][0] + 1, p["bh"][1] - 1), (p["head"][0] - 1, p["bh"][1] - 1)],
                  fill=c(pal["accent"]))
        d.line([(p["head"][0] - 2, p["bs"][1] + 1), (p["head"][0] + 2, p["bs"][1] + 1)],
               fill=OUTLINE)
        d.line([(p["bs"][0], p["bs"][1] + 4), (p["bh"][0] + 1, p["bh"][1] - 2)], fill=shirt_d)
    elif pal["label"] == "KAREN":
        # cardigan opening + blouse
        d.line([(p["head"][0], p["bs"][1] + 2), (p["head"][0], p["bh"][1] - 1)],
               fill=shirt_d, width=2)
        d.polygon([(p["head"][0] + 1, p["bs"][1] + 2),
                   (p["head"][0] + 5, p["bs"][1] + 2),
                   (p["head"][0] + 4, p["bh"][1] - 1),
                   (p["head"][0] + 1, p["bh"][1] - 1)], fill=c(pal["accent2"]))
    elif pal["label"] == "TONY":
        # work jacket zip + collar
        d.line([(p["head"][0], p["bs"][1] + 1), (p["head"][0], p["bh"][1] - 1)],
               fill=shade(pal["shirt"], 0.7), width=2)
        d.polygon([(p["bs"][0] - 1, p["bs"][1] - 1), (p["head"][0] - 1, p["bs"][1] + 4),
                   (p["head"][0] + 2, p["bs"][1] + 5)], fill=shade(pal["shirt"], 1.15))
        d.rectangle([p["head"][0] + 1, p["bh"][1] - 8, p["head"][0] + 4, p["bh"][1] - 6],
                    fill=c(pal["accent"]))
    elif pal["label"] == "CHAD":
        # hoodie pocket + drawstrings
        d.polygon([(p["head"][0] - 6, p["bh"][1] - 7), (p["head"][0] + 7, p["bh"][1] - 7),
                   (p["head"][0] + 5, p["bh"][1] - 2), (p["head"][0] - 4, p["bh"][1] - 2)],
                  fill=shirt_d)
        d.line([(p["head"][0] - 2, p["bs"][1] + 2), (p["head"][0] - 3, p["bs"][1] + 9)],
               fill=c(pal["accent2"]))
        d.line([(p["head"][0] + 2, p["bs"][1] + 2), (p["head"][0] + 3, p["bs"][1] + 9)],
               fill=c(pal["accent2"]))

    # --- head ---------------------------------------------------------------
    draw_head(d, p, pal)

    # --- front arm ----------------------------------------------------------
    if sleeve == "long":
        capsule(d, p["fs"], p["fe"], shirt, 6, OUTLINE, 2)
        capsule(d, p["fe"], p["fhand"], shirt, 5, OUTLINE, 2)
    else:
        capsule(d, p["fs"], p["fe"], shirt, 6, OUTLINE, 2)
        capsule(d, p["fe"], p["fhand"], skin, 5, OUTLINE, 2)
    disc(d, int(p["fhand"][0]), int(p["fhand"][1]), 3, skin)

    # --- prop ---------------------------------------------------------------
    hand = p["bhand"] if p.get("prop_hand") == "back" else p["fhand"]
    draw_prop(d, hand, p.get("prop"), p.get("hide_prop", False))
    return img


# ---------------------------------------------------------------------------
# Poses per animation frame
# ---------------------------------------------------------------------------


def guard_pose(pal):
    p = base_pose(pal)
    p["be"] = (p["bs"][0] + 4, p["bs"][1] + 10)
    p["bhand"] = (p["head"][0] + 1, p["head"][1] + 8)
    p["fe"] = (p["fs"][0] + 2, p["fs"][1] + 10)
    p["fhand"] = (p["head"][0] + 7, p["head"][1] + 9)
    p["lean"] = -1.0
    return p


def idle_frames(pal):
    frames = []
    for i in range(4):
        p = base_pose(pal)
        bob = [0, 0, 1, 1][i]
        sway = [0, 1, 1, 0][i]
        shift_body(p, 0, bob)
        p["bhand"] = (p["bhand"][0] - sway, p["bhand"][1])
        p["fhand"] = (p["fhand"][0] + sway * 0.5, p["fhand"][1])
        p["be"] = (p["be"][0] - sway * 0.5, p["be"][1])
        p["fe"] = (p["fe"][0] + sway * 0.5, p["fe"][1])
        frames.append(p)
    return frames


def walk_frames(pal):
    frames = []
    for i in range(6):
        p = base_pose(pal)
        phase = i / 6.0
        for side, ph in (("b", phase), ("f", (phase + 0.5) % 1.0)):
            swing = math.sin(ph * math.tau)
            lift = max(0.0, math.cos(ph * math.tau)) * 9.0
            hip = p["bh"] if side == "b" else p["fh"]
            foot = (hip[0] + swing * 9.0, 91.0 - lift)
            knee = ((hip[0] + foot[0]) / 2.0 + 3.0, (hip[1] + foot[1]) / 2.0
                    - (2.0 if lift > 3 else 0.0))
            set_leg(p, side, foot, knee)
        bob = -1.0 if i in (1, 4) else 0.0
        shift_body(p, 0, bob * 0.5)
        swing = math.sin(phase * math.tau)
        p["bhand"] = (p["bhand"][0] - swing * 5.0, p["bhand"][1] - abs(swing) * 2.0)
        p["be"] = (p["be"][0] - swing * 3.0, p["be"][1])
        p["fhand"] = (p["fhand"][0] + swing * 5.0, p["fhand"][1] - abs(swing) * 2.0)
        p["fe"] = (p["fe"][0] + swing * 3.0, p["fe"][1])
        frames.append(p)
    return frames


def crouch_frames(pal):
    frames = []
    for i in range(2):
        p = base_pose(pal)
        shift_body(p, 0, 15 + i)
        p["bh"] = (p["bh"][0] - 1, 70.0 + i)
        p["fh"] = (p["fh"][0] + 1, 70.0 + i)
        set_leg(p, "b", (p["bh"][0] - 8, 91.0), (p["bh"][0] - 10, 81.0 + i))
        set_leg(p, "f", (p["fh"][0] + 9, 91.0), (p["fh"][0] + 11, 81.0 + i))
        p["be"] = (p["bs"][0] + 6, p["bs"][1] + 12)
        p["bhand"] = (p["head"][0] + 1, p["head"][1] + 9)
        p["fe"] = (p["fs"][0] + 1, p["fs"][1] + 12)
        p["fhand"] = (p["head"][0] + 8, p["head"][1] + 9)
        p["head"] = (p["head"][0], p["head"][1] + 2)
        frames.append(p)
    return frames


def jump_frames(pal):
    frames = []
    # rise
    p = base_pose(pal)
    shift_body(p, 0, -3)
    set_leg(p, "b", (p["bh"][0] - 6, 80.0), (p["bh"][0] - 9, 70.0))
    set_leg(p, "f", (p["fh"][0] + 3, 84.0), (p["fh"][0] + 8, 71.0))
    p["be"] = (p["bs"][0] - 4, p["bs"][1] + 6)
    p["bhand"] = (p["bs"][0] - 7, p["bs"][1] + 1)
    p["fe"] = (p["fs"][0] + 5, p["fs"][1] + 4)
    p["fhand"] = (p["fs"][0] + 8, p["fs"][1] - 3)
    frames.append(p)
    # fall
    p = base_pose(pal)
    set_leg(p, "b", (p["bh"][0] - 7, 88.0), (p["bh"][0] - 8, 76.0))
    set_leg(p, "f", (p["fh"][0] + 6, 89.0), (p["fh"][0] + 7, 77.0))
    p["be"] = (p["bs"][0] - 5, p["bs"][1] + 8)
    p["bhand"] = (p["bs"][0] - 8, p["bs"][1] + 4)
    p["fe"] = (p["fs"][0] + 5, p["fs"][1] + 7)
    p["fhand"] = (p["fs"][0] + 7, p["fs"][1] + 2)
    frames.append(p)
    return frames


def block_frames(pal):
    frames = []
    for i in range(2):
        p = guard_pose(pal)
        shift_body(p, 0, i * 0.5)
        p["lean"] = -2.0
        p["be"] = (p["head"][0] + 3, p["head"][1] + 10)
        p["bhand"] = (p["head"][0] + 8, p["head"][1] + 6)
        p["fe"] = (p["head"][0] + 5, p["head"][1] + 12)
        p["fhand"] = (p["head"][0] + 10, p["head"][1] + 2)
        frames.append(p)
    return frames


def hurt_frames(pal):
    frames = []
    for i in range(2):
        p = base_pose(pal)
        shift_body(p, -4 - i, 2)
        p["head"] = (p["head"][0] - 3, p["head"][1] - 2)
        p["lean"] = -3.0
        p["be"] = (p["bs"][0] - 6, p["bs"][1] - 2)
        p["bhand"] = (p["bs"][0] - 9, p["bs"][1] - 8)
        p["fe"] = (p["fs"][0] + 1, p["fs"][1] - 4)
        p["fhand"] = (p["fs"][0] + 3, p["fs"][1] - 11)
        set_leg(p, "f", (p["fh"][0] + 8, 88.0), (p["fh"][0] + 9, 76.0))
        frames.append(p)
    return frames


def ko_frames(pal):
    frames = []
    # falling backwards
    p = base_pose(pal)
    shift_body(p, -6, 8)
    p["lean"] = -6.0
    p["head"] = (p["head"][0] - 8, p["head"][1] + 2)
    p["be"] = (p["bs"][0] - 8, p["bs"][1] - 2)
    p["bhand"] = (p["bs"][0] - 11, p["bs"][1] - 10)
    p["fe"] = (p["fs"][0] - 2, p["fs"][1] - 4)
    p["fhand"] = (p["fs"][0] + 1, p["fs"][1] - 12)
    set_leg(p, "b", (p["bh"][0] + 2, 84.0), (p["bh"][0] + 1, 74.0))
    set_leg(p, "f", (p["fh"][0] + 14, 92.0), (p["fh"][0] + 8, 82.0))
    frames.append(p)

    # lying on the ground, feet to the right (facing right)
    img = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    skin = c(pal["skin"])
    shirt = c(pal["shirt"])
    pants = c(pal["pants"])
    head = (16, 88)
    disc(d, head[0], head[1], 8, skin)
    d.ellipse([head[0] - 8, head[1] - 8, head[0] + 8, head[1] + 8], outline=OUTLINE)
    # hair
    d.pieslice([head[0] - 9, head[1] - 9, head[0] + 9, head[1] + 8], 90, 270,
               fill=c(pal["hair"]))
    # torso lying
    d.polygon([(24, 82), (43, 84), (44, 93), (24, 94)], fill=shirt, outline=OUTLINE)
    d.polygon([(43, 84), (58, 86), (58, 92), (44, 93)], fill=pants, outline=OUTLINE)
    draw_shoe(d, (62, 90), pal)
    # arms
    capsule(d, (31, 83), (28, 74), shirt, 5, OUTLINE, 2)
    capsule(d, (36, 84), (41, 73), shirt, 5, OUTLINE, 2)
    # X eyes
    d.line([(12, 86), (15, 89)], fill=OUTLINE)
    d.line([(15, 86), (12, 89)], fill=OUTLINE)
    d.line([(18, 86), (21, 89)], fill=OUTLINE)
    d.line([(21, 86), (18, 89)], fill=OUTLINE)
    frames.append(("image", img))
    return frames


def light_frames(pal):
    frames = []
    # windup, fist pulled to the chest
    p = base_pose(pal)
    p["fe"] = (p["fs"][0] - 3, p["fs"][1] + 9)
    p["fhand"] = (p["head"][0] + 4, p["head"][1] + 15)
    p["bhand"] = (p["head"][0] - 2, p["head"][1] + 11)
    frames.append(p)
    # extend jab
    p = base_pose(pal)
    p["lean"] = 1.5
    p["head"] = (p["head"][0] + 1, p["head"][1])
    p["fe"] = (p["fs"][0] + 8, p["fs"][1] + 2)
    p["fhand"] = (58.0, p["fs"][1] + 3)
    p["bhand"] = (p["head"][0] - 1, p["head"][1] + 9)
    p["be"] = (p["bs"][0] + 2, p["bs"][1] + 10)
    frames.append(p)
    # hold
    p = base_pose(pal)
    p["lean"] = 1.0
    p["fe"] = (p["fs"][0] + 7, p["fs"][1] + 3)
    p["fhand"] = (56.0, p["fs"][1] + 4)
    frames.append(p)
    # recover
    p = base_pose(pal)
    p["fe"] = (p["fs"][0] + 3, p["fs"][1] + 8)
    p["fhand"] = (p["head"][0] + 6, p["head"][1] + 9)
    frames.append(p)
    return frames


def heavy_frames(pal):
    frames = []
    # windup, torso coiled back
    p = base_pose(pal)
    p["lean"] = -3.0
    p["bs"] = (p["bs"][0] - 2, p["bs"][1])
    p["fs"] = (p["fs"][0] - 3, p["fs"][1])
    p["fe"] = (p["fs"][0] - 4, p["fs"][1] + 6)
    p["fhand"] = (p["bs"][0] - 4, p["bs"][1] + 4)
    p["bhand"] = (p["head"][0] + 1, p["head"][1] + 9)
    frames.append(p)
    # swing across
    p = base_pose(pal)
    p["lean"] = 2.0
    p["fe"] = (p["fs"][0] + 10, p["fs"][1] - 2)
    p["fhand"] = (p["fs"][0] + 20, p["fs"][1] + 6)
    p["bhand"] = (p["head"][0] + 1, p["head"][1] + 9)
    frames.append(p)
    # follow through
    p = base_pose(pal)
    p["lean"] = 4.0
    p["head"] = (p["head"][0] + 2, p["head"][1])
    p["fe"] = (p["fs"][0] + 7, p["fs"][1] + 8)
    p["fhand"] = (p["fs"][0] + 16, p["fs"][1] + 14)
    frames.append(p)
    # hold
    p = base_pose(pal)
    p["lean"] = 3.0
    p["fe"] = (p["fs"][0] + 6, p["fs"][1] + 9)
    p["fhand"] = (p["fs"][0] + 13, p["fs"][1] + 13)
    frames.append(p)
    # recover
    p = base_pose(pal)
    p["fe"] = (p["fs"][0] + 3, p["fs"][1] + 9)
    p["fhand"] = (p["head"][0] + 6, p["head"][1] + 10)
    frames.append(p)
    return frames


def low_frames(pal):
    frames = []
    for i in range(4):
        p = base_pose(pal)
        shift_body(p, 0, 15 + (1 if i == 2 else 0))
        p["bh"] = (p["bh"][0] - 1, 70.0 + (1 if i == 2 else 0))
        p["fh"] = (p["fh"][0] + 1, 70.0 + (1 if i == 2 else 0))
        set_leg(p, "b", (p["bh"][0] - 8, 91.0), (p["bh"][0] - 10, 81.0))
        set_leg(p, "f", (p["fh"][0] + 9, 91.0), (p["fh"][0] + 11, 81.0))
        p["be"] = (p["bs"][0] + 6, p["bs"][1] + 12)
        p["bhand"] = (p["head"][0] - 1, p["head"][1] + 10)
        p["head"] = (p["head"][0], p["head"][1] + 2)

        if i == 0:
            # windup: fist pulled back beside the knee
            p["fe"] = (p["fs"][0] - 3, p["fs"][1] + 12)
            p["fhand"] = (p["head"][0] + 2, p["head"][1] + 33)
        elif i == 1:
            # low swipe
            p["lean"] = 2.0
            p["fe"] = (p["fs"][0] + 7, p["fs"][1] + 16)
            p["fhand"] = (58.0, 76.0)
        elif i == 2:
            # held out
            p["lean"] = 1.5
            p["fe"] = (p["fs"][0] + 6, p["fs"][1] + 15)
            p["fhand"] = (56.0, 74.0)
        else:
            # recover to guard
            p["fe"] = (p["fs"][0] + 1, p["fs"][1] + 12)
            p["fhand"] = (p["head"][0] + 6, p["head"][1] + 21)
        frames.append(p)
    return frames


def special_frames(pal):
    """A big committed swing with the character's prop."""
    frames = []
    prop = pal.get("prop")
    is_throw = prop == "clipboard"
    # 0 windup: both hands back
    p = base_pose(pal)
    p["lean"] = -3.0
    p["be"] = (p["bs"][0] - 1, p["bs"][1] + 6)
    p["bhand"] = (p["bs"][0] - 3, p["bs"][1] + 2)
    p["fe"] = (p["bs"][0] + 1, p["bs"][1] + 8)
    p["fhand"] = (p["bs"][0] + 2, p["bs"][1] + 2)
    p["prop"] = prop
    frames.append(p)
    # 1 charge
    p = base_pose(pal)
    p["lean"] = -5.0
    p["head"] = (p["head"][0] - 2, p["head"][1] + 1)
    p["be"] = (p["bs"][0] - 2, p["bs"][1] + 4)
    p["bhand"] = (p["bs"][0] - 4, p["bs"][1] - 2)
    p["fe"] = (p["bs"][0], p["bs"][1] + 6)
    p["fhand"] = (p["bs"][0] + 1, p["bs"][1] - 1)
    p["prop"] = prop
    frames.append(p)
    # 2 release
    p = base_pose(pal)
    p["lean"] = 4.0
    p["head"] = (p["head"][0] + 2, p["head"][1])
    p["fe"] = (p["fs"][0] + 9, p["fs"][1] - 2)
    p["fhand"] = (57.0, p["fs"][1] + 1)
    p["be"] = (p["bs"][0] + 4, p["bs"][1] + 8)
    p["bhand"] = (p["bs"][0] + 6, p["bs"][1] + 3)
    p["prop"] = None if is_throw else prop
    frames.append(p)
    # 3 hold
    p = base_pose(pal)
    p["lean"] = 3.0
    p["fe"] = (p["fs"][0] + 8, p["fs"][1] + 3)
    p["fhand"] = (55.0, p["fs"][1] + 5)
    p["prop"] = None if is_throw else prop
    frames.append(p)
    # 4 recover
    p = base_pose(pal)
    p["fe"] = (p["fs"][0] + 3, p["fs"][1] + 8)
    p["fhand"] = (p["head"][0] + 7, p["head"][1] + 9)
    p["prop"] = None if is_throw else prop
    frames.append(p)
    # 5 settle
    p = base_pose(pal)
    p["prop"] = None
    frames.append(p)
    return frames


def win_frames(pal):
    frames = []
    for i in range(4):
        p = base_pose(pal)
        hop = [0, -2, 0, -1][i]
        shift_body(p, 0, hop)
        raised = i % 2 == 0
        p["be"] = (p["bs"][0] - 2, p["bs"][1] - 4)
        p["bhand"] = (p["bs"][0] - 4, p["bs"][1] - 14)
        p["fe"] = (p["fs"][0] + 1, p["fs"][1] - 5)
        p["fhand"] = (p["fs"][0] + 3, p["fs"][1] - (16 if raised else 12))
        if i == 2:
            p["head"] = (p["head"][0], p["head"][1] + 1)
        frames.append(p)
    return frames


ANIMATIONS = [
    ("idle", 0, idle_frames),
    ("walk", 1, walk_frames),
    ("crouch", 2, crouch_frames),
    ("jump", 3, jump_frames),
    ("block", 4, block_frames),
    ("hurt", 5, hurt_frames),
    ("ko", 6, ko_frames),
    ("light", 7, light_frames),
    ("heavy", 8, heavy_frames),
    ("special", 9, special_frames),
    ("win", 10, win_frames),
    ("low", 11, low_frames),
]


def build_fighter_sheet(char_id: str, pal) -> Image.Image:
    rows = len(ANIMATIONS)
    sheet = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    for name, row, maker in ANIMATIONS:
        frames = maker(pal)
        for col, pose in enumerate(frames[:COLS]):
            if isinstance(pose, tuple) and pose[0] == "image":
                frame = pose[1]
            else:
                frame = draw_fighter_frame(pal, pose)
            sheet.alpha_composite(frame, (col * CELL_W, row * CELL_H))
    return sheet


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------


def build_hit_spark(path):
    frames = 5
    size = 48
    sheet = Image.new("RGBA", (frames * size, size), (0, 0, 0, 0))
    for f in range(frames):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        t = f / (frames - 1)
        r = 4 + t * 14
        alpha = int(255 * (1.0 - t * 0.75))
        color = (255, 244, 200, alpha)
        color2 = (255, 176, 64, alpha)
        cx, cy = size // 2, size // 2
        for k in range(8):
            a = k * math.tau / 8 + 0.2
            x = cx + math.cos(a) * r
            y = cy + math.sin(a) * r
            d.line([(cx, cy), (x, y)], fill=color2, width=3 if k % 2 else 2)
        disc(d, cx, cy, int(r * 0.6), color)
        disc(d, cx, cy, int(r * 0.32), (255, 255, 255, alpha))
        sheet.alpha_composite(img, (f * size, 0))
    sheet.save(path)


def build_block_spark(path):
    frames = 4
    size = 40
    sheet = Image.new("RGBA", (frames * size, size), (0, 0, 0, 0))
    for f in range(frames):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        t = f / (frames - 1)
        alpha = int(255 * (1.0 - t))
        cx, cy = size // 2, size // 2
        for k in range(6):
            a = k * math.tau / 6
            r = 6 + t * 12
            d.line([(cx + math.cos(a) * 5, cy + math.sin(a) * 5),
                    (cx + math.cos(a) * r, cy + math.sin(a) * r)],
                   fill=(180, 236, 255, alpha), width=2)
        d.arc([cx - 10, cy - 10, cx + 10, cy + 10], 200, 340, fill=(240, 252, 255, alpha), width=2)
        sheet.alpha_composite(img, (f * size, 0))
    sheet.save(path)


def build_dust(path):
    frames = 4
    w, h = 32, 24
    sheet = Image.new("RGBA", (frames * w, h), (0, 0, 0, 0))
    for f in range(frames):
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        t = f / (frames - 1)
        alpha = int(150 * (1.0 - t))
        for k in range(4):
            x = 8 + t * 14 + (k - 1.5) * 5
            y = h - 4 - t * 6 - (k % 2) * 3
            r = 3 + t * 3 + (k % 2)
            d.ellipse([x - r, y - r, x + r, y + r], fill=(222, 218, 206, alpha))
        sheet.alpha_composite(img, (f * w, 0))
    sheet.save(path)


def build_shadow(path):
    w, h = 96, 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(6):
        a = 16 + i * 6
        d.ellipse([i * 3, i * 1.5, w - i * 3, h - i * 1.5], fill=(0, 0, 0, a))
    img.save(path)


# ---------------------------------------------------------------------------
# Stages
# ---------------------------------------------------------------------------


def stage_breakroom(path):
    img = Image.new("RGBA", (1280, 720), (207, 199, 178, 255))
    d = ImageDraw.Draw(img)

    # wall + ceiling
    dither_gradient(img, (0, 0, 1280, 470), (214, 206, 188), (196, 186, 166))
    d.rectangle([0, 0, 1280, 46], fill=(96, 94, 88))
    d.rectangle([0, 46, 1280, 60], fill=(120, 118, 110))
    for x in range(90, 1280, 210):
        d.rectangle([x, 10, x + 120, 20], fill=(238, 244, 226))
        d.rectangle([x - 6, 8, x + 126, 12], fill=(150, 148, 140))
        for gx in range(x - 60, x + 190, 30):
            d.rectangle([gx, 20, gx + 2, 26], fill=(180, 176, 160))
    d.rectangle([0, 60, 1280, 64], fill=(170, 164, 150))

    # wainscoting
    d.rectangle([0, 452, 1280, 600], fill=(150, 140, 120))
    for x in range(0, 1280, 96):
        d.rectangle([x, 452, x + 88, 594], outline=(132, 122, 104))
    d.rectangle([0, 444, 1280, 452], fill=(176, 166, 146))

    # floor
    checker(d, (0, 600, 1280, 720), (176, 172, 162), (158, 154, 146), 32, 1)
    d.rectangle([0, 600, 1280, 606], fill=(112, 108, 100))
    speckle(img, (0, 610, 1280, 720), (90, 88, 84), 900, seed=3, alpha_min=8, alpha_max=26)

    # window with a parking lot view
    d.rectangle([480, 120, 800, 330], fill=(96, 106, 126), outline=(120, 118, 110), width=4)
    dither_gradient(img, (484, 124, 796, 300), (236, 166, 108), (150, 132, 150))
    d.rectangle([484, 300, 796, 326], fill=(74, 78, 86))
    for bx in range(500, 780, 60):
        d.rectangle([bx, 260, bx + 40, 300], fill=(92, 86, 104))
        d.rectangle([bx + 6, 272, bx + 14, 280], fill=(240, 208, 120))
    d.rectangle([638, 124, 642, 326], fill=(120, 118, 110))
    d.rectangle([484, 218, 796, 222], fill=(120, 118, 110))
    d.rectangle([470, 326, 810, 336], fill=(160, 150, 132))
    # blinds
    for y in range(126, 218, 8):
        d.rectangle([486, y, 794, y + 4], fill=(224, 218, 200, 110))

    # motivational poster
    d.rectangle([880, 120, 1030, 250], fill=(238, 234, 220), outline=(70, 66, 62), width=2)
    draw_text(d, "HANG IN", 902, 140, (58, 66, 76), 2)
    draw_text(d, "THERE", 916, 162, (58, 66, 76), 2)
    d.rectangle([902, 190, 1008, 236], fill=(128, 166, 168))
    d.ellipse([932, 196, 958, 222], fill=(240, 226, 170))
    d.polygon([(902, 236), (952, 206), (1008, 236)], fill=(92, 128, 116))

    # clock at 4:59
    d.ellipse([1108, 110, 1172, 174], fill=(240, 238, 228), outline=(70, 66, 62), width=3)
    d.line([(1140, 142), (1140, 122)], fill=(40, 40, 44), width=3)
    d.line([(1140, 142), (1124, 148)], fill=(40, 40, 44), width=3)
    draw_text(d, "4:59", 1114, 180, (60, 58, 54), 2)

    # vending machine
    d.rectangle([46, 250, 190, 600], fill=(46, 92, 132), outline=(28, 34, 44), width=3)
    d.rectangle([58, 266, 178, 470], fill=(92, 158, 196))
    for row in range(3):
        for col in range(3):
            x = 66 + col * 36
            y = 278 + row * 58
            d.rectangle([x, y, x + 26, y + 40], fill=(236, 226, 204), outline=(50, 60, 70))
            d.rectangle([x + 4, y + 8, x + 22, y + 30], fill=(
                (196, 92, 84), (224, 196, 96), (120, 176, 132))[(row + col) % 3])
    d.rectangle([58, 486, 178, 512], fill=(30, 40, 52))
    d.rectangle([70, 492, 110, 506], fill=(150, 220, 200))
    d.rectangle([150, 492, 166, 504], fill=(80, 84, 90))
    d.rectangle([58, 530, 178, 580], fill=(32, 42, 54))
    draw_text(d, "AVERAGE", 72, 538, (232, 214, 148), 1)
    draw_text(d, "SNACKS", 78, 552, (232, 214, 148), 1)
    draw_text(d, "1.25", 82, 566, (200, 200, 190), 1)

    # water cooler
    d.rectangle([250, 430, 310, 600], fill=(206, 208, 206), outline=(120, 118, 112), width=2)
    d.rectangle([258, 350, 302, 430], fill=(178, 214, 230), outline=(110, 150, 170), width=2)
    d.rectangle([262, 358, 298, 418], fill=(206, 234, 244))
    d.rectangle([264, 452, 280, 466], fill=(120, 160, 190))
    d.rectangle([284, 452, 300, 466], fill=(120, 160, 190))

    # break table + chairs
    d.rectangle([960, 470, 1160, 486], fill=(176, 146, 108), outline=(96, 76, 56), width=2)
    d.rectangle([970, 486, 980, 600], fill=(120, 120, 126))
    d.rectangle([1140, 486, 1150, 600], fill=(120, 120, 126))
    d.rectangle([1000, 430, 1030, 466], fill=(226, 224, 216), outline=(120, 116, 110))
    d.rectangle([990, 424, 1040, 434], fill=(244, 240, 230), outline=(140, 136, 130))
    d.arc([1002, 402, 1028, 428], 200, 340, fill=(244, 240, 230), width=3)
    # chair
    d.rectangle([900, 470, 930, 520], fill=(70, 88, 104))
    d.rectangle([906, 520, 914, 600], fill=(90, 94, 100))
    d.rectangle([894, 520, 936, 528], fill=(90, 94, 100))

    # fridge
    d.rectangle([330, 300, 440, 600], fill=(222, 224, 218), outline=(140, 138, 132), width=3)
    d.line([(330, 380), (440, 380)], fill=(140, 138, 132), width=2)
    d.rectangle([424, 330, 432, 360], fill=(160, 160, 156))
    d.rectangle([424, 400, 432, 430], fill=(160, 160, 156))
    d.rectangle([350, 320, 386, 342], fill=(232, 214, 120))
    d.rectangle([392, 318, 410, 340], fill=(196, 96, 88))

    # baseboard shadow
    d.rectangle([0, 592, 1280, 600], fill=(96, 92, 84))
    # overhead light pools on the floor
    for x in (300, 640, 980):
        glow(img, (x, 660), 210, (255, 250, 220), strength=0.8)

    img.convert("RGB").save(path)


def stage_parkinglot(path):
    img = Image.new("RGBA", (1280, 720), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)

    # dusk sky
    dither_gradient(img, (0, 0, 1280, 430), (72, 78, 128), (236, 146, 96))
    # sun band
    dither_gradient(img, (0, 300, 1280, 430), (236, 146, 96), (250, 196, 120))
    # clouds
    for cx, cy, cw in ((220, 120, 210), (700, 80, 260), (1040, 150, 180)):
        d.ellipse([cx - cw // 2, cy - 14, cx + cw // 2, cy + 14], fill=(92, 94, 140, 180))
        d.ellipse([cx - cw // 3, cy - 22, cx + cw // 3, cy + 10], fill=(120, 112, 152, 160))

    # distant skyline
    rng = random.Random(11)
    x = 0
    while x < 1280:
        w = rng.randrange(40, 90)
        h = rng.randrange(60, 170)
        d.rectangle([x, 330 - h, x + w, 430], fill=(58, 58, 88))
        for wy in range(340 - h, 424, 14):
            for wx in range(x + 6, x + w - 6, 14):
                if rng.random() < 0.3:
                    d.rectangle([wx, wy, wx + 5, wy + 7], fill=(226, 190, 110, 160))
        x += w + rng.randrange(2, 14)

    # storefront block
    d.rectangle([0, 400, 1280, 600], fill=(84, 72, 76))
    d.rectangle([0, 400, 1280, 418], fill=(60, 52, 58))
    # three shops
    shops = [
        (60, 380, "LAUNDROMAT", (96, 150, 168)),
        (470, 360, "PIZZA", (186, 92, 68)),
        (880, 400, "AUTO PARTS", (108, 116, 96)),
    ]
    for x0, w, sign, accent in shops:
        d.rectangle([x0, 430, x0 + w, 600], fill=(66, 58, 62))
        d.rectangle([x0 + 20, 470, x0 + w - 20, 596], fill=(34, 34, 44))
        # glass reflection
        d.polygon([(x0 + 24, 590), (x0 + 70, 480), (x0 + 92, 480), (x0 + 46, 590)],
                  fill=(70, 86, 104, 120))
        # sign board
        d.rectangle([x0, 400, x0 + w, 438], fill=accent, outline=(40, 36, 40), width=2)
        draw_text(d, sign, x0 + 12, 410, (246, 240, 226), 2)
        # awning trim
        for ax in range(x0, x0 + w, 32):
            d.rectangle([ax, 438, ax + 16, 448], fill=(236, 228, 208))
            d.rectangle([ax + 16, 438, ax + 32, 448], fill=accent)

    # doors + warm light
    for x0 in (180, 610, 1010):
        d.rectangle([x0, 480, x0 + 70, 600], fill=(48, 44, 44))
        d.rectangle([x0 + 6, 490, x0 + 64, 540], fill=(236, 202, 130))
        d.rectangle([x0 + 6, 544, x0 + 64, 596], fill=(150, 128, 96))
        glow(img, (x0 + 35, 520), 90, (255, 214, 140), strength=0.9)

    # pole sign
    d.rectangle([1180, 200, 1196, 600], fill=(70, 70, 78))
    d.rectangle([1080, 160, 1270, 296], fill=(40, 40, 48), outline=(90, 90, 98), width=3)
    draw_text(d, "AVERAGE", 1104, 178, (238, 216, 120), 3)
    draw_text(d, "MART", 1132, 210, (238, 216, 120), 3)
    draw_text(d, "OPEN 25 HRS", 1096, 254, (200, 198, 190), 1)
    glow(img, (1175, 230), 150, (255, 220, 140), strength=0.7)

    # asphalt
    dither_gradient(img, (0, 600, 1280, 720), (78, 76, 88), (56, 54, 64))
    speckle(img, (0, 600, 1280, 720), (40, 40, 48), 1200, seed=5, alpha_min=10, alpha_max=40)
    # parking lines + stains
    for x in range(40, 1280, 220):
        d.polygon([(x, 720), (x + 40, 720), (x + 30, 630), (x + 8, 630)],
                  fill=(214, 206, 176, 60))
    d.ellipse([330, 650, 420, 676], fill=(44, 42, 52, 140))
    d.ellipse([760, 690, 900, 714], fill=(44, 42, 52, 120))

    # street lamp
    d.rectangle([246, 250, 256, 600], fill=(58, 58, 66))
    d.rectangle([246, 250, 340, 258], fill=(58, 58, 66))
    d.rectangle([332, 258, 352, 268], fill=(70, 70, 78))
    d.ellipse([330, 264, 354, 276], fill=(255, 232, 168))
    glow(img, (342, 272), 220, (255, 222, 150), strength=1.0)
    d.rectangle([0, 690, 1280, 720], fill=(40, 38, 46, 60))

    # car (left, beater)
    d.rectangle([120, 540, 330, 604], fill=(112, 92, 96), outline=(40, 38, 44), width=2)
    d.polygon([(160, 540), (190, 496), (286, 496), (310, 540)], fill=(126, 104, 108),
              outline=(40, 38, 44))
    d.rectangle([196, 504, 240, 534], fill=(72, 86, 104))
    d.rectangle([246, 504, 282, 534], fill=(72, 86, 104))
    for wx in (160, 292):
        d.ellipse([wx - 20, 582, wx + 20, 620], fill=(36, 34, 40), outline=(20, 20, 24), width=2)
        d.ellipse([wx - 9, 593, wx + 9, 611], fill=(120, 120, 128))
    d.ellipse([300, 552, 314, 566], fill=(240, 226, 160))
    glow(img, (308, 560), 70, (255, 230, 160), strength=0.7)
    # dent
    d.line([(228, 558), (258, 570)], fill=(78, 62, 66), width=3)

    # car (right, newer)
    d.rectangle([960, 552, 1150, 606], fill=(64, 96, 118), outline=(30, 36, 44), width=2)
    d.polygon([(986, 552), (1016, 512), (1114, 512), (1136, 552)], fill=(74, 108, 132),
              outline=(30, 36, 44))
    d.rectangle([1020, 520, 1062, 546], fill=(90, 110, 128))
    d.rectangle([1068, 520, 1106, 546], fill=(90, 110, 128))
    for wx in (996, 1114):
        d.ellipse([wx - 18, 588, wx + 18, 624], fill=(28, 28, 34), outline=(16, 16, 20), width=2)
        d.ellipse([wx - 8, 598, wx + 8, 614], fill=(130, 132, 140))

    # cart corral
    d.line([(760, 520), (900, 520)], fill=(170, 172, 180), width=3)
    d.line([(760, 520), (760, 600)], fill=(150, 152, 160), width=3)
    d.line([(900, 520), (900, 600)], fill=(150, 152, 160), width=3)
    for i in range(3):
        x = 780 + i * 34
        d.rectangle([x, 550, x + 20, 588], fill=(150, 154, 164), outline=(90, 92, 100))
        d.line([(x + 20, 556), (x + 30, 548)], fill=(120, 124, 132), width=2)

    # trash can
    d.rectangle([1200, 520, 1250, 600], fill=(70, 78, 72), outline=(40, 46, 42), width=2)
    d.ellipse([1196, 512, 1254, 528], fill=(90, 98, 90))

    img.convert("RGB").save(path)


def stage_backyard(path):
    img = Image.new("RGBA", (1280, 720), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)

    # evening sky
    dither_gradient(img, (0, 0, 1280, 500), (58, 62, 104), (232, 150, 120))
    dither_gradient(img, (0, 330, 1280, 500), (232, 150, 120), (246, 190, 130))
    # stars
    rng = random.Random(21)
    for _ in range(90):
        x = rng.randrange(0, 1280)
        y = rng.randrange(0, 210)
        a = rng.randrange(90, 200)
        d.point((x, y), fill=(250, 248, 232, a))
    # moon
    d.ellipse([1050, 70, 1114, 134], fill=(248, 240, 212))
    d.ellipse([1038, 60, 1102, 124], fill=(66, 68, 110))
    glow(img, (1082, 102), 90, (250, 240, 200), strength=0.6)

    # tree line
    for bx in range(-40, 1320, 90):
        r = rng.randrange(30, 60)
        d.ellipse([bx - r, 360 - r, bx + r, 400 + r], fill=(52, 68, 62))
    d.rectangle([0, 380, 1280, 500], fill=(60, 78, 66))

    # fence
    for x in range(0, 1280, 40):
        d.rectangle([x, 380, x + 34, 560], fill=(150, 126, 92), outline=(96, 78, 58))
        d.polygon([(x, 380), (x + 17, 362), (x + 34, 380)], fill=(160, 136, 100),
                  outline=(96, 78, 58))
    d.rectangle([0, 412, 1280, 424], fill=(120, 98, 70))
    d.rectangle([0, 500, 1280, 512], fill=(120, 98, 70))

    # string lights
    points = []
    for i in range(0, 1281, 20):
        y = 190 + math.sin(i / 1280 * math.pi * 2.2) * 40
        points.append((i, y))
    for i in range(len(points) - 1):
        d.line([points[i], points[i + 1]], fill=(60, 54, 52), width=2)
    for i in range(0, len(points), 7):
        x, y = points[i]
        d.ellipse([x - 4, y - 2, x + 4, y + 10], fill=(255, 226, 150))
        glow(img, (x, y + 5), 40, (255, 220, 150), strength=0.6)

    # house wall on the left
    d.rectangle([0, 250, 250, 600], fill=(196, 178, 146), outline=(120, 106, 88), width=2)
    for y in range(260, 600, 22):
        d.line([(0, y), (250, y)], fill=(178, 160, 130))
    d.rectangle([60, 360, 160, 520], fill=(92, 116, 132), outline=(70, 66, 60), width=3)
    d.rectangle([66, 366, 154, 514], fill=(150, 190, 200))
    d.polygon([(66, 514), (110, 420), (154, 514)], fill=(96, 140, 120, 160))
    d.rectangle([0, 240, 260, 252], fill=(110, 90, 74))
    d.rectangle([180, 300, 230, 330], fill=(236, 214, 160))
    glow(img, (205, 315), 70, (255, 220, 150), strength=0.8)

    # grass
    dither_gradient(img, (0, 560, 1280, 720), (82, 118, 76), (56, 88, 60))
    for _ in range(1400):
        x = rng.randrange(0, 1280)
        y = rng.randrange(560, 720)
        c = rng.choice([(96, 138, 88), (66, 100, 68), (110, 150, 96)])
        d.line([(x, y), (x + rng.choice([-1, 0, 1]), y - rng.randrange(2, 5))], fill=c)
    d.rectangle([0, 556, 1280, 562], fill=(64, 92, 66))

    # patio stones right
    checker(d, (900, 590, 1280, 720), (168, 160, 144), (150, 142, 128), 40, 1)

    # grill
    d.rectangle([1010, 470, 1150, 520], fill=(52, 52, 58), outline=(28, 28, 32), width=2)
    d.rectangle([1000, 452, 1160, 476], fill=(70, 70, 78), outline=(28, 28, 32), width=2)
    d.ellipse([1020, 446, 1140, 466], fill=(38, 38, 44))
    for gx in range(1028, 1136, 12):
        d.line([(gx, 450), (gx + 8, 462)], fill=(120, 120, 128), width=2)
    d.rectangle([1030, 520, 1040, 592], fill=(44, 44, 50))
    d.rectangle([1120, 520, 1130, 592], fill=(44, 44, 50))
    d.rectangle([1060, 520, 1100, 540], fill=(90, 90, 96))
    d.ellipse([1024, 540, 1064, 560], fill=(180, 180, 186))
    # smoke
    for i in range(6):
        a = 46 - i * 6
        d.ellipse([1080 + i * 7, 420 - i * 22, 1110 + i * 9, 448 - i * 22],
                  fill=(220, 220, 220, max(0, a)))
    # flames
    d.polygon([(1050, 478), (1062, 456), (1070, 472), (1080, 450), (1090, 474),
               (1098, 460), (1104, 480)], fill=(240, 150, 60))

    # picnic table
    d.rectangle([420, 520, 700, 536], fill=(172, 132, 92), outline=(110, 80, 54), width=2)
    d.rectangle([400, 556, 720, 572], fill=(158, 120, 84), outline=(110, 80, 54), width=2)
    d.polygon([(420, 536), (440, 556), (430, 556), (410, 536)], fill=(120, 92, 64))
    d.polygon([(700, 536), (680, 556), (690, 556), (710, 536)], fill=(120, 92, 64))
    d.rectangle([440, 572, 454, 620], fill=(110, 88, 64))
    d.rectangle([666, 572, 680, 620], fill=(110, 88, 64))
    # solo cups + plate
    d.rectangle([505, 498, 523, 520], fill=(196, 62, 62), outline=(120, 40, 44))
    d.rectangle([497, 498, 531, 504], fill=(224, 224, 216))
    d.ellipse([560, 506, 610, 522], fill=(238, 236, 226), outline=(180, 176, 162))
    d.rectangle([640, 502, 668, 520], fill=(224, 180, 70), outline=(150, 116, 44))

    # cooler
    d.rectangle([330, 540, 392, 600], fill=(86, 116, 164), outline=(48, 66, 96), width=2)
    d.rectangle([322, 528, 400, 546], fill=(224, 224, 216), outline=(150, 150, 146), width=2)
    d.rectangle([350, 528, 372, 538], fill=(200, 200, 196))

    # lawn chair
    d.line([(770, 540), (800, 600)], fill=(60, 60, 66), width=3)
    d.line([(840, 540), (816, 600)], fill=(60, 60, 66), width=3)
    d.polygon([(762, 540), (848, 540), (838, 570), (772, 570)], fill=(86, 126, 156))
    d.line([(762, 540), (750, 500)], fill=(60, 60, 66), width=3)
    d.line([(848, 540), (860, 500)], fill=(60, 60, 66), width=3)
    d.polygon([(748, 500), (862, 500), (838, 522), (772, 522)], fill=(96, 138, 168))

    img.convert("RGB").save(path)


# ---------------------------------------------------------------------------
# Icon
# ---------------------------------------------------------------------------


def build_icon(path):
    size = 64
    img = Image.new("RGBA", (size, size), (26, 28, 38, 255))
    d = ImageDraw.Draw(img)
    dither_gradient(img, (0, 0, size, size), (40, 46, 66), (22, 24, 34))
    # burst
    for i in range(12):
        a = i * math.tau / 12
        d.line([(32, 34), (32 + math.cos(a) * 22, 34 + math.sin(a) * 22)],
               fill=(214, 176, 96), width=2)
    # two fists meeting
    d.rectangle([8, 30, 26, 44], fill=(206, 160, 126), outline=(28, 24, 26))
    d.rectangle([38, 30, 56, 44], fill=(232, 186, 148), outline=(28, 24, 26))
    d.rectangle([6, 36, 12, 44], fill=(170, 54, 54))
    d.rectangle([52, 36, 58, 44], fill=(54, 96, 150))
    draw_text(d, "AC", 18, 8, (244, 236, 214), 2, shadow=(20, 20, 26))
    img.resize((256, 256), Image.NEAREST).save(path)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    os.makedirs(os.path.join(ASSETS, "sprites", "fighters"), exist_ok=True)
    os.makedirs(os.path.join(ASSETS, "sprites", "fx"), exist_ok=True)
    os.makedirs(os.path.join(ASSETS, "stages"), exist_ok=True)

    for char_id, pal in FIGHTERS.items():
        sheet = build_fighter_sheet(char_id, pal)
        out = os.path.join(ASSETS, "sprites", "fighters", f"{char_id}.png")
        sheet.save(out)
        print("wrote", os.path.relpath(out, ROOT), sheet.size)

    build_hit_spark(os.path.join(ASSETS, "sprites", "fx", "hit.png"))
    build_block_spark(os.path.join(ASSETS, "sprites", "fx", "block.png"))
    build_dust(os.path.join(ASSETS, "sprites", "fx", "dust.png"))
    build_shadow(os.path.join(ASSETS, "sprites", "fx", "shadow.png"))

    stage_breakroom(os.path.join(ASSETS, "stages", "breakroom.png"))
    stage_parkinglot(os.path.join(ASSETS, "stages", "parkinglot.png"))
    stage_backyard(os.path.join(ASSETS, "stages", "backyard.png"))

    build_icon(os.path.join(ROOT, "icon.png"))
    print("art done")


if __name__ == "__main__":
    main()
