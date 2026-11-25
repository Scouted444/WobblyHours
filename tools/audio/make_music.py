"""Renders the jukebox / menu songs for Wobbly Hours to audio/music/*.ogg (seamless stereo loops).

    python tools/audio/make_music.py [output folder]

Each song is composed here (chords, bass line, drum grooves, melody) and played by the band-limited
instruments in instruments.py, then mixed with reverb / delay / sidechain and mastered.
"""
import sys
from pathlib import Path
import numpy as np
from dsp import SR, save_ogg, db, lp, hp, peq, shelf_hi, convolve, reverb_ir, master, rms_db, compress
import instruments as I

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("audio/music")
OUT.mkdir(parents=True, exist_ok=True)

PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
      "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
QUAL = {"maj": [0, 4, 7], "min": [0, 3, 7], "maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "dom7": [0, 4, 7, 10],
        "maj9": [0, 4, 7, 11, 14], "min9": [0, 3, 7, 10, 14], "dom9": [0, 4, 7, 10, 14], "sus4": [0, 5, 7],
        "7sus": [0, 5, 7, 10, 14], "add9": [0, 4, 7, 14], "6": [0, 4, 7, 9], "min6": [0, 3, 7, 9],
        "13": [0, 4, 10, 14, 21], "m7b5": [0, 3, 6, 10]}


def chord(sym):
    """'F:maj9' -> (root pitch class, intervals)."""
    r, q = sym.split(":")
    return PC[r], QUAL[q]


def voicing(sym, center=62, prev=None, size=4, rootless=False):
    root, iv = chord(sym)
    tones = [i for i in iv if not (rootless and i == 0)][:size] if rootless else iv[:size]
    base = root + 12 * round((center - 6 - root) / 12)
    notes = sorted(base + i for i in tones)
    best, cost = notes, 1e9
    cand = notes
    for _ in range(len(notes) * 2):
        for shift in (-12, 0, 12):
            c = [n + shift for n in cand]
            ref = np.mean(prev) if prev else center
            k = abs(np.mean(c) - ref) + (abs(np.mean(c) - center) * 0.5)
            if k < cost:
                best, cost = c, k
        cand = sorted(cand[1:] + [cand[0] + 12])
    return best


class Song:
    def __init__(self, name, bpm, bars, swing=0.0, seed=0, beats_per_bar=4):
        self.name, self.bpm, self.bars, self.swing = name, bpm, bars, swing
        self.bpb = beats_per_bar
        self.spb = 60.0 / bpm
        self.length = int(round(bars * beats_per_bar * self.spb * SR))
        self.tail = int(4.0 * SR)
        self.tracks = {}
        self.rng = np.random.default_rng(seed)
        self.kicks = []

    def track(self, name, pan=0.0, rev=0.15, dly=0.0, duck=0.0, gain_db=0.0, eq=None):
        self.tracks[name] = dict(buf=np.zeros(self.length + self.tail), pan=pan, rev=rev, dly=dly, duck=duck,
                                 gain=db(gain_db), eq=eq)

    def time(self, beat, human=0.004):
        """Beat -> seconds, with swing on off-beat 16ths and a little human timing."""
        s16 = beat * 4
        if abs(s16 - round(s16)) < 1e-6 and int(round(s16)) % 2 == 1:
            beat += self.swing * 0.25
        return beat * self.spb + (self.rng.normal(0, human) if human else 0.0)

    def put(self, trk, beat, sig, vol_db=0.0, human=0.004):
        i = max(0, int(self.time(beat, human) * SR))
        b = self.tracks[trk]["buf"]
        n = min(len(sig), len(b) - i)
        if n > 0:
            b[i:i + n] += sig[:n] * db(vol_db)

    def note(self, trk, beat, dur_beats, sig_fn, vol_db=0.0, human=0.004):
        self.put(trk, beat, sig_fn(dur_beats * self.spb), vol_db, human)

    def drums(self, bar, pattern, kit, vol=None, human=0.003):
        """pattern: {voice: 16-char string}, 'X' accent, 'x' hit, 'o' ghost."""
        vol = vol or {}
        for voice, steps in pattern.items():
            for s, ch in enumerate(steps):
                if ch in "Xxo":
                    v = {"X": 1.0, "x": 0.8, "o": 0.4}[ch] * self.rng.uniform(0.92, 1.0)
                    beat = bar * self.bpb + s / 4.0
                    self.put("drums_" + voice if "drums_" + voice in self.tracks else "drums", beat,
                             kit[voice](v), vol.get(voice, 0.0), human)
                    if voice == "kick":
                        self.kicks.append(self.time(beat, 0))

    def render(self, rev_ir, delay_beats=0.75, delay_fb=0.35, lowpass=None, vinyl=None, target=-16.5):
        L, total = self.length, self.length + self.tail
        t = np.arange(total) / SR
        duck_env = np.ones(total)
        if self.kicks:
            env = np.zeros(total)
            for k in self.kicks:
                for rep in (0.0, L / SR):       # also wrap kicks so the loop seam ducks properly
                    i = int((k + rep) * SR)
                    if i < total:
                        seg = np.exp(-np.arange(total - i) / SR / 0.11)
                        env[i:] = np.maximum(env[i:], seg)
            duck_env = env
        mix = np.zeros((total, 2))
        rev_bus = np.zeros((total, 2))
        dly_bus = np.zeros(total)
        for name, tr in self.tracks.items():
            x = tr["buf"] * tr["gain"]
            if tr["eq"]:
                x = tr["eq"](x)
            if tr["duck"] > 0:
                x = x * (1 - tr["duck"] * duck_env)
            p = (tr["pan"] + 1) * np.pi / 4
            st = np.stack([x * np.cos(p), x * np.sin(p)], axis=1)
            mix += st
            rev_bus += st * tr["rev"]
            dly_bus += x * tr["dly"]
        # ping-pong delay
        if np.any(dly_bus):
            d = int(delay_beats * self.spb * SR)
            echo = np.zeros((total, 2))
            src = lp(hp(dly_bus, 300), 3500)
            g = 1.0
            for r in range(1, 7):
                g *= delay_fb
                ch = (r + 1) % 2
                if r * d < total:
                    echo[r * d:, ch] += src[:total - r * d] * g
                src = lp(src, 3000)
            mix += echo
            rev_bus += echo * 0.3
        wet = convolve(rev_bus, rev_ir)[:total]
        mix += hp(wet, 180)
        # wrap the tail onto the start so the loop is seamless
        out = mix[:L].copy()
        tail = mix[L:]
        n = min(len(tail), L)
        out[:n] += tail[:n]
        if vinyl is not None:
            out += np.stack([vinyl[:L], np.roll(vinyl[:L], 777)], axis=1)
        if lowpass:
            out = lp(out, lowpass, 2)
        out = peq(out, 55.0, -4.0, 0.7)          # tame the sub so it doesn't boom
        out = peq(out, 300.0, -1.5, 0.8)         # clear a little mud
        out = shelf_hi(out, 5000, 2.0)           # a touch of air (everything is band-limited, so no fizz)
        # master three copies back to back and keep the middle one, so the compressor / filters are already
        # settled at the loop point and the seam is sample-continuous
        tiled = master(np.concatenate([out, out, out]), target, -1.2)
        return tiled[L:2 * L].astype(np.float32)


# ------------------------------------------------------------------ melody writer
def write_melody(song, trk, inst, chords_per_bar, start_bar, bars, scale, lo, hi, rhythms, vol_db=0.0, seed=0,
                 cadence=True):
    """Phrase-based melody: 2-bar motifs in an A A' B A'' shape, notes on the beat lean on chord tones,
    the rest walk stepwise through the scale. rhythms: list of 2-bar patterns [(start16, len16), ...]."""
    r = np.random.default_rng(seed)
    pool = [m for m in range(lo, hi + 1) if m % 12 in scale]
    cur = pool[len(pool) // 2]
    shape = [0, 0, 1, 0] * 8
    motif_cache = {}
    for ph in range(bars // 2):
        bar0 = start_bar + ph * 2
        ridx = shape[ph % len(shape)] if len(rhythms) > 1 else 0
        if ph % 4 == 2 and len(rhythms) > 2:
            ridx = 2
        rhythm = rhythms[ridx]
        last_phrase = cadence and (ph % 4 == 3)
        contour = motif_cache.get(ridx)
        steps = []
        for ni, (st, ln) in enumerate(rhythm):
            bar = bar0 + st // 16
            ch = chords_per_bar[(bar - start_bar) % len(chords_per_bar)]
            sym = ch[0] if st % 16 < 8 or len(ch) == 1 else ch[1]
            root, iv = chord(sym)
            ctones = [(root + i) % 12 for i in iv[:4]]
            strong = st % 4 == 0
            if contour is not None and ni < len(contour) and r.random() < 0.65:
                target = cur + contour[ni]          # repeat the motif's shape
            else:
                target = cur + int(r.choice([-4, -2, -1, 1, 2, 3, 5]) if r.random() < 0.8 else r.choice([-7, 7]))
            if last_phrase and ni == len(rhythm) - 1:
                cands = [m for m in pool if m % 12 == root % 12] or pool
            elif strong:
                cands = [m for m in pool if m % 12 in ctones] or pool
            else:
                cands = pool
            nxt = min(cands, key=lambda m: abs(m - target) + r.uniform(0, 0.6))
            steps.append(nxt - cur)
            cur = nxt
            dur = ln / 4.0
            vel = (0.85 if strong else 0.7) * r.uniform(0.9, 1.0)
            song.note(trk, bar0 * song.bpb + st / 4.0, dur, lambda s, m=cur, v=vel: inst(m, s, v), vol_db)
        if ridx not in motif_cache:
            motif_cache[ridx] = steps
        # drift back toward the middle of the range between phrases
        mid = (lo + hi) / 2
        if abs(cur - mid) > 7:
            cur = int(cur + np.sign(mid - cur) * 5)


def bars_of(prog, n):
    """Repeat a progression (list of per-bar chord lists) for n bars."""
    return [prog[i % len(prog)] for i in range(n)]


def comp(song, trk, inst, bars, start_bar, pattern, center=62, size=4, vol_db=0.0, rootless=False, spread=0.0):
    """Chord comping. pattern: list of (beat_in_bar, length_beats, velocity). Two chords per bar split at beat 2."""
    prev = None
    for b, ch in enumerate(bars):
        for beat, ln, vel in pattern:
            sym = ch[0] if beat < 2 or len(ch) == 1 else ch[1]
            v = voicing(sym, center, prev, size, rootless)
            prev = v
            for j, m in enumerate(v):
                song.note(trk, (start_bar + b) * song.bpb + beat + j * spread, ln,
                          lambda s, m=m, vv=vel: inst(m, s, vv), vol_db - 2.5)


def bassline(song, trk, inst, bars, start_bar, pattern, octave=36, vol_db=0.0):
    """pattern: list of (beat, len, interval: 'R' root / '5' fifth / '8' octave / 'n' approach next root, vel)."""
    for b, ch in enumerate(bars):
        for beat, ln, deg, vel in pattern:
            sym = ch[0] if beat < 2 or len(ch) == 1 else ch[1]
            root, iv = chord(sym)
            m = octave + root
            if m > octave + 7:
                m -= 12
            if deg == "5":
                m += 7
            elif deg == "8":
                m += 12
            elif deg == "3":
                m += iv[1]
            elif deg == "7":
                m += iv[3] if len(iv) > 3 else 10
            elif deg == "n":
                nxt = bars[(b + 1) % len(bars)][0]
                nr = octave + chord(nxt)[0]
                if nr > octave + 7:
                    nr -= 12
                m = nr - 1 if song.rng.random() < 0.5 else nr + 2
            song.note(trk, (start_bar + b) * song.bpb + beat, ln, lambda s, m=m, v=vel: inst(m, s, v), vol_db)


KIT = {"kick": I.kick, "snare": I.snare, "hat": I.hat, "ohat": lambda v: I.hat(v, True), "rim": I.rim,
       "clap": I.clap, "shk": I.shaker, "crash": I.crash}


def scale_of(key, mode):
    steps = {"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10],
             "pent": [0, 2, 4, 7, 9], "mpent": [0, 3, 5, 7, 10]}[mode]
    return [(PC[key] + s) % 12 for s in steps]


# =============================================================== the songs
def menu_groove():
    """Neo-soul / funk: Rhodes, clean guitar licks, finger bass, a laid-back pocket."""
    s = Song("Menu Groove", 96, 32, swing=0.12, seed=1)
    s.track("keys", pan=-0.2, rev=0.22)
    s.track("gtr", pan=0.35, rev=0.25, dly=0.18)
    s.track("bass", rev=0.02)
    s.track("drums", rev=0.08)
    s.track("drums_hat", pan=0.25, rev=0.05, gain_db=-4)
    s.track("drums_shk", pan=-0.4, rev=0.1, gain_db=-8)
    A = [["F:maj9"], ["E:min7", "A:dom7"], ["D:min9"], ["C:min7", "F:dom9"]]
    B = [["Bb:maj7"], ["A:min7"], ["G:min9"], ["C:7sus"]]
    prog = bars_of(A, 8) + bars_of(A, 8) + bars_of(B, 8) + bars_of(A, 8)
    comp(s, "keys", lambda m, d, v: I.epiano(m, d, v * 0.8), prog, 0,
         [(0, 1.4, 0.8), (1.75, 0.5, 0.55), (2.5, 1.2, 0.7), (3.75, 0.25, 0.45)], center=63, rootless=True, spread=0.012)
    bassline(s, "bass", lambda m, d, v: I.sub_bass(m, d, v, 0.45, 0.8), prog, 0,
             [(0, 0.9, "R", 0.95), (1.5, 0.25, "8", 0.6), (1.75, 0.5, "5", 0.75), (2.5, 0.75, "R", 0.85), (3.5, 0.4, "n", 0.7)],
             octave=36)
    groove = {"kick": "X.....x...x.....", "snare": "....X.......X..o", "hat": "x.x.x.x.x.xox.x.", "shk": "..x...x...x...x."}
    intro = {"kick": "X.........x.....", "hat": "x.x.x.x.x.x.x.x."}
    for b in range(32):
        p = intro if b < 4 else groove
        if b % 8 == 7 and b >= 4:
            p = dict(groove, snare="....X.......X.oo")
        s.drums(b, p, KIT, {"kick": -2, "snare": -5, "hat": -8, "shk": -6})
    sc = scale_of("F", "major")
    rh = [[(0, 3), (3, 1), (4, 2), (6, 2), (10, 6), (24, 2), (26, 2), (28, 4)],
          [(2, 2), (4, 2), (6, 4), (12, 2), (14, 6), (22, 2), (24, 8)],
          [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4), (16, 2), (20, 4), (26, 6)]]
    gtr = lambda m, d, v: I.guitar(m, d, v, bright=0.45, damp=0.997)
    write_melody(s, "gtr", gtr, prog[8:], 8, 24, sc, 65, 84, rh, vol_db=-1, seed=11)
    return s, dict(rev=reverb_ir(1.8, 3.2, seed=1), delay_beats=0.75, delay_fb=0.3)


def pool_party():
    """Tropical house: marimba / steel-pan hook, off-beat guitar, pumping pad, four on the floor."""
    s = Song("Pool Party", 110, 32, swing=0.05, seed=2)
    s.track("pad", rev=0.25, duck=0.55, gain_db=-6)
    s.track("gtr", pan=-0.35, rev=0.2, duck=0.3)
    s.track("hook", pan=0.15, rev=0.25, dly=0.2)
    s.track("bass", duck=0.35)
    s.track("drums", rev=0.06)
    s.track("drums_hat", pan=0.3, rev=0.08, gain_db=-5)
    s.track("drums_shk", pan=-0.3, rev=0.08, gain_db=-7)
    prog = bars_of([["G:add9"], ["E:min7"], ["C:maj7"], ["D:6"]], 32)
    comp(s, "pad", lambda m, d, v: I.pad(m, d, v, 2200, 0.15), prog, 0, [(0, 3.9, 0.7)], center=62)
    comp(s, "gtr", lambda m, d, v: I.guitar(m, d, v, 0.6, mute=True), prog[4:], 4,
         [(0.5, 0.25, 0.6), (1.5, 0.25, 0.7), (2.5, 0.25, 0.6), (3.5, 0.25, 0.7), (3.75, 0.2, 0.4)], center=67, size=3)
    bassline(s, "bass", lambda m, d, v: I.sub_bass(m, d, v, 0.3, 0.5), prog, 0,
             [(0, 0.45, "R", 0.9), (0.75, 0.25, "R", 0.6), (1.5, 0.45, "8", 0.7), (2.5, 0.45, "5", 0.8), (3.5, 0.4, "R", 0.75)],
             octave=31)
    house = {"kick": "x...x...x...x...", "clap": "....x.......x...", "hat": "..x...x...x...x.", "shk": "xoxoxoxoxoxoxoxo"}
    for b in range(32):
        p = house if b >= 4 else {"shk": house["shk"], "hat": house["hat"]}
        if b in (12, 28):
            p = dict(house, crash="x...............")
        if b in (15, 31):
            p = dict(house, clap="....x.......x.xx")
        s.drums(b, p, KIT, {"kick": -1, "clap": -8, "hat": -7, "shk": -12, "crash": -16})
    sc = scale_of("G", "pent")
    rh = [[(0, 2), (3, 2), (6, 2), (8, 2), (10, 4), (16, 2), (19, 2), (22, 4)],
          [(0, 2), (2, 2), (4, 2), (6, 4), (14, 2), (16, 6), (24, 2), (26, 4)],
          [(2, 2), (6, 2), (10, 2), (12, 4), (18, 2), (22, 2), (26, 2), (28, 4)]]
    write_melody(s, "hook", lambda m, d, v: I.steel(m, d, v),
                 prog[8:], 8, 24, sc, 67, 86, rh, vol_db=-2, seed=22)
    return s, dict(rev=reverb_ir(1.5, 3.6, seed=2), delay_beats=0.75, delay_fb=0.3)


def boss_fight():
    """Driving minor-key rock-synth: punchy drums, 8th-note bass, a soaring (but filtered) lead."""
    s = Song("Boss Fight", 140, 32, seed=3)
    s.track("pad", rev=0.25, gain_db=-8)
    s.track("bass", rev=0.0)
    s.track("gtr", pan=-0.5, rev=0.12, gain_db=-4)
    s.track("gtr2", pan=0.5, rev=0.12, gain_db=-4)
    s.track("lead", pan=0.05, rev=0.22, dly=0.22)
    s.track("drums", rev=0.12)
    s.track("drums_hat", pan=0.3, rev=0.05, gain_db=-5)
    s.track("drums_crash", rev=0.15, gain_db=-8)
    A = [["A:min"], ["F:maj"], ["G:maj"], ["E:min"]]
    B = [["D:min"], ["A:min"], ["F:maj"], ["E:maj"]]
    prog = bars_of(A, 8) + bars_of(A, 8) + bars_of(B, 8) + bars_of(A, 8)
    comp(s, "pad", lambda m, d, v: I.strings(m, d, v, 0.1), prog, 0, [(0, 3.95, 0.6)], center=60, size=3)
    bassline(s, "bass", lambda m, d, v: I.saw_bass(m, d, v, 750), prog, 0,
             [(i * 0.5, 0.42, "R" if i != 7 else "8", 0.9 if i % 2 == 0 else 0.7) for i in range(8)], octave=33)
    # chugging muted power chords (root + fifth), doubled left / right
    for b, ch in enumerate(prog[8:], 8):
        root = chord(ch[0])[0]
        for i in range(8):
            for trk, det in (("gtr", 0), ("gtr2", 1)):
                for iv in (0, 7, 12):
                    s.note(trk, b * 4 + i * 0.5 + det * 0.006, 0.3,
                           lambda d, m=40 + root + iv if root < 5 else 28 + root + iv: I.guitar(m, d, 0.7, 0.35, mute=True))
    rock = {"kick": "X.x...x.X.x...x.", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.x."}
    for b in range(32):
        p = rock if b >= 4 else {"kick": "x...x...x...x...", "hat": "x.x.x.x.x.x.x.x."}
        if b % 8 == 0 and b >= 8:
            p = dict(rock, crash="x...............")
        if b % 8 == 7 and b >= 4:
            p = dict(rock, snare="....X.......XoXX")
        s.drums(b, p, KIT, {"kick": 0, "snare": -3, "hat": -8, "crash": -8})
    sc = scale_of("A", "minor")
    rh = [[(0, 4), (4, 2), (6, 2), (8, 4), (12, 4), (16, 6), (22, 2), (24, 8)],
          [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4), (16, 8), (24, 4), (28, 4)],
          [(0, 6), (6, 2), (8, 6), (14, 2), (16, 4), (20, 4), (24, 8)]]
    write_melody(s, "lead", lambda m, d, v: I.lead(m, d, v, 2300), prog[8:], 8, 24, sc, 64, 81, rh, vol_db=-3, seed=33)
    return s, dict(rev=reverb_ir(1.6, 3.4, seed=3), delay_beats=0.75, delay_fb=0.28)


def sunset_drive():
    """Synthwave: warm pads, a 16th-note arp, gated snare, long singing lead."""
    s = Song("Sunset Drive", 96, 32, seed=4)
    s.track("pad", rev=0.3, duck=0.3, gain_db=-5)
    s.track("arp", pan=0.3, rev=0.2, dly=0.25, gain_db=-7)
    s.track("bass", duck=0.2)
    s.track("lead", pan=-0.1, rev=0.3, dly=0.3)
    s.track("drums", rev=0.2)
    s.track("drums_hat", pan=-0.25, rev=0.05, gain_db=-6)
    prog = bars_of([["D:min9"], ["Bb:maj7"], ["F:maj9"], ["C:6"]], 32)
    comp(s, "pad", lambda m, d, v: I.pad(m, d, v, 1600, 0.5), prog, 0, [(0, 3.95, 0.7)], center=60)
    for b, ch in enumerate(prog):
        v = voicing(ch[0], 69, None, 4)
        seq = [v[0], v[1], v[2], v[3], v[2], v[1], v[0] + 12, v[1]]
        for i in range(16):
            s.note("arp", b * 4 + i * 0.25, 0.22, lambda d, m=seq[i % 8]: I.pluck(m, d, 0.6, 2200), human=0.0)
    bassline(s, "bass", lambda m, d, v: I.saw_bass(m, d, v, 600), prog, 0,
             [(i * 0.5, 0.45, "R" if i % 4 != 3 else "8", 0.85 if i % 2 == 0 else 0.65) for i in range(8)], octave=34)
    wave = {"kick": "x.......x.......", "snare": "....X.......X...", "hat": "..x...x...x...x."}
    for b in range(32):
        p = wave if b >= 4 else {"kick": "x.......x......."}
        s.drums(b, p, KIT, {"kick": -1, "snare": -3, "hat": -8})
    sc = scale_of("D", "minor")
    rh = [[(0, 6), (6, 2), (8, 8), (16, 4), (20, 4), (24, 8)],
          [(0, 4), (4, 4), (8, 6), (14, 2), (16, 12)],
          [(2, 2), (4, 4), (8, 4), (12, 4), (16, 6), (22, 2), (24, 8)]]
    write_melody(s, "lead", lambda m, d, v: I.lead(m, d, v, 2000, square=True), prog[8:], 8, 24, sc, 62, 79, rh,
                 vol_db=-4, seed=44)
    return s, dict(rev=reverb_ir(2.6, 2.2, seed=4, hf_damp=3500), delay_beats=0.75, delay_fb=0.4)


def lazy_sunday():
    """Lo-fi hip hop: dusty Rhodes, upright-ish bass, swung boom-bap, vinyl crackle."""
    s = Song("Lazy Sunday", 78, 24, swing=0.33, seed=5)
    s.track("keys", pan=-0.15, rev=0.28)
    s.track("mel", pan=0.25, rev=0.3, dly=0.15)
    s.track("bass", rev=0.02)
    s.track("drums", rev=0.08)
    s.track("drums_hat", pan=0.3, rev=0.05, gain_db=-5)
    prog = bars_of([["C:maj9"], ["A:min9"], ["D:min9"], ["G:13"]], 24)
    comp(s, "keys", lambda m, d, v: I.epiano(m, d, v * 0.75, 0.7), prog, 0,
         [(0, 1.9, 0.75), (2.25, 0.5, 0.5), (3.0, 0.9, 0.6)], center=62, size=4, rootless=True, spread=0.02)
    bassline(s, "bass", lambda m, d, v: I.sub_bass(m, d, v, 0.25, 0.4), prog, 0,
             [(0, 1.2, "R", 0.9), (1.75, 0.5, "5", 0.6), (2.5, 1.0, "R", 0.75), (3.5, 0.45, "n", 0.6)], octave=36)
    bap = {"kick": "X......x..x.....", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.xo", "rim": "..........o....."}
    for b in range(24):
        p = bap if b >= 2 else {"hat": bap["hat"]}
        s.drums(b, p, KIT, {"kick": -1, "snare": -5, "hat": -7, "rim": -12})
    sc = scale_of("C", "pent")
    rh = [[(0, 2), (2, 2), (4, 6), (12, 2), (14, 2), (16, 8)],
          [(4, 2), (6, 2), (8, 4), (14, 2), (16, 4), (22, 6)]]
    write_melody(s, "mel", lambda m, d, v: I.epiano(m, d, v * 0.6, 0.5), prog[8:], 8, 16, sc, 67, 84, rh, vol_db=-3,
                 seed=55)
    vin = I.vinyl(s.length / SR + 1, 0.8)
    return s, dict(rev=reverb_ir(1.4, 3.8, seed=5, hf_damp=3000), delay_beats=0.75, delay_fb=0.3,
                   lowpass=7500, vinyl=vin, target=-17.5)


def disco_inferno():
    """Disco: octave bass, string swells, chicken-scratch guitar, open hats on the off-beat."""
    s = Song("Disco Inferno", 118, 32, seed=6)
    s.track("strings", rev=0.25, duck=0.25, gain_db=-3)
    s.track("gtr", pan=0.45, rev=0.1, gain_db=-4)
    s.track("keys", pan=-0.4, rev=0.18, gain_db=-5)
    s.track("bass", duck=0.15)
    s.track("lead", pan=-0.05, rev=0.25, dly=0.12)
    s.track("drums", rev=0.08)
    s.track("drums_hat", pan=0.25, rev=0.06, gain_db=-5)
    s.track("drums_ohat", pan=-0.2, rev=0.08, gain_db=-7)
    prog = bars_of([["E:min9"], ["A:dom9"], ["E:min9"], ["A:dom9"], ["C:maj7"], ["B:7sus"], ["E:min9"], ["B:dom7"]], 32)
    comp(s, "strings", lambda m, d, v: I.strings(m, d, v, 0.3), prog, 0, [(0, 3.95, 0.6)], center=64, size=3)
    for b, ch in enumerate(prog[4:], 4):
        v = voicing(ch[0], 66, None, 3)
        for i in range(16):
            if i % 4 in (1, 2, 3) or i % 8 == 0:
                vel = 0.7 if i % 2 else 0.5
                for j, m in enumerate(v):
                    s.note("gtr", b * 4 + i * 0.25 + j * 0.004, 0.12,
                           lambda d, m=m, vel=vel: I.guitar(m, d, vel, 0.7, mute=True))
    comp(s, "keys", lambda m, d, v: I.epiano(m, d, v * 0.6), prog[8:], 8,
         [(1.5, 0.4, 0.6), (3.5, 0.4, 0.6)], center=67, size=3)
    for b, ch in enumerate(prog):
        root = chord(ch[0])[0]
        base = 28 + root if root < 8 else 16 + root
        for i in range(8):
            m = base + (12 if i % 2 else 0)
            s.note("bass", b * 4 + i * 0.5, 0.42, lambda d, m=m, i=i: I.sub_bass(m, d, 0.9 if i % 2 == 0 else 0.75, 0.5, 0.9))
    disco = {"kick": "x...x...x...x...", "clap": "....x.......x...", "hat": "x.xxx.xxx.xxx.xx", "ohat": "..x...x...x...x."}
    for b in range(32):
        p = disco if b >= 4 else {"kick": disco["kick"], "hat": disco["hat"]}
        if b % 8 == 0 and b >= 8:
            p = dict(disco, crash="x...............")
        s.drums(b, p, KIT, {"kick": -1, "clap": -6, "hat": -10, "ohat": -10, "crash": -12})
    sc = scale_of("E", "dorian")
    rh = [[(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4), (16, 8), (24, 2), (26, 2), (28, 4)],
          [(0, 6), (6, 2), (8, 4), (12, 4), (16, 2), (18, 2), (20, 4), (24, 8)]]
    write_melody(s, "lead", lambda m, d, v: I.strings(m, d, v, 0.05) * 1.6, prog[16:], 16, 16, sc, 67, 83, rh,
                 vol_db=-1, seed=66)
    return s, dict(rev=reverb_ir(1.7, 3.2, seed=6), delay_beats=0.5, delay_fb=0.25)


SONGS = {"Menu Groove": ("menu_groove", menu_groove), "Pool Party": ("pool_party", pool_party),
         "Boss Fight": ("boss_fight", boss_fight), "Sunset Drive": ("sunset_drive", sunset_drive),
         "Lazy Sunday": ("lazy_sunday", lazy_sunday), "Disco Inferno": ("disco_inferno", disco_inferno)}

if __name__ == "__main__":
    only = sys.argv[2:] if len(sys.argv) > 2 else None
    for title, (fname, fn) in SONGS.items():
        if only and fname not in only:
            continue
        song, kw = fn()
        audio = song.render(kw.pop("rev"), **kw)
        save_ogg(OUT / f"{fname}.ogg", audio, q=5)
        print(f"{title:14s} {len(audio) / SR:5.1f}s  rms {rms_db(audio):.1f} dB  peak {20 * np.log10(np.abs(audio).max()):.1f} dB")
