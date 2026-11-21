"""Generates grounded, semi-realistic graphic-novel 2D fighting-game art for Average Combat.

Run from the repo root:
    .venv/bin/python tools/gen_art.py            # fighters + FX only (default)
    .venv/bin/python tools/gen_art.py --stages   # also regenerate legacy stages & icon

Outputs:
    assets/sprites/fighters/<id>.png   (6 x 16 grid of 192x288 frames -> 1152x4608,
                                        2x supersampled at 384x576 + LANCZOS)
    assets/sprites/fx/hit.png          (240x48 = 5 x 48x48)
    assets/sprites/fx/block.png        (160x40 = 4 x 40x40)
    assets/sprites/fx/dust.png         (128x24 = 4 x 32x24)
    assets/sprites/fx/shadow.png       (64x16)

The fighter sheet layout is the contract with scripts/data/character_db.gd.
"""

from __future__ import annotations

import argparse
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

from pixel_art import (
    checker, color_bands, darken_layer, dither_gradient, draw_clipped_overlay,
    draw_text, lerp_pt, rgba, rot_pt, shade_and_ink_layer, shift_tone,
    stepped_glow, tapered_limb_polygon,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")

# Target 1:1 native fighter cell dimensions & 2x supersampling canvas
CELL_W, CELL_H = 192, 288
SS = 2
SS_W, SS_H = CELL_W * SS, CELL_H * SS  # 384 x 576
COLS = 6
GROUND_Y = 600.0

# 2x anchor constants (192x288 feet anchor at x=96, y=273 -> 2x at x=192, y=546)
CX = 192.0
FOOT_Y = 546.0

# ---------------------------------------------------------------------------
# Grounded Realistic Fighter Palettes & Profiles
# ---------------------------------------------------------------------------

FIGHTERS = {
    "dave": {
        "id": "dave",
        "label": "DAVE",
        "skin": (224, 182, 150),
        "skin_shade": (188, 144, 114),
        "skin_hi": (242, 210, 182),
        "hair": (66, 46, 34),
        "hair_hi": (104, 76, 56),
        "hair_dark": (40, 28, 22),
        "shirt": (218, 216, 208),
        "shirt_dark": (166, 166, 162),
        "shirt_hi": (238, 236, 230),
        "pants": (156, 144, 118),
        "pants_dark": (118, 108, 86),
        "shoes": (68, 46, 36),
        "sole": (34, 26, 24),
        "belt": (46, 42, 44),
        "accent": (126, 36, 44),       # loosened dark burgundy tie
        "accent2": (186, 190, 198),    # wire-rim glasses / buckle
        "ink": (28, 22, 24),
        "bulk": 1.00,
        "height": 0.0,
        "style": "short",
        "sleeve": "long",
        "glasses": True,
        "prop": "box",
    },
    "karen": {
        "id": "karen",
        "label": "KAREN",
        "skin": (230, 190, 160),
        "skin_shade": (194, 152, 124),
        "skin_hi": (246, 216, 190),
        "hair": (198, 176, 128),
        "hair_hi": (228, 210, 166),
        "hair_dark": (146, 124, 82),
        "shirt": (118, 70, 118),       # tailored muted plum blazer
        "shirt_dark": (78, 44, 82),
        "shirt_hi": (148, 98, 148),
        "pants": (58, 60, 70),         # fitted charcoal-slate slacks
        "pants_dark": (38, 40, 48),
        "shoes": (38, 34, 42),         # dark low-heel dress shoes
        "sole": (24, 20, 26),
        "belt": (44, 38, 48),
        "accent": (212, 192, 134),     # subtle gold button / stud
        "accent2": (232, 226, 212),    # ivory blouse
        "ink": (28, 18, 28),
        "bulk": 0.90,
        "height": 8.0,
        "style": "bob",
        "sleeve": "long",
        "glasses": False,
        "prop": "clipboard",
    },
    "tony": {
        "id": "tony",
        "label": "TONY",
        "skin": (210, 162, 128),
        "skin_shade": (172, 126, 94),
        "skin_hi": (232, 192, 160),
        "hair": (76, 72, 70),          # salt-and-pepper beard
        "hair_hi": (152, 150, 146),    # silver flecks
        "hair_dark": (42, 38, 38),
        "shirt": (106, 90, 64),        # weathered olive-brown canvas work jacket
        "shirt_dark": (68, 56, 40),
        "shirt_hi": (134, 116, 88),
        "pants": (62, 66, 74),         # dark charcoal work pants
        "pants_dark": (42, 44, 52),
        "shoes": (58, 46, 38),         # scuffed steel-toe work boots
        "sole": (30, 26, 24),
        "belt": (46, 36, 28),
        "accent": (188, 150, 78),      # brass zipper & button
        "accent2": (78, 82, 86),       # dark heather henley tee
        "ink": (26, 22, 18),
        "bulk": 1.18,
        "height": -6.0,
        "style": "bald",
        "sleeve": "rolled",
        "glasses": False,
        "prop": "plunger",
    },
    "chad": {
        "id": "chad",
        "label": "CHAD",
        "skin": (220, 176, 142),
        "skin_shade": (182, 138, 108),
        "skin_hi": (240, 204, 174),
        "hair": (54, 44, 38),
        "hair_hi": (88, 72, 60),
        "hair_dark": (34, 28, 24),
        "shirt": (54, 104, 104),       # matte dark teal zip-up hoodie
        "shirt_dark": (34, 68, 70),
        "shirt_hi": (80, 134, 132),
        "pants": (74, 88, 114),        # weathered indigo denim jeans
        "pants_dark": (50, 62, 84),
        "shoes": (214, 212, 204),      # clean muted off-white/grey sneakers
        "sole": (132, 126, 118),
        "belt": (48, 46, 44),
        "accent": (46, 52, 62),        # backwards dark slate baseball cap
        "accent2": (218, 214, 202),    # hoodie drawstrings & sneaker trim
        "ink": (18, 24, 26),
        "bulk": 0.92,
        "height": 4.0,
        "style": "cap",
        "sleeve": "long",
        "glasses": False,
        "prop": "laptop",
    },
}


# ---------------------------------------------------------------------------
# Skeleton & Pose Helpers (2x Supersampled Coordinates: 384 x 576)
# ---------------------------------------------------------------------------


def base_pose(pal: dict) -> dict:
    """Grounded 3/4 open boxer/brawler fighting stance facing RIGHT.

    - Standing adult height ~456px at 2x (~228px at 1x, ~7.3 heads tall).
    - Natural short strong neck & broad adult ribcage/shoulders.
    - Far side ('b', Layer 1 arm / Layer 2 leg) = lead guard & forward planted leg.
    - Near side ('f', Layer 6 arm / Layer 3 leg) = rear power arm & rear planted leg.
    - Torso + jacket/blazer/hoodie hem (Layer 4) naturally overlaps both hip tops!
    """
    b = pal["bulk"]
    h = pal["height"]
    cx = CX
    hy = 124.0 + h
    return {
        "head": (cx + 8.0, hy),
        "head_tilt": 4.0,
        "expr": "focused",
        # Broad natural adult shoulders with compact athletic neck (hy+46)
        "bs": (cx + 28.0 * b, hy + 44.0),       # far (lead) shoulder
        "fs": (cx - 28.0 * b, hy + 50.0),       # near (rear) shoulder
        "torso_twist": 0.0,                      # +1 = driving front shoulder forward
        "bh": (cx + 16.0 * b, hy + 194.0),      # far (lead) hip
        "fh": (cx - 18.0 * b, hy + 198.0),      # near (rear) hip
        # Authentic raised boxer/brawler guard
        "be": (cx + 50.0 * b, hy + 108.0),      # lead elbow
        "bhand": (cx + 82.0 * b, hy + 62.0),    # lead fist forward-high
        "fe": (cx - 18.0 * b, hy + 124.0),      # rear elbow tight to ribs
        "fhand": (cx + 28.0 * b, hy + 72.0),    # rear fist guarding jaw
        # Grounded sunk-knee athletic brawler base
        "bk": (cx + 48.0 * b, hy + 306.0),      # lead knee bent forward
        "bfoot": (cx + 56.0 * b, FOOT_Y - 12.0),
        "fk": (cx - 38.0 * b, hy + 310.0),      # rear knee bent
        "ffoot": (cx - 56.0 * b, FOOT_Y - 12.0),
        "bfoot_angle": 0.0,
        "ffoot_angle": 0.0,
        "bhand_open": False,
        "fhand_open": False,
        "prop": None,
        "prop_hand": "front",
        "prop_angle": 0.0,
        "prop_offset": (0.0, 0.0),
        "streaks": [],
        "lying": False,
    }


def shift_body(p: dict, dx: float = 0.0, dy: float = 0.0, move_feet: bool = False) -> None:
    keys = ["head", "bs", "fs", "bh", "fh", "be", "bhand", "fe", "fhand", "bk", "fk"]
    if move_feet:
        keys += ["bfoot", "ffoot"]
    for k in keys:
        x, y = p[k]
        p[k] = (x + dx, y + dy)
    if not move_feet:
        for k in ("bfoot", "ffoot"):
            x, y = p[k]
            p[k] = (x + dx, y)


def set_leg(p: dict, side: str, foot, knee=None, angle: float = 0.0) -> None:
    hip = p["bh"] if side == "b" else p["fh"]
    if knee is None:
        knee = ((hip[0] + foot[0]) * 0.5 + 14.0, (hip[1] + foot[1]) * 0.5 - 4.0)
    p["bk" if side == "b" else "fk"] = knee
    p["bfoot" if side == "b" else "ffoot"] = foot
    p["bfoot_angle" if side == "b" else "ffoot_angle"] = angle


# ---------------------------------------------------------------------------
# Anatomical Sculpted Part Renderers
# ---------------------------------------------------------------------------


def _draw_shoe(d: ImageDraw.ImageDraw, ankle: tuple[float, float], pal: dict,
               angle_deg: float = 0.0, is_back: bool = False) -> None:
    """Sculpted side-3/4 adult shoe/boot/sneaker with heel, instep, toe box, and sole."""
    ax, ay = ankle
    ang = math.radians(angle_deg)
    shoe_col = pal["shoes"]
    shoe_dark = shift_tone(shoe_col, 0.72, -0.4)
    shoe_hi = shift_tone(shoe_col, 1.18, 0.25)
    sole_col = pal["sole"]
    if is_back:
        shoe_col = shift_tone(shoe_col, 0.88, -0.2)

    style = pal["id"]
    if style == "tony":
        upper = [(-13, -10), (10, -8), (22, 0), (33, 3), (35, 9), (-14, 9), (-15, 0)]
        sole = [(-15, 8), (36, 8), (35, 13), (8, 13), (4, 11), (-4, 11), (-6, 13), (-15, 13)]
        toe_cap = [(19, 0), (32, 3), (34, 8), (18, 8)]
    elif style == "karen":
        upper = [(-11, -7), (8, -6), (20, 2), (31, 5), (32, 9), (-11, 9)]
        sole = [(-12, 8), (32, 8), (31, 11), (10, 11), (-2, 10), (-4, 13), (-12, 13)]
        toe_cap = [(20, 3), (30, 5), (31, 8), (19, 8)]
    elif style == "chad":
        upper = [(-12, -8), (9, -7), (21, 1), (32, 4), (33, 8), (-13, 8)]
        sole = [(-14, 7), (34, 7), (33, 12), (-14, 12)]
        toe_cap = [(20, 2), (31, 4), (32, 8), (19, 8)]
    else:
        upper = [(-12, -8), (9, -7), (21, 1), (33, 4), (34, 9), (-13, 9)]
        sole = [(-13, 8), (34, 8), (33, 12), (8, 12), (2, 10), (-4, 10), (-5, 12), (-13, 12)]
        toe_cap = [(20, 2), (32, 4), (33, 8), (19, 8)]

    def xform(pts):
        return [rot_pt((ax + x, ay + y), (ax, ay), ang) for x, y in pts]

    d.polygon(xform(upper), fill=rgba(shoe_col))
    d.polygon(xform(toe_cap), fill=rgba(shoe_hi if style != "chad" else shift_tone(shoe_col, 0.88)))
    heel = [(-13, -4), (-3, -2), (-4, 8), (-13, 8)]
    d.polygon(xform(heel), fill=rgba(shoe_dark, 150))
    d.polygon(xform(sole), fill=rgba(sole_col))
    if style == "chad":
        stripe = [(4, 0), (16, 4), (14, 6), (2, 3)]
        d.polygon(xform(stripe), fill=rgba((86, 112, 116)))
    elif style in ("dave", "tony"):
        for k in range(3):
            p1 = rot_pt((ax + 9 + k * 3.5, ay - 3 + k * 2.0), (ax, ay), ang)
            p2 = rot_pt((ax + 12 + k * 3.5, ay - 1 + k * 2.0), (ax, ay), ang)
            d.line([p1, p2], fill=rgba(shoe_dark, 200), width=2)


def _draw_hand(d: ImageDraw.ImageDraw, wrist: tuple[float, float], elbow: tuple[float, float],
               pal: dict, is_open: bool = False, scale: float = 1.0) -> None:
    """Sculpted realistic fist or open grabbing/shoving hand."""
    wx, wy = wrist
    dx = wx - elbow[0]
    dy = wy - elbow[1]
    ang = math.atan2(dy, dx)
    skin = pal["skin"]
    skin_sh = pal["skin_shade"]
    skin_hi = pal["skin_hi"]
    s = scale * (0.95 + 0.14 * (pal["bulk"] - 1.0))

    if is_open:
        palm = [
            (-5 * s, -9 * s), (10 * s, -10 * s), (22 * s, -7 * s),
            (24 * s, -2 * s), (21 * s, 5 * s), (11 * s, 9 * s),
            (-2 * s, 10 * s), (-6 * s, 5 * s),
        ]
        thumb = [(1 * s, -9 * s), (11 * s, -15 * s), (16 * s, -12 * s), (9 * s, -6 * s)]
        d.polygon([rot_pt((wx + x, wy + y), (wx, wy), ang) for x, y in palm], fill=rgba(skin))
        d.polygon([rot_pt((wx + x, wy + y), (wx, wy), ang) for x, y in thumb], fill=rgba(skin_hi))
        for fy in (-4, 0, 4):
            p1 = rot_pt((wx + 11 * s, wy + fy * s), (wx, wy), ang)
            p2 = rot_pt((wx + 21 * s, wy + (fy + 0.6) * s), (wx, wy), ang)
            d.line([p1, p2], fill=rgba(skin_sh, 195), width=2)
    else:
        fist = [
            (-5 * s, -9 * s), (8 * s, -11 * s), (17 * s, -8 * s),
            (18 * s, 3 * s), (13 * s, 10 * s), (1 * s, 11 * s),
            (-6 * s, 7 * s),
        ]
        knuckle_ridge = [(9 * s, -10 * s), (16 * s, -7 * s), (16 * s, 2 * s), (10 * s, 3 * s)]
        thumb_wrap = [(0 * s, 2 * s), (11 * s, 1 * s), (12 * s, 8 * s), (1 * s, 10 * s)]
        d.polygon([rot_pt((wx + x, wy + y), (wx, wy), ang) for x, y in fist], fill=rgba(skin))
        d.polygon([rot_pt((wx + x, wy + y), (wx, wy), ang) for x, y in knuckle_ridge],
                  fill=rgba(skin_hi, 175))
        d.polygon([rot_pt((wx + x, wy + y), (wx, wy), ang) for x, y in thumb_wrap],
                  fill=rgba(skin_sh, 155))
        for fy in (-4.5, -0.5, 3.5):
            p1 = rot_pt((wx + 8 * s, wy + fy * s), (wx, wy), ang)
            p2 = rot_pt((wx + 15 * s, wy + fy * s), (wx, wy), ang)
            d.line([p1, p2], fill=rgba(skin_sh, 170), width=2)


def _render_leg_layer(pal: dict, hip, knee, ankle, foot_angle: float,
                      is_back: bool) -> Image.Image:
    """Render one complete leg (thigh + knee + calf + cuff + shoe) as a unified shaded layer."""
    layer = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    b = pal["bulk"]
    pants = pal["pants"]
    pants_dark = pal["pants_dark"]
    pants_hi = shift_tone(pants, 1.16, 0.2)

    _draw_shoe(d, ankle, pal, angle_deg=foot_angle, is_back=is_back)

    # Slimmer realistic hip radius so thighs flow smoothly out of the pelvis/jacket hem
    r_hip = 17.5 * b
    r_knee = 13.6 * b
    r_ankle = 10.2 * b
    if pal["id"] == "karen":
        r_hip *= 0.90
        r_knee *= 0.88
        r_ankle *= 0.86
    elif pal["id"] == "tony":
        r_hip *= 1.04
        r_knee *= 1.05
        r_ankle *= 1.06

    thigh_poly = tapered_limb_polygon(
        hip, knee, r_hip, r_knee,
        bulge_pos=0.40, bulge_front=0.14, bulge_back=0.10,
        cap_start=0.58, cap_end=0.70,
    )
    shin_poly = tapered_limb_polygon(
        knee, ankle, r_knee * 0.96, r_ankle,
        bulge_pos=0.32, bulge_front=0.05, bulge_back=0.17,
        cap_start=0.70, cap_end=0.35,
    )

    d.polygon(thigh_poly, fill=rgba(pants))
    d.polygon(shin_poly, fill=rgba(pants))
    kr = r_knee * 0.96
    d.ellipse([knee[0] - kr, knee[1] - kr, knee[0] + kr, knee[1] + kr], fill=rgba(pants))

    def paint_trouser_details(od: ImageDraw.ImageDraw) -> None:
        if pal["id"] == "chad":
            od.line([lerp_pt(hip, knee, 0.18), lerp_pt(hip, knee, 0.82)],
                    fill=rgba(pants_hi, 115), width=int(10 * b))
        else:
            od.line([lerp_pt(hip, knee, 0.16), knee, lerp_pt(knee, ankle, 0.88)],
                    fill=rgba(pants_hi, 90), width=3)

        # Natural fabric tension creases behind knee bend
        v1 = (hip[0] - knee[0], hip[1] - knee[1])
        v2 = (ankle[0] - knee[0], ankle[1] - knee[1])
        l1 = math.hypot(*v1) or 1.0
        l2 = math.hypot(*v2) or 1.0
        bx = v1[0] / l1 + v2[0] / l2
        by = v1[1] / l1 + v2[1] / l2
        bl = math.hypot(bx, by) or 1.0
        bx, by = bx / bl, by / bl
        px, py = -by, bx
        for off in (-5.0, 0.0, 5.0):
            c0 = (knee[0] + bx * (r_knee * 0.72) + px * off,
                  knee[1] + by * (r_knee * 0.72) + py * off)
            c1 = (knee[0] - bx * (r_knee * 0.16) + px * (off * 1.35),
                  knee[1] - by * (r_knee * 0.16) + py * (off * 1.35))
            od.line([c0, c1], fill=rgba(pants_dark, 175), width=3)

        # Trouser cuff over shoe
        dx = ankle[0] - knee[0]
        dy = ankle[1] - knee[1]
        al = math.hypot(dx, dy) or 1.0
        ux, uy = dx / al, dy / al
        nx, ny = -uy, ux
        cuff_a = (ankle[0] - nx * r_ankle * 1.05, ankle[1] - ny * r_ankle * 1.05)
        cuff_b = (ankle[0] + nx * r_ankle * 1.05, ankle[1] + ny * r_ankle * 1.05)
        od.line([cuff_a, cuff_b], fill=rgba(pants_dark, 210), width=5)
        if pal["id"] == "chad":
            od.line([(cuff_a[0] - ux * 5, cuff_a[1] - uy * 5),
                     (cuff_b[0] - ux * 5, cuff_b[1] - uy * 5)],
                    fill=rgba((148, 160, 182), 185), width=4)

    draw_clipped_overlay(layer, paint_trouser_details)

    if is_back:
        layer = darken_layer(layer, 0.89)

    return shade_and_ink_layer(
        layer,
        ink_color=pal["ink"],
        shadow_strength=0.36 if not is_back else 0.42,
        highlight_strength=0.18 if not is_back else 0.10,
        rim_strength=0.16 if not is_back else 0.06,
    )


def _render_arm_layer(pal: dict, shoulder, elbow, hand, is_back: bool,
                      hand_open: bool = False, draw_hand: bool = True) -> Image.Image:
    """Render one complete arm (deltoid + upper arm + elbow + forearm + cuff + hand)."""
    layer = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    b = pal["bulk"]
    shirt = pal["shirt"]
    shirt_dark = pal["shirt_dark"]
    shirt_hi = pal["shirt_hi"]
    skin = pal["skin"]
    skin_sh = pal["skin_shade"]
    rolled = pal["sleeve"] == "rolled"

    r_sh = 16.0 * b
    r_el = 12.2 * b
    r_wr = 8.8 * b
    if pal["id"] == "karen":
        r_sh *= 0.88
        r_el *= 0.86
        r_wr *= 0.84

    forearm_col = skin if rolled else shirt
    forearm_poly = tapered_limb_polygon(
        elbow, hand, r_el * (1.02 if rolled else 0.96), r_wr,
        bulge_pos=0.28, bulge_front=0.16 if rolled else 0.10, bulge_back=0.12,
        cap_start=0.72, cap_end=0.45,
    )
    d.polygon(forearm_poly, fill=rgba(forearm_col))

    upper_poly = tapered_limb_polygon(
        shoulder, elbow, r_sh, r_el,
        bulge_pos=0.38, bulge_front=0.14, bulge_back=0.14,
        cap_start=0.84, cap_end=0.76,
    )
    d.polygon(upper_poly, fill=rgba(shirt))
    d.ellipse([shoulder[0] - r_sh, shoulder[1] - r_sh,
               shoulder[0] + r_sh, shoulder[1] + r_sh], fill=rgba(shirt))
    if not rolled:
        er = r_el * 0.96
        d.ellipse([elbow[0] - er, elbow[1] - er, elbow[0] + er, elbow[1] + er], fill=rgba(shirt))

    if draw_hand:
        _draw_hand(d, hand, elbow, pal, is_open=hand_open)

    def paint_arm_details(od: ImageDraw.ImageDraw) -> None:
        dx = hand[0] - elbow[0]
        dy = hand[1] - elbow[1]
        fl = math.hypot(dx, dy) or 1.0
        ux, uy = dx / fl, dy / fl
        nx, ny = -uy, ux

        if rolled:
            cuff_p = lerp_pt(elbow, hand, 0.16)
            p_a = (cuff_p[0] - nx * r_el * 1.18, cuff_p[1] - ny * r_el * 1.18)
            p_b = (cuff_p[0] + nx * r_el * 1.18, cuff_p[1] + ny * r_el * 1.18)
            sh_a = (p_a[0] + ux * 6, p_a[1] + uy * 6)
            sh_b = (p_b[0] + ux * 6, p_b[1] + uy * 6)
            od.line([sh_a, sh_b], fill=rgba(skin_sh, 200), width=6)
            od.line([p_a, p_b], fill=rgba(shirt_hi, 235), width=9)
            od.line([(p_a[0] - ux * 4, p_a[1] - uy * 4), (p_b[0] - ux * 4, p_b[1] - uy * 4)],
                    fill=rgba(shirt_dark, 200), width=3)
            od.line([lerp_pt(elbow, hand, 0.28), lerp_pt(elbow, hand, 0.78)],
                    fill=rgba(skin_sh, 105), width=5)
            wp = lerp_pt(elbow, hand, 0.84)
            od.line([(wp[0] - nx * r_wr, wp[1] - ny * r_wr),
                     (wp[0] + nx * r_wr, wp[1] + ny * r_wr)],
                    fill=rgba((64, 66, 72), 215), width=5)
        else:
            wp = lerp_pt(elbow, hand, 0.90)
            p_a = (wp[0] - nx * r_wr * 1.12, wp[1] - ny * r_wr * 1.12)
            p_b = (wp[0] + nx * r_wr * 1.12, wp[1] + ny * r_wr * 1.12)
            cuff_col = shirt_dark if pal["id"] != "chad" else shift_tone(shirt, 0.78)
            od.line([p_a, p_b], fill=rgba(cuff_col, 225), width=6 if pal["id"] == "chad" else 4)
            v1 = (shoulder[0] - elbow[0], shoulder[1] - elbow[1])
            v2 = (hand[0] - elbow[0], hand[1] - elbow[1])
            l1 = math.hypot(*v1) or 1.0
            l2 = math.hypot(*v2) or 1.0
            bx = v1[0] / l1 + v2[0] / l2
            by = v1[1] / l1 + v2[1] / l2
            bl = math.hypot(bx, by) or 1.0
            bx, by = bx / bl, by / bl
            px, py = -by, bx
            for off in (-5.0, 0.0, 5.0):
                c0 = (elbow[0] + bx * r_el * 0.75 + px * off,
                      elbow[1] + by * r_el * 0.75 + py * off)
                c1 = (elbow[0] - bx * r_el * 0.15 + px * (off * 1.3),
                      elbow[1] - by * r_el * 0.15 + py * (off * 1.3))
                od.line([c0, c1], fill=rgba(shirt_dark, 175), width=3)

        od.line([lerp_pt(shoulder, elbow, 0.22), lerp_pt(shoulder, elbow, 0.65)],
                fill=rgba(shirt_dark, 95), width=4)

    draw_clipped_overlay(layer, paint_arm_details)

    if is_back:
        layer = darken_layer(layer, 0.88)

    return shade_and_ink_layer(
        layer,
        ink_color=pal["ink"],
        shadow_strength=0.35 if not is_back else 0.42,
        highlight_strength=0.20 if not is_back else 0.10,
        rim_strength=0.16 if not is_back else 0.06,
    )


def _render_torso_layer(pal: dict, p: dict) -> Image.Image:
    """Broad, anatomically solid 3/4 adult torso that NEVER collapses during twists.

    Rendered on top of both leg layers so trouser waistlines, belts, blazers,
    work jackets, and hoodie hems naturally overlap the hips with zero hip-socket seams.
    """
    layer = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    b = pal["bulk"]
    cid = pal["id"]
    shirt = pal["shirt"]
    shirt_d = pal["shirt_dark"]
    shirt_hi = pal["shirt_hi"]
    pants = pal["pants"]
    pants_d = pal["pants_dark"]
    belt = pal["belt"]

    fs = p["fs"]
    bs = p["bs"]
    fh = p["fh"]
    bh = p["bh"]

    # Spine axis: shoulder midpoint -> hip midpoint
    s_mid = lerp_pt(fs, bs, 0.5)
    h_mid = lerp_pt(fh, bh, 0.5)
    axis_dx = h_mid[0] - s_mid[0]
    axis_dy = h_mid[1] - s_mid[1]
    t_len = math.hypot(axis_dx, axis_dy) or 1.0
    ux, uy = axis_dx / t_len, axis_dy / t_len      # spine down
    rx, ry = -uy, ux                               # perpendicular facing (+x in upright)
    if (bs[0] - fs[0]) * rx + (bs[1] - fs[1]) * ry < 0:
        rx, ry = -rx, -ry

    # Guaranteed solid anatomical ribcage/chest/waist/pelvis half-widths (never pinches!)
    half_sh = max(32.0 * b, math.hypot(bs[0] - fs[0], bs[1] - fs[1]) * 0.56)
    chest_hw = (36.0 if cid == "tony" else (29.5 if cid == "karen" else 33.5)) * b
    waist_hw = (31.0 if cid == "tony" else (23.0 if cid == "karen" else 27.5)) * b
    hip_hw = max(29.0 * b, math.hypot(bh[0] - fh[0], bh[1] - fh[1]) * 0.52 + 12.0 * b)

    # Trapezius & shoulder line
    sh_l = (s_mid[0] - rx * half_sh - ux * 6.0, s_mid[1] - ry * half_sh - uy * 6.0)
    sh_r = (s_mid[0] + rx * half_sh - ux * 6.0, s_mid[1] + ry * half_sh - uy * 6.0)
    trap_l = (s_mid[0] - rx * 14.0 * b - ux * 18.0, s_mid[1] - ry * 14.0 * b - uy * 18.0)
    trap_r = (s_mid[0] + rx * 14.0 * b - ux * 18.0, s_mid[1] + ry * 14.0 * b - uy * 18.0)

    chest_l = (s_mid[0] + ux * t_len * 0.24 - rx * chest_hw,
               s_mid[1] + uy * t_len * 0.24 - ry * chest_hw)
    chest_r = (s_mid[0] + ux * t_len * 0.24 + rx * chest_hw,
               s_mid[1] + uy * t_len * 0.24 + ry * chest_hw)
    waist_l = (s_mid[0] + ux * t_len * 0.72 - rx * waist_hw,
               s_mid[1] + uy * t_len * 0.72 - ry * waist_hw)
    waist_r = (s_mid[0] + ux * t_len * 0.72 + rx * waist_hw,
               s_mid[1] + uy * t_len * 0.72 + ry * waist_hw)
    hip_l = (h_mid[0] - rx * hip_hw, h_mid[1] - ry * hip_hw)
    hip_r = (h_mid[0] + rx * hip_hw, h_mid[1] + ry * hip_hw)
    pelv_l = (hip_l[0] + ux * 20.0 + rx * 2.0, hip_l[1] + uy * 20.0 + ry * 2.0)
    pelv_r = (hip_r[0] + ux * 20.0 - rx * 2.0, hip_r[1] + uy * 20.0 - ry * 2.0)
    crotch = (h_mid[0] + ux * 26.0, h_mid[1] + uy * 26.0)

    # 1. Trouser seat / pelvis block (smoothly bridges both legs under the belt/hem!)
    pelvis_poly = [waist_l, waist_r, hip_r, pelv_r, crotch, pelv_l, hip_l]
    d.polygon(pelvis_poly, fill=rgba(pants))

    # 2. Upper garment (blazers / work jackets / hoodies drape cleanly past the waist!)
    hem_drop = 0.84 if cid == "dave" else (1.04 if cid == "karen" else 0.98)
    hem_t = (hem_drop - 0.72) / 0.28
    hem_l = lerp_pt(waist_l, hip_l, hem_t)
    hem_r = lerp_pt(waist_r, hip_r, hem_t)
    # Slight blazer/jacket hem flare
    if cid in ("karen", "tony"):
        hem_l = (hem_l[0] - rx * 3.5, hem_l[1] - ry * 3.5)
        hem_r = (hem_r[0] + rx * 3.5, hem_r[1] + ry * 3.5)

    torso_poly = [sh_l, trap_l, trap_r, sh_r, chest_r, waist_r, hem_r, hem_l, waist_l, chest_l]
    d.polygon(torso_poly, fill=rgba(shirt))

    # Draped hood behind Chad's collar
    if cid == "chad":
        hood_pts = [
            (sh_l[0] - rx * 6 - ux * 2, sh_l[1] - ry * 6 - uy * 2),
            (trap_l[0] - rx * 14 - ux * 16, trap_l[1] - ry * 14 - uy * 16),
            (trap_r[0] - rx * 4 - ux * 10, trap_r[1] - ry * 4 - uy * 10),
            (sh_r[0], sh_r[1]),
            (chest_l[0], chest_l[1]),
        ]
        d.polygon(hood_pts, fill=rgba(shirt_d))

    # 3. Clipped outfit tailoring, lapels, tie, zipper, pockets, belt, creases & AO
    def paint_torso_details(od: ImageDraw.ImageDraw) -> None:
        # 3/4 sternum line offset toward the facing side (+rx)
        sternum_top = (s_mid[0] + rx * 11.0 * b - ux * 8, s_mid[1] + ry * 11.0 * b - uy * 8)
        sternum_bot = (h_mid[0] + rx * 10.0 * b - ux * 18, h_mid[1] + ry * 10.0 * b - uy * 18)

        # Belt (visible on Dave at waist, subtle peek on Tony)
        if cid in ("dave", "tony"):
            b_l = lerp_pt(waist_l, hip_l, 0.42)
            b_r = lerp_pt(waist_r, hip_r, 0.42)
            od.line([b_l, b_r], fill=rgba(belt), width=11)
            od.line([(b_l[0] + ux * 7, b_l[1] + uy * 7), (b_r[0] + ux * 7, b_r[1] + uy * 7)],
                    fill=rgba(pants_d, 190), width=5)
            bk = lerp_pt(b_l, b_r, 0.64)
            od.polygon([
                (bk[0] - rx * 7 - ux * 5, bk[1] - ry * 7 - uy * 5),
                (bk[0] + rx * 7 - ux * 5, bk[1] + ry * 7 - uy * 5),
                (bk[0] + rx * 7 + ux * 5, bk[1] + ry * 7 + uy * 5),
                (bk[0] - rx * 7 + ux * 5, bk[1] - ry * 7 + uy * 5),
            ], fill=rgba(pal["accent2"] if cid == "dave" else pal["accent"]))

        if cid == "dave":
            od.line([sternum_top, sternum_bot], fill=rgba(shirt_d, 175), width=3)
            # Subtle realistic shirt wrinkles at waist/ribs
            for frac in (0.34, 0.56, 0.74):
                p0 = lerp_pt(chest_l, waist_l, frac)
                p1 = lerp_pt(sternum_top, sternum_bot, frac + 0.04)
                od.line([p0, lerp_pt(p0, p1, 0.65)], fill=rgba(shirt_d, 125), width=3)
            # Crisp dress-shirt collar flaps
            c_left = [
                (sternum_top[0] - rx * 20 - ux * 4, sternum_top[1] - ry * 20 - uy * 4),
                (sternum_top[0] - rx * 2 + ux * 10, sternum_top[1] - ry * 2 + uy * 10),
                (sternum_top[0] - rx * 16 + ux * 18, sternum_top[1] - ry * 16 + uy * 18),
            ]
            c_right = [
                (sternum_top[0] + rx * 16 - ux * 4, sternum_top[1] + ry * 16 - uy * 4),
                (sternum_top[0] + rx * 2 + ux * 10, sternum_top[1] + ry * 2 + uy * 10),
                (sternum_top[0] + rx * 15 + ux * 17, sternum_top[1] + ry * 15 + uy * 17),
            ]
            od.polygon(c_left, fill=rgba(shirt_hi), outline=rgba(shirt_d, 185))
            od.polygon(c_right, fill=rgba(shirt_hi), outline=rgba(shirt_d, 185))
            # Loosened burgundy tie + soft cast shadow
            tie_col = pal["accent"]
            tie_dark = shift_tone(tie_col, 0.65, -0.3)
            tie_top = (sternum_top[0] + ux * 8, sternum_top[1] + uy * 8)
            tie_mid = lerp_pt(sternum_top, sternum_bot, 0.80)
            tie_tip = (sternum_bot[0] + ux * 10 + rx * 3, sternum_bot[1] + uy * 10 + ry * 3)
            od.polygon([
                (tie_top[0] - rx * 3 + ux * 2, tie_top[1] - ry * 3 + uy * 2),
                (tie_top[0] + rx * 7 + ux * 2, tie_top[1] + ry * 7 + uy * 2),
                (tie_mid[0] + rx * 11 + ux * 3, tie_mid[1] + ry * 11 + uy * 3),
                (tie_tip[0] + rx * 4 + ux * 3, tie_tip[1] + ry * 4 + uy * 3),
                (tie_mid[0] - rx * 4 + ux * 3, tie_mid[1] - ry * 4 + uy * 3),
            ], fill=rgba(shirt_d, 155))
            od.polygon([
                (tie_top[0] - rx * 5, tie_top[1] - ry * 5),
                (tie_top[0] + rx * 5, tie_top[1] + ry * 5),
                (tie_mid[0] + rx * 8.5, tie_mid[1] + ry * 8.5),
                tie_tip,
                (tie_mid[0] - rx * 6, tie_mid[1] - ry * 6),
            ], fill=rgba(tie_col))
            od.line([
                (tie_top[0] - rx * 5 + ux * 10, tie_top[1] - ry * 5 + uy * 10),
                (tie_top[0] + rx * 5 + ux * 10, tie_top[1] + ry * 5 + uy * 10),
            ], fill=rgba(tie_dark, 220), width=3)
            for tf in (0.28, 0.50, 0.72):
                tp = lerp_pt(tie_top, tie_mid, tf)
                od.line([(tp[0] - rx * 5, tp[1] - ry * 5 - ux * 2),
                         (tp[0] + rx * 6, tp[1] + ry * 6 + ux * 3)],
                        fill=rgba(shift_tone(tie_col, 1.35, 0.2), 140), width=2)

        elif cid == "karen":
            # Ivory blouse V-neck under structured plum blazer
            v_bot = lerp_pt(sternum_top, sternum_bot, 0.50)
            od.polygon([
                (sternum_top[0] - rx * 16 - ux * 6, sternum_top[1] - ry * 16 - uy * 6),
                (sternum_top[0] + rx * 16 - ux * 6, sternum_top[1] + ry * 16 - uy * 6),
                (v_bot[0] + rx * 2, v_bot[1] + ry * 2),
            ], fill=rgba(pal["accent2"]))
            od.line([(sternum_top[0] - rx * 14, sternum_top[1] - ry * 14), v_bot],
                    fill=rgba((182, 174, 162), 195), width=4)
            # Tailored notched blazer lapels
            lap_l = [
                (sternum_top[0] - rx * 16 - ux * 6, sternum_top[1] - ry * 16 - uy * 6),
                (sternum_top[0] - rx * 26 + ux * 28, sternum_top[1] - ry * 26 + uy * 28),
                (v_bot[0] - rx * 4, v_bot[1] - ry * 4),
            ]
            lap_r = [
                (sternum_top[0] + rx * 16 - ux * 6, sternum_top[1] + ry * 16 - uy * 6),
                (sternum_top[0] + rx * 22 + ux * 26, sternum_top[1] + ry * 22 + uy * 26),
                (v_bot[0] + rx * 4, v_bot[1] + ry * 4),
            ]
            od.polygon(lap_l, fill=rgba(shirt_hi), outline=rgba(shirt_d, 210))
            od.polygon(lap_r, fill=rgba(shirt_hi), outline=rgba(shirt_d, 210))
            od.line([v_bot, (sternum_bot[0] + ux * 26, sternum_bot[1] + uy * 26)],
                    fill=rgba(shirt_d, 220), width=3)
            btn = lerp_pt(v_bot, sternum_bot, 0.25)
            od.ellipse([btn[0] - 4, btn[1] - 4, btn[0] + 4, btn[1] + 4], fill=rgba(pal["accent"]))
            od.line([(hem_l[0] + ux * 4, hem_l[1] + uy * 4), (hem_r[0] + ux * 4, hem_r[1] + uy * 4)],
                    fill=rgba(pants_d, 215), width=6)

        elif cid == "tony":
            v_bot = lerp_pt(sternum_top, sternum_bot, 0.26)
            od.polygon([
                (sternum_top[0] - rx * 18 - ux * 6, sternum_top[1] - ry * 18 - uy * 6),
                (sternum_top[0] + rx * 18 - ux * 6, sternum_top[1] + ry * 18 - uy * 6),
                v_bot,
            ], fill=rgba(pal["accent2"]))
            col_l = [
                (sternum_top[0] - rx * 18 - ux * 6, sternum_top[1] - ry * 18 - uy * 6),
                (sternum_top[0] - rx * 34 + ux * 18, sternum_top[1] - ry * 34 + uy * 18),
                (v_bot[0] - rx * 8, v_bot[1] - ry * 8),
            ]
            col_r = [
                (sternum_top[0] + rx * 18 - ux * 6, sternum_top[1] + ry * 18 - uy * 6),
                (sternum_top[0] + rx * 28 + ux * 18, sternum_top[1] + ry * 28 + uy * 18),
                (v_bot[0] + rx * 6, v_bot[1] + ry * 6),
            ]
            od.polygon(col_l, fill=rgba(shirt_hi), outline=rgba(shirt_d, 220))
            od.polygon(col_r, fill=rgba(shirt_hi), outline=rgba(shirt_d, 220))
            zip_bot = (sternum_bot[0] + ux * 22, sternum_bot[1] + uy * 22)
            od.line([v_bot, zip_bot], fill=rgba(shirt_d, 230), width=7)
            od.line([v_bot, zip_bot], fill=rgba(pal["accent"], 215), width=3)
            pk = lerp_pt(chest_l, sternum_top, 0.44)
            od.polygon([
                (pk[0] - rx * 14 + ux * 14, pk[1] - ry * 14 + uy * 14),
                (pk[0] + rx * 12 + ux * 14, pk[1] + ry * 12 + uy * 14),
                (pk[0] + rx * 12 + ux * 40, pk[1] + ry * 12 + uy * 40),
                (pk[0] - rx * 14 + ux * 40, pk[1] - ry * 14 + uy * 40),
            ], fill=rgba(shirt_d, 145), outline=rgba(shirt_d, 220))
            snap = (pk[0] - rx * 1 + ux * 20, pk[1] - ry * 1 + uy * 20)
            od.ellipse([snap[0] - 3, snap[1] - 3, snap[0] + 3, snap[1] + 3], fill=rgba(pal["accent"]))
            od.line([hem_l, hem_r], fill=rgba(shirt_d, 235), width=8)

        elif cid == "chad":
            zip_top = (sternum_top[0] + ux * 6, sternum_top[1] + uy * 6)
            zip_bot = (sternum_bot[0] + ux * 22, sternum_bot[1] + uy * 22)
            od.line([zip_top, zip_bot], fill=rgba(shirt_d, 220), width=4)
            od.line([zip_top, zip_bot], fill=rgba((146, 154, 160), 170), width=1)
            p_top_l = lerp_pt(chest_l, waist_l, 0.72)
            p_top_r = lerp_pt(chest_r, waist_r, 0.72)
            p_bot_l = lerp_pt(waist_l, hem_l, 0.80)
            p_bot_r = lerp_pt(waist_r, hem_r, 0.80)
            od.polygon([
                lerp_pt(p_top_l, p_top_r, 0.14),
                lerp_pt(p_top_l, p_top_r, 0.88),
                lerp_pt(p_bot_l, p_bot_r, 0.94),
                lerp_pt(p_bot_l, p_bot_r, 0.08),
            ], fill=rgba(shirt_d, 155), outline=rgba(shirt_d, 220))
            for side_off in (-7.5, 7.5):
                ds0 = (sternum_top[0] + rx * side_off + ux * 6,
                       sternum_top[1] + ry * side_off + uy * 6)
                ds1 = (sternum_top[0] + rx * (side_off * 1.15) + ux * 44,
                       sternum_top[1] + ry * (side_off * 1.15) + uy * 44)
                od.line([ds0, ds1], fill=rgba(pal["accent2"], 230), width=3)
                od.ellipse([ds1[0] - 2.5, ds1[1] - 2.5, ds1[0] + 2.5, ds1[1] + 2.5],
                           fill=rgba((158, 154, 144)))
            od.line([hem_l, hem_r], fill=rgba(shirt_d, 235), width=11)

        # Soft AO shadows under chin/collar and under front arm/shoulder
        od.ellipse([s_mid[0] - 20, s_mid[1] - 18, s_mid[0] + 22, s_mid[1] + 8],
                   fill=rgba(shirt_d, 105))
        od.ellipse([fs[0] - 16 * b, fs[1] - 10 * b, fs[0] + 22 * b, fs[1] + 26 * b],
                   fill=rgba(shirt_d, 85))

    draw_clipped_overlay(layer, paint_torso_details)

    return shade_and_ink_layer(
        layer,
        ink_color=pal["ink"],
        shadow_strength=0.33,
        highlight_strength=0.18,
        rim_strength=0.15,
    )


def _render_head_layer(pal: dict, p: dict) -> Image.Image:
    """Sculpted realistic adult neck & 3/4 head with soft painterly skin planes (NO X eyes!)."""
    layer = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    hx, hy = p["head"]
    ang = math.radians(p.get("head_tilt", 0.0))
    expr = p.get("expr", "focused")
    cid = pal["id"]

    skin = pal["skin"]
    skin_sh = pal["skin_shade"]
    skin_deep = shift_tone(skin_sh, 0.78, -0.25)
    skin_hi = pal["skin_hi"]
    hair = pal["hair"]
    hair_hi = pal["hair_hi"]
    hair_dark = pal["hair_dark"]
    ink = pal["ink"]

    def hp(x: float, y: float) -> tuple[float, float]:
        return rot_pt((hx + x, hy + y), (hx, hy), ang)

    def hpoly(pts):
        return [hp(x, y) for x, y in pts]

    # 1. Grounded strong adult neck (compact, proportional — never stretched!)
    s_mid = lerp_pt(p["fs"], p["bs"], 0.5)
    neck_top = hp(-4.0, 18.0)
    neck_bot = (s_mid[0] - 2.0, s_mid[1] - 2.0)
    neck_r = 13.5 * (0.90 if cid == "karen" else (1.16 if cid == "tony" else 1.02))
    neck_poly = tapered_limb_polygon(neck_top, neck_bot, neck_r * 0.94, neck_r * 1.18,
                                     bulge_front=0.04, bulge_back=0.05,
                                     cap_start=0.5, cap_end=0.55)
    d.polygon(neck_poly, fill=rgba(skin_sh))
    # Subtle sternocleidomastoid highlight + crisp jaw cast shadow onto neck
    d.line([hp(-10, 22), lerp_pt(neck_top, neck_bot, 0.85)], fill=rgba(skin, 165), width=5)
    d.polygon(hpoly([(-16, 18), (13, 18), (9, 31), (-16, 29)]), fill=rgba(skin_deep, 155))

    # 2. Back hair mass for Karen's angled bob
    if pal["style"] == "bob":
        back_bob = [
            (-28, -14), (-31, 10), (-26, 32), (-6, 34), (9, 24), (11, -14), (-11, -30),
        ]
        d.polygon(hpoly(back_bob), fill=rgba(hair_dark))

    # 3. Sculpted Adult Cranium + Angular Jaw + Chin + 3/4 Nose Profile (~64px tall x ~48px wide)
    jaw_w = 1.07 if cid == "tony" else (0.93 if cid == "karen" else 1.00)
    head_contour = [
        (-18 * jaw_w, -26),     # upper occiput
        (-4, -33),              # crown
        (12, -30),              # forehead top
        (21, -19),              # forehead slope
        (23, -10),              # brow ridge
        (21.5, -5),             # eye bridge
        (26.5, 4),              # nose tip
        (22.0, 9),              # under nose
        (23.0, 14),             # upper lip
        (21.0, 18),             # lower lip
        (21.5, 24),             # chin point
        (12 * jaw_w, 30),       # chin base
        (-2 * jaw_w, 28),       # jaw line
        (-15 * jaw_w, 20),      # jaw angle
        (-21 * jaw_w, 8),       # below ear
        (-24 * jaw_w, -7),      # back skull
    ]
    d.polygon(hpoly(head_contour), fill=rgba(skin))

    # 4. Soft painterly facial planes (blurred gently & clipped to skin — ZERO harsh smudges!)
    face_shade = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(face_shade)
    # Soft back-cheek / temple recess
    fd.polygon(hpoly([(-20 * jaw_w, -6), (-7, -2), (-4, 18), (-14 * jaw_w, 20), (-21 * jaw_w, 8)]),
               fill=rgba(skin_sh, 95))
    # Subtle warm cheekbone & forehead catchlights
    fd.polygon(hpoly([(4, -24), (18, -18), (18, -10), (5, -12)]), fill=rgba(skin_hi, 110))
    fd.polygon(hpoly([(5, 0), (17, 2), (15, 11), (3, 10)]), fill=rgba(skin_hi, 95))
    # Subtle soft eye-socket depth under brow ridge
    fd.polygon(hpoly([(4, -10), (20, -10), (19, -2), (5, -3)]), fill=rgba(skin_sh, 80))
    # Under-nose cast shadow
    fd.polygon(hpoly([(16, 5), (25, 5), (21, 9.5), (15, 7.5)]), fill=rgba(skin_deep, 130))
    face_shade = face_shade.filter(ImageFilter.GaussianBlur(2.2))
    # Clip soft facial shading to current layer alpha
    base_a = layer.getchannel("A")
    fs_a = face_shade.getchannel("A")
    from PIL import ImageChops
    face_shade.putalpha(ImageChops.darker(base_a, fs_a))
    layer.alpha_composite(face_shade)
    d = ImageDraw.Draw(layer)

    # Crisp subtle lower-lip shadow & Dave's faint tired under-eye line
    d.line([hp(12, 19), hp(19, 19)], fill=rgba(skin_deep, 115), width=2)
    if cid == "dave":
        d.line([hp(8, 1), hp(15, 1)], fill=rgba(skin_deep, 85), width=2)

    # Anatomical Ear
    ear = [(-17 * jaw_w, -4), (-23 * jaw_w, -3), (-22 * jaw_w, 9), (-15 * jaw_w, 10)]
    d.polygon(hpoly(ear), fill=rgba(skin))
    d.line([hp(-19 * jaw_w, 0), hp(-19 * jaw_w, 6)], fill=rgba(skin_sh, 195), width=2)
    if cid == "karen":
        ep = hp(-17 * jaw_w, 9)
        d.ellipse([ep[0] - 2.5, ep[1] - 2.5, ep[0] + 2.5, ep[1] + 2.5], fill=rgba(pal["accent"]))

    # 5. Realistic Eyes, Brows & Mouth (NEVER cartoon dots or X eyes!)
    brow_col = hair_dark if cid != "karen" else shift_tone(hair_dark, 0.72)
    if expr == "closed":
        d.line([hp(6, -5), hp(14, -4)], fill=rgba(ink, 230), width=3)
        d.line([hp(17, -5), hp(22, -4)], fill=rgba(ink, 220), width=2)
        d.line([hp(5, -10), hp(15, -9)], fill=rgba(brow_col, 220), width=3)
        d.line([hp(17, -10), hp(22, -9)], fill=rgba(brow_col, 210), width=2)
    else:
        eye_h = 3.2 if expr != "hurt" else 2.0
        d.polygon(hpoly([(7.5, -6), (15.0, -6), (14.0, -6 + eye_h), (8.5, -6 + eye_h)]),
                  fill=rgba((234, 232, 226), 215))
        ep_iris = hp(12.2, -4.5)
        d.ellipse([ep_iris[0] - 2.0, ep_iris[1] - 2.0, ep_iris[0] + 2.0, ep_iris[1] + 2.0],
                  fill=rgba(ink, 245))
        d.line([hp(7.0, -6.5), hp(15.5, -6.0)], fill=rgba(ink, 240), width=3)
        d.line([hp(18.0, -6.0), hp(22.0, -6.0)], fill=rgba(ink, 235), width=3)
        d.point(hp(20.0, -4.5), fill=rgba(ink, 235))

        brow_w = 5 if cid == "tony" else 3
        if expr == "hurt":
            d.line([hp(5, -10.5), hp(15, -12.5)], fill=rgba(brow_col, 235), width=brow_w)
            d.line([hp(17, -11.5), hp(22.5, -10.5)], fill=rgba(brow_col, 225), width=max(2, brow_w - 1))
        elif expr == "smug":
            d.line([hp(5, -11.5), hp(15, -9.8)], fill=rgba(brow_col, 235), width=brow_w)
            d.line([hp(17, -10.5), hp(22.5, -11.5)], fill=rgba(brow_col, 225), width=max(2, brow_w - 1))
        else:
            d.line([hp(5.5, -11.5), hp(15.5, -8.8)], fill=rgba(brow_col, 240), width=brow_w)
            d.line([hp(17.5, -8.8), hp(22.5, -11.0)], fill=rgba(brow_col, 230), width=max(2, brow_w - 1))

    if expr in ("grit", "hurt"):
        d.polygon(hpoly([(10.5, 12.5), (20.5, 13.0), (19.5, 17.0), (11.5, 16.5)]),
                  fill=rgba((62, 34, 34), 225))
        if expr == "grit":
            d.line([hp(12.0, 14.0), hp(19.5, 14.2)], fill=rgba((226, 220, 208), 220), width=2)
    elif expr == "smug":
        d.line([hp(9.5, 15.0), hp(16.0, 14.6), hp(21.0, 12.6)], fill=rgba(skin_deep, 230), width=3)
    else:
        lip_col = (146, 86, 92) if cid == "karen" else skin_deep
        d.line([hp(10.5, 14.5), hp(21.0, 14.2)], fill=rgba(lip_col, 230), width=3)

    # 6. Character Hair, Beard, Wire-Rim Glasses & Backwards Cap
    style = pal["style"]
    if style == "short":
        hair_mass = [
            (-25, -8), (-25, -22), (-15, -34), (2, -37), (17, -33), (24, -22),
            (19, -16), (8, -21), (-4, -20), (-12, -12), (-14, 1), (-20, 2), (-23, -2),
        ]
        d.polygon(hpoly(hair_mass), fill=rgba(hair))
        d.line([hp(-10, -30), hp(13, -26)], fill=rgba(hair_hi, 195), width=4)
        d.line([hp(-19, -21), hp(7, -24)], fill=rgba(hair_dark, 180), width=3)
        d.line([hp(-15, -14), hp(-4, -23)], fill=rgba(hair_hi, 155), width=3)

    elif style == "bob":
        bob_top = [
            (-27, -14), (-22, -30), (-6, -37), (13, -34), (24, -23),
            (21, -13), (8, -18), (-2, -15), (-6, 13), (-15, 27), (-27, 23), (-29, 4),
        ]
        d.polygon(hpoly(bob_top), fill=rgba(hair))
        d.polygon(hpoly([(15, -25), (25, -19), (21, -7), (15, -14)]), fill=rgba(hair_hi, 210))
        d.line([hp(-15, -31), hp(11, -27)], fill=rgba(hair_hi, 215), width=5)
        d.line([hp(-21, -10), hp(-15, 20)], fill=rgba(hair_dark, 175), width=4)
        d.line([hp(-12, -15), hp(-9, 18)], fill=rgba(hair_hi, 185), width=3)

    elif style == "bald":
        d.polygon(hpoly([(-9, -30), (9, -28), (13, -21), (-7, -22)]), fill=rgba(skin_hi, 135))
        d.polygon(hpoly([(-24, -8), (-20, -17), (-13, -6), (-15, 6), (-22, 4)]),
                  fill=rgba(hair, 85))
        beard = [
            (-17 * jaw_w, 4), (-13 * jaw_w, 10), (4, 15), (10, 9.5), (22.5, 9.5),
            (23.5, 14.5), (22.5, 25), (12 * jaw_w, 31), (-2 * jaw_w, 29),
            (-15 * jaw_w, 21), (-19 * jaw_w, 10),
        ]
        d.polygon(hpoly(beard), fill=rgba(hair))
        if expr in ("grit", "hurt"):
            d.polygon(hpoly([(10.5, 13.0), (20.5, 13.5), (19.5, 17.0), (11.5, 16.5)]),
                      fill=rgba((62, 34, 34), 235))
            if expr == "grit":
                d.line([hp(12.0, 14.2), hp(19.5, 14.4)], fill=rgba((226, 220, 208), 220), width=2)
        else:
            d.line([hp(10.5, 14.5), hp(21.0, 14.2)], fill=rgba(hair_dark, 245), width=3)
        for fx, fy in ((-11, 17), (-4, 22), (3, 25), (12, 24), (17, 19), (9, 11.5), (-6, 12.5)):
            d.line([hp(fx, fy), hp(fx + 3, fy + 2)], fill=rgba(hair_hi, 195), width=2)

    elif style == "cap":
        d.polygon(hpoly([(13, -21), (22, -18), (19, -11), (9, -15)]), fill=rgba(hair))
        d.polygon(hpoly([(-16, -10), (-12, 2), (-18, 4), (-21, -6)]), fill=rgba(hair))
        cap_col = pal["accent"]
        cap_dark = shift_tone(cap_col, 0.72, -0.3)
        cap_hi = shift_tone(cap_col, 1.24, 0.1)
        d.polygon(hpoly([(-19, -17), (-45, -13), (-47, -8), (-21, -9)]), fill=rgba(cap_dark))
        d.line([hp(-44, -12), hp(-21, -15)], fill=rgba(cap_hi, 175), width=3)
        d.polygon(hpoly([(-24, -10), (-24, -24), (-12, -36), (9, -36), (22, -24), (23, -15),
                         (7, -15), (-15, -12)]), fill=rgba(cap_col))
        d.line([hp(-2, -36), hp(2, -15)], fill=rgba(cap_dark, 200), width=2)
        d.line([hp(-15, -28), hp(13, -29)], fill=rgba(cap_hi, 120), width=4)
        btn = hp(-2, -36)
        d.ellipse([btn[0] - 3, btn[1] - 2.5, btn[0] + 3, btn[1] + 2.5], fill=rgba(cap_hi))
        d.polygon(hpoly([(13, -20), (22, -19), (22, -15), (13, -16)]), fill=rgba(cap_dark))

    if pal.get("glasses"):
        frame_col = (52, 56, 64)
        lens_glint = (232, 240, 248)
        d.polygon(hpoly([(6.0, -9.0), (16.5, -9.0), (16.5, -1.5), (6.0, -1.5)]),
                  fill=rgba(lens_glint, 46), outline=rgba(frame_col, 240))
        d.line([hp(7.5, -8.0), hp(10.5, -2.5)], fill=rgba(lens_glint, 130), width=2)
        d.polygon(hpoly([(18.5, -9.0), (23.5, -9.0), (23.5, -1.8), (18.5, -1.8)]),
                  fill=rgba(lens_glint, 40), outline=rgba(frame_col, 235))
        d.line([hp(16.5, -6.2), hp(18.5, -6.2)], fill=rgba(frame_col, 245), width=2)
        d.line([hp(6.0, -6.8), hp(-17 * jaw_w, -3.5)], fill=rgba(frame_col, 230), width=2)

    return shade_and_ink_layer(
        layer,
        ink_color=ink,
        shadow_strength=0.26,
        highlight_strength=0.16,
        rim_strength=0.16,
        key_offset=(6, 4),
        shadow_offset=(-9, -5),
    )


def _render_prop_layer(pal: dict, hand: tuple[float, float], kind: str | None,
                       angle_deg: float = 0.0, offset=(0.0, 0.0)) -> Image.Image:
    """Grounded, realistic illustrated props (banker's box, clipboard, plunger, laptop)."""
    layer = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    if kind is None:
        return layer
    d = ImageDraw.Draw(layer)
    px = hand[0] + offset[0]
    py = hand[1] + offset[1]
    ang = math.radians(angle_deg)

    def pp(x: float, y: float) -> tuple[float, float]:
        return rot_pt((px + x, py + y), (px, py), ang)

    def ppoly(pts):
        return [pp(x, y) for x, y in pts]

    if kind == "box":
        d.polygon(ppoly([(-22, -26), (-8, -42), (8, -38), (4, -24)]), fill=rgba((214, 192, 134)))
        d.polygon(ppoly([(-4, -26), (12, -44), (24, -36), (16, -24)]), fill=rgba((230, 224, 208)))
        d.polygon(ppoly([(-30, -26), (18, -26), (32, -34), (-16, -34)]), fill=rgba((136, 102, 66)))
        d.polygon(ppoly([(-30, -26), (18, -26), (18, 22), (-30, 22)]), fill=rgba((168, 130, 86)))
        d.polygon(ppoly([(18, -26), (32, -34), (32, 14), (18, 22)]), fill=rgba((122, 92, 58)))
        d.line([pp(-30, -14), pp(18, -14)], fill=rgba((146, 110, 70), 210), width=4)
        d.polygon(ppoly([(22, -12), (28, -15), (28, -9), (22, -6)]), fill=rgba((58, 42, 28)))
        d.polygon(ppoly([(-20, -10), (8, -10), (8, 8), (-20, 8)]), fill=rgba((232, 226, 212)))
        for ly in (-5, 0, 4):
            d.line([pp(-16, ly), pp(4 if ly != 4 else -4, ly)], fill=rgba((76, 72, 68), 210), width=2)

    elif kind == "clipboard":
        d.polygon(ppoly([(-19, -28), (19, -28), (19, 28), (-19, 28)]), fill=rgba((124, 86, 52)))
        for gx in (-14, -6, 4, 13):
            d.line([pp(gx, -27), pp(gx + 1, 27)], fill=rgba((96, 64, 38), 140), width=2)
        d.polygon(ppoly([(-14, -20), (14, -20), (14, 18), (8, 23), (-14, 23)]),
                  fill=rgba((228, 220, 200)))
        d.polygon(ppoly([(8, 23), (14, 18), (8, 18)]), fill=rgba((198, 190, 170)))
        d.line([pp(-10, -14), pp(8, -14)], fill=rgba((158, 52, 46), 220), width=3)
        for ly in (-7, -1, 5, 11, 16):
            end_x = 10 if ly < 15 else 2
            d.line([pp(-10, ly), pp(end_x, ly)], fill=rgba((84, 80, 76), 195), width=2)
        d.polygon(ppoly([(-10, -32), (10, -32), (12, -21), (-12, -21)]), fill=rgba((146, 150, 158)))
        d.line([pp(-9, -29), pp(9, -29)], fill=rgba((214, 218, 224), 220), width=3)
        d.line([pp(-11, -21), pp(11, -21)], fill=rgba((62, 64, 70), 220), width=2)

    elif kind == "plunger":
        handle = tapered_limb_polygon(pp(0, 32), pp(0, -50), 5.5, 4.8,
                                      bulge_front=0.02, bulge_back=0.02, cap_start=0.4, cap_end=0.4)
        d.polygon(handle, fill=rgba((142, 104, 66)))
        d.line([pp(-2, 26), pp(-2, -46)], fill=rgba((176, 136, 92), 160), width=3)
        bell = [
            (-8, -46), (8, -46), (16, -58), (24, -70), (26, -78),
            (-26, -78), (-24, -70), (-16, -58),
        ]
        d.polygon(ppoly(bell), fill=rgba((150, 56, 48)))
        d.polygon(ppoly([(-14, -60), (-4, -60), (-10, -75), (-20, -75)]),
                  fill=rgba((192, 92, 80), 150))
        d.line([pp(-25, -77), pp(25, -77)], fill=rgba((92, 32, 28), 230), width=5)

    elif kind == "laptop":
        d.polygon(ppoly([(-22, -32), (24, -36), (22, 0), (-20, 4)]), fill=rgba((118, 124, 134)))
        d.polygon(ppoly([(-19, -29), (21, -33), (19, -3), (-17, 1)]), fill=rgba((36, 44, 54)))
        d.polygon(ppoly([(-16, -26), (18, -30), (16, -6), (-14, -2)]), fill=rgba((78, 126, 146)))
        for k in range(3):
            d.line([pp(-11, -21 + k * 6), pp(8 - k * 3, -23 + k * 6)],
                   fill=rgba((186, 224, 236), 190), width=2)
        d.polygon(ppoly([(-26, 4), (26, 0), (32, 9), (-22, 13)]), fill=rgba((174, 180, 188)))
        d.polygon(ppoly([(-22, 13), (32, 9), (32, 13), (-22, 17)]), fill=rgba((102, 108, 118)))

    return shade_and_ink_layer(
        layer,
        ink_color=pal["ink"],
        shadow_strength=0.28,
        highlight_strength=0.18,
        rim_strength=0.16,
    )


def _draw_streaks(img: Image.Image, streaks: list[dict]) -> None:
    """Subtle, sleek graphic-novel air-cut motion streaks (never thick opaque wedges)."""
    if not streaks:
        return
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for st in streaks:
        p0 = st["p0"]
        p1 = st["p1"]
        col = st.get("color", (236, 228, 210))
        alpha = int(st.get("alpha", 130) * 0.72)
        w0 = st.get("w0", 1.2)
        w1 = st.get("w1", 3.6)
        dx = p1[0] - p0[0]
        dy = p1[1] - p0[1]
        l = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / l, dx / l
        poly = [
            (p0[0] + nx * w0, p0[1] + ny * w0),
            (p1[0] + nx * w1, p1[1] + ny * w1),
            (p1[0] - nx * w1, p1[1] - ny * w1),
            (p0[0] - nx * w0, p0[1] - ny * w0),
        ]
        d.polygon(poly, fill=rgba(col, alpha))
    ov = ov.filter(ImageFilter.GaussianBlur(1.2))
    img.alpha_composite(ov)


def draw_fighter_frame(pal: dict, pose: dict) -> Image.Image:
    """Render one fighter frame on 2x supersampled 384x576 canvas and downsample via LANCZOS."""
    canvas = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
    p = pose
    prop = p.get("prop")
    prop_hand = p.get("prop_hand", "front")
    prop_angle = p.get("prop_angle", 0.0)
    prop_offset = p.get("prop_offset", (0.0, 0.0))

    # Layer 1: Back arm (far/lead arm) + prop if held in back hand
    back_arm = _render_arm_layer(
        pal, p["bs"], p["be"], p["bhand"],
        is_back=True, hand_open=p.get("bhand_open", False),
    )
    canvas.alpha_composite(back_arm)
    if prop and prop_hand == "back":
        canvas.alpha_composite(_render_prop_layer(pal, p["bhand"], prop, prop_angle, prop_offset))

    # Layer 2: Back leg (far leg)
    back_leg = _render_leg_layer(
        pal, p["bh"], p["bk"], p["bfoot"],
        foot_angle=p.get("bfoot_angle", 0.0), is_back=True,
    )
    canvas.alpha_composite(back_leg)

    # Layer 3: Front leg (near leg — drawn under torso hem/belt so trousers join hips cleanly!)
    front_leg = _render_leg_layer(
        pal, p["fh"], p["fk"], p["ffoot"],
        foot_angle=p.get("ffoot_angle", 0.0), is_back=False,
    )
    canvas.alpha_composite(front_leg)

    # Layer 4: Torso + clothing + jacket/blazer/hoodie hem + belt
    torso = _render_torso_layer(pal, p)
    canvas.alpha_composite(torso)

    # Layer 5: Neck + sculpted adult head
    head = _render_head_layer(pal, p)
    canvas.alpha_composite(head)

    # Layer 6: Front arm + prop
    if prop and prop_hand == "front":
        front_arm_no_hand = _render_arm_layer(
            pal, p["fs"], p["fe"], p["fhand"],
            is_back=False, hand_open=p.get("fhand_open", False), draw_hand=False,
        )
        canvas.alpha_composite(front_arm_no_hand)
        canvas.alpha_composite(_render_prop_layer(pal, p["fhand"], prop, prop_angle, prop_offset))
        grip_layer = Image.new("RGBA", (SS_W, SS_H), (0, 0, 0, 0))
        _draw_hand(ImageDraw.Draw(grip_layer), p["fhand"], p["fe"], pal,
                   is_open=p.get("fhand_open", False))
        grip_layer = shade_and_ink_layer(grip_layer, ink_color=pal["ink"],
                                         shadow_strength=0.30, highlight_strength=0.18,
                                         rim_strength=0.14)
        canvas.alpha_composite(grip_layer)
    else:
        front_arm = _render_arm_layer(
            pal, p["fs"], p["fe"], p["fhand"],
            is_back=False, hand_open=p.get("fhand_open", False),
        )
        canvas.alpha_composite(front_arm)

    # Subtle kinetic motion-arc streaks
    _draw_streaks(canvas, p.get("streaks", []))

    return canvas.resize((CELL_W, CELL_H), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Grounded Fighting Stances & Poses (16 Rows Matching CharacterDB.ANIMS)
# ---------------------------------------------------------------------------


def idle_frames(pal: dict) -> list[dict]:
    """Row 0 (4 frames): Authentic 3/4 boxer/brawler stance with breathing & guard micro-shift."""
    frames = []
    for i in range(4):
        p = base_pose(pal)
        bob = (0.0, 2.5, 4.5, 2.0)[i]
        sway = (0.0, 2.5, 3.5, 1.0)[i]
        shift_body(p, 0.0, bob)
        p["head"] = (p["head"][0] + sway * 0.35, p["head"][1] + bob * 0.25)
        p["head_tilt"] = 4.0 + bob * 0.35
        p["be"] = (p["be"][0] + sway * 0.6, p["be"][1] + bob * 0.4)
        p["bhand"] = (p["bhand"][0] + sway * 0.9, p["bhand"][1] - bob * 0.5)
        p["fe"] = (p["fe"][0] - sway * 0.4, p["fe"][1] + bob * 0.3)
        p["fhand"] = (p["fhand"][0] + sway * 0.4, p["fhand"][1] - bob * 0.4)
        p["bk"] = (p["bk"][0] + bob * 0.5, p["bk"][1] + bob * 0.4)
        p["fk"] = (p["fk"][0] - bob * 0.3, p["fk"][1] + bob * 0.4)
        frames.append(p)
    return frames


def walk_frames(pal: dict) -> list[dict]:
    """Row 1 (6 frames): Grounded combat footwork stride keeping boxing guard up."""
    frames = []
    for i in range(6):
        p = base_pose(pal)
        ph = i / 6.0
        for side, s_ph in (("b", ph), ("f", (ph + 0.5) % 1.0)):
            swing = math.sin(s_ph * math.tau)
            lift = max(0.0, math.cos(s_ph * math.tau)) * 22.0
            hip = p["bh"] if side == "b" else p["fh"]
            foot_x = hip[0] + swing * 52.0 + (12.0 if side == "b" else -12.0)
            foot_y = (FOOT_Y - 12.0) - lift
            knee_x = (hip[0] + foot_x) * 0.5 + 16.0 + max(0.0, swing) * 8.0
            knee_y = (hip[1] + foot_y) * 0.5 - (8.0 if lift > 6.0 else 2.0)
            foot_ang = -12.0 if lift > 8.0 else (6.0 if swing < -0.3 else 0.0)
            set_leg(p, side, (foot_x, foot_y), (knee_x, knee_y), angle=foot_ang)

        bob = -4.0 if i in (1, 4) else (2.5 if i in (0, 3) else 0.0)
        twist = math.sin(ph * math.tau) * 6.0
        shift_body(p, 0.0, bob)
        p["head_tilt"] = 5.0
        p["be"] = (p["be"][0] - twist * 0.6, p["be"][1] + abs(twist) * 0.4)
        p["bhand"] = (p["bhand"][0] - twist * 0.9, p["bhand"][1] - abs(twist) * 0.5)
        p["fe"] = (p["fe"][0] + twist * 0.5, p["fe"][1] + abs(twist) * 0.3)
        p["fhand"] = (p["fhand"][0] + twist * 0.7, p["fhand"][1] - abs(twist) * 0.3)
        frames.append(p)
    return frames


def crouch_frames(pal: dict) -> list[dict]:
    """Row 2 (2 frames): Low athletic combat crouch matching CROUCH_HURTBOX, back heel raised."""
    frames = []
    b = pal["bulk"]
    for i in range(2):
        p = base_pose(pal)
        drop = 122.0 + i * 4.0
        shift_body(p, -6.0, drop)
        p["head"] = (p["head"][0] + 18.0, p["head"][1] + 6.0)
        p["head_tilt"] = 9.0
        p["bs"] = (p["bs"][0] + 12.0, p["bs"][1] + 4.0)
        p["fs"] = (p["fs"][0] + 4.0, p["fs"][1] + 6.0)
        p["bh"] = (CX + 10.0 * b, 424.0 + i * 3.0)
        p["fh"] = (CX - 22.0 * b, 428.0 + i * 3.0)
        set_leg(p, "b", (CX + 62.0 * b, FOOT_Y - 12.0), (CX + 66.0 * b, 466.0 + i * 2.0), angle=0.0)
        set_leg(p, "f", (CX - 56.0 * b, FOOT_Y - 16.0), (CX - 18.0 * b, 476.0 + i * 2.0), angle=22.0)
        p["be"] = (p["bs"][0] + 22.0, p["bs"][1] + 46.0)
        p["bhand"] = (p["head"][0] + 64.0, p["head"][1] + 38.0)
        p["fe"] = (p["fs"][0] + 18.0, p["fs"][1] + 54.0)
        p["fhand"] = (p["head"][0] + 28.0, p["head"][1] + 46.0)
        frames.append(p)
    return frames


def jump_frames(pal: dict) -> list[dict]:
    """Row 3 (2 frames): Driven upward knee-tuck (0) & balanced descending drop (1)."""
    frames = []

    p = base_pose(pal)
    shift_body(p, 0.0, -24.0)
    p["head_tilt"] = 6.0
    set_leg(p, "b", (p["bh"][0] + 16.0, 444.0), (p["bh"][0] + 58.0, 368.0), angle=22.0)
    set_leg(p, "f", (p["fh"][0] - 44.0, 488.0), (p["fh"][0] - 12.0, 408.0), angle=28.0)
    p["be"] = (p["bs"][0] + 24.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["bs"][0] + 54.0, p["bs"][1] - 4.0)
    p["fe"] = (p["fs"][0] - 18.0, p["fs"][1] + 56.0)
    p["fhand"] = (p["fs"][0] + 18.0, p["fs"][1] + 10.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, 0.0, -8.0)
    p["head_tilt"] = 10.0
    set_leg(p, "b", (p["bh"][0] + 42.0, 502.0), (p["bh"][0] + 50.0, 412.0), angle=12.0)
    set_leg(p, "f", (p["fh"][0] - 46.0, 516.0), (p["fh"][0] - 26.0, 424.0), angle=14.0)
    p["be"] = (p["bs"][0] + 30.0, p["bs"][1] + 50.0)
    p["bhand"] = (p["bs"][0] + 60.0, p["bs"][1] + 12.0)
    p["fe"] = (p["fs"][0] - 20.0, p["fs"][1] + 58.0)
    p["fhand"] = (p["fs"][0] + 14.0, p["fs"][1] + 18.0)
    frames.append(p)
    return frames


def block_frames(pal: dict) -> list[dict]:
    """Row 4 (2 frames): Tight high Muay-Thai / boxing shell guard, weight set back."""
    frames = []
    b = pal["bulk"]
    for i in range(2):
        p = base_pose(pal)
        recoil = i * 6.0
        shift_body(p, -14.0 - recoil, 10.0 + i * 3.0)
        p["head"] = (p["head"][0] - 8.0, p["head"][1] + 6.0)
        p["head_tilt"] = 14.0
        p["expr"] = "grit"
        set_leg(p, "b", (CX + 52.0 * b, FOOT_Y - 12.0), (CX + 36.0 * b, 434.0), angle=0.0)
        set_leg(p, "f", (CX - 66.0 * b, FOOT_Y - 12.0), (CX - 56.0 * b, 438.0), angle=0.0)
        p["be"] = (p["head"][0] + 30.0, p["head"][1] + 66.0)
        p["bhand"] = (p["head"][0] + 42.0, p["head"][1] - 4.0)
        p["fe"] = (p["head"][0] + 10.0, p["head"][1] + 70.0)
        p["fhand"] = (p["head"][0] + 24.0, p["head"][1] - 6.0)
        frames.append(p)
    return frames


def hurt_frames(pal: dict) -> list[dict]:
    """Row 5 (2 frames): Realistic head-snap recoil & torso stagger."""
    frames = []
    b = pal["bulk"]
    for i in range(2):
        p = base_pose(pal)
        snap = i * 10.0
        shift_body(p, -20.0 - snap, 8.0 + i * 4.0)
        p["head"] = (p["head"][0] - 22.0 - snap * 0.5, p["head"][1] - 4.0)
        p["head_tilt"] = -22.0 - i * 8.0
        p["expr"] = "hurt"
        p["be"] = (p["bs"][0] + 34.0, p["bs"][1] + 30.0)
        p["bhand"] = (p["bs"][0] + 66.0, p["bs"][1] - 20.0)
        p["fe"] = (p["fs"][0] - 36.0, p["fs"][1] + 24.0)
        p["fhand"] = (p["fs"][0] - 60.0, p["fs"][1] - 22.0)
        p["fhand_open"] = True
        p["bhand_open"] = True
        set_leg(p, "b", (CX + 46.0 * b, FOOT_Y - 22.0), (CX + 38.0 * b, 434.0), angle=-16.0)
        set_leg(p, "f", (CX - 68.0 * b, FOOT_Y - 12.0), (CX - 50.0 * b, 444.0), angle=0.0)
        frames.append(p)
    return frames


def ko_frames(pal: dict) -> list[dict]:
    """Row 6 (2 frames): Crumpling backwards fall (0) & realistic sprawled floor KO (1, NO X eyes!)."""
    frames = []

    p = base_pose(pal)
    p["head"] = (106.0, 218.0)
    p["head_tilt"] = -50.0
    p["expr"] = "closed"
    p["bs"] = (154.0, 246.0)
    p["fs"] = (128.0, 276.0)
    p["bh"] = (224.0, 370.0)
    p["fh"] = (196.0, 386.0)
    p["be"] = (146.0, 182.0)
    p["bhand"] = (176.0, 134.0)
    p["fe"] = (84.0, 246.0)
    p["fhand"] = (54.0, 202.0)
    p["bhand_open"] = True
    p["fhand_open"] = True
    set_leg(p, "b", (298.0, 482.0), (264.0, 412.0), angle=-35.0)
    set_leg(p, "f", (264.0, 524.0), (234.0, 456.0), angle=-18.0)
    frames.append(p)

    # 1: realistic unconscious sprawl on the floor (closed eyes, grounded anatomy!)
    p = base_pose(pal)
    p["lying"] = True
    p["head"] = (66.0, 514.0)
    p["head_tilt"] = -82.0
    p["expr"] = "closed"
    p["bs"] = (108.0, 496.0)
    p["fs"] = (110.0, 530.0)
    p["bh"] = (212.0, 504.0)
    p["fh"] = (212.0, 532.0)
    p["be"] = (74.0, 474.0)
    p["bhand"] = (46.0, 494.0)
    p["bhand_open"] = True
    p["fe"] = (148.0, 540.0)
    p["fhand"] = (198.0, 542.0)
    p["fhand_open"] = True
    set_leg(p, "b", (332.0, 534.0), (272.0, 518.0), angle=-76.0)
    set_leg(p, "f", (310.0, 538.0), (266.0, 502.0), angle=-58.0)
    frames.append(p)
    return frames


def light_frames(pal: dict) -> list[dict]:
    """Row 7 (4 frames): Snappy lead jab with shoulder rotation & tight rear chin guard."""
    frames = []
    b = pal["bulk"]

    p = base_pose(pal)
    shift_body(p, -6.0, 2.0)
    p["be"] = (p["bs"][0] + 18.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["bs"][0] + 42.0, p["bs"][1] + 6.0)
    p["fe"] = (p["fs"][0] + 6.0, p["fs"][1] + 66.0)
    p["fhand"] = (p["head"][0] + 22.0, p["head"][1] + 18.0)
    frames.append(p)

    # 1: snappy full-extension lead jab (safely inside x<=368!)
    p = base_pose(pal)
    shift_body(p, 14.0, 4.0)
    p["head"] = (p["head"][0] + 10.0, p["head"][1] + 4.0)
    p["head_tilt"] = 8.0
    p["expr"] = "grit"
    p["be"] = (p["bs"][0] + 58.0, p["bs"][1] - 2.0)
    p["bhand"] = (346.0, p["bs"][1] - 4.0)
    p["fe"] = (p["fs"][0] + 10.0, p["fs"][1] + 60.0)
    p["fhand"] = (p["head"][0] + 18.0, p["head"][1] + 18.0)
    set_leg(p, "b", (CX + 68.0 * b, FOOT_Y - 12.0), (CX + 62.0 * b, 434.0))
    set_leg(p, "f", (CX - 58.0 * b, FOOT_Y - 12.0), (CX - 38.0 * b, 436.0), angle=12.0)
    p["streaks"] = [
        {"p0": (254, p["bhand"][1] - 9), "p1": (356, p["bhand"][1] - 5), "w0": 1.2, "w1": 3.8, "alpha": 145},
    ]
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, 10.0, 4.0)
    p["head"] = (p["head"][0] + 8.0, p["head"][1] + 4.0)
    p["head_tilt"] = 7.0
    p["be"] = (p["bs"][0] + 52.0, p["bs"][1] + 4.0)
    p["bhand"] = (336.0, p["bs"][1] + 4.0)
    p["fe"] = (p["fs"][0] + 8.0, p["fs"][1] + 62.0)
    p["fhand"] = (p["head"][0] + 20.0, p["head"][1] + 20.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, 4.0, 2.0)
    p["be"] = (p["bs"][0] + 34.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["bs"][0] + 66.0, p["bs"][1] + 10.0)
    frames.append(p)
    return frames


def heavy_frames(pal: dict) -> list[dict]:
    """Row 8 (5 frames): Deep coiled windup (0-2), explosive full cross on frame 3 (count-2), follow-through (4)."""
    frames = []
    b = pal["bulk"]

    # 0: initial weight shift back
    p = base_pose(pal)
    shift_body(p, -12.0, 6.0)
    p["head_tilt"] = 2.0
    p["fe"] = (p["fs"][0] - 24.0, p["fs"][1] + 50.0)
    p["fhand"] = (p["fs"][0] - 10.0, p["fs"][1] + 22.0)
    p["be"] = (p["bs"][0] + 36.0, p["bs"][1] + 40.0)
    p["bhand"] = (p["bs"][0] + 70.0, p["bs"][1] + 12.0)
    set_leg(p, "b", (CX + 56.0 * b, FOOT_Y - 12.0), (CX + 44.0 * b, 434.0))
    set_leg(p, "f", (CX - 60.0 * b, FOOT_Y - 12.0), (CX - 52.0 * b, 436.0))
    frames.append(p)

    # 1: mid coil
    p = base_pose(pal)
    shift_body(p, -24.0, 12.0)
    p["head"] = (p["head"][0] - 6.0, p["head"][1] + 4.0)
    p["head_tilt"] = 0.0
    p["fe"] = (p["fs"][0] - 44.0, p["fs"][1] + 34.0)
    p["fhand"] = (p["fs"][0] - 58.0, p["fs"][1] + 4.0)
    p["be"] = (p["bs"][0] + 44.0, p["bs"][1] + 26.0)
    p["bhand"] = (p["bs"][0] + 82.0, p["bs"][1] + 2.0)
    set_leg(p, "b", (CX + 60.0 * b, FOOT_Y - 12.0), (CX + 40.0 * b, 436.0))
    set_leg(p, "f", (CX - 66.0 * b, FOOT_Y - 12.0), (CX - 64.0 * b, 438.0))
    frames.append(p)

    # 2: deepest coiled power windup
    p = base_pose(pal)
    shift_body(p, -34.0, 18.0)
    p["head"] = (p["head"][0] - 10.0, p["head"][1] + 6.0)
    p["head_tilt"] = -2.0
    p["expr"] = "grit"
    p["fe"] = (p["fs"][0] - 50.0, p["fs"][1] + 22.0)
    p["fhand"] = (max(28.0, p["fs"][0] - 70.0), p["fs"][1] - 10.0)
    p["be"] = (p["bs"][0] + 48.0, p["bs"][1] + 20.0)
    p["bhand"] = (p["bs"][0] + 90.0, p["bs"][1] - 4.0)
    set_leg(p, "b", (CX + 64.0 * b, FOOT_Y - 12.0), (CX + 38.0 * b, 438.0))
    set_leg(p, "f", (CX - 72.0 * b, FOOT_Y - 12.0), (CX - 72.0 * b, 440.0))
    frames.append(p)

    # 3: ACTIVE STRIKE (count - 2 = 3) — explosive full-extension cross, solid rotated torso!
    p = base_pose(pal)
    shift_body(p, 26.0, 14.0)
    p["head"] = (p["head"][0] + 18.0, p["head"][1] + 6.0)
    p["head_tilt"] = 10.0
    p["expr"] = "grit"
    # Keep torso broad & solid — drive near arm powerfully across the chest!
    p["fe"] = (p["fs"][0] + 92.0, p["fs"][1] - 6.0)
    p["fhand"] = (348.0, p["fs"][1] - 8.0)
    p["be"] = (p["bs"][0] - 28.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["bs"][0] - 42.0, p["bs"][1] + 72.0)
    set_leg(p, "b", (CX + 82.0 * b, FOOT_Y - 12.0), (CX + 78.0 * b, 436.0), angle=0.0)
    set_leg(p, "f", (80.0, FOOT_Y - 16.0), (144.0, 446.0), angle=26.0)
    p["streaks"] = [
        {"p0": (224, p["fhand"][1] - 14), "p1": (356, p["fhand"][1] - 6), "w0": 1.4, "w1": 4.8, "alpha": 160},
        {"p0": (244, p["fhand"][1] + 10), "p1": (350, p["fhand"][1] + 6), "w0": 1.0, "w1": 3.0, "alpha": 120, "color": (228, 192, 132)},
    ]
    frames.append(p)

    # 4: controlled follow-through
    p = base_pose(pal)
    shift_body(p, 12.0, 8.0)
    p["head"] = (p["head"][0] + 8.0, p["head"][1] + 4.0)
    p["head_tilt"] = 7.0
    p["fe"] = (p["fs"][0] + 46.0, p["fs"][1] + 52.0)
    p["fhand"] = (p["fs"][0] + 92.0, p["fs"][1] + 80.0)
    p["be"] = (p["bs"][0] + 16.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["bs"][0] + 44.0, p["bs"][1] + 22.0)
    set_leg(p, "b", (CX + 70.0 * b, FOOT_Y - 12.0), (CX + 62.0 * b, 434.0))
    set_leg(p, "f", (CX - 58.0 * b, FOOT_Y - 12.0), (CX - 38.0 * b, 438.0), angle=10.0)
    frames.append(p)
    return frames


def special_frames(pal: dict) -> list[dict]:
    """Row 9 (6 frames): Character-authentic dramatic prop attacks.

    Karen's clipboard releases cleanly on frame 2 (matching CharacterDB release_frame=2).
    """
    cid = pal["id"]
    b = pal["bulk"]
    frames = []

    if cid == "karen":
        # 0: draw clipboard back
        p = base_pose(pal)
        shift_body(p, -14.0, 6.0)
        p["fe"] = (p["fs"][0] - 28.0, p["fs"][1] + 34.0)
        p["fhand"] = (p["fs"][0] - 46.0, p["fs"][1] - 4.0)
        p["be"] = (p["bs"][0] + 36.0, p["bs"][1] + 34.0)
        p["bhand"] = (p["bs"][0] + 74.0, p["bs"][1] + 8.0)
        p["prop"] = "clipboard"
        p["prop_angle"] = -28.0
        frames.append(p)

        # 1: deep torque coil, clipboard cocked high-back
        p = base_pose(pal)
        shift_body(p, -26.0, 12.0)
        p["head"] = (p["head"][0] - 8.0, p["head"][1] + 4.0)
        p["expr"] = "grit"
        p["fe"] = (p["fs"][0] - 44.0, p["fs"][1] + 18.0)
        p["fhand"] = (max(36.0, p["fs"][0] - 66.0), p["fs"][1] - 24.0)
        p["be"] = (p["bs"][0] + 44.0, p["bs"][1] + 24.0)
        p["bhand"] = (p["bs"][0] + 84.0, p["bs"][1] + 2.0)
        p["prop"] = "clipboard"
        p["prop_angle"] = -52.0
        frames.append(p)

        # 2: RELEASE FRAME (prop cleanly gone -> Projectile spawns!)
        p = base_pose(pal)
        shift_body(p, 22.0, 8.0)
        p["head"] = (p["head"][0] + 14.0, p["head"][1] + 4.0)
        p["head_tilt"] = 8.0
        p["expr"] = "grit"
        p["fe"] = (p["fs"][0] + 86.0, p["fs"][1] - 8.0)
        p["fhand"] = (340.0, p["fs"][1] - 10.0)
        p["fhand_open"] = True
        p["be"] = (p["bs"][0] - 24.0, p["bs"][1] + 44.0)
        p["bhand"] = (p["bs"][0] - 42.0, p["bs"][1] + 66.0)
        set_leg(p, "b", (CX + 76.0 * b, FOOT_Y - 12.0), (CX + 70.0 * b, 434.0))
        set_leg(p, "f", (92.0, FOOT_Y - 16.0), (146.0, 444.0), angle=22.0)
        p["prop"] = None
        p["streaks"] = [
            {"p0": (254, p["fhand"][1] - 12), "p1": (360, p["fhand"][1] - 6), "w0": 1.2, "w1": 4.2, "alpha": 150},
        ]
        frames.append(p)

        # 3: sharp accusing follow-through
        p = base_pose(pal)
        shift_body(p, 16.0, 8.0)
        p["head"] = (p["head"][0] + 10.0, p["head"][1] + 4.0)
        p["fe"] = (p["fs"][0] + 74.0, p["fs"][1] + 4.0)
        p["fhand"] = (330.0, p["fs"][1] + 8.0)
        p["fhand_open"] = True
        p["prop"] = None
        frames.append(p)

        # 4: recover
        p = base_pose(pal)
        shift_body(p, 6.0, 4.0)
        p["fe"] = (p["fs"][0] + 28.0, p["fs"][1] + 52.0)
        p["fhand"] = (p["fs"][0] + 62.0, p["fs"][1] + 32.0)
        p["prop"] = None
        frames.append(p)

        # 5: settle
        p = base_pose(pal)
        p["prop"] = None
        frames.append(p)
        return frames

    if cid == "dave":
        # SEVERANCE PACKAGE — two-handed heavy banker's box lunge!
        p = base_pose(pal)
        shift_body(p, -14.0, 10.0)
        p["fe"] = (p["fs"][0] - 14.0, p["fs"][1] + 52.0)
        p["fhand"] = (p["fs"][0] + 12.0, p["fs"][1] + 24.0)
        p["be"] = (p["bs"][0] - 4.0, p["bs"][1] + 48.0)
        p["bhand"] = (p["fs"][0] + 24.0, p["fs"][1] + 18.0)
        p["prop"] = "box"
        p["prop_angle"] = -14.0
        p["prop_offset"] = (12.0, -4.0)
        frames.append(p)

        p = base_pose(pal)
        shift_body(p, -26.0, 16.0)
        p["expr"] = "grit"
        p["fe"] = (p["fs"][0] - 28.0, p["fs"][1] + 36.0)
        p["fhand"] = (p["fs"][0] - 14.0, p["fs"][1] + 6.0)
        p["be"] = (p["bs"][0] - 14.0, p["bs"][1] + 34.0)
        p["bhand"] = (p["fs"][0], p["fs"][1] + 2.0)
        p["prop"] = "box"
        p["prop_angle"] = -24.0
        p["prop_offset"] = (8.0, -8.0)
        frames.append(p)

        # 2: explosive box lunge forward (box safely inside x<=368!)
        p = base_pose(pal)
        shift_body(p, 24.0, 14.0)
        p["head"] = (p["head"][0] + 16.0, p["head"][1] + 6.0)
        p["head_tilt"] = 12.0
        p["expr"] = "grit"
        p["fe"] = (p["fs"][0] + 68.0, p["fs"][1] + 16.0)
        p["fhand"] = (304.0, p["fs"][1] + 6.0)
        p["be"] = (p["bs"][0] + 44.0, p["bs"][1] + 14.0)
        p["bhand"] = (314.0, p["bs"][1] + 4.0)
        set_leg(p, "b", (CX + 82.0 * b, FOOT_Y - 12.0), (CX + 78.0 * b, 434.0))
        set_leg(p, "f", (80.0, FOOT_Y - 16.0), (144.0, 444.0), angle=24.0)
        p["prop"] = "box"
        p["prop_angle"] = 12.0
        p["prop_offset"] = (14.0, -4.0)
        p["streaks"] = [
            {"p0": (212, p["fhand"][1] - 28), "p1": (356, p["fhand"][1] - 22), "w0": 1.2, "w1": 4.2, "alpha": 145},
            {"p0": (220, p["fhand"][1] + 22), "p1": (352, p["fhand"][1] + 20), "w0": 1.0, "w1": 3.2, "alpha": 120},
        ]
        frames.append(p)

        p = base_pose(pal)
        shift_body(p, 20.0, 14.0)
        p["head"] = (p["head"][0] + 12.0, p["head"][1] + 6.0)
        p["head_tilt"] = 10.0
        p["fe"] = (p["fs"][0] + 60.0, p["fs"][1] + 24.0)
        p["fhand"] = (296.0, p["fs"][1] + 14.0)
        p["be"] = (p["bs"][0] + 40.0, p["bs"][1] + 22.0)
        p["bhand"] = (306.0, p["bs"][1] + 12.0)
        set_leg(p, "b", (CX + 78.0 * b, FOOT_Y - 12.0), (CX + 72.0 * b, 434.0))
        set_leg(p, "f", (92.0, FOOT_Y - 14.0), (150.0, 444.0), angle=18.0)
        p["prop"] = "box"
        p["prop_angle"] = 16.0
        p["prop_offset"] = (12.0, -2.0)
        frames.append(p)

        p = base_pose(pal)
        shift_body(p, 8.0, 6.0)
        p["fe"] = (p["fs"][0] + 32.0, p["fs"][1] + 54.0)
        p["fhand"] = (p["fs"][0] + 74.0, p["fs"][1] + 50.0)
        p["prop"] = "box"
        p["prop_angle"] = 8.0
        p["prop_offset"] = (10.0, 6.0)
        frames.append(p)

        p = base_pose(pal)
        frames.append(p)
        return frames

    if cid == "tony":
        # EVICTION NOTICE — armored heavy overhead plunger slam!
        p = base_pose(pal)
        shift_body(p, -12.0, 12.0)
        p["fe"] = (p["fs"][0] - 28.0, p["fs"][1] + 14.0)
        p["fhand"] = (p["fs"][0] - 26.0, p["fs"][1] - 32.0)
        p["be"] = (p["bs"][0] + 18.0, p["bs"][1] + 18.0)
        p["bhand"] = (p["fs"][0] - 12.0, p["fs"][1] - 18.0)
        p["prop"] = "plunger"
        p["prop_angle"] = -34.0
        set_leg(p, "b", (CX + 62.0 * b, FOOT_Y - 12.0), (CX + 52.0 * b, 434.0))
        set_leg(p, "f", (CX - 66.0 * b, FOOT_Y - 12.0), (CX - 60.0 * b, 436.0))
        frames.append(p)

        p = base_pose(pal)
        shift_body(p, -22.0, 16.0)
        p["head_tilt"] = -6.0
        p["expr"] = "grit"
        p["fe"] = (p["fs"][0] - 38.0, p["fs"][1] - 10.0)
        p["fhand"] = (p["fs"][0] - 34.0, max(106.0, p["fs"][1] - 54.0))
        p["be"] = (p["bs"][0] + 8.0, p["bs"][1] - 2.0)
        p["bhand"] = (p["fs"][0] - 20.0, max(116.0, p["fs"][1] - 42.0))
        p["prop"] = "plunger"
        p["prop_angle"] = -56.0
        set_leg(p, "b", (CX + 66.0 * b, FOOT_Y - 12.0), (CX + 52.0 * b, 436.0))
        set_leg(p, "f", (CX - 72.0 * b, FOOT_Y - 12.0), (CX - 68.0 * b, 438.0))
        frames.append(p)

        # 2: brutal downward-forward plunger smash (plunger bell safely inside x<=368!)
        p = base_pose(pal)
        shift_body(p, 22.0, 16.0)
        p["head"] = (p["head"][0] + 16.0, p["head"][1] + 6.0)
        p["head_tilt"] = 12.0
        p["expr"] = "grit"
        p["fe"] = (p["fs"][0] + 74.0, p["fs"][1] + 10.0)
        p["fhand"] = (278.0, p["fs"][1] + 12.0)
        p["be"] = (p["bs"][0] + 30.0, p["bs"][1] + 20.0)
        p["bhand"] = (268.0, p["fs"][1] + 22.0)
        set_leg(p, "b", (CX + 78.0 * b, FOOT_Y - 12.0), (CX + 72.0 * b, 436.0))
        set_leg(p, "f", (80.0, FOOT_Y - 14.0), (140.0, 444.0), angle=22.0)
        p["prop"] = "plunger"
        p["prop_angle"] = 88.0
        p["streaks"] = [
            {"p0": (220, p["fhand"][1] - 66), "p1": (356, p["fhand"][1] - 12), "w0": 1.6, "w1": 5.0, "alpha": 160},
            {"p0": (236, p["fhand"][1] - 44), "p1": (350, p["fhand"][1] + 10), "w0": 1.2, "w1": 3.4, "alpha": 125, "color": (214, 152, 92)},
        ]
        frames.append(p)

        p = base_pose(pal)
        shift_body(p, 18.0, 18.0)
        p["head"] = (p["head"][0] + 12.0, p["head"][1] + 8.0)
        p["head_tilt"] = 10.0
        p["fe"] = (p["fs"][0] + 68.0, p["fs"][1] + 22.0)
        p["fhand"] = (274.0, p["fs"][1] + 28.0)
        p["be"] = (p["bs"][0] + 26.0, p["bs"][1] + 30.0)
        p["bhand"] = (264.0, p["fs"][1] + 36.0)
        p["prop"] = "plunger"
        p["prop_angle"] = 96.0
        frames.append(p)

        p = base_pose(pal)
        shift_body(p, 6.0, 8.0)
        p["fe"] = (p["fs"][0] + 24.0, p["fs"][1] + 50.0)
        p["fhand"] = (p["fs"][0] + 58.0, p["fs"][1] + 26.0)
        p["prop"] = "plunger"
        p["prop_angle"] = 48.0
        frames.append(p)

        p = base_pose(pal)
        frames.append(p)
        return frames

    # CHAD: REPLY ALL — low aerodynamic laptop shoulder-drive dash!
    p = base_pose(pal)
    shift_body(p, -18.0, 26.0)
    p["head"] = (p["head"][0] + 10.0, p["head"][1] + 6.0)
    p["head_tilt"] = 12.0
    p["fe"] = (p["fs"][0] - 10.0, p["fs"][1] + 52.0)
    p["fhand"] = (p["fs"][0] + 34.0, p["fs"][1] + 24.0)
    p["prop"] = "laptop"
    p["prop_angle"] = -12.0
    set_leg(p, "b", (CX + 58.0 * b, FOOT_Y - 12.0), (CX + 56.0 * b, 444.0))
    set_leg(p, "f", (CX - 68.0 * b, FOOT_Y - 16.0), (CX - 46.0 * b, 450.0), angle=20.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, -26.0, 38.0)
    p["head"] = (p["head"][0] + 16.0, p["head"][1] + 12.0)
    p["head_tilt"] = 16.0
    p["expr"] = "grit"
    p["fe"] = (p["fs"][0] - 18.0, p["fs"][1] + 46.0)
    p["fhand"] = (p["fs"][0] + 28.0, p["fs"][1] + 20.0)
    p["prop"] = "laptop"
    p["prop_angle"] = -8.0
    set_leg(p, "b", (CX + 62.0 * b, FOOT_Y - 12.0), (CX + 60.0 * b, 452.0))
    set_leg(p, "f", (CX - 76.0 * b, FOOT_Y - 18.0), (CX - 50.0 * b, 456.0), angle=28.0)
    frames.append(p)

    # 2: high-speed forward dash-ram driving laptop edge forward (safely inside x<=368!)
    p = base_pose(pal)
    shift_body(p, 26.0, 26.0)
    p["head"] = (p["head"][0] + 22.0, p["head"][1] + 10.0)
    p["head_tilt"] = 15.0
    p["expr"] = "grit"
    p["fe"] = (p["fs"][0] + 68.0, p["fs"][1] + 12.0)
    p["fhand"] = (314.0, p["fs"][1] + 4.0)
    p["be"] = (p["bs"][0] - 34.0, p["bs"][1] + 30.0)
    p["bhand"] = (p["bs"][0] - 66.0, p["bs"][1] + 54.0)
    set_leg(p, "b", (CX + 86.0 * b, FOOT_Y - 12.0), (CX + 86.0 * b, 444.0))
    set_leg(p, "f", (68.0, FOOT_Y - 22.0), (138.0, 448.0), angle=34.0)
    p["prop"] = "laptop"
    p["prop_angle"] = 20.0
    p["prop_offset"] = (10.0, -2.0)
    p["streaks"] = [
        {"p0": (148, p["fs"][1] - 20), "p1": (356, p["fs"][1] - 16), "w0": 1.2, "w1": 4.0, "alpha": 150, "color": (176, 224, 232)},
        {"p0": (166, p["fs"][1] + 20), "p1": (354, p["fs"][1] + 16), "w0": 1.0, "w1": 3.0, "alpha": 120},
    ]
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, 22.0, 22.0)
    p["head"] = (p["head"][0] + 18.0, p["head"][1] + 8.0)
    p["head_tilt"] = 13.0
    p["fe"] = (p["fs"][0] + 60.0, p["fs"][1] + 16.0)
    p["fhand"] = (308.0, p["fs"][1] + 8.0)
    p["be"] = (p["bs"][0] - 28.0, p["bs"][1] + 34.0)
    p["bhand"] = (p["bs"][0] - 54.0, p["bs"][1] + 56.0)
    set_leg(p, "b", (CX + 82.0 * b, FOOT_Y - 12.0), (CX + 78.0 * b, 442.0))
    set_leg(p, "f", (82.0, FOOT_Y - 16.0), (144.0, 446.0), angle=24.0)
    p["prop"] = "laptop"
    p["prop_angle"] = 16.0
    p["prop_offset"] = (8.0, 0.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, 10.0, 10.0)
    p["fe"] = (p["fs"][0] + 26.0, p["fs"][1] + 52.0)
    p["fhand"] = (p["fs"][0] + 62.0, p["fs"][1] + 36.0)
    p["prop"] = "laptop"
    p["prop_angle"] = 6.0
    frames.append(p)

    p = base_pose(pal)
    frames.append(p)
    return frames


def win_frames(pal: dict) -> list[dict]:
    """Row 10 (4 frames): Grounded deadpan victory beat (NO cartoonish jumping!)."""
    cid = pal["id"]
    b = pal["bulk"]
    frames = []

    for i in range(4):
        p = base_pose(pal)
        p["head"] = (CX + 4.0, 114.0 + pal["height"])
        p["bs"] = (CX + 28.0 * b, p["head"][1] + 44.0)
        p["fs"] = (CX - 28.0 * b, p["head"][1] + 48.0)
        p["bh"] = (CX + 16.0 * b, p["head"][1] + 196.0)
        p["fh"] = (CX - 16.0 * b, p["head"][1] + 198.0)
        set_leg(p, "b", (CX + 38.0 * b, FOOT_Y - 12.0), (CX + 32.0 * b, 428.0))
        set_leg(p, "f", (CX - 38.0 * b, FOOT_Y - 12.0), (CX - 32.0 * b, 430.0))

        if cid == "dave":
            p["head_tilt"] = (2.0, 4.0, 2.0, 0.0)[i]
            p["be"] = (p["bs"][0] + 10.0, p["bs"][1] + 74.0)
            p["bhand"] = (p["bs"][0] + 14.0, p["bs"][1] + 142.0)
            if i in (0, 1):
                t_off = i * 4.0
                p["fe"] = (p["fs"][0] + 6.0, p["fs"][1] + 66.0)
                p["fhand"] = (p["head"][0] + 16.0, p["head"][1] + 58.0 - t_off)
            else:
                g_off = (i - 2) * 3.0
                p["fe"] = (p["fs"][0] + 16.0, p["fs"][1] + 48.0)
                p["fhand"] = (p["head"][0] + 24.0, p["head"][1] + 4.0 - g_off)

        elif cid == "karen":
            p["head_tilt"] = (8.0, 12.0, 6.0, 4.0)[i]
            p["expr"] = "focused" if i < 2 else "smug"
            p["be"] = (p["bs"][0] + 26.0, p["bs"][1] + 58.0)
            p["bhand"] = (p["bs"][0] + 58.0, p["bs"][1] + 42.0)
            p["prop"] = "clipboard"
            p["prop_hand"] = "back"
            p["prop_angle"] = 14.0
            tap = (0.0, 8.0, 2.0, 0.0)[i]
            p["fe"] = (p["fs"][0] + 18.0, p["fs"][1] + 66.0)
            p["fhand"] = (p["bhand"][0] - 12.0 + tap, p["bhand"][1] - 4.0 + tap * 0.5)
            p["fhand_open"] = True

        elif cid == "tony":
            p["head_tilt"] = (0.0, -2.0, 0.0, 1.0)[i]
            p["expr"] = "focused"
            p["be"] = (p["bs"][0] + 28.0, p["bs"][1] + 66.0)
            p["bhand"] = (p["bh"][0] + 14.0, p["bh"][1] - 6.0)
            sh_bob = (0.0, -4.0, -2.0, 0.0)[i]
            p["fe"] = (p["fs"][0] - 16.0, p["fs"][1] + 54.0 + sh_bob)
            p["fhand"] = (p["fs"][0] + 4.0, p["fs"][1] + 8.0 + sh_bob)
            p["prop"] = "plunger"
            p["prop_hand"] = "front"
            p["prop_angle"] = -38.0 + sh_bob * 0.5

        else:
            p["head_tilt"] = (6.0, 10.0, 8.0, 4.0)[i]
            p["expr"] = "smug"
            p["be"] = (p["bs"][0] + 22.0, p["bs"][1] + 62.0)
            p["bhand"] = (p["bs"][0] + 54.0, p["bs"][1] + 52.0)
            p["prop"] = "laptop"
            p["prop_hand"] = "back"
            p["prop_angle"] = 8.0
            tap = (0.0, 6.0, -2.0, 4.0)[i]
            p["fe"] = (p["fs"][0] + 16.0, p["fs"][1] + 70.0)
            p["fhand"] = (p["bhand"][0] - 14.0 + tap, p["bhand"][1] + 4.0)
            p["fhand_open"] = True

        frames.append(p)
    return frames


def low_frames(pal: dict) -> list[dict]:
    """Row 11 (4 frames): Low crouched snap kick / shin check."""
    frames = []
    b = pal["bulk"]

    p = base_pose(pal)
    shift_body(p, -10.0, 114.0)
    p["head"] = (p["head"][0] + 10.0, p["head"][1] + 6.0)
    p["head_tilt"] = 8.0
    p["bh"] = (CX + 2.0 * b, 422.0)
    p["fh"] = (CX - 22.0 * b, 426.0)
    set_leg(p, "b", (CX - 34.0 * b, FOOT_Y - 12.0), (CX - 10.0 * b, 476.0))
    set_leg(p, "f", (CX + 28.0 * b, 514.0), (CX + 38.0 * b, 460.0), angle=18.0)
    p["be"] = (p["bs"][0] + 22.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["head"][0] + 56.0, p["head"][1] + 38.0)
    p["fe"] = (p["fs"][0] + 12.0, p["fs"][1] + 52.0)
    p["fhand"] = (p["head"][0] + 20.0, p["head"][1] + 46.0)
    frames.append(p)

    # 1: snappy low shin-check kick (safely inside x<=368!)
    p = base_pose(pal)
    shift_body(p, -18.0, 118.0)
    p["head"] = (p["head"][0] - 4.0, p["head"][1] + 6.0)
    p["head_tilt"] = 4.0
    p["expr"] = "grit"
    p["bh"] = (CX - 4.0 * b, 430.0)
    p["fh"] = (CX - 18.0 * b, 434.0)
    set_leg(p, "b", (CX - 46.0 * b, FOOT_Y - 12.0), (CX - 24.0 * b, 480.0))
    set_leg(p, "f", (328.0, 514.0), (258.0, 476.0), angle=-16.0)
    p["be"] = (p["bs"][0] + 22.0, p["bs"][1] + 42.0)
    p["bhand"] = (p["head"][0] + 56.0, p["head"][1] + 36.0)
    p["fe"] = (p["fs"][0] - 10.0, p["fs"][1] + 52.0)
    p["fhand"] = (p["fs"][0] - 28.0, p["fs"][1] + 82.0)
    p["streaks"] = [
        {"p0": (244, 514), "p1": (346, 510), "w0": 1.2, "w1": 3.8, "alpha": 140},
    ]
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, -14.0, 118.0)
    p["head"] = (p["head"][0], p["head"][1] + 6.0)
    p["bh"] = (CX - 2.0 * b, 430.0)
    p["fh"] = (CX - 18.0 * b, 434.0)
    set_leg(p, "b", (CX - 44.0 * b, FOOT_Y - 12.0), (CX - 22.0 * b, 480.0))
    set_leg(p, "f", (318.0, 516.0), (252.0, 478.0), angle=-12.0)
    p["be"] = (p["bs"][0] + 22.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["head"][0] + 56.0, p["head"][1] + 38.0)
    p["fe"] = (p["fs"][0] - 6.0, p["fs"][1] + 54.0)
    p["fhand"] = (p["fs"][0] - 14.0, p["fs"][1] + 74.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, -8.0, 120.0)
    p["head"] = (p["head"][0] + 12.0, p["head"][1] + 6.0)
    p["bh"] = (CX + 6.0 * b, 424.0)
    p["fh"] = (CX - 22.0 * b, 428.0)
    set_leg(p, "b", (CX + 50.0 * b, FOOT_Y - 12.0), (CX + 52.0 * b, 470.0))
    set_leg(p, "f", (CX - 50.0 * b, FOOT_Y - 14.0), (CX - 20.0 * b, 476.0), angle=16.0)
    p["be"] = (p["bs"][0] + 22.0, p["bs"][1] + 46.0)
    p["bhand"] = (p["head"][0] + 58.0, p["head"][1] + 42.0)
    p["fe"] = (p["fs"][0] + 16.0, p["fs"][1] + 52.0)
    p["fhand"] = (p["head"][0] + 24.0, p["head"][1] + 48.0)
    frames.append(p)
    return frames


def sweep_frames(pal: dict) -> list[dict]:
    """Row 12 (4 frames): Low pivoted martial-arts sweep kick with planted support palm."""
    frames = []

    p = base_pose(pal)
    p["head"] = (146.0, 302.0)
    p["head_tilt"] = 6.0
    p["bs"] = (170.0, 348.0)
    p["fs"] = (124.0, 358.0)
    p["bh"] = (180.0, 464.0)
    p["fh"] = (154.0, 472.0)
    p["be"] = (106.0, 434.0)
    p["bhand"] = (84.0, 524.0)
    p["bhand_open"] = True
    p["fe"] = (156.0, 424.0)
    p["fhand"] = (186.0, 384.0)
    set_leg(p, "b", (134.0, FOOT_Y - 12.0), (118.0, 496.0), angle=18.0)
    set_leg(p, "f", (236.0, 524.0), (228.0, 476.0), angle=10.0)
    frames.append(p)

    p = base_pose(pal)
    p["head"] = (118.0, 334.0)
    p["head_tilt"] = 8.0
    p["expr"] = "grit"
    p["bs"] = (140.0, 378.0)
    p["fs"] = (96.0, 392.0)
    p["bh"] = (168.0, 488.0)
    p["fh"] = (148.0, 496.0)
    p["be"] = (82.0, 464.0)
    p["bhand"] = (58.0, FOOT_Y - 6.0)
    p["bhand_open"] = True
    p["fe"] = (136.0, 446.0)
    p["fhand"] = (176.0, 412.0)
    set_leg(p, "b", (136.0, FOOT_Y - 12.0), (112.0, 508.0), angle=22.0)
    set_leg(p, "f", (318.0, 530.0), (242.0, 514.0), angle=-24.0)
    frames.append(p)

    # 2: peak active sweep (safely inside x<=368!)
    p = base_pose(pal)
    p["head"] = (106.0, 348.0)
    p["head_tilt"] = 10.0
    p["expr"] = "grit"
    p["bs"] = (128.0, 392.0)
    p["fs"] = (86.0, 404.0)
    p["bh"] = (166.0, 498.0)
    p["fh"] = (150.0, 504.0)
    p["be"] = (72.0, 474.0)
    p["bhand"] = (48.0, FOOT_Y - 6.0)
    p["bhand_open"] = True
    p["fe"] = (126.0, 456.0)
    p["fhand"] = (168.0, 424.0)
    set_leg(p, "b", (142.0, FOOT_Y - 12.0), (114.0, 514.0), angle=26.0)
    set_leg(p, "f", (334.0, 532.0), (252.0, 518.0), angle=-26.0)
    p["streaks"] = [
        {"p0": (224, 538), "p1": (356, 532), "w0": 1.4, "w1": 4.6, "alpha": 150},
    ]
    frames.append(p)

    p = base_pose(pal)
    p["head"] = (164.0, 288.0)
    p["head_tilt"] = 8.0
    p["bs"] = (190.0, 334.0)
    p["fs"] = (142.0, 342.0)
    p["bh"] = (192.0, 444.0)
    p["fh"] = (164.0, 450.0)
    p["be"] = (146.0, 418.0)
    p["bhand"] = (142.0, 476.0)
    p["fe"] = (184.0, 406.0)
    p["fhand"] = (224.0, 366.0)
    set_leg(p, "b", (148.0, FOOT_Y - 12.0), (138.0, 488.0), angle=12.0)
    set_leg(p, "f", (246.0, FOOT_Y - 12.0), (242.0, 484.0), angle=0.0)
    frames.append(p)
    return frames


def air_frames(pal: dict) -> list[dict]:
    """Row 13 (4 frames): Crisp mid-air tucked knee into extended angled jump kick."""
    frames = []

    p = base_pose(pal)
    shift_body(p, -10.0, -42.0)
    p["head_tilt"] = 6.0
    p["be"] = (p["bs"][0] + 24.0, p["bs"][1] + 40.0)
    p["bhand"] = (p["bs"][0] + 54.0, p["bs"][1] - 4.0)
    p["fe"] = (p["fs"][0] - 26.0, p["fs"][1] + 46.0)
    p["fhand"] = (p["fs"][0] + 4.0, p["fs"][1] + 6.0)
    set_leg(p, "b", (p["bh"][0] - 24.0, 396.0), (p["bh"][0] + 18.0, 334.0), angle=28.0)
    set_leg(p, "f", (p["fh"][0] + 36.0, 386.0), (p["fh"][0] + 74.0, 316.0), angle=18.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, -18.0, -44.0)
    p["head"] = (p["head"][0] - 12.0, p["head"][1] + 4.0)
    p["head_tilt"] = 4.0
    p["expr"] = "grit"
    p["be"] = (p["bs"][0] + 20.0, p["bs"][1] + 38.0)
    p["bhand"] = (p["bs"][0] + 46.0, p["bs"][1] - 6.0)
    p["fe"] = (p["fs"][0] - 36.0, p["fs"][1] + 34.0)
    p["fhand"] = (p["fs"][0] - 58.0, p["fs"][1] - 10.0)
    set_leg(p, "b", (p["bh"][0] - 42.0, 392.0), (p["bh"][0] - 4.0, 344.0), angle=34.0)
    set_leg(p, "f", (318.0, 412.0), (256.0, 344.0), angle=18.0)
    frames.append(p)

    # 2: peak active angled jump kick (safely inside x<=368!)
    p = base_pose(pal)
    shift_body(p, -26.0, -48.0)
    p["head"] = (p["head"][0] - 18.0, p["head"][1] + 8.0)
    p["head_tilt"] = 0.0
    p["expr"] = "grit"
    p["bh"] = (p["bh"][0] + 10.0, p["bh"][1] + 4.0)
    p["fh"] = (p["fh"][0] + 12.0, p["fh"][1] + 6.0)
    p["be"] = (p["bs"][0] + 16.0, p["bs"][1] + 36.0)
    p["bhand"] = (p["bs"][0] + 38.0, p["bs"][1] - 8.0)
    p["fe"] = (p["fs"][0] - 40.0, p["fs"][1] + 26.0)
    p["fhand"] = (max(28.0, p["fs"][0] - 66.0), p["fs"][1] - 18.0)
    set_leg(p, "b", (p["bh"][0] - 54.0, 376.0), (p["bh"][0] - 8.0, 330.0), angle=42.0)
    set_leg(p, "f", (332.0, 398.0), (260.0, 344.0), angle=16.0)
    p["streaks"] = [
        {"p0": (250, 346), "p1": (354, 394), "w0": 1.4, "w1": 4.6, "alpha": 150},
    ]
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, -8.0, -24.0)
    p["head_tilt"] = 8.0
    p["be"] = (p["bs"][0] + 26.0, p["bs"][1] + 46.0)
    p["bhand"] = (p["bs"][0] + 58.0, p["bs"][1] + 6.0)
    p["fe"] = (p["fs"][0] - 24.0, p["fs"][1] + 54.0)
    p["fhand"] = (p["fs"][0] + 12.0, p["fs"][1] + 14.0)
    set_leg(p, "b", (p["bh"][0] - 28.0, 466.0), (p["bh"][0] - 12.0, 396.0), angle=18.0)
    set_leg(p, "f", (p["fh"][0] + 52.0, 456.0), (p["fh"][0] + 66.0, 378.0), angle=12.0)
    frames.append(p)
    return frames


def crouch_block_frames(pal: dict) -> list[dict]:
    """Row 14 (2 frames): Tight crouched defensive shell guard."""
    frames = []
    b = pal["bulk"]
    for i in range(2):
        p = base_pose(pal)
        recoil = i * 6.0
        shift_body(p, -16.0 - recoil, 126.0 + i * 4.0)
        p["head"] = (p["head"][0] + 6.0, p["head"][1] + 12.0)
        p["head_tilt"] = 16.0
        p["expr"] = "grit"
        p["bh"] = (CX + 2.0 * b, 434.0 + i * 3.0)
        p["fh"] = (CX - 28.0 * b, 438.0 + i * 3.0)
        set_leg(p, "b", (CX + 52.0 * b, FOOT_Y - 12.0), (CX + 54.0 * b, 474.0 + i * 2.0))
        set_leg(p, "f", (CX - 64.0 * b, FOOT_Y - 14.0), (CX - 28.0 * b, 480.0 + i * 2.0), angle=20.0)
        p["be"] = (p["head"][0] + 34.0, p["head"][1] + 62.0)
        p["bhand"] = (p["head"][0] + 48.0, p["head"][1] - 4.0)
        p["fe"] = (p["head"][0] + 14.0, p["head"][1] + 68.0)
        p["fhand"] = (p["head"][0] + 28.0, p["head"][1] - 8.0)
        frames.append(p)
    return frames


def throw_frames(pal: dict) -> list[dict]:
    """Row 15 (4 frames): Collar-grab reach (0), clinch pull (1), forceful two-handed shove (2), recovery (3)."""
    frames = []
    b = pal["bulk"]

    p = base_pose(pal)
    shift_body(p, 16.0, 6.0)
    p["head"] = (p["head"][0] + 10.0, p["head"][1] + 4.0)
    p["head_tilt"] = 8.0
    p["be"] = (p["bs"][0] + 58.0, p["bs"][1] + 14.0)
    p["bhand"] = (334.0, p["bs"][1] + 6.0)
    p["fe"] = (p["fs"][0] + 62.0, p["fs"][1] + 24.0)
    p["fhand"] = (322.0, p["fs"][1] + 14.0)
    p["bhand_open"] = True
    p["fhand_open"] = True
    set_leg(p, "b", (CX + 70.0 * b, FOOT_Y - 12.0), (CX + 64.0 * b, 434.0))
    set_leg(p, "f", (CX - 56.0 * b, FOOT_Y - 12.0), (CX - 36.0 * b, 438.0), angle=10.0)
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, -20.0, 14.0)
    p["head"] = (p["head"][0] - 8.0, p["head"][1] + 6.0)
    p["expr"] = "grit"
    p["be"] = (p["bs"][0] + 16.0, p["bs"][1] + 56.0)
    p["bhand"] = (p["bs"][0] + 56.0, p["bs"][1] + 28.0)
    p["fe"] = (p["fs"][0] - 6.0, p["fs"][1] + 66.0)
    p["fhand"] = (p["fs"][0] + 56.0, p["fs"][1] + 32.0)
    set_leg(p, "b", (CX + 56.0 * b, FOOT_Y - 12.0), (CX + 38.0 * b, 438.0))
    set_leg(p, "f", (CX - 68.0 * b, FOOT_Y - 12.0), (CX - 64.0 * b, 440.0))
    frames.append(p)

    # 2: forceful two-handed shoulder shove with realistic motion streaks (safely inside x<=368!)
    p = base_pose(pal)
    shift_body(p, 22.0, 12.0)
    p["head"] = (p["head"][0] + 16.0, p["head"][1] + 6.0)
    p["head_tilt"] = 10.0
    p["expr"] = "grit"
    p["be"] = (p["bs"][0] + 58.0, p["bs"][1] + 6.0)
    p["bhand"] = (330.0, p["bs"][1] - 4.0)
    p["fe"] = (p["fs"][0] + 74.0, p["fs"][1] + 12.0)
    p["fhand"] = (324.0, p["fs"][1] + 8.0)
    p["bhand_open"] = True
    p["fhand_open"] = True
    set_leg(p, "b", (CX + 80.0 * b, FOOT_Y - 12.0), (CX + 74.0 * b, 434.0))
    set_leg(p, "f", (82.0, FOOT_Y - 16.0), (144.0, 444.0), angle=24.0)
    cy = p["fhand"][1]
    p["streaks"] = [
        {"p0": (326, cy - 26), "p1": (364, cy - 38), "w0": 3.4, "w1": 1.0, "alpha": 165},
        {"p0": (332, cy - 4), "p1": (366, cy - 4), "w0": 4.2, "w1": 1.2, "alpha": 185, "color": (250, 246, 232)},
        {"p0": (326, cy + 22), "p1": (364, cy + 34), "w0": 3.4, "w1": 1.0, "alpha": 165},
    ]
    frames.append(p)

    p = base_pose(pal)
    shift_body(p, 8.0, 4.0)
    p["be"] = (p["bs"][0] + 36.0, p["bs"][1] + 44.0)
    p["bhand"] = (p["bs"][0] + 66.0, p["bs"][1] + 16.0)
    p["fe"] = (p["fs"][0] + 10.0, p["fs"][1] + 64.0)
    p["fhand"] = (p["fs"][0] + 52.0, p["fs"][1] + 32.0)
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
    ("sweep", 12, sweep_frames),
    ("air", 13, air_frames),
    ("crouch_block", 14, crouch_block_frames),
    ("throw", 15, throw_frames),
]


def build_fighter_sheet(char_id: str, pal: dict) -> Image.Image:
    rows = len(ANIMATIONS)
    sheet = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    for _name, row, maker in ANIMATIONS:
        frames = maker(pal)
        for col, pose in enumerate(frames[:COLS]):
            frame = draw_fighter_frame(pal, pose)
            sheet.alpha_composite(frame, (col * CELL_W, row * CELL_H))
    return sheet


# ---------------------------------------------------------------------------
# Gritty Painted FX Sprites (2x Supersampled -> LANCZOS to exact Arena sizes)
# ---------------------------------------------------------------------------


def build_hit_spark(path: str) -> None:
    """5 x (48x48) = 240x48: incandescent kinetic impact slashes & ember spark shards."""
    frames = 5
    size = 48
    ss = size * 2  # 96x96
    sheet = Image.new("RGBA", (frames * size, size), (0, 0, 0, 0))
    cx, cy = ss * 0.5, ss * 0.5

    for f in range(frames):
        img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        t = f / (frames - 1)
        fade = 1.0 - t * 0.78

        halo = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
        hd = ImageDraw.Draw(halo)
        hr = 14 + t * 22
        hd.ellipse([cx - hr, cy - hr, cx + hr, cy + hr],
                   fill=(242, 134, 46, int(115 * (1.0 - t * 0.88))))
        halo = halo.filter(ImageFilter.GaussianBlur(4.5))
        img.alpha_composite(halo)

        if f <= 2:
            slash_angles = (0.35, -0.78, 1.88)
            for idx, a in enumerate(slash_angles):
                ca, sa = math.cos(a), math.sin(a)
                nx, ny = -sa, ca
                reach = (18 + t * 26) * (1.12 if idx == 0 else 0.85)
                thick = max(1.2, (5.5 - t * 3.8) * (1.1 if idx == 0 else 0.78))
                poly = [
                    (cx - ca * reach * 0.55, cy - sa * reach * 0.55),
                    (cx + nx * thick, cy + ny * thick),
                    (cx + ca * reach, cy + sa * reach),
                    (cx - nx * thick, cy - ny * thick),
                ]
                col = (255, 246, 218) if idx == 0 else (250, 174, 68)
                d.polygon(poly, fill=rgba(col, int(245 * fade)))

        rng = random.Random(101 + f * 7)
        for k in range(11):
            a = k * (math.tau / 11.0) + rng.uniform(-0.22, 0.22)
            r0 = 6 + t * 18 + (k % 3) * 4
            r1 = r0 + (16 - t * 7) + rng.uniform(0, 6)
            x0, y0 = cx + math.cos(a) * r0, cy + math.sin(a) * r0
            x1, y1 = cx + math.cos(a) * r1, cy + math.sin(a) * r1
            nx, ny = -math.sin(a), math.cos(a)
            w = max(0.8, (2.6 - t * 1.4) * (1.0 if k % 2 == 0 else 0.65))
            shard = [
                (x0 + nx * w, y0 + ny * w),
                (x1, y1),
                (x0 - nx * w, y0 - ny * w),
            ]
            col = (255, 236, 174) if k % 3 == 0 else (246, 146, 52)
            d.polygon(shard, fill=rgba(col, int(240 * (1.0 - t * 0.74))))

        if f <= 1:
            cr = 12 - f * 4
            d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr],
                      fill=(255, 252, 242, int(245 * (1.0 - f * 0.36))))

        sheet.alpha_composite(img.resize((size, size), Image.LANCZOS), (f * size, 0))
    sheet.save(path)


def build_block_spark(path: str) -> None:
    """4 x (40x40) = 160x40: crisp steel-blue deflection arc & glancing metallic sparks."""
    frames = 4
    size = 40
    ss = size * 2  # 80x80
    sheet = Image.new("RGBA", (frames * size, size), (0, 0, 0, 0))
    cx, cy = ss * 0.5, ss * 0.5

    for f in range(frames):
        img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        t = f / (frames - 1)
        alpha = int(240 * (1.0 - t * 0.85))

        glow_img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_img)
        gr = 14 + t * 14
        gd.ellipse([cx - gr * 0.7, cy - gr, cx + gr * 0.7, cy + gr],
                   fill=(128, 196, 234, int(95 * (1.0 - t * 0.8))))
        glow_img = glow_img.filter(ImageFilter.GaussianBlur(4.0))
        img.alpha_composite(glow_img)

        r_outer = 14 + t * 18
        r_inner = 9 + t * 14
        d.arc([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer],
              -68, 68, fill=(224, 244, 255, alpha), width=max(2, int(5 - t * 3)))
        if f <= 2:
            d.arc([cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner],
                  -52, 52, fill=(142, 206, 238, int(alpha * 0.85)), width=max(1, int(3 - t * 1.5)))

        for a_deg in (-80, -48, -18, 18, 48, 80):
            a = math.radians(a_deg)
            r0 = 8 + t * 14
            r1 = r0 + (12 - t * 4)
            x0, y0 = cx + math.cos(a) * r0, cy + math.sin(a) * r0
            x1, y1 = cx + math.cos(a) * r1, cy + math.sin(a) * r1
            d.line([(x0, y0), (x1, y1)], fill=(214, 240, 255, int(alpha * 0.9)),
                   width=max(1, int(2.5 - t)))

        sheet.alpha_composite(img.resize((size, size), Image.LANCZOS), (f * size, 0))
    sheet.save(path)


def build_dust(path: str) -> None:
    """4 x (32x24) = 128x24: layered gritty concrete/asphalt floor dust puffs."""
    frames = 4
    w, h = 32, 24
    sw, sh = w * 2, h * 2  # 64x48
    sheet = Image.new("RGBA", (frames * w, h), (0, 0, 0, 0))

    puffs_base = [
        (-14, 0, 9.0, 0.85),
        (-5, -3, 11.5, 1.0),
        (5, -2, 11.0, 0.95),
        (14, 1, 8.5, 0.80),
        (0, -6, 9.5, 0.75),
    ]
    for f in range(frames):
        img = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        t = f / (frames - 1)
        base_a = int(170 * (1.0 - t * 0.80))

        for idx, (ox, oy, rad, weight) in enumerate(puffs_base):
            spread = 1.0 + t * 0.72
            px = sw * 0.5 + ox * spread
            py = sh - 10.0 + oy - t * (10.0 + (idx % 3) * 3.0)
            r = rad * (0.72 + t * 0.55)
            a = int(base_a * weight)
            d.ellipse([px - r, py - r * 0.78, px + r, py + r * 0.78],
                      fill=(166, 158, 144, a))
            d.ellipse([px - r * 0.82, py - r * 0.76, px + r * 0.72, py + r * 0.35],
                      fill=(212, 204, 190, int(a * 0.85)))

        img = img.filter(ImageFilter.GaussianBlur(1.4))
        if f <= 2:
            dd = ImageDraw.Draw(img)
            for gx, gy in ((16 - f * 4, 34 - f * 5), (48 + f * 4, 32 - f * 4), (30, 26 - f * 6)):
                dd.rectangle([gx, gy, gx + 2, gy + 2], fill=(116, 108, 96, int(185 * (1.0 - t * 0.7))))

        sheet.alpha_composite(img.resize((w, h), Image.LANCZOS), (f * w, 0))
    sheet.save(path)


def build_shadow(path: str) -> None:
    """64x16 soft elliptical contact shadow (rendered 2x at 128x32 -> LANCZOS)."""
    w, h = 64, 16
    sw, sh = w * 2, h * 2  # 128x32
    img = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([8, 4, sw - 8, sh - 4], fill=(10, 8, 12, 72))
    d.ellipse([20, 7, sw - 20, sh - 7], fill=(8, 6, 10, 105))
    d.ellipse([34, 10, sw - 34, sh - 10], fill=(4, 4, 8, 120))
    img = img.filter(ImageFilter.GaussianBlur(4.2))
    img.resize((w, h), Image.LANCZOS).save(path)


# ---------------------------------------------------------------------------
# Optional Legacy Stages & Icon (ONLY generated when --stages is passed)
# ---------------------------------------------------------------------------

STAGE_W, STAGE_H = 320, 180
STAGE_FLOOR_Y = 150


def _save_stage(img: Image.Image, path: str) -> None:
    img.convert("RGB").resize((1280, 720), Image.NEAREST).save(path)


def stage_breakroom(path: str) -> None:
    img = Image.new("RGBA", (STAGE_W, STAGE_H), (190, 183, 168, 255))
    d = ImageDraw.Draw(img)
    color_bands(d, (0, 15, STAGE_W, 114), [
        (202, 195, 180), (194, 187, 172), (186, 179, 164), (179, 172, 158),
    ])
    for sx in (80, 160, 240):
        d.line([(sx, 16), (sx, 113)], fill=(172, 165, 152))
    d.rectangle([0, 0, STAGE_W - 1, 12], fill=(104, 102, 96))
    for lx in (38, 138, 238):
        d.rectangle([lx - 2, 2, lx + 46, 8], fill=(136, 134, 126))
        d.rectangle([lx, 4, lx + 44, 7], fill=(238, 244, 224))
        stepped_glow(img, (lx + 22, 12), 26, (255, 250, 224), rings=3, max_alpha=20)
    d.rectangle([0, 114, STAGE_W - 1, STAGE_FLOOR_Y - 1], fill=(150, 142, 126))
    checker(d, (0, STAGE_FLOOR_Y, STAGE_W, STAGE_H), (156, 151, 140), (149, 144, 134), 12, 0)
    _save_stage(img, path)


def stage_parkinglot(path: str) -> None:
    img = Image.new("RGBA", (STAGE_W, STAGE_H), (46, 52, 86, 255))
    d = ImageDraw.Draw(img)
    color_bands(d, (0, 0, STAGE_W, 108), [
        (46, 52, 86), (68, 72, 110), (104, 86, 118),
        (156, 106, 112), (204, 134, 102), (226, 174, 116),
    ])
    d.rectangle([0, 96, STAGE_W - 1, 144], fill=(88, 80, 84))
    d.rectangle([104, 91, 218, 107], fill=(44, 46, 58), outline=(124, 120, 116))
    draw_text(d, "AVERAGE MART", 125, 96, (238, 216, 134), 1, shadow=(24, 24, 30))
    d.rectangle([0, 144, STAGE_W - 1, 149], fill=(124, 120, 116))
    color_bands(d, (0, STAGE_FLOOR_Y + 1, STAGE_W, STAGE_H), [
        (76, 74, 84), (68, 66, 76), (60, 58, 68),
    ])
    _save_stage(img, path)


def stage_backyard(path: str) -> None:
    img = Image.new("RGBA", (STAGE_W, STAGE_H), (88, 122, 168, 255))
    d = ImageDraw.Draw(img)
    color_bands(d, (0, 0, STAGE_W, 102), [
        (88, 122, 168), (118, 142, 178), (168, 156, 166),
        (216, 164, 132), (236, 186, 126), (244, 212, 148),
    ])
    plank_w = 10
    for idx in range(STAGE_W // plank_w):
        x0 = idx * plank_w
        top_y = 76 if idx == 13 else 96
        d.rectangle([x0, top_y, x0 + plank_w - 2, STAGE_FLOOR_Y - 1], fill=(150, 122, 92))
    d.rectangle([0, STAGE_FLOOR_Y, STAGE_W - 1, STAGE_H - 1], fill=(78, 112, 66))
    _save_stage(img, path)


def build_icon(path: str) -> None:
    size = 64
    img = Image.new("RGBA", (size, size), (26, 28, 38, 255))
    d = ImageDraw.Draw(img)
    dither_gradient(img, (0, 0, size, size), (40, 46, 66), (22, 24, 34))
    draw_text(d, "AC", 18, 20, (244, 236, 214), 2, shadow=(20, 20, 26))
    img.resize((256, 256), Image.NEAREST).save(path)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Average Combat sprites and FX.")
    parser.add_argument(
        "--stages",
        action="store_true",
        help="Also regenerate legacy stage backgrounds and icon.png (off by default).",
    )
    args = parser.parse_args()

    os.makedirs(os.path.join(ASSETS, "sprites", "fighters"), exist_ok=True)
    os.makedirs(os.path.join(ASSETS, "sprites", "fx"), exist_ok=True)

    for char_id, pal in FIGHTERS.items():
        sheet = build_fighter_sheet(char_id, pal)
        out = os.path.join(ASSETS, "sprites", "fighters", f"{char_id}.png")
        sheet.save(out)
        print("wrote", os.path.relpath(out, ROOT), sheet.size)

    fx_outputs = [
        ("hit.png", build_hit_spark),
        ("block.png", build_block_spark),
        ("dust.png", build_dust),
        ("shadow.png", build_shadow),
    ]
    for fname, fn in fx_outputs:
        out = os.path.join(ASSETS, "sprites", "fx", fname)
        fn(out)
        print("wrote", os.path.relpath(out, ROOT), Image.open(out).size)

    if args.stages:
        os.makedirs(os.path.join(ASSETS, "stages"), exist_ok=True)
        stage_breakroom(os.path.join(ASSETS, "stages", "breakroom.png"))
        stage_parkinglot(os.path.join(ASSETS, "stages", "parkinglot.png"))
        stage_backyard(os.path.join(ASSETS, "stages", "backyard.png"))
        build_icon(os.path.join(ROOT, "icon.png"))
        print("stages & icon regenerated")

    print("art done")


if __name__ == "__main__":
    main()
