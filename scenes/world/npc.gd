class_name Npc
extends CharacterBody3D
## A person built with the character maker. Spawned ones wander about; townspeople ("residents") walk
## the pavements of the town. Everyone reacts to what you do and say:
##   - hurt them, shoot near them or blow something up and they scream and run (a few brave ones
##     fight back and chase you down with their fists, and hold a grudge)
##   - point a gun at them and their hands go up
##   - F talks to them; they answer chat (hello, sorry, dance, follow me, insults, questions...)
## The server runs all of this; everyone else follows the sync (position, act, dead, severed).

const WALK := 1.4
const RUN := 4.3
const GRAVITY := 18.0
const MAX_HP := 100
const LIMB_BITS := {"head": 1, "arm_l": 2, "arm_r": 4, "leg_l": 8, "leg_r": 16}
const NAMES := ["Gary", "Linda", "Dave", "Sharon", "Kevin", "Brenda", "Steve", "Karen", "Doug", "Tina", "Barry",
	"Pam", "Rick", "Debbie", "Carl", "Wendy", "Phil", "Janet", "Terry", "Gloria", "Nigel", "Fran", "Bob", "Marge",
	"Stan", "Rita", "Lenny", "Joy", "Earl", "Bev", "Gus", "Dot", "Vince", "Nora", "Mo", "Ida"]

## act (synced): what the body is doing
const ACT_NONE := 0
const ACT_HANDS_UP := 1
const ACT_DANCE := 2
const ACT_PUNCH := 3

var owner_id := 0           # who spawned me (spawn limits); 0 = the town
var look_seed := 0          # same seed on every machine = same looks and name
var resident := false       # a townsperson (walks the pavements, respawns)
var troublemaker := false   # a job target: picks fights with everyone
var hp := MAX_HP
var dead := false           # synced
var move_speed := 0.0       # synced, drives the walk animation
var severed := 0            # limbs knocked off (bit mask, synced)
var act := 0                # synced
var npc_name := ""
var brave := false
var _body: NpcBody
var _target := Vector3.ZERO
var _think := 0.0
var _flee_from := Vector3.ZERO
var _flee_t := 0.0
var _dead_t := 0.0
var _fell := false
var _regrow_t := 0.0
# townsperson brain (server)
var path: Array = []        # pavement waypoints
var path_loop := true
var _wp := 0
var _wp_dir := 1
var _stuck_t := 0.0
var hostile := 0            # peer id I'm fighting
var _hostile_t := 0.0
var _punch_cd := 0.0
var _act_t := 0.0
var _follow := 0
var _follow_t := 0.0
var _stop_t := 0.0          # standing still (talking)
var _face := Vector3.ZERO
var grudge := {}            # peer id -> how annoyed I am (0..)
var _say_cd := 0.0
var _vis_t := 0.0
# ragdoll: the server simulates it and sends the part poses (rag_pose, empty when standing)
var rag_pose := PackedFloat32Array()   # synced
var _rig: PlayerRig
var _ragdoll: PlayerRagdoll
var _rag_t := 0.0
var _still_t := 0.0
var _rag_shown := false
const TORSO_Y := 1.22

func _ready() -> void:
	add_to_group("npcs")
	if resident:
		add_to_group("residents")
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	npc_name = NAMES[rng.randi() % NAMES.size()]
	brave = rng.randf() < 0.22 or troublemaker
	if troublemaker:
		hp = 180
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
	for path_p in [^".:position", ^".:rotation"]:
		cfg.add_property(path_p)
		cfg.property_set_replication_mode(path_p, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path2 in [^".:dead", ^".:move_speed", ^".:severed", ^".:act", ^".:rag_pose"]:
		cfg.add_property(path2)
		cfg.property_set_replication_mode(path2, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	add_child(sync)
	_target = position
	_think = randf_range(0.5, 2.5)
	if rotation.y == 0.0:
		rotation.y = randf() * TAU

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_step(delta)
	_animate()
	_vis_t -= delta
	if _vis_t <= 0.0:
		_vis_t = 0.5
		_far_hide()

## Don't pose people nobody can see (the town is big).
func _far_hide() -> void:
	if _body == null:
		return
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_body.visible = cam.global_position.distance_to(global_position) < 90.0

func _server_step(delta: float) -> void:
	if global_position.y < -20.0:
		queue_free()
		return
	if dead:
		_dead_t += delta
		if _ragdoll != null and _ragdoll.active:
			_rag_step(delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
			velocity.y -= GRAVITY * delta
			move_and_slide()
		if _dead_t > 25.0:
			queue_free()
		return
	if _ragdoll != null and _ragdoll.active:
		_rag_step(delta)
		# lying there for a bit, then get back up once the body has stopped moving
		if _rag_t > 2.2 and _ragdoll.torso().linear_velocity.length() < 1.2:
			_get_up()
		return
	if severed != 0:
		_regrow_t += delta
		if _regrow_t >= 20.0:
			severed = 0   # good as new
			_regrow_t = 0.0
			_say_line("Ah, that's better.")
	_say_cd -= delta
	_punch_cd -= delta
	for k in grudge.keys():
		grudge[k] = float(grudge[k]) - delta * 0.004   # people slowly forgive
		if float(grudge[k]) <= 0.0:
			grudge.erase(k)
	if _act_t > 0.0:
		_act_t -= delta
		if _act_t <= 0.0:
			act = ACT_NONE
	var speed := WALK
	var want := Vector3.ZERO
	var face_dir := Vector3.ZERO
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if troublemaker and hostile == 0 and world != null:
		var victim := _nearest_player(world, 14.0)
		if victim != 0:
			hostile = victim
			_hostile_t = 0.0
			_say_line(["WHAT ARE YOU LOOKING AT?!", "You want a piece of me?!", "This is MY street!"][randi() % 3], true)
	if hostile != 0:
		_hostile_t += delta
		var foe: Node3D = null
		if world != null:
			foe = world.get_node_or_null(str(hostile)) as Node3D
		var limit := 60.0 if troublemaker else 25.0
		if foe == null or _hostile_t > limit or foe.global_position.distance_to(global_position) > 40.0 or (hp < 35 and not troublemaker):
			if foe != null and hp < 35:
				_flee_t = 6.0
				_flee_from = foe.global_position
				_say_line("Okay, okay! I give up!", true)
			hostile = 0
		else:
			var to := foe.global_position - global_position
			to.y = 0.0
			face_dir = to
			if to.length() > 1.3:
				want = to.normalized()
				speed = RUN * 0.95
			elif _punch_cd <= 0.0:
				_punch_cd = 1.1
				act = ACT_PUNCH
				_act_t = 0.35
				var pl := foe as Player
				if pl != null:
					pl.knock.rpc_id(hostile, to.normalized() * 4.5 + Vector3.UP * 2.5)
					Sfx.play_at(get_parent(), "thud", foe.global_position + Vector3.UP, 2.0)
				if randf() < 0.5:
					_say_line(["Take that!", "And stay down!", "HYAAH!", "Pow!", "Had enough?!"][randi() % 5], true)
	elif _flee_t > 0.0:
		_flee_t -= delta
		var away := global_position - _flee_from
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		want = away.normalized()
		speed = RUN
		if act == ACT_HANDS_UP or act == ACT_DANCE:
			act = ACT_NONE
	elif act == ACT_HANDS_UP:
		face_dir = _face
	elif _stop_t > 0.0:
		_stop_t -= delta
		face_dir = _face
	elif act == ACT_DANCE:
		rotation.y += delta * 4.0
	elif _follow != 0 and world != null:
		_follow_t -= delta
		var lead := world.get_node_or_null(str(_follow)) as Node3D
		if lead == null or _follow_t <= 0.0:
			if lead != null:
				_say_line("Right, I'm off. Bye!")
			_follow = 0
		else:
			var to2 := lead.global_position - global_position
			to2.y = 0.0
			if to2.length() > 2.6:
				want = to2.normalized()
				speed = RUN if to2.length() > 7.0 else WALK * 1.6
			else:
				face_dir = to2
	elif resident and not path.is_empty():
		var wp: Vector3 = path[_wp]
		var to3 := wp - global_position
		to3.y = 0.0
		if to3.length() < 0.8:
			_next_wp()
		else:
			want = to3.normalized()
			speed = WALK * (1.0 + float(look_seed % 5) * 0.08)
	else:
		_think -= delta
		if _think <= 0.0:
			_think = randf_range(3.0, 7.0)
			if randf() < 0.35:
				_target = global_position   # stand around for a bit
			else:
				_target = global_position + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
		var to4 := _target - global_position
		to4.y = 0.0
		if to4.length() > 0.5:
			want = to4.normalized()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.move_toward(want * speed, 10.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if want.length() > 0.1 and hv.length() < 0.25:
		_stuck_t += delta
		if _stuck_t > 1.5:   # walked into something: pick another way
			_stuck_t = 0.0
			_think = 0.0
			if resident and not path.is_empty():
				_wp_dir = -_wp_dir
				_next_wp()
	else:
		_stuck_t = 0.0
	if face_dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-face_dir.x, -face_dir.z), clampf(8.0 * delta, 0.0, 1.0))
	elif want.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-want.x, -want.z), clampf(8.0 * delta, 0.0, 1.0))
	move_speed = hv.length()

func _next_wp() -> void:
	if path.is_empty():
		return
	if path_loop:
		_wp = posmod(_wp + _wp_dir, path.size())
	else:
		var n := _wp + _wp_dir
		if n < 0 or n >= path.size():
			_wp_dir = -_wp_dir
			n = _wp + _wp_dir
		_wp = clampi(n, 0, path.size() - 1)

func _nearest_player(world: GameWorld, radius: float) -> int:
	var best := 0
	var best_d := radius
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null:
			continue
		var d := p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p.get_multiplayer_authority()
	return best

func _animate() -> void:
	if _body == null:
		return
	if rag_pose.size() >= PlayerRig.N * 7 or (_ragdoll != null and _ragdoll.active):
		_show_ragdoll()
		_body.set_severed(severed)
		_body.animate(0.0, false)
		return
	if _rag_shown:
		_rag_shown = false
		_body.set_ragdoll([])
		_body.top_level = false
		_body.position = Vector3.ZERO
		_body.rotation = Vector3.ZERO
	if dead:
		if not _fell:   # the ragdoll poses are on their way from the host
			_fell = true
			collision_layer = 0
		_body.animate(0.0, false)
		_body.set_severed(severed)
		return
	_body.set_severed(severed)
	match act:
		ACT_HANDS_UP:
			_body.set_pose(0, 3)
		ACT_DANCE:
			_body.set_pose(1, 0)
		ACT_PUNCH:
			_body.set_pose(0, 1)
		_:
			_body.set_pose(0, 0)
	_body.animate(move_speed, false)

# ------------------------------------------------------------------ ragdoll
## The invisible stick-figure the ragdoll is built on / that the body follows.
func _ensure_rig() -> void:
	if _rig != null:
		return
	_rig = PlayerRig.new()
	_rig.visible = false
	add_child(_rig)
	_rig.setup(look_seed)
	_rig.visible = false

## Server: go floppy (hit by a car, blown up, shoved hard, or dead).
func knock_down(vel: Vector3) -> void:
	if not multiplayer.is_server() or not is_inside_tree():
		return
	if _ragdoll != null and _ragdoll.active:
		_ragdoll.add_velocity(vel.limit_length(10.0))
		_rag_t = minf(_rag_t, 1.0)
		return
	_ensure_rig()
	_rig.apply_standing(global_transform, _rig.stand_pose(0.0, clampf(move_speed / 6.0, 0.0, 1.0), 0.0, 0.0, 0.0))
	if _ragdoll == null:
		_ragdoll = PlayerRagdoll.new()
		add_child(_ragdoll)
	_ragdoll.spawn(_rig, velocity + vel.limit_length(11.0), self)
	_rag_t = 0.0
	_still_t = 0.0
	collision_layer = 0
	act = ACT_NONE
	hostile = 0 if not troublemaker else hostile
	rag_pose = PlayerRig.encode(_ragdoll.bodies)

func _rag_step(delta: float) -> void:
	_rag_t += delta
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null:
		_ragdoll.step(world)
	var t := _ragdoll.torso()
	global_position = t.global_position - Vector3(0.0, TORSO_Y, 0.0)
	if dead:
		# settled: freeze the body where it lies and stop sending it
		if t.linear_velocity.length() < 0.35:
			_still_t += delta
			if _still_t > 1.5 and not t.freeze:
				for b in _ragdoll.bodies:
					b.freeze = true
				rag_pose = PlayerRig.encode(_ragdoll.bodies)
				return
		else:
			_still_t = 0.0
		if t.freeze:
			return
	if Engine.get_physics_frames() % 2 == 0:
		rag_pose = PlayerRig.encode(_ragdoll.bodies)

func _get_up() -> void:
	var t := _ragdoll.torso().global_position
	var q := PhysicsRayQueryParameters3D.create(t + Vector3.UP * 0.3, t + Vector3.DOWN * 4.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var floor_y: float = (hit["position"] as Vector3).y if not hit.is_empty() else t.y - 1.0
	_ragdoll.clear()
	global_position = Vector3(t.x, floor_y + 0.05, t.z)
	velocity = Vector3.ZERO
	collision_layer = 1
	rag_pose = PackedFloat32Array()
	if randf() < 0.6:
		_say_line(["Ow...", "What hit me?", "I'm okay! I'm okay.", "My back...", "Ugh."][randi() % 5])

## Everyone: make the body follow the ragdoll (the server's own bodies, or the synced poses).
func _show_ragdoll() -> void:
	_ensure_rig()
	var k := 1.0 - exp(-25.0 * get_physics_process_delta_time())
	if _ragdoll != null and _ragdoll.active:
		_rig.apply_bodies(_ragdoll.bodies)
	elif not _rig.apply_encoded(rag_pose, k if _rag_shown else 1.0):
		return
	_rag_shown = true
	var ts: Array = []
	for part in _rig.parts:
		ts.append(part.global_transform)
	_body.set_ragdoll(ts)
	_body.top_level = true
	var torso: Transform3D = _rig.parts[PlayerRig.TORSO].global_transform
	_body.global_transform = Transform3D(torso.basis.orthonormalized(), torso.origin) * Transform3D(Basis(), Vector3(0, -1.1, 0))

# ------------------------------------------------------------------ talking
## Speech bubble over my head (with my name).
@rpc("authority", "call_local", "unreliable")
func _say(text: String) -> void:
	_pop_label(text, Color(1.0, 1.0, 0.85), 1.8)

func _say_line(text: String, force := false) -> void:
	if not force and _say_cd > 0.0:
		return
	_say_cd = 2.5
	_say.rpc("%s: %s" % [npc_name, text] if resident or troublemaker else text)

func _face_towards(p: Vector3, hold := 3.0) -> void:
	_face = p - global_position
	_face.y = 0.0
	_stop_t = maxf(_stop_t, hold)

func _player_of(id: int) -> Player:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return null
	return world.get_node_or_null(str(id)) as Player

## F: a player talks to me.
@rpc("any_peer", "call_local", "reliable")
func talk() -> void:
	if not multiplayer.is_server() or dead:
		return
	var by := multiplayer.get_remote_sender_id()
	if by == 0:
		by = 1
	var pl := _player_of(by)
	if pl == null or pl.global_position.distance_to(global_position) > 4.5:
		return
	if hostile != 0 or _flee_t > 0.0:
		_say_line(["Not now!", "Get away from me!", "Can't talk, RUNNING!"][randi() % 3], true)
		return
	_face_towards(pl.global_position, 4.0)
	var who := str(Net.players.get(by, {}).get("name", "you"))
	var g := float(grudge.get(by, 0.0))
	var line := ""
	if troublemaker:
		line = "Talk? I'll give you TALK!"
		hostile = by
	elif g > 0.6:
		line = ["YOU! Stay away from me!", "Oh great, it's the maniac.", "I've called the police on you, you know."][randi() % 3]
		if brave:
			line = ["You've got some nerve coming back here, %s." % who, "Say sorry first."][randi() % 2]
	elif pl.equipped == "pistol" or pl.equipped == "rpg":
		line = ["Is... is that a gun?", "Please put that away.", "I don't want any trouble!"][randi() % 3]
	elif pl.severed != 0:
		line = ["Uh... you're missing a bit there.", "Should you be walking around like that?", "Is that... where's your arm?"][randi() % 3]
	elif pl.ride_name != "":
		line = "Nice ride!"
	else:
		var lines := [
			"Hi %s! Lovely day, isn't it?" % who,
			"Looking for work? Wobbly Jobs on Main Street always needs a hand.",
			"Pizza Palace pays drivers in cash AND pizza.",
			"Don't go near the Chop Shop. They ask no questions. That's the problem.",
			"I'm %s. I live round here." % npc_name,
			"Have you seen my cat? Orange. Wobbly.",
			"The traffic in this town is murder. Sometimes literally.",
			"They say there's an RPG on a roof somewhere. Nonsense, obviously.",
			"I used to be a party animal. Then I got a mortgage.",
			"Mind the cars, they don't stop for anybody.",
			"Nice %s!" % ["shirt", "hat", "shoes", "haircut", "everything"][randi() % 5],
		]
		line = lines[randi() % lines.size()]
	_say_line(line, true)

## Something was said in chat by player `by`, close to me.
func hear(text: String, by: int) -> void:
	if dead or not multiplayer.is_server():
		return
	var t := " " + text.to_lower().strip_edges() + " "
	for ch in ["!", "?", ".", ","]:
		t = t.replace(ch, " ")
	var pl := _player_of(by)
	if pl == null:
		return
	var who := str(Net.players.get(by, {}).get("name", "you"))
	var g := float(grudge.get(by, 0.0))
	if _has(t, ["idiot", "stupid", "ugly", "loser", "dumb", "moron", "noob", "shut up", "hate you", "smell", "fat", "nerd", "bozo", "clown"]):
		grudge[by] = g + 0.5
		_face_towards(pl.global_position, 2.0)
		if brave or troublemaker:
			hostile = by
			_hostile_t = 0.0
			_say_line(["What did you just say?!", "Say that to my FACE!", "Right, that's it!"][randi() % 3], true)
		else:
			_say_line(["Rude!", "Well, I never!", "*sniff* That's hurtful.", "My mum says I'm cool."][randi() % 4], true)
		return
	if _has(t, ["sorry", "my bad", "apologi", "forgive"]):
		grudge.erase(by)
		if hostile == by and not troublemaker:
			hostile = 0
		_face_towards(pl.global_position, 2.0)
		_say_line(["Fine. Apology accepted.", "Hmph. Okay.", "Don't let it happen again."][randi() % 3], true)
		return
	if troublemaker:
		_say_line("Blah blah blah! Come here!", true)
		hostile = by
		return
	if _has(t, ["hands up", "freeze", "stick em up", "on the ground", "dont move", "don t move"]):
		_hands_up(pl.global_position, 4.0)
		return
	if _has(t, ["run", "bomb", "fire", "zombie", "police", "cops"]):
		_flee_t = 5.0
		_flee_from = pl.global_position
		_say_line(["AAAAH!", "Every person for themselves!", "Not again!"][randi() % 3], true)
		return
	if _has(t, ["dance", "party", "boogie", "groove"]):
		if g > 0.6:
			_say_line("I'm not dancing for YOU.", true)
			return
		act = ACT_DANCE
		_act_t = 6.0
		_say_line(["Okay! Watch this!", "You don't have to ask twice!", "Is there music? Who cares!"][randi() % 3], true)
		return
	if _has(t, ["follow me", "come with me", "come here", "come on", "this way"]):
		if g > 0.6:
			_say_line("Follow YOU? No chance.", true)
			return
		_follow = by
		_follow_t = 40.0
		_say_line(["Lead the way!", "Ooh, an adventure!", "Sure, why not."][randi() % 3], true)
		return
	if _has(t, ["go away", "get lost", "leave", "shoo", "stop following", "bye", "goodbye"]):
		if _follow == by:
			_follow = 0
		_say_line(["Fine, fine. Bye!", "See ya!", "Charming."][randi() % 3], true)
		_flee_t = 1.5
		_flee_from = pl.global_position
		return
	_face_towards(pl.global_position, 2.5)
	if _has(t, [" hi ", "hello", " hey ", " yo ", " sup ", "howdy", "hiya", "greetings", "good morning"]):
		_say_line(["Hi %s!" % who, "Hello there!", "Oh, hi!", "Hey %s. Nice day for it." % who][randi() % 4], true)
	elif _has(t, ["how are you", "how r u", "whats up", "what s up", "how s it going", "hows it going"]):
		_say_line(["Not bad, not bad.", "Better before you showed up." if g > 0.3 else "Great, thanks for asking!", "My back hurts. Otherwise fine."][randi() % 3], true)
	elif _has(t, ["job", "work", "money", "cash", "mission", "earn"]):
		_say_line(["Check the job board outside Wobbly Jobs on Main Street.", "The Chop Shop pays big for the right car. Not that I'd know.", "Pizza Palace is always short of drivers."][randi() % 3], true)
	elif _has(t, ["pizza", "food", "hungry", "burger"]):
		_say_line(["Pizza Palace, Main Street. Best slices in town.", "There's a burger place near the job centre.", "The corner shop by the big house sells snacks."][randi() % 3], true)
	elif _has(t, ["car", "drive", "ride", "chop", "steal"]):
		_say_line(["You didn't hear it from me, but the Chop Shop is by the parking lot.", "Keep your hands off my car.", "Taxis are yellow. Police cars are trouble."][randi() % 3], true)
	elif _has(t, ["name", "who are you"]):
		_say_line("I'm %s. Nice to meet you, %s." % [npc_name, who], true)
	elif _has(t, ["thank", "thx", "cheers", "ty "]):
		_say_line(["No problem!", "Any time!", "You're welcome!"][randi() % 3], true)
	elif _has(t, ["love you", "marry", "date", "cute", "pretty", "handsome"]):
		_say_line(["Oh! Um. I'm flattered?", "*blushes*", "Buy me a pizza first."][randi() % 3], true)
	elif _has(t, ["joke", "funny"]):
		_say_line(["Why did the ragdoll cross the road? It didn't. It fell over.", "I'd tell you a chemistry joke but I know I wouldn't get a reaction.", "My life is the joke."][randi() % 3], true)
	elif _has(t, [" yes ", " no ", "ok", "okay", " lol ", "haha", "lmao"]):
		_say_line(["Ha!", "Right...", "Okay then.", "*nods*"][randi() % 4], true)
	elif text.contains("?"):
		_say_line(["Hmm, good question.", "No idea, sorry.", "Ask someone else, I'm busy."][randi() % 3])
	else:
		_say_line(["Huh?", "What?", "Uh-huh.", "If you say so.", "Mhm."][randi() % 5])

func _has(t: String, words: Array) -> bool:
	for w in words:
		if t.contains(str(w)):
			return true
	return false

# ------------------------------------------------------------------ reacting
func _hands_up(from: Vector3, secs: float) -> void:
	act = ACT_HANDS_UP
	_act_t = secs
	_face = from - global_position
	_face.y = 0.0

## Someone is pointing a gun at me.
func aimed_at(by: int) -> void:
	if dead or hostile != 0 or _flee_t > 0.0:
		return
	var pl := _player_of(by)
	if pl == null:
		return
	if brave:
		_face_towards(pl.global_position, 1.0)
		_say_line(["Put that thing away.", "You don't scare me.", "Is that a real one?"][randi() % 3])
		return
	if act != ACT_HANDS_UP:
		_say_line(["Don't shoot!", "Whoa whoa whoa!", "Take my wallet! Just don't shoot!", "Okay! Okay!"][randi() % 4], true)
	_hands_up(pl.global_position, 3.0)

## Violence happened near me (`by` = the player who did it, 0 = nobody / an explosion).
func witness(at: Vector3, by: int, severity: float) -> void:
	if dead or hostile != 0:
		return
	if by > 0:
		grudge[by] = float(grudge.get(by, 0.0)) + 0.25 * severity
	var pl: Player = null
	if by > 0:
		pl = _player_of(by)
	if pl != null and brave and hp > 50 and severity >= 0.9 and randf() < 0.6:
		hostile = by
		_hostile_t = 0.0
		_follow = 0
		_say_line(["HEY! Pick on someone your own size!", "Right, you're going down!", "Not on my street!"][randi() % 3], true)
		return
	_flee_t = randf_range(4.0, 7.0)
	_flee_from = at
	_follow = 0
	act = ACT_NONE
	if randf() < 0.55:
		_say_line(["AAAAH!", "HELP!", "Somebody call the police!", "Not again!", "RUN!", "MY EYES!"][randi() % 6], true)

## LMB shove / walking into me.
@rpc("any_peer", "call_local", "unreliable")
func nudge(vel: Vector3) -> void:
	if not multiplayer.is_server() or dead:
		return
	vel.y = 0.0
	velocity += vel.limit_length(5.0)
	if randf() < 0.08:
		_say_line(["Excuse me!", "Watch it!", "Rude.", "Hey!"][randi() % 4])

## LMB shove: stagger back and run off, a tiny bit of damage.
@rpc("any_peer", "call_local", "reliable")
func shove(vel: Vector3) -> void:
	if not multiplayer.is_server() or dead:
		return
	var by := multiplayer.get_remote_sender_id()
	damage(5, vel.limit_length(9.0), 1 if by == 0 else by)

## Server: take a hit. `by` is the peer who did it (they get run away from, or fought).
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
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	var cut: Array[String] = []
	for l2 in sever:
		if world != null and world.sever_limb(self, l2, push):
			cut.append(l2)
	sever = cut
	if "head" in sever and not killing:
		hp = 0   # no head, no person
		killing = true
	if amount >= 10 or not sever.is_empty():
		_gore_fx.rpc(hit_at, push, sever, killing)
	velocity += push.limit_length(10.0)
	act = ACT_NONE
	_stop_t = 0.0
	_follow = 0
	var attacker: Node3D = null
	if world != null and by != 0:
		attacker = world.get_node_or_null(str(by)) as Node3D
	if by > 0:
		grudge[by] = float(grudge.get(by, 0.0)) + 1.0
	if hp > 0 and attacker != null and (brave or troublemaker) and hp > 35 and amount < 60:
		hostile = by        # fight back!
		_hostile_t = 0.0
		if randf() < 0.6:
			_say_line(["OW! You'll pay for that!", "Oh, it's ON now!", "Big mistake, pal!"][randi() % 3], true)
	else:
		hostile = 0
		_flee_t = 5.0
		_flee_from = attacker.global_position if attacker != null else global_position - push
	if hp <= 0:
		dead = true
		_dead_t = 0.0
		collision_layer = 0   # the body stays on the ground, but people walk through it
		knock_down(push + Vector3.UP * 1.5)
	elif blast or push.length() > 7.0 or amount >= 40:
		knock_down(push + Vector3.UP * 2.0)   # sent flying, gets back up in a bit
	_hurt_fx.rpc(dead)
	if world != null:
		world.alarm(global_position, by, 1.0 if amount >= 10 or dead else 0.5, 22.0, self)

@rpc("authority", "call_local", "reliable")
func _hurt_fx(died: bool) -> void:
	Sfx.play_at(get_parent(), "thud", global_position + Vector3.UP, 2.0)
	var txt: String = ["OOF!", "OW!", "HEY!", "OUCH!", "WHY?!"][randi() % 5] if not died else ["x_x", "BLEH", "OOF..."][randi() % 3]
	_pop_label(txt, Color(1.0, 0.3, 0.25) if not died else Color(0.8, 0.8, 0.85))

func _pop_label(text: String, col: Color, secs := 0.9) -> void:
	if get_parent() == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 64 if text.length() < 14 else 44
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_parent().add_child(l)
	l.global_position = global_position + Vector3(0, 2.1, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.5 + secs * 0.3, 0), secs)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(maxf(0.0, secs - 0.6))
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
