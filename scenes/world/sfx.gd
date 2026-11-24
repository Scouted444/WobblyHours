class_name Sfx
extends RefCounted
## Procedural sound effects and chiptune songs (no audio files needed).
##   Sfx.play_at(node, "shot", pos)   positional
##   Sfx.play_ui(node, "click")        non-positional
##   Sfx.tune_async("Pool Party", cb)  songs are rendered on a thread, then cb(stream) is called

const RATE := 22050
static var _cache := {}
static var _threads: Array = []

# ------------------------------------------------------------------ playing
## `far` raises the distance a sound can be heard from (explosions).
static func play_at(parent: Node, kind: String, pos: Vector3, volume_db := 0.0, far := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(kind)
	p.volume_db = volume_db
	p.unit_size = 8.0 * far
	p.max_distance = 70.0 * far
	p.pitch_scale = randf_range(0.94, 1.06)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

## Non-positional sound (menus, computer).
static func play_ui(parent: Node, kind: String, volume_db := -4.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = _stream(kind)
	p.volume_db = volume_db
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

static func _stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = _pcm(_samples(kind))
	_cache[kind] = s
	return s

static func _pcm(samples: PackedFloat32Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	return b

# ------------------------------------------------------------ sound effects
static func _dur(kind: String) -> float:
	match kind:
		"shot": return 0.5
		"whoosh": return 0.35
		"throw": return 0.22
		"stab": return 0.16
		"nom": return 0.5
		"burp": return 0.65
		"bleep": return 0.18
		"puff": return 0.5
		"glug": return 0.55
		"click": return 0.05
		"hover": return 0.035
		"ding": return 0.9
		"error": return 0.32
		"boot": return 1.3
		"pop": return 0.2
		"step": return 0.13
		"land": return 0.28
		"jump": return 0.2
		"splash": return 0.95
		"boing": return 0.8
		"thud": return 0.32
		"boom": return 1.8
		"launch": return 1.1
		"honk": return 0.55
		"pickup": return 0.22
		"chat": return 0.18
	return 0.3

static func _samples(kind: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var dur := _dur(kind)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var ph2 := 0.0
	var bub_t := -1.0
	var bub_f := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match kind:
			"shot":
				lp = lerpf(lp, noise, 0.45)
				lp2 = lerpf(lp2, noise, 0.05)
				ph += TAU * (55.0 + 130.0 * exp(-t * 22.0)) / RATE
				v = noise * exp(-t * 140.0) * 0.9 + lp * exp(-t * 28.0) * 0.8 + sin(ph) * exp(-t * 11.0) * 0.9 + lp2 * exp(-t * 7.0) * 0.9
			"whoosh":
				var env := pow(sin(PI * t / dur), 2.0)
				lp = lerpf(lp, noise, lerpf(0.04, 0.4, t / dur))
				v = lp * env * 2.6
			"throw":
				var env2 := pow(sin(PI * t / dur), 1.5)
				lp = lerpf(lp, noise, lerpf(0.3, 0.06, t / dur))
				v = lp * env2 * 2.0
			"stab":
				v = noise * exp(-t * 70.0) * 0.5 + sin(TAU * 2200.0 * t) * exp(-t * 45.0) * 0.3 + sin(TAU * 3300.0 * t) * exp(-t * 60.0) * 0.2
			"nom":
				var c := fmod(t, 0.16)
				lp = lerpf(lp, noise, 0.4)
				v = (lp * exp(-c * 34.0) * 1.7 + sin(TAU * 130.0 * c) * exp(-c * 30.0) * 0.4) * (1.0 if t < 0.48 else 0.0)
			"burp":
				var f := 88.0 - 34.0 * t / dur
				ph += TAU * f / RATE
				var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
				lp = lerpf(lp, saw, 0.22)
				v = lp * (0.55 + 0.45 * sin(TAU * 27.0 * t)) * sin(PI * t / dur) * 1.5
			"bleep":
				var f2 := 880.0 if t < 0.08 else 1320.0
				ph += TAU * f2 / RATE
				lp = lerpf(lp, 1.0 if sin(ph) > 0.0 else -1.0, 0.35)
				v = lp * 0.3 * exp(-fmod(t, 0.08) * 9.0)
			"puff":
				lp = lerpf(lp, noise, lerpf(0.25, 0.04, t / dur))
				v = lp * 2.0 * sin(PI * t / dur)
			"glug":
				var lt := fmod(t, 0.18)
				var fg := 220.0 + 800.0 * lt
				v = sin(TAU * fg * lt) * exp(-lt * 15.0) * 0.55 * (1.0 if t < 0.5 else 0.0)
			"click":
				lp = lerpf(lp, noise, 0.5)
				v = sin(TAU * 1800.0 * t) * exp(-t * 110.0) * 0.4 + lp * exp(-t * 300.0) * 0.3
			"hover":
				v = sin(TAU * 1100.0 * t) * exp(-t * 140.0) * 0.16
			"ding":
				v = (sin(TAU * 880.0 * t) * 0.5 + sin(TAU * 1760.0 * t) * 0.25 * exp(-t * 3.0) + sin(TAU * 2217.0 * t) * 0.18 * exp(-t * 6.0)) * exp(-t * 4.5) * 0.7
			"error":
				ph += TAU * (196.0 if t < 0.15 else 147.0) / RATE
				lp = lerpf(lp, fmod(ph / TAU, 1.0) * 2.0 - 1.0, 0.3)
				v = lp * 0.4 * (1.0 - t / dur) * (1.0 if fmod(t, 0.15) < 0.12 else 0.0)
			"boot":
				var step_i := mini(int(t / 0.2), 4)
				var fr: float = [523.25, 659.25, 783.99, 1046.5, 1318.5][step_i]
				var lt2 := t - step_i * 0.2
				var tri := absf(fmod(t * fr, 1.0) * 2.0 - 1.0) * 2.0 - 1.0
				var shimmer := sin(TAU * fr * 2.0 * t) * 0.15
				var tail := 1.0 if step_i < 4 else exp(-lt2 * 3.5)
				v = (tri * 0.3 + shimmer) * exp(-lt2 * 4.0) * tail + (sin(TAU * 130.8 * t) * 0.12 * exp(-t * 2.0))
			"pop":
				ph += TAU * (520.0 * exp(-t * 28.0) + 110.0) / RATE
				v = noise * exp(-t * 90.0) * 0.8 + sin(ph) * exp(-t * 26.0) * 0.8
			"step":
				lp = lerpf(lp, noise, 0.18)
				v = lp * exp(-t * 50.0) * 1.6 + sin(TAU * 90.0 * t) * exp(-t * 55.0) * 0.5
			"land":
				lp = lerpf(lp, noise, 0.09)
				v = lp * exp(-t * 20.0) * 2.2 + sin(TAU * (75.0 - 30.0 * t) * t) * exp(-t * 18.0) * 0.8
			"jump":
				lp = lerpf(lp, noise, 0.12)
				ph += TAU * (260.0 + 900.0 * t) / RATE
				v = lp * 0.5 * pow(sin(PI * t / dur), 0.7) + sin(ph) * exp(-t * 16.0) * 0.18
			"splash":
				lp = lerpf(lp, noise, 0.3)
				lp2 = lerpf(lp2, noise, 0.06)
				var senv := (1.0 - exp(-t * 80.0)) * exp(-t * 4.5)
				v = lp * senv * 1.1 + lp2 * exp(-t * 3.0) * 0.9
				if bub_t < 0.0 and rng.randf() < 0.0009 * exp(-t * 1.5):
					bub_t = 0.0
					bub_f = rng.randf_range(300.0, 900.0)
				if bub_t >= 0.0:
					v += sin(TAU * (bub_f + 1500.0 * bub_t) * bub_t) * exp(-bub_t * 40.0) * 0.4
					bub_t += 1.0 / RATE
					if bub_t > 0.12:
						bub_t = -1.0
			"boing":
				var bf := 150.0 + 330.0 * exp(-t * 7.0)
				bf *= 1.0 + 0.22 * sin(TAU * 16.0 * t) * exp(-t * 3.0)
				ph += TAU * bf / RATE
				v = (sin(ph) + 0.4 * sin(ph * 2.0) + 0.2 * sin(ph * 3.0)) * exp(-t * 4.5) * 0.5 * minf(t * 400.0, 1.0)
			"thud":
				lp = lerpf(lp, noise, 0.1)
				ph += TAU * (120.0 - 70.0 * t / dur) / RATE
				v = sin(ph) * exp(-t * 15.0) * 1.0 + lp * exp(-t * 55.0) * 0.8
			"boom":
				lp = lerpf(lp, noise, lerpf(0.5, 0.02, minf(t / 0.9, 1.0)))
				ph += TAU * (28.0 + 80.0 * exp(-t * 6.0)) / RATE
				v = lp * exp(-t * 3.2) * 2.4 + sin(ph) * exp(-t * 4.0) * 1.2 + noise * exp(-t * 80.0) * 1.0
				v = tanh(v * 1.4)
			"launch":
				lp = lerpf(lp, noise, lerpf(0.5, 0.05, minf(t / 0.6, 1.0)))
				v = lp * (1.0 - exp(-t * 40.0)) * exp(-t * 2.4) * 2.4 + sin(TAU * 62.0 * t) * exp(-t * 4.0) * 0.5 + noise * exp(-t * 110.0) * 0.8
				v = tanh(v * 1.2)
			"honk":
				ph += TAU * 392.0 / RATE
				ph2 += TAU * 494.0 / RATE
				var sq := (1.0 if sin(ph) > 0.0 else -1.0) + (1.0 if sin(ph2) > 0.0 else -1.0)
				lp = lerpf(lp, sq, 0.2)
				v = lp * 0.22 * minf(t * 300.0, 1.0) * (1.0 if t < 0.4 else exp(-(t - 0.4) * 30.0))
			"pickup":
				var pf := 660.0 if t < 0.09 else 990.0
				v = sin(TAU * pf * t) * 0.3 * exp(-fmod(t, 0.09) * 14.0)
			"chat":
				var cf := 1000.0 if t < 0.07 else 1500.0
				var ct := fmod(t, 0.07)
				v = (absf(fmod(ct * cf, 1.0) * 2.0 - 1.0) * 2.0 - 1.0) * 0.22 * exp(-ct * 20.0)
		# short fades keep the ends of every sound from clicking
		v *= minf(t * 1000.0, 1.0) * minf((dur - t) * 200.0, 1.0)
		out[i] = v
	return out

# ------------------------------------------------------------------ chiptunes
const CHORDS := {
	"maj": [0, 4, 7], "min": [0, 3, 7], "maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "dom7": [0, 4, 7, 10]}

## Drum patterns: 8 eighth-note steps per bar, as [kick, snare, hat]. x = hit.
const DRUMS := {
	"four": ["x.x.x.x.", "..x...x.", ".x.x.x.x"],
	"pop": ["x..x..x.", "..x...x.", "xxxxxxxx"],
	"half": ["x.....x.", "....x...", "x.x.x.x."],
	"driv": ["x.x.x.xx", "..x...x.", "xxxxxxxx"],
	"none": ["........", "........", "........"]}

## notes: semitones above C4. 99 = rest, 98 = keep holding the previous note. 8 eighth notes per bar.
## chords: [root semitones, type] per bar.
const TUNES := {
	"Menu Groove": {
		"bpm": 124.0, "drums": "pop", "wave": "pulse", "duty": 0.25, "bass": "pluck", "arp": 0.07,
		"chords": [[0, "maj"], [9, "min"], [5, "maj"], [7, "maj"], [0, "maj"], [9, "min"], [5, "maj"], [7, "maj"]],
		"lead": [12, 99, 16, 19, 24, 19, 16, 19,  21, 99, 16, 12, 16, 21, 24, 21,  17, 99, 21, 24, 29, 24, 21, 17,  19, 99, 23, 26, 31, 26, 23, 19,
				24, 23, 24, 19, 16, 19, 24, 99,  21, 24, 28, 24, 21, 16, 12, 16,  17, 21, 24, 21, 17, 21, 24, 29,  26, 23, 19, 23, 26, 31, 26, 19]},
	"Pool Party": {
		"bpm": 108.0, "drums": "half", "wave": "pulse", "duty": 0.5, "bass": "pluck", "arp": 0.05,
		"chords": [[7, "maj"], [4, "min"], [0, "maj"], [2, "maj"], [7, "maj"], [4, "min"], [0, "maj"], [2, "maj"]],
		"lead": [14, 99, 14, 16, 19, 99, 16, 14,  16, 99, 16, 19, 16, 14, 11, 14,  12, 99, 16, 19, 24, 99, 19, 16,  14, 16, 18, 21, 18, 16, 14, 99,
				19, 98, 16, 14, 11, 14, 16, 19,  16, 98, 99, 14, 16, 19, 21, 19,  19, 16, 12, 16, 19, 24, 98, 99,  21, 18, 14, 18, 21, 26, 98, 99]},
	"Boss Fight": {
		"bpm": 156.0, "drums": "driv", "wave": "saw", "duty": 0.5, "bass": "pluck", "arp": 0.05,
		"chords": [[-3, "min"], [-7, "maj"], [-5, "maj"], [-8, "maj"], [-3, "min"], [-7, "maj"], [-5, "maj"], [-8, "maj"]],
		"lead": [21, 21, 19, 21, 24, 21, 19, 16,  17, 17, 16, 17, 21, 17, 16, 12,  19, 19, 17, 19, 23, 19, 17, 14,  16, 16, 15, 16, 20, 23, 20, 16,
				24, 21, 24, 28, 24, 21, 19, 21,  21, 17, 21, 24, 21, 17, 16, 17,  23, 19, 23, 26, 23, 19, 17, 19,  20, 23, 28, 26, 23, 20, 16, 99]},
	"Sunset Drive": {
		"bpm": 98.0, "drums": "pop", "wave": "pulse", "duty": 0.5, "bass": "pluck", "arp": 0.08,
		"chords": [[2, "min"], [-2, "maj"], [5, "maj"], [0, "maj"], [2, "min"], [-2, "maj"], [5, "maj"], [0, "maj"]],
		"lead": [21, 98, 98, 98, 17, 98, 19, 21,  22, 98, 98, 98, 17, 98, 14, 17,  21, 98, 98, 98, 24, 98, 21, 17,  19, 98, 98, 16, 19, 98, 16, 12,
				26, 98, 98, 98, 24, 98, 21, 98,  22, 98, 21, 98, 17, 98, 22, 98,  24, 98, 98, 98, 21, 98, 17, 98,  19, 98, 16, 98, 12, 98, 99, 99]},
	"Lazy Sunday": {
		"bpm": 84.0, "drums": "half", "wave": "tri", "duty": 0.5, "bass": "pluck", "arp": 0.09,
		"chords": [[0, "maj7"], [9, "min7"], [2, "min7"], [7, "dom7"], [0, "maj7"], [9, "min7"], [2, "min7"], [7, "dom7"]],
		"lead": [16, 98, 19, 98, 23, 98, 19, 16,  16, 98, 21, 98, 19, 98, 16, 12,  17, 98, 21, 98, 24, 98, 21, 17,  19, 98, 17, 98, 14, 98, 11, 99,
				24, 98, 23, 98, 19, 98, 16, 19,  21, 98, 19, 98, 16, 98, 12, 16,  21, 98, 17, 98, 14, 98, 17, 21,  19, 98, 23, 98, 19, 98, 17, 14]},
	"Disco Inferno": {
		"bpm": 120.0, "drums": "four", "wave": "pulse", "duty": 0.5, "bass": "octave", "arp": 0.04,
		"chords": [[4, "min"], [9, "min"], [2, "maj"], [7, "maj"], [4, "min"], [9, "min"], [2, "maj"], [7, "maj"]],
		"lead": [16, 99, 19, 16, 99, 19, 21, 19,  21, 99, 24, 21, 99, 24, 23, 21,  18, 99, 21, 18, 99, 21, 23, 21,  19, 99, 23, 19, 99, 23, 26, 23,
				28, 99, 26, 23, 99, 21, 19, 16,  24, 99, 21, 24, 99, 28, 26, 24,  26, 99, 23, 21, 99, 18, 21, 23,  23, 99, 26, 31, 99, 26, 23, 19]},
}
const TUNE_NAMES := ["Menu Groove", "Pool Party", "Boss Fight", "Sunset Drive", "Lazy Sunday", "Disco Inferno"]

## Synchronous version (renders on the calling thread; takes a moment the first time).
static func tune(name: String) -> AudioStreamWAV:
	var key := "tune_" + name
	if _cache.has(key):
		return _cache[key]
	return _make_tune(name, _render_tune(name))

## Renders on a background thread, then calls on_ready(stream) on the main thread.
static func tune_async(name: String, on_ready: Callable) -> void:
	var key := "tune_" + name
	if _cache.has(key):
		on_ready.call(_cache[key])
		return
	var th := Thread.new()
	_threads.append(th)
	th.start(func():
		var pcm := _render_tune(name)
		var done := _tune_done.bind(name, pcm, th, on_ready)
		done.call_deferred())

static func _tune_done(name: String, pcm: PackedByteArray, th: Thread, on_ready: Callable) -> void:
	th.wait_to_finish()
	_threads.erase(th)
	var s := _make_tune(name, pcm)
	if on_ready.is_valid():
		on_ready.call(s)

static func _make_tune(name: String, pcm: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = pcm
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = pcm.size() / 2
	_cache["tune_" + name] = s
	return s

static func _hz(semis: float) -> float:
	return 261.63 * pow(2.0, semis / 12.0)

static func _wave(kind: String, ph: float, duty: float) -> float:
	var p := fmod(ph, 1.0)
	match kind:
		"saw":
			return p * 2.0 - 1.0
		"tri":
			return absf(p * 2.0 - 1.0) * 2.0 - 1.0
	return 1.0 if p < duty else -1.0

## Pure function of the song (safe to call from a thread).
static func _render_tune(name: String) -> PackedByteArray:
	var d: Dictionary = TUNES[name]
	var lead: Array = d["lead"]
	var chords: Array = d["chords"]
	var step := 60.0 / float(d["bpm"]) / 2.0
	var steps := lead.size()
	var wave: String = d["wave"]
	var duty: float = d["duty"]
	var arp_vol: float = d["arp"]
	var octave_bass: bool = d["bass"] == "octave"
	var drum: Array = DRUMS[d["drums"]]

	# resolve held notes: which note each step plays and when it started
	var note_at: Array = []
	var start_at: Array = []
	for s in steps:
		var nv: int = lead[s]
		if nv == 98 and s > 0:
			note_at.append(note_at[s - 1])
			start_at.append(start_at[s - 1])
		else:
			note_at.append(nv)
			start_at.append(s)

	var n := int(step * steps * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = name.hash()
	var prev_noise := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := mini(int(t / step), steps - 1)
		var k := s % 8
		var bar := s / 8
		var local := t - s * step
		var v := 0.0

		# lead
		var nt: int = note_at[s]
		if nt != 99:
			var lt := t - float(start_at[s]) * step
			var f := _hz(nt)
			f *= 1.0 + 0.006 * sin(TAU * 5.5 * lt) * clampf((lt - 0.15) * 4.0, 0.0, 1.0)
			var decay := 1.3 if wave == "tri" else 2.6
			v += _wave(wave, t * f, duty) * 0.17 * minf(lt * 160.0, 1.0) * exp(-lt * decay)

		# chord arpeggio
		var ch: Array = chords[bar % chords.size()]
		var tones: Array = CHORDS[ch[1]]
		if arp_vol > 0.0:
			var tone: int = tones[k % tones.size()]
			var af := _hz(float(int(ch[0]) + tone + 12))
			v += _wave("pulse", t * af, 0.125) * arp_vol * exp(-local * 8.0)

		# bass
		var bnote: int = int(ch[0]) - 24
		while bnote < -29:
			bnote += 12
		var play_bass := false
		if octave_bass:
			play_bass = true
			if k % 2 == 1:
				bnote += 12
		else:
			play_bass = k == 0 or k == 3 or k == 4 or k == 6
		if play_bass:
			var bf := _hz(float(bnote))
			var tri := absf(fmod(t * bf, 1.0) * 2.0 - 1.0) * 2.0 - 1.0
			var sq := _wave("pulse", t * bf, 0.5)
			var benv := exp(-local * (7.0 if octave_bass else 3.5)) * minf(local * 300.0, 1.0)
			v += (tri * 0.3 + sq * 0.04) * benv

		# drums
		var noise := rng.randf_range(-1.0, 1.0)
		if (drum[0] as String)[k] == "x" and local < 0.3:
			v += sin(TAU * (45.0 * local + 5.0 * (1.0 - exp(-local * 30.0)))) * exp(-local * 13.0) * 0.55
		if (drum[1] as String)[k] == "x" and local < 0.25:
			v += (noise * 0.28 + sin(TAU * 185.0 * local) * 0.2) * exp(-local * 22.0)
		if (drum[2] as String)[k] == "x" and local < 0.08:
			v += (noise - prev_noise) * 0.16 * exp(-local * 75.0)
		prev_noise = noise

		out[i] = tanh(v * 1.15) * 0.9
	return _pcm(out)
