"""Small DSP toolkit shared by the Wobbly Hours audio build scripts (numpy + scipy + ffmpeg)."""
import subprocess
import numpy as np
from scipy import signal

SR = 44100


# ------------------------------------------------------------------ file io
def load(path, sr=SR):
    """Decode any audio file to a mono float32 array via ffmpeg."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def save_ogg(path, x, q=5):
    """x: (n,) mono or (n, 2) stereo float array in [-1, 1]."""
    x = np.asarray(x, dtype=np.float32)
    ch = 1 if x.ndim == 1 else x.shape[1]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), str(path)], input=x.tobytes(), check=True)


# ------------------------------------------------------------------ levels
def db(x):
    return 10 ** (x / 20.0)


def peak_norm(x, peak_db=-1.0):
    p = np.max(np.abs(x)) + 1e-12
    return x * (db(peak_db) / p)


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(np.square(x))) + 1e-12)


def trim(x, thresh_db=-50.0, pad=0.01, tail_fade=0.03):
    """Cut silence at both ends and fade the tail so nothing clicks."""
    a = np.abs(x)
    th = db(thresh_db) * np.max(a)
    idx = np.where(a > th)[0]
    if len(idx) == 0:
        return x
    s = max(0, idx[0] - int(pad * SR))
    e = min(len(x), idx[-1] + int(pad * SR))
    y = x[s:e].copy()
    fade(y, 0.002, tail_fade)
    return y


def fade(y, fin=0.002, fout=0.02):
    ni = min(len(y), int(fin * SR))
    no = min(len(y), int(fout * SR))
    if ni > 0:
        y[:ni] *= np.linspace(0, 1, ni)
    if no > 0:
        y[-no:] *= np.linspace(1, 0, no) ** 2
    return y


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


# ------------------------------------------------------------------ filters
def _sos(kind, f, order=2):
    f = np.clip(np.asarray(f, dtype=float), 10, SR * 0.49)
    return signal.butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("low", f, order), x, axis=0)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("high", f, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("band", [lo, hi], order), x, axis=0)


def peq(x, f, gain_db, q=1.0):
    """RBJ peaking EQ."""
    A = 10 ** (gain_db / 40.0)
    w = 2 * np.pi * f / SR
    al = np.sin(w) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w), 1 - al * A]
    a = [1 + al / A, -2 * np.cos(w), 1 - al / A]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def shelf_hi(x, f, gain_db):
    """RBJ high shelf (S=1)."""
    A = 10 ** (gain_db / 40.0)
    w = 2 * np.pi * f / SR
    al = np.sin(w) / 2 * np.sqrt(2)
    c = np.cos(w)
    b0 = A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al)
    b1 = -2 * A * ((A - 1) + (A + 1) * c)
    b2 = A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al)
    a0 = (A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al
    a1 = 2 * ((A - 1) - (A + 1) * c)
    a2 = (A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al
    return signal.lfilter([b0 / a0, b1 / a0, b2 / a0], [1, a1 / a0, a2 / a0], x, axis=0)


def sweep_lp(x, f0, f1, curve=1.0, block=256):
    """Time-varying one-pole-ish lowpass (block-wise 2nd order butterworth with state carried over)."""
    out = np.zeros_like(x)
    n = len(x)
    zi = np.zeros((1, 2))
    for s in range(0, n, block):
        t = (s / max(1, n - 1)) ** curve
        f = f0 * (f1 / f0) ** t
        sos = _sos("low", f)
        seg, zi = signal.sosfilt(sos, x[s:s + block], zi=zi)
        out[s:s + block] = seg
    return out


# ------------------------------------------------------------------ reverb
def reverb_ir(seconds=1.6, decay=3.0, stereo=True, hf_damp=4500.0, predelay=0.012, seed=1):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * decay)
    chans = []
    for c in range(2 if stereo else 1):
        nz = rng.standard_normal(n) * env
        # darker as it decays: blend a lowpassed copy in over time
        dark = lp(nz, hf_damp, 1)
        mix = np.clip(t / seconds * 1.5, 0, 1)
        ir = nz * (1 - mix) + dark * mix
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return np.stack(chans, axis=1) if stereo else chans[0]


def convolve(x, ir):
    """Mono or stereo x with mono or stereo ir, returns same length as x + ir."""
    if x.ndim == 1 and ir.ndim == 1:
        return signal.fftconvolve(x, ir)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    if ir.ndim == 1:
        ir = np.stack([ir, ir], axis=1)
    return np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], axis=1)


def room(x, wet=0.12, seconds=0.5, decay=9.0, hf=5000.0, seed=3):
    """Small natural room for one-shot SFX (mono in, mono out, with a tail)."""
    ir = reverb_ir(seconds, decay, stereo=False, hf_damp=hf, predelay=0.006, seed=seed)
    w = convolve(x, ir)
    d = np.concatenate([x, np.zeros(len(w) - len(x))])
    return d * (1 - wet * 0.5) + w * wet


# ------------------------------------------------------------------ dynamics
def compress(x, thresh_db=-18.0, ratio=3.0, attack=0.005, release=0.12, makeup_db=0.0):
    """Feed-forward RMS-ish compressor (stereo-linked). Works on (n,) or (n,2)."""
    mono = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    # envelope follower with separate attack / release, done in blocks for speed
    blk = 64
    nb = int(np.ceil(len(mono) / blk))
    pk = np.array([mono[i * blk:(i + 1) * blk].max() for i in range(nb)])
    env = np.zeros(nb)
    a_c = np.exp(-blk / (attack * SR))
    r_c = np.exp(-blk / (release * SR))
    e = 0.0
    for i in range(nb):
        c = a_c if pk[i] > e else r_c
        e = c * e + (1 - c) * pk[i]
        env[i] = e
    lvl = 20 * np.log10(env + 1e-9)
    over = np.maximum(0.0, lvl - thresh_db)
    gain_db = -over * (1 - 1 / ratio) + makeup_db
    g = np.repeat(db(gain_db), blk)[:len(mono)]
    g = signal.savgol_filter(g, 129, 2) if len(g) > 200 else g
    return x * (g[:, None] if x.ndim == 2 else g)


def master(x, target_rms_db=-16.0, ceiling_db=-1.0):
    """Glue compression, loudness to a gentle target, then a soft limiter."""
    x = hp(x, 28.0, 2)
    x = compress(x, -20.0, 2.0, 0.01, 0.2)
    x = x * db(target_rms_db - rms_db(x))
    c = db(ceiling_db)
    return np.tanh(x / c) * c
