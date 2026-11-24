"""Full-size cars for the town and the delivery package (imported by make_models.py).

Origin = centre of the physics box (prop.gd CARS), front at -Z, tyres touch y = -H/2.
Material "paint" is repainted in the game (random colours); "glass" is see-through so you can
see who is driving. The driver sits on the left (x < 0).
"""
import math

CAR_SPECS = {
    #          W     H     L    wheel  clear  belt  roof  ws_z   rw_z   paint
    "sedan":  (1.84, 1.45, 4.5, 0.34, 0.16, 0.86, 1.42, -0.55, 1.05, (0.25, 0.42, 0.75)),
    "taxi":   (1.84, 1.45, 4.5, 0.34, 0.16, 0.86, 1.42, -0.55, 1.05, (1.0, 0.78, 0.08)),
    "police": (1.84, 1.45, 4.6, 0.34, 0.16, 0.86, 1.42, -0.55, 1.05, (0.96, 0.96, 0.97)),
    "sports": (1.92, 1.18, 4.4, 0.33, 0.12, 0.72, 1.16, -0.25, 0.95, (0.9, 0.1, 0.08)),
    "truck":  (2.0, 1.85, 5.3, 0.42, 0.26, 1.12, 1.84, -1.0, 0.25, (0.3, 0.5, 0.3)),
}


def car(new, name):
    W, H, L, wr, clear, belt, roof_y, ws_z, rw_z, paint_c = CAR_SPECS[name]

    def f():
        m = new(name)
        y0 = -H / 2.0
        hw = W / 2.0
        truck = name == "truck"
        sports = name == "sports"
        paint = m.mat("paint", paint_c, 0.3, 0.2)
        trim = m.mat("trim_black", (0.06, 0.06, 0.07), 0.6)
        chrome = m.mat("chrome", (0.85, 0.86, 0.9), 0.2, 0.9)
        tire = m.mat("tire", (0.06, 0.06, 0.07), 0.9)
        rim = m.mat("rim", (0.75, 0.76, 0.8), 0.3, 0.8)
        glass = m.mat("glass", (0.35, 0.45, 0.55, 0.35), 0.05)
        seat = m.mat("seat", (0.14, 0.14, 0.16), 0.85)
        dash = m.mat("dash_plastic", (0.1, 0.1, 0.11), 0.7)
        head = m.mat("headlamp", (1.0, 0.97, 0.85), 0.2, emissive=(1.0, 0.95, 0.8), emit_strength=0.6)
        tail = m.mat("taillamp", (0.85, 0.05, 0.05), 0.3, emissive=(0.9, 0.05, 0.05), emit_strength=0.5)
        plate = m.mat("plate", (0.95, 0.95, 0.9), 0.5, tex=None)
        body_lo = y0 + clear
        belt_y = y0 + belt
        nose = -L / 2.0
        # lower body
        m.rbox((W, belt_y - body_lo, L), (0, (body_lo + belt_y) / 2.0, 0), paint, 0.12)
        if not truck:   # bonnet bulge, lower at the nose
            hood = m.mat("police_black", (0.05, 0.05, 0.07), 0.35, 0.2) if name == "police" else paint
            m.prism([(belt_y - 0.03, nose + 0.12), (belt_y + 0.05, ws_z - 0.15), (belt_y - 0.03, ws_z - 0.15)],
                    -hw + 0.08, hw - 0.08, (0, 0, 0), hood, rot=(0, 0, 90))
        # glass greenhouse + painted roof
        top_y = y0 + roof_y - 0.05
        if truck:
            zf_b, zf_t, zb_t, zb_b = ws_z, ws_z + 0.35, rw_z - 0.05, rw_z
        elif sports:
            zf_b, zf_t, zb_t, zb_b = ws_z, ws_z + 0.75, rw_z - 0.6, rw_z + 0.5
        else:
            zf_b, zf_t, zb_t, zb_b = ws_z, ws_z + 0.62, rw_z - 0.45, rw_z + 0.3
        inset = 0.1
        m.prism([(belt_y, zf_b), (top_y, zf_t), (top_y, zb_t), (belt_y, zb_b)],
                -hw + inset, hw - inset, (0, 0, 0), glass, rot=(0, 0, 90))
        m.rbox((W - 2 * inset + 0.02, 0.07, zb_t - zf_t + 0.08), (0, top_y + 0.02, (zf_t + zb_t) / 2.0), paint, 0.03)
        mid = (zf_t + zb_t) / 2.0 + 0.05
        for sx in (-1, 1):
            x = sx * (hw - inset - 0.01)
            for (zb, zt) in ((zf_b, zf_t), (zb_b, zb_t)):
                ln = math.hypot(zt - zb, top_y - belt_y)
                ang = math.degrees(math.atan2(zt - zb, top_y - belt_y))
                m.box((0.05, ln, 0.07), (x, (belt_y + top_y) / 2.0, (zb + zt) / 2.0), paint, rot=(ang, 0, 0))
            if not sports:
                m.box((0.05, top_y - belt_y, 0.09), (x, (belt_y + top_y) / 2.0, mid), paint)
            dh = belt_y - body_lo - 0.12
            m.box((0.01, dh, 0.012), (sx * (hw + 0.002), (body_lo + belt_y) / 2.0 + 0.04, mid), trim)
            m.box((0.01, dh, 0.012), (sx * (hw + 0.002), (body_lo + belt_y) / 2.0 + 0.04, zf_b - 0.05), trim)
            m.rbox((0.03, 0.035, 0.14), (sx * (hw + 0.01), belt_y - 0.12, mid - 0.25), chrome, 0.012)
            m.rbox((0.16, 0.1, 0.06), (sx * (hw + 0.08), belt_y + 0.08, zf_b + 0.12), paint, 0.03)
            m.box((0.012, 0.075, 0.045), (sx * (hw + 0.165), belt_y + 0.08, zf_b + 0.12), m.mat("mirror_glass", (0.7, 0.8, 0.9), 0.05, 0.8))
            m.box((0.012, 0.05, L * 0.8), (sx * (hw + 0.004), body_lo + 0.12, 0), trim)
        if truck:   # open bed behind the cab, roll bar
            z0, z1 = rw_z + 0.15, L / 2.0 - 0.05
            m.box((W - 0.06, 0.06, z1 - z0), (0, belt_y - 0.35, (z0 + z1) / 2), m.mat("bed_liner", (0.15, 0.15, 0.16), 0.9))
            for sx in (-1, 1):
                m.rbox((0.07, 0.5, z1 - z0), (sx * (hw - 0.035), belt_y - 0.1, (z0 + z1) / 2), paint, 0.03)
                m.cyl(0.035, 0.035, 0.5, (sx * (hw - 0.15), belt_y + 0.25, z0 + 0.1), chrome, seg=10)
            m.rbox((W - 0.06, 0.5, 0.07), (0, belt_y - 0.1, z1), paint, 0.03)
            m.cyl(0.035, 0.035, W - 0.3, (0, belt_y + 0.5, z0 + 0.1), chrome, rot=(0, 0, 90), seg=10)
        if sports:  # wing and side intakes
            for sx in (-1, 1):
                m.box((0.05, 0.16, 0.08), (sx * 0.55, belt_y + 0.06, L / 2.0 - 0.3), trim)
                m.box((0.02, 0.14, 0.5), (sx * (hw + 0.005), body_lo + 0.3, 0.9), trim)
            m.rbox((W - 0.2, 0.04, 0.3), (0, belt_y + 0.16, L / 2.0 - 0.28), paint, 0.015, rot=(-8, 0, 0))
        # wheels
        for sx in (-1, 1):
            for z in (nose + 0.85 + (0.1 if truck else 0.0), L / 2.0 - 0.8):
                x = sx * (hw - 0.14)
                wy = y0 + wr
                m.cyl(wr + 0.05, wr + 0.05, 0.05, (sx * (hw - 0.005), wy + 0.03, z), trim, rot=(0, 0, 90), seg=20)
                m.cyl(wr, wr, 0.26, (x, wy, z), tire, rot=(0, 0, 90), seg=24)
                m.cyl(wr * 0.62, wr * 0.62, 0.27, (x, wy, z), rim, rot=(0, 0, 90), seg=20)
                for k in range(5):
                    m.box((0.02, wr * 0.95, 0.05), (x + sx * 0.136, wy, z), rim, rot=(k * 72.0, 0, 0))
                m.cyl(0.05, 0.05, 0.28, (x, wy, z), chrome, rot=(0, 0, 90), seg=10)
        # front and back
        m.rbox((W - 0.1, 0.18, 0.14), (0, body_lo + 0.05, nose + 0.04), chrome if name == "police" else trim, 0.05)
        m.box((W * 0.45, (belt - clear) * 0.3, 0.03), (0, belt_y - 0.2, nose - 0.005), m.mat("grille", (0.08, 0.08, 0.09), 0.5))
        for k in range(4):
            m.box((W * 0.45, 0.012, 0.035), (0, belt_y - 0.27 + k * 0.05, nose - 0.01), chrome)
        for sx in (-1, 1):
            m.rbox((0.32, 0.12, 0.05), (sx * (hw - 0.3), belt_y - 0.14, nose), head, 0.03)
            m.rbox((0.3, 0.12, 0.05), (sx * (hw - 0.28), belt_y - 0.16, L / 2.0 - 0.01), tail, 0.03)
        m.box((0.36, 0.12, 0.02), (0, body_lo + 0.1, nose - 0.04), plate)
        m.box((0.36, 0.12, 0.02), (0, body_lo + 0.12, L / 2.0 + 0.03), plate)
        m.rbox((W - 0.1, 0.16, 0.12), (0, body_lo + 0.05, L / 2.0 - 0.01), trim, 0.05)
        # interior
        seat_y = body_lo + 0.34
        fz = zf_b + 0.8
        for sx in (-1, 1):
            m.rbox((0.5, 0.14, 0.5), (sx * 0.4, seat_y, fz), seat, 0.05)
            m.rbox((0.48, 0.62, 0.12), (sx * 0.4, seat_y + 0.35, fz + 0.3), seat, 0.05, rot=(-12, 0, 0))
            m.rbox((0.26, 0.16, 0.1), (sx * 0.4, seat_y + 0.74, fz + 0.36), seat, 0.04)
        if not (truck or sports):
            m.rbox((W - 0.4, 0.14, 0.45), (0, seat_y, fz + 0.62), seat, 0.05)
            m.rbox((W - 0.4, 0.5, 0.12), (0, seat_y + 0.3, fz + 0.86), seat, 0.05, rot=(-10, 0, 0))
        m.rbox((W - 0.25, 0.22, 0.3), (0, belt_y - 0.02, zf_b + 0.12), dash, 0.05)
        m.cyl(0.03, 0.03, 0.3, (-0.4, belt_y + 0.02, zf_b + 0.3), dash, rot=(60, 0, 0), seg=8)
        m.torus(0.17, 0.022, (-0.4, belt_y + 0.1, zf_b + 0.42), dash, rot=(65, 0, 0), seg=24, tube=6)
        if name == "taxi":
            m.rbox((0.6, 0.18, 0.26), (0, top_y + 0.15, (zf_t + zb_t) / 2.0),
                   m.mat("taxi_sign", (1.0, 0.95, 0.6), 0.3, emissive=(1.0, 0.9, 0.4), emit_strength=0.7), 0.04)
            chk = m.mat("checker_black", (0.05, 0.05, 0.05), 0.5, tex=None)
            for sx in (-1, 1):
                i = 0
                while True:
                    z = nose + 0.6 + i * 0.25
                    if z > L / 2.0 - 0.6:
                        break
                    for row in range(2):
                        if (i + row) % 2 == 0:
                            m.box((0.012, 0.06, 0.125), (sx * (hw + 0.006), belt_y - 0.3 + row * 0.06, z), chk)
                    i += 1
        if name == "police":
            blk = m.mat("police_black", (0.05, 0.05, 0.07), 0.35, 0.2)
            for sx in (-1, 1):   # blue stripe and black sills along the sides
                m.box((0.012, 0.1, L * 0.9), (sx * (hw + 0.006), belt_y - 0.22, 0), m.mat("police_blue", (0.1, 0.25, 0.8), 0.4, tex=None))
                m.box((0.012, 0.16, L * 0.86), (sx * (hw + 0.006), body_lo + 0.1, 0), blk)
            m.rbox((1.1, 0.08, 0.24), (0, top_y + 0.09, (zf_t + zb_t) / 2.0), trim, 0.03)
            m.node("SirenR")
            m.rbox((0.48, 0.11, 0.2), (-0.28, top_y + 0.17, (zf_t + zb_t) / 2.0),
                   m.mat("siren_red", (1.0, 0.1, 0.1), 0.2, emissive=(1.0, 0.1, 0.1), emit_strength=0.9), 0.04)
            m.node("SirenB")
            m.rbox((0.48, 0.11, 0.2), (0.28, top_y + 0.17, (zf_t + zb_t) / 2.0),
                   m.mat("siren_blue", (0.1, 0.3, 1.0), 0.2, emissive=(0.1, 0.3, 1.0), emit_strength=0.9), 0.04)
            m.node(None)
            m.rbox((W - 0.2, 0.22, 0.12), (0, body_lo + 0.1, nose - 0.08), chrome, 0.04)
        return m
    return f


def package(new):
    def f():
        m = new("package")
        card = m.mat("cardboard", (0.72, 0.55, 0.34), 0.9)
        tape = m.mat("tape", (0.85, 0.75, 0.55), 0.4)
        m.rbox((0.5, 0.36, 0.4), (0, 0, 0), card, 0.015)
        m.box((0.08, 0.005, 0.402), (0, 0.181, 0), tape)
        m.box((0.08, 0.362, 0.005), (0, 0, 0.201), tape)
        m.box((0.08, 0.362, 0.005), (0, 0, -0.201), tape)
        m.box((0.16, 0.1, 0.004), (0.12, 0.05, 0.2025), m.mat("label_paper", (0.97, 0.97, 0.95), 0.6, tex=None))
        return m
    return f
