class_name Player
extends CharacterBody3D
## First-person player. The OWNER simulates movement, the ragdoll and grabbing;
## everyone else just copies the synced state and animates the humanoid rig from it.

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.0
const SWIM_SPEED := 3.2
const ACCEL := 32.0
const STOP_DECEL := 36.0
const AIR_ACCEL := 5.0
const JUMP_VELOCITY := 5.8
const GRAVITY := 16.0
const EYE := 1.62
const TORSO_Y := 1.22
const MOUSE_SENS := 0.0022   # multiplied by Settings.sensitivity

var rig: PlayerRig
var label: Label3D
var stand_shape: CollisionShape3D
var head: Node3D
var camera: Camera3D
var _world: GameWorld
var _ragdoll: PlayerRagdoll

# ---- synced to everybody by the MultiplayerSynchronizer
var net_pos := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var move_speed := 0.0
var holding := false
var anim_state := 0     # 0 ground, 1 air, 2 swim, 3 sitting in the coupe, 4 on a rocket (synced for animation)
var ride_name := ""     # name of the vehicle I am in (synced, so others glue me to their copy of it)
var veh_yaw := 0.0      # the vehicle's heading while I ride it (synced)
var _swimming := false
var _air_t := 0.0
var pose := PackedFloat32Array()
var ragdolled := false:
	set(value):
		ragdolled = value
		if stand_shape != null:
			stand_shape.disabled = value
		_refresh_layers()

# ---- local state
var equipped := ""   # kind of the item in my hand ("" = empty); synced so everyone sees it
var equipped_tint := ""   # colours of a held body part (skin|hair), synced
var gloves_on := false    # wearing rubber gloves: LMB on a person rips a limb off (synced)
var severed := 0          # limbs I have lost (bit mask, see Npc.LIMB_BITS); synced
var _shown := ""
var _vm_item: Prop    # what I see in my own hand
var _hand_item: Prop  # what others see in this player's hand
var _use_cd := 0.0
## Melee weapons: [reach, power, arc degrees]. Hold LMB to wind up (up to 2.6x power), let go to swing.
const MELEE := {"knife": [2.0, 7.0, 70.0], "bat": [2.7, 17.0, 110.0], "limb_arm": [2.4, 12.0, 100.0],
	"limb_leg": [2.6, 16.0, 110.0], "limb_head": [2.1, 10.0, 80.0]}
var _charge := -1.0        # 0..1 while winding up a swing, -1 otherwise
var _swing_t := 1.0        # 0..1 progress of the swing animation
var _swing_side := 1.0     # alternates: right-to-left, then left-to-right
var _swing_charge := 0.0
## Weapon wheel: things I carry besides what is in my hand. [[kind, tint], ...]
const INVENTORY_SIZE := 7
var inventory: Array = []
var _wheel: Control
var _custom: CustomBody    # Workshop character model (replaces the built-in body)
var _custom_id := ""
var third_person := false
var cam3: Camera3D      # the camera used in third person (the eye camera keeps aiming)
var _cam_far := false   # ragdoll camera has pulled back far enough to see my own body
var _custom_failed := ""
var _wall_push := 0.0
var drunk := 0.0   # seconds of wobbliness left (beer)
var rush := 0.0    # seconds of sugar rush left (soda)
var _hold_amt := 0.0
var _phase := 0.0
var _idle_t := 0.0
var _bob_t := 0.0
var _land_dip := 0.0
var _shake := 0.0
var _coyote := 0.0
var _jump_buf := 0.0
var _prev_vy := 0.0
var _in_water := false
var _step_dist := 0.0
var _step_y := 0.0
var _grounded_prev := true
var _shove_cd := 0.0
var _rag_time := 0.0
var _got_first := false
var _rag_cd := {}
var _vm_arms: Array[Node3D] = []
var _arm_w: Array = [Vector3.ZERO, Vector3.ZERO]        # smoothed wrist positions
var _arm_q: Array = [Quaternion.IDENTITY, Quaternion.IDENTITY]
var _arm_mode: Array = ["", ""]
var _arm_t: Array = [0.0, 0.0]
var _prompt: Label
var _dot: Panel
var _look := {}
var _cust: Node = null
var carrier := 0           # (victim side) peer id carrying me while I am knocked out
var carrying := 0          # (holder side) peer id of the knocked-out player I hold above my head
var _ride: Prop            # the rocket I am riding
var _seat := false         # true = I am sitting IN the shopping cart (someone else pushes)
var _equip_anim := 1.0
var _cig_t := -1.0          # seconds into the "raise the cigarette to my mouth" animation (-1 = not smoking)
var _cig_puffed := false
var input_locked := false  # true while the character creator is open

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())  # node name = owner's peer id
	add_to_group("players")

func _ready() -> void:
	var id := name.to_int()
	_world = get_tree().get_first_node_in_group("world") as GameWorld
	motion_mode = MOTION_MODE_GROUNDED
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	floor_block_on_wall = false
	safe_margin = 0.02
	max_slides = 8

	stand_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	stand_shape.shape = cap
	stand_shape.position.y = 0.9
	stand_shape.disabled = ragdolled
	add_child(stand_shape)

	rig = PlayerRig.new()
	add_child(rig)
	_look = _net_look()
	rig.setup(id, _look)
	Net.players_changed.connect(_on_players_changed)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.004
	label.font_size = 64
	label.outline_size = 12
	label.visible = not is_multiplayer_authority()
	add_child(label)
	label.top_level = true

	_setup_sync(id)
	if is_multiplayer_authority():
		_build_owner_parts()
	_refresh_layers()

func _setup_sync(id: int) -> void:
	var cfg := SceneReplicationConfig.new()
	for path in [^".:net_pos", ^".:yaw", ^".:pitch", ^".:move_speed", ^".:veh_yaw"]:
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path in [^".:ragdolled", ^".:holding", ^".:pose", ^".:equipped", ^".:anim_state", ^".:ride_name", ^".:equipped_tint", ^".:gloves_on", ^".:severed"]:
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	add_child(sync)
	sync.set_multiplayer_authority(id)

func _refresh_layers() -> void:
	if rig == null or rig.parts.is_empty():
		return
	rig.set_layers(1, 1)
	if is_multiplayer_authority():
		_apply_fp_visibility(false)

# ----------------------------------------------------------- owner-only parts
func _build_owner_parts() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, EYE, 0)
	add_child(head)

	camera = Camera3D.new()
	camera.fov = Settings.fov
	camera.near = 0.02
	camera.far = 300.0
	# World is layer 1. Viewmodel arms are layer 3 (bit 4). The body is hidden locally.
	camera.cull_mask = 1 | 4
	head.add_child(camera)
	camera.make_current()
	cam3 = Camera3D.new()
	cam3.top_level = true
	cam3.near = 0.05
	cam3.far = 300.0
	cam3.cull_mask = 1   # no first-person arms in third person
	add_child(cam3)

	_ragdoll = PlayerRagdoll.new()
	add_child(_ragdoll)
	_ragdoll.prop_touched.connect(_on_rag_prop)

	_build_viewmodel()

	var layer := CanvasLayer.new()
	add_child(layer)
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.custom_minimum_size = Vector2(8, 8)
	_dot.size = Vector2(8, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(4)
	sb.border_color = Color(0, 0, 0, 0.7)
	sb.set_border_width_all(1)
	_dot.add_theme_stylebox_override("panel", sb)
	layer.add_child(_dot)
	_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dot.pivot_offset = Vector2(4, 4)
	_prompt = Label.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.custom_minimum_size = Vector2(420, 24)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	layer.add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-210, 28)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _part_color(cat: String) -> Variant:
	var npc: Dictionary = _look.get("npc", {}) if _look.get("npc", {}) is Dictionary else {}
	var parts: Dictionary = npc.get("parts", {}) if npc.get("parts", {}) is Dictionary else {}
	var e: Dictionary = parts.get(cat, {}) if parts.get(cat, {}) is Dictionary else {}
	if int(e.get("i", -1)) >= 0:
		return Color.html(str(e.get("c", "ffffff")))
	return null

const ARM_A := 0.27    # upper arm length
const ARM_B := 0.265   # forearm length (elbow to wrist)

## First-person arms: sleeve / skin tubes with an elbow, and a blocky hand with bending fingers (FpHand).
## The arm is posed by two-bone IK in _place_arm so the hand always reaches the item it holds.
## Index 0 is the left arm, 1 the right arm.
func _build_viewmodel() -> void:
	for a in _vm_arms:
		a.queue_free()
	_vm_arms.clear()
	_arm_w = [Vector3.ZERO, Vector3.ZERO]
	_arm_q = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	_arm_mode = ["", ""]
	_arm_t = [0.0, 0.0]
	var skin: Color = rig.skin
	var npc_skin: Dictionary = _look.get("npc", {}) if _look.get("npc", {}) is Dictionary else {}
	if npc_skin.has("skin"):
		skin = Color.html(str(npc_skin["skin"]))
	var long_sleeve: Variant = _part_color("jacket")
	if long_sleeve == null:
		long_sleeve = _part_color("bodysuit")
	var short_sleeve: Variant = _part_color("shirt")
	var sleeve: Color = rig.shirt.darkened(0.08)
	if long_sleeve != null:
		sleeve = long_sleeve as Color
	elif short_sleeve != null:
		sleeve = short_sleeve as Color
	var cuff: Color = sleeve.darkened(0.14)
	for i in 2:
		var arm := Node3D.new()
		camera.add_child(arm)
		var fore := Node3D.new()
		fore.position = Vector3(0, ARM_A, 0)
		arm.add_child(fore)
		if long_sleeve != null:
			# sleeve all the way to the wrist, with a cuff, then a skin wrist
			_vm_cyl(arm, 0.052, 0.056, ARM_A, sleeve, Vector3(0, ARM_A * 0.5, 0))
			_vm_ball(arm, 0.058, sleeve, Vector3(0, ARM_A, 0))
			_vm_cyl(fore, 0.046, 0.05, 0.235, sleeve, Vector3(0, 0.1175, 0))
			_vm_cyl(fore, 0.052, 0.052, 0.03, cuff, Vector3(0, 0.235, 0))
			_vm_cyl(fore, 0.04, 0.04, 0.06, skin, Vector3(0, 0.255, 0))
		else:
			# short sleeve: the hem sits on the upper arm, the elbow and forearm are skin
			_vm_cyl(arm, 0.054, 0.056, 0.2, sleeve, Vector3(0, 0.1, 0))
			_vm_cyl(arm, 0.06, 0.06, 0.03, cuff, Vector3(0, 0.2, 0))
			_vm_cyl(arm, 0.049, 0.051, 0.09, skin, Vector3(0, 0.225, 0))
			_vm_ball(arm, 0.051, skin, Vector3(0, ARM_A, 0))
			_vm_cyl(fore, 0.042, 0.05, 0.25, skin, Vector3(0, 0.125, 0))
			_vm_ball(fore, 0.043, skin, Vector3(0, 0.255, 0))
		var hand := FpHand.new()
		hand.build(skin)
		hand.position = Vector3(0, ARM_B, 0)
		fore.add_child(hand)
		arm.set_meta("fore", fore)
		arm.set_meta("hand", hand)
		_vm_arms.append(arm)
	_tint_fp_hands()
	_ghost_arms()

static func _basis_y(y: Vector3, ref: Vector3) -> Basis:
	var yn := y.normalized()
	var xr := ref - yn * ref.dot(yn)
	if xr.length() < 0.001:
		xr = Vector3.RIGHT
	xr = xr.normalized()
	return Basis(xr, yn, xr.cross(yn))

## Pose arm i so its wrist is at `wrist` (camera space) and the hand has orientation `node_basis`.
## The shoulder is imagined below and behind the wrist (out of sight), the elbow bends outward.
func _place_arm(i: int, wrist: Vector3, node_basis: Basis) -> void:
	var arm := _vm_arms[i]
	var side := 1.0 if i == 1 else -1.0
	var sh := wrist + Vector3(side * 0.35, -0.8, 0.55).normalized() * 0.47
	var pole := Vector3(side * 0.6, -0.7, 0.4)
	var to := wrist - sh
	var d := clampf(to.length(), 0.12, ARM_A + ARM_B - 0.005)
	var u := to.normalized()
	var w2 := sh + u * d
	var x := (ARM_A * ARM_A - ARM_B * ARM_B + d * d) / (2.0 * d)
	var h := sqrt(maxf(ARM_A * ARM_A - x * x, 0.0))
	var p := (pole - u * pole.dot(u)).normalized()
	var elbow := sh + u * x + p * h
	var bu := _basis_y(elbow - sh, p)
	var bf := _basis_y(w2 - elbow, p)
	arm.transform = Transform3D(bu, sh)
	var fore := arm.get_meta("fore") as Node3D
	fore.basis = bu.inverse() * bf
	var hand := arm.get_meta("hand") as Node3D
	hand.basis = bf.inverse() * node_basis * Basis.from_scale(Vector3.ONE * FpHand.SCALE)

## Hand i goes to this wrist position / orientation (smoothed for a moment when the pose type changes, so
## hands glide to a new item instead of snapping) with these finger curls.
func _set_hand(i: int, mode: String, wrist: Vector3, node_basis: Basis, curls: Array, thumb: Array, delta: float) -> void:
	var side := 1.0 if i == 1 else -1.0
	var rn: Basis = node_basis if side > 0.0 else node_basis * Grips.mirror_x()
	var q := rn.orthonormalized().get_rotation_quaternion()
	if _arm_mode[i] != mode:
		_arm_mode[i] = mode
		_arm_t[i] = 0.25
	var k := 1.0
	if float(_arm_t[i]) > 0.0:
		_arm_t[i] = float(_arm_t[i]) - delta
		k = 1.0 - exp(-16.0 * delta)
		wrist = (_arm_w[i] as Vector3).lerp(wrist, k)
		q = (_arm_q[i] as Quaternion).slerp(q, k)
	_arm_w[i] = wrist
	_arm_q[i] = q
	var nb: Basis = Basis(q) if side > 0.0 else Basis(q) * Grips.mirror_x()
	_place_arm(i, wrist, nb)
	(_vm_arms[i].get_meta("hand") as FpHand).pose(curls, thumb, 1.0 - exp(-18.0 * delta))

func _vm_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, color: Color, pos: Vector3) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	_vm_add(parent, m, color, pos)

func _vm_ball(parent: Node3D, r: float, color: Color, pos: Vector3) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	_vm_add(parent, m, color, pos)

func _vm_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := _vm_add(parent, m, color, pos)
	mi.rotation_degrees = rot_deg

func _vm_add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.solid(color, 0.8)
	mi.position = pos
	mi.layers = 4
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _vm_mesh(arm: Node3D, r: float, h: float, color: Color, pos: Vector3) -> void:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = Mats.solid(color, 0.8)
	mi.position = pos
	mi.layers = 4
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(mi)

# ----------------------------------------------------------------------- look
func _net_look() -> Dictionary:
	var info: Dictionary = Net.players.get(name.to_int(), {})
	if info.has("look"):
		return info["look"]
	if is_multiplayer_authority():
		return Net.my_look
	return {}

func _on_players_changed() -> void:
	var l := _net_look()
	if l.is_empty() or l.hash() == _look.hash():
		return
	_look = l
	rig.rebuild(l)
	_refresh_layers()
	if is_multiplayer_authority() and camera != null:
		_build_viewmodel()

func _open_customizer() -> void:
	if _cust != null or ragdolled:
		return
	input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var c := Customizer.new()
	c.theme = UITheme.shared()
	c.setup(_look if not _look.is_empty() else Net.my_look)
	layer.add_child(c)
	_cust = layer
	c.finished.connect(func(new_look: Dictionary, saved: bool):
		if saved:
			Net.set_my_look(new_look)
		layer.queue_free()
		_cust = null
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

# --------------------------------------------------------------------- frame
func _process(delta: float) -> void:
	var mine := is_multiplayer_authority()
	if not mine:
		_smooth_remote(delta)
	_update_rig(delta, mine)
	_footsteps(delta, mine)
	_update_item_visuals()
	_update_custom_body(mine)
	label.text = Net.players.get(name.to_int(), {}).get("name", "...")
	label.global_position = rig.parts[PlayerRig.HEAD].global_position + Vector3(0, 0.3 + 0.12 * rig.head_size, 0)
	if mine and camera != null and head != null:
		_update_camera(delta)

## A helper for sounds that come from this player.
func _snd(kind: String, vol := 0.0) -> void:
	var w := get_tree().get_first_node_in_group("world") as Node3D
	if w != null:
		Sfx.play_at(w, kind, global_position, vol)

## Footsteps: one every couple of metres walked, for everybody (remote players are judged by their replicated speed).
func _footsteps(delta: float, mine: bool) -> void:
	var on_ground := is_on_floor() if mine else absf(global_position.y - _step_y) < 0.03
	_step_y = global_position.y
	if ragdolled or carrier != 0 or _ride != null or move_speed < 0.8 or not on_ground or (mine and _in_water):
		_step_dist = minf(_step_dist, 1.0)
		return
	_step_dist += move_speed * delta
	if _step_dist >= 2.1:
		_step_dist = 0.0
		_snd("step", -9.0 + clampf(move_speed - 5.0, 0.0, 3.0))

func _smooth_remote(delta: float) -> void:
	if not _got_first:
		if net_pos != Vector3.ZERO:
			global_position = net_pos
			rotation.y = yaw
			_got_first = true
		return
	var k := 1.0 - exp(-18.0 * delta)
	if ride_name != "" and _world != null:
		# riding something: stick to MY copy of that vehicle, so they never trail behind it at speed
		var v := _world.get_node_or_null(ride_name) as Prop
		if v != null:
			global_position = v.global_position + ride_offset(v, v.kind == "cart" and anim_state == 3)
			rotation.y = lerp_angle(rotation.y, yaw, k)
			return
	global_position = global_position.lerp(net_pos, k)
	rotation.y = lerp_angle(rotation.y, yaw, k)

## Where a rider's feet go relative to the vehicle.
static func ride_offset(v: Prop, seat: bool) -> Vector3:
	var flat := Basis(Vector3.UP, v.global_rotation.y)
	match v.kind:
		"cart":
			return flat * (Vector3(0.0, -0.58, 0.0) if seat else Vector3(0.0, -0.5, 0.95))
		"coupe":
			return v.global_basis * Vector3(0.0, -0.45, 0.15)
	return Vector3(0.0, 0.15, 0.0)

func _update_rig(delta: float, mine: bool) -> void:
	if ragdolled:
		if mine:
			if _ragdoll != null and _ragdoll.active:
				rig.apply_bodies(_ragdoll.bodies)
		else:
			rig.apply_encoded(pose, 1.0 - exp(-25.0 * delta))
		return
	_phase += delta * move_speed * 1.8
	_idle_t += delta
	var s := clampf(move_speed / SPRINT_SPEED, 0.0, 1.0)
	var hold_target := 1.0 if holding else 0.0
	_hold_amt = move_toward(_hold_amt, hold_target, delta * 6.0)
	rig.apply_standing(global_transform, rig.stand_pose(_phase, s, pitch, _hold_amt, _idle_t))

func _update_camera(delta: float) -> void:
	var grounded := is_on_floor() and not ragdolled
	var spd := move_speed if grounded else 0.0
	_bob_t += delta * spd * 1.7
	var amp := 0.018 * clampf(spd / 6.0, 0.0, 1.0)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	var use3 := third_person and not ragdolled
	if not use3 and not camera.current:
		camera.make_current()

	if ragdolled and _ragdoll != null and _ragdoll.active and not rig.parts.is_empty():
		# Pull back so the ragdoll is visible, and stop the camera inside walls.
		head.top_level = true
		var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var focus: Vector3 = rig.parts[PlayerRig.HEAD].global_position
		var desired := focus + look.z * 2.7 + Vector3.UP * 0.35
		var origin := focus + Vector3.UP * 0.1
		var q := PhysicsRayQueryParameters3D.create(origin, desired, 1)
		q.exclude = [get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		var cam_pos := desired
		if not hit.is_empty() and origin.distance_to(hit.position) < origin.distance_to(desired):
			cam_pos = hit.position + (origin - desired).normalized() * 0.18
		head.global_position = cam_pos
		head.global_basis = look
	else:
		if head.top_level:
			head.top_level = false
		head.rotation = Vector3(pitch, 0.0, 0.0)
		var eye := EYE * (0.55 if (_ride != null and (_ride.kind == "coupe" or _seat)) else 1.0)   # ducked under the toy car roof / in the cart
		head.position = Vector3(cos(_bob_t * 0.5) * amp * 0.5, eye + sin(_bob_t) * amp - _land_dip, -0.12 if (_ride != null and _ride.kind == "coupe") else 0.0)

	_land_dip = move_toward(_land_dip, 0.0, delta * 1.2)
	var sprinting := Input.is_action_pressed("sprint") and spd > 5.5
	camera.fov = lerpf(camera.fov, Settings.fov + (7.0 if sprinting else 0.0), minf(1.0, delta * 8.0))
	if drunk > 0.0:
		var tt := Time.get_ticks_msec() / 1000.0
		var k2 := minf(1.0, drunk / 5.0)
		camera.rotation.z = sin(tt * 0.9) * 0.12 * k2
		camera.fov += sin(tt * 1.3) * 5.0 * k2
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	_apply_fp_visibility(true)
	if use3:
		_third_person_cam()

	var wall_push := 0.0
	var wq := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 0.9, 1)
	wq.exclude = [get_rid()]
	var wall_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(wq)
	if not wall_hit.is_empty():
		wall_push = clampf(0.9 - camera.global_position.distance_to(wall_hit["position"]), 0.0, 0.6)

	_wall_push = wall_push
	_update_viewmodel(delta, spd, amp, wall_push)

# Open / relaxed finger curls for hands that are not holding anything.
const CURL_RELAXED := [[20.0, 25.0, 15.0], [28.0, 32.0, 20.0], [32.0, 36.0, 22.0], [36.0, 40.0, 25.0]]
const CURL_OPEN := [[10.0, 10.0, 5.0], [10.0, 10.0, 5.0], [10.0, 10.0, 5.0], [10.0, 10.0, 5.0]]
const CURL_CARRY := [[30.0, 35.0, 25.0], [30.0, 35.0, 25.0], [30.0, 35.0, 25.0], [30.0, 35.0, 25.0]]

const CIG_TIME := 1.9
const CIG_MOUTH_POS := Vector3(0.03, -0.08, -0.25)   # where the cigarette is held when it is at my lips
const CIG_MOUTH_ROT := Vector3(8.0, 6.0, 0.0)

## 0..1: how far the cigarette is raised to my mouth. Raise (0.5 s), puff and hold, lower again.
func _cig_mouth_amount(delta: float) -> float:
	if _cig_t < 0.0:
		return 0.0
	_cig_t += delta
	if _cig_t >= 0.55 and not _cig_puffed:
		_cig_puffed = true
		if _world != null:
			_world.use_item.rpc_id(1, "cig", camera.global_position, -camera.global_basis.z)
	if _cig_t > CIG_TIME:
		_cig_t = -1.0
		return 0.0
	var m := 1.0
	if _cig_t < 0.5:
		m = _cig_t / 0.5
	elif _cig_t > CIG_TIME - 0.5:
		m = (CIG_TIME - _cig_t) / 0.5
	return m * m * (3.0 - 2.0 * m)

## Where the melee weapon is pulled to: back and up while winding up, then a sweep across the screen.
func _swing_offset() -> Array:
	var side := _swing_side
	if _charge >= 0.0:
		var c := _charge * _charge * (3.0 - 2.0 * _charge)
		var wob := sin(Time.get_ticks_msec() * 0.03) * 0.006 * c   # shaking with effort
		return [Vector3(0.12 * -side + wob, 0.1 * c, 0.14 * c), Vector3(30.0 * c, 35.0 * -side * c, 0.0)]
	if _swing_t < 1.0:
		var t := _swing_t
		var e := 1.0 - pow(1.0 - t, 3.0)                    # fast start, slow follow-through
		var back := 1.0 - minf(t * 4.0, 1.0)                # leaves the wind-up quickly
		var amt := 1.0 + _swing_charge * 0.6
		var x := lerpf(0.14 * -side, -0.3 * -side * amt, e)
		var y := lerpf(0.1, -0.12, e) * (0.4 + 0.6 * amt) + 0.05 * back
		var z := lerpf(0.12, -0.18, sin(e * PI) * 0.6 + e * 0.4)
		var yaw := lerpf(35.0 * -side, -60.0 * -side * amt, e)
		var pitch := lerpf(30.0, -35.0, e)
		var ret := 1.0 - smoothstep(0.75, 1.0, t)           # settle back at the end
		return [Vector3(x, y, z) * ret, Vector3(pitch, yaw, 15.0 * side * sin(e * PI)) * ret]
	return [Vector3.ZERO, Vector3.ZERO]

## First-person hands: gripping the held item when there is one (see Grips), otherwise relaxed at the sides
## (or raised while carrying something).
func _update_viewmodel(delta: float, spd: float, amp: float, wall_push: float) -> void:
	if _vm_arms.size() < 2:
		return
	var show := not ragdolled and not third_person
	for a in _vm_arms:
		a.visible = show   # a lost arm still shows: as a see-through ghost arm (see _ghost_arms)
	if equipped != "cig" or ragdolled:
		_cig_t = -1.0
	if not show:
		_cig_mouth_amount(delta)   # keeps the puff timing going in third person
		return
	var busy := [false, false]   # [left, right] hand is holding the item
	var bob := Vector3(cos(_bob_t * 0.5) * amp * 0.25, sin(_bob_t) * 0.006 * clampf(spd / 4.0, 0.0, 1.0), 0.0)
	var push := Vector3(0.0, -wall_push * 0.6, wall_push)   # items and hands pull back instead of poking through walls
	if equipped != "" and _vm_item != null and Prop.is_valid_kind(equipped):
		var half := float(Prop.def_of(equipped)["half"])
		var sc := 0.5 if half >= 0.25 else (0.7 if half >= 0.2 else 1.0)
		var ease_in := 1.0 - pow(1.0 - _equip_anim, 3.0)
		var lift := Vector3(0.0, -0.45 * (1.0 - ease_in), 0.15 * (1.0 - ease_in))   # the item comes up from below when equipped
		var gs := Grips.spec(equipped)
		if not gs.is_empty():
			var ipos: Vector3 = gs["pos"]
			var irot: Vector3 = gs["rot"]
			if MELEE.has(equipped):
				var so := _swing_offset()
				ipos += so[0]
				irot += so[1]
			if equipped == "cig":
				var m := _cig_mouth_amount(delta)
				ipos = ipos.lerp(CIG_MOUTH_POS, m)
				irot = irot.lerp(CIG_MOUTH_ROT, m)
			var item_xf := Transform3D(Grips.cam_rot(irot), ipos + bob + push + lift)
			_vm_item.global_transform = camera.global_transform * item_xf
			for hd in gs["hands"]:
				var placed := Grips.place_hand(item_xf, hd as Dictionary)
				var idx := 1 if int(hd["side"]) == 1 else 0
				busy[idx] = true
				_set_hand(idx, "grip:" + equipped, placed["wrist"] as Vector3, placed["basis"] as Basis, hd["curls"] as Array, hd["thumb"] as Array, delta)
		else:
			# a crate, ball, melon...: carried in both hands in front of me
			var c := Vector3(0.0, -0.24, -0.6) + bob + push + lift
			_vm_item.global_transform = camera.global_transform * Transform3D(Basis.from_scale(Vector3.ONE * sc), c)
			var reach := half * sc + 0.07
			for side in [-1, 1]:
				var idx2 := 1 if side == 1 else 0
				var fh := Grips.free_hand(side, c + Vector3(float(side) * reach, -0.02, 0.12), Vector3(10.0, 28.0, 0.0))
				busy[idx2] = true
				_set_hand(idx2, "carry", fh["wrist"] as Vector3, fh["basis"] as Basis, CURL_CARRY, [25.0, 20.0], delta)
	if _ride != null and is_instance_valid(_ride) and _ride.kind == "cart":
		# both hands on the trolley handle, palms down
		for i3 in 2:
			var s3 := 1 if i3 == 1 else -1
			var fc := Grips.free_hand(s3, Vector3(0.22 * float(s3), -0.36, -0.52) + bob * 0.5, Vector3(5.0, 8.0, -90.0 * float(s3)))
			busy[i3] = true
			_set_hand(i3, "cart", fc["wrist"] as Vector3, fc["basis"] as Basis, [[70.0, 80.0, 60.0], [70.0, 80.0, 60.0], [70.0, 80.0, 60.0], [70.0, 80.0, 60.0]], [40.0, 30.0], delta)
	for i in 2:
		if busy[i]:
			continue
		var side2 := 1 if i == 1 else -1
		var amt := _hold_amt if equipped == "" else 0.0
		var rest := Vector3(0.27 * side2, -0.25, -0.5)
		var raised := Vector3(0.22 * side2, -0.2, -0.5)
		var w := rest.lerp(raised, amt) + bob
		w.y += sin(_bob_t + float(i) * PI) * 0.012 * clampf(spd / 4.0, 0.0, 1.0)
		w += push
		var ang := Vector3(lerpf(15.0, 55.0, amt), lerpf(12.0, 10.0, amt), 0.0)
		var fr := Grips.free_hand(side2, w, ang)
		var curls: Array = CURL_OPEN if amt > 0.5 else CURL_RELAXED
		_set_hand(i, "idle", fr["wrist"] as Vector3, fr["basis"] as Basis, curls, [15.0, 10.0], delta)

## Third person: the camera floats behind and above my shoulder and never goes through walls.
func _third_person_cam() -> void:
	var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var focus := global_position + Vector3.UP * 1.55
	var desired := focus + look.z * 3.3 + look.x * 0.45 + Vector3.UP * 0.25
	var q := PhysicsRayQueryParameters3D.create(focus, desired, 1)
	q.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var cam_pos := desired
	if not hit.is_empty():
		cam_pos = hit.position + (focus - desired).normalized() * 0.2
	cam3.global_transform = Transform3D(look, cam_pos)
	cam3.fov = camera.fov
	if not cam3.current:
		cam3.make_current()

func toggle_view() -> void:
	third_person = not third_person

## "I'm stuck!": get out of anything and go back to the spawn point.
func stuck_respawn() -> void:
	if not is_multiplayer_authority():
		return
	if _ride != null:
		_dismount(Vector3.ZERO)
	if carrying != 0:
		_drop_carried(false)
	carrier = 0
	_respawn()
	input_locked = false

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _apply_fp_visibility(use_camera_distance: bool) -> void:
	if rig == null or not is_multiplayer_authority():
		return
	var show := false
	if ragdolled and use_camera_distance and head != null and head.top_level and not rig.parts.is_empty():
		var dist := head.global_position.distance_to(rig.parts[PlayerRig.HEAD].global_position)
		show = dist > 0.85
	_cam_far = show
	if _custom != null and _custom is NpcBody:
		show = false
	for v in rig.visuals:
		v.visible = show
	for v in rig.head_visuals:
		v.visible = show

# --------------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or camera == null or input_locked:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS * Settings.sensitivity)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS * Settings.sensitivity, -1.35, 1.35)
		yaw = rotation.y
		if head != null and not ragdolled:
			head.rotation.x = pitch
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or camera == null or input_locked:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("view"):
		toggle_view()
		return
	if event.is_action_pressed("stuck"):
		stuck_respawn()
		return
	if event.is_action_pressed("interact") and _ride != null and Prop.is_vehicle(_ride.kind):
		_dismount(Vector3.ZERO)
		return
	if event.is_action_pressed("interact") and _world != null and _ride == null and not ragdolled:
		if carrying != 0:
			_drop_carried(false)
			return
		var pc := _world.nearest_pc(global_position)
		if pc != null:
			_world.open_pc(self, pc)
			return
		var shelf := _shelf_in_view()
		if shelf != "":
			_world.take_from_shelf.rpc_id(1, camera.global_position, -camera.global_basis.z)
			return
		if _world.near_shop(global_position):
			_world.open_shop(self)
			return
		var rk := _find_rocket()
		if rk != null:
			if rk.kind == "cart" and _cart_wants_seat(rk):
				rk.sit_in.rpc_id(1)
			else:
				rk.ride.rpc_id(1)
			return
		var down := _find_downed()
		if down != null:
			drop_equipped(Vector3.ZERO)
			carrying = down.get_multiplayer_authority()
			holding = true
			down.picked_up_by.rpc_id(carrying, get_multiplayer_authority())
			return
	if event.is_action_pressed("chat") and _world != null:
		_world.open_chat(self)
		return
	if event.is_action_pressed("customize"):
		_open_customizer()
		return
	if event.is_action_pressed("flop") and not ragdolled:
		set_ragdoll(true)
	if event.is_action_pressed("grab") and not ragdolled and carrying == 0 and _ride == null:   # RMB: pick up / put down
		if equipped != "":
			drop_equipped(velocity * 0.5)
		else:
			_try_pickup()
	if event.is_action_pressed("shove"):                    # LMB: use the item (or shove)
		if carrying != 0:
			_drop_carried(true)
			return
		if equipped != "":
			if MELEE.has(equipped):
				if _use_cd <= 0.0 and not ragdolled:
					_charge = 0.0   # wind up; the swing happens when the button is let go
			elif Prop.ITEMS.has(equipped):
				_use_equipped()
			else:
				throw_equipped()
		elif gloves_on and _someone_to_rip():
			_world.rip.rpc_id(1, camera.global_position, -camera.global_basis.z)
		else:
			_shove()
	if event.is_action_released("shove") and _charge >= 0.0:
		_do_swing()
	if event.is_action_pressed("wheel") and _wheel == null:
		_open_wheel()
	if event.is_action_pressed("throw") and equipped != "":
		throw_equipped()
	if event.is_action_pressed("menu") and _world != null and not ragdolled:
		_world.open_menu(self)
		return
	for i in GameWorld.PROP_ORDER.size():
		if event.is_action_pressed("spawn_%d" % (i + 1)) and _world != null:
			spawn_kind(GameWorld.PROP_ORDER[i])

# ------------------------------------------------------------------ movement
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _world != null and not _world.map_ready:   # the map is still loading: wait in place
		velocity = Vector3.ZERO
		_publish(0.0)
		return
	_shove_cd = maxf(0.0, _shove_cd - delta)
	_use_cd = maxf(0.0, _use_cd - delta)
	if severed != 0:
		_regrow_t += delta
		if _regrow_t >= REGROW_TIME:
			_regrow()
	if _charge >= 0.0:
		_charge = minf(1.0, _charge + delta / 0.8)
		if not MELEE.has(equipped) or ragdolled:
			_charge = -1.0
	_swing_t = minf(1.0, _swing_t + delta / 0.3)
	drunk = maxf(0.0, drunk - delta)
	rush = maxf(0.0, rush - delta)
	if global_position.y < -30.0:
		_respawn()
		return
	if ragdolled:
		_ragdoll_step(delta)
		_publish(0.0)
		return
	if _ride != null:
		_ride_step()
		return
	if carrying != 0:
		var victim: Player = null
		if _world != null:
			victim = _world.get_node_or_null(str(carrying)) as Player
		if victim == null or not victim.ragdolled:
			carrying = 0
			holding = equipped != ""

	var surface := _world.water_surface(global_position) if _world != null else NAN
	var depth := 0.0 if is_nan(surface) else surface - global_position.y
	var swimming := depth > 1.1
	_swimming = swimming
	if swimming and not _in_water and velocity.y < -1.0:
		_snd("splash", 3.0)
	_in_water = depth > 0.3
	var input := Vector2.ZERO if input_locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint := Input.is_action_pressed("sprint") and input.y < 0.1
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	if depth > 0.1:
		speed *= 0.65
	if rush > 0.0:
		speed *= 1.4
	if carrying != 0:
		speed *= 0.7
	if drunk > 0.0:  # beer: your legs have opinions
		var k := minf(1.0, drunk / 5.0)
		input = input.rotated(sin(Time.get_ticks_msec() / 1000.0 * 1.7) * 0.7 * k)
	var speed_before := Vector2(velocity.x, velocity.z).length()
	_prev_vy = velocity.y

	var lad: Dictionary = _world.ladder_near(global_position) if _world != null else {}
	var climb_in := not input_locked and (input.y < -0.3 or Input.is_action_pressed("jump"))
	if not lad.is_empty() and climb_in:
		# climbing the pool ladder: straight up against the wall, then a step out onto the deck
		var out: Vector3 = lad["out"]
		var lp: Vector3 = lad["pos"]
		var side_fix := Vector3(lp.x - global_position.x, 0.0, lp.z - global_position.z) * 4.0
		velocity = out * 0.8 + side_fix + Vector3.UP * 3.2
		if global_position.y > -0.35:
			velocity = out * 3.5 + Vector3.UP * 3.0
		_climbing = true
	elif swimming:
		_climbing = false
		_swim(delta, input, surface)
	else:
		_climbing = false
		_walk(delta, input, speed)
	# being pushed by someone walking into me
	velocity.x += _ext_push.x
	velocity.z += _ext_push.z
	_ext_push = _ext_push.move_toward(Vector3.ZERO, 14.0 * delta)
	var my_h := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_push_bodies(my_h, delta)

	var grounded := is_on_floor()
	if grounded and not _grounded_prev and not swimming:
		if _prev_vy < -13.0:
			knock(Vector3(velocity.x, 0.0, velocity.z) * 0.6 + Vector3.UP * 2.0)
		elif _prev_vy < -6.0:
			_land_dip = clampf(-_prev_vy * 0.012, 0.0, 0.18)
		if _prev_vy < -4.5:
			_snd("land", clampf((-_prev_vy - 4.5) * 0.4, -4.0, 3.0))
	_grounded_prev = grounded

	# Walking into toys pushes them (the server owns their physics)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var prop := c.get_collider() as Prop
		if prop != null and speed_before > 0.5:
			var dir := -c.get_normal()
			dir.y = 0.0
			if dir.length() > 0.01:
				prop.push.rpc_id(1, dir.normalized() * speed_before * prop.mass * 0.8)

	_update_prompt()
	_publish(Vector2(velocity.x, velocity.z).length())

func _walk(delta: float, input: Vector2, speed: float) -> void:
	var wish := global_basis * Vector3(input.x, 0.0, input.y)
	var hv := Vector2(velocity.x, velocity.z)
	var tv := Vector2(wish.x, wish.z) * speed
	var rate := AIR_ACCEL
	if is_on_floor():
		rate = ACCEL if tv.length() > 0.01 else STOP_DECEL
	hv = hv.move_toward(tv, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.y

	_coyote = 0.12 if is_on_floor() else _coyote - delta
	_jump_buf = 0.12 if (Input.is_action_just_pressed("jump") and not input_locked) else _jump_buf - delta
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_snd("jump", -4.0)
		_jump_buf = 0.0
		_coyote = 0.0

func _swim(delta: float, input: Vector2, surface: float) -> void:
	_coyote = 0.0
	var target := (camera.global_basis * Vector3(input.x, 0.0, input.y)) * SWIM_SPEED
	var vert := 0.0 if input_locked else Input.get_action_strength("jump") - Input.get_action_strength("crouch")
	if vert != 0.0:
		target.y = vert * 2.5
	elif input == Vector2.ZERO:
		target.y = clampf((surface - 1.45 - global_position.y) * 2.5, -2.0, 2.0)  # float at the surface
	velocity = velocity.move_toward(target, 10.0 * delta)
	if not input_locked and Input.is_action_pressed("jump") and surface - global_position.y < 1.7 and input != Vector2.ZERO:
		velocity.y = 5.5  # hop out of the pool

func _publish(spd: float) -> void:
	net_pos = global_position
	_air_t = 0.0 if is_on_floor() else _air_t + get_physics_process_delta_time()
	var st := 0
	if _ride != null and is_instance_valid(_ride):
		st = 3 if (_ride.kind == "coupe" or _seat) else (5 if _ride.kind == "cart" else 4)
		veh_yaw = _ride.global_rotation.y
	elif _swimming:
		st = 2
	elif _air_t > 0.15:
		st = 1
	anim_state = st
	yaw = rotation.y
	move_speed = spd
	if _ragdoll != null and _ragdoll.active:
		pose = PlayerRig.encode(_ragdoll.bodies)

func _respawn() -> void:
	if severed != 0 or gloves_on:
		severed = 0          # back in one piece
		gloves_on = false
		_build_viewmodel()
	if ragdolled:
		_ragdoll.clear()
		ragdolled = false
		collision_layer = 1
	velocity = Vector3.ZERO
	global_position = _world.spawn_point if _world != null else Vector3(-4.6, 0.2, 1.7)
	rotation.y = yaw
	if head != null:
		head.top_level = false
		head.position = Vector3(0, EYE, 0)
		head.rotation = Vector3(pitch, 0, 0)

# ------------------------------------------------------------------- ragdoll
func set_ragdoll(on: bool, extra := Vector3.ZERO) -> void:
	if on == ragdolled or _ragdoll == null:
		return
	carrier = 0
	if on:
		if _ride != null:
			_dismount(Vector3.ZERO)
		drop_equipped(Vector3.ZERO)
		_ragdoll.spawn(rig, velocity + extra, self)
		_rag_time = 0.0
		ragdolled = true
		collision_layer = 0   # my standing capsule is out of the way while I flop
	else:
		var t := _ragdoll.torso().global_position
		var floor_y := _find_floor(t)
		_ragdoll.clear()
		global_position = Vector3(t.x, floor_y + 0.05, t.z)
		velocity = Vector3.ZERO
		ragdolled = false
		collision_layer = 1

func _find_floor(pos: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 4.0, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return pos.y - 1.0
	return (hit["position"] as Vector3).y

func _ragdoll_step(delta: float) -> void:
	_rag_time += delta
	_ragdoll.step(_world)
	var t := _ragdoll.torso()
	global_position = t.global_position - Vector3(0.0, TORSO_Y, 0.0)
	var speed := t.linear_velocity.length()
	if carrier != 0:
		var holder := _world.get_node_or_null(str(carrier)) as Player
		if holder == null or holder.ragdolled:
			_release_carrier(Vector3.ZERO)
		else:
			var target := holder.global_position + Vector3(0.0, 2.3, 0.0)
			var v := ((target - t.global_position) * 10.0).limit_length(12.0)
			t.linear_velocity = v
			t.angular_velocity *= 0.8
			for b in _ragdoll.bodies:
				if b != t:
					b.linear_velocity = b.linear_velocity.lerp(v, 0.1)
			if _rag_time > 1.5 and Input.is_action_just_pressed("jump"):   # wriggle free
				holder.carry_ended.rpc_id(holder.get_multiplayer_authority())
				_release_carrier(Vector3(0.0, 2.0, 0.0))
			return
	var wants_up := Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("flop")
	if _rag_time > 0.8 and speed < 3.0 and wants_up:
		set_ragdoll(false)
	elif _rag_time > 6.0 and speed < 0.8:
		set_ragdoll(false)

## Walking into people pushes them along (players and the wandering NPCs).
var _ext_push := Vector3.ZERO
var _climbing := false
var _push_cd := {}

func _push_bodies(my_h: Vector3, _delta: float) -> void:
	if my_h.length() < 0.6:
		return
	var now := Time.get_ticks_msec()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other == null or other == self:
			continue
		var key := other.get_instance_id()
		if now - int(_push_cd.get(key, 0)) < 90:
			continue
		var dir := Vector3(-col.get_normal().x, 0.0, -col.get_normal().z)
		if dir.length() < 0.2:
			continue
		dir = dir.normalized()
		var strength := clampf(my_h.dot(dir), 0.0, 9.0) * (1.6 if Input.is_action_pressed("sprint") else 1.0)
		if strength < 0.3:
			continue
		_push_cd[key] = now
		if other is Player:
			(other as Player).nudge.rpc_id((other as Player).get_multiplayer_authority(), dir * strength * 0.55)
		elif other is Npc:
			(other as Npc).nudge.rpc_id(1, dir * strength * 0.9)

@rpc("any_peer", "call_local", "unreliable")
func nudge(vel: Vector3) -> void:
	if not is_multiplayer_authority() or ragdolled or _ride != null:
		return
	vel.y = 0.0
	_ext_push = (_ext_push + vel.limit_length(4.0)).limit_length(6.0)

## Sent to the owner by explosions, shoves and bonking props.
@rpc("any_peer", "call_local", "reliable")
func knock(vel: Vector3) -> void:
	if not is_multiplayer_authority() or _ragdoll == null:
		return
	vel = vel.limit_length(10.0)   # nothing ever launches you across the map
	_snd("thud", 1.0)
	if ragdolled:
		_ragdoll.add_velocity(vel * 0.5)
	else:
		set_ragdoll(true, vel)

func _on_rag_prop(prop: Prop, vel: Vector3) -> void:
	var now := Time.get_ticks_msec()
	var key := prop.get_instance_id()
	if now - int(_rag_cd.get(key, 0)) < 150:
		return
	_rag_cd[key] = now
	prop.push.rpc_id(1, vel.limit_length(8.0) * prop.mass * 0.15)

# ------------------------------------------- carrying knocked-out people
func _find_downed() -> Player:
	if camera == null:
		return null
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var best: Player = null
	var best_d := 3.2
	for n in get_tree().get_nodes_in_group("players"):
		var other := n as Player
		if other == null or other == self or not other.ragdolled:
			continue
		var off := (other.global_position + Vector3.UP * 0.5) - from
		var d := off.length()
		if d < best_d and off.normalized().dot(fwd) > 0.2:
			best_d = d
			best = other
	return best

## Near a cart: sit in it (from the front or sides, or when someone is already pushing),
## or push it (from behind the handle, or when someone is already sitting in it).
func _cart_wants_seat(c: Prop) -> bool:
	if c.rider != 0:
		return c.passenger == 0
	if c.passenger != 0:
		return false
	var local := Basis(Vector3.UP, c.global_rotation.y).inverse() * (global_position - c.global_position)
	return local.z < 0.45

func _find_rocket() -> Prop:
	var best: Prop = null
	var best_d := 8.0
	for n in get_tree().get_nodes_in_group("props"):
		var p := n as Prop
		if p == null or (p.kind != "rocket" and not Prop.is_vehicle(p.kind)) or p.exploded:
			continue
		var d := p.global_position.distance_to(global_position + Vector3.UP)
		if Prop.is_vehicle(p.kind) and (d > 3.0 or (p.rider != 0 and (p.kind != "cart" or p.passenger != 0))):
			continue
		if d < best_d:
			best_d = d
			best = p
	return best

func _drop_carried(throw_them: bool) -> void:
	var victim: Player = null
	if _world != null:
		victim = _world.get_node_or_null(str(carrying)) as Player
	if victim != null and victim.ragdolled:
		var vel := Vector3(0.0, 1.0, 0.0)
		if throw_them and camera != null:
			vel = -camera.global_basis.z * 7.0 + Vector3.UP * 3.0
		victim.released_by.rpc_id(victim.get_multiplayer_authority(), vel)
	carrying = 0
	holding = equipped != ""

## (victim) someone lifts me up.
@rpc("any_peer", "call_remote", "reliable")
func picked_up_by(holder_id: int) -> void:
	if not is_multiplayer_authority() or not ragdolled or _ragdoll == null:
		return
	carrier = holder_id
	_rag_time = 0.0
	_ragdoll.set_mask(0)

## (victim) I was put down or thrown.
@rpc("any_peer", "call_remote", "reliable")
func released_by(vel: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	_release_carrier(vel)

func _release_carrier(vel: Vector3) -> void:
	carrier = 0
	_rag_time = 0.0
	if _ragdoll != null and _ragdoll.active:
		_ragdoll.set_mask(1)
		_ragdoll.add_velocity(vel.limit_length(9.0))

## (holder) the person I carried wriggled free.
@rpc("any_peer", "call_remote", "reliable")
func carry_ended() -> void:
	if is_multiplayer_authority():
		carrying = 0
		holding = equipped != ""

# --------------------------------------------------------- rocket riding
@rpc("any_peer", "call_local", "reliable")
func begin_ride(path: NodePath, seat := false) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	var rk := get_node_or_null(path) as Prop
	if rk == null:
		return
	drop_equipped(Vector3.ZERO)
	_ride = rk
	_seat = seat
	ride_name = rk.name
	velocity = Vector3.ZERO

@rpc("any_peer", "call_local", "reliable")
func stop_ride() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	_ride = null
	_seat = false
	ride_name = ""
	velocity = Vector3(0.0, 2.0, 0.0)

func _ride_step() -> void:
	if not is_instance_valid(_ride) or _ride.exploded:
		_ride = null
		ride_name = ""
		velocity = Vector3(0.0, 2.0, 0.0)
		return
	if not input_locked and Input.is_action_just_pressed("jump"):
		_dismount(-camera.global_basis.z * 5.0 + Vector3.UP * 4.0)
		return
	if _seat:
		# riding in the cart's basket, knees up, while someone else pushes
		global_position = _ride.global_position + ride_offset(_ride, true)
		velocity = Vector3.ZERO
		_publish(0.0)
		return
	if _ride.kind == "cart":
		var thr2 := 0.0
		var steer2 := 0.0
		if not input_locked:
			thr2 = Input.get_axis("move_back", "move_forward")
			steer2 = Input.get_axis("move_left", "move_right")
		var run := not input_locked and Input.is_action_pressed("sprint")
		_ride.drive.rpc_id(1, thr2, steer2, run)
		var was := global_position
		global_position = _ride.global_position + ride_offset(_ride, false)   # behind the handle
		velocity = Vector3.ZERO
		_publish((global_position - was).length() / maxf(get_physics_process_delta_time(), 0.001))
		return
	if _ride.kind == "coupe":
		var thr := 0.0
		var steer := 0.0
		if not input_locked:
			thr = Input.get_axis("move_back", "move_forward")
			steer = Input.get_axis("move_left", "move_right")
		var boost := not input_locked and Input.is_action_pressed("sprint")
		_ride.drive.rpc_id(1, thr, steer, boost)
		_set_prompt("W/S drive   A/D steer   hold SHIFT for rocket boosters   Space get out")
		global_position = _ride.global_position + _ride.global_basis * Vector3(0.0, -0.45, 0.15)   # bum on the seat, legs folded up
	else:
		global_position = _ride.global_position + Vector3(0.0, 0.15, 0.0)
	velocity = Vector3.ZERO
	_publish(0.0)

func _dismount(kick: Vector3) -> void:
	var rk := _ride
	_ride = null
	ride_name = ""
	var was_seat := _seat
	_seat = false
	if rk != null and is_instance_valid(rk):
		if was_seat:
			global_position = rk.global_position + Basis(Vector3.UP, rk.global_rotation.y) * Vector3(0.9, -0.3, 0.0) + Vector3.UP * 0.3
			velocity = kick.limit_length(9.0)
			rk.leave_seat.rpc_id(1)
			return
		if rk.kind == "cart":
			global_position = rk.global_position + Basis(Vector3.UP, rk.global_rotation.y) * Vector3(0.0, -0.4, 1.1) + Vector3.UP * 0.2
		elif rk.kind == "coupe":
			global_position = rk.global_position + rk.global_basis * Vector3(1.0, 0.0, 0.2) + Vector3.UP * 0.4
		velocity = kick.limit_length(9.0)
		rk.end_ride.rpc_id(1)

# ------------------------------------------------- items in your hand
func _ray() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _set_equipped(k: String, t := "") -> void:
	equipped_tint = t
	equipped = k
	holding = k != ""

## The prop nearest to the crosshair within reach (generous: a cone, not a thin ray).
func _find_prop() -> Prop:
	if camera == null:
		return null
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var best: Prop = null
	var best_score := 999.0
	for n in get_tree().get_nodes_in_group("props"):
		var p := n as Prop
		if p == null or p.exploded:
			continue
		var off := p.global_position - from
		var dist := off.length()
		if dist > 3.8 or dist < 0.05:
			continue
		var ang := acos(clampf(off.normalized().dot(fwd), -1.0, 1.0))
		var allow := 0.2 + 0.35 / maxf(dist, 0.6)   # radians; closer things are easier to hit
		if ang > allow:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, p.global_position, 1)
		q.exclude = [get_rid()]
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty() and res["collider"] != p:
			continue   # something solid in the way
		var score := ang + dist * 0.03
		if score < best_score:
			best_score = score
			best = p
	return best

func _try_pickup() -> void:
	var prop := _find_prop()
	if prop != null:
		prop.pickup.rpc_id(1)

## The server sends this when my pickup succeeded.
@rpc("any_peer", "call_local", "reliable")
func equip(kind: String, tint := "") -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	if equipped != "":
		if inventory.size() < INVENTORY_SIZE:
			inventory.append([equipped, equipped_tint])   # the old item goes into the weapon wheel
		else:
			drop_equipped(Vector3.ZERO)
	_set_equipped(kind, tint)

## The shop shelf row I'm looking at, or "".
func _shelf_in_view() -> String:
	if _world == null or _world.house == null or _world.custom_map or camera == null:
		return ""
	if global_position.z < 60.0:   # only inside the shop (saves work everywhere else)
		return ""
	return _world.house.shelf_kind_at(camera.global_position, -camera.global_basis.z)

## Rubber gloves on and somebody within grabbing range in front of me?
func _someone_to_rip() -> bool:
	if _world == null or camera == null:
		return false
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var cands: Array = get_tree().get_nodes_in_group("npcs")
	cands.append_array(get_tree().get_nodes_in_group("players"))
	for n in cands:
		var b := n as Node3D
		if b == null or b == self:
			continue
		var off := (b.global_position + Vector3.UP * 0.9) - from
		if off.length() < 2.8 and off.normalized().dot(fwd) > 0.45:
			return true
	return false

const REGROW_TIME := 15.0   # seconds after losing a limb until it all grows back
var _regrow_t := 0.0

## Lost limbs grow back (with a silly boing).
func _regrow() -> void:
	severed = 0
	_regrow_t = 0.0
	_build_viewmodel()
	_snd("boing", 2.0)

## The server says a limb of mine came off.
@rpc("any_peer", "call_local", "reliable")
func lose_limb(bit: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	severed |= bit
	_regrow_t = 0.0   # the regrow countdown starts again from the latest loss
	_snd("thud", 3.0)
	_ghost_arms()
	if bit == 1:
		# lost my head: down I go, and back to the spawn point in a moment
		set_ragdoll(true, Vector3.UP * 2.0)
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(self) and severed & 1:
				_respawn())

## "skin|hair" colours for a body part torn off me.
func tint_string() -> String:
	var nb := _custom as NpcBody
	if nb != null:
		return nb.skin_color().to_html(false) + "|" + nb.hair_color().to_html(false)
	if rig != null:
		return rig.skin.to_html(false) + "|" + rig.hair.to_html(false)
	return ""

## Arms I have lost turn into spooky see-through ghost arms in first person (they still work).
func _ghost_arms() -> void:
	var ghost := StandardMaterial3D.new()
	ghost.albedo_color = Color(0.7, 0.95, 1.0, 0.28)
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.emission_enabled = true
	ghost.emission = Color(0.45, 0.85, 1.0)
	ghost.emission_energy_multiplier = 0.9
	ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in _vm_arms.size():
		var lost: bool = (severed & 2) != 0 if i == 0 else (severed & 4) != 0
		if not lost:
			continue
		for m in _vm_arms[i].find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = ghost

func _tint_fp_hands() -> void:
	if not gloves_on:
		return
	var rubber := Mats.solid(Color(1.0, 0.85, 0.1), 0.35)
	for a in _vm_arms:
		var hand := a.get_meta("hand") as Node3D
		if hand == null:
			continue
		for m in hand.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = rubber

## Picked up the rubber gloves: they go on your hands (until you respawn).
@rpc("any_peer", "call_local", "reliable")
func wear_gloves() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	gloves_on = true
	_snd("pickup", 0.0)
	_tint_fp_hands()

## A point in front of me that is not inside a wall.
func _front_point(want: float) -> Vector3:
	var fwd := -camera.global_basis.z
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * (want + 0.4), 1)
	q.exclude = [get_rid()]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var d := want
	if not res.is_empty():
		d = maxf(0.5, from.distance_to(res["position"]) - 0.5)
	return from + fwd * d

## Put the item back into the world as a normal physics prop.
func drop_equipped(vel: Vector3) -> void:
	if equipped == "" or _world == null or camera == null:
		return
	var k := equipped
	var t := equipped_tint
	_set_equipped("")
	_world.request_throw.rpc_id(1, k, _front_point(0.8) + Vector3.DOWN * 0.25, vel, t)

func throw_equipped() -> void:
	if equipped == "" or _world == null or camera == null:
		return
	var k := equipped
	var t := equipped_tint
	var power := 13.0 - minf(float(Prop.def_of(k)["mass"]), 6.0) * 1.2
	_set_equipped("")
	_snd("throw", -2.0)
	_world.request_throw.rpc_id(1, k, _front_point(0.7), -camera.global_basis.z * power + velocity * 0.5, t)

func _use_equipped() -> void:
	if _use_cd > 0.0 or ragdolled:
		return
	if equipped == "cig":
		# lift it to my mouth first; _update_viewmodel fires the puff when it gets there
		if _cig_t < 0.0:
			_cig_t = 0.0
			_cig_puffed = false
			_use_cd = CIG_TIME + 0.2
		return
	_use_cd = float(Prop.ITEMS[equipped]["cd"])
	_world.use_item.rpc_id(1, equipped, camera.global_position, -camera.global_basis.z)
	if equipped == "pistol":
		shake(0.25)

func _do_swing() -> void:
	var ch := clampf(_charge, 0.0, 1.0)
	_charge = -1.0
	if not MELEE.has(equipped) or _world == null or camera == null:
		return
	_swing_charge = ch
	_swing_side = -_swing_side
	_swing_t = 0.0
	_use_cd = float(Prop.ITEMS[equipped]["cd"]) * (1.0 + ch * 0.5)
	_snd("whoosh", -4.0 + ch * 6.0)
	_world.melee_swing.rpc_id(1, equipped, camera.global_position, -camera.global_basis.z, ch, _swing_side)

## The server says my swing connected: a little kick so it feels like it landed.
@rpc("any_peer", "call_local", "unreliable")
func melee_hit(strength: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	shake(clampf(0.12 + strength * 0.02, 0.12, 0.5))
	_snd("thud", clampf(-6.0 + strength * 0.3, -6.0, 4.0))

# ------------------------------------------------------------- weapon wheel
func _open_wheel() -> void:
	if _world == null or ragdolled:
		return
	_charge = -1.0
	_wheel = WeaponWheel.new()
	_wheel.setup(self)
	var layer := CanvasLayer.new()
	layer.layer = 14
	add_child(layer)
	layer.add_child(_wheel)
	input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	_wheel.tree_exited.connect(func():
		layer.queue_free()
		_wheel = null
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

## Wheel choice: -1 = empty hands (what I hold goes into the wheel), otherwise take slot i out.
func wheel_pick(i: int) -> void:
	if i < 0:
		if equipped != "" and inventory.size() < INVENTORY_SIZE:
			inventory.append([equipped, equipped_tint])
			_set_equipped("")
			_snd("pickup", -6.0)
		return
	if i >= inventory.size():
		return
	var e: Array = inventory[i]
	if equipped != "":
		inventory[i] = [equipped, equipped_tint]   # swap
	else:
		inventory.remove_at(i)
	_set_equipped(String(e[0]), String(e[1]))
	_snd("pickup", -6.0)

## Effects of the item I hold (muzzle flash, swing, puff...). Sent by the server to everyone.
@rpc("any_peer", "call_local", "reliable")
func item_fx(what: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender > 1 and sender != get_multiplayer_authority():
		return
	var v := _vm_item if _vm_item != null else _hand_item
	if v != null and is_instance_valid(v):
		v.play_fx(what)

## Food and drink effects (sent by the server when you finish an item).
@rpc("any_peer", "call_local", "reliable")
func consume(kind: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	get_tree().create_timer(0.3).timeout.connect(_set_equipped.bind(""))
	match kind:
		"beer":
			drunk = 45.0
		"soda":
			rush = 20.0

## Workshop character: show the .glb model instead of the built-in body (others only; I see my own hands).
func _update_custom_body(mine: bool) -> void:
	if rig == null:
		return
	var model_id: String = str(_look.get("model", ""))
	var npc: Dictionary = {}
	if model_id.is_empty() and _look.get("npc", {}) is Dictionary:
		npc = _look.get("npc", {})
	var want := model_id
	if want.is_empty() and not npc.is_empty():
		want = "npc:%d" % npc.hash()
	if want != _custom_id:
		_custom_id = want
		if _custom != null:
			_custom.queue_free()
			_custom = null
		if want.is_empty():
			pass
		elif not npc.is_empty():
			var nb := NpcBody.new()
			add_child(nb)
			if nb.load_npc(npc):
				_custom = nb
				if mine and camera != null:
					_build_viewmodel()   # my first-person arms come from this character
			else:
				_custom_failed = want
				nb.queue_free()
		elif Content.has(want):
			var body := CustomBody.new()
			add_child(body)
			if body.load_model(want):
				_custom = body
			else:
				_custom_failed = want
				body.queue_free()
	elif not model_id.is_empty() and _custom == null and _custom_failed != want and Content.has(want):
		_custom_id = ""   # the file just arrived over the network: try again next frame
	_custom_apply(mine)

## Show the chosen character instead of the built-in body. My own is visible too (body when I look down,
## and while ragdolled once the camera has pulled back); a limp ragdoll carries the model along with its torso.
func _custom_apply(mine: bool) -> void:
	if _custom == null:
		return
	var standing := not ragdolled
	var show_custom := true
	if mine:
		if ragdolled:
			show_custom = _cam_far
		else:
			show_custom = third_person   # in first person you only see your arms
	var nb := _custom as NpcBody
	if nb != null:
		nb.set_first_person(false)
		var st := anim_state if not ragdolled else 0
		var hold := 0
		if holding and not ragdolled:
			if equipped == "":
				hold = 3   # carrying a person
			elif float(Prop.def_of(equipped)["half"]) >= 0.25:
				hold = 2
			else:
				hold = 1
		nb.set_severed(severed)
		if st == 5:   # pushing a cart: walk with both hands out on the handle
			nb.set_pose(0, 2)
		else:
			nb.set_pose(st, hold)
		nb.scale = Vector3.ONE   # full size even in the toy car: that is the joke
	_custom.visible = show_custom
	_custom.animate(move_speed, not standing)
	if ragdolled and not rig.parts.is_empty():
		_custom.top_level = true
		if nb != null:
			var ts: Array = []
			for part in rig.parts:
				ts.append(part.global_transform)
			nb.set_ragdoll(ts)
		var torso: Transform3D = rig.parts[PlayerRig.TORSO].global_transform
		_custom.global_transform = Transform3D(torso.basis.orthonormalized(), torso.origin) * Transform3D(Basis(), Vector3(0, -1.1, 0))
	else:
		if nb != null:
			nb.set_ragdoll([])
		if _custom.top_level:
			_custom.top_level = false
		_custom.position = Vector3.ZERO
		_custom.rotation = Vector3.ZERO
		if nb != null and anim_state >= 3:
			_custom.rotation.y = wrapf(veh_yaw - rotation.y, -PI, PI)   # face where the vehicle points
	if mine and nb == null:
		_custom.visible = false   # Workshop models stay hidden for me
		return
	for v in rig.visuals:
		v.visible = false
	for v in rig.head_visuals:
		v.visible = false

## Build / remove the model in the hand, and keep it glued to it.
func _update_item_visuals() -> void:
	if rig == null:
		return
	if equipped + equipped_tint != _shown:
		_shown = equipped + equipped_tint
		_equip_anim = 0.0
		if _vm_item != null:
			_vm_item.queue_free()
			_vm_item = null
		if _hand_item != null:
			_hand_item.queue_free()
			_hand_item = null
		if equipped != "" and Prop.is_valid_kind(equipped):
			var v := Prop.new()
			v.kind = equipped
			v.tint = equipped_tint
			v.visual_only = true
			v.name = "HandItem"
			add_child(v)
			if is_multiplayer_authority():
				_vm_item = v
			else:
				_hand_item = v
	var half := 0.1
	if equipped != "" and Prop.is_valid_kind(equipped):
		half = float(Prop.def_of(equipped)["half"])
	var sc := 0.5 if half >= 0.25 else (0.7 if half >= 0.2 else 1.0)
	if _vm_item != null and camera != null and not third_person:
		_vm_item.visible = not ragdolled
		_equip_anim = minf(1.0, _equip_anim + get_process_delta_time() * 4.5)   # placed by _update_viewmodel
	elif (_hand_item != null or _vm_item != null) and not rig.parts.is_empty():
		var held: Prop = _hand_item if _hand_item != null else _vm_item
		held.visible = not ragdolled
		var nbody := _custom as NpcBody
		if nbody != null and _custom.visible:
			# in the character's right hand, facing the way the character faces (tilted with the look pitch)
			var face := Basis(Vector3.UP, rotation.y if anim_state < 3 else veh_yaw)
			var tilt := Basis(Vector3.RIGHT, clampf(pitch * 0.6, -0.6, 0.6))
			held.global_transform = Transform3D(face * tilt * Basis.from_scale(Vector3.ONE * sc), nbody.hand_point())
		else:
			var hand := rig.parts[PlayerRig.LARM_R]
			var local := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3.ONE * sc), Vector3(0, -0.3, -0.04))
			held.global_transform = hand.global_transform * local

func _update_prompt() -> void:
	if _ride != null:
		if _seat:
			_set_prompt("Enjoy the ride!   F or SPACE climb out")
		elif _ride.kind == "cart":
			_set_prompt("W/S push   A/D turn   SHIFT run   ram into people!   F let go")
		elif _ride.kind == "coupe":
			_set_prompt("W/S drive   A/D steer   F or SPACE get out")
		else:
			_set_prompt("Look to steer   SPACE bail out")
		return
	if carrying != 0:
		_set_prompt("LMB throw   F put down   (they can wriggle free)")
		return
	if equipped == "" and _world != null and _world.nearest_pc(global_position) == null:
		var rk := _find_rocket()
		if rk != null:
			if rk.kind == "cart":
				_set_prompt("F  hop in the cart" if _cart_wants_seat(rk) else "F  push the shopping cart")
			else:
				_set_prompt("F  drive the toy coupe" if rk.kind == "coupe" else "F  RIDE THE ROCKET!")
			return
		var down := _find_downed()
		if down != null:
			_set_prompt("F  pick up %s" % Net.players.get(down.name.to_int(), {}).get("name", "them"))
			return
	if _climbing or (_world != null and _swimming and not _world.ladder_near(global_position).is_empty()):
		_set_prompt("Hold W or SPACE to climb the ladder")
		return
	if equipped != "":
		if MELEE.has(equipped):
			_set_prompt("Hold LMB to wind up, let go to swing   G throw   RMB put down   Q wheel")
		elif Prop.ITEMS.has(equipped):
			_set_prompt("LMB use   G throw   RMB put down   Q wheel")
		else:
			_set_prompt("LMB throw   RMB put down")
	else:
		var target := _find_prop()
		if target != null:
			_set_prompt("RMB pick up %s" % Prop.LABELS.get(target.kind, target.kind))
		elif _world != null and _world.nearest_pc(global_position) != null:
			_set_prompt("F  use the computer")
		elif _shelf_in_view() != "":
			var sk := _shelf_in_view()
			_set_prompt("F  take %s ($%d)   (you have $%d)" % [Prop.LABELS.get(sk, sk), int(GameWorld.PRICES.get(sk, 0)), _world.my_money])
		elif _world != null and _world.near_shop(global_position):
			_set_prompt("F  shop  ($%d)" % _world.my_money)
		else:
			_set_prompt("")
	if _dot != null:
		var near := equipped == "" and _prompt != null and _prompt.text.begins_with("RMB pick")
		var sbx := _dot.get_theme_stylebox("panel") as StyleBoxFlat
		sbx.bg_color = Color(0.4, 1.0, 0.5) if near else Color.WHITE
		_dot.scale = Vector2.ONE * (1.6 if near else 1.0)

## Spawn a toy / item just in front of me (never inside a wall).
func spawn_kind(kind: String) -> void:
	if _world == null or camera == null:
		return
	_world.request_spawn.rpc_id(1, kind, _front_point(2.0))

func _set_prompt(text: String) -> void:
	if _prompt != null:
		_prompt.text = text

func _shove() -> void:
	if _shove_cd > 0.0 or ragdolled:
		return
	_shove_cd = 0.45
	var fwd := -camera.global_basis.z
	var origin := camera.global_position
	for n in get_tree().get_nodes_in_group("props"):
		var prop := n as Prop
		var off := prop.global_position - origin
		if off.length() < 2.6 and off.normalized().dot(fwd) > 0.5:
			prop.hit.rpc_id(1, fwd * 5.0 * maxf(prop.mass, 1.0) + Vector3.UP * 1.5)
	for n2 in get_tree().get_nodes_in_group("npcs"):
		var npc := n2 as Npc
		if npc == null or npc.dead:
			continue
		var off2 := (npc.global_position + Vector3.UP * 1.0) - origin
		if off2.length() < 2.4 and off2.normalized().dot(fwd) > 0.5:
			npc.shove.rpc_id(1, fwd * 6.0 + Vector3.UP * 3.0)
	for n in get_tree().get_nodes_in_group("players"):
		var other := n as Player
		if other == self:
			continue
		var off := (other.global_position + Vector3.UP * 1.0) - origin
		if off.length() < 2.4 and off.normalized().dot(fwd) > 0.5:
			other.knock.rpc_id(other.get_multiplayer_authority(), fwd * 6.0 + Vector3.UP * 3.0)
