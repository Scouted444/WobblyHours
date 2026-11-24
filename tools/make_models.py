"""Generates every furniture / prop model of Wobbly Hours as a real .glb file into ../models/.

    python3 tools/make_models.py

The .glb files are normal glTF models: open them in Blender, edit them, or drop in your own
file with the same name. Conventions: metres, front faces -Z, furniture origin = floor centre,
held items / toys origin = grip / body centre (same as the physics colliders in prop.gd).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from glb import Model, validate  # noqa: E402
import numpy as np  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")
MODELS = {}


def model(fn):
    MODELS[fn.__name__] = fn
    return fn


def reg(name, fn):
    MODELS[name] = fn


# shared colours -------------------------------------------------------------
WOOD = (0.62, 0.42, 0.26)
WOOD_L = (0.82, 0.64, 0.45)
WOOD_D = (0.36, 0.24, 0.16)
WHITE = (0.95, 0.95, 0.96)
DARK = (0.09, 0.09, 0.11)
METAL = (0.78, 0.8, 0.85)
BEIGE = (0.82, 0.79, 0.68)


def new(name):
    return Model(name)


# =================================================================== FURNITURE
def make_sofa(name, width, color):
    def f():
        m = new(name)
        c = m.mat("fabric", color, 0.95)
        cl = m.mat("cushion", tuple(min(1, x + 0.1) for x in color), 0.95)
        leg = m.mat("leg", WOOD_D, 0.6)
        for x in (-width / 2 + 0.12, width / 2 - 0.12):
            for z in (-0.38, 0.38):
                m.cyl(0.03, 0.025, 0.12, (x, 0.06, z), leg, seg=10)
        m.rbox((width, 0.32, 0.95), (0, 0.28, 0), c, 0.05)
        m.rbox((width, 0.62, 0.24), (0, 0.78, 0.36), c, 0.08)
        for s in (-1, 1):
            m.rbox((0.28, 0.62, 0.95), (s * (width / 2 - 0.14), 0.55, 0), c, 0.1)
        seat_w = (width - 0.56) / (3 if width > 2.2 else 2 if width > 1.4 else 1)
        n = 3 if width > 2.2 else 2 if width > 1.4 else 1
        for i in range(n):
            x = (i - (n - 1) / 2) * seat_w
            m.rbox((seat_w - 0.03, 0.16, 0.72), (x, 0.52, -0.06), cl, 0.06)
            m.rbox((seat_w - 0.03, 0.42, 0.14), (x, 0.8, 0.2), cl, 0.06, rot=(-8, 0, 0))
        return m
    return f


reg("sofa_purple", make_sofa("sofa_purple", 2.8, (0.45, 0.25, 0.6)))
reg("sofa_blue", make_sofa("sofa_blue", 2.0, (0.25, 0.45, 0.6)))
reg("sofa_pink", make_sofa("sofa_pink", 2.4, (0.8, 0.25, 0.4)))
reg("loveseat_pink", make_sofa("loveseat_pink", 1.2, (0.8, 0.25, 0.4)))


@model
def coffee_table():
    m = new("coffee_table")
    w = m.mat("wood", WOOD_L, 0.5)
    d = m.mat("darkwood", WOOD, 0.6)
    m.rbox((1.3, 0.06, 0.7), (0, 0.42, 0), w, 0.02)
    m.rbox((1.1, 0.03, 0.5), (0, 0.17, 0), d, 0.01)
    for x in (-1, 1):
        for z in (-1, 1):
            m.rbox((0.06, 0.4, 0.06), (x * 0.58, 0.2, z * 0.28), d, 0.015)
    # a few things on top
    m.cyl(0.1, 0.08, 0.1, (-0.35, 0.5, 0.05), m.mat("mug", (0.9, 0.9, 0.2), 0.4), seg=14)
    m.rbox((0.22, 0.02, 0.3), (0.3, 0.46, -0.05), m.mat("magazine", (0.8, 0.2, 0.3), 0.7), 0.005, rot=(0, 20, 0))
    return m


@model
def bookshelf():
    m = new("bookshelf")
    w = m.mat("wood", (0.45, 0.3, 0.2), 0.6)
    m.box((1.6, 2.2, 0.04), (0, 1.1, 0.16), w)
    for s in (0.03, 0.57, 1.11, 1.65, 2.17):
        m.box((1.6, 0.06, 0.35), (0, s, 0), w)
    for x in (-0.78, 0.78):
        m.box((0.05, 2.2, 0.35), (x, 1.1, 0), w)
    rng = random.Random(7)
    for shelf in range(4):
        x = -0.72
        y0 = 0.06 + shelf * 0.54
        while x < 0.66:
            wd = rng.uniform(0.04, 0.09)
            h = rng.uniform(0.28, 0.44)
            col = hsv(rng.random(), 0.55, rng.uniform(0.55, 0.85))
            lean = rng.random() < 0.08
            m.rbox((wd, h, 0.22), (x + wd / 2, y0 + h / 2, 0.0), m.mat("book%d" % int(col[0] * 255 // 16), col, 0.7), 0.005,
                   rot=(0, 0, -12 if lean else 0))
            x += wd + 0.008
            if rng.random() < 0.06:
                x += 0.15
    m.sphere(0.07, (0.5, 0.06 + 3 * 0.54 + 0.08, 0), m.mat("globe", (0.2, 0.5, 0.8), 0.4), scale=(1, 1, 1), seg=14, rings=10)
    return m


def hsv(h, s, v):
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]


@model
def tv_unit():
    m = new("tv_unit")
    w = m.mat("wood", (0.25, 0.17, 0.13), 0.55)
    bl = m.mat("black", (0.04, 0.04, 0.05), 0.35)
    m.rbox((2.4, 0.6, 0.5), (0, 0.3, 0), w, 0.02)
    for x in (-0.6, 0.6):
        m.box((1.1, 0.4, 0.01), (x, 0.3, -0.255), m.mat("drawer", (0.32, 0.22, 0.16), 0.6))
        m.rbox((0.25, 0.025, 0.02), (x, 0.42, -0.27), m.mat("handle", METAL, 0.3, 0.9), 0.01)
    m.rbox((0.5, 0.05, 0.3), (0, 0.63, 0), bl, 0.01)
    m.rbox((0.12, 0.45, 0.06), (0, 0.85, 0.02), bl, 0.01)
    m.rbox((1.9, 1.05, 0.07), (0, 1.3, 0), bl, 0.02)
    m.node("Screen")
    m.box((1.8, 0.95, 0.01), (0, 1.3, -0.036), m.mat("screen", (0.25, 0.55, 1.0), 0.2, emissive=(0.25, 0.55, 1.0)))
    m.node(None)
    m.rbox((0.4, 0.2, 0.3), (-0.9, 0.7, 0), m.mat("console", (0.85, 0.85, 0.9), 0.4), 0.02)
    return m


@model
def plant():
    m = new("plant")
    pot = m.mat("pot", (0.75, 0.4, 0.28), 0.8)
    m.lathe([(0.0, 0.0), (0.14, 0.0), (0.2, 0.3), (0.24, 0.5), (0.2, 0.5), (0.0, 0.46)], (0, 0, 0), pot, seg=20)
    m.cyl(0.2, 0.2, 0.02, (0, 0.47, 0), m.mat("soil", (0.2, 0.12, 0.08), 1.0), seg=16)
    leaf = m.mat("leaf", (0.15, 0.5, 0.2), 0.7)
    leaf2 = m.mat("leaf2", (0.2, 0.6, 0.25), 0.7)
    rng = random.Random(3)
    for i in range(11):
        a = i / 11 * 360
        tilt = rng.uniform(15, 45)
        col = leaf if i % 2 else leaf2
        h = rng.uniform(0.55, 0.9)
        # leaf = flattened ellipsoid, leaning outward
        ar = math.radians(a)
        px, pz = math.sin(ar) * 0.12, math.cos(ar) * 0.12
        m.sphere(0.12, (px + math.sin(ar) * h * 0.2, 0.5 + h * 0.5, pz + math.cos(ar) * h * 0.2), col,
                 scale=(0.4, h * 3.2, 1.0), rot=(0, a - 90, -tilt), seg=10, rings=8)
    return m


@model
def floor_lamp():
    m = new("floor_lamp")
    dk = m.mat("iron", (0.12, 0.12, 0.13), 0.4, 0.6)
    m.cyl(0.18, 0.2, 0.04, (0, 0.02, 0), dk, seg=18)
    m.cyl(0.02, 0.02, 1.55, (0, 0.8, 0), dk, seg=10)
    m.node("Shade")
    m.lathe([(0.12, 1.55), (0.2, 1.65), (0.26, 1.85), (0.2, 1.88), (0.1, 1.76)][::-1][::-1],
            (0, 0, 0), m.mat("shade", (1.0, 0.88, 0.6), 0.9, emissive=(1.0, 0.8, 0.45), emit_strength=0.8), seg=20)
    m.node(None)
    return m


@model
def bed():
    m = new("bed")
    fr = m.mat("frame", (0.4, 0.28, 0.2), 0.55)
    sh = m.mat("sheet", (0.97, 0.97, 0.97), 0.95)
    bk = m.mat("blanket", (0.85, 0.3, 0.35), 0.95)
    pl = m.mat("pillow", (0.95, 0.95, 1.0), 0.95)
    m.rbox((2.0, 0.34, 2.3), (0, 0.27, 0.0), fr, 0.03)
    m.rbox((1.9, 0.26, 2.15), (0, 0.55, 0.02), sh, 0.08)
    m.rbox((1.94, 0.1, 1.35), (0, 0.72, 0.38), bk, 0.04)
    m.rbox((1.96, 0.04, 0.3), (0, 0.74, -0.28), bk, 0.02)
    m.rbox((2.0, 1.05, 0.1), (0, 0.78, -1.14), fr, 0.03)
    m.rbox((2.0, 0.55, 0.08), (0, 0.5, 1.14), fr, 0.03)
    for x in (-0.46, 0.46):
        m.rbox((0.72, 0.16, 0.4), (x, 0.74, -0.8), pl, 0.07, rot=(-8, 0, 0))
    for x in (-1, 1):
        m.cyl(0.05, 0.05, 1.25, (x * 0.98, 0.62, -1.14), fr, seg=10)
        m.sphere(0.06, (x * 0.98, 1.28, -1.14), fr, seg=10, rings=8)
    m.sphere(0.2, (0.5, 0.82, 0.1), m.mat("plush", (0.9, 0.75, 0.3), 1.0), scale=(1, 0.8, 1), seg=12, rings=8)  # teddy
    m.sphere(0.12, (0.5, 0.99, 0.1), m.mat("plush", (0.9, 0.75, 0.3), 1.0), seg=12, rings=8)
    return m


@model
def nightstand():
    m = new("nightstand")
    w = m.mat("wood", WOOD_L, 0.55)
    m.rbox((0.5, 0.5, 0.5), (0, 0.25, 0), w, 0.02)
    m.box((0.44, 0.18, 0.01), (0, 0.33, -0.255), m.mat("drawer", WOOD, 0.6))
    m.sphere(0.02, (0, 0.33, -0.27), m.mat("knob", METAL, 0.3, 0.9), seg=8, rings=6)
    m.cyl(0.09, 0.1, 0.03, (0, 0.52, 0), m.mat("lampbase", (0.2, 0.2, 0.25), 0.4, 0.5), seg=14)
    m.cyl(0.015, 0.015, 0.14, (0, 0.6, 0), m.mat("lampbase", (0.2, 0.2, 0.25), 0.4, 0.5), seg=8)
    m.node("Shade")
    m.cyl(0.07, 0.12, 0.16, (0, 0.72, 0), m.mat("shade", (1.0, 0.85, 0.55), 0.9, emissive=(1.0, 0.75, 0.4), emit_strength=0.7), seg=16)
    m.node(None)
    return m


@model
def wardrobe():
    m = new("wardrobe")
    w = m.mat("wood", (0.55, 0.4, 0.3), 0.6)
    w2 = m.mat("door", (0.6, 0.45, 0.34), 0.55)
    m.rbox((1.6, 2.2, 0.6), (0, 1.1, 0), w, 0.02)
    for x in (-0.4, 0.4):
        m.rbox((0.78, 2.0, 0.02), (x, 1.12, -0.31), w2, 0.01)
        m.rbox((0.4, 0.8, 0.004), (x, 1.5, -0.322), m.mat("panel", (0.5, 0.36, 0.27), 0.6), 0.0)
        m.rbox((0.4, 0.8, 0.004), (x, 0.65, -0.322), m.mat("panel", (0.5, 0.36, 0.27), 0.6), 0.0)
    for x in (-0.06, 0.06):
        m.cyl(0.012, 0.012, 0.22, (x, 1.1, -0.34), m.mat("handle", METAL, 0.3, 0.9), seg=8)
    m.box((1.7, 0.05, 0.64), (0, 2.22, 0), w)
    return m


@model
def fridge():
    m = new("fridge")
    body = m.mat("body", (0.85, 0.87, 0.9), 0.3, 0.4)
    gr = m.mat("seam", (0.4, 0.4, 0.45), 0.5)
    hd = m.mat("handle", (0.55, 0.57, 0.6), 0.25, 0.9)
    m.rbox((1.0, 2.0, 0.9), (0, 1.0, 0), body, 0.04)
    m.box((0.98, 0.012, 0.02), (0, 1.35, -0.455), gr)
    m.rbox((0.03, 0.55, 0.05), (-0.4, 1.7, -0.5), hd, 0.01)
    m.rbox((0.03, 0.3, 0.05), (-0.4, 0.95, -0.5), hd, 0.01)
    # magnets
    for i, c in enumerate([(0.9, 0.2, 0.2), (0.2, 0.6, 0.9), (0.95, 0.85, 0.2)]):
        m.rbox((0.07, 0.07, 0.01), (0.15 + i * 0.1, 1.6 + (i % 2) * 0.1, -0.46), m.mat("magnet%d" % i, c, 0.5), 0.01)
    m.rbox((0.2, 0.26, 0.004), (0.3, 1.3 + 0.2, -0.455), m.mat("note", (1.0, 0.95, 0.6), 0.9), 0.0)
    return m


@model
def counter_run():
    """4.8 m kitchen run: 1.0 deep (z), counter + sink + stove + wall cabinets at the back (+Z)."""
    m = new("counter_run")
    cab = m.mat("cabinet", (0.3, 0.45, 0.55), 0.6)
    cab2 = m.mat("cabinet_door", (0.34, 0.5, 0.6), 0.55)
    top = m.mat("counter", (0.92, 0.92, 0.9), 0.3)
    st = m.mat("steel", (0.72, 0.74, 0.78), 0.2, 0.9)
    bl = m.mat("black", (0.05, 0.05, 0.05), 0.4)
    L = 4.8
    m.box((L, 0.1, 0.94), (0, 0.05, 0.0), m.mat("kick", (0.1, 0.1, 0.12), 0.8))
    m.rbox((L, 0.8, 0.94), (0, 0.5, 0), cab, 0.01)
    m.rbox((L + 0.02, 0.06, 1.0), (0, 0.93, 0), top, 0.01)
    n = 8
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n
        m.rbox((L / n - 0.04, 0.7, 0.02), (x, 0.5, -0.47), cab2, 0.008)
        m.rbox((0.12, 0.02, 0.02), (x, 0.8, -0.49), st, 0.008)
    # sink (basin as dark inset + tap)
    sx = -1.4
    m.rbox((0.7, 0.012, 0.5), (sx, 0.965, -0.02), st, 0.004)
    m.box((0.6, 0.004, 0.4), (sx, 0.972, -0.02), bl)
    m.cyl(0.018, 0.018, 0.3, (sx, 1.1, 0.35), st, seg=10)
    m.torus(0.07, 0.015, (sx, 1.25, 0.28), st, rot=(0, 0, 0), seg=14, tube=6)
    # stove (hob)
    for bx in (-0.3, 0.3):
        for bz in (-0.2, 0.2):
            m.cyl(0.11, 0.11, 0.015, (1.1 + bx * 0.9, 0.972, bz), bl, seg=16)
            m.torus(0.07, 0.008, (1.1 + bx * 0.9, 0.98, bz), m.mat("ring", (0.35, 0.35, 0.38), 0.4, 0.8), seg=14, tube=6)
    # pot on the hob
    m.cyl(0.13, 0.13, 0.14, (1.1 - 0.27, 1.05, -0.2), st, seg=18)
    m.cyl(0.135, 0.135, 0.02, (1.1 - 0.27, 1.13, -0.2), st, seg=18)
    # wall cabinets
    for i in range(6):
        x = -L / 2 + (i + 0.5) * L / 6
        m.rbox((L / 6 - 0.03, 0.8, 0.4), (x, 2.0, 0.3), cab, 0.01)
        m.rbox((L / 6 - 0.07, 0.72, 0.02), (x, 2.0, 0.09), cab2, 0.008)
    # fruit bowl on the counter
    m.lathe([(0.0, 0.0), (0.1, 0.02), (0.16, 0.08), (0.15, 0.08), (0.0, 0.0)][:4], (0.2, 0.96, 0.0), m.mat("bowl", (0.9, 0.9, 0.95), 0.3), seg=16)
    for k, c in enumerate([(0.9, 0.15, 0.1), (0.95, 0.8, 0.1), (0.4, 0.75, 0.2)]):
        a = k * 2.1
        m.sphere(0.045, (0.2 + math.cos(a) * 0.05, 1.05, math.sin(a) * 0.05), m.mat("fruit%d" % k, c, 0.5), seg=10, rings=8)
    return m


@model
def kitchen_island():
    m = new("kitchen_island")
    cab = m.mat("cabinet", (0.3, 0.45, 0.55), 0.6)
    top = m.mat("counter", (0.92, 0.92, 0.9), 0.3)
    m.box((2.2, 0.1, 0.8), (0, 0.05, 0), m.mat("kick", (0.1, 0.1, 0.12), 0.8))
    m.rbox((2.2, 0.82, 0.8), (0, 0.49, 0), cab, 0.01)
    m.rbox((2.4, 0.06, 1.0), (0, 0.93, 0), top, 0.015)
    for i in range(4):
        m.rbox((0.5, 0.65, 0.02), (-0.82 + i * 0.55, 0.5, -0.41), m.mat("door", (0.34, 0.5, 0.6), 0.55), 0.008)
    # pizza box + cups
    m.rbox((0.4, 0.05, 0.4), (-0.6, 0.99, 0.0), m.mat("box", (0.85, 0.7, 0.5), 0.9), 0.005, rot=(0, 15, 0))
    for x in (0.4, 0.62):
        m.cyl(0.04, 0.03, 0.1, (x, 1.01, 0.1), m.mat("cup", (0.9, 0.2, 0.2), 0.5), seg=12)
    return m


@model
def stool():
    m = new("stool")
    st = m.mat("steel", (0.3, 0.3, 0.33), 0.3, 0.8)
    m.cyl(0.2, 0.2, 0.06, (0, 0.62, 0), m.mat("seat", (0.85, 0.3, 0.3), 0.6), seg=20)
    m.cyl(0.04, 0.04, 0.56, (0, 0.31, 0), st, seg=10)
    m.cyl(0.2, 0.22, 0.03, (0, 0.015, 0), st, seg=16)
    m.torus(0.16, 0.012, (0, 0.25, 0), st, seg=18, tube=6)
    return m


@model
def toilet():
    m = new("toilet")
    w = m.mat("porcelain", (0.96, 0.96, 0.98), 0.15)
    m.rbox((0.38, 0.22, 0.5), (0, 0.11, 0.0), w, 0.03)
    m.cyl(0.18, 0.14, 0.2, (0, 0.32, -0.08), w, seg=20, rot=(0, 0, 0))
    m.torus(0.15, 0.03, (0, 0.43, -0.08), m.mat("seat", (0.9, 0.9, 0.95), 0.4), seg=20, tube=8)
    m.cyl(0.14, 0.14, 0.015, (0, 0.425, -0.08), m.mat("lid", (0.88, 0.9, 0.95), 0.4), seg=20)
    m.rbox((0.4, 0.5, 0.18), (0, 0.65, 0.23), w, 0.03)
    m.cyl(0.03, 0.03, 0.03, (0, 0.93, 0.23), m.mat("flush", METAL, 0.2, 0.9), seg=10)
    return m


@model
def bathtub():
    """1.1 wide x 2.4 long x 0.6 tall; water surface at y = 0.5 (own translucent node)."""
    m = new("bathtub")
    w = m.mat("porcelain", (0.96, 0.96, 0.98), 0.15)
    m.rbox((1.1, 0.6, 0.12), (0, 0.3, -1.14), w, 0.03)
    m.rbox((1.1, 0.6, 0.12), (0, 0.3, 1.14), w, 0.03)
    m.rbox((0.12, 0.6, 2.4), (-0.49, 0.3, 0), w, 0.03)
    m.rbox((0.12, 0.6, 2.4), (0.49, 0.3, 0), w, 0.03)
    m.box((0.9, 0.06, 2.2), (0, 0.03, 0), w)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.sphere(0.05, (sx * 0.45, 0.03, sz * 1.1), m.mat("foot", (0.8, 0.7, 0.3), 0.3, 0.8), seg=8, rings=6)
    m.cyl(0.02, 0.02, 0.2, (0, 0.7, 1.05), m.mat("tap", METAL, 0.2, 0.9), seg=8)
    m.node("Water")
    m.box((0.88, 0.01, 2.18), (0, 0.5, 0), m.mat("water", (0.3, 0.6, 0.9, 0.55), 0.05))
    m.node(None)
    # rubber duck + bubbles
    m.sphere(0.07, (0.1, 0.55, -0.4), m.mat("duck", (1.0, 0.85, 0.1), 0.4), seg=12, rings=8)
    m.sphere(0.045, (0.1, 0.63, -0.46), m.mat("duck", (1.0, 0.85, 0.1), 0.4), seg=10, rings=8)
    for i in range(7):
        m.sphere(0.07 + 0.01 * (i % 3), (-0.2 + (i * 0.37) % 0.5, 0.52, 0.2 + i * 0.12), m.mat("foam", (1, 1, 1), 0.9), scale=(1, 0.6, 1), seg=10, rings=6)
    return m


@model
def vanity():
    """Bathroom cabinet with sink, tap and wall mirror at the back (+Z). 1.2 x 0.5 x 0.9 (+ mirror)."""
    m = new("vanity")
    w = m.mat("cabinet", WHITE, 0.3)
    m.rbox((1.2, 0.8, 0.5), (0, 0.4, 0), w, 0.015)
    m.rbox((1.24, 0.06, 0.54), (0, 0.83, 0), m.mat("top", (0.85, 0.85, 0.88), 0.2), 0.015)
    m.cyl(0.19, 0.15, 0.06, (0, 0.89, -0.02), w, seg=20)
    m.cyl(0.15, 0.12, 0.02, (0, 0.905, -0.02), m.mat("basin", (0.7, 0.85, 0.95), 0.1), seg=20)
    tap = m.mat("tap", METAL, 0.15, 0.95)
    m.cyl(0.015, 0.015, 0.2, (0, 0.96, 0.17), tap, seg=8)
    m.cyl(0.012, 0.012, 0.1, (0, 1.06, 0.13), tap, rot=(90, 0, 0), seg=8)
    for x in (-0.3, 0.3):
        m.rbox((0.5, 0.64, 0.02), (x, 0.4, -0.255), m.mat("door", (0.9, 0.9, 0.93), 0.3), 0.008)
        m.sphere(0.018, (x * 0.2 + (0.2 if x < 0 else -0.2) * 0 + (0.17 if x < 0 else -0.17), 0.55, -0.275), tap, seg=8, rings=6)
    # mirror on the wall
    m.box((0.96, 1.06, 0.03), (0, 1.6, 0.26), m.mat("mirrorframe", (0.85, 0.85, 0.88), 0.3))
    m.box((0.88, 0.98, 0.01), (0, 1.6, 0.245), m.mat("mirror", (0.75, 0.88, 0.98), 0.02, 0.9))
    m.rbox((0.2, 0.08, 0.1), (0.45, 0.92, 0.12), m.mat("soap", (0.9, 0.5, 0.7), 0.6), 0.02)
    return m


@model
def rug_red():
    m = new("rug_red")
    m.rbox((5.0, 0.016, 3.4), (0, 0.008, 0), m.mat("rug", (0.75, 0.3, 0.3), 1.0), 0.006)
    m.rbox((4.5, 0.02, 2.9), (0, 0.009, 0), m.mat("rug_border", (0.95, 0.85, 0.6), 1.0), 0.006)
    m.rbox((4.3, 0.022, 2.7), (0, 0.01, 0), m.mat("rug", (0.75, 0.3, 0.3), 1.0), 0.006)
    m.cyl(0.9, 0.9, 0.024, (0, 0.012, 0), m.mat("rug_ring", (0.35, 0.2, 0.5), 1.0), seg=32)
    m.cyl(0.7, 0.7, 0.026, (0, 0.013, 0), m.mat("rug", (0.75, 0.3, 0.3), 1.0), seg=32)
    return m


@model
def bathmat():
    m = new("bathmat")
    m.rbox((1.2, 0.016, 0.8), (0, 0.008, 0), m.mat("mat", (0.4, 0.75, 0.7), 1.0), 0.006)
    m.rbox((1.0, 0.02, 0.6), (0, 0.009, 0), m.mat("mat2", (0.55, 0.85, 0.8), 1.0), 0.006)
    return m


def painting(name, w, h, bg, motif):
    def f():
        m = new(name)
        m.rbox((w + 0.1, h + 0.1, 0.05), (0, 0, 0), m.mat("frame", (0.2, 0.15, 0.1), 0.5), 0.01)
        m.box((w, h, 0.03), (0, 0, -0.012), m.mat("canvas", bg, 0.7))
        if motif == "sun":
            m.cyl(h * 0.2, h * 0.2, 0.01, (w * 0.15, h * 0.1, -0.03), m.mat("sun", (1, 0.9, 0.3), 0.7, emissive=(0.4, 0.3, 0)), rot=(90, 0, 0), seg=20)
            m.prism([(-w / 2, -h / 2), (w * 0.1, -h / 2), (-w * 0.15, h * 0.1)], 0, 0.01, (0, 0, -0.03), m.mat("hill", (0.2, 0.5, 0.3), 0.8), rot=(-90, 0, 0))
        elif motif == "waves":
            for i in range(4):
                m.box((w * 0.9, h * 0.07, 0.01), (0, -h * 0.3 + i * h * 0.17, -0.03), m.mat("wave", (0.9, 0.95, 1.0), 0.7), rot=(0, 0, 0))
        elif motif == "dots":
            rng = random.Random(5)
            for i in range(9):
                m.cyl(h * 0.07, h * 0.07, 0.01, (rng.uniform(-w * .35, w * .35), rng.uniform(-h * .35, h * .35), -0.03),
                      m.mat("dot%d" % (i % 3), hsv(rng.random(), 0.6, 0.95), 0.7), rot=(90, 0, 0), seg=14)
        else:
            m.rbox((w * 0.4, h * 0.5, 0.01), (0, 0, -0.03), m.mat("shape", (0.95, 0.85, 0.2), 0.7), 0.003, rot=(0, 0, 20))
        return m
    return f


reg("painting_sun", painting("painting_sun", 1.2, 0.8, (0.9, 0.55, 0.2), "sun"))
reg("painting_waves", painting("painting_waves", 0.8, 1.0, (0.2, 0.6, 0.7), "waves"))
reg("painting_dots", painting("painting_dots", 1.0, 0.7, (0.8, 0.3, 0.45), "dots"))
reg("painting_shape", painting("painting_shape", 0.9, 0.6, (0.3, 0.5, 0.9), "shape"))


@model
def ceiling_lamp():
    m = new("ceiling_lamp")
    m.cyl(0.08, 0.08, 0.02, (0, 0.03, 0), m.mat("rim", (0.9, 0.9, 0.9), 0.4), seg=24)
    m.lathe([(0.3, -0.06), (0.29, -0.02), (0.24, 0.02), (0.1, 0.04), (0.0, 0.045)], (0, 0, 0), m.mat("shade_dome", (0.95, 0.95, 0.93), 0.35), seg=36)
    m.torus(0.3, 0.012, (0, -0.06, 0), m.mat("rim", (0.9, 0.9, 0.9), 0.4), seg=36, tube=6)
    m.node("Glow")
    m.sphere(0.28, (0, -0.06, 0), m.mat("glow", (1.0, 0.95, 0.85), 0.5, emissive=(1.0, 0.93, 0.8)), scale=(1, 0.18, 1), seg=32, rings=8)
    m.node(None)
    return m


@model
def retro_pc():
    """Beige 1995 desktop on a desk with tower, speakers and chair. Screen faces -Z. Desk 1.6 x 0.7."""
    m = new("retro_pc")
    beige = m.mat("beige", BEIGE, 0.6)
    beige2 = m.mat("beige_dark", (0.72, 0.69, 0.58), 0.6)
    dark = m.mat("black", (0.15, 0.15, 0.18), 0.5)
    m.rbox((1.6, 0.05, 0.7), (0, 0.75, 0), m.mat("desk", (0.75, 0.55, 0.4), 0.5), 0.01)
    for x in (-0.74, 0.74):
        m.rbox((0.05, 0.74, 0.62), (x, 0.37, 0), dark, 0.01)
    m.rbox((1.5, 0.3, 0.02), (0, 0.5, 0.31), dark, 0.005)
    # CRT
    m.rbox((0.36, 0.06, 0.3), (0, 0.8, 0.05), beige2, 0.015)
    m.rbox((0.58, 0.46, 0.22), (0, 1.08, 0.0), beige, 0.03)
    m.rbox((0.42, 0.34, 0.26), (0, 1.06, 0.2), beige, 0.05)
    m.rbox((0.5, 0.4, 0.02), (0, 1.09, -0.105), beige2, 0.01)
    m.node("Screen")
    m.box((0.44, 0.33, 0.01), (0, 1.09, -0.118), m.mat("screen", (0.1, 0.45, 0.6), 0.1, emissive=(0.1, 0.45, 0.6)))
    m.node(None)
    m.sphere(0.012, (0.2, 0.9, -0.11), m.mat("led", (0.3, 1.0, 0.3), 0.3, emissive=(0.3, 1.0, 0.3)), seg=8, rings=6)
    # tower
    m.rbox((0.22, 0.52, 0.46), (0.98, 0.26, 0.05), beige, 0.015)
    m.box((0.18, 0.04, 0.01), (0.98, 0.42, -0.185), dark)
    m.box((0.14, 0.012, 0.01), (0.98, 0.34, -0.185), dark)
    m.box((0.12, 0.012, 0.01), (0.98, 0.3, -0.185), dark)
    m.sphere(0.012, (0.98, 0.16, -0.185), m.mat("led", (0.3, 1.0, 0.3), 0.3, emissive=(0.3, 1.0, 0.3)), seg=8, rings=6)
    m.cyl(0.02, 0.02, 0.01, (0.98, 0.2, -0.185), m.mat("button", (0.6, 0.58, 0.5), 0.4), rot=(90, 0, 0), seg=10)
    # keyboard, mouse, pad
    m.rbox((0.48, 0.028, 0.16), (0, 0.789, -0.22), beige, 0.008)
    for r in range(3):
        for c in range(12):
            m.box((0.028, 0.008, 0.026), (-0.2 + c * 0.036, 0.808, -0.265 + r * 0.04), m.mat("key", (0.62, 0.6, 0.52), 0.6))
    m.rbox((0.22, 0.006, 0.22), (0.45, 0.778, -0.2), m.mat("pad", (0.8, 0.2, 0.3), 0.9), 0.002)
    m.rbox((0.06, 0.03, 0.1), (0.45, 0.795, -0.2), beige, 0.012)
    # speakers
    for x in (-0.58, 0.58):
        m.rbox((0.14, 0.24, 0.16), (x, 0.9, 0.05), dark, 0.015)
        m.cyl(0.045, 0.045, 0.01, (x, 0.86, -0.04), m.mat("cone", (0.3, 0.3, 0.33), 0.4), rot=(90, 0, 0), seg=14)
        m.cyl(0.02, 0.02, 0.01, (x, 0.95, -0.04), m.mat("cone", (0.3, 0.3, 0.33), 0.4), rot=(90, 0, 0), seg=10)
    # floppy disks and a sticky note
    m.rbox((0.09, 0.004, 0.09), (-0.5, 0.78, -0.18), m.mat("floppy", (0.2, 0.3, 0.8), 0.6), 0.001, rot=(0, 20, 0))
    m.rbox((0.08, 0.004, 0.08), (-0.38, 0.78, -0.25), m.mat("note", (1.0, 0.95, 0.4), 0.9), 0.001, rot=(0, -10, 0))
    # office chair
    blue = m.mat("chairblue", (0.2, 0.25, 0.5), 0.8)
    m.cyl(0.04, 0.04, 0.45, (0, 0.25, -0.85), dark, seg=10)
    m.cyl(0.04, 0.3, 0.05, (0, 0.04, -0.85), dark, seg=5)
    for i in range(5):
        a = i * 72
        ar = math.radians(a)
        m.rbox((0.3, 0.025, 0.04), (math.sin(ar) * 0.15, 0.04, -0.85 + math.cos(ar) * 0.15), dark, 0.01, rot=(0, a + 90, 0))
        m.sphere(0.03, (math.sin(ar) * 0.29, 0.03, -0.85 + math.cos(ar) * 0.29), dark, seg=8, rings=6)
    m.rbox((0.48, 0.09, 0.48), (0, 0.52, -0.85), blue, 0.04)
    m.rbox((0.44, 0.48, 0.08), (0, 0.82, -0.62), blue, 0.04, rot=(-6, 0, 0))
    return m


@model
def speaker():
    m = new("speaker")
    blk = m.mat("cabinet", (0.06, 0.06, 0.07), 0.5)
    baffle = m.mat("baffle", (0.1, 0.1, 0.11), 0.7)
    ring = m.mat("ring", (0.25, 0.25, 0.27), 0.35, 0.7)
    cone = m.mat("cone", (0.12, 0.12, 0.14), 0.9)
    dust = m.mat("dustcap", (0.2, 0.2, 0.22), 0.6)
    chrome = m.mat("chrome", (0.8, 0.8, 0.85), 0.2, 0.9)
    m.rbox((0.7, 1.5, 0.6), (0, 0.75, 0), blk, 0.03)
    m.rbox((0.64, 1.44, 0.02), (0, 0.75, -0.3), baffle, 0.01)
    for y, r in ((0.42, 0.25), (0.92, 0.14)):
        m.torus(r, 0.022, (0, y, -0.31), ring, rot=(90, 0, 0), seg=32, tube=8)
        m.lathe([(0.0, -0.06), (r * 0.25, -0.055), (r * 0.6, -0.03), (r * 0.95, 0.0)], (0, y, -0.31), cone, rot=(-90, 0, 0), seg=32)
        m.sphere(r * 0.24, (0, y, -0.3), dust, scale=(1, 1, 0.45), seg=16, rings=8)
    m.torus(0.07, 0.012, (0, 1.24, -0.31), ring, rot=(90, 0, 0), seg=24, tube=6)
    m.sphere(0.065, (0, 1.24, -0.3), chrome, scale=(1, 1, 0.4), seg=16, rings=10)
    m.cyl(0.05, 0.05, 0.03, (0.2, 0.12, -0.3), m.mat("port", (0.01, 0.01, 0.01), 0.9), rot=(90, 0, 0), seg=16)
    m.torus(0.05, 0.008, (0.2, 0.12, -0.315), ring, rot=(90, 0, 0), seg=16, tube=5)
    m.sphere(0.012, (-0.24, 1.4, -0.31), m.mat("led", (0.2, 1.0, 0.3), 0.3, emissive=(0.2, 1.0, 0.3)), seg=8, rings=6)
    m.rbox((0.2, 0.04, 0.02), (0, 1.4, -0.31), m.mat("badge", (0.8, 0.8, 0.8), 0.3, 0.8), 0.01)
    for x in (-0.3, 0.3):
        for z in (-0.24, 0.24):
            m.cyl(0.04, 0.035, 0.03, (x, 0.015, z), m.mat("foot", (0.1, 0.1, 0.1), 0.9), seg=12)
    return m


def beanbag(name, color):
    def f():
        m = new(name)
        c = m.mat("fabric", color, 0.95)
        seam = m.mat("seam", tuple(x * 0.75 for x in color), 0.95)
        m.sphere(0.5, (0, 0.3, 0), c, scale=(1.0, 0.62, 1.0), seg=32, rings=18)
        m.sphere(0.34, (0.0, 0.5, 0.2), c, scale=(1.15, 0.75, 0.8), seg=24, rings=14, rot=(-25, 0, 0))   # back rest
        m.sphere(0.22, (0.28, 0.36, -0.12), c, scale=(1.0, 0.7, 1.0), seg=18, rings=10)                  # lumps
        m.sphere(0.2, (-0.3, 0.35, -0.05), c, scale=(1.0, 0.7, 1.0), seg=18, rings=10)
        m.sphere(0.3, (0.0, 0.43, -0.12), c, scale=(1.2, 0.45, 1.1), seg=22, rings=10)                   # the dent you sit in
        m.torus(0.48, 0.012, (0, 0.3, 0), seam, seg=48, tube=5)
        m.torus(0.08, 0.012, (0, 0.52, -0.1), m.mat("zip", METAL, 0.3, 0.8), seg=12, tube=5)
        m.rbox((0.04, 0.012, 0.08), (0.0, 0.53, -0.19), m.mat("zip", METAL, 0.3, 0.8), 0.004)
        return m
    return f


reg("beanbag_yellow", beanbag("beanbag_yellow", (0.95, 0.75, 0.2)))
reg("beanbag_green", beanbag("beanbag_green", (0.3, 0.8, 0.5)))
reg("beanbag_blue", beanbag("beanbag_blue", (0.4, 0.5, 0.95)))


@model
def dj_booth():
    m = new("dj_booth")
    blk = m.mat("body", (0.1, 0.1, 0.12), 0.4)
    ch = m.mat("platter", (0.75, 0.75, 0.8), 0.2, 0.9)
    m.rbox((2.4, 1.0, 0.7), (0, 0.5, 0), blk, 0.03)
    m.box((2.3, 0.02, 0.02), (0, 0.9, -0.36), m.mat("trim", (1.0, 0.2, 0.7), 0.3, emissive=(1.0, 0.2, 0.7)))
    for x in (-0.7, 0.7):
        m.cyl(0.26, 0.26, 0.04, (x, 1.02, 0), m.mat("deck", (0.2, 0.2, 0.22), 0.4), seg=24)
        m.cyl(0.22, 0.22, 0.02, (x, 1.045, 0), ch, seg=24)
        m.cyl(0.06, 0.06, 0.005, (x, 1.056, 0), m.mat("label", (0.95, 0.3, 0.3), 0.5), seg=14)
        m.cyl(0.01, 0.01, 0.2, (x + 0.28, 1.06, 0.15), ch, rot=(90, 0, 12), seg=8)
    m.rbox((0.5, 0.06, 0.4), (0, 1.03, 0), m.mat("mixer", (0.15, 0.15, 0.18), 0.4), 0.01)
    for i in range(4):
        m.box((0.02, 0.02, 0.1), (-0.15 + i * 0.1, 1.07, 0.0), m.mat("fader", (0.9, 0.9, 0.9), 0.4))
    m.node("Glow")
    m.box((0.4, 0.004, 0.06), (0, 1.064, -0.12), m.mat("vu", (0.3, 0.9, 1.0), 0.3, emissive=(0.3, 0.9, 1.0)))
    m.node(None)
    m.rbox((0.4, 0.02, 0.28), (1.0, 1.01, 0.1), m.mat("laptop", (0.6, 0.6, 0.65), 0.3, 0.7), 0.005)
    m.rbox((0.4, 0.26, 0.012), (1.0, 1.14, 0.24), m.mat("laptop", (0.6, 0.6, 0.65), 0.3, 0.7), 0.005, rot=(-15, 0, 0))
    return m


@model
def disco_ball():
    m = new("disco_ball")
    m.cyl(0.01, 0.01, 0.6, (0, 0.55, 0), m.mat("chain", (0.3, 0.3, 0.3), 0.4, 0.8), seg=6)
    m.sphere(0.35, (0, 0, 0), m.mat("mirror", (0.88, 0.88, 0.95), 0.04, 1.0), seg=16, rings=10, flat=True)
    return m


@model
def neon_sign():
    m = new("neon_sign")
    m.box((2.4, 0.5, 0.04), (0, 0, 0.02), m.mat("backing", (0.05, 0.05, 0.08), 0.7))
    pink = m.mat("neon", (1.0, 0.2, 0.7), 0.3, emissive=(1.0, 0.2, 0.7), emit_strength=1.0)
    cyan = m.mat("neon2", (0.3, 0.9, 1.0), 0.3, emissive=(0.3, 0.9, 1.0), emit_strength=1.0)
    m.node("Glow")
    for i in range(6):  # "letters": simple glowing shapes
        x = -1.0 + i * 0.4
        m.rbox((0.06, 0.32, 0.03), (x - 0.08, 0, -0.01), pink if i % 2 == 0 else cyan, 0.015)
        m.rbox((0.06, 0.32, 0.03), (x + 0.08, 0, -0.01), pink if i % 2 == 0 else cyan, 0.015)
        m.rbox((0.22, 0.06, 0.03), (x, 0.13 if i % 2 else -0.13, -0.01), pink if i % 2 == 0 else cyan, 0.015)
    m.node(None)
    return m


# ===================================================================== YARD
@model
def tree():
    m = new("tree")
    bark = m.mat("bark", (0.4, 0.28, 0.18), 0.95)
    m.lathe([(0.34, 0.0), (0.3, 0.3), (0.22, 1.5), (0.2, 3.0)], (0, 0, 0), bark, seg=14)
    for a in (30, 150, 270):
        ar = math.radians(a)
        m.cyl(0.05, 0.09, 1.1, (math.sin(ar) * 0.45, 2.7, math.cos(ar) * 0.45), bark, rot=(math.cos(ar) * 40, 0, -math.sin(ar) * 40), seg=8)
    ls = [m.mat("leafA", (0.15, 0.5, 0.2), 0.95), m.mat("leafB", (0.18, 0.56, 0.22), 0.95), m.mat("leafC", (0.12, 0.44, 0.18), 0.95)]
    rng = random.Random(11)
    m.lathe([(0.55, 0.0), (0.36, 0.08), (0.3, 0.3)], (0, 0, 0), bark, seg=14)   # root flare
    blobs = [((0, 3.7, 0), 1.7), ((0.95, 3.0, 0.4), 1.2), ((-0.85, 3.1, -0.5), 1.3), ((0.3, 4.4, -0.4), 1.0), ((-0.5, 4.1, 0.7), 0.95)]
    for _ in range(9):   # extra clumps so the crown is lumpy instead of five balls
        a = rng.random() * 6.28
        d = rng.uniform(0.9, 1.5)
        blobs.append(((math.sin(a) * d, rng.uniform(2.8, 4.5), math.cos(a) * d), rng.uniform(0.55, 0.85)))
    for i, (p, r) in enumerate(blobs):
        m.sphere(r, p, ls[i % 3], scale=(1, 0.88, 1), seg=18, rings=12)
    for i in range(12):
        a = rng.random() * 6.28
        d = rng.uniform(0.8, 1.7)
        m.sphere(0.07, (math.sin(a) * d, 3.2 + rng.random() * 1.5, math.cos(a) * d), m.mat("apple", (0.85, 0.12, 0.1), 0.5), seg=8, rings=6)
    return m


@model
def pine_tree():
    m = new("pine_tree")
    m.cyl(0.14, 0.2, 1.4, (0, 0.7, 0), m.mat("bark", (0.35, 0.24, 0.16), 0.95), seg=10)
    g = [m.mat("pineA", (0.08, 0.36, 0.2), 0.95), m.mat("pineB", (0.1, 0.42, 0.24), 0.95)]
    for i in range(5):
        m.cyl(0.0, 1.5 - i * 0.26, 1.3, (0, 1.7 + i * 0.85, 0), g[i % 2], seg=14)
    return m


@model
def bush():
    m = new("bush")
    a = m.mat("leafA", (0.17, 0.46, 0.2), 0.95)
    b = m.mat("leafB", (0.2, 0.52, 0.22), 0.95)
    m.sphere(0.55, (0, 0.45, 0), a, scale=(1.0, 0.85, 1.0), seg=14, rings=10)
    m.sphere(0.42, (0.45, 0.35, 0.1), b, seg=12, rings=8)
    m.sphere(0.45, (-0.4, 0.38, -0.15), b, seg=12, rings=8)
    m.sphere(0.3, (0.05, 0.4, -0.45), a, seg=12, rings=8)
    rng = random.Random(5)
    for i in range(10):
        ar = rng.random() * 6.28
        d = rng.uniform(0.35, 0.6)
        m.sphere(rng.uniform(0.16, 0.26), (math.sin(ar) * d, rng.uniform(0.3, 0.7), math.cos(ar) * d), a if i % 2 else b, seg=12, rings=8)
    for i in range(6):
        ar = i * 1.1
        m.sphere(0.04, (math.sin(ar) * 0.5, 0.45 + (i % 3) * 0.12, math.cos(ar) * 0.5), m.mat("flower%d" % (i % 2), (1.0, 0.4 + 0.4 * (i % 2), 0.6), 0.6), seg=6, rings=4)
    return m


@model
def bench():
    m = new("bench")
    wood = m.mat("wood", (0.75, 0.55, 0.38), 0.6)
    iron = m.mat("iron", (0.2, 0.2, 0.22), 0.5, 0.6)
    for i in range(4):
        m.rbox((1.6, 0.025, 0.1), (0, 0.45, -0.18 + i * 0.12), wood, 0.008)
    for i in range(3):
        m.rbox((1.6, 0.1, 0.02), (0, 0.6 + i * 0.13, 0.22 + i * 0.015), wood, 0.008, rot=(-8, 0, 0))
    for x in (-0.7, 0.7):
        m.rbox((0.05, 0.45, 0.05), (x, 0.225, -0.2), iron, 0.01)
        m.rbox((0.05, 0.45, 0.05), (x, 0.225, 0.2), iron, 0.01)
        m.rbox((0.05, 0.5, 0.05), (x, 0.7, 0.24), iron, 0.01, rot=(-8, 0, 0))
        m.rbox((0.05, 0.05, 0.5), (x, 0.58, -0.0), iron, 0.01)
    return m


@model
def mailbox():
    m = new("mailbox")
    m.rbox((0.1, 1.1, 0.1), (0, 0.55, 0), m.mat("post", (0.22, 0.22, 0.24), 0.6), 0.01)
    blue = m.mat("blue", (0.16, 0.38, 0.78), 0.4)
    m.rbox((0.3, 0.05, 0.42), (0, 0.97, 0), blue, 0.01)
    m.cyl(0.15, 0.15, 0.42, (0, 1.05, 0), blue, rot=(90, 0, 0), seg=16)
    m.box((0.02, 0.18, 0.04), (0.17, 1.12, 0.08), m.mat("flag", (0.85, 0.2, 0.15), 0.5))
    return m


@model
def pool_ladder():
    """Two rails and rungs, origin at the water-level top; extends down to y = -2.2."""
    m = new("pool_ladder")
    metal = m.mat("chrome", (0.85, 0.87, 0.92), 0.15, 0.95)
    for s in (-0.25, 0.25):
        m.cyl(0.025, 0.025, 2.1, (0.0, -1.05, s), metal, seg=10)
        m.cyl(0.025, 0.025, 0.9, (0.0, 0.45, s), metal, seg=10)
        m.torus(0.14, 0.025, (0.14, 0.9, s), metal, rot=(90, 0, 0), seg=12, tube=6)
    for k in range(7):
        m.cyl(0.02, 0.02, 0.5, (0.0, -1.9 + k * 0.38, 0), metal, rot=(90, 0, 0), seg=8)
    m.cyl(0.03, 0.03, 0.04, (0, 0.04, 0.25), metal, seg=10)
    return m


@model
def trampoline():
    """Round 3 m trampoline: padded rim, black bouncy mat, springs, angled legs. Top at y = 0.30."""
    m = new("trampoline")
    blue = m.mat("pad", (0.12, 0.28, 0.82), 0.5)
    blk = m.mat("mat", (0.04, 0.04, 0.06), 0.9)
    steel = m.mat("steel", (0.7, 0.72, 0.78), 0.3, 0.8)
    m.cyl(1.2, 1.2, 0.02, (0, 0.285, 0), blk, seg=40)
    m.torus(1.38, 0.1, (0, 0.27, 0), blue, seg=40, tube=12)                              # safety pad
    m.torus(1.28, 0.025, (0, 0.24, 0), steel, seg=40, tube=8)                            # frame
    m.cyl(1.2, 1.2, 0.006, (0, 0.296, 0), m.mat("edge", (0.95, 0.85, 0.2), 0.6), seg=40, caps=False)
    for i in range(36):                                                                      # springs
        a = i * math.tau / 36
        m.cyl(0.012, 0.012, 0.08, (math.sin(a) * 1.23, 0.26, math.cos(a) * 1.23), steel, seg=6,
              rot=(math.degrees(math.cos(a)) * 0.0, 0, 0))
    m.cyl(0.3, 0.3, 0.004, (0, 0.297, 0), m.mat("center", (0.9, 0.9, 0.9), 0.8), seg=24)
    m.torus(0.5, 0.012, (0, 0.298, 0), m.mat("center", (0.9, 0.9, 0.9), 0.8), seg=24, tube=6)
    for i in range(6):
        a = i * math.tau / 6 + 0.26
        x, z = math.sin(a) * 1.3, math.cos(a) * 1.3
        m.cyl(0.035, 0.035, 0.27, (x, 0.135, z), steel, seg=8)
        m.rbox((0.16, 0.025, 0.06), (x, 0.012, z), m.mat("foot", (0.1, 0.1, 0.12), 0.8), 0.008, rot=(0, math.degrees(a), 0))
    return m


@model
def lounge_chair():
    """Sun lounger: flat seat, backrest raised at the head end (-Z), on a metal frame."""
    m = new("lounge_chair")
    fr = m.mat("frame", (0.9, 0.9, 0.92), 0.4, 0.3)
    cu = m.mat("cushion", (0.95, 0.55, 0.15), 0.9)
    ang = 38.0
    hinge_z, hinge_y = -0.4, 0.32
    back_len = 0.85
    c = math.cos(math.radians(ang)); s_ = math.sin(math.radians(ang))
    bz = hinge_z - c * back_len / 2
    by = hinge_y + s_ * back_len / 2
    m.rbox((0.7, 0.1, 1.3), (0, 0.32, 0.25), cu, 0.04)                       # seat cushion
    m.rbox((0.7, 0.1, back_len), (0, by + 0.01, bz), cu, 0.04, rot=(ang, 0, 0))   # backrest, rising toward the head end
    m.rbox((0.42, 0.08, 0.2), (0, by + s_ * 0.3 + 0.07, bz - c * 0.3), cu, 0.04, rot=(ang, 0, 0))   # pillow
    for x in (-0.33, 0.33):
        m.rbox((0.04, 0.04, 1.32), (x, 0.26, 0.25), fr, 0.01)                   # seat rail
        m.rbox((0.04, 0.04, back_len), (x, by - 0.05, bz), fr, 0.01, rot=(ang, 0, 0))   # backrest rail
        for z in (0.85, -0.38):
            m.rbox((0.04, 0.26, 0.04), (x, 0.13, z), fr, 0.01)                  # legs
        m.rbox((0.04, 0.5, 0.04), (x, 0.3, -0.72), fr, 0.01, rot=(-20, 0, 0))   # prop holding the back up
    m.rbox((0.7, 0.04, 0.04), (0, 0.26, -0.4), fr, 0.01)                         # cross bars
    m.rbox((0.7, 0.04, 0.04), (0, 0.26, 0.88), fr, 0.01)
    return m


@model
def bbq():
    m = new("bbq")
    blk = m.mat("body", (0.1, 0.1, 0.12), 0.4, 0.4)
    m.lathe([(0.0, 0.0), (0.3, 0.0), (0.38, 0.1), (0.38, 0.2), (0.0, 0.2)][::1], (0, 0.9, 0), blk, seg=20)
    m.sphere(0.38, (0, 1.12, 0), blk, scale=(1, 0.6, 1), seg=20, rings=8)
    for a in (0, 120, 240):
        ar = math.radians(a)
        m.cyl(0.02, 0.02, 0.9, (math.sin(ar) * 0.25, 0.45, math.cos(ar) * 0.25), m.mat("leg", (0.4, 0.4, 0.42), 0.4, 0.8), seg=8,
              rot=(math.cos(ar) * 6, 0, -math.sin(ar) * 6))
    m.cyl(0.01, 0.01, 0.3, (0.0, 1.38, -0.33), m.mat("handle", (0.4, 0.4, 0.42), 0.4, 0.8), rot=(90, 0, 0), seg=6)
    m.sphere(0.04, (0, 1.4, 0), m.mat("knob", (0.4, 0.4, 0.42), 0.4, 0.8), seg=8, rings=6)
    return m


@model
def gnome():
    m = new("gnome")
    coat = m.mat("coat", (0.2, 0.35, 0.85), 0.8)
    skin = m.mat("skin", (0.95, 0.75, 0.65), 0.7)
    beard = m.mat("beard", (0.97, 0.97, 0.97), 0.9)
    hat = m.mat("hat", (0.9, 0.15, 0.15), 0.8)
    m.cyl(0.2, 0.22, 0.04, (0, 0.02, 0), m.mat("pedestal", (0.5, 0.5, 0.48), 0.9), seg=20)
    m.lathe([(0.0, 0.04), (0.16, 0.04), (0.17, 0.1), (0.15, 0.22), (0.11, 0.32), (0.0, 0.33)], (0, 0, 0), coat, seg=22)
    m.torus(0.155, 0.018, (0, 0.17, 0), m.mat("belt", (0.15, 0.1, 0.07), 0.6), seg=22, tube=6)
    m.rbox((0.05, 0.04, 0.02), (0, 0.17, -0.165), m.mat("gold", (0.95, 0.75, 0.2), 0.3, 0.8), 0.006)
    for sx in (-1, 1):   # arms resting on the belly
        m.cyl(0.035, 0.04, 0.16, (sx * 0.14, 0.22, -0.04), coat, rot=(35, 0, sx * 25), seg=10)
        m.sphere(0.035, (sx * 0.07, 0.17, -0.13), skin, seg=10, rings=6)
    m.sphere(0.12, (0, 0.4, -0.01), skin, seg=18, rings=12)
    m.sphere(0.11, (0, 0.31, -0.07), beard, scale=(1.1, 1.25, 0.75), seg=16, rings=10)    # long beard
    m.sphere(0.05, (-0.035, 0.37, -0.11), beard, scale=(1.2, 0.5, 0.7), seg=10, rings=6)   # moustache
    m.sphere(0.05, (0.035, 0.37, -0.11), beard, scale=(1.2, 0.5, 0.7), seg=10, rings=6)
    m.sphere(0.032, (0, 0.4, -0.125), m.mat("nose", (0.95, 0.5, 0.5), 0.6), seg=10, rings=8)
    for sx in (-1, 1):
        m.sphere(0.014, (sx * 0.045, 0.44, -0.105), m.mat("eye", (0.05, 0.05, 0.08), 0.3), seg=8, rings=6)
        m.sphere(0.025, (sx * 0.07, 0.4, -0.09), m.mat("cheek", (1.0, 0.6, 0.6), 0.7), scale=(1, 0.7, 0.6), seg=8, rings=6)
    m.torus(0.125, 0.025, (0, 0.47, 0), hat, seg=22, tube=8)
    m.lathe([(0.13, 0.0), (0.1, 0.12), (0.06, 0.26), (0.02, 0.38), (0.0, 0.42)], (0, 0.47, 0.03), hat, rot=(-12, 0, 0), seg=18)
    for x in (-0.07, 0.07):
        m.rbox((0.09, 0.05, 0.15), (x, 0.065, -0.09), m.mat("boot", (0.2, 0.12, 0.08), 0.8), 0.025)
    return m


@model
def flamingo():
    m = new("flamingo")
    pk = m.mat("pink", (1.0, 0.45, 0.6), 0.6)
    pk2 = m.mat("pink_dark", (0.9, 0.3, 0.45), 0.6)
    leg = m.mat("leg", (0.95, 0.4, 0.5), 0.6)
    m.cyl(0.012, 0.012, 0.42, (0, 0.6, 0.03), leg, seg=8)           # thigh down to the knee
    m.sphere(0.018, (0, 0.39, 0.03), leg, seg=8, rings=6)            # knee
    m.cyl(0.01, 0.01, 0.39, (0, 0.195, 0.03), leg, seg=8)            # stake into the lawn
    m.cyl(0.01, 0.012, 0.3, (0.04, 0.62, 0.1), leg, rot=(60, 0, -20), seg=8)   # tucked-up second leg
    m.sphere(0.17, (0, 0.88, 0.04), pk, scale=(0.75, 0.9, 1.45), seg=20, rings=12)
    for sx in (-1, 1):   # wings
        m.sphere(0.12, (sx * 0.1, 0.9, 0.08), pk2, scale=(0.3, 0.7, 1.4), seg=14, rings=8, rot=(-10, 0, 0))
    m.cyl(0.0, 0.08, 0.16, (0, 0.92, 0.3), pk2, rot=(-70, 0, 0), seg=10)        # tail
    # S-shaped neck from short segments
    pts = [(0, 0.98, -0.12), (0, 1.12, -0.17), (0, 1.25, -0.13), (0, 1.36, -0.07), (0, 1.46, -0.1), (0, 1.53, -0.18)]
    for a, b in zip(pts, pts[1:]):
        mid = [(x + y) / 2 for x, y in zip(a, b)]
        dy, dz = b[1] - a[1], b[2] - a[2]
        ln = math.hypot(dy, dz)
        ang = math.degrees(math.atan2(dz, dy))
        m.cyl(0.032, 0.036, ln + 0.02, tuple(mid), pk, rot=(ang, 0, 0), seg=12)
        m.sphere(0.034, b, pk, seg=12, rings=8)
    m.sphere(0.06, (0, 1.56, -0.22), pk, scale=(0.9, 0.9, 1.1), seg=14, rings=10)   # head
    m.cyl(0.018, 0.028, 0.08, (0, 1.53, -0.3), m.mat("beak_pale", (0.98, 0.9, 0.85), 0.5), rot=(-110, 0, 0), seg=10)
    m.cyl(0.004, 0.018, 0.06, (0, 1.49, -0.355), m.mat("beak", (0.1, 0.1, 0.1), 0.5), rot=(-150, 0, 0), seg=10)
    for sx in (-1, 1):
        m.sphere(0.011, (sx * 0.045, 1.58, -0.24), m.mat("eye", (0.05, 0.05, 0.05), 0.3), seg=8, rings=6)
    return m


@model
def fence_post():
    m = new("fence_post")
    wood = m.mat("post", (0.8, 0.72, 0.6), 0.8)
    m.rbox((0.12, 1.72, 0.12), (0, 0.86, 0), wood, 0.012)
    m.cyl(0.0, 0.085, 0.1, (0, 1.77, 0), wood, seg=4, rot=(0, 45, 0))   # pointed top
    for y in (0.45, 1.35):                                             # rail brackets
        m.rbox((0.14, 0.09, 0.02), (0, y, -0.065), m.mat("bracket", (0.3, 0.3, 0.32), 0.5, 0.6), 0.004)
        for x in (-0.04, 0.04):
            m.sphere(0.008, (x, y, -0.077), m.mat("rivet", METAL, 0.3, 0.9), seg=6, rings=4)
    return m


# =============================================================== TOYS / ITEMS
# Toys are centred on the body; items on their grip. Same sizes as the physics shapes in prop.gd.
@model
def crate():
    m = new("crate")
    w = m.mat("wood", (0.85, 0.65, 0.4), 0.6)
    d = m.mat("wood_dark", (0.6, 0.42, 0.24), 0.7)
    m.rbox((0.8, 0.8, 0.8), (0, 0, 0), d, 0.02)
    for s in (-1, 1):
        for y in (-0.27, 0, 0.27):
            m.rbox((0.74, 0.2, 0.02), (0, y, s * 0.4), w, 0.01)
            m.rbox((0.02, 0.2, 0.74), (s * 0.4, y, 0), w, 0.01)
    for ex in (-1, 1):
        for ez in (-1, 1):
            m.rbox((0.07, 0.82, 0.07), (ex * 0.37, 0, ez * 0.37), d, 0.015)
    m.rbox((0.04, 0.92, 0.02), (0, 0, 0.415), d, 0.005, rot=(0, 0, 45))
    return m


@model
def chair():
    m = new("chair")
    wood = m.mat("wood", (0.9, 0.7, 0.5), 0.5)
    dk = m.mat("wood_dark", (0.7, 0.5, 0.34), 0.6)
    m.rbox((0.5, 0.06, 0.5), (0, 0.0, 0), wood, 0.015)
    for x in (-0.2, 0.2):
        for z in (-0.2, 0.2):
            m.rbox((0.05, 0.42, 0.05), (x, -0.25, z), dk, 0.01)
        m.rbox((0.05, 0.55, 0.05), (x, 0.3, 0.22), dk, 0.01)
    m.rbox((0.45, 0.14, 0.04), (0, 0.4, 0.22), wood, 0.01)
    m.rbox((0.45, 0.12, 0.04), (0, 0.22, 0.22), wood, 0.01)
    m.rbox((0.4, 0.03, 0.03), (0, -0.28, 0.0), dk, 0.005)
    return m


@model
def melon():
    m = new("melon")
    g1 = m.mat("rind", (0.12, 0.45, 0.18), 0.5)
    g2 = m.mat("rind_stripe", (0.06, 0.28, 0.1), 0.5)
    m.sphere(0.25, (0, 0, 0), g1, scale=(1.15, 0.9, 0.9), seg=24, rings=14)
    m.cyl(0.015, 0.02, 0.05, (0, 0.22, 0), m.mat("stem", (0.4, 0.3, 0.1), 0.8), seg=8)
    return m


@model
def duck():
    m = new("duck")
    y = m.mat("yellow", (1.0, 0.85, 0.1), 0.35)
    m.sphere(0.2, (0, 0, 0), y, scale=(1.0, 0.9, 1.25), seg=22, rings=14)
    m.sphere(0.12, (0, 0.2, -0.14), y, seg=18, rings=12)
    m.sphere(0.07, (0, -0.02, 0.27), y, scale=(0.8, 1.0, 1.3), seg=12, rings=8, rot=(30, 0, 0))   # tail
    m.sphere(0.12, (-0.18, 0.02, 0.02), y, scale=(0.35, 0.8, 1.0), seg=10, rings=8, rot=(0, 0, 20))
    m.sphere(0.12, (0.18, 0.02, 0.02), y, scale=(0.35, 0.8, 1.0), seg=10, rings=8, rot=(0, 0, -20))
    bk = m.mat("beak", (1.0, 0.5, 0.05), 0.5)
    m.sphere(0.06, (0, 0.17, -0.27), bk, scale=(1.3, 0.55, 1.2), seg=12, rings=8)
    blk = m.mat("eye", (0.02, 0.02, 0.02), 0.2)
    for x in (-0.055, 0.055):
        m.sphere(0.022, (x, 0.25, -0.22), blk, seg=8, rings=6)
        m.sphere(0.007, (x * 1.0 + (0.008 if x > 0 else -0.008), 0.256, -0.238), m.mat("glint", (1, 1, 1), 0.2), seg=6, rings=4)
    return m


@model
def pin():
    m = new("pin")
    w = m.mat("white", (0.97, 0.97, 0.95), 0.3)
    r = m.mat("red", (0.85, 0.1, 0.1), 0.4)
    m.lathe([(0.0, -0.3), (0.07, -0.3), (0.095, -0.2), (0.1, -0.1), (0.07, 0.04), (0.04, 0.12), (0.045, 0.2), (0.065, 0.26),
             (0.06, 0.31), (0.0, 0.33)], (0, 0, 0), w, seg=22)
    m.cyl(0.058, 0.052, 0.025, (0, 0.14, 0), r, seg=22, caps=False)
    m.cyl(0.062, 0.066, 0.025, (0, 0.17, 0), r, seg=22, caps=False)
    return m


@model
def barrel():
    m = new("barrel")
    red = m.mat("red", (0.85, 0.12, 0.1), 0.5, 0.3)
    bk = m.mat("band", (0.15, 0.15, 0.15), 0.4, 0.6)
    yw = m.mat("hazard", (1.0, 0.85, 0.1), 0.5)
    m.lathe([(0.0, -0.5), (0.32, -0.5), (0.35, -0.44), (0.35, 0.44), (0.32, 0.5), (0.0, 0.5)], (0, 0, 0), red, seg=26)
    for y in (-0.25, 0.25):
        m.cyl(0.36, 0.36, 0.06, (y * 0, y, 0), bk, seg=26, caps=False)
    m.torus(0.3, 0.02, (0, 0.5, 0), bk, seg=24, tube=6)
    m.cyl(0.08, 0.08, 0.04, (0.15, 0.51, 0.1), m.mat("cap", (0.6, 0.6, 0.62), 0.3, 0.8), seg=14)
    # hazard badge (flat disc on the front, -Z)
    m.cyl(0.13, 0.13, 0.01, (0, 0.02, -0.352), yw, rot=(90, 0, 0), seg=20)
    m.sphere(0.04, (0, 0.04, -0.36), bk, scale=(1, 1, 0.3), seg=10, rings=8)
    m.rbox((0.04, 0.1, 0.012), (0, -0.03, -0.36), bk, 0.004)
    return m


@model
def bomb():
    m = new("bomb")
    m.sphere(0.25, (0, 0, 0), m.mat("shell", (0.1, 0.1, 0.1), 0.35, 0.5), seg=22, rings=14)
    m.cyl(0.05, 0.07, 0.07, (0, 0.26, 0), m.mat("cap", (0.35, 0.35, 0.38), 0.4, 0.7), seg=12)
    m.cyl(0.008, 0.008, 0.12, (0.03, 0.34, 0), m.mat("fuse", (0.7, 0.6, 0.4), 0.9), rot=(0, 0, -25), seg=6)
    m.node("Fuse")
    m.sphere(0.04, (0.06, 0.4, 0), m.mat("spark", (1.0, 0.3, 0.0), 0.3, emissive=(1.0, 0.3, 0.0)), seg=8, rings=6)
    m.node(None)
    m.sphere(0.04, (-0.1, 0.12, -0.2), m.mat("shine", (1, 1, 1), 0.1), scale=(1, 0.6, 0.6), seg=8, rings=6)
    return m


@model
def pistol():
    """Classic steel single-stack service pistol: long slide, rear slide grooves, spur hammer,
    beaver-tail grip safety and chequered brown grip panels. Muzzle at -Z, origin = grip area."""
    m = new("pistol")
    steel = m.mat("steel", (0.2, 0.21, 0.23), 0.45, 0.75)
    slide_m = m.mat("slide", (0.17, 0.18, 0.2), 0.4, 0.8)
    dark = m.mat("barrel", (0.04, 0.04, 0.045), 0.3, 0.8)
    groove = m.mat("serration", (0.08, 0.08, 0.09), 0.6, 0.7)
    grip = m.mat("grip", (0.36, 0.17, 0.1), 0.65)
    grip_dk = m.mat("checker", (0.25, 0.11, 0.06), 0.8)
    screw = m.mat("screw", (0.55, 0.55, 0.58), 0.3, 0.9)
    # slide: flat sides, narrower rounded top
    m.rbox((0.044, 0.05, 0.29), (0, 0.072, -0.02), slide_m, 0.006)
    m.rbox((0.034, 0.016, 0.29), (0, 0.1, -0.02), slide_m, 0.007)
    for i in range(8):   # vertical grooves at the back of the slide
        z = 0.072 + i * 0.0065
        for sx in (-1, 1):
            m.box((0.002, 0.042, 0.003), (sx * 0.0225, 0.075, z), groove)
    m.box((0.002, 0.022, 0.055), (0.0225, 0.085, -0.01), m.mat("port", (0.02, 0.02, 0.02), 0.6))   # ejection port
    m.cyl(0.017, 0.017, 0.012, (0, 0.07, -0.168), steel, rot=(90, 0, 0), seg=16)    # barrel bushing
    m.cyl(0.009, 0.009, 0.014, (0, 0.07, -0.17), dark, rot=(90, 0, 0), seg=12)      # bore
    m.rbox((0.006, 0.012, 0.012), (0, 0.114, -0.15), steel, 0.002)                 # front sight
    m.rbox((0.03, 0.012, 0.01), (0, 0.113, 0.118), steel, 0.002)                   # rear sight
    m.box((0.006, 0.006, 0.012), (0, 0.121, 0.118), dark)
    # frame
    m.rbox((0.04, 0.028, 0.175), (0, 0.035, -0.07), steel, 0.005)                  # dust cover
    m.rbox((0.04, 0.04, 0.075), (0, 0.03, 0.095), steel, 0.006)                    # frame top behind the trigger
    m.rbox((0.04, 0.04, 0.07), (0, 0.03, 0.035), steel, 0.005)                     # frame around the trigger
    m.rbox((0.012, 0.008, 0.125), (0, -0.026, 0.004), steel, 0.003)               # trigger guard bottom, back to the grip
    m.rbox((0.012, 0.05, 0.009), (0, -0.003, -0.058), steel, 0.003, rot=(-12, 0, 0))   # trigger guard front
    m.rbox((0.009, 0.026, 0.012), (0, 0.004, -0.014), steel, 0.003, rot=(-8, 0, 0))    # trigger
    # grip, raked back
    m.rbox((0.038, 0.15, 0.062), (0, -0.05, 0.1), steel, 0.008, rot=(-16, 0, 0))
    for sx in (-1, 1):
        m.rbox((0.006, 0.115, 0.052), (sx * 0.021, -0.045, 0.098), grip, 0.004, rot=(-16, 0, 0))
        for r in range(7):          # chequering: little raised squares
            for c in range(4):
                yy = -0.093 + r * 0.014
                zz = 0.08 + c * 0.012
                zz += -(yy + 0.045) * math.tan(math.radians(16))   # follow the rake
                m.box((0.003, 0.007, 0.007), (sx * 0.0245, yy, zz), grip_dk, rot=(-16, 0, 45))
        for yy in (-0.008, -0.085):  # grip screws
            zz = 0.098 - (yy + 0.045) * math.tan(math.radians(16))
            m.cyl(0.0055, 0.0055, 0.004, (sx * 0.0245, yy, zz), screw, rot=(0, 0, 90), seg=10)
    m.rbox((0.042, 0.014, 0.066), (0, -0.124, 0.122), steel, 0.004, rot=(-16, 0, 0))   # magazine base / housing
    m.torus(0.008, 0.002, (0, -0.132, 0.145), steel, rot=(90, 0, 0), seg=10, tube=4)  # lanyard loop
    # beaver-tail grip safety, spur hammer, levers
    m.rbox((0.036, 0.06, 0.045), (0, 0.05, 0.14), steel, 0.006)                   # frame tang behind the slide
    m.rbox((0.034, 0.016, 0.06), (0, 0.03, 0.17), steel, 0.006, rot=(-20, 0, 0))
    m.rbox((0.011, 0.035, 0.016), (0, 0.09, 0.15), steel, 0.004, rot=(-35, 0, 0))
    m.rbox((0.006, 0.01, 0.03), (0.023, 0.058, 0.108), steel, 0.003)               # thumb safety
    m.rbox((0.006, 0.01, 0.045), (0.023, 0.047, -0.03), steel, 0.003)              # slide stop
    m.cyl(0.005, 0.005, 0.05, (0, 0.045, -0.05), screw, rot=(0, 0, 90), seg=8)    # slide stop pin
    m.cyl(0.006, 0.006, 0.044, (0, 0.022, 0.052), groove, rot=(0, 0, 90), seg=10)  # magazine release
    m.node("Flash")
    m.sphere(0.07, (0, 0.07, -0.25), m.mat("flash", (1.0, 0.8, 0.3), 0.3, emissive=(1.0, 0.8, 0.3)), seg=10, rings=8)
    m.node(None)
    return m


@model
def knife():
    m = new("knife")
    blade = m.mat("blade", (0.85, 0.87, 0.9), 0.12, 0.95)
    # blade as a thin box with a tapered tip
    m.rbox((0.012, 0.05, 0.2), (0, 0, -0.13), blade, 0.003)
    m.rbox((0.012, 0.03, 0.06), (0, -0.005, -0.255), blade, 0.003)
    edge = m.mat("edge_bright", (0.97, 0.97, 1.0), 0.05, 1.0)
    m.box((0.004, 0.008, 0.25), (0, -0.024, -0.15), edge)                    # sharpened edge
    for sx in (-1, 1):
        m.box((0.002, 0.008, 0.15), (sx * 0.006, 0.006, -0.12), m.mat("fuller", (0.6, 0.62, 0.66), 0.2, 0.9))   # blood groove
    m.rbox((0.035, 0.07, 0.014), (0, 0, -0.025), m.mat("guard", (0.16, 0.16, 0.18), 0.35, 0.7), 0.004)
    m.rbox((0.03, 0.045, 0.13), (0, 0, 0.05), m.mat("handle", (0.25, 0.15, 0.1), 0.8), 0.012)
    for z in (0.01, 0.05, 0.09):
        m.cyl(0.006, 0.006, 0.034, (0, 0, z), m.mat("rivet", METAL, 0.3, 0.9), rot=(0, 0, 90), seg=8)
    m.sphere(0.02, (0, 0, 0.12), m.mat("pommel", (0.16, 0.16, 0.18), 0.35, 0.7), seg=10, rings=6)
    return m


@model
def bat():
    m = new("bat")
    wood = m.mat("wood", (0.9, 0.7, 0.45), 0.5)
    tape = m.mat("tape", (0.1, 0.1, 0.12), 0.9)
    # lathe along Y then rotate to Z: thin handle at +Z, fat end at -Z
    m.lathe([(0.0, 0.45), (0.04, 0.44), (0.047, 0.38), (0.046, 0.15), (0.03, -0.05), (0.018, -0.22), (0.018, -0.4), (0.024, -0.43), (0.0, -0.45)],
            (0, 0, -0.3), wood, rot=(-90, 0, 0), seg=18)
    m.cyl(0.02, 0.02, 0.18, (0, 0, -0.3 + 0.32), tape, rot=(90, 0, 0), seg=12)
    m.sphere(0.026, (0, 0, 0.16), tape, scale=(1, 1, 0.6), seg=10, rings=6)
    return m


@model
def cig():
    m = new("cig")
    m.cyl(0.0072, 0.0072, 0.1, (0, 0, 0.0), m.mat("paper", (0.97, 0.97, 0.95), 0.9), rot=(90, 0, 0), seg=10)
    m.cyl(0.0074, 0.0074, 0.03, (0, 0, 0.065), m.mat("filter", (0.85, 0.5, 0.2), 0.9), rot=(90, 0, 0), seg=10)
    m.node("Tip")
    m.cyl(0.0066, 0.0066, 0.008, (0, 0, -0.052), m.mat("ember", (1.0, 0.3, 0.05), 0.5, emissive=(1.0, 0.3, 0.05)), rot=(90, 0, 0), seg=10)
    m.node(None)
    m.cyl(0.0068, 0.0068, 0.006, (0, 0, -0.047), m.mat("ash", (0.5, 0.5, 0.5), 1.0), rot=(90, 0, 0), seg=10)
    return m


@model
def console():
    m = new("console")
    b = m.mat("body", (0.25, 0.25, 0.85), 0.4)
    dk = m.mat("dark", (0.1, 0.1, 0.1), 0.5)
    m.rbox((0.2, 0.11, 0.025), (0, 0, 0), b, 0.008)
    m.rbox((0.12, 0.08, 0.004), (0, 0.005, 0.014), m.mat("bezel", (0.05, 0.05, 0.07), 0.4), 0.002)
    m.node("Screen")
    m.box((0.1, 0.065, 0.004), (0, 0.005, 0.0165), m.mat("screen", (0.3, 0.9, 0.4), 0.2, emissive=(0.3, 0.9, 0.4), emit_strength=0.9))
    m.node(None)
    m.rbox((0.03, 0.01, 0.006), (-0.073, 0, 0.015), dk, 0.002)
    m.rbox((0.01, 0.03, 0.006), (-0.073, 0, 0.015), dk, 0.002)
    m.sphere(0.011, (0.07, -0.012, 0.015), m.mat("btnA", (0.9, 0.2, 0.25), 0.4), seg=10, rings=6, scale=(1, 1, 0.5))
    m.sphere(0.011, (0.082, 0.013, 0.015), m.mat("btnB", (0.95, 0.85, 0.2), 0.4), seg=10, rings=6, scale=(1, 1, 0.5))
    m.cyl(0.006, 0.006, 0.004, (0.07, -0.04, 0.014), dk, rot=(90, 0, 0), seg=8)
    for k in range(2):    # start / select
        m.rbox((0.016, 0.005, 0.004), (-0.012 + k * 0.024, -0.047, 0.0135), dk, 0.002)
    for i in range(3):    # speaker holes
        for j in range(2):
            m.cyl(0.002, 0.002, 0.004, (0.082 + i * 0.006, -0.035 - j * 0.006, 0.0135), dk, rot=(90, 0, 0), seg=6)
    m.rbox((0.04, 0.008, 0.02), (0.06, 0.057, 0.0), dk, 0.003)   # shoulder button
    m.rbox((0.04, 0.008, 0.02), (-0.06, 0.057, 0.0), dk, 0.003)
    return m


@model
def burger():
    m = new("burger")
    bun = m.mat("bun", (0.88, 0.62, 0.3), 0.8)
    m.cyl(0.075, 0.07, 0.035, (0, -0.075, 0), bun, seg=22)
    m.cyl(0.08, 0.08, 0.035, (0, -0.04, 0), m.mat("patty", (0.35, 0.18, 0.1), 0.9), seg=22)
    m.rbox((0.14, 0.01, 0.14), (0, -0.017, 0), m.mat("cheese", (1.0, 0.8, 0.15), 0.6), 0.002, rot=(0, 45, 0))
    m.cyl(0.085, 0.085, 0.015, (0, -0.005, 0), m.mat("lettuce", (0.3, 0.7, 0.2), 0.8), seg=22)
    m.cyl(0.07, 0.07, 0.015, (0, 0.01, 0), m.mat("tomato", (0.85, 0.15, 0.1), 0.6), seg=22)
    for a in (20, 140, 250):
        ar = math.radians(a)
        m.sphere(0.014, (math.cos(ar) * 0.085, -0.026, math.sin(ar) * 0.085), m.mat("cheese", (1.0, 0.8, 0.15), 0.6), scale=(1, 1.6, 1), seg=8, rings=6)
    m.sphere(0.078, (0, 0.02, 0), bun, scale=(1, 0.6, 1), seg=22, rings=10)
    seed = m.mat("seed", (1.0, 0.95, 0.8), 0.7)
    for k in range(8):
        a = math.tau * k / 8
        m.sphere(0.008, (math.cos(a) * 0.04, 0.062, math.sin(a) * 0.04), seed, scale=(1, 0.5, 1), seg=6, rings=4)
    return m


@model
def pizza():
    m = new("pizza")
    crust = m.mat("crust", (0.85, 0.62, 0.3), 0.8)
    cheese = m.mat("cheese", (1.0, 0.75, 0.2), 0.5)
    # slice: triangle, apex at -Z
    m.prism([(0.0, -0.15), (0.12, 0.13), (-0.12, 0.13)][::-1], -0.01, 0.01, (0, 0, 0), crust)
    m.prism([(0.0, -0.13), (0.1, 0.12), (-0.1, 0.12)][::-1], 0.01, 0.018, (0, 0, 0), cheese)
    m.rbox((0.25, 0.03, 0.04), (0, 0.0, 0.15), m.mat("crust_edge", (0.78, 0.5, 0.2), 0.85), 0.015)
    red = m.mat("pepperoni", (0.75, 0.15, 0.12), 0.5)
    for p in ((0, 0.025, -0.07), (-0.04, 0.025, 0.04), (0.045, 0.025, 0.05)):
        m.cyl(0.026, 0.026, 0.008, p, red, seg=14)
    m.sphere(0.01, (0.02, 0.026, -0.02), m.mat("olive", (0.1, 0.12, 0.1), 0.6), scale=(1, 0.5, 1), seg=6, rings=4)
    rng = random.Random(3)
    for p in ((0.0, 0.025, -0.035), (-0.03, 0.025, 0.08), (0.05, 0.025, 0.1), (-0.065, 0.025, 0.11)):
        m.cyl(0.02, 0.02, 0.008, p, red, seg=14)
    for i in range(10):   # melted cheese bubbles
        z = rng.uniform(-0.1, 0.1)
        w = 0.1 * (z + 0.13) / 0.25
        m.sphere(0.012, (rng.uniform(-w, w), 0.019, z), cheese, scale=(1, 0.4, 1), seg=8, rings=4)
    for i in range(8):    # bumpy crust
        m.sphere(0.022, (-0.105 + i * 0.03, 0.012, 0.15), m.mat("crust_edge", (0.78, 0.5, 0.2), 0.85), scale=(1, 0.8, 1), seg=10, rings=6)
    return m


@model
def soda():
    m = new("soda")
    red = m.mat("can", (0.85, 0.1, 0.1), 0.3, 0.5)
    sv = m.mat("silver", (0.82, 0.82, 0.86), 0.2, 0.9)
    m.lathe([(0.0, -0.06), (0.03, -0.06), (0.036, -0.05), (0.036, 0.05), (0.032, 0.058), (0.032, 0.062), (0.0, 0.062)], (0, 0, 0), red, seg=22)
    m.cyl(0.0372, 0.0372, 0.035, (0, 0.0, 0), m.mat("label", (0.96, 0.96, 0.96), 0.4, 0.3), seg=22, caps=False)
    m.cyl(0.031, 0.033, 0.008, (0, 0.063, 0), sv, seg=20)
    m.cyl(0.027, 0.027, 0.004, (0, 0.067, 0), m.mat("lid", (0.7, 0.7, 0.75), 0.2, 0.9), seg=18)
    m.rbox((0.014, 0.002, 0.024), (0, 0.07, 0), sv, 0.0008)
    return m


@model
def beer():
    m = new("beer")
    glass = m.mat("glass", (0.4, 0.22, 0.06), 0.1, 0.1)
    m.lathe([(0.0, -0.13), (0.028, -0.13), (0.033, -0.12), (0.033, -0.01), (0.03, 0.04), (0.016, 0.1), (0.013, 0.13), (0.015, 0.135), (0.0, 0.135)],
            (0, 0, 0), glass, seg=20)
    m.cyl(0.0335, 0.0335, 0.07, (0, -0.05, 0), m.mat("label", (0.95, 0.9, 0.7), 0.6), seg=20, caps=False)
    m.cyl(0.0338, 0.0338, 0.012, (0, -0.075, 0), m.mat("labelstripe", (0.6, 0.15, 0.1), 0.6), seg=20, caps=False)
    m.cyl(0.016, 0.016, 0.012, (0, 0.135, 0), m.mat("cap", (0.8, 0.7, 0.2), 0.3, 0.8), seg=14)
    m.cyl(0.0125, 0.0125, 0.03, (0, 0.095, 0), m.mat("neck", (0.9, 0.85, 0.5), 0.5), seg=10, caps=False)
    return m



# ================================================================== PEOPLE
# Body parts of the player rig. Material names "skin", "shirt", "pants", "shoe", "hair"... are
# re-coloured at runtime from the player's look (see ModelLib.tint); other colours stay fixed.
# Node names starting with "Head" / "Neck" are drawn on the head render layer (hidden in first person).
def _dk(c, f):
    return tuple(max(0.0, x * (1 - f)) for x in c)


def person_mats(m):
    return {
        "skin": m.mat("skin", (0.96, 0.8, 0.69), 0.8),
        "skin_dark": m.mat("skin_dark", (0.9, 0.74, 0.64), 0.8),
        "shirt": m.mat("shirt", (0.3, 0.5, 0.9), 0.85),
        "shirt_dark": m.mat("shirt_dark", (0.22, 0.38, 0.7), 0.85),
        "pants": m.mat("pants", (0.2, 0.25, 0.4), 0.85),
        "pants_dark": m.mat("pants_dark", (0.15, 0.19, 0.3), 0.85),
        "shoe": m.mat("shoe", (0.8, 0.2, 0.2), 0.7),
        "sole": m.mat("sole", (0.9, 0.9, 0.9), 0.8),
        "hair": m.mat("hair", (0.1, 0.07, 0.05), 0.9),
        "belt": m.mat("belt", (0.16, 0.12, 0.09), 0.6),
        "gold": m.mat("gold", (0.9, 0.78, 0.3), 0.3, 0.8),
        "white": m.mat("white", (0.97, 0.97, 0.97), 0.5),
        "eye": m.mat("eye", (0.08, 0.08, 0.1), 0.2),
        "lips": m.mat("lips", (0.7, 0.35, 0.38), 0.6),
    }


@model
def person_torso():
    m = new("person_torso")
    c = person_mats(m)
    m.cyl(0.19, 0.15, 0.36, (0, 0.12, 0), c["shirt"], seg=24, scale=(1, 1, 0.62))
    m.cyl(0.15, 0.145, 0.2, (0, -0.1, 0), c["shirt"], seg=24, scale=(1, 1, 0.66))
    m.cyl(0.152, 0.15, 0.03, (0, -0.19, 0), c["shirt_dark"], seg=24, scale=(1, 1, 0.67))       # hem
    m.cyl(0.16, 0.158, 0.17, (0, -0.27, 0), c["pants"], seg=24, scale=(1, 1, 0.7))
    m.cyl(0.162, 0.162, 0.035, (0, -0.2, 0), c["belt"], seg=24, scale=(1, 1, 0.7))
    m.rbox((0.045, 0.032, 0.01), (0, -0.2, -0.118), c["gold"], 0.004)
    m.box((0.004, 0.11, 0.004), (0, -0.28, -0.112), c["pants_dark"])                              # fly seam
    for s in (-1, 1):
        m.sphere(0.07, (s * 0.215, 0.25, 0), c["shirt"], seg=14, rings=10)                       # shoulders
        m.rbox((0.06, 0.05, 0.012), (s * 0.075, 0.14, -0.108), c["shirt_dark"], 0.004)         # chest pocket
        m.rbox((0.07, 0.08, 0.012), (s * 0.11, -0.29, -0.108), c["pants_dark"], 0.004)         # hip pocket
    m.cyl(0.075, 0.085, 0.03, (0, 0.305, 0), c["shirt_dark"], seg=20, scale=(1, 1, 0.9))        # collar
    m.rbox((0.035, 0.3, 0.012), (0, 0.1, -0.12), c["shirt_dark"], 0.004)                         # button strip
    for k in range(4):
        m.sphere(0.008, (0, 0.2 - k * 0.07, -0.128), c["white"], seg=6, rings=4)
    m.node("Neck")
    m.cyl(0.044, 0.05, 0.11, (0, 0.345, 0), c["skin"], seg=16)
    m.node(None)
    return m


@model
def person_head():
    m = new("person_head")
    c = person_mats(m)
    m.node("Head")
    m.sphere(0.135, (0, 0.02, 0), c["skin"], scale=(0.96, 1.08, 0.98), seg=26, rings=18)
    m.sphere(0.1, (0, -0.065, -0.025), c["skin"], scale=(0.88, 0.8, 0.9), seg=20, rings=12)  # jaw
    for s in (-1, 1):
        m.sphere(0.045, (0.125 * s, 0.0, 0.0), c["skin_dark"], scale=(0.45, 0.75, 0.55), seg=12, rings=8)   # ears
        m.sphere(0.03, (0.048 * s, 0.025, -0.118), c["white"], seg=12, rings=8)                         # eyes
        m.sphere(0.017, (0.048 * s, 0.025, -0.14), c["eye"], seg=10, rings=8)
        m.sphere(0.005, (0.048 * s - 0.004, 0.03, -0.155), c["white"], seg=6, rings=4)                  # glint
        m.rbox((0.056, 0.012, 0.02), (0.048 * s, 0.062, -0.125), c["hair"], 0.004, rot=(0, 0, -8 * s))  # brows
    m.sphere(0.022, (0, -0.005, -0.13), c["skin_dark"], scale=(0.8, 0.7, 1.1), seg=12, rings=8)         # nose
    m.rbox((0.055, 0.012, 0.02), (0, -0.055, -0.128), c["lips"], 0.005)
    m.node(None)
    return m


@model
def person_uarm():
    m = new("person_uarm")
    c = person_mats(m)
    m.cyl(0.062, 0.057, 0.17, (0, 0.065, 0), c["shirt"], seg=16)
    m.cyl(0.059, 0.059, 0.025, (0, -0.012, 0), c["shirt_dark"], seg=16)          # cuff
    m.cyl(0.052, 0.047, 0.15, (0, -0.075, 0), c["skin"], seg=16)
    m.sphere(0.064, (0, 0.14, 0), c["shirt"], scale=(1, 0.9, 1), seg=14, rings=10)
    m.sphere(0.046, (0, -0.15, 0), c["skin"], seg=12, rings=8)
    return m


def _forearm(name, sx):
    def f():
        m = new(name)
        c = person_mats(m)
        m.cyl(0.046, 0.034, 0.3, (0, 0, 0), c["skin"], seg=16)
        m.cyl(0.036, 0.036, 0.02, (0, -0.13, 0), c["white"], seg=14)                     # wrist band
        m.rbox((0.07, 0.085, 0.034), (0, -0.19, 0), c["skin"], 0.012)                     # palm
        for k in range(4):                                                                  # fingers
            m.rbox((0.015, 0.055 - abs(k - 1.5) * 0.004, 0.02), (-0.025 + k * 0.0167, -0.255, -0.003), c["skin_dark"], 0.006)
        m.rbox((0.022, 0.05, 0.026), (0.042 * sx, -0.2, -0.012), c["skin"], 0.008, rot=(0, 0, -20 * sx))   # thumb
        return m
    return f


reg("person_larm_l", _forearm("person_larm_l", 1.0))
reg("person_larm_r", _forearm("person_larm_r", -1.0))


@model
def person_uleg():
    m = new("person_uleg")
    c = person_mats(m)
    m.cyl(0.092, 0.07, 0.45, (0, 0, 0), c["pants"], seg=18)
    m.sphere(0.07, (0, -0.225, 0), c["pants"], seg=14, rings=10)
    m.box((0.004, 0.36, 0.004), (0.0, -0.0, -0.088), c["pants_dark"])                     # crease
    return m


@model
def person_lleg():
    m = new("person_lleg")
    c = person_mats(m)
    m.cyl(0.068, 0.05, 0.42, (0, 0, 0), c["pants"], seg=18)
    m.cyl(0.052, 0.05, 0.05, (0, -0.18, 0), c["white"], seg=16)                           # sock
    m.rbox((0.1, 0.07, 0.15), (0, -0.205, -0.045), c["shoe"], 0.02)
    m.sphere(0.052, (0, -0.205, -0.115), c["shoe"], scale=(1.0, 0.75, 1.0), seg=14, rings=8)
    m.rbox((0.11, 0.025, 0.26), (0, -0.243, -0.05), c["sole"], 0.01)
    m.rbox((0.07, 0.01, 0.07), (0, -0.168, -0.08), c["white"], 0.003, rot=(-20, 0, 0))       # laces
    m.rbox((0.07, 0.01, 0.015), (0, -0.19, -0.1), c["white"], 0.003)
    m.rbox((0.07, 0.01, 0.015), (0, -0.176, -0.06), c["white"], 0.003)
    return m


# ================================================================ WEAPONS / MISC
@model
def rpg():
    """Held rocket launcher. Tube along Z (muzzle at -Z, rocket tip sticks out), grip below."""
    m = new("rpg")
    od = m.mat("olive", (0.28, 0.34, 0.2), 0.6, 0.2)
    dk = m.mat("dark", (0.1, 0.1, 0.11), 0.45, 0.6)
    red = m.mat("warhead", (0.8, 0.12, 0.1), 0.45)
    wd = m.mat("wood", (0.4, 0.28, 0.18), 0.7)
    m.cyl(0.055, 0.055, 0.8, (0, 0.05, 0.05), od, rot=(90, 0, 0), seg=18)
    m.cyl(0.075, 0.055, 0.14, (0, 0.05, 0.5), od, rot=(90, 0, 0), seg=18)                   # rear flare
    m.cyl(0.062, 0.062, 0.05, (0, 0.05, -0.18), dk, rot=(90, 0, 0), seg=18)
    m.cyl(0.062, 0.062, 0.05, (0, 0.05, 0.3), dk, rot=(90, 0, 0), seg=18)
    m.cyl(0.0, 0.05, 0.2, (0, 0.05, -0.55), red, rot=(-90, 0, 0), seg=16)                    # rocket nose
    m.cyl(0.05, 0.05, 0.1, (0, 0.05, -0.4), m.mat("warhead_band", (0.9, 0.9, 0.9), 0.5), rot=(90, 0, 0), seg=16)
    m.rbox((0.045, 0.14, 0.07), (0, -0.04, 0.0), wd, 0.012, rot=(10, 0, 0))                  # grip
    m.rbox((0.045, 0.09, 0.06), (0, -0.03, -0.25), wd, 0.012)                                # front grip
    m.rbox((0.02, 0.05, 0.1), (0.07, 0.11, -0.05), dk, 0.006)                                # sight
    m.rbox((0.012, 0.03, 0.012), (0.07, 0.14, -0.1), dk, 0.003)
    m.node("Flash")
    m.sphere(0.12, (0, 0.05, 0.6), m.mat("backblast", (1.0, 0.7, 0.3), 0.3, emissive=(1.0, 0.6, 0.2)), seg=10, rings=8)
    m.node(None)
    return m


@model
def rocket():
    """Flying rocket: nose at -Z, fins, and a flame node at the back."""
    m = new("rocket")
    wh = m.mat("body", (0.92, 0.92, 0.9), 0.4, 0.2)
    red = m.mat("nose", (0.85, 0.12, 0.1), 0.4)
    dk = m.mat("fin", (0.2, 0.2, 0.24), 0.5, 0.5)
    m.cyl(0.09, 0.09, 0.6, (0, 0, 0.05), wh, rot=(90, 0, 0), seg=18)
    m.lathe([(0.0, 0.0), (0.04, 0.06), (0.08, 0.15), (0.09, 0.22)], (0, 0, 0), red, rot=(90, 0, 0), seg=18) if False else None
    m.cyl(0.0, 0.09, 0.26, (0, 0, -0.36), red, rot=(-90, 0, 0), seg=18)
    m.cyl(0.095, 0.095, 0.05, (0, 0, -0.2), dk, rot=(90, 0, 0), seg=18)
    for a in (0, 90, 180, 270):
        m.prism([(0.0, 0.0), (0.0, 0.2), (0.17, 0.0)] if False else [(0.0, 0.05), (0.17, 0.12), (0.0, 0.12)], -0.012, 0.012, (0, 0, 0), dk, rot=(0, 0, 0)) if False else None
        ar = math.radians(a)
        m.rbox((0.025, 0.16, 0.2), (math.sin(ar) * 0.12, math.cos(ar) * 0.12, 0.28), dk, 0.006, rot=(0, 0, -a))
    m.cyl(0.07, 0.08, 0.05, (0, 0, 0.36), dk, rot=(90, 0, 0), seg=14)
    m.node("Flame")
    m.cyl(0.0, 0.07, 0.4, (0, 0, 0.58), m.mat("flame", (1.0, 0.55, 0.1), 0.3, emissive=(1.0, 0.5, 0.05)), rot=(-90, 0, 0), seg=12)
    m.cyl(0.0, 0.04, 0.25, (0, 0, 0.5), m.mat("flame_core", (1.0, 0.95, 0.6), 0.3, emissive=(1.0, 0.9, 0.5)), rot=(-90, 0, 0), seg=10)
    m.node(None)
    return m


@model
def diving_board():
    """Origin = floor under the pedestal. Board runs toward -Z (2.4 m), top at y = 0.7."""
    m = new("diving_board")
    ped = m.mat("pedestal", (0.92, 0.92, 0.9), 0.6)
    m.rbox((0.7, 0.62, 0.85), (0, 0.31, 0.0), ped, 0.03)
    m.rbox((0.74, 0.05, 0.9), (0, 0.64, 0.0), m.mat("cap", (0.8, 0.8, 0.82), 0.4), 0.02)
    m.node("Board")
    m.rbox((0.62, 0.07, 3.0), (0, 0.69, -1.1), m.mat("board", (0.15, 0.55, 0.9), 0.35), 0.025)
    m.rbox((0.58, 0.012, 2.8), (0, 0.73, -1.15), m.mat("grip", (0.9, 0.95, 1.0), 0.95), 0.004)
    m.rbox((0.64, 0.05, 0.1), (0, 0.69, 0.42), m.mat("hinge", (0.7, 0.7, 0.75), 0.3, 0.8), 0.01)
    m.node(None)
    return m



@model
def cart():
    """Supermarket trolley. Front at -Z, handle at +Z, floor at y = -0.5, origin = collider centre."""
    m = new("cart")
    wire = m.mat("chrome_wire", (0.82, 0.84, 0.88), 0.25, 0.9)
    red = m.mat("plastic_red", (0.85, 0.12, 0.12), 0.45)
    blk = m.mat("tire", (0.08, 0.08, 0.09), 0.85)
    grey = m.mat("caster", (0.5, 0.52, 0.55), 0.35, 0.8)
    r = 0.008
    # basket: wider and taller at the back (handle end), tapering to the front
    def corners(z, half_w, y0, y1):
        return [(-half_w, y0, z), (half_w, y0, z), (half_w, y1, z), (-half_w, y1, z)]
    back = corners(0.38, 0.29, -0.12, 0.45)
    front = corners(-0.46, 0.25, -0.05, 0.4)
    def bar(a, b, rad=r, mat=wire):
        a = np.array(a, float); b = np.array(b, float)
        d = b - a
        length = float(np.linalg.norm(d))
        mid = (a + b) / 2
        dy, dz, dx = d[1], d[2], d[0]
        rx = math.degrees(math.atan2(math.hypot(dx, dz), dy))     # tilt from +Y
        ry = math.degrees(math.atan2(dx, dz))
        m.cyl(rad, rad, length, tuple(mid), mat, rot=(rx, ry, 0), seg=6)
    for i in range(4):
        bar(back[i], back[(i + 1) % 4])
        bar(front[i], front[(i + 1) % 4])
        bar(back[i], front[i])
    # side and bottom wires (the mesh look)
    for k in range(1, 9):
        t = k / 9.0
        for side in (0, 1):   # left = corners 0/3, right = 1/2
            a0 = back[0 if side == 0 else 1]; a1 = back[3 if side == 0 else 2]
            b0 = front[0 if side == 0 else 1]; b1 = front[3 if side == 0 else 2]
            pa = [b0[j] + (a0[j] - b0[j]) * t for j in range(3)]
            pb = [b1[j] + (a1[j] - b1[j]) * t for j in range(3)]
            bar(pa, pb, r * 0.7)
        pa = [front[0][j] + (back[0][j] - front[0][j]) * t for j in range(3)]
        pb = [front[1][j] + (back[1][j] - front[1][j]) * t for j in range(3)]
        bar(pa, pb, r * 0.7)
    for k in range(1, 4):   # horizontal rungs round the sides
        t = k / 4.0
        for (c0, c1) in ((0, 3), (1, 2)):
            pa = [back[c0][j] + (back[c1][j] - back[c0][j]) * t for j in range(3)]
            pb = [front[c0][j] + (front[c1][j] - front[c0][j]) * t for j in range(3)]
            bar(pa, pb, r * 0.7)
    for k in range(1, 6):   # back gate and front grille
        t = k / 6.0
        bar([back[0][0] + (back[1][0] - back[0][0]) * t, back[0][1], 0.38], [back[0][0] + (back[1][0] - back[0][0]) * t, back[2][1], 0.38], r * 0.7)
        bar([front[0][0] + (front[1][0] - front[0][0]) * t, front[0][1], -0.46], [front[0][0] + (front[1][0] - front[0][0]) * t, front[2][1], -0.46], r * 0.7)
    # handle with a red plastic grip
    for sx in (-1, 1):
        bar((sx * 0.27, 0.42, 0.38), (sx * 0.27, 0.58, 0.52), 0.012)
    m.cyl(0.022, 0.022, 0.6, (0, 0.58, 0.52), red, rot=(0, 0, 90), seg=12)
    m.rbox((0.3, 0.06, 0.02), (0, 0.5, 0.41), red, 0.01)       # little red badge on the gate
    # chassis: two rails down to the wheels, a bottom tray
    for sx in (-1, 1):
        bar((sx * 0.24, -0.12, 0.36), (sx * 0.2, -0.4, 0.32), 0.012)
        bar((sx * 0.22, -0.05, -0.44), (sx * 0.19, -0.4, -0.4), 0.012)
        bar((sx * 0.2, -0.4, 0.32), (sx * 0.19, -0.4, -0.4), 0.012)
    for k in range(5):
        x = -0.16 + k * 0.08
        bar((x, -0.36, 0.3), (x, -0.36, -0.36), r * 0.7)
    for sx in (-1, 1):
        for z in (0.32, -0.4):
            m.cyl(0.012, 0.012, 0.05, (sx * 0.2, -0.42, z), grey, seg=6)
            m.cyl(0.05, 0.05, 0.025, (sx * 0.2, -0.45, z), blk, rot=(0, 0, 90), seg=14)
            m.cyl(0.02, 0.02, 0.03, (sx * 0.2, -0.45, z), grey, rot=(0, 0, 90), seg=8)
    # fold-down child seat flap at the back
    m.rbox((0.5, 0.012, 0.16), (0, 0.42, 0.3), red, 0.005)
    return m


@model
def coupe():
    """Kids' ride-on toy buggy with a cartoon face (original design): googly eyes, grin, roof on posts, chunky wheels.
    Front at -Z, floor at y = -0.3, origin = collider centre. The seat is open so the rider fits."""
    m = new("coupe")
    body = m.mat("body", (0.85, 0.12, 0.1), 0.35)        # body / roof colours are repainted in the game
    body_dk = m.mat("body_dark", (0.6, 0.08, 0.07), 0.45)
    white = m.mat("stripe", (0.96, 0.96, 0.94), 0.4)
    orange = m.mat("orange", (1.0, 0.55, 0.12), 0.4)
    blk = m.mat("tire", (0.07, 0.07, 0.08), 0.9)
    grey = m.mat("bumper", (0.8, 0.8, 0.82), 0.45)
    seat = m.mat("seat", (0.15, 0.15, 0.17), 0.8)
    # tub and nose
    m.rbox((0.7, 0.26, 1.08), (0, -0.14, 0.0), body, 0.1)
    m.rbox((0.62, 0.2, 0.5), (0, 0.02, -0.3), body, 0.09)                      # bonnet
    m.sphere(0.32, (0, -0.02, -0.46), body, scale=(1.0, 0.55, 0.45), seg=24, rings=10)   # rounded nose
    m.rbox((0.66, 0.24, 0.34), (0, 0.0, 0.36), body, 0.09)                     # rear deck
    for sx in (-1, 1):                                                         # side skirts
        m.rbox((0.06, 0.1, 0.62), (sx * 0.34, -0.22, 0.0), body_dk, 0.04)
    m.rbox((0.12, 0.016, 0.5), (0, 0.125, -0.3), white, 0.006)                 # racing stripe over the bonnet
    m.rbox((0.12, 0.016, 0.34), (0, 0.124, 0.36), white, 0.006)                # ... and the deck
    for sx in (-1, 1):                                                         # number roundels on the sides
        m.cyl(0.075, 0.075, 0.01, (sx * 0.352, -0.1, 0.04), white, rot=(0, 0, 90), seg=20)
        m.rbox((0.012, 0.07, 0.02), (sx * 0.358, -0.1, 0.04), orange, 0.004)
    # cockpit
    m.rbox((0.48, 0.05, 0.36), (0, 0.0, 0.12), seat, 0.02)                     # seat base
    m.rbox((0.46, 0.3, 0.07), (0, 0.15, 0.3), seat, 0.03, rot=(-10, 0, 0))     # seat back
    m.rbox((0.56, 0.1, 0.08), (0, 0.15, -0.08), body_dk, 0.03)                 # dashboard
    for x in (-0.14, 0.14):
        m.cyl(0.022, 0.022, 0.012, (x, 0.17, -0.12), white, rot=(60, 0, 0), seg=12)   # dials
    m.cyl(0.012, 0.012, 0.2, (0, 0.23, -0.06), blk, rot=(55, 0, 0), seg=8)     # column
    m.torus(0.085, 0.016, (0, 0.3, 0.0), orange, rot=(55, 0, 0), seg=20, tube=6)   # steering wheel
    m.cyl(0.02, 0.02, 0.02, (0, 0.3, 0.0), blk, rot=(55, 0, 0), seg=10)
    # cartoon face: big googly eyes on the bonnet, eyebrows, a grin under the headlights
    eye_w = m.mat("eye_white", (0.98, 0.98, 0.98), 0.25)
    pupil = m.mat("eye_pupil", (0.03, 0.03, 0.05), 0.2)
    for sx, name in ((-1, "PupilL"), (1, "PupilR")):
        m.sphere(0.1, (sx * 0.13, 0.2, -0.33), eye_w, scale=(1.0, 1.15, 0.75), seg=24, rings=14)
        m.torus(0.1, 0.012, (sx * 0.13, 0.2, -0.33), body_dk, rot=(90, 0, 0), seg=24, tube=6)   # eye rim
        m.node(name)     # pupils are their own nodes so the game can make them look around
        m.sphere(0.045, (sx * 0.13, 0.19, -0.395), pupil, scale=(1.0, 1.1, 0.6), seg=18, rings=10)
        m.sphere(0.013, (sx * 0.13 - 0.015, 0.21, -0.42), m.mat("eye_glint", (1.0, 1.0, 1.0), 0.1, emissive=(1.0, 1.0, 1.0), emit_strength=0.3), seg=8, rings=6)
        m.node(None)
        m.rbox((0.13, 0.025, 0.03), (sx * 0.14, 0.34, -0.33), orange, 0.01, rot=(0, 0, -sx * 12))   # eyebrows
    nose_c, nose_r, nose_s = (0.0, -0.02, -0.46), 0.32, (1.0, 0.55, 0.45)
    grin = m.mat("grin", (0.08, 0.04, 0.05), 0.6)
    for i in range(13):
        x = -0.17 + i * (0.34 / 12)
        y = -0.07 - 0.07 * (1 - (x / 0.17) ** 2)
        ex = x / (nose_r * nose_s[0])
        ey = (y - nose_c[1]) / (nose_r * nose_s[1])
        z = nose_c[2] - nose_r * nose_s[2] * math.sqrt(max(0.0, 1 - ex * ex - ey * ey))
        m.sphere(0.02, (x, y, z), grin, seg=10, rings=6)
    m.sphere(0.04, (0.0, -0.13, -0.585), m.mat("tongue", (0.95, 0.35, 0.45), 0.5), scale=(1.2, 0.6, 0.6), seg=12, rings=8)
    for sx in (-1, 1):
        m.sphere(0.04, (sx * 0.23, -0.06, -0.55), m.mat("cheek", (1.0, 0.45, 0.5), 0.6), scale=(1.0, 0.7, 0.5), seg=12, rings=8)
    # roof on four posts (its colour is set in the game: scenes/world/car_paint.gd)
    roof = m.mat("roof", (0.95, 0.95, 0.95), 0.4)
    for sx in (-1, 1):
        for z in (-0.2, 0.44):
            m.cyl(0.024, 0.026, 0.72, (sx * 0.31, 0.42, z), roof, seg=12)
    m.rbox((0.8, 0.06, 0.82), (0, 0.8, 0.12), roof, 0.03)
    m.rbox((0.72, 0.03, 0.74), (0, 0.84, 0.12), roof, 0.03)
    # headlights with chrome rims, tail lights, bumpers
    for sx in (-1, 1):
        m.torus(0.06, 0.012, (sx * 0.19, 0.06, -0.55), grey, rot=(90, 0, 0), seg=18, tube=6)
        m.sphere(0.055, (sx * 0.19, 0.06, -0.55), m.mat("lamp", (1.0, 0.95, 0.6), 0.3, emissive=(1.0, 0.9, 0.4), emit_strength=0.5), scale=(1, 1, 0.5), seg=14, rings=8)
        m.rbox((0.1, 0.05, 0.02), (sx * 0.22, 0.0, 0.535), m.mat("taillight", (0.9, 0.1, 0.08), 0.3, emissive=(0.8, 0.05, 0.05), emit_strength=0.4), 0.008)
    m.rbox((0.58, 0.06, 0.06), (0, -0.2, -0.6), grey, 0.025)
    m.rbox((0.58, 0.06, 0.06), (0, -0.2, 0.58), grey, 0.025)
    # wheels: chunky tyres with tread blocks, white hubs, mudguards
    for x in (-0.38, 0.38):
        for z in (-0.36, 0.36):
            m.cyl(0.125, 0.125, 0.11, (x, -0.18, z), blk, rot=(0, 0, 90), seg=24)
            for k in range(12):
                a = k * math.tau / 12
                m.box((0.12, 0.03, 0.02), (x, -0.18 + math.cos(a) * 0.125, z + math.sin(a) * 0.125), blk, rot=(-math.degrees(a), 0, 0))
            m.cyl(0.07, 0.07, 0.115, (x, -0.18, z), white, rot=(0, 0, 90), seg=16)
            m.cyl(0.025, 0.025, 0.12, (x, -0.18, z), orange, rot=(0, 0, 90), seg=10)
            m.sphere(0.17, (x * 0.97, -0.13, z), body_dk, scale=(0.4, 0.45, 1.0), seg=18, rings=8)   # mudguard
    return m


# ======================================================================= cars
import cars  # noqa: E402
for _cn in cars.CAR_SPECS:
    reg(_cn, cars.car(new, _cn))
reg("package", cars.package(new))


# =================================================================== main
def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    total = 0
    for name, fn in MODELS.items():
        if only and name not in only:
            continue
        m = fn()
        m.name = name
        path = os.path.join(OUT, name + ".glb")
        m.save(path)
        v, t, nodes = validate(path)
        total += os.path.getsize(path)
        print("%-16s %6d verts %6d tris %6.1f KB  nodes=%s" % (name, v, t, os.path.getsize(path) / 1024, nodes))
    print("total %.0f KB, %d models" % (total / 1024, len(MODELS)))


if __name__ == "__main__":
    main()
