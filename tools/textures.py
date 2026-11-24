"""Small tileable grayscale detail textures for the generated models (wood grain, fabric weave, brushed metal...).

They are multiplied with each material's colour, so they only add surface detail; the colour stays the one
given in make_models.py. Every texture tiles seamlessly (built from periodic noise).
"""
import io

import numpy as np
from PIL import Image

N = 256
_cache = {}

# metres covered by one repeat of the texture
SCALE = {"wood": 0.7, "fabric": 0.12, "brushed": 0.35, "leaf": 0.35, "bark": 0.45, "speckle": 0.35,
         "noise": 0.6, "food": 0.15, "rubber": 0.2}


def _noise(seed, cutoff, aniso=(1.0, 1.0)):
    """Periodic smooth noise in 0..1, by low-pass filtering white noise in Fourier space."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((N, N))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(N)[:, None] * N * aniso[1]
    kx = np.fft.fftfreq(N)[None, :] * N * aniso[0]
    k = np.sqrt(kx * kx + ky * ky)
    f *= np.exp(-(k / cutoff) ** 2)
    out = np.real(np.fft.ifft2(f))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def _wood():
    y = np.arange(N)[:, None] / N
    warp = _noise(1, 3.0) * 0.6 + _noise(2, 10.0, (0.25, 1.0)) * 0.15
    rings = 0.5 + 0.5 * np.sin((y * 9.0 + warp * 2.0) * 2 * np.pi)
    streak = _noise(3, 60.0, (1.0, 0.06))            # fine grain running along u
    v = 0.95 - 0.16 * rings ** 6 - 0.12 * (1.0 - streak) + 0.04 * warp
    return v


def _fabric():
    x = np.arange(N)[None, :]
    y = np.arange(N)[:, None]
    weave = 0.5 + 0.25 * np.sin(x * 2 * np.pi / 8) * np.sign(np.sin(y * 2 * np.pi / 16)) \
        + 0.25 * np.sin(y * 2 * np.pi / 8) * np.sign(np.sin(x * 2 * np.pi / 16) + 1e-9)
    fuzz = _noise(4, 60.0)
    blotch = _noise(5, 4.0)
    return 0.78 + 0.12 * weave + 0.06 * fuzz + 0.05 * blotch


def _brushed():
    return 0.78 + 0.2 * _noise(6, 70.0, (1.0, 0.02)) + 0.04 * _noise(7, 5.0)


def _leaf():
    big = _noise(8, 6.0)
    small = _noise(9, 30.0)
    return 0.8 + 0.12 * big + 0.08 * small


def _bark():
    cracks = _noise(11, 35.0, (0.08, 1.0))
    return 0.62 + 0.3 * cracks ** 1.5 + 0.08 * _noise(12, 8.0)


def _speckle():
    rng = np.random.default_rng(13)
    dots = (rng.random((N, N)) > 0.985) * rng.random((N, N))
    return np.clip(0.86 + 0.08 * _noise(14, 12.0) - 0.35 * dots + 0.1 * (rng.random((N, N)) > 0.992), 0, 1)


def _plain():
    return 0.88 + 0.08 * _noise(15, 4.0) + 0.04 * _noise(16, 40.0)


def _food():
    return 0.8 + 0.12 * _noise(17, 18.0) + 0.08 * _noise(18, 60.0)


def _rubber():
    return 0.85 + 0.15 * _noise(19, 80.0)


_MAKERS = {"wood": _wood, "fabric": _fabric, "brushed": _brushed, "leaf": _leaf, "bark": _bark,
           "speckle": _speckle, "noise": _plain, "food": _food, "rubber": _rubber}


def png(kind):
    """PNG bytes of the texture `kind`."""
    if kind not in _cache:
        v = np.clip(_MAKERS[kind](), 0.0, 1.0)
        img = Image.fromarray((v * 255).astype(np.uint8), "L").convert("RGB")
        buf = io.BytesIO()
        img.save(buf, "PNG", optimize=True)
        _cache[kind] = buf.getvalue()
    return _cache[kind]


# material name -> texture kind
_WORDS = [
    ("wood", ["wood", "desk", "deck", "drawer", "cabinet", "board", "post", "frame", "crate", "plank", "grip",
              "bench", "leg", "stock"]),
    ("fabric", ["fabric", "cushion", "seat", "rug", "mat", "plush", "pillow", "sheet", "blanket", "pad", "hat", "coat",
                "shirt", "pants", "canvas", "bean", "towel", "fold", "sofa", "trim"]),
    ("brushed", ["steel", "chrome", "iron", "slide", "rim", "guard", "blade", "tap", "chain", "metal", "silver", "hinge",
                 "rivet", "pommel", "knob", "lid", "ladder", "pole"]),
    ("leaf", ["leaf", "pine", "bush", "hill", "lettuce"]),
    ("bark", ["bark", "stem", "trunk"]),
    ("speckle", ["counter", "top", "stone", "pedestal"]),
    ("food", ["bun", "patty", "crust", "cheese", "rind", "tomato", "melon", "pepperoni", "apple", "seed"]),
    ("rubber", ["tire", "sole", "boot", "bumper", "tape", "foot"]),
]
_NONE = ["screen", "glass", "mirror", "water", "flame", "flash", "glow", "neon", "led", "eye", "lips", "shine", "glint",
         "spark", "ember", "backblast", "skin", "hair", "beard", "lamp", "shade", "vu", "porcelain", "basin", "bowl"]


def kind_for(name, emissive):
    low = name.lower()
    if emissive is not None or any(w in low for w in _NONE):
        return None
    for kind, words in _WORDS:
        if any(w in low for w in words):
            return kind
    return "noise"
