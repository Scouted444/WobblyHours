class_name Npc
extends CharacterBody3D
## A random passer-by built with the character maker. Wanders about, stands around, runs away when hurt,
## and keels over for good when its health runs out (shots, knives, bats, explosions, flying junk,
## or being run over by a cart or the toy car). The server moves it; everyone else follows the sync.

const WALK := 1.4
const RUN := 4.3
const GRAVITY := 18.0
const MAX_HP := 100

var owner_id := 0           # who spawned me (spawn limits)
var look_seed := 0          # same seed on every machine = same looks
var hp := MAX_HP
var dead := false           # synced
var move_speed := 0.0       # synced, drives the walk animation
var _body: NpcBody
var _target := Vector3.ZERO
var _think := 0.0
var _flee_from := Vector3.ZERO
var _flee_t := 0.0
var _dead_t := 0.0
var _fell := false
var _regrow_t := 0.0
var severed := 0          # limbs knocked off (bit mask, synced)
const LIMB_BITS := {"head": 1, "arm_l": 2, "arm_r": 4, "leg_l": 8, "leg_r": 16}

func _ready() -> void:
	add_to_group("npcs")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.875, 0)
	add_child(cs)
	_body = NpcBody.new()
	add_child(_body)
	_body.load_npc(NpcLook.random(look_seed))
	var cfg := SceneReplicationConfig.new()
	for path in [^".:position", ^".:rotation"]:
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path2 in [^".:dead", ^".:move_speed", ^".:severed"]:
		cfg.add_property(path2)
		cfg.property_set_replication_mode(path2, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	add_child(sync)
	_target = position
	_think = randf_range(0.5, 2.5)
	rotation.y = randf() * TAU

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_step(delta)
	_animate()

func _server_step(delta: float) -> void:
	if global_position.y < -20.0:
		queue_free()
		return
	if dead:
		_dead_t += delta
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		if _dead_t > 25.0:
			queue_free()
		return
	if severed != 0:
		_regrow_t += delta
		if _regrow_t >= 20.0:
			severed = 0   # good as new
			_regrow_t = 0.0
			_say.rpc("Ah, that's better.")
	var speed := WALK
	var want := Vector3.ZERO
	if _flee_t > 0.0:
		_flee_t -= delta
		var away := global_position - _flee_from
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		want = away.normalized()
		speed = RUN
	else:
		_think -= delta
		if _think <= 0.0:
			_think = randf_range(3.0, 7.0)
			if randf() < 0.35:
				_target = global_position   # stand around for a bit
			else:
				_target = global_position + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
		var to := _target - global_position
		to.y = 0.0
		if to.length() > 0.5:
			want = to.normalized()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.move_toward(want * speed, 10.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if is_on_wall() and _flee_t <= 0.0:
		_think = 0.0   # walked into something: pick another way
	if want.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-want.x, -want.z), clampf(8.0 * delta, 0.0, 1.0))
	move_speed = hv.length()

func _animate() -> void:
	if _body == null:
		return
	if dead:
		if not _fell:
			_fell = true
			collision_layer = 0
			_body.set_pose(1, 0)   # arms flung out as they go down
			var tw := create_tween()
			var side := -1.0 if (look_seed % 2) == 0 else 1.0
			tw.tween_property(_body, "rotation:x", side * PI * 0.5, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): _body.set_pose(0, 0))
		_body.animate(0.0, false)
		_body.set_severed(severed)
		return
	_body.set_severed(severed)
	_body.set_pose(0, 0)
	_body.animate(move_speed, false)

## Someone walked into me: get shuffled along (no harm done).
@rpc("any_peer", "call_local", "unreliable")
func nudge(vel: Vector3) -> void:
	if not multiplayer.is_server() or dead:
		return
	vel.y = 0.0
	velocity += vel.limit_length(5.0)
	if randf() < 0.08:
		_say.rpc(["Excuse me!", "Watch it!", "Rude.", "Hey!"][randi() % 4])

## LMB shove: stagger back and run off, a tiny bit of damage.
@rpc("any_peer", "call_local", "reliable")
func shove(vel: Vector3) -> void:
	if not multiplayer.is_server() or dead:
		return
	var by := multiplayer.get_remote_sender_id()
	damage(5, vel.limit_length(9.0), 1 if by == 0 else by)

@rpc("authority", "call_local", "unreliable")
func _say(text: String) -> void:
	_pop_label(text, Color(1.0, 1.0, 0.85))

## Server: take a hit. `by` is the peer who did it (they get run away from).
func damage(amount: int, push: Vector3, by := 0, at := Vector3.ZERO, blast := false, can_sever := true) -> void:
	if not multiplayer.is_server() or dead or not is_inside_tree():
		return
	hp -= maxi(amount, 1)
	# gore: work out which limb got hit and whether it comes off (shown only to people with gore on)
	var hit_at := at if at != Vector3.ZERO else global_position + Vector3.UP * 1.2
	var sever: Array[String] = []
	var limb := _limb_at(hit_at)
	var killing := hp <= 0
	if not can_sever:
		pass
	elif blast and killing:
		for l in ["arm_l", "arm_r", "leg_l", "leg_r", "head"]:
			if randf() < 0.35 and not (severed & int(LIMB_BITS[l])):
				sever.append(l)
	elif limb != "" and not (severed & int(LIMB_BITS[limb])) and (amount >= 34 and randf() < 0.45 or (killing and amount >= 25)):
		sever.append(limb)
	var world0 := get_tree().get_first_node_in_group("world") as GameWorld
	var cut: Array[String] = []
	for l2 in sever:
		if world0 != null and world0.sever_limb(self, l2, push):
			cut.append(l2)
	sever = cut
	if "head" in sever and not killing:
		hp = 0   # no head, no person
		killing = true
	if amount >= 10 or not sever.is_empty():
		_gore_fx.rpc(hit_at, push, sever, killing)
	velocity += push.limit_length(10.0)
	_flee_t = 5.0
	_flee_from = global_position - push
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null and by != 0:
		var who := world.get_node_or_null(str(by)) as Node3D
		if who != null:
			_flee_from = who.global_position
	if hp <= 0:
		dead = true
		_dead_t = 0.0
		collision_layer = 0   # the body stays on the ground, but people walk through it
	_hurt_fx.rpc(dead)

@rpc("authority", "call_local", "reliable")
func _hurt_fx(died: bool) -> void:
	Sfx.play_at(get_parent(), "thud", global_position + Vector3.UP, 2.0)
	var txt: String = ["OOF!", "OW!", "HEY!", "OUCH!", "WHY?!"][randi() % 5] if not died else ["x_x", "BLEH", "OOF..."][randi() % 3]
	_pop_label(txt, Color(1.0, 0.3, 0.25) if not died else Color(0.8, 0.8, 0.85))

func _pop_label(text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	get_parent().add_child(l)
	l.global_position = global_position + Vector3(0, 2.1, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.8, 0), 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.tween_callback(l.queue_free)

## Which limb is at this world point (head / arm_l / arm_r / leg_l / leg_r, or "" for the body).
func _limb_at(p: Vector3) -> String:
	var lp := to_local(p)
	if lp.y > 1.45:
		return "head"
	if lp.y > 0.95:
		if absf(lp.x) < 0.17:
			return ""
		return "arm_l" if lp.x < 0.0 else "arm_r"
	return "leg_l" if lp.x < 0.0 else "leg_r"

@rpc("authority", "call_local", "reliable")
func _gore_fx(at: Vector3, push: Vector3, sever: Array, died: bool) -> void:
	if not Settings.gore or _body == null:
		return
	var world := get_parent() as Node3D
	if world == null:
		return
	Gore.burst(world, at, push + Vector3.UP * 1.5, 26 if sever.is_empty() else 45)
	Gore.splat(world, Vector3(at.x, global_position.y, at.z), 0.25)
	for l in sever:
		Gore.burst(world, _body.limb_origin(str(l)), Vector3.UP + push * 0.2, 40)
	if died:
		world.get_tree().create_timer(0.7).timeout.connect(func():
			if is_instance_valid(self):
				Gore.splat(world, global_position, 0.9))

## "skin|hair" colours for a body part torn off me.
func tint_string() -> String:
	if _body == null:
		return ""
	return _body.skin_color().to_html(false) + "|" + _body.hair_color().to_html(false)
