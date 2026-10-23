#!/usr/bin/env python3
"""Generate stylized 3D device icons (USDZ) for LiquidDynamo.

Usage:  python3 generate_models.py <out_dir> [device_name ...]

Every model is original, brand-neutral geometry (no logos or trademarked artwork),
built from signed-distance shapes and exported with UsdPreviewSurface materials.
"""
import math
import os
import sys
import time

import numpy as np

from sdflib import *  # noqa: F401,F403


def bb(cx, cy, cz, hx, hy, hz):
    return (cx - hx, cy - hy, cz - hz), (cx + hx, cy + hy, cz + hz)


def mk(name, mat, sdf, box, voxel, tris):
    lo, hi = box
    return Part(name, mat, sdf, lo, hi, voxel, tris)


# ----------------------------------------------------------------------------- earbuds
def dev_airpods():
    """Stem-style true wireless earbuds with a charging case."""
    parts = []

    def case(P):
        d = box_r(P, (0, 0, 0), (2.65, 2.2, 1.1), 1.0)
        inner = box_r(P, (0, 0, 0), (2.53, 2.08, 0.98), 0.9)
        groove = np.maximum(np.abs(P[:, 1] - 0.62) - 0.045, -inner)
        return np.maximum(d, -groove)

    parts.append(mk("case", "white_gloss", case, bb(0, 0, 0, 2.8, 2.35, 1.25), 0.04, 26000))
    parts.append(mk("led", "emerald", lambda P: sphere(P, (0, 0.1, 1.12), 0.09),
                    bb(0, 0.1, 1.12, 0.2, 0.2, 0.2), 0.025, 600))
    for sx, nm in ((-1, "budL"), (1, "budR")):
        def bud(P, sx=sx):
            q = loc(P, (sx * 1.5, 0.7, 2.4), rotz(math.radians(-sx * 9)))
            head = ellipsoid(q, (0, 0, 0), (0.80, 0.88, 0.72))
            stem = capsule(q, (0, -0.2, 0), (0, -2.6, 0.06), 0.31)
            return smin(head, stem, 0.32)

        def noz(P, sx=sx):
            return cyl_r(P, (sx * (1.5 - 0.78), 0.72, 2.4), 0.3, 0.1, 0.05, axis=0)

        parts.append(mk(nm, "white_gloss", bud, bb(sx * 1.5, -0.4, 2.4, 1.5, 2.6, 1.3), 0.04, 9000))
        parts.append(mk(nm + "_speaker", "black_matte", noz,
                        bb(sx * (1.5 - 0.78), 0.72, 2.4, 0.4, 0.5, 0.5), 0.03, 800))
    return parts, 0, 18


def dev_earbuds():
    """Generic true wireless earbuds with a smoked-glass lid case."""
    parts = []

    def lower(P):
        return np.maximum(box_r(P, (0, 0, 0), (2.4, 1.7, 1.5), 1.3), P[:, 1] - 0.04)

    def lid(P):
        return np.maximum(box_r(P, (0, 0, 0), (2.4, 1.7, 1.5), 1.3), 0.08 - P[:, 1])

    parts.append(mk("case", "graphite", lower, bb(0, -0.8, 0, 2.55, 1.0, 1.65), 0.05, 9000))
    parts.append(mk("lid", "smoke_glass", lid, bb(0, 0.9, 0, 2.55, 0.9, 1.65), 0.05, 9000))
    parts.append(mk("led", "emerald", lambda P: sphere(P, (0, -0.3, 1.5), 0.09),
                    bb(0, -0.3, 1.5, 0.2, 0.2, 0.2), 0.025, 600))
    for sx, nm in ((-1, "budL"), (1, "budR")):
        def bud(P, sx=sx):
            q = loc(P, (sx * 1.4, 0.0, 2.7), rotz(math.radians(-sx * 12)))
            body = ellipsoid(q, (0, 0.2, 0), (0.78, 0.66, 0.66))
            stem = capsule(q, (sx * 0.1, 0.0, 0), (sx * 0.05, -1.7, 0.0), 0.27)
            nozzle = capsule(q, (0, 0.2, 0), (-sx * 0.85, 0.2, 0.0), 0.3)
            return smin(smin(body, stem, 0.3), nozzle, 0.25)

        def tip(P, sx=sx):
            return ellipsoid(P, (sx * 1.4 - sx * 1.05, 0.2, 2.7), (0.34, 0.42, 0.42))

        parts.append(mk(nm, "black_gloss", bud, bb(sx * 1.4, -0.7, 2.7, 1.5, 1.7, 1.2), 0.04, 8000))
        parts.append(mk(nm + "_tip", "rubber", tip, bb(sx * 0.35, 0.2, 2.7, 0.5, 0.6, 0.6), 0.03, 1200))
    return parts, 0, 18


def dev_earphones():
    """Wired in-ear earphones with a V-cable and a plug."""
    parts = []
    cable_pts = []
    for sx in (-1, 1):
        cable_pts.append(bezier((0, -1.3, 0), (0, 0.5, 0), (sx * 1.75, 1.45, 0), 18))
    cable_pts.append(np.array([[0, -1.3, 0], [0, -3.9, 0]], np.float32))

    def cable(P):
        d = None
        for pts in cable_pts:
            c = chain(P, pts, 0.17)
            d = c if d is None else np.minimum(d, c)
        return d

    parts.append(mk("cable", "black_matte", cable, bb(0, -1.2, 0, 2.2, 3.1, 0.4), 0.05, 9000))
    parts.append(mk("joint", "rubber",
                    lambda P: capsule(P, (0, -1.15, 0), (0, -2.1, 0), 0.34),
                    bb(0, -1.6, 0, 0.5, 0.8, 0.5), 0.04, 1500))

    def plug(P):
        collar = cyl_r(P, (0, -4.0, 0), 0.45, 0.35, 0.1, axis=1)
        pin = capsule(P, (0, -4.3, 0), (0, -5.6, 0), 0.26)
        return smin(collar, pin, 0.1)

    parts.append(mk("plug", "aluminum", plug, bb(0, -4.7, 0, 0.6, 1.2, 0.6), 0.03, 2500))
    for sx, nm in ((-1, "budL"), (1, "budR")):
        def bud(P, sx=sx):
            q = loc(P, (sx * 2.1, 1.55, 0))
            body = ellipsoid(q, (0, 0, 0), (0.62, 0.55, 0.55))
            nozzle = capsule(q, (0, 0, 0), (-sx * 0.8, 0.2, 0), 0.30)
            return smin(body, nozzle, 0.25)

        def tip(P, sx=sx):
            return ellipsoid(P, (sx * 2.1 - sx * 1.02, 1.75, 0), (0.34, 0.42, 0.42))

        parts.append(mk(nm, "white_gloss", bud, bb(sx * 2.1, 1.6, 0, 1.1, 0.9, 0.9), 0.03, 4000))
        parts.append(mk(nm + "_tip", "rubber", tip, bb(sx * 1.08, 1.75, 0, 0.5, 0.6, 0.6), 0.03, 1200))
    return parts, 0, 12


def dev_headphones():
    parts = []
    ang = np.radians(np.linspace(12, 168, 40))
    band_pts = np.stack([5.0 * np.cos(ang), 5.0 * np.sin(ang), np.zeros_like(ang)], 1).astype(np.float32)

    def band(P):
        d = chain(P, band_pts, 0.3)
        for sx in (-1, 1):
            d = np.minimum(d, capsule(P, (sx * 4.9, 1.0, 0), (sx * 5.0, 0.0, 0), 0.28))
        return d

    parts.append(mk("band", "graphite", band, bb(0, 2.6, 0, 5.5, 2.9, 0.5), 0.06, 12000))
    parts.append(mk("pad", "black_matte",
                    lambda P: box_r(P, (0, 4.6, 0), (1.9, 0.22, 0.55), 0.2),
                    bb(0, 4.6, 0, 2.0, 0.35, 0.65), 0.04, 2500))
    for sx, nm in ((-1, "cupL"), (1, "cupR")):
        parts.append(mk(nm, "graphite",
                        lambda P, sx=sx: cyl_r(P, (sx * 5.2, -1.6, 0), 2.2, 0.85, 0.55, axis=0),
                        bb(sx * 5.2, -1.6, 0, 1.0, 2.4, 2.4), 0.06, 7000))
        parts.append(mk(nm + "_cushion", "black_matte",
                        lambda P, sx=sx: torus(P, (sx * 3.95, -1.6, 0), 1.6, 0.62, axis=0),
                        bb(sx * 3.95, -1.6, 0, 0.8, 2.4, 2.4), 0.05, 7000))
        parts.append(mk(nm + "_ring", "emerald",
                        lambda P, sx=sx: torus(P, (sx * 6.02, -1.6, 0), 1.0, 0.05, axis=0),
                        bb(sx * 6.02, -1.6, 0, 0.2, 1.2, 1.2), 0.03, 2500))
    return parts, 0, 22


def dev_speaker():
    parts = []

    def body(P):
        return cyl_r(P, (0, 0, 0), 3.2, 4.0, 1.1, axis=1)

    def rings(P):
        d = None
        for y0 in (-1.9, -0.5, 0.9, 2.3):
            c = torus(P, (0, y0, 0), 3.2, 0.11, 1)
            d = c if d is None else np.minimum(d, c)
        return d

    parts.append(mk("body", "fabric", body, bb(0, 0, 0, 3.4, 4.2, 3.4), 0.07, 9000))
    parts.append(mk("rings", "graphite", rings, bb(0, 0.2, 0, 3.5, 2.6, 3.5), 0.035, 12000))
    parts.append(mk("cap", "aluminum",
                    lambda P: cyl_r(P, (0, 4.1, 0), 2.7, 0.18, 0.1, axis=1),
                    bb(0, 4.1, 0, 2.9, 0.4, 2.9), 0.04, 3000))

    def buttons(P):
        d = None
        for a in (90, 210, 330):
            x, z = 1.35 * math.cos(math.radians(a)), 1.35 * math.sin(math.radians(a))
            c = cyl_r(P, (x, 4.36, z), 0.42, 0.1, 0.06, axis=1)
            d = c if d is None else np.minimum(d, c)
        return d

    parts.append(mk("buttons", "black_matte", buttons, bb(0, 4.36, 0, 2.0, 0.25, 2.0), 0.03, 3000))
    parts.append(mk("base", "rubber",
                    lambda P: cyl_r(P, (0, -4.05, 0), 3.0, 0.3, 0.15, axis=1),
                    bb(0, -4.05, 0, 3.2, 0.5, 3.2), 0.05, 3000))
    parts.append(mk("led", "emerald",
                    lambda P: capsule(P, (-0.6, 3.1, 3.17), (0.6, 3.1, 3.17), 0.09),
                    bb(0, 3.1, 3.17, 0.8, 0.2, 0.2), 0.025, 1000))
    return parts, 6, -20


# ----------------------------------------------------------------------------- input devices
def mouse_body(P):
    a = ellipsoid(P, (0, 0.0, 0), (2.8, 1.45, 5.3))
    b = ellipsoid(P, (0, -0.2, -1.2), (2.65, 1.25, 4.5))
    d = smin(a, b, 0.8)
    d = smax(d, -0.95 - P[:, 1], 0.35)
    groove = np.maximum(np.maximum(np.abs(P[:, 0]) - 0.06, 0.7 - P[:, 2]), 0.0 - P[:, 1])
    return np.maximum(d, -groove)


def dev_mouse():
    parts = [mk("body", "white_gloss", mouse_body, bb(0, 0.3, 0, 3.0, 1.5, 5.5), 0.04, 20000)]
    ty = top_y(mouse_body, 0.35, 1.5)
    parts.append(mk("wheel", "black_matte",
                    lambda P: cyl_r(P, (0, ty - 0.08, 1.5), 0.5, 0.3, 0.12, axis=0),
                    bb(0, ty - 0.08, 1.5, 0.45, 0.7, 0.7), 0.03, 1800))
    return parts, 20, -32


def dev_keyboard():
    def plate(P):
        return box_r(P, (0, 0, 0), (13.0, 0.5, 5.1), 0.45)

    def keys(P):
        px = pz = 1.9
        i = np.clip(np.round(P[:, 0] / px + 6.0), 0, 12)
        j = np.clip(np.round(P[:, 2] / pz + 2.0), 0, 4)
        q = np.stack([P[:, 0] - (i - 6.0) * px, P[:, 1], P[:, 2] - (j - 2.0) * pz], 1)
        d = box_r(q, (0, 0.80, 0), (0.78, 0.33, 0.78), 0.2)
        d = np.where((j == 4) & (i >= 3) & (i <= 9), 1e3, d)
        space = box_r(P, (0, 0.80, 3.8), (6.4, 0.33, 0.78), 0.2)
        return np.minimum(d, space)

    parts = [mk("plate", "aluminum", plate, bb(0, 0, 0, 13.2, 0.6, 5.3), 0.12, 9000),
             mk("keys", "black_matte", keys, bb(0, 0.75, 0, 12.8, 0.55, 4.9), 0.11, 22000)]
    return parts, 30, -20


def dev_trackpad():
    parts = [mk("base", "aluminum",
                lambda P: box_r(P, (0, 0, 0), (6.2, 0.3, 4.3), 0.25),
                bb(0, 0, 0, 6.4, 0.5, 4.5), 0.06, 8000),
             mk("glass", "black_gloss",
                lambda P: box_r(P, (0, 0.2, 0), (5.85, 0.12, 3.95), 0.1),
                bb(0, 0.2, 0, 6.0, 0.3, 4.1), 0.05, 6000)]
    return parts, 30, -20


# ----------------------------------------------------------------------------- storage
def dev_ssd():
    def body(P):
        d = box_r(P, (0, 0, 0), (5.0, 0.62, 2.9), 0.5)
        for gx in (-1.8, -0.9, 0.0, 0.9, 1.8):
            d = np.maximum(d, -np.maximum(np.abs(P[:, 0] - gx) - 0.05, 0.38 - P[:, 1]))
        slot = box_r(P, (5.05, 0.0, 0.0), (0.95, 0.17, 0.62), 0.15)
        return np.maximum(d, -slot)

    parts = [mk("body", "graphite", body, bb(0, 0, 0, 5.2, 0.8, 3.1), 0.045, 22000),
             mk("port", "black_matte",
                lambda P: box_r(P, (4.3, 0, 0), (0.45, 0.06, 0.45), 0.05),
                bb(4.3, 0, 0, 0.6, 0.2, 0.6), 0.03, 800),
             mk("led", "emerald",
                lambda P: capsule(P, (-4.0, 0.05, 2.88), (-3.1, 0.05, 2.88), 0.08),
                bb(-3.5, 0.05, 2.88, 0.7, 0.2, 0.2), 0.025, 600)]
    return parts, 28, -28


def dev_usb():
    def conn(P):
        d = box_r(P, (3.1, 0, 0), (1.5, 0.3, 0.85), 0.12)
        return np.maximum(d, -box_r(P, (3.3, 0, 0), (0.35, 1.0, 0.22), 0.1))

    parts = [mk("body", "black_gloss",
                lambda P: box_r(P, (-1.0, 0, 0), (2.7, 0.66, 1.05), 0.5),
                bb(-1.0, 0, 0, 2.9, 0.85, 1.25), 0.04, 9000),
             mk("connector", "aluminum", conn, bb(3.1, 0, 0, 1.7, 0.5, 1.0), 0.03, 6000),
             mk("ring", "aluminum",
                lambda P: torus(P, (-3.95, 0, 0), 0.5, 0.12, axis=2),
                bb(-3.95, 0, 0, 0.8, 0.8, 0.3), 0.03, 3000),
             mk("led", "emerald", lambda P: sphere(P, (-2.6, 0.64, 0), 0.1),
                bb(-2.6, 0.64, 0, 0.2, 0.2, 0.2), 0.025, 500)]
    return parts, 25, -25


# ----------------------------------------------------------------------------- phones & tablets
def _phone(w, h, d, corner, edge, frame_mat, back_mat, style):
    frame = lambda P: slab_r(P, (0, 0, 0), (w / 2, h / 2), d / 2, corner, edge)
    scr = lambda P: slab_r(P, (0, 0, d / 2 - 0.105), (w / 2 - edge, h / 2 - edge), 0.12, corner - edge, 0.045)
    back = lambda P: slab_r(P, (0, 0, -(d / 2 - 0.105)), (w / 2 - edge, h / 2 - edge), 0.12, corner - edge, 0.045)
    zb = -(d / 2) - 0.03
    parts = [mk("frame", frame_mat, frame, bb(0, 0, 0, w / 2 + 0.1, h / 2 + 0.1, d / 2 + 0.1), 0.05, 20000),
             mk("screen", "screen", scr, bb(0, 0, d / 2 - 0.105, w / 2, h / 2, 0.2), 0.04, 5000),
             mk("back", back_mat, back, bb(0, 0, -(d / 2 - 0.105), w / 2, h / 2, 0.2), 0.04, 5000)]
    ytop = h / 2
    if style == "phone":
        cx, cy = -1.55, ytop - 1.9
        plateau = lambda P: slab_r(P, (cx, cy, zb), (1.5, 1.5), 0.09, 0.6, 0.05)
        parts.append(mk("plateau", "black_gloss", plateau, bb(cx, cy, zb, 1.6, 1.6, 0.2), 0.04, 3500))
        lenses = [(cx - 0.6, cy + 0.6), (cx + 0.6, cy - 0.6)]
        zl = zb - 0.1
        parts.append(mk("lenses", "lens",
                        lambda P: np.minimum(*[cyl_r(P, (x, y, zl), 0.5, 0.1, 0.05, axis=2) for x, y in lenses]),
                        bb(cx, cy, zl, 1.5, 1.5, 0.25), 0.03, 3500))
        parts.append(mk("rings", "aluminum",
                        lambda P: np.minimum(*[torus(P, (x, y, zl - 0.04), 0.52, 0.07, axis=2) for x, y in lenses]),
                        bb(cx, cy, zl, 1.5, 1.5, 0.3), 0.025, 3500))
        parts.append(mk("flash", "soft_white",
                        lambda P: cyl_r(P, (cx + 0.6, cy + 0.6, zl), 0.2, 0.06, 0.03, axis=2),
                        bb(cx + 0.6, cy + 0.6, zl, 0.3, 0.3, 0.2), 0.02, 600))
    else:
        cx = -1.9
        cy = ytop - 2.0
        pill = lambda P: slab_r(P, (cx, cy, zb), (0.8, 1.7), 0.09, 0.8, 0.05)
        parts.append(mk("camera_bar", "black_gloss", pill, bb(cx, cy, zb, 0.9, 1.8, 0.2), 0.04, 3000))
        zl = zb - 0.1
        ys = (cy + 0.95, cy, cy - 0.95)
        parts.append(mk("lenses", "lens",
                        lambda P: np.minimum.reduce([cyl_r(P, (cx, y, zl), 0.4, 0.1, 0.05, axis=2) for y in ys]),
                        bb(cx, cy, zl, 0.7, 1.6, 0.25), 0.03, 3500))
        parts.append(mk("rings", "aluminum",
                        lambda P: np.minimum.reduce([torus(P, (cx, y, zl - 0.04), 0.42, 0.06, axis=2) for y in ys]),
                        bb(cx, cy, zl, 0.7, 1.6, 0.3), 0.025, 3500))
        parts.append(mk("flash", "soft_white",
                        lambda P: cyl_r(P, (cx + 1.0, cy + 1.0, zl), 0.16, 0.05, 0.03, axis=2),
                        bb(cx + 1.0, cy + 1.0, zl, 0.3, 0.3, 0.2), 0.02, 500))
    return parts


def dev_phone():
    return _phone(7.1, 14.7, 0.78, 1.0, 0.3, "titanium", "back_midnight", "phone"), 0, 150


def dev_android():
    return _phone(7.2, 15.6, 0.82, 0.9, 0.22, "aluminum", "back_sage", "android"), 0, 150


def dev_tablet():
    w, h, d = 17.8, 24.5, 0.62
    parts = [mk("frame", "aluminum",
                lambda P: slab_r(P, (0, 0, 0), (w / 2, h / 2), d / 2, 1.6, 0.25),
                bb(0, 0, 0, w / 2 + 0.1, h / 2 + 0.1, d / 2 + 0.1), 0.1, 12000),
             mk("screen", "screen",
                lambda P: slab_r(P, (0, 0, d / 2 - 0.105), (w / 2 - 0.55, h / 2 - 0.55), 0.12, 1.0, 0.04),
                bb(0, 0, d / 2 - 0.105, w / 2, h / 2, 0.2), 0.07, 6000),
             mk("camera", "aluminum",
                lambda P: slab_r(P, (-6.4, 10.3, -d / 2 - 0.03), (1.3, 1.3), 0.06, 0.45, 0.05),
                bb(-6.4, 10.3, -d / 2 - 0.03, 1.4, 1.4, 0.2), 0.04, 2500),
             mk("lens", "lens",
                lambda P: cyl_r(P, (-6.5, 10.4, -d / 2 - 0.13), 0.45, 0.1, 0.05, axis=2),
                bb(-6.5, 10.4, -d / 2 - 0.13, 0.6, 0.6, 0.2), 0.03, 1500)]
    return parts, 6, 150


# ----------------------------------------------------------------------------- printer, monitor, controller
def dev_printer():
    def body(P):
        d = box_r(P, (0, 0, 0), (10, 3.4, 7.0), 0.9)
        return np.maximum(d, -box_r(P, (0, -1.9, 7.05), (8.6, 0.45, 0.6), 0.15))

    def tray_q(P):
        return loc(P, (0, -2.6, 9.4), rotx(math.radians(-8)))

    def in_q(P):
        return loc(P, (0, 5.6, -5.2), rotx(math.radians(38)))

    parts = [mk("body", "soft_white", body, bb(0, 0, 0, 10.2, 3.6, 7.2), 0.1, 14000),
             mk("lid", "graphite", lambda P: box_r(P, (0, 3.85, 0), (10.1, 0.55, 7.1), 0.4),
                bb(0, 3.85, 0, 10.3, 0.75, 7.3), 0.08, 7000),
             mk("panel", "screen",
                lambda P: slab_r(P, (5.8, 1.3, 7.05), (2.3, 1.0), 0.1, 0.3, 0.06),
                bb(5.8, 1.3, 7.05, 2.5, 1.2, 0.25), 0.04, 2500),
             mk("buttons", "soft_white",
                lambda P: np.minimum(cyl_r(P, (1.6, 1.0, 7.1), 0.35, 0.1, 0.05, axis=2),
                                     cyl_r(P, (2.7, 1.0, 7.1), 0.35, 0.1, 0.05, axis=2)),
                bb(2.15, 1.0, 7.1, 1.3, 0.6, 0.3), 0.03, 1500),
             mk("led", "emerald", lambda P: cyl_r(P, (-8.0, 1.5, 7.08), 0.2, 0.06, 0.03, axis=2),
                bb(-8.0, 1.5, 7.08, 0.4, 0.4, 0.2), 0.02, 500),
             mk("out_tray", "soft_white", lambda P: box_r(tray_q(P), (0, 0, 0), (8.2, 0.1, 2.9), 0.08),
                bb(0, -2.4, 9.4, 8.5, 0.9, 3.4), 0.06, 4000),
             mk("out_paper", "paper",
                lambda P: box_r(loc(P, (0, -2.45, 9.2), rotx(math.radians(-8))), (0, 0, 0), (6.6, 0.03, 3.7), 0.02),
                bb(0, -2.4, 9.2, 6.8, 0.9, 4.0), 0.05, 2500),
             mk("in_tray", "soft_white", lambda P: box_r(in_q(P), (0, 0, 0), (7.2, 0.08, 3.4), 0.06),
                bb(0, 6.5, -6.0, 7.5, 2.9, 3.9), 0.06, 4000),
             mk("in_paper", "paper",
                lambda P: box_r(loc(P, (0, 5.78, -5.25), rotx(math.radians(38))), (0, 0, 0), (5.6, 0.03, 3.0), 0.02),
                bb(0, 6.4, -6.0, 5.8, 2.9, 3.6), 0.05, 2500)]
    return parts, 24, -28


def dev_monitor():
    parts = [mk("bezel", "graphite",
                lambda P: slab_r(P, (0, 0, 0), (12.4, 7.3), 0.42, 0.55, 0.3),
                bb(0, 0, 0, 12.6, 7.5, 0.6), 0.09, 8000),
             mk("screen", "screen",
                lambda P: slab_r(P, (0, 0, 0.32), (11.9, 6.85), 0.12, 0.35, 0.03),
                bb(0, 0, 0.32, 12.0, 7.0, 0.25), 0.05, 6000),
             mk("neck_joint", "aluminum",
                lambda P: box_r(P, (0, -5.9, -0.75), (1.7, 1.1, 0.4), 0.3),
                bb(0, -5.9, -0.75, 1.9, 1.3, 0.6), 0.05, 2500),
             mk("neck", "aluminum",
                lambda P: box_r(P, (0, -8.6, -1.1), (1.3, 2.4, 0.4), 0.25),
                bb(0, -8.6, -1.1, 1.5, 2.6, 0.6), 0.06, 2500),
             mk("base", "aluminum",
                lambda P: cyl_r(P, (0, -11.2, -0.9), 5.2, 0.22, 0.2, axis=1),
                bb(0, -11.2, -0.9, 5.4, 0.5, 5.4), 0.07, 4000)]
    return parts, 0, -25


def pad_body(P):
    c = ellipsoid(P, (0, 0, -0.4), (4.3, 1.55, 2.7))
    g1 = capsule(P, (-3.3, -0.1, 0.3), (-4.2, -0.8, 4.3), 1.3)
    g2 = capsule(P, (3.3, -0.1, 0.3), (4.2, -0.8, 4.3), 1.3)
    return smin(smin(c, g1, 1.4), g2, 1.4)


def dev_gamepad():
    parts = [mk("body", "soft_white", pad_body, bb(0, -0.2, 1.0, 5.8, 2.2, 5.0), 0.07, 16000)]
    ty = lambda x, z: top_y(pad_body, x, z)
    lsx, lsz = -2.5, -0.9
    rsx, rsz = 1.25, 1.05
    dpx, dpz = -1.3, 1.05
    yl, yr, yd = ty(lsx, lsz), ty(rsx, rsz), ty(dpx, dpz)
    parts.append(mk("sticks", "black_matte",
                    lambda P: np.minimum.reduce([
                        torus(P, (lsx, yl - 0.05, lsz), 0.75, 0.16, 1),
                        cyl_r(P, (lsx, yl + 0.28, lsz), 0.52, 0.32, 0.2, 1),
                        torus(P, (rsx, yr - 0.05, rsz), 0.75, 0.16, 1),
                        cyl_r(P, (rsx, yr + 0.28, rsz), 0.52, 0.32, 0.2, 1)]),
                    bb(-0.6, 1.0, 0.1, 3.6, 0.9, 2.4), 0.04, 5000))
    parts.append(mk("dpad", "black_matte",
                    lambda P: np.minimum(box_r(P, (dpx, yd + 0.05, dpz), (0.8, 0.13, 0.27), 0.1),
                                         box_r(P, (dpx, yd + 0.05, dpz), (0.27, 0.13, 0.8), 0.1)),
                    bb(dpx, yd + 0.05, dpz, 1.0, 0.3, 1.0), 0.03, 2500))
    btn = [(2.55, -1.65), (2.55, -0.15), (1.8, -0.9), (3.3, -0.9)]
    yb = [ty(x, z) for x, z in btn]
    parts.append(mk("buttons", "graphite",
                    lambda P: np.minimum.reduce([cyl_r(P, (btn[i][0], yb[i] + 0.04, btn[i][1]), 0.36, 0.14, 0.08, 1)
                                                 for i in (0, 2, 3)]),
                    bb(2.55, 1.0, -0.9, 1.4, 0.8, 1.4), 0.03, 3000))
    parts.append(mk("button_a", "emerald",
                    lambda P: cyl_r(P, (btn[1][0], yb[1] + 0.04, btn[1][1]), 0.36, 0.14, 0.08, 1),
                    bb(btn[1][0], yb[1] + 0.04, btn[1][1], 0.5, 0.3, 0.5), 0.03, 900))
    yg = ty(0, -1.3)
    parts.append(mk("guide", "emerald",
                    lambda P: cyl_r(P, (0, yg + 0.03, -1.3), 0.38, 0.1, 0.06, 1),
                    bb(0, yg + 0.03, -1.3, 0.5, 0.25, 0.5), 0.025, 700))
    for sx, nm in ((-1, "bumperL"), (1, "bumperR")):
        parts.append(mk(nm, "graphite",
                        lambda P, sx=sx: capsule(P, (sx * 3.9, 0.55, -2.1), (sx * 2.3, 0.85, -2.5), 0.3),
                        bb(sx * 3.1, 0.7, -2.3, 1.2, 0.5, 0.6), 0.03, 1500))
    return parts, 32, -25


def dev_generic():
    parts = [mk("shell", "glass", lambda P: box_r(P, (0, 0, 0), (2.2, 2.2, 2.2), 0.9),
                bb(0, 0, 0, 2.4, 2.4, 2.4), 0.06, 8000),
             mk("core", "emerald", lambda P: sphere(P, (0, 0, 0), 0.95),
                bb(0, 0, 0, 1.1, 1.1, 1.1), 0.04, 3000),
             mk("base", "aluminum", lambda P: cyl_r(P, (0, -2.55, 0), 2.1, 0.25, 0.15, axis=1),
                bb(0, -2.55, 0, 2.3, 0.45, 2.3), 0.05, 3000)]
    return parts, 12, 30


DEVICES = {
    # names that LiquidDynamo's resolver already looks up
    "earbuds": dev_earbuds,
    "headphones": dev_headphones,
    "speaker": dev_speaker,
    "ssd_drive": dev_ssd,
    "usb_stick": dev_usb,
    "mouse": dev_mouse,
    "keyboard": dev_keyboard,
    "phone": dev_phone,
    "generic": dev_generic,
    # extra models for new device kinds
    "airpods": dev_airpods,
    "earphones": dev_earphones,
    "trackpad": dev_trackpad,
    "android_phone": dev_android,
    "tablet": dev_tablet,
    "printer": dev_printer,
    "monitor": dev_monitor,
    "gamepad": dev_gamepad,
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "out"
    names = sys.argv[2:] or list(DEVICES)
    os.makedirs(os.path.join(out, "models"), exist_ok=True)
    os.makedirs(os.path.join(out, "previews"), exist_ok=True)
    for n in names:
        t = time.time()
        parts, pitch, yaw = DEVICES[n]()
        build_device(parts, pitch=pitch, yaw=yaw)
        path = write_usdz(parts, os.path.join(out, "models"), n)
        render(parts, size=520, ss=2, yaw=0, pitch=0).save(os.path.join(out, "previews", n + ".png"))
        tris = sum(len(p.faces) for p in parts)
        print(f"{n:14s} {tris:6d} tris  {os.path.getsize(path)/1024:7.0f} KB  {time.time()-t:5.1f}s", flush=True)


if __name__ == "__main__":
    main()
