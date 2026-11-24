class_name CustomBody
extends Node3D
## A player model loaded from a .glb (Workshop character). Fitted to 1.8 m tall, feet at the
## origin, facing -Z. Plays the model's own walk/idle animation if it has one.

var model_id := ""
var _anim: AnimationPlayer
var _walk := ""
var _idle := ""
var _playing := ""

func load_model(id: String) -> bool:
	var scene := Content.load_scene(Content.path_of(id))
	if scene == null:
		return false
	model_id = id
	var holder := Node3D.new()
	holder.rotation.y = PI  # glTF models face +Z, the game faces -Z
	add_child(holder)
	holder.add_child(scene)
	for cam in scene.find_children("*", "Camera3D", true, false):
		cam.queue_free()
	var box := Content.scene_aabb(scene)
	if box.size.y < 0.001:
		return false
	var s := 1.8 / box.size.y
	scene.scale = Vector3.ONE * s
	scene.position = Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5)) * s
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0] as AnimationPlayer
		for n in _anim.get_animation_list():
			var low := String(n).to_lower()
			if _idle.is_empty() and "idle" in low:
				_idle = n
			elif _walk.is_empty() and ("walk" in low or "run" in low):
				_walk = n
		if _walk.is_empty():  # a lone unnamed clip is most likely the walk cycle
			for n in _anim.get_animation_list():
				if n != _idle and String(n) != "RESET":
					_walk = n
					break
		for n in [_walk, _idle]:
			if not String(n).is_empty():
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return true

func animate(speed: float, ragdolled: bool) -> void:
	if _anim == null:
		return
	var want := ""
	if not ragdolled and speed > 0.3 and not _walk.is_empty():
		want = _walk
	elif not ragdolled and not _idle.is_empty():
		want = _idle
	if want != _playing:
		_playing = want
		if want.is_empty():
			_anim.stop()
		else:
			_anim.play(want)
	if not want.is_empty() and want == _walk:
		_anim.speed_scale = clampf(speed / 3.0, 0.5, 2.2)
