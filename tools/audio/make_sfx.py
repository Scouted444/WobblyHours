"""Builds audio/sfx/*.ogg for Wobbly Hours.

Real recordings come from Kenney's CC0 packs (Impact Sounds, RPG Audio, Sci-Fi Sounds, Interface Sounds,
UI Audio). Sounds that have no good recording (gunshot, splash, burp...) are synthesised here at 44.1 kHz with
proper filters and a touch of room, instead of raw square waves.

    python tools/audio/make_sfx.py <folder with the kenney packs> <output folder>

The kenney folder is searched recursively by file name, so the pack layout doesn't matter.
"""
import os
import sys
import json
from pathlib import Path
import numpy as np
from dsp import (SR, load, save_ogg, db, peak_norm, rms_db, trim, fade, soft_clip, lp, hp, bp, peq,
                 sweep_lp, room, convolve, reverb_ir, shelf_hi)

SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("kenney")
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("audio/sfx")
OUT.mkdir(parents=True, exist_ok=True)
_index = {}
for _root, _dirs, _files in os.walk(SRC, followlinks=True):
    for _f in sorted(_files):
        _p = Path(_root) / _f
        if _p.suffix.lower() in (".ogg", ".wav"):
            _index.setdefault(_p.stem, _p)

counts = {}


def k(name):
    """Load a Kenney recording by file stem."""
    if name not in _index:
        raise SystemExit("missing source sound: " + name)
    return load(_index[name])


def put(kind, x, level_db):
    """Write the next variant of `kind`, levelled by RMS so every sound of a kind sits at the same loudness.
    The peak is always kept under -1 dBFS."""
    x = np.asarray(x, dtype=np.float64)
    x = trim(x, -55.0)
    x = x * db(level_db - rms_db(x))
    pk = np.max(np.abs(x))
    if pk > db(-3.0):   # keep headroom: the Ogg encoder overshoots peaks a little
        x = soft_clip(x / db(-3.0), 1.2) * db(-3.0)
    i = counts.get(kind, 0)
    counts[kind] = i + 1
    save_ogg(OUT / f"{kind}_{i}.ogg", x.astype(np.float32), q=6)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def mix(*parts):
    """Mix (offset_seconds, signal, gain_db) tuples."""
    n = max(int(o * SR) + len(s) for o, s, g in parts)
    out = np.zeros(n)
    for o, s, g in parts:
        i = int(o * SR)
        out[i:i + len(s)] += s * db(g)
    return out


rng = np.random.default_rng(7)

# ============================================================ recorded foley
for surf in ("wood", "concrete", "grass", "carpet"):
    for i in range(5):
        x = k(f"footstep_{surf}_{i:03d}")
        x = hp(x, 70.0)
        put("step_" + surf, x, -20.0)

for i in range(5):  # landing: a body-weight thump plus a scuff
    put("land", mix((0, k(f"impactSoft_heavy_{i:03d}"), 0), (0.01, k(f"footstep_concrete_{i:03d}"), -6)), -17.0)

for name in [f"impactPunch_medium_{i:03d}" for i in range(5)] + [f"impactPunch_heavy_{i:03d}" for i in range(3)]:
    put("thud", k(name), -16.0)

for name in [f"impactGlass_heavy_{i:03d}" for i in range(5)]:
    put("glass", room(k(name), 0.12), -17.0)

for i in range(4):  # car crash: metal crunch + body panel + rattling bits, all real recordings
    parts = [(0, k(f"impactMetal_heavy_{i:03d}"), 0),
             (0.02, k(f"impactPlate_heavy_{(i + 1) % 5:03d}"), -3),
             (0.0, lp(k(f"impactSoft_heavy_{(i + 2) % 5:03d}"), 500), -2)]
    for j in range(4):
        parts.append((0.12 + j * rng.uniform(0.07, 0.14), k(f"impactMetal_light_{(i + j) % 5:03d}"), -10 - j * 2))
        parts.append((0.18 + j * rng.uniform(0.06, 0.12), k(f"impactTin_medium_{(i + j + 1) % 5:03d}"), -14 - j * 2))
    put("crash", room(mix(*parts), 0.1), -15.0)

for name in ["knifeSlice", "knifeSlice2"]:
    put("stab", lp(mix((0, k(name), 0), (0.005, lp(k("impactSoft_medium_000"), 900), -4)), 7500), -18.0)

for name in ["cloth1", "cloth2", "cloth3", "handleSmallLeather", "handleSmallLeather2"]:
    put("pickup", k(name), -22.0)
for name in ["cloth1", "cloth2", "cloth3", "cloth4"]:
    put("jump", hp(k(name), 120), -24.0)
for name in ["handleCoins", "handleCoins2"]:
    put("coins", room(lp(k(name), 8000), 0.1), -21.0)

# interface (Kenney Interface Sounds / UI Audio)
for name in ["click_001", "click_002", "click_003"]:
    put("click", lp(k(name), 9000), -24.0)
for name in ["tick_001", "tick_002"]:
    put("hover", lp(k(name), 7000), -30.0)
for name in ["select_001", "select_002"]:
    put("bleep", k(name), -22.0)

# ============================================================ synthesised sounds


def noise(sec, seed=None):
    r = np.random.default_rng(seed)
    return r.standard_normal(int(sec * SR))


def env_exp(sec, rate, attack=0.001):
    t = t_of(sec)
    return np.minimum(t / attack, 1.0) * np.exp(-t * rate)


def additive(freq_fn, sec, harmonics):
    """Band-limited tone: freq_fn(t) array in Hz, harmonics = [(n, amp), ...]."""
    t = t_of(sec)
    f = freq_fn(t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros_like(t)
    for n, a in harmonics:
        mask = (f * n) < SR * 0.45
        out += a * np.sin(ph * n) * mask
    return out


def fm_bell(freq, sec, ratio=3.5, index=2.5, decay=3.0, idecay=6.0):
    t = t_of(sec)
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * np.exp(-t * idecay)
    return np.sin(2 * np.pi * freq * t + mod) * np.exp(-t * decay) * np.minimum(t / 0.002, 1)


def bandsweep(x, fc_fn, q=2.0, block=128):
    """Time-varying band-pass (block-wise biquad), fc_fn(t_seconds) -> Hz."""
    from scipy import signal
    out = np.zeros_like(x)
    zi = np.zeros(2)
    for s in range(0, len(x), block):
        fc = float(np.clip(fc_fn(s / SR), 40, SR * 0.45))
        w = 2 * np.pi * fc / SR
        al = np.sin(w) / (2 * q)
        b = np.array([al, 0, -al]) / (1 + al)
        a = np.array([1, -2 * np.cos(w) / (1 + al), (1 - al) / (1 + al)])
        seg, zi = signal.lfilter(b, a, x[s:s + block], zi=zi)
        out[s:s + block] = seg
    return out


# --- gunshot: crack + powder body + low thump + outdoor slap-back
for v in range(3):
    r = np.random.default_rng(100 + v)
    crack = hp(noise(0.02, 100 + v), 1500) * env_exp(0.02, 380)
    body = bp(noise(0.35, 200 + v), 180, 3500) * env_exp(0.35, 22 + v * 3)
    f0 = 110 + v * 10
    thump = additive(lambda t: 45 + f0 * np.exp(-t * 35), 0.3, [(1, 1.0), (2, 0.2)]) * env_exp(0.3, 18)
    click = bp(noise(0.012, 300 + v), 2500, 6000) * env_exp(0.012, 500)
    shot = mix((0, click, -6), (0.001, crack, 0), (0.001, body, -2), (0, thump, -1))
    shot = soft_clip(shot / np.max(np.abs(shot)) * 1.6, 1.0)
    echo = lp(shot, 1800) * 0.25
    shot = mix((0, shot, 0), (0.11 + v * 0.02, echo, -4), (0.23 + v * 0.03, lp(echo, 1000), -10))
    shot = room(shot, 0.25, 1.0, 5.0, 3500, seed=v)
    shot = lp(shelf_hi(shot, 5000, -5), 9000)
    put("shot", shot, -13.0)

# --- whoosh (swing / dodge): band-limited air with a sweeping centre
for v in range(4):
    dur = 0.32 + 0.05 * v
    peak = 0.45 + 0.1 * v
    fc = lambda t, d=dur, p=peak: 300 + 1300 * np.sin(np.pi * min(t / d, 1.0)) ** 2 * (1.0 if t / d < p else 0.8)
    x = bandsweep(noise(dur, 400 + v), fc, q=1.4)
    x *= np.sin(np.pi * t_of(dur) / dur) ** 2.2
    put("whoosh", lp(x, 5000), -20.0)
# --- throw: a quick arm whoosh + sleeve rustle
for v, cl in enumerate(["cloth2", "cloth3", "cloth4"]):
    dur = 0.24
    x = bandsweep(noise(dur, 500 + v), lambda t: 500 + 1500 * np.sin(np.pi * min(t / dur, 1.0)), q=1.2)
    x *= np.sin(np.pi * t_of(dur) / dur) ** 1.6
    put("throw", mix((0, lp(x, 5000), 0), (0, hp(k(cl), 200), -8)), -22.0)

# --- splash: impact, a sheet of spray, then a cloud of bubbles and drips
for v in range(3):
    r = np.random.default_rng(600 + v)
    dur = 1.3
    t = t_of(dur)
    impact = lp(noise(0.25, 601 + v), 900) * env_exp(0.25, 14, 0.004)
    spray = sweep_lp(noise(dur, 602 + v), 7000, 900, 0.6) * np.minimum(t / 0.01, 1) * np.exp(-t * 3.8)
    plop = additive(lambda tt: 70 + 90 * np.exp(-tt * 20), 0.25, [(1, 1)]) * env_exp(0.25, 16, 0.003)
    bub = np.zeros(int(dur * SR))
    for b in range(90):
        st = r.exponential(0.25) + 0.03
        if st > dur - 0.1:
            continue
        bd = r.uniform(0.015, 0.06)
        f = r.uniform(350, 1400) if b % 3 else r.uniform(1400, 2600)
        bt = t_of(bd)
        tone = np.sin(2 * np.pi * (f * bt + f * 2.5 * bt * bt / bd * 0.5)) * np.exp(-bt * 60) * np.minimum(bt / 0.002, 1)
        i = int(st * SR)
        bub[i:i + len(tone)] += tone * r.uniform(0.2, 0.6) * np.exp(-st * 2.0)
    x = mix((0, impact, -2), (0, plop, -4), (0.005, spray, 0), (0.02, bub, -9))
    put("splash", x, -15.0)

# --- beach ball pop: sharp burst of air with a rubbery snap
for v in range(2):
    burst = hp(noise(0.25, 700 + v), 300) * env_exp(0.25, 45, 0.0005)
    snap = bp(noise(0.06, 710 + v), 1200, 5000) * env_exp(0.06, 120, 0.0003)
    body = additive(lambda t: 160 + 200 * np.exp(-t * 60), 0.12, [(1, 1)]) * env_exp(0.12, 40)
    put("pop", room(lp(mix((0, snap, 0), (0, burst, -3), (0, body, -6)), 6500), 0.15), -16.0)

# --- boing: a wooden board knock plus a springy, wobbling twang
for v in range(3):
    dur = 0.9
    base = 120 + v * 18
    tw = additive(lambda t: base + 110 * np.exp(-t * 6) + 9 * np.sin(2 * np.pi * 13 * t) * np.exp(-t * 3),
                  dur, [(1, 1.0), (2, 0.25), (3, 0.08)]) * env_exp(dur, 4.0, 0.004)
    knock = k(f"impactPlank_medium_{v:03d}")
    put("boing", room(mix((0, knock, -2), (0.004, tw, -6)), 0.12), -18.0)

# --- toy car horn: rubber-bulb reed, soft and nasal ("meep")
for v in range(2):
    dur = 0.42
    f0 = 410 + v * 40
    reed = additive(lambda t: f0 * (1 - 0.03 * t) + 3 * np.sin(2 * np.pi * 6 * t), dur,
                    [(n, 1.0 / n ** 1.1) for n in range(1, 18)])
    reed = peq(peq(lp(reed, 3200), 900, 6, 2.0), 2100, 3, 2.0)
    e = np.minimum(t_of(dur) / 0.025, 1) * np.minimum((dur - t_of(dur)) / 0.06, 1)
    put("honk", room(reed * e, 0.1), -20.0)

# --- car alarm warble: sine-ish, low-passed and quieter than real alarms (they're meant to hurt; ours isn't)
for v in range(1):
    dur = 0.9
    x = additive(lambda t: 850 + 380 * np.sin(2 * np.pi * 5 * t), dur, [(1, 1.0), (2, 0.18), (3, 0.08)])
    x = lp(x, 2800)
    put("alarm", fade(x, 0.004, 0.004), -24.0)

# --- burp: voiced, with throat formants
for v in range(3):
    r = np.random.default_rng(800 + v)
    dur = 0.55 + 0.1 * v
    t = t_of(dur)
    f0 = (85 - 25 * t / dur) * (1 + 0.04 * r.standard_normal(len(t)).cumsum() / np.sqrt(len(t)) * 3)
    ph = np.cumsum(f0) / SR
    pulses = (np.mod(ph, 1.0) < 0.15).astype(float)  # glottal-ish pulse train
    pulses += noise(dur, 801 + v) * 0.05
    voice = sum(bp(pulses, f * 0.85, f * 1.15) * g for f, g in [(520, 1.0), (850, 0.7), (2300, 0.15)])
    rough = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * (24 + v * 3) * t))
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    put("burp", room(voice * rough * e, 0.12), -18.0)

# --- eating: three crunchy bites
for v in range(2):
    r = np.random.default_rng(900 + v)
    parts = []
    for b in range(3):
        sec = 0.11
        crack = np.zeros(int(sec * SR))
        for _ in range(60):
            i = int(r.exponential(0.02) * SR)
            if i < len(crack):
                crack[i] += r.uniform(-1, 1)
        crunch = bp(crack, 900, 5000) * env_exp(sec, 25)
        thump = lp(noise(0.07, 950 + b), 300) * env_exp(0.07, 50)
        parts.append((b * 0.16 + r.uniform(0, 0.02), crunch, 0))
        parts.append((b * 0.16, thump, -6))
    put("nom", mix(*parts), -20.0)

# --- drinking: three gulps
for v in range(2):
    parts = []
    for g in range(3):
        sec = 0.14
        t = t_of(sec)
        gulp = np.sin(2 * np.pi * (260 * t + 2600 * t * t)) * np.exp(-t * 28) * np.minimum(t / 0.004, 1)
        throat = lp(noise(sec, 1000 + g + v * 5), 400) * np.exp(-t * 35)
        parts.append((g * 0.17 + v * 0.01, lp(gulp, 1800), 0))
        parts.append((g * 0.17, throat, -4))
    put("glug", mix(*parts), -20.0)

# --- smoke puff: a soft exhale
for v in range(2):
    dur = 0.6
    t = t_of(dur)
    x = bp(noise(dur, 1100 + v), 250, 2600) * (np.sin(np.pi * t / dur) ** 1.5) * np.exp(-t * 1.5)
    put("puff", lp(x, 2500), -24.0)

# --- explosion: real low-frequency blast + crunch, a long rumble, falling debris
for v in range(3):
    r = np.random.default_rng(1200 + v)
    dur = 2.6
    t = t_of(dur)
    rumble = np.cumsum(noise(dur, 1201 + v)) * 0.02            # brown noise
    rumble = lp(hp(rumble, 25), 160) * np.minimum(t / 0.01, 1) * np.exp(-t * 1.6)
    crack = hp(noise(0.08, 1210 + v), 600) * env_exp(0.08, 50, 0.0005)
    parts = [(0, crack, -4), (0, rumble, 0),
             (0, k(f"lowFrequency_explosion_{v % 2:03d}"), -1),
             (0.005, k(f"explosionCrunch_{v:03d}"), -5)]
    for j in range(7):
        parts.append((0.35 + r.uniform(0, 1.4), k(f"impactWood_light_{r.integers(5):03d}"), -20 - j))
    x = room(mix(*parts), 0.18, 1.6, 2.5, 2500, seed=v)
    x = soft_clip(x / np.max(np.abs(x)) * 1.4, 1.0)
    put("boom", shelf_hi(lp(x, 6000), 2500, -5), -12.0)

# --- rocket launch: thruster ignition + rising roar
for v in range(2):
    dur = 1.3
    t = t_of(dur)
    roar = sweep_lp(noise(dur, 1300 + v), 400, 3500, 0.7) * np.minimum(t / 0.05, 1) * np.exp(-t * 1.4)
    thr = k(f"thrusterFire_{v:03d}")[:int(1.6 * SR)].copy()
    fade(thr, 0.002, 0.5)
    x = mix((0, thr, 0), (0, roar, -4), (0, lp(np.cumsum(noise(dur, 1310 + v)) * 0.03, 120) * np.exp(-t * 2), -4))
    put("launch", room(x, 0.12), -14.0)

# --- UI tones: soft bells instead of square beeps
ding = mix((0, fm_bell(1318.5, 1.2, 3.5, 1.2, 3.2), 0), (0.09, fm_bell(1975.5, 1.2, 3.5, 1.0, 3.4), -2))
put("ding", room(lp(ding, 7000), 0.2, 0.9, 4.0), -20.0)

err = mix((0, fm_bell(392.0, 0.5, 1.0, 1.5, 9.0, 12), 0), (0.12, fm_bell(311.1, 0.6, 1.0, 1.5, 8.0, 12), 0))
put("error", lp(err, 3500), -21.0)

for v, (a, b) in enumerate([(1046.5, 1318.5), (987.8, 1174.7)]):
    blip = mix((0, fm_bell(a, 0.25, 2.0, 0.8, 18, 25), 0), (0.065, fm_bell(b, 0.3, 2.0, 0.8, 16, 25), -1))
    put("chat", lp(blip, 6000), -24.0)

boot = []
for j, f in enumerate([261.63, 329.63, 392.0, 493.88, 587.33]):   # Cmaj9 bloom
    boot.append((j * 0.12, fm_bell(f, 2.2, 1.0, 1.2, 1.8, 3), -2 - j))
    boot.append((j * 0.12, fm_bell(f * 2, 1.6, 3.5, 0.6, 2.5, 6), -12 - j))
put("boot", room(lp(mix(*boot), 6000), 0.3, 1.8, 2.5), -20.0)

print("VARIANTS for sfx.gd:", json.dumps(counts, sort_keys=True))
