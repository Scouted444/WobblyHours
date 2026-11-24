class_name PlayerRig
extends Node3D
## The visible humanoid: 10 parts (torso, head, 2x upper/lower arm, 2x upper/lower leg).
## Each part's origin is the centre of its capsule. Parts are driven either by a walk-cycle
## pose (standing) or by physics bodies / network data (ragdoll).

const N := 10
const TORSO := 0
const HEAD := 1
const UARM_L := 2
const UARM_R := 3
const LARM_L := 4
const LARM_R := 5
const ULEG_L := 6
const ULEG_R := 7
const LLEG_L := 8
const LLEG_R := 9

## [radius, capsule height] per part. The head is a sphere (radius only).
const DIMS := [
	[0.17, 0.62], [0.13, 0.0], [0.06, 0.30], [0.06, 0.30], [0.05, 0.32], [0.05, 0.32],
	[0.08, 0.45], [0.08, 0.45], [0.065, 0.45], [0.065, 0.45]]
const MASSES := [14.0, 4.0, 2.6, 2.6, 2.0, 2.0, 5.5, 5.5, 3.6, 3.6]   # kept within ~7:1 so the joints stay stable

const SKINS := [Color(0.96, 0.8, 0.69), Color(0.87, 0.67, 0.5), Color(0.68, 0.47, 0.33), Color(0.45, 0.3, 0.2), Color(0.3, 0.2, 0.14)]
const HAIRS := [Color(0.1, 0.07, 0.05), Color(0.35, 0.2, 0.1), Color(0.85, 0.7, 0.35), Color(0.6, 0.15, 0.1), Color(0.2, 0.2, 0.25)]

var parts: Array[Node3D] = []
var visuals: Array[VisualInstance3D] = []
var head_visuals: Array[VisualInstance3D] = []
var skin := Color.WHITE
var shirt := Color.WHITE
var pants := Color.WHITE
var shoe := Color.WHITE
var hair := Color.BLACK

static func shape_for(i: int) -> Shape3D:
	if i == HEAD:
		var s := SphereShape3D.new()
		s.radius = DIMS[i][0]
		return s
	var c := CapsuleShape3D.new()
	c.radius = DIMS[i][0]
	c.height = DIMS[i][1]
	return c

var look := {}
var head_size := 1.0

## id is only used for a stable random look when no look is given.
func setup(id: int, new_look := {}) -> void:
	top_level = true
	_apply_look(new_look if not new_look.is_empty() else Look.random_look(id))
	for i in N:
		parts.append(_build_part(i))

## Throw the model away and build it again (the player changed their look).
func rebuild(new_look: Dictionary) -> void:
	for p in parts:
		remove_child(p)
		p.queue_free()
	parts.clear()
	visuals.clear()
	head_visuals.clear()
	_apply_look(new_look)
	for i in N:
		parts.append(_build_part(i))

func _apply_look(new_look: Dictionary) -> void:
	look = Look.sanitize(new_look)
	skin = Look.color_of(look, "skin")
	hair = Look.color_of(look, "hair_color")
	shirt = Look.color_of(look, "shirt")
	pants = Look.color_of(look, "pants")
	shoe = Look.color_of(look, "shoes")
	head_size = float(look["head_size"])

func set_layers(body_layer: int, head_layer: int) -> void:
	for v in visuals:
		v.layers = body_layer
	for v in head_visuals:
		v.layers = head_layer

# ------------------------------------------------------------------- models
func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl := Vector3.ONE, is_head := false, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.solid(color, 0.8)
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	parent.add_child(mi)
	if is_head:
		head_visuals.append(mi)
	else:
		visuals.append(mi)

func _cap(parent: Node3D, r: float, h: float, color: Color, pos := Vector3.ZERO, scl := Vector3.ONE, is_head := false) -> void:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	_add(parent, m, color, pos, scl, is_head)

func _sph(parent: Node3D, r: float, color: Color, pos := Vector3.ZERO, scl := Vector3.ONE, is_head := false) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	_add(parent, m, color, pos, scl, is_head)

## Tapered cylinder: the building block for limbs and torso (looks like a body, not a ball).
func _cone(parent: Node3D, r_top: float, r_bot: float, h: float, color: Color, pos := Vector3.ZERO, scl := Vector3.ONE, is_head := false) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	_add(parent, m, color, pos, scl, is_head)

func _box(parent: Node3D, size: Vector3, color: Color, pos := Vector3.ZERO, is_head := false) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(parent, m, color, pos, Vector3.ONE, is_head)

const PART_MODELS := {
	TORSO: "person_torso", HEAD: "person_head", UARM_L: "person_uarm", UARM_R: "person_uarm",
	LARM_L: "person_larm_l", LARM_R: "person_larm_r", ULEG_L: "person_uleg", ULEG_R: "person_uleg",
	LLEG_L: "person_lleg", LLEG_R: "person_lleg"}

## The real body-part models (res://models/person_*.glb), tinted with this player's look.
func _build_model_part(n: Node3D, i: int) -> bool:
	var model := ModelLib.make(PART_MODELS[i])
	if model == null:
		return false
	ModelLib.tint(model, {
		"skin": skin, "skin_dark": skin.darkened(0.06), "shirt": shirt, "shirt_dark": shirt.darkened(0.22),
		"pants": pants, "pants_dark": pants.darkened(0.22), "shoe": shoe, "sole": shoe.darkened(0.45), "hair": hair})
	var host: Node3D = n
	if i == HEAD:
		var hp := Node3D.new()   # hair, hat... live here so "head size" scales everything
		hp.scale = Vector3.ONE * head_size
		n.add_child(hp)
		host = hp
	host.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if i == HEAD or String(mi.name).begins_with("Neck") or String(mi.name).begins_with("Head"):
			head_visuals.append(mi)
		else:
			visuals.append(mi)
	if i == TORSO and look["stripes"]:
		for k in 4:
			var y := 0.0 + k * 0.08
			var rr := 0.15 + (y + 0.06) / 0.36 * 0.04 + 0.004
			_cone(n, rr, rr, 0.035, shirt.lightened(0.55), Vector3(0, y, 0), Vector3(1.0, 1.0, 0.62))
	if i == HEAD:
		_build_hair(host)
		_build_beard(host)
		_build_glasses(host)
		_build_hat(host)
	return true

func _build_part(i: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	if _build_model_part(n, i):
		return n
	match i:
		TORSO:
			_cone(n, 0.19, 0.15, 0.36, shirt, Vector3(0, 0.12, 0), Vector3(1.0, 1.0, 0.62))   # chest
			_cone(n, 0.15, 0.145, 0.2, shirt, Vector3(0, -0.1, 0), Vector3(1.0, 1.0, 0.66))   # waist
			if look["stripes"]:
				for k in 4:
					var y := 0.0 + k * 0.08
					var r := 0.15 + (y + 0.06) / 0.36 * 0.04 + 0.004
					_cone(n, r, r, 0.035, shirt.lightened(0.55), Vector3(0, y, 0), Vector3(1.0, 1.0, 0.62))
			_cone(n, 0.16, 0.158, 0.17, pants, Vector3(0, -0.27, 0), Vector3(1.0, 1.0, 0.7))  # hips
			_cone(n, 0.162, 0.162, 0.035, Color(0.16, 0.12, 0.09), Vector3(0, -0.185, 0), Vector3(1.0, 1.0, 0.7))  # belt
			_box(n, Vector3(0.04, 0.03, 0.01), Color(0.8, 0.7, 0.3), Vector3(0, -0.185, -0.118))  # buckle
			_sph(n, 0.07, shirt, Vector3(-0.215, 0.25, 0))   # shoulders
			_sph(n, 0.07, shirt, Vector3(0.215, 0.25, 0))
			_cone(n, 0.044, 0.05, 0.11, skin, Vector3(0, 0.345, 0), Vector3.ONE, true)       # neck
		HEAD:
			var hp := Node3D.new()  # everything on the head lives here so "head size" can scale it
			hp.scale = Vector3.ONE * head_size
			n.add_child(hp)
			_sph(hp, 0.135, skin, Vector3(0, 0.02, 0), Vector3(0.96, 1.08, 0.98), true)
			_sph(hp, 0.1, skin, Vector3(0, -0.065, -0.025), Vector3(0.88, 0.8, 0.9), true)   # jaw / chin
			for side in [-1.0, 1.0]:
				_sph(hp, 0.045, skin.darkened(0.04), Vector3(0.125 * side, 0.0, 0.0), Vector3(0.45, 0.75, 0.55), true)
				_sph(hp, 0.03, Color.WHITE, Vector3(0.048 * side, 0.025, -0.118), Vector3.ONE, true)
				_sph(hp, 0.015, Color(0.08, 0.08, 0.1), Vector3(0.048 * side, 0.025, -0.142), Vector3.ONE, true)
				_box(hp, Vector3(0.05, 0.012, 0.02), hair, Vector3(0.048 * side, 0.062, -0.125), true)
			_sph(hp, 0.022, skin.darkened(0.08), Vector3(0, -0.005, -0.128), Vector3(0.8, 0.7, 1.1), true)
			_box(hp, Vector3(0.055, 0.012, 0.02), Color(0.55, 0.24, 0.28), Vector3(0, -0.055, -0.128), true)
			_build_hair(hp)
			_build_beard(hp)
			_build_glasses(hp)
			_build_hat(hp)
		UARM_L, UARM_R:
			_cone(n, 0.062, 0.057, 0.17, shirt, Vector3(0, 0.065, 0))        # sleeve
			_cone(n, 0.052, 0.047, 0.15, skin, Vector3(0, -0.075, 0))        # bare arm
			_sph(n, 0.064, shirt, Vector3(0, 0.14, 0), Vector3(1, 0.9, 1))   # shoulder
			_sph(n, 0.046, skin, Vector3(0, -0.15, 0))                       # elbow
		LARM_L, LARM_R:
			var sx := 1.0 if i == LARM_L else -1.0   # thumb points to the body
			_cone(n, 0.046, 0.034, 0.3, skin)
			_box(n, Vector3(0.07, 0.085, 0.034), skin, Vector3(0, -0.19, 0))                 # palm
			_box(n, Vector3(0.068, 0.055, 0.026), skin.darkened(0.05), Vector3(0, -0.26, -0.004))  # fingers
			_box(n, Vector3(0.022, 0.05, 0.026), skin, Vector3(0.042 * sx, -0.2, -0.012))   # thumb
		ULEG_L, ULEG_R:
			_cone(n, 0.092, 0.07, 0.45, pants)
			_sph(n, 0.07, pants, Vector3(0, -0.225, 0))                      # knee
		_:
			_cone(n, 0.068, 0.05, 0.42, pants)
			_cone(n, 0.052, 0.05, 0.05, skin.darkened(0.1), Vector3(0, -0.18, 0))   # ankle
			_box(n, Vector3(0.1, 0.07, 0.15), shoe, Vector3(0, -0.205, -0.045))
			_sph(n, 0.052, shoe, Vector3(0, -0.205, -0.115), Vector3(1.0, 0.75, 1.0))   # rounded toe
			_box(n, Vector3(0.11, 0.025, 0.26), shoe.darkened(0.45), Vector3(0, -0.243, -0.05))  # sole
	return n

# --------------------------------------------------------------- walk cycle
func _limb(joint: Vector3, a1: float, l1: float, a2: float, l2: float) -> Array:
	var b1 := Basis(Vector3.RIGHT, a1)
	var b2 := Basis(Vector3.RIGHT, a2)
	var t1 := Transform3D(b1, joint + b1 * Vector3(0, -l1 * 0.5, 0))
	var elbow := joint + b1 * Vector3(0, -l1, 0)
	var t2 := Transform3D(b2, elbow + b2 * Vector3(0, -l2 * 0.5, 0))
	return [t1, t2]

## Local transforms (relative to the player's feet) for a standing/walking pose.
## spd: 0..1 how fast we move, pitch: look up/down in radians, hold: 0..1 arms raised.
func stand_pose(phase: float, spd: float, pitch: float, hold: float, idle_t: float) -> Array:
	var out := []
	out.resize(N)
	var bob := absf(cos(phase)) * 0.03 * spd + sin(idle_t * 1.6) * 0.004 - 0.05 * spd
	var lean := -0.1 * spd
	out[TORSO] = Transform3D(Basis(Vector3.RIGHT, lean), Vector3(0, 1.22 + bob, 0))
	out[HEAD] = Transform3D(Basis(Vector3.RIGHT, clampf(pitch, -1.0, 1.0) * 0.6 - lean * 0.5), Vector3(0, 1.70 + bob, 0))

	var sw := sin(phase) * 0.5 * spd
	var arm_l := lerpf(-sw * 0.9, 0.9, hold)
	var arm_r := lerpf(sw * 0.9, 0.9, hold)
	var elbow := lerpf(0.15 + 0.25 * spd, 0.9, hold)
	var al := _limb(Vector3(-0.25, 1.46 + bob, 0), arm_l, 0.30, arm_l + elbow, 0.30)
	var ar := _limb(Vector3(0.25, 1.46 + bob, 0), arm_r, 0.30, arm_r + elbow, 0.30)
	out[UARM_L] = al[0]
	out[LARM_L] = al[1]
	out[UARM_R] = ar[0]
	out[LARM_R] = ar[1]

	var bend_l := maxf(0.0, cos(phase)) * 0.9 * spd
	var bend_r := maxf(0.0, -cos(phase)) * 0.9 * spd
	var ll := _limb(Vector3(-0.10, 0.92 + bob * 0.5, 0), sw, 0.45, sw - bend_l, 0.45)
	var lr := _limb(Vector3(0.10, 0.92 + bob * 0.5, 0), -sw, 0.45, -sw - bend_r, 0.45)
	out[ULEG_L] = ll[0]
	out[LLEG_L] = ll[1]
	out[ULEG_R] = lr[0]
	out[LLEG_R] = lr[1]
	return out

func apply_standing(root: Transform3D, pose_local: Array) -> void:
	for i in N:
		parts[i].global_transform = root * (pose_local[i] as Transform3D)

# ------------------------------------------------------------------ ragdoll
## Pack part transforms of physics bodies into floats (pos + quaternion each).
static func encode(bodies: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bodies.size() * 7)
	for i in bodies.size():
		var t: Transform3D = (bodies[i] as Node3D).global_transform
		var q := Quaternion(t.basis.orthonormalized())
		var o := i * 7
		out[o] = t.origin.x
		out[o + 1] = t.origin.y
		out[o + 2] = t.origin.z
		out[o + 3] = q.x
		out[o + 4] = q.y
		out[o + 5] = q.z
		out[o + 6] = q.w
	return out

func apply_bodies(bodies: Array) -> void:
	for i in N:
		parts[i].global_transform = (bodies[i] as Node3D).global_transform

func apply_encoded(data: PackedFloat32Array, k: float) -> bool:
	if data.size() < N * 7:
		return false
	for i in N:
		var o := i * 7
		var p := Vector3(data[o], data[o + 1], data[o + 2])
		var q := Quaternion(data[o + 3], data[o + 4], data[o + 5], data[o + 6]).normalized()
		var cur := parts[i].global_transform
		var cq := Quaternion(cur.basis.orthonormalized())
		parts[i].global_transform = Transform3D(Basis(cq.slerp(q, k)), cur.origin.lerp(p, k))
	return true

# --------------------------------------------------------------- accessories
func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	_add(parent, m, color, pos, scl, true, rot)

func _ring(parent: Node3D, inner: float, outer: float, color: Color, pos: Vector3) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	_add(parent, m, color, pos, Vector3.ONE, true, Vector3(90, 0, 0))  # axis toward the front

func _build_hair(p: Node3D) -> void:
	var style := int(look["hair_style"])
	if style == 0:
		return
	if style == 5:  # afro
		_sph(p, 0.19, hair, Vector3(0, 0.07, 0.06), Vector3(1.0, 0.9, 0.85), true)
		return
	_sph(p, 0.15, hair, Vector3(0, 0.07, 0.012), Vector3(1.05, 0.86, 1.05), true)
	_sph(p, 0.12, hair, Vector3(0, 0.03, 0.08), Vector3(1.05, 0.9, 0.6), true)
	match style:
		2:  # long
			_box(p, Vector3(0.27, 0.32, 0.06), hair, Vector3(0, -0.08, 0.115), true)
			for side in [-1.0, 1.0]:
				_box(p, Vector3(0.04, 0.22, 0.1), hair, Vector3(0.128 * side, -0.05, 0.05), true)
		3:  # spiky
			for k in 7:
				var a := TAU * k / 7.0
				_cyl(p, 0.0, 0.032, 0.13, hair, Vector3(cos(a) * 0.075, 0.17, sin(a) * 0.075 + 0.01), Vector3(sin(a) * 25.0, 0, -cos(a) * 25.0))
		4:  # mohawk
			for k in 6:
				var z := -0.08 + k * 0.035
				_box(p, Vector3(0.03, 0.08 + (3 - absf(k - 2.5)) * 0.015, 0.045), hair, Vector3(0, 0.17, z), true)
		6:  # bun
			_sph(p, 0.065, hair, Vector3(0, 0.18, 0.06), Vector3.ONE, true)
		7:  # pigtails
			for side in [-1.0, 1.0]:
				_sph(p, 0.055, hair, Vector3(0.15 * side, -0.01, 0.08), Vector3.ONE, true)
				_box(p, Vector3(0.03, 0.1, 0.03), hair, Vector3(0.135 * side, 0.04, 0.08), true)

func _build_beard(p: Node3D) -> void:
	match int(look["beard"]):
		1:  # mustache
			_box(p, Vector3(0.075, 0.02, 0.02), hair, Vector3(0, -0.033, -0.137), true)
		2:  # full beard
			_sph(p, 0.12, hair, Vector3(0, -0.075, -0.015), Vector3(0.95, 0.6, 0.85), true)
			_box(p, Vector3(0.075, 0.02, 0.02), hair, Vector3(0, -0.033, -0.137), true)
		3:  # goatee
			_sph(p, 0.04, hair, Vector3(0, -0.1, -0.11), Vector3(1.0, 1.3, 1.0), true)

func _build_glasses(p: Node3D) -> void:
	var frame := Color(0.08, 0.08, 0.1)
	match int(look["glasses"]):
		1:  # round
			for side in [-1.0, 1.0]:
				_ring(p, 0.022, 0.034, frame, Vector3(0.05 * side, 0.025, -0.135))
				_box(p, Vector3(0.008, 0.008, 0.14), frame, Vector3(0.115 * side, 0.03, -0.06), true)
			_box(p, Vector3(0.03, 0.008, 0.008), frame, Vector3(0, 0.03, -0.135), true)
		2:  # sunglasses
			for side in [-1.0, 1.0]:
				_box(p, Vector3(0.075, 0.045, 0.012), Color(0.03, 0.03, 0.05), Vector3(0.05 * side, 0.025, -0.136), true)
				_box(p, Vector3(0.008, 0.01, 0.14), frame, Vector3(0.12 * side, 0.03, -0.06), true)
			_box(p, Vector3(0.03, 0.01, 0.01), frame, Vector3(0, 0.035, -0.136), true)
		3:  # goofy giant
			for side in [-1.0, 1.0]:
				_ring(p, 0.045, 0.065, Color(0.95, 0.75, 0.1), Vector3(0.07 * side, 0.015, -0.145))
				_sph(p, 0.03, Color(0.6, 0.85, 1.0), Vector3(0.07 * side, 0.015, -0.146), Vector3(1.4, 1.4, 0.2), true)
			_box(p, Vector3(0.05, 0.014, 0.014), Color(0.95, 0.75, 0.1), Vector3(0, 0.025, -0.145), true)
		4:  # 3D glasses
			_box(p, Vector3(0.075, 0.05, 0.012), Color(0.9, 0.15, 0.15), Vector3(-0.05, 0.025, -0.136), true)
			_box(p, Vector3(0.075, 0.05, 0.012), Color(0.15, 0.8, 0.95), Vector3(0.05, 0.025, -0.136), true)
			_box(p, Vector3(0.17, 0.008, 0.008), Color.WHITE, Vector3(0, 0.054, -0.138), true)
		5:  # monocle
			_ring(p, 0.026, 0.036, Color(0.9, 0.75, 0.2), Vector3(0.048, 0.025, -0.136))

func _build_hat(p: Node3D) -> void:
	var c := Look.color_of(look, "hat_color")
	match int(look["hat"]):
		1:  # traffic cone
			_box(p, Vector3(0.3, 0.02, 0.3), c, Vector3(0, 0.145, 0), true)
			_cyl(p, 0.012, 0.115, 0.3, c, Vector3(0, 0.3, 0))
			_cyl(p, 0.075, 0.09, 0.05, Color.WHITE, Vector3(0, 0.25, 0))
		2:  # top hat
			_cyl(p, 0.19, 0.19, 0.02, c.darkened(0.6), Vector3(0, 0.145, 0))
			_cyl(p, 0.11, 0.11, 0.26, c.darkened(0.6), Vector3(0, 0.27, 0))
			_cyl(p, 0.113, 0.113, 0.04, c, Vector3(0, 0.18, 0))
		3:  # cowboy
			_cyl(p, 0.26, 0.26, 0.015, c, Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
			_cyl(p, 0.08, 0.115, 0.13, c, Vector3(0, 0.215, 0))
		4:  # crown
			var gold := Color(1.0, 0.82, 0.2)
			_cyl(p, 0.12, 0.12, 0.07, gold, Vector3(0, 0.18, 0))
			for k in 5:
				var a := TAU * k / 5.0
				_cyl(p, 0.0, 0.03, 0.1, gold, Vector3(cos(a) * 0.1, 0.265, sin(a) * 0.1))
			_sph(p, 0.025, c, Vector3(0, 0.18, -0.12), Vector3.ONE, true)
		5:  # beanie
			_sph(p, 0.15, c, Vector3(0, 0.1, 0), Vector3(1.0, 0.75, 1.0), true)
			_sph(p, 0.04, Color.WHITE, Vector3(0, 0.235, 0), Vector3.ONE, true)
		6:  # propeller cap
			_sph(p, 0.145, c, Vector3(0, 0.115, 0), Vector3(1.0, 0.55, 1.0), true)
			_cyl(p, 0.015, 0.015, 0.06, Color(0.2, 0.2, 0.2), Vector3(0, 0.21, 0))
			_box(p, Vector3(0.3, 0.01, 0.045), Color(0.95, 0.85, 0.2), Vector3(0, 0.245, 0), true)
			_box(p, Vector3(0.045, 0.01, 0.3), Color(0.2, 0.7, 0.95), Vector3(0, 0.25, 0), true)
		7:  # a rubber duck sitting on your head
			var y := Color(1.0, 0.85, 0.1)
			_sph(p, 0.09, y, Vector3(0, 0.22, 0), Vector3(1.0, 0.9, 1.2), true)
			_sph(p, 0.055, y, Vector3(0, 0.31, -0.05), Vector3.ONE, true)
			_box(p, Vector3(0.05, 0.02, 0.05), Color(1.0, 0.5, 0.05), Vector3(0, 0.30, -0.105), true)
			for side in [-1.0, 1.0]:
				_sph(p, 0.01, Color.BLACK, Vector3(0.03 * side, 0.325, -0.09), Vector3.ONE, true)
