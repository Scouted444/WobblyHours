class_name Ambience
extends Node
## Makes the party feel alive: a background radio of happy songs (it fades out while the bedroom jukebox
## or your own dropped-in music is playing nearby) and birds chirping from spots all around you.
## Runs locally on every player; nothing here is networked.

const RADIO_LEVEL := 0.35       # background music sits under everything (times the Music setting)
const LOOPS_PER_SONG := 2
const FADE := 4.0

var world: Node3D
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _cur: AudioStreamPlayer
var _queue: Array = []
var _song_left := 0.0
var _duck := 1.0                # 1 = radio audible, 0 = faded out for the jukebox
var _xfade := 1.0               # 0..1 progress of the current cross-fade
var _bird_t := 2.0

func _ready() -> void:
	_a = _make_player()
	_b = _make_player()
	_next_song()

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.volume_db = -80.0
	add_child(p)
	return p

func _next_song() -> void:
	if _queue.is_empty():
		_queue = Sfx.RADIO.duplicate()
		_queue.shuffle()
	var title: String = _queue.pop_front()
	var st := Sfx.tune(title)
	if st == null:
		return
	var nxt := _b if _cur == _a else _a
	nxt.stream = st
	nxt.volume_db = -80.0
	nxt.play()
	_cur = nxt
	_xfade = 0.0
	_song_left = st.get_length() * LOOPS_PER_SONG

func _process(delta: float) -> void:
	_radio(delta)
	_birds(delta)

func _radio(delta: float) -> void:
	if _cur == null:
		return
	_song_left -= delta
	if _song_left <= FADE:
		_next_song()
	_xfade = minf(_xfade + delta / FADE, 1.0)
	_duck = move_toward(_duck, 0.0 if _music_playing_nearby() else 1.0, delta / 1.5)
	var base := Settings.music * RADIO_LEVEL * _duck
	var other := _a if _cur == _b else _b
	_cur.volume_db = linear_to_db(maxf(base * sin(_xfade * PI * 0.5), 0.0001))
	if other.playing:
		var out := base * cos(_xfade * PI * 0.5)
		other.volume_db = linear_to_db(maxf(out, 0.0001))
		if _xfade >= 1.0:
			other.stop()

## The jukebox (or a song you dropped on the window) takes over from the radio.
func _music_playing_nearby() -> bool:
	for n in get_tree().get_nodes_in_group("user_music"):
		if n is AudioStreamPlayer and (n as AudioStreamPlayer).playing:
			return true
	if world != null and world.has_method("jukebox_playing") and world.jukebox_playing():
		var cam := get_viewport().get_camera_3d()
		var juke = world.get("_juke")
		if cam == null or juke == null:
			return true
		return cam.global_position.distance_to((juke as Node3D).global_position) < 40.0
	return false

## Birds: a little song every few seconds from a random spot around you (in the trees, off to the side),
## sometimes answered by another bird somewhere else.
func _birds(delta: float) -> void:
	_bird_t -= delta
	if _bird_t > 0.0:
		return
	_bird_t = randf_range(1.2, 4.5)
	var cam := get_viewport().get_camera_3d()
	if cam == null or world == null:
		return
	var at := _bird_spot(cam.global_position)
	Sfx.play_at(world, "bird", at, randf_range(-6.0, 0.0))
	if randf() < 0.35:
		var at2 := _bird_spot(cam.global_position)
		get_tree().create_timer(randf_range(0.4, 1.0)).timeout.connect(func():
			if is_instance_valid(world):
				Sfx.play_at(world, "bird", at2, randf_range(-8.0, -2.0)))

func _bird_spot(around: Vector3) -> Vector3:
	var ang := randf() * TAU
	var dist := randf_range(8.0, 26.0)
	return around + Vector3(cos(ang) * dist, randf_range(3.0, 8.0), sin(ang) * dist)
