class_name Gore
extends RefCounted
## Cartoon blood and flying limbs for the people (NPCs). Purely visual and local: only shown when
## Settings.gore is on, so everyone can pick for themselves.

const RED := Color(0.62, 0.02, 0.03)
const MAX_SPLATS := 60

static var _blood_mat: StandardMaterial3D
static var _drop_mesh: SphereMesh

static func _mat() -> StandardMaterial3D:
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.albedo_color = RED
		_blood_mat.roughness = 0.25
		_blood_mat.metallic_specular = 0.8
	return _blood_mat

static func _drop() -> SphereMesh:
	if _drop_mesh == null:
		_drop_mesh = SphereMesh.new()
		_drop_mesh.radius = 0.025
		_drop_mesh.height = 0.05
		_drop_mesh.radial_segments = 6
		_drop_mesh.rings = 3
		_drop_mesh.material = _mat()
	return _drop_mesh

static func _particles(amount: int, life: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _drop()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.85 if one_shot else 0.0
	p.spread = 35.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	return p

## A spray of blood drops at `pos`, flying along `dir`.
static func burst(world: Node3D, pos: Vector3, dir: Vector3, amount := 30) -> void:
	var p := _particles(amount, 0.9, true)
	world.add_child(p)
	p.global_position = pos
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.direction = d
	p.emitting = true
	world.get_tree().create_timer(1.6).timeout.connect(p.queue_free)

## Continuous squirt from a stump for a few seconds (parent it to a BoneAttachment3D).
static func spurt() -> CPUParticles3D:
	var p := _particles(24, 0.7, false)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.emitting = true
	var t := Timer.new()
	t.wait_time = 3.5
	t.one_shot = true
	t.autostart = true
	t.timeout.connect(func(): p.emitting = false)
	p.add_child(t)
	return p

## A puddle on the ground that spreads out, then fades away after a while.
static func splat(world: Node3D, ground_pos: Vector3, size := 0.35) -> void:
	var splats := world.get_tree().get_nodes_in_group("blood_splat")
	if splats.size() >= MAX_SPLATS:
		splats[0].queue_free()
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 0.004
	m.radial_segments = 14
	mi.mesh = m
	var mat := _mat().duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("blood_splat")
	world.add_child(mi)
	mi.global_position = ground_pos + Vector3(randf_range(-0.1, 0.1), 0.012 + randf() * 0.004, randf_range(-0.1, 0.1))
	mi.scale = Vector3(0.05, 1.0, 0.05)
	var s := size * randf_range(0.8, 1.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(s, 1.0, s * randf_range(0.7, 1.0)), 1.5).set_ease(Tween.EASE_OUT)
	tw.tween_interval(40.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	tw.tween_callback(mi.queue_free)

## A severed limb that tumbles off (local physics only, nobody else needs to agree where it lands).
static func limb(world: Node3D, limb_name: String, pos: Vector3, push: Vector3, skin: Color, hair: Color) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 2.0
	var cs := CollisionShape3D.new()
	var skin_mat := Mats.solid(skin, 0.7)
	var stump := StandardMaterial3D.new()
	stump.albedo_color = Color(0.7, 0.05, 0.06)
	stump.roughness = 0.4
	if limb_name == "head":
		var sh := SphereShape3D.new()
		sh.radius = 0.13
		cs.shape = sh
		var head := SphereMesh.new()
		head.radius = 0.13
		head.height = 0.28
		_mi(rb, head, skin_mat, Vector3.ZERO)
		var cap := SphereMesh.new()
		cap.radius = 0.135
		cap.height = 0.16
		_mi(rb, cap, Mats.solid(hair, 0.9), Vector3(0, 0.07, 0.01))
		for sx in [-0.045, 0.045]:
			var eye := SphereMesh.new()
			eye.radius = 0.018
			eye.height = 0.036
			_mi(rb, eye, Mats.solid(Color(0.05, 0.05, 0.05), 0.3), Vector3(sx, 0.02, -0.12))
		var neck := CylinderMesh.new()
		neck.top_radius = 0.05
		neck.bottom_radius = 0.05
		neck.height = 0.02
		_mi(rb, neck, stump, Vector3(0, -0.13, 0))
	else:
		var leg := limb_name.begins_with("leg")
		var length := 0.85 if leg else 0.62
		var r := 0.075 if leg else 0.055
		var cap_s := CapsuleShape3D.new()
		cap_s.radius = r
		cap_s.height = length
		cs.shape = cap_s
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = length
		_mi(rb, cm, skin_mat, Vector3.ZERO)
		var end := CylinderMesh.new()
		end.top_radius = r * 0.95
		end.bottom_radius = r * 0.95
		end.height = 0.02
		_mi(rb, end, stump, Vector3(0, length * 0.5 - r * 0.6, 0))
	rb.add_child(cs)
	world.add_child(rb)
	rb.global_position = pos
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	rb.linear_velocity = push.limit_length(9.0) + Vector3(randf_range(-1.0, 1.0), 2.5, randf_range(-1.0, 1.0))
	rb.angular_velocity = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
	var trail := _particles(10, 0.6, false)
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	rb.add_child(trail)
	trail.emitting = true
	world.get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(trail):
			trail.emitting = false)
	world.get_tree().create_timer(30.0).timeout.connect(func():
		if is_instance_valid(rb):
			rb.queue_free())

static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
