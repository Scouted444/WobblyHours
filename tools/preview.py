"""Quick software preview of .glb models -> PNG contact sheet (painter's algorithm, flat shading).
python3 tools/preview.py out.png model1 model2 ..."""
import json, struct, sys, os
import numpy as np
from PIL import Image, ImageDraw

def load(path):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    doc = json.loads(d[20:20 + jl]); off = 20 + jl
    blob = d[off + 8:]
    tris = []
    for m in doc["meshes"]:
        for p in m["primitives"]:
            pa = doc["accessors"][p["attributes"]["POSITION"]]; ia = doc["accessors"][p["indices"]]
            pv = doc["bufferViews"][pa["bufferView"]]; iv = doc["bufferViews"][ia["bufferView"]]
            pos = np.frombuffer(blob, np.float32, pa["count"] * 3, pv["byteOffset"]).reshape(-1, 3)
            idx = np.frombuffer(blob, np.uint32, ia["count"], iv["byteOffset"]).reshape(-1, 3)
            mat = doc["materials"][p["material"]]
            col = np.array(mat["pbrMetallicRoughness"]["baseColorFactor"][:3])
            em = np.array(mat.get("emissiveFactor", [0, 0, 0]))
            tris.append((pos[idx], col, em))
    return tris

def render(path, size=360, yaw=28, pitch=22):
    tris = load(path)
    allp = np.concatenate([t[0].reshape(-1, 3) for t in tris])
    c = (allp.min(0) + allp.max(0)) / 2; ext = (allp.max(0) - allp.min(0)).max()
    a, b = np.radians(yaw), np.radians(pitch)
    # camera looks from -Z (front), rotated by yaw/pitch
    ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    rx = np.array([[1, 0, 0], [0, np.cos(b), -np.sin(b)], [0, np.sin(b), np.cos(b)]])
    R = rx @ ry
    polys = []
    L = np.array([-0.4, 0.8, -0.5]); L /= np.linalg.norm(L)
    for v, col, em in tris:
        w = (v - c)
        n = np.cross(w[:, 1] - w[:, 0], w[:, 2] - w[:, 0]); ln = np.linalg.norm(n, axis=1, keepdims=True); n = n / np.where(ln == 0, 1, ln)
        cam = w @ R.T  # camera space: looking toward +Z, x right, y up
        nc = n @ R.T
        for i in range(len(v)):
            if nc[i, 2] > 0.0:  # facing away from viewer (camera looks +z): back-face
                continue
            sh = 0.35 + 0.65 * max(0, float(n[i] @ L))
            rgb = np.clip(col * sh + em * 0.6, 0, 1)
            polys.append((cam[i, :, 2].mean(), cam[i], rgb))
    polys.sort(key=lambda p: -p[0])
    img = Image.new("RGB", (size, size), (225, 228, 235)); dr = ImageDraw.Draw(img)
    s = size * 0.8 / ext
    for _, q, rgb in polys:
        pts = [(size / 2 + p[0] * s, size / 2 - p[1] * s) for p in q]
        dr.polygon(pts, fill=tuple(int(x * 255) for x in rgb))
    return img

if __name__ == "__main__":
    out = sys.argv[1]; names = sys.argv[2:]
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")
    cols = min(4, len(names)); rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 360, rows * 360))
    for i, n in enumerate(names):
        sheet.paste(render(os.path.join(base, n + ".glb")), ((i % cols) * 360, (i // cols) * 360))
    sheet.save(out)
