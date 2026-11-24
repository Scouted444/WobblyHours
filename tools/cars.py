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
    "sports": (1.92, 1.26, 4.4, 0.33, 0.12, 0.72, 1.25, -0.25, 0.95, (0.9, 0.1, 0.08)),
    "truck":  (2.0, 1.85, 5.3, 0.42, 0.26, 1.12, 1.84, -1.0, 0.25, (0.3, 0.5, 0.3)),
}
# cabin floor top and seat cushion top, above the ground. A seated adult (character maker model:
# thigh joint 1.0 m up, 0.47 m thigh, 0.47 m shin, head top ~1.78 m) has to fit between them and the roof.
CABIN = {
    "sedan": (0.22, 0.42), "taxi": (0.22, 0.42), "police": (0.22, 0.42),
    "sports": (0.16, 0.28), "truck": (0.40, 0.62),
}


def seat_info(name):
    """Numbers prop.gd needs (printed by `python cars.py`): driver origin, foot and hand targets."""
    W, H, L, wr, clear, belt, roof_y, ws_z, rw_z, _ = CAR_SPECS[name]
    floor_h, seat_h = CABIN[name]
    y0 = -H / 2.0
    fz = ws_z + 0.8
    origin = (-0.4, y0 + seat_h + 0.1 - 1.0, fz + 0.12)
    wheel = (-0.4, y0 + belt + 0.1, ws_z + 0.48)
    return origin, wheel, y0 + floor_h


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
        floor_h, seat_h = CABIN[name]
        floor_y = y0 + floor_h
        cushion_y = y0 + seat_h
        trim_in = m.mat("interior", (0.55, 0.52, 0.48), 0.8, tex=None)
        carpet = m.mat("carpet", (0.12, 0.12, 0.13), 0.95)
        headliner = m.mat("headliner", (0.78, 0.76, 0.72), 0.9, tex=None)
        # lower body: engine bay and boot are solid, the cabin between them is hollow (floor + doors)
        if truck:
            zf_b0, zb_b0 = ws_z, rw_z
        elif sports:
            zf_b0, zb_b0 = ws_z, rw_z + 0.5
        else:
            zf_b0, zb_b0 = ws_z, rw_z + 0.3
        fw = zf_b0 - 0.25                  # firewall: the footwells reach in under the dash
        rear_z = zb_b0                     # back of the cabin
        m.rbox((W, floor_y - body_lo, L), (0, (body_lo + floor_y) / 2.0, 0), paint, min(0.1, (floor_y - body_lo) / 2.0 - 0.005))
        m.rbox((W, belt_y - body_lo, fw - nose), (0, (body_lo + belt_y) / 2.0, (nose + fw) / 2.0), paint, 0.12)
        rear_top = belt_y - 0.38 if truck else belt_y
        m.rbox((W, rear_top - body_lo, L / 2.0 - rear_z), (0, (body_lo + rear_top) / 2.0, (rear_z + L / 2.0) / 2.0), paint, 0.12)
        for sx in (-1, 1):
            m.box((0.07, belt_y - floor_y + 0.02, rear_z - fw + 0.2), (sx * (hw - 0.035), (floor_y + belt_y) / 2.0, (fw + rear_z) / 2.0), paint)
            # door card with armrest and handle (what you see from inside)
            m.box((0.03, belt_y - floor_y - 0.04, rear_z - fw - 0.1), (sx * (hw - 0.085), (floor_y + belt_y) / 2.0, (fw + rear_z) / 2.0), trim_in)
            m.rbox((0.08, 0.05, 0.4), (sx * (hw - 0.13), floor_y + (belt_y - floor_y) * 0.55, fw + 0.85), m.mat("seat", (0.14, 0.14, 0.16), 0.85), 0.02)
            m.box((0.02, 0.03, 0.12), (sx * (hw - 0.105), belt_y - 0.1, fw + 0.55), chrome)
        m.box((W - 0.1, 0.05, zf_b0 - fw + 0.06), (0, belt_y - 0.025, (fw + zf_b0) / 2.0), paint)        # cowl over the dash
        m.box((W - 0.16, 0.02, rear_z - fw), (0, floor_y + 0.01, (fw + rear_z) / 2.0), carpet)            # floor
        m.box((W - 0.16, belt_y - floor_y, 0.03), (0, (floor_y + belt_y) / 2.0, fw + 0.015), carpet)    # firewall
        if truck:   # the cab's back wall (the bed is outside it)
            m.box((W, belt_y - rear_top + 0.02, 0.08), (0, (rear_top + belt_y) / 2.0, rear_z + 0.04), paint)
        m.box((W - 0.16, belt_y - floor_y, 0.03), (0, (floor_y + belt_y) / 2.0, rear_z - 0.015), trim_in)  # back wall
        if not truck:
            m.box((W - 0.16, 0.03, 0.3), (0, belt_y - 0.015, rear_z - 0.15), carpet)                         # parcel shelf
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
        m.box((W - 2 * inset - 0.06, 0.015, zb_t - zf_t - 0.04), (0, top_y - 0.022, (zf_t + zb_t) / 2.0), headliner)
        for vx in (-0.42, 0.42):   # sun visors
            m.box((0.5, 0.02, 0.18), (vx, top_y - 0.045, zf_t + 0.12), headliner, rot=(-15, 0, 0))
        m.box((0.24, 0.07, 0.025), (0, top_y - 0.11, zf_t + 0.16), dash)                                   # rear-view mirror
        m.box((0.2, 0.05, 0.005), (0, top_y - 0.11, zf_t + 0.174), m.mat("mirror_glass", (0.7, 0.8, 0.9), 0.05, 0.8))
        m.box((0.02, 0.06, 0.02), (0, top_y - 0.05, zf_t + 0.16), dash)
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
                if fw - wr < z < rear_z + wr:
                    # wheel arch bulging into the cabin
                    top = wy + wr + 0.05
                    if top > floor_y:
                        m.rbox((0.3, top - floor_y, 2 * wr + 0.12), (sx * (hw - 0.22), (floor_y + top) / 2.0, z), carpet, 0.05)
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
        # interior: seats (on pedestals), dashboard with dials and radio, console, gear stick, pedals, wheel
        fz = zf_b + 0.8
        recline = 22 if sports else 14
        for sx in (-1, 1):
            m.box((0.36, cushion_y - 0.12 - floor_y, 0.36), (sx * 0.4, (floor_y + cushion_y - 0.12) / 2.0, fz), dash)
            m.rbox((0.5, 0.14, 0.52), (sx * 0.4, cushion_y - 0.07, fz), seat, 0.05)
            m.rbox((0.48, 0.64, 0.12), (sx * 0.4, cushion_y + 0.3, fz + 0.32), seat, 0.05, rot=(-recline, 0, 0))
            m.rbox((0.26, 0.16, 0.1), (sx * 0.4, cushion_y + 0.7, fz + 0.32 + 0.4 * math.sin(math.radians(recline))), seat, 0.04)
        if not (truck or sports):
            m.box((W - 0.4, cushion_y - 0.1 - floor_y, 0.4), (0, (floor_y + cushion_y - 0.1) / 2.0, fz + 0.68), dash)
            m.rbox((W - 0.4, 0.14, 0.45), (0, cushion_y - 0.05, fz + 0.68), seat, 0.05)
            m.rbox((W - 0.4, 0.5, 0.12), (0, cushion_y + 0.25, fz + 0.94), seat, 0.05, rot=(-10, 0, 0))
        dash_z = zf_b + 0.1
        m.rbox((W - 0.22, 0.26, 0.42), (0, belt_y - 0.05, dash_z), dash, 0.06)
        dial = m.mat("dial", (0.95, 0.95, 0.9), 0.4, emissive=(0.6, 0.8, 1.0), emit_strength=0.5)
        needle = m.mat("needle", (1.0, 0.3, 0.1), 0.4, emissive=(1.0, 0.3, 0.1), emit_strength=0.8)
        m.box((0.42, 0.15, 0.06), (-0.4, belt_y + 0.07, dash_z + 0.2), m.mat("cluster", (0.05, 0.05, 0.06), 0.5, tex=None))
        for dx in (-0.1, 0.1):
            m.cyl(0.055, 0.055, 0.01, (-0.4 + dx, belt_y + 0.07, dash_z + 0.235), dial, rot=(90, 0, 0), seg=18)
            m.box((0.006, 0.045, 0.006), (-0.4 + dx, belt_y + 0.085, dash_z + 0.243), needle, rot=(0, 0, 35))
        m.box((0.24, 0.13, 0.02), (0, belt_y + 0.0, dash_z + 0.215), m.mat("radio_screen", (0.2, 0.5, 0.9), 0.3, emissive=(0.2, 0.5, 0.9), emit_strength=0.6))
        for vx in (-0.75, 0.15, 0.75):
            m.box((0.12, 0.05, 0.02), (vx if vx != 0.15 else 0.0, belt_y + 0.11, dash_z + 0.215), trim)   # air vents
        m.box((0.01, 0.12, 0.25), (0.42, belt_y - 0.1, dash_z + 0.21), trim, rot=(0, 90, 0))              # glovebox seam
        m.box((0.24, floor_y + 0.0 - floor_y + 0.26, fz - dash_z + 0.1), (0, floor_y + 0.13, (dash_z + fz) / 2.0 + 0.1), dash)  # console
        m.cyl(0.012, 0.012, 0.2, (0, floor_y + 0.36, fz - 0.2), chrome, rot=(-15, 0, 0), seg=8)
        m.sphere(0.035, (0, floor_y + 0.46, fz - 0.23), m.mat("knob", (0.05, 0.05, 0.05), 0.4), seg=10, rings=6)
        for px in (-0.5, -0.33):
            m.box((0.07, 0.1, 0.02), (px, floor_y + 0.1, fw + 0.12), chrome, rot=(-30, 0, 0))
        wz = zf_b + 0.48
        wy = belt_y + 0.1
        m.cyl(0.03, 0.03, 0.4, (-0.4, belt_y + 0.02, (dash_z + wz) / 2.0 + 0.05), dash, rot=(65, 0, 0), seg=8)
        m.torus(0.17, 0.022, (-0.4, wy, wz), dash, rot=(65, 0, 0), seg=24, tube=6)
        m.cyl(0.05, 0.05, 0.05, (-0.4, wy, wz), dash, rot=(65, 0, 0), seg=12)
        for a in (0, 120, 240):
            m.box((0.15, 0.02, 0.02), (-0.4 + 0.075 * math.cos(math.radians(a)), wy + 0.075 * math.sin(math.radians(a)) * 0.42,
                                       wz + 0.075 * math.sin(math.radians(a)) * 0.9), dash, rot=(65, 0, a))
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


if __name__ == "__main__":
    for n in CAR_SPECS:
        o, w, f = seat_info(n)
        print(n, "origin", [round(v, 3) for v in o], "wheel", [round(v, 3) for v in w], "floor", round(f, 3))
