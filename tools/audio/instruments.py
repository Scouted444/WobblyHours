"""Instruments for the Wobbly Hours music renderer. Every voice is band-limited (no raw square / saw
waves), so nothing aliases or buzzes. Each function returns a mono float64 note, including its release tail."""
import numpy as np
from dsp import SR, lp, hp, bp

_rng = np.random.default_rng(11)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def _t(sec):
    return np.arange(int(sec * SR)) / SR


def _adsr(n_on, a, d, s, r, total):
    """Attack/decay/sustain while held (n_on samples), then an exponential release."""
    t = np.arange(total) / SR
    on = n_on / SR
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    held = env[min(n_on, total - 1)] if total > 0 else 0
    rel = held * np.exp(-(t - on) / max(r, 1e-4))
    return np.where(t < on, env, rel)


def _additive(f, sec, amps, vib=0.0, vib_rate=5.0, detune=0.0):
    t = _t(sec)
    fv = f * (1 + detune) * (1 + vib * np.sin(2 * np.pi * vib_rate * t) * np.clip(t * 2 - 0.3, 0, 1))
    ph = 2 * np.pi * np.cumsum(fv) / SR
    out = np.zeros_like(t)
    for n, a in enumerate(amps, 1):
        if f * n > SR * 0.42:
            break
        out += a * np.sin(n * ph + _rng.uniform(0, 6.28))
    return out


def saw_amps(n=40, bright=1.0):
    return [(1.0 / k) * np.exp(-(k - 1) * 0.04 / bright) for k in range(1, n + 1)]


def square_amps(n=40):
    return [(1.0 / k if k % 2 else 0.0) for k in range(1, n + 1)]


# --------------------------------------------------------------------------- keys
def epiano(m, dur, vel=0.8, bright=1.0):
    """FM electric piano (Rhodes-ish): bell-like attack that mellows into a round tone."""
    f = mtof(m)
    sec = dur + 1.2
    t = _t(sec)
    idx = (0.9 + 1.6 * vel * bright) * np.exp(-t * 3.0) + 0.25
    car = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    tine = np.sin(2 * np.pi * f * 7.0 * t) * np.exp(-t * 28) * 0.10 * vel * (1 if f * 7 < 12000 else 0)
    bark = np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 6) * 0.12 * vel
    env = _adsr(int(dur * SR), 0.003, 1.6, 0.0, 0.18, len(t))
    x = (car + tine + bark) * env * vel
    return lp(x, 6500)


def marimba(m, dur, vel=0.8):
    f = mtof(m)
    sec = min(dur, 0.6) + 0.8
    t = _t(sec)
    x = (np.sin(2 * np.pi * f * t) * np.exp(-t * 5.5)
         + 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t * 22) * (f * 3.93 < 15000)
         + 0.12 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t * 60) * (f * 9.2 < 15000))
    x *= np.minimum(t / 0.0015, 1) * vel
    return x


def steel(m, dur, vel=0.8):
    """Steel-pan-ish: FM with a slightly inharmonic shimmer."""
    f = mtof(m)
    sec = min(dur, 0.8) + 1.0
    t = _t(sec)
    idx = 1.2 * np.exp(-t * 7) + 0.3
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 2.0 * t))
    x += 0.2 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * 8)
    x *= np.minimum(t / 0.004, 1) * np.exp(-t * 2.8) * vel
    return lp(x, 7000)


# --------------------------------------------------------------------------- strings
def guitar(m, dur, vel=0.8, bright=0.5, damp=0.996, mute=False):
    """Karplus-Strong plucked string - sounds like a real nylon / clean electric guitar."""
    f = mtof(m)
    N = max(2, int(round(SR / f - 0.5)))
    ring = dur + (0.06 if mute else 0.35)
    total = int(ring * SR)
    exc = _rng.uniform(-1, 1, N)
    exc = lp(exc, 1500 + 6000 * bright)
    y = np.zeros(total + N)
    y[:N] = exc
    g = damp if not mute else 0.90
    prev = y[:N].copy()
    pos = N
    while pos < len(y):
        shifted = np.concatenate([[prev[-1]], prev[:-1]])
        cur = g * 0.5 * (prev + shifted)
        n = min(N, len(y) - pos)
        y[pos:pos + n] = cur[:n]
        prev = cur
        pos += N
    y = y[:total]
    t = np.arange(total) / SR
    stop = np.where(t < dur, 1.0, np.exp(-(t - dur) / (0.015 if mute else 0.08)))
    y = y * stop * vel
    return hp(y, 70)


def strings(m, dur, vel=0.7, attack=0.25):
    f = mtof(m)
    sec = dur + 0.6
    x = sum(_additive(f, sec, saw_amps(30, 0.7), vib=0.004, vib_rate=5.2 + d * 3, detune=d * 0.004) for d in (-1, 0, 1))
    env = _adsr(int(dur * SR), attack, 0.6, 0.85, 0.35, len(x))
    return lp(x * env * vel / 3.0, 3800)


def pad(m, dur, vel=0.6, cutoff=1800, attack=0.4):
    f = mtof(m)
    sec = dur + 1.0
    x = sum(_additive(f, sec, saw_amps(24, 0.5), detune=d * 0.005) for d in (-1, 0, 1))
    env = _adsr(int(dur * SR), attack, 1.0, 0.8, 0.6, len(x))
    return lp(x * env * vel / 3.0, cutoff)


# --------------------------------------------------------------------------- synths
def pluck(m, dur, vel=0.7, cutoff=2600):
    """Soft analog-style pluck (filtered saw with a fast filter envelope)."""
    f = mtof(m)
    sec = dur + 0.4
    x = _additive(f, sec, saw_amps(30, 0.6))
    t = _t(sec)
    bright = lp(x, cutoff)
    dark = lp(x, 500)
    fe = np.exp(-t * 14)
    y = dark * (1 - fe) + bright * fe
    env = _adsr(int(dur * SR), 0.002, 0.25, 0.25, 0.15, len(t))
    return y * env * vel


def lead(m, dur, vel=0.7, cutoff=2400, square=False):
    f = mtof(m)
    sec = dur + 0.5
    amps = square_amps(30) if square else saw_amps(30, 0.8)
    x = _additive(f, sec, amps, vib=0.006, vib_rate=5.5) * 0.7 + _additive(f, sec, amps, detune=0.004) * 0.3
    env = _adsr(int(dur * SR), 0.012, 0.4, 0.7, 0.18, len(x))
    return lp(lp(x * env * vel, cutoff), cutoff * 1.6)


def sub_bass(m, dur, vel=0.9, tone=0.35, pluck_amt=0.6):
    """Warm bass: sine + a little upper harmonic content that fades (finger / synth bass)."""
    f = mtof(m)
    sec = dur + 0.25
    t = _t(sec)
    ph = 2 * np.pi * f * t
    body = np.sin(ph) + tone * 0.5 * np.sin(2 * ph) + tone * 0.25 * np.sin(3 * ph)
    pl = np.exp(-t * 18) * pluck_amt
    upper = (0.3 * np.sin(4 * ph) + 0.15 * np.sin(5 * ph)) * pl
    env = _adsr(int(dur * SR), 0.004, 0.5, 0.75, 0.05, len(t))
    x = np.tanh((body + upper) * 1.3) * env * vel
    return lp(x, 1800)


def saw_bass(m, dur, vel=0.9, cutoff=900):
    f = mtof(m)
    sec = dur + 0.15
    t = _t(sec)
    x = _additive(f, sec, saw_amps(24, 0.8)) + 0.6 * np.sin(2 * np.pi * f * t)
    fe = np.exp(-t * 10)
    y = lp(x, cutoff * 0.4) * (1 - fe) + lp(x, cutoff) * fe
    env = _adsr(int(dur * SR), 0.003, 0.3, 0.8, 0.04, len(t))
    return np.tanh(y * env * 1.2) * vel


# --------------------------------------------------------------------------- drums
def kick(vel=1.0, punch=1.0, tail=0.35):
    t = _t(tail + 0.1)
    f = 48 + 110 * punch * np.exp(-t * 32)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tail * 3.2)
    click = lp(_rng.standard_normal(len(t)), 4000) * np.exp(-t * 300) * 0.25
    return np.tanh((body + click) * 1.4) * vel


def snare(vel=1.0, tone=190, snappy=0.8, decay=14.0):
    t = _t(0.45)
    body = (np.sin(2 * np.pi * tone * t) + 0.5 * np.sin(2 * np.pi * tone * 1.7 * t)) * np.exp(-t * 28)
    wires = bp(_rng.standard_normal(len(t)), 1800, 9000) * np.exp(-t * decay) * snappy
    x = (body * 0.7 + wires) * vel
    return lp(x, 10000)


def rim(vel=1.0):
    t = _t(0.12)
    x = (np.sin(2 * np.pi * 820 * t) * 0.6 + bp(_rng.standard_normal(len(t)), 1500, 5000) * 0.5) * np.exp(-t * 60)
    return x * vel


def clap(vel=1.0):
    t = _t(0.4)
    n = _rng.standard_normal(len(t))
    env = np.zeros_like(t)
    for off in (0.0, 0.011, 0.022):
        env += np.where(t >= off, np.exp(-(t - off) * 140), 0)
    env += np.where(t >= 0.03, np.exp(-(t - 0.03) * 14) * 0.6, 0)
    return bp(n, 900, 5500) * env * vel


def hat(vel=1.0, open_=False):
    t = _t(0.5 if open_ else 0.09)
    n = _rng.standard_normal(len(t))
    x = hp(bp(n, 6000, 13000), 5000) * np.exp(-t * (7 if open_ else 55))
    return lp(x, 12000) * vel


def shaker(vel=1.0):
    t = _t(0.12)
    n = _rng.standard_normal(len(t))
    env = np.minimum(t / 0.02, 1) * np.exp(-t * 35)
    return bp(n, 3500, 9000) * env * vel


def tom(m=45, vel=1.0):
    t = _t(0.6)
    f = mtof(m) * (1 + 0.5 * np.exp(-t * 25))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    x += bp(_rng.standard_normal(len(t)), 200, 2500) * np.exp(-t * 30) * 0.2
    return x * vel


def crash(vel=1.0):
    t = _t(2.5)
    x = hp(_rng.standard_normal(len(t)), 3500) * np.exp(-t * 1.6) * np.minimum(t / 0.003, 1)
    return lp(x, 11000) * vel


def vinyl(sec, amount=1.0, seed=5):
    r = np.random.default_rng(seed)
    n = int(sec * SR)
    hiss = lp(hp(r.standard_normal(n), 2000), 7000) * 0.015
    pops = np.zeros(n)
    idx = r.integers(0, n, int(sec * 9))
    pops[idx] = r.uniform(-1, 1, len(idx)) * r.uniform(0.1, 0.5, len(idx))
    pops = bp(pops, 800, 6000)
    return (hiss + pops * 0.4) * amount
