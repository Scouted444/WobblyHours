"""Tiny GLB (glTF 2.0 binary) writer with mesh primitives. Needs only numpy.

Usage:
    m = Model("sofa")
    red = m.mat("red", (0.8, 0.2, 0.2), rough=0.9)
    m.box((1, 0.5, 1), (0, 0.25, 0), red)
    m.node("Screen")            # following geometry goes into a child node called "Screen"
    m.node(None)                # back to the main body
    m.save("sofa.glb")

Conventions: metres, +Y up, front of a model faces -Z (Godot forward), origin as the caller chooses.
"""
import json
import struct

import numpy as np

import textures


def _rot(rx, ry, rz):
    """Rotation matrix from Euler degrees (applied X, then Y, then Z)."""
    a, b, c = np.radians([rx, ry, rz])
    cx, sx, cy, sy, cz, sz = np.cos(a), np.sin(a), np.cos(b), np.sin(b), np.cos(c), np.sin(c)
    mx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    my = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    mz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return mz @ my @ mx


class Model:
    def __init__(self, name):
        self.name = name
        self.materials = []      # dicts for glTF
        self.mat_index = {}
        self.groups = {None: {}}  # node name -> {mat index: [pos, nrm, idx lists]}
        self.cur = None

    # ------------------------------------------------------------ materials
    def mat(self, name, color, rough=0.8, metal=0.0, emissive=None, emit_strength=1.0, tex="auto"):
        """tex: a texture kind from textures.py, None for a plain colour, "auto" = pick from the name."""
        if tex == "auto":
            tex = textures.kind_for(name, emissive)
        key = (name, tuple(color), rough, metal, emissive, tex)
        if key in self.mat_index:
            return self.mat_index[key]
        rgba = list(color) + [1.0] if len(color) == 3 else list(color)
        m = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [float(x) for x in rgba],
                "metallicFactor": float(metal),
                "roughnessFactor": float(rough),
            },
        }
        if emissive is not None:
            m["emissiveFactor"] = [float(min(1.0, x * emit_strength)) for x in emissive]
        if rgba[3] < 1.0:
            m["alphaMode"] = "BLEND"
        m["doubleSided"] = True
        if tex:
            m["_tex"] = tex
        self.materials.append(m)
        self.mat_index[key] = len(self.materials) - 1
        return self.mat_index[key]

    def node(self, name):
        self.cur = name
        self.groups.setdefault(name, {})

    # ------------------------------------------------------------ geometry
    def _add(self, mat, pos, nrm, idx, rot, at, scale=None):
        pos = np.asarray(pos, dtype=np.float64)
        nrm = np.asarray(nrm, dtype=np.float64)
        if scale is not None:
            pos = pos * np.asarray(scale)
            inv = 1.0 / np.asarray(scale)
            nrm = nrm * inv
            n = np.linalg.norm(nrm, axis=1, keepdims=True)
            nrm = nrm / np.where(n == 0, 1, n)
        r = _rot(*rot)
        pos = pos @ r.T + np.asarray(at)
        nrm = nrm @ r.T
        g = self.groups[self.cur].setdefault(mat, [[], [], []])
        base = sum(len(p) for p in g[0])
        g[0].append(pos)
        g[1].append(nrm)
        g[2].append(np.asarray(idx, dtype=np.uint32) + base)

    def box(self, size, at, mat, rot=(0, 0, 0)):
        self.rbox(size, at, mat, 0.0, rot)

    def rbox(self, size, at, mat, radius=0.02, rot=(0, 0, 0), n=3):
        """Box with rounded edges (radius 0 gives a sharp box)."""
        hx, hy, hz = [s / 2.0 for s in size]
        radius = min(radius, hx, hy, hz)
        P, N, I = [], [], []
        faces = [
            (np.array([1, 0, 0]), np.array([0, 1, 0]), np.array([0, 0, 1])),
            (np.array([-1, 0, 0]), np.array([0, 1, 0]), np.array([0, 0, -1])),
            (np.array([0, 1, 0]), np.array([0, 0, 1]), np.array([1, 0, 0])),
            (np.array([0, -1, 0]), np.array([0, 0, -1]), np.array([1, 0, 0])),
            (np.array([0, 0, 1]), np.array([1, 0, 0]), np.array([0, 1, 0])),
            (np.array([0, 0, -1]), np.array([-1, 0, 0]), np.array([0, 1, 0])),
        ]
        half = np.array([hx, hy, hz])
        seg = n if radius > 0 else 1
        for normal, u, v in faces:
            base = len(P)
            for i in range(seg + 1):
                for j in range(seg + 1):
                    s = i / seg * 2 - 1
                    t = j / seg * 2 - 1
                    p = normal * half + u * half * s + v * half * t
                    if radius > 0:
                        inner = np.clip(p, -(half - radius), half - radius)
                        d = p - inner
                        ln = np.linalg.norm(d)
                        nn = d / ln if ln > 1e-9 else normal
                        p = inner + nn * radius
                        P.append(p)
                        N.append(nn)
                    else:
                        P.append(p)
                        N.append(normal)
            for i in range(seg):
                for j in range(seg):
                    a = base + i * (seg + 1) + j
                    b = a + 1
                    c = a + seg + 1
                    d = c + 1
                    # make winding counter-clockwise seen from outside
                    if np.dot(np.cross(u, v), normal) > 0:
                        I += [a, c, b, b, c, d]
                    else:
                        I += [a, b, c, b, d, c]
        I = _fix_winding(P, N, I)
        self._add(mat, P, N, I, rot, at)

    def cyl(self, r_top, r_bot, h, at, mat, rot=(0, 0, 0), seg=20, caps=True, scale=None):
        """Cylinder / cone frustum along Y, centred on `at`."""
        P, N, I = [], [], []
        slope = (r_bot - r_top) / h if h else 0.0
        for k in range(seg + 1):
            a = 2 * np.pi * k / seg
            ca, sa = np.cos(a), np.sin(a)
            nn = np.array([ca, slope, sa])
            nn = nn / np.linalg.norm(nn)
            P.append([r_top * ca, h / 2, r_top * sa])
            N.append(nn)
            P.append([r_bot * ca, -h / 2, r_bot * sa])
            N.append(nn)
        for k in range(seg):
            a = 2 * k
            I += [a, a + 1, a + 2, a + 2, a + 1, a + 3]
        # winding: verify outward by flipping if needed (ccw seen from outside for +x normal)
        I = _fix_winding(P, N, I)
        if caps:
            for top, r in ((True, r_top), (False, r_bot)):
                if r <= 1e-6:
                    continue
                y = h / 2 if top else -h / 2
                base = len(P)
                P.append([0, y, 0])
                N.append([0, 1 if top else -1, 0])
                for k in range(seg + 1):
                    a = 2 * np.pi * k / seg
                    P.append([r * np.cos(a), y, r * np.sin(a)])
                    N.append([0, 1 if top else -1, 0])
                for k in range(seg):
                    if top:
                        I += [base, base + k + 2, base + k + 1]
                    else:
                        I += [base, base + k + 1, base + k + 2]
        I = _fix_winding(P, N, I)
        self._add(mat, P, N, I, rot, at, scale)

    def sphere(self, r, at, mat, scale=(1, 1, 1), rot=(0, 0, 0), seg=20, rings=12, flat=False):
        P, N, I = [], [], []
        for i in range(rings + 1):
            th = np.pi * i / rings
            for k in range(seg + 1):
                ph = 2 * np.pi * k / seg
                n = [np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)]
                P.append([r * x for x in n])
                N.append(n)
        for i in range(rings):
            for k in range(seg):
                a = i * (seg + 1) + k
                b = a + seg + 1
                I += [a, a + 1, b, a + 1, b + 1, b]
        I = _fix_winding(P, N, I)
        if flat:
            P, N, I = _flatten(P, I)
        self._add(mat, P, N, I, rot, at, scale)

    def torus(self, R, r, at, mat, rot=(0, 0, 0), seg=24, tube=10):
        """Ring in the XZ plane (axis = Y)."""
        P, N, I = [], [], []
        for i in range(seg + 1):
            a = 2 * np.pi * i / seg
            for j in range(tube + 1):
                b = 2 * np.pi * j / tube
                c = np.array([np.cos(a) * R, 0, np.sin(a) * R])
                n = np.array([np.cos(a) * np.cos(b), np.sin(b), np.sin(a) * np.cos(b)])
                P.append(c + n * r)
                N.append(n)
        for i in range(seg):
            for j in range(tube):
                a = i * (tube + 1) + j
                b = a + tube + 1
                I += [a, a + 1, b, a + 1, b + 1, b]
        I = _fix_winding(P, N, I)
        self._add(mat, P, N, I, rot, at)

    def lathe(self, profile, at, mat, rot=(0, 0, 0), seg=24):
        """Surface of revolution about Y. profile = [(radius, y), ...] from bottom to top."""
        P, N, I = [], [], []
        pts = np.array(profile, dtype=float)
        # per-point 2D normals from neighbours
        nrm2 = []
        for i in range(len(pts)):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            t = b - a
            n = np.array([t[1], -t[0]])
            ln = np.linalg.norm(n)
            nrm2.append(n / ln if ln else np.array([1.0, 0.0]))
        for k in range(seg + 1):
            ph = 2 * np.pi * k / seg
            c, s = np.cos(ph), np.sin(ph)
            for (rad, y), n2 in zip(pts, nrm2):
                P.append([rad * c, y, rad * s])
                N.append([n2[0] * c, n2[1], n2[0] * s])
        m = len(pts)
        for k in range(seg):
            for i in range(m - 1):
                a = k * m + i
                b = a + m
                I += [a, a + 1, b, a + 1, b + 1, b]
        I = _fix_winding(P, N, I)
        self._add(mat, P, N, I, rot, at)

    def prism(self, pts2d, y0, y1, at, mat, rot=(0, 0, 0)):
        """Extrude a convex polygon (list of (x, z), counter-clockwise from above) from y0 to y1."""
        P, N, I = [], [], []
        n = len(pts2d)
        # caps (fan)
        for y, up in ((y1, 1), (y0, -1)):
            base = len(P)
            for x, z in pts2d:
                P.append([x, y, z])
                N.append([0, up, 0])
            for i in range(1, n - 1):
                I += [base, base + i, base + i + 1] if up < 0 else [base, base + i + 1, base + i]
        # sides
        for i in range(n):
            x0, z0 = pts2d[i]
            x1, z1 = pts2d[(i + 1) % n]
            e = np.array([x1 - x0, 0, z1 - z0])
            nn = np.cross(e, [0, 1, 0])
            ln = np.linalg.norm(nn)
            nn = nn / ln if ln else nn
            base = len(P)
            P += [[x0, y0, z0], [x1, y0, z1], [x1, y1, z1], [x0, y1, z0]]
            N += [nn] * 4
            I += [base, base + 1, base + 2, base, base + 2, base + 3]
        I = _fix_winding(P, N, I)
        self._add(mat, P, N, I, rot, at)

    # ------------------------------------------------------------ output
    def save(self, path):
        bin_data = bytearray()
        buffer_views, accessors, meshes, nodes = [], [], [], []
        children = []

        def add_view(arr, target):
            while len(bin_data) % 4:
                bin_data.append(0)
            off = len(bin_data)
            bin_data.extend(arr.tobytes())
            buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes, "target": target})
            return len(buffer_views) - 1

        images, tex_of = [], {}
        mats_out = []
        for m in self.materials:
            m = dict(m)
            kind = m.pop("_tex", None)
            if kind:
                if kind not in tex_of:
                    data = np.frombuffer(textures.png(kind), dtype=np.uint8)
                    while len(bin_data) % 4:
                        bin_data.append(0)
                    off = len(bin_data)
                    bin_data.extend(data.tobytes())
                    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
                    images.append({"bufferView": len(buffer_views) - 1, "mimeType": "image/png", "name": kind})
                    tex_of[kind] = len(images) - 1
                m["pbrMetallicRoughness"] = dict(m["pbrMetallicRoughness"])
                m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex_of[kind]}
            mats_out.append((m, kind))

        for gname, mats in self.groups.items():
            prims = []
            for mi, (ps, ns, ids) in mats.items():
                if not ps:
                    continue
                pos = np.concatenate(ps).astype(np.float32)
                nrm = np.concatenate(ns).astype(np.float32)
                nl = np.linalg.norm(nrm, axis=1, keepdims=True)
                nrm = (nrm / np.where(nl == 0, 1, nl)).astype(np.float32)
                idx = np.concatenate(ids).astype(np.uint32)
                v = add_view(pos, 34962)
                accessors.append({"bufferView": v, "componentType": 5126, "count": len(pos), "type": "VEC3",
                                  "min": [float(x) for x in pos.min(0)], "max": [float(x) for x in pos.max(0)]})
                a_pos = len(accessors) - 1
                v = add_view(nrm, 34962)
                accessors.append({"bufferView": v, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
                a_nrm = len(accessors) - 1
                v = add_view(idx, 34963)
                accessors.append({"bufferView": v, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
                a_idx = len(accessors) - 1
                attrs = {"POSITION": a_pos, "NORMAL": a_nrm}
                kind = mats_out[mi][1]
                if kind:
                    uv = _box_uv(pos, nrm, textures.SCALE[kind]).astype(np.float32)
                    v = add_view(uv, 34962)
                    accessors.append({"bufferView": v, "componentType": 5126, "count": len(uv), "type": "VEC2"})
                    attrs["TEXCOORD_0"] = len(accessors) - 1
                prims.append({"attributes": attrs, "indices": a_idx, "material": mi})
            if not prims:
                continue
            meshes.append({"name": gname or self.name, "primitives": prims})
            nodes.append({"name": gname or (self.name + "_body"), "mesh": len(meshes) - 1})
            children.append(len(nodes) - 1)
        root = {"name": self.name, "children": children}
        nodes.append(root)
        doc = {
            "asset": {"version": "2.0", "generator": "wobbly_hours tools/glb.py"},
            "scene": 0,
            "scenes": [{"nodes": [len(nodes) - 1]}],
            "nodes": nodes,
            "meshes": meshes,
            "materials": [m for m, _ in mats_out],
            "accessors": accessors,
            "bufferViews": buffer_views,
            "buffers": [{"byteLength": len(bin_data)}],
        }
        if images:
            doc["images"] = images
            doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
            doc["textures"] = [{"source": i, "sampler": 0} for i in range(len(images))]
        js = json.dumps(doc, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        bd = bytes(bin_data) + b"\0" * ((4 - len(bin_data) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(bd)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<I4s", len(js), b"JSON"))
            f.write(js)
            f.write(struct.pack("<I4s", len(bd), b"BIN\0"))
            f.write(bd)


def _box_uv(pos, nrm, scale):
    """Box-projected UVs: each vertex is mapped on the plane its normal faces most, one repeat per `scale` metres."""
    a = np.abs(nrm)
    ax = np.argmax(a, axis=1)
    u = np.where(ax == 0, pos[:, 2], pos[:, 0])
    v = np.where(ax == 1, pos[:, 2], pos[:, 1])
    return np.stack([u / scale, -v / scale], axis=1)


def _fix_winding(P, N, I):
    """Flip triangles whose geometric normal disagrees with the vertex normals."""
    P = np.asarray(P, dtype=float)
    N = np.asarray(N, dtype=float)
    I = np.asarray(I, dtype=np.uint32).reshape(-1, 3)
    a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
    face = np.cross(b - a, c - a)
    avg = N[I[:, 0]] + N[I[:, 1]] + N[I[:, 2]]
    flip = np.einsum("ij,ij->i", face, avg) < 0
    I[flip] = I[flip][:, [0, 2, 1]]
    return I.reshape(-1).tolist()


def validate(path):
    """Re-read a GLB and check structure. Returns (vertex count, triangle count, node names)."""
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, total = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and ver == 2 and total == len(data), "bad header"
    jl, jt = struct.unpack_from("<I4s", data, 12)
    assert jt == b"JSON"
    doc = json.loads(data[20:20 + jl])
    off = 20 + jl
    bl, bt = struct.unpack_from("<I4s", data, off)
    assert bt == b"BIN\0" and bl % 4 == 0 and jl % 4 == 0
    blob = data[off + 8:off + 8 + bl]
    verts = tris = 0
    for m in doc["meshes"]:
        for p in m["primitives"]:
            pa = doc["accessors"][p["attributes"]["POSITION"]]
            ia = doc["accessors"][p["indices"]]
            bv = doc["bufferViews"][ia["bufferView"]]
            idx = np.frombuffer(blob, dtype=np.uint32, count=ia["count"], offset=bv["byteOffset"])
            assert idx.max() < pa["count"], "index out of range"
            assert ia["count"] % 3 == 0
            pv = doc["bufferViews"][pa["bufferView"]]
            pos = np.frombuffer(blob, dtype=np.float32, count=pa["count"] * 3, offset=pv["byteOffset"]).reshape(-1, 3)
            assert np.isfinite(pos).all(), "NaN positions"
            assert np.allclose(pos.min(0), pa["min"], atol=1e-4)
            verts += pa["count"]
            tris += ia["count"] // 3
            assert 0 <= p["material"] < len(doc["materials"])
    return verts, tris, [n["name"] for n in doc["nodes"]]


def _flatten(P, I):
    """Un-share vertices so every triangle gets its own face normal (faceted look)."""
    P = np.asarray(P, dtype=float)
    I = np.asarray(I, dtype=np.uint32).reshape(-1, 3)
    P2, N2, I2 = [], [], []
    for t in I:
        a, b, c = P[t[0]], P[t[1]], P[t[2]]
        n = np.cross(b - a, c - a)
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            continue
        n = n / ln
        base = len(P2)
        P2 += [a, b, c]
        N2 += [n, n, n]
        I2 += [base, base + 1, base + 2]
    return P2, N2, I2
