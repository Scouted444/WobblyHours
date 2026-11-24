class_name PlayerRagdoll
extends Node3D
## Physics ragdoll: 10 capsule bodies connected by cone-twist joints.
## Only the owning player's machine simulates it; everyone else just receives the poses.
## Ragdoll bodies live on collision layer 4 and only collide with layer 1 (world, props),
## so the limbs never fight each other.

signal prop_touched(prop: Prop, velocity: Vector3)

## parent part, child part, anchor in parent's local space, swing span, twist span (degrees)
const JOINTS := [
	[0, 1, Vector3(0.0, 0.32, 0.0), 50.0, 35.0],     # neck
	[0, 2, Vector3(-0.25, 0.24, 0.0), 85.0, 30.0],   # shoulders
	[0, 3, Vector3(0.25, 0.24, 0.0), 85.0, 30.0],
	[2, 4, Vector3(0.0, -0.15, 0.0), 70.0, 20.0],    # elbows
	[3, 5, Vector3(0.0, -0.15, 0.0), 70.0, 20.0],
	[0, 6, Vector3(-0.10, -0.30, 0.0), 70.0, 25.0],  # hips
	[0, 7, Vector3(0.10, -0.30, 0.0), 70.0, 25.0],
	[6, 8, Vector3(0.0, -0.225, 0.0), 60.0, 15.0],   # knees
	[7, 9, Vector3(0.0, -0.225, 0.0), 60.0, 15.0]]

var bodies: Array[RigidBody3D] = []
var active := false

func _ready() -> void:
	top_level = true  # bodies use world coordinates, independent of the player node

func torso() -> RigidBody3D:
	return bodies[0]

## `owner_body`: the player's own capsule, which stays where the torso is: the limbs must ignore it,
## or they shove against it every frame (that was the main cause of the twitchy, exploding ragdolls).
func spawn(rig: PlayerRig, vel: Vector3, owner_body: PhysicsBody3D = null) -> void:
	clear()
	for i in PlayerRig.N:
		var b := RigidBody3D.new()
		b.mass = PlayerRig.MASSES[i]
		b.collision_layer = 4
		b.collision_mask = 1
		b.linear_damp = 0.15
		b.angular_damp = 3.5
		b.can_sleep = false
		b.continuous_cd = true  # fast limbs must not tunnel through floors and walls
		b.contact_monitor = true
		b.max_contacts_reported = 4
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.1
		b.physics_material_override = pm
		var cs := CollisionShape3D.new()
		cs.shape = PlayerRig.shape_for(i)
		b.add_child(cs)
		add_child(b)
		b.global_transform = rig.parts[i].global_transform
		b.linear_velocity = vel
		b.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
		b.body_entered.connect(_on_contact.bind(b))
		bodies.append(b)
		if owner_body != null:
			b.add_collision_exception_with(owner_body)

	for d in JOINTS:
		var a := bodies[d[0]]
		var c := bodies[d[1]]
		var j := ConeTwistJoint3D.new()
		add_child(j)
		# Joint frame: X axis points along the limb (down), anchored in the parent's frame.
		j.global_transform = Transform3D(
			a.global_basis * Basis(Vector3.BACK, -PI / 2.0),
			a.global_transform * (d[2] as Vector3))
		j.node_a = j.get_path_to(a)
		j.node_b = j.get_path_to(c)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(d[3]))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(d[4]))
		j.set_param(ConeTwistJoint3D.PARAM_BIAS, 0.5)          # pull back together firmly
		j.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.9)
		j.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 0.8)    # less bouncing off the limits
	active = true

func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	bodies.clear()
	active = false

## Per physics frame: water makes the body float and drag.
func step(world: GameWorld) -> void:
	for b in bodies:
		b.linear_velocity = b.linear_velocity.limit_length(13.0)   # never fling off the map
		b.angular_velocity = b.angular_velocity.limit_length(12.0)
		var s := world.water_surface(b.global_position)
		if is_nan(s):
			b.linear_damp = 0.15
			b.angular_damp = 3.5
		else:
			b.linear_damp = 2.5
			b.angular_damp = 4.0
			if b.global_position.y < s:
				b.apply_central_force(Vector3(0.0, b.mass * 16.0 * 1.5, 0.0))

func set_mask(m: int) -> void:
	for b in bodies:
		b.collision_mask = m

func add_velocity(v: Vector3) -> void:
	for b in bodies:
		b.linear_velocity += v

func _on_contact(other: Node, body: RigidBody3D) -> void:
	if other is Prop:
		prop_touched.emit(other, body.linear_velocity)
