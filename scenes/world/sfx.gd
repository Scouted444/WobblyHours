class_name Sfx
extends RefCounted
## Sound effects and music.
##   Sfx.play_at(node, "shot", pos)   positional
##   Sfx.play_ui(node, "click")        non-positional
##   Sfx.tune_async("Pool Party", cb)  cb(stream) gets a looping song
##
## Sounds are real recordings (Kenney's CC0 foley packs) plus a few carefully synthesised ones, and the songs
## are fully mixed tracks; all of it lives in res://audio/. tools/audio/ has the scripts that build them.
## Every sound has a few takes and a random one plays each time, so nothing sounds copy-pasted.

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"

## How many takes each sound has (<kind>_0.ogg ... <kind>_N-1.ogg).
const VARIANTS := {
	"alarm": 1, "bird": 8, "boost_end": 2, "booster": 1, "bleep": 2, "boing": 3, "boom": 3, "boot": 1, "burp": 3, "chat": 2, "click": 3, "coins": 2,
	"crash": 4, "ding": 1, "error": 1, "glass": 5, "glug": 2, "honk": 2, "hover": 2, "jump": 4, "land": 5,
	"launch": 2, "nom": 2, "pickup": 5, "pop": 2, "puff": 2, "shot": 3, "splash": 3, "stab": 2,
	"step_carpet": 5, "step_concrete": 5, "step_grass": 5, "step_wood": 5, "throw": 3, "thud": 8, "whoosh": 4}

## Loudness trim per sound (dB), added to whatever the caller asks for, so the whole mix sits together.
const TRIM := {"bird": 0.0, "click": 4.0, "hover": 4.0, "chat": 3.0, "bleep": 2.0, "step": 2.0, "jump": 2.0, "pickup": 2.0,
	"boom": -1.0, "launch": -2.0, "alarm": -2.0}

## How much random pitch each sound gets (recordings sound natural with a little, UI sounds get none).
const PITCH_JITTER := {"bird": 0.08, "click": 0.0, "hover": 0.0, "ding": 0.0, "error": 0.0, "boot": 0.0, "chat": 0.0,
	"coins": 0.02, "alarm": 0.0, "honk": 0.02}

## At most this many copies of one sound can play at once (stops 16 players' footsteps or a pile-up of
## crashes from stacking into a wall of noise).
const MAX_VOICES := 6

## Songs: jukebox name -> file in MUSIC_DIR.
const TUNES := {
	"Menu Groove": "menu_groove", "Pool Party": "pool_party", "Boss Fight": "boss_fight",
	"Sunset Drive": "sunset_drive", "Lazy Sunday": "lazy_sunday", "Disco Inferno": "disco_inferno",
	"Sunny Afternoon": "sunny_afternoon", "Backyard Bounce": "backyard_bounce", "Cannonball": "cannonball"}
const TUNE_NAMES := ["Sunny Afternoon", "Backyard Bounce", "Cannonball", "Pool Party", "Menu Groove",
	"Disco Inferno", "Sunset Drive", "Lazy Sunday", "Boss Fight"]
## The in-game background radio plays these (the happy ones), shuffled.
const RADIO := ["Sunny Afternoon", "Backyard Bounce", "Cannonball", "Pool Party", "Menu Groove"]

static var _cache := {}
static var _last := {}      # kind -> last take played, so the same take never plays twice in a row
static var _voices := {}    # kind -> how many are playing right now
static var _buses_ready := false

# ------------------------------------------------------------------ playing
## `far` raises the distance a sound can be heard from (explosions).
static func play_at(parent: Node, kind: String, pos: Vector3, volume_db := 0.0, far := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if kind == "step":
		kind = "step_" + surface_at(pos)
	var st := _pick(kind)
	if st == null or not _take_voice(kind):
		return
	_setup_buses()
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = volume_db + _trim(kind) + randf_range(-1.5, 1.0)
	# Space: full left/right panning (Godot's project default only pans half way), a quicker fall-off
	# with distance, and distant sounds get duller - so you can hear *where* things happen.
	p.panning_strength = 2.0
	p.unit_size = 3.5 * far
	p.max_distance = 60.0 * far
	p.attenuation_filter_cutoff_hz = 4500.0
	p.attenuation_filter_db = -20.0
	var j: float = PITCH_JITTER.get(kind, 0.04)
	p.pitch_scale = randf_range(1.0 - j, 1.0 + j)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(_done.bind(p, kind))
	p.play()

## Non-positional sound (menus, computer).
static func play_ui(parent: Node, kind: String, volume_db := -4.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var st := _pick(kind)
	if st == null or not _take_voice(kind):
		return
	_setup_buses()
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = volume_db + _trim(kind)
	parent.add_child(p)
	p.finished.connect(_done.bind(p, kind))
	p.play()

static func _trim(kind: String) -> float:
	if kind.begins_with("step_"):
		kind = "step"
	return TRIM.get(kind, 0.0)

static func _take_voice(kind: String) -> bool:
	var n: int = _voices.get(kind, 0)
	if n >= MAX_VOICES:
		return false
	_voices[kind] = n + 1
	return true

static func _done(p: Node, kind: String) -> void:
	_voices[kind] = maxi(int(_voices.get(kind, 1)) - 1, 0)
	if is_instance_valid(p):
		p.queue_free()

## A random take of this sound (never the same one twice in a row).
static func _pick(kind: String) -> AudioStream:
	var n: int = VARIANTS.get(kind, 0)
	if n <= 0:
		push_warning("Sfx: unknown sound '%s'" % kind)
		return null
	var i := randi() % n
	if n > 1 and i == _last.get(kind, -1):
		i = (i + 1 + randi() % (n - 1)) % n
	_last[kind] = i
	var path := "%s%s_%d.ogg" % [SFX_DIR, kind, i]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

## Makes the "SFX" and "Music" buses (once): a soft room on effects so they sit in the world together, and a
## limiter on the master so nothing - not even five explosions at once - can get painfully loud.
static func _setup_buses() -> void:
	if _buses_ready:
		return
	_buses_ready = true
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		var hl: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter")
		hl.set("ceiling_db", -1.0)
		hl.set("pre_gain_db", 0.0)
		AudioServer.add_bus_effect(0, hl)
	else:
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -1.0
		lim.threshold_db = -3.0
		AudioServer.add_bus_effect(0, lim)
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, &"Master")
	# The effects bus is mixed to sit *under* the music: a bit quieter, gently compressed so no single
	# sound jumps out, and no reverb (the sounds are dry; distance and panning give the space).
	var sfx := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx, -4.0)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -20.0
	comp.ratio = 3.0
	comp.attack_us = 4000.0
	comp.release_ms = 160.0
	comp.gain = 1.0
	AudioServer.add_bus_effect(sfx, comp)
	var shelf := AudioEffectHighShelfFilter.new()   # one more gentle treble roll-off for the whole bus
	shelf.cutoff_hz = 5000.0
	shelf.gain = 0.7
	AudioServer.add_bus_effect(sfx, shelf)

# ------------------------------------------------------------------ footstep surfaces
## Floors register themselves here (see HouseBuilder._b and Town._flat) so footsteps can sound like wood,
## carpet, grass or concrete. Each entry: [weakref(node), local Rect2 on xz, local top y, surface, global cache].
static var _floors: Array = []

static func add_floor(node: Node3D, center: Vector3, size: Vector3, mat: Material) -> void:
	if node == null or mat == null or not mat.has_meta("surface"):
		return
	var r := Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)
	_floors.append([weakref(node), r, center.y + size.y * 0.5, String(mat.get_meta("surface")), null])

## Surface under a world position: the highest registered floor just under the feet.
static func surface_at(pos: Vector3) -> String:
	var best := "concrete"
	var best_y := -INF
	var i := 0
	while i < _floors.size():
		var f: Array = _floors[i]
		var node := (f[0] as WeakRef).get_ref() as Node3D
		if node == null:
			_floors.remove_at(i)
			continue
		i += 1
		if f[4] == null:
			if not node.is_inside_tree():
				continue
			var r: Rect2 = f[1]
			var xf := node.global_transform
			var a := xf * Vector3(r.position.x, f[2], r.position.y)
			var b := xf * Vector3(r.end.x, f[2], r.end.y)
			f[4] = [Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z))), a.y]
		var g: Array = f[4]
		var top: float = g[1]
		if top > pos.y + 0.35 or top < pos.y - 0.6 or top <= best_y:
			continue
		var area: Rect2 = g[0]
		if area.has_point(Vector2(pos.x, pos.z)):
			best = f[3]
			best_y = top
	return best

## A looping sound (the rocket booster roar). Its own copy, so the one-shot cache isn't affected.
static func loop_stream(kind: String) -> AudioStream:
	var key := "loop_" + kind
	if not _cache.has(key):
		var st: AudioStream = load("%s%s_0.ogg" % [SFX_DIR, kind])
		if st is AudioStreamOggVorbis:
			st = st.duplicate()
			(st as AudioStreamOggVorbis).loop = true
		_cache[key] = st
	return _cache[key]

# ------------------------------------------------------------------ music
## Calls on_ready(stream) with a looping song (deferred, like the old background renderer).
static func tune_async(name: String, on_ready: Callable) -> void:
	var st := tune(name)
	if st != null:
		on_ready.call_deferred(st)

static func tune(name: String) -> AudioStream:
	if not TUNES.has(name):
		return null
	var key := "tune_" + name
	if not _cache.has(key):
		_setup_buses()
		var st: AudioStream = load(MUSIC_DIR + String(TUNES[name]) + ".ogg")
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		_cache[key] = st
	return _cache[key]
