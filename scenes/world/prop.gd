class_name Prop
extends RigidBody3D
## A physics toy. The SERVER simulates it; clients just copy its transform (frozen kinematic).
## kinds: crate, ball (beach ball), chair, melon, duck, pin, barrel (explodes), bomb (fuse)

## mass, buoyancy (above 1 = floats), bounce, friction, half-size (for water depth)
const MAX_SPEED := 18.0   # props never move faster than this (keeps throws and hits from launching things)

const DEFS := {
	"crate":  {"mass": 1.5, "float": 1.3, "bounce": 0.1, "friction": 0.8, "half": 0.4},
	"ball":   {"mass": 0.5, "float": 3.0, "bounce": 0.85, "friction": 0.5, "half": 0.4},
	"chair":  {"mass": 2.0, "float": 1.1, "bounce": 0.1, "friction": 0.8, "half": 0.45},
	"melon":  {"mass": 3.5, "float": 0.9, "bounce": 0.3, "friction": 0.6, "half": 0.25},
	"duck":   {"mass": 0.3, "float": 2.6, "bounce": 0.4, "friction": 0.6, "half": 0.2},
	"pin":    {"mass": 0.8, "float": 1.2, "bounce": 0.2, "friction": 0.6, "half": 0.3},
	"barrel": {"mass": 3.0, "float": 1.4, "bounce": 0.1, "friction": 0.7, "half": 0.5},
	"bomb":   {"mass": 0.8, "float": 0.4, "bounce": 0.3, "friction": 0.6, "half": 0.25},
	"coupe":  {"mass": 6.0, "float": 0.9, "bounce": 0.05, "friction": 0.6, "half": 0.3},
	"cart":   {"mass": 8.0, "float": 0.8, "bounce": 0.05, "friction": 0.6, "half": 0.45},
	"gloves": {"mass": 0.3, "float": 1.0, "bounce": 0.2, "friction": 0.8, "half": 0.08},
	"rocket": {"mass": 1.0, "float": 0.0, "bounce": 0.0, "friction": 0.5, "half": 0.2},
	"package": {"mass": 1.2, "float": 1.4, "bounce": 0.1, "friction": 0.8, "half": 0.2},
	"sedan":  {"mass": 40.0, "float": 0.6, "bounce": 0.02, "friction": 0.7, "half": 0.7},
	"taxi":   {"mass": 40.0, "float": 0.6, "bounce": 0.02, "friction": 0.7, "half": 0.7},
	"police": {"mass": 42.0, "float": 0.6, "bounce": 0.02, "friction": 0.7, "half": 0.7},
	"sports": {"mass": 36.0, "float": 0.6, "bounce": 0.02, "friction": 0.7, "half": 0.6},
	"truck":  {"mass": 55.0, "float": 0.6, "bounce": 0.02, "friction": 0.7, "half": 0.9},
}

## Full-size cars: physics box, top speed / reverse (m/s), acceleration, turn rate, driver seat
## (where the driver's FEET go, car space: sitting means the feet end up below the seat).
const CARS := {
	"sedan":  {"size": Vector3(1.84, 1.45, 4.5), "top": 16.0, "rev": 5.0, "accel": 8.0, "turn": 1.5, "seat": Vector3(-0.4, -1.205, 0.37), "label": "sedan",
		"ik": {"foot": Vector2(0.8, 0.78), "hand": Vector2(0.44, 1.44), "recline": 0.2}},
	"taxi":   {"size": Vector3(1.84, 1.45, 4.5), "top": 16.0, "rev": 5.0, "accel": 8.0, "turn": 1.5, "seat": Vector3(-0.4, -1.205, 0.37), "label": "taxi",
		"ik": {"foot": Vector2(0.8, 0.78), "hand": Vector2(0.44, 1.44), "recline": 0.2}},
	"police": {"size": Vector3(1.84, 1.45, 4.6), "top": 19.0, "rev": 6.0, "accel": 10.0, "turn": 1.6, "seat": Vector3(-0.4, -1.205, 0.37), "label": "police car",
		"ik": {"foot": Vector2(0.8, 0.78), "hand": Vector2(0.44, 1.44), "recline": 0.2}},
	"sports": {"size": Vector3(1.92, 1.26, 4.4), "top": 24.0, "rev": 6.0, "accel": 13.0, "turn": 1.75, "seat": Vector3(-0.4, -1.25, 0.67), "label": "sports car",
		"ik": {"foot": Vector2(0.85, 0.86), "hand": Vector2(0.44, 1.44), "recline": 0.32}},
	"truck":  {"size": Vector3(2.0, 1.85, 5.3), "top": 13.0, "rev": 4.5, "accel": 6.0, "turn": 1.25, "seat": Vector3(-0.4, -1.205, -0.08), "label": "pickup truck",
		"ik": {"foot": Vector2(0.75, 0.76), "hand": Vector2(0.44, 1.5), "recline": 0.18}},
}
const CAR_COLORS := ["2b5fb4", "b42b2b", "e8e8e8", "222428", "3d7a45", "c9a227", "7a3db4", "d96c1a", "8a9099", "1f8a8a"]

static func is_car(k: String) -> bool:
	return CARS.has(k)

## Extra kinds: tools you can USE while holding them (LMB). "aim" = held pointing where you look,
## "upright" = held level (only turns left/right), "cd" = seconds between uses.
const ITEMS := {
	"limb_arm":  {"mass": 2.5, "float": 0.8, "bounce": 0.2, "friction": 0.7, "half": 0.12, "use": true, "aim": true, "cd": 0.55},
	"limb_leg":  {"mass": 4.0, "float": 0.8, "bounce": 0.2, "friction": 0.7, "half": 0.14, "use": true, "aim": true, "cd": 0.7},
	"limb_head": {"mass": 3.0, "float": 0.9, "bounce": 0.3, "friction": 0.7, "half": 0.13, "use": true, "aim": true, "cd": 0.6},
	"pistol":  {"mass": 0.8, "float": 0.5, "bounce": 0.1, "friction": 0.6, "half": 0.1, "use": true, "aim": true, "cd": 0.2},
	"knife":   {"mass": 0.3, "float": 0.5, "bounce": 0.1, "friction": 0.6, "half": 0.05, "use": true, "aim": true, "cd": 0.4},
	"bat":     {"mass": 1.0, "float": 1.0, "bounce": 0.2, "friction": 0.6, "half": 0.08, "use": true, "aim": true, "cd": 0.7},
	"cig":     {"mass": 0.1, "float": 1.5, "bounce": 0.1, "friction": 0.6, "half": 0.03, "use": true, "aim": true, "cd": 1.2},
	"console": {"mass": 0.4, "float": 0.8, "bounce": 0.1, "friction": 0.6, "half": 0.08, "use": true, "aim": true, "cd": 0.25},
	"burger":  {"mass": 0.3, "float": 1.2, "bounce": 0.1, "friction": 0.7, "half": 0.08, "use": true, "aim": true, "upright": true, "cd": 0.5},
	"pizza":   {"mass": 0.3, "float": 1.2, "bounce": 0.1, "friction": 0.7, "half": 0.03, "use": true, "aim": true, "cd": 0.5},
	"soda":    {"mass": 0.3, "float": 1.0, "bounce": 0.3, "friction": 0.5, "half": 0.08, "use": true, "aim": true, "upright": true, "cd": 0.5},
	"rpg":     {"mass": 3.0, "float": 0.8, "bounce": 0.1, "friction": 0.6, "half": 0.15, "use": true, "aim": true, "cd": 2.5},
	"beer":    {"mass": 0.4, "float": 1.0, "bounce": 0.2, "friction": 0.5, "half": 0.12, "use": true, "aim": true, "upright": true, "cd": 0.5},
}
const LABELS := {
	"crate": "Crate", "ball": "Beach ball", "chair": "Chair", "melon": "Watermelon", "duck": "Rubber duck",
	"pin": "Bowling pin", "barrel": "Barrel (boom)", "bomb": "Bomb (boom)",
	"pistol": "Pistol", "knife": "Knife", "bat": "Baseball bat", "cig": "Cigarette", "console": "Game console",
	"burger": "Burger", "pizza": "Pizza slice", "soda": "Soda", "beer": "Beer",
	"rpg": "RPG", "rocket": "Rocket", "coupe": "Toy coupe", "cart": "Shopping cart", "npc": "Person",
	"gloves": "Rubber gloves", "limb_arm": "Arm", "limb_leg": "Leg", "limb_head": "Head",
	"package": "Package", "sedan": "Sedan", "taxi": "Taxi", "police": "Police car", "sports": "Sports car", "truck": "Pickup truck",
}
const CATEGORIES := {
	"Toys": ["crate", "ball", "chair", "melon", "duck", "pin", "barrel", "bomb", "coupe", "cart"],
	"People": ["npc"],
	"Weapons": ["pistol", "knife", "bat"],
	"Props": ["cig", "console", "gloves"],
	"Food": ["burger", "pizza", "soda", "beer"],
	"Cars": ["sedan", "taxi", "police", "sports", "truck"],
}

static func def_of(k: String) -> Dictionary:
	return DEFS[k] if DEFS.has(k) else ITEMS[k]

## Kinds nobody can spawn from the menu (the RPG lives on the roof; rockets only come out of it).
## Things you get into and drive (F): the toy coupe and the shopping cart.
static func is_vehicle(k: String) -> bool:
	return k == "coupe" or k == "cart" or CARS.has(k)

static func is_restricted(k: String) -> bool:
	return k == "rpg" or k == "rocket" or k == "package" or is_limb(k)

## Body parts torn off people: only come from gore, never from the spawn menu.
static func is_limb(k: String) -> bool:
	return k.begins_with("limb_")

static func is_valid_kind(k: String) -> bool:
	return DEFS.has(k) or ITEMS.has(k)

var kind := "crate"
var tint := ""                 # body parts: "skin hex|hair hex"
var _root: Node3D = self      # meshes go here (tools use a pivot so they can recoil / swing)
var _pv: Node3D
var _flash: MeshInstance3D
var _screen_mat: StandardMaterial3D
var _next_use := 0
var exploded := false
var hp := 3                 # barrels blow up after 3 shoves
var visual_only := false    # a model shown in someone's hand: no physics, no networking
var init_vel := Vector3.ZERO
var shooter := 0            # peer id that threw / fired this (no self-bonking, no self-explosion)
var rider := 0              # peer id riding this rocket
var passenger := 0          # peer id sitting in the shopping cart
var cart_contents: Array = []   # server, carts: props riding in the basket
var in_cart: Prop = null        # server: the cart I'm riding in
var _cart_local := Transform3D()
var _saved_layers := Vector2i(1, 1)
var _model: Node3D
var _age := 0.0
var _dir := Vector3.FORWARD
var _speed := 9.0
var _hue := 0.0
var _smoke_t := 0.0
var _thr := 0.0     # coupe throttle / steering from the driver
var boosting := false   # coupe rocket boosters are firing (replicated, so everyone sees the flames)
var _flames: Array[MeshInstance3D] = []
var _was_boost := false
var _pupils: Array[Node3D] = []
var _last_yaw := 0.0
var _last_pos := Vector3.ZERO
var _look := 0.0
var _sag := 1.0
var _sag_v := 0.0
var _pm: PhysicsMaterial
var _last_drive := 0
var _ground_n := Vector3.UP
var _air_time := 0.0
var _boost_snd := 0.0
var _steer := 0.0
var _prev_speed := 0.0
var _bonk_cd := {}
var driver_seed := 0        # cars: a townsperson is driving (their look seed; 0 = nobody). Synced.
var siren := false          # police car lights (synced)
var ai_route: Array = []    # server: [from node, to node] in the town road graph
var _ai_block_t := 0.0
var _ai_honk_t := 0.0
var _driver_body: NpcBody
var _driver_shown := -1
var _siren_nodes: Array[Node3D] = []

func _ready() -> void:
	if visual_only:
		_build_body()
		for c in get_children():
			if c is CollisionShape3D:
				remove_child(c)
				c.queue_free()
		collision_layer = 0
		collision_mask = 0
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		top_level = true
		set_physics_process(false)
		for m in find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	add_to_group("props")
	_build_body()
	var def: Dictionary = def_of(kind)
	mass = def["mass"]
	_pm = PhysicsMaterial.new()
	_pm.bounce = def["bounce"]
	_pm.friction = def["friction"]
	physics_material_override = _pm
	if is_vehicle(kind):
		can_sleep = false
	if is_car(kind) and driver_seed != 0:
		_pm.friction = 0.0   # the AI drives it like a player would
	if kind == "cart" and multiplayer.is_server():
		# anything that lands in the basket sticks there and rides along
		var basket := Area3D.new()
		basket.collision_layer = 0
		basket.collision_mask = 1
		var bcs := CollisionShape3D.new()
		var bbox := BoxShape3D.new()
		bbox.size = Vector3(0.5, 0.5, 0.85)
		bcs.shape = bbox
		bcs.position = Vector3(0, 0.25, -0.04)
		basket.add_child(bcs)
		add_child(basket)
		basket.body_entered.connect(_on_basket_body)   # a sleeping body never runs _integrate_forces, so it could not be driven

	if multiplayer.is_server():
		continuous_cd = true  # thrown toys must not tunnel through walls
		linear_velocity = init_vel
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(_on_body_entered)
		if kind == "bomb":
			get_tree().create_timer(3.0).timeout.connect(explode)
		if kind == "rocket":
			gravity_scale = 0.0
			linear_damp = 0.0
			angular_damp = 0.0
			lock_rotation = false
			_dir = init_vel.normalized() if init_vel.length() > 0.1 else Vector3.FORWARD
			var world0 := get_tree().get_first_node_in_group("world") as GameWorld
			if world0 != null:
				var sh := world0.get_node_or_null(str(shooter)) as Player
				if sh != null:
					add_collision_exception_with(sh)
			get_tree().create_timer(7.0).timeout.connect(explode)
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true

	var cfg := SceneReplicationConfig.new()
	for path in [^".:position", ^".:rotation"]:
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	if is_vehicle(kind):
		cfg.add_property(^".:boosting")
		cfg.property_set_replication_mode(^".:boosting", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		cfg.add_property(^".:rider")
		cfg.property_set_replication_mode(^".:rider", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		cfg.add_property(^".:passenger")
		cfg.property_set_replication_mode(^".:passenger", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	if is_car(kind):
		for cp in [^".:driver_seed", ^".:siren"]:
			cfg.add_property(cp)
			cfg.property_set_replication_mode(cp, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	add_child(sync)
	_pop_in()

## Spawn animation: the model pops in with a little overshoot.
func _pop_in() -> void:
	var target: Node3D = _model if _model != null else _pv
	if target == null:
		return
	var final_scale := target.scale
	target.scale = final_scale * 0.15
	var tw := create_tween()
	tw.tween_property(target, "scale", final_scale, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------- models
func _shape_box(size: Vector3, pos := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	add_child(cs)

func _shape_sphere(r: float, pos := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	cs.shape = s
	cs.position = pos
	add_child(cs)

func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> void:
	if _model != null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	_root.add_child(mi)

func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _sphere_mesh(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m

func _cyl_mesh(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	return m

## A cylinder lying along Z (rotated), handy for barrels of guns, bats, cigarettes.
func _along_z(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	if _model != null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	_root.add_child(mi)

func _build_item() -> void:
	var metal := Mats.solid(Color(0.16, 0.16, 0.18), 0.35, 0.7)
	match kind:
		"pistol":
			_shape_box(Vector3(0.07, 0.2, 0.3), Vector3(0, -0.02, 0))
			_mesh(_box_mesh(Vector3(0.055, 0.07, 0.3)), metal, Vector3(0, 0.05, -0.02))
			_along_z(_cyl_mesh(0.014, 0.014, 0.06), Mats.solid(Color(0.05, 0.05, 0.05), 0.3, 0.8), Vector3(0, 0.05, -0.19))
			_mesh(_box_mesh(Vector3(0.05, 0.14, 0.07)), Mats.solid(Color(0.3, 0.2, 0.12), 0.7), Vector3(0, -0.04, 0.09))
			_mesh(_box_mesh(Vector3(0.015, 0.04, 0.05)), metal, Vector3(0, -0.01, -0.01))
			_mesh(_box_mesh(Vector3(0.012, 0.015, 0.02)), Mats.solid(Color(0.8, 0.8, 0.8)), Vector3(0, 0.09, 0.12))
			_flash = MeshInstance3D.new()   # replaced by the model's "Flash" node when there is one
			_flash.mesh = _sphere_mesh(0.07)
			_flash.material_override = Mats.glow(Color(1.0, 0.8, 0.3), 6.0)
			_flash.position = Vector3(0, 0.05, -0.27)
			_flash.visible = false
			_root.add_child(_flash)
		"rpg":
			_shape_box(Vector3(0.16, 0.2, 1.0), Vector3(0, 0.03, 0.05))
		"knife":
			_shape_box(Vector3(0.05, 0.06, 0.36))
			_mesh(_box_mesh(Vector3(0.012, 0.05, 0.22)), Mats.solid(Color(0.85, 0.87, 0.9), 0.15, 0.95), Vector3(0, 0, -0.14))
			_mesh(_box_mesh(Vector3(0.035, 0.07, 0.012)), metal, Vector3(0, 0, -0.025))
			_mesh(_box_mesh(Vector3(0.03, 0.045, 0.13)), Mats.solid(Color(0.25, 0.15, 0.1), 0.8), Vector3(0, 0, 0.05))
		"limb_arm", "limb_leg", "limb_head":
			_build_limb()
		"bat":
			_shape_box(Vector3(0.1, 0.1, 0.95), Vector3(0, 0, -0.3))
			var wood := Mats.textured("planks", Color(0.9, 0.7, 0.45), 0.5)
			_along_z(_cyl_mesh(0.016, 0.045, 0.9), wood, Vector3(0, 0, -0.3))   # thin end (+Z) is the handle
			_mesh(_sphere_mesh(0.02), wood, Vector3(0, 0, 0.16))
		"cig":
			_shape_box(Vector3(0.05, 0.05, 0.14))
			_along_z(_cyl_mesh(0.007, 0.007, 0.1), Mats.solid(Color(0.97, 0.97, 0.95)), Vector3(0, 0, 0.0))
			_along_z(_cyl_mesh(0.0072, 0.0072, 0.03), Mats.solid(Color(0.85, 0.5, 0.2)), Vector3(0, 0, 0.065))
			_along_z(_cyl_mesh(0.0065, 0.0065, 0.008), Mats.glow(Color(1.0, 0.3, 0.05), 3.0), Vector3(0, 0, -0.052))
		"console":
			_shape_box(Vector3(0.2, 0.11, 0.03))
			_mesh(_box_mesh(Vector3(0.2, 0.11, 0.025)), Mats.solid(Color(0.25, 0.25, 0.85), 0.4))
			_mesh(_box_mesh(Vector3(0.11, 0.075, 0.004)), Mats.solid(Color(0.05, 0.05, 0.07)), Vector3(0, 0.005, 0.014))
			_screen_mat = StandardMaterial3D.new()
			_screen_mat.albedo_color = Color(0.3, 0.9, 0.4)
			_screen_mat.emission_enabled = true
			_screen_mat.emission = Color(0.3, 0.9, 0.4)
			_screen_mat.emission_energy_multiplier = 1.2
			_mesh(_box_mesh(Vector3(0.1, 0.065, 0.004)), _screen_mat, Vector3(0, 0.005, 0.0165))
			_mesh(_box_mesh(Vector3(0.03, 0.01, 0.006)), Mats.solid(Color(0.1, 0.1, 0.1)), Vector3(-0.073, 0.0, 0.015))
			_mesh(_box_mesh(Vector3(0.01, 0.03, 0.006)), Mats.solid(Color(0.1, 0.1, 0.1)), Vector3(-0.073, 0.0, 0.015))
			for k in 2:
				_mesh(_sphere_mesh(0.011), Mats.solid(Color(0.9, 0.2, 0.25) if k == 0 else Color(0.95, 0.85, 0.2)), Vector3(0.07 + k * 0.012, -0.012 + k * 0.025, 0.015))
		"burger":
			_shape_cyl(0.085, 0.2)
			_mesh(_cyl_mesh(0.075, 0.07, 0.035), Mats.solid(Color(0.85, 0.6, 0.3)), Vector3(0, -0.075, 0))
			_mesh(_cyl_mesh(0.08, 0.08, 0.035), Mats.solid(Color(0.35, 0.18, 0.1)), Vector3(0, -0.04, 0))
			_mesh(_box_mesh(Vector3(0.14, 0.01, 0.14)), Mats.solid(Color(1.0, 0.8, 0.15)), Vector3(0, -0.017, 0))
			_mesh(_cyl_mesh(0.085, 0.085, 0.015), Mats.solid(Color(0.3, 0.7, 0.2)), Vector3(0, -0.005, 0))
			_mesh(_cyl_mesh(0.07, 0.07, 0.015), Mats.solid(Color(0.85, 0.15, 0.1)), Vector3(0, 0.01, 0))
			_mesh(_sphere_mesh(0.078), Mats.solid(Color(0.88, 0.62, 0.3)), Vector3(0, 0.02, 0), Vector3(1, 0.6, 1))
			for k in 6:
				var a := TAU * k / 6.0
				_mesh(_sphere_mesh(0.008), Mats.solid(Color(1.0, 0.95, 0.8)), Vector3(cos(a) * 0.035, 0.062, sin(a) * 0.035), Vector3(1, 0.5, 1))
		"pizza":
			_shape_box(Vector3(0.24, 0.04, 0.3))
			var crust_mat := Mats.solid(Color(0.85, 0.62, 0.3))
			_root_prism(Vector3(0.24, 0.3, 0.02), crust_mat, Vector3(0, 0, 0))
			_root_prism(Vector3(0.21, 0.26, 0.01), Mats.solid(Color(1.0, 0.75, 0.2)), Vector3(0, 0.012, -0.005))
			_mesh(_box_mesh(Vector3(0.24, 0.03, 0.04)), Mats.solid(Color(0.78, 0.5, 0.2)), Vector3(0, 0.0, 0.15))
			for pp in [Vector3(0, 0.02, -0.08), Vector3(-0.04, 0.02, 0.03), Vector3(0.045, 0.02, 0.05)]:
				_mesh(_cyl_mesh(0.026, 0.026, 0.008), Mats.solid(Color(0.75, 0.15, 0.12)), pp)
		"soda":
			_shape_cyl(0.04, 0.13)
			_mesh(_cyl_mesh(0.036, 0.036, 0.12), Mats.solid(Color(0.85, 0.1, 0.1), 0.3, 0.5))
			_mesh(_cyl_mesh(0.0365, 0.0365, 0.035), Mats.solid(Color(0.95, 0.95, 0.95), 0.3, 0.3))
			_mesh(_cyl_mesh(0.033, 0.036, 0.008), Mats.solid(Color(0.8, 0.8, 0.85), 0.2, 0.9), Vector3(0, 0.063, 0))
			_mesh(_cyl_mesh(0.03, 0.03, 0.006), Mats.solid(Color(0.8, 0.8, 0.85), 0.2, 0.9), Vector3(0, 0.068, 0))
		"beer":
			_shape_cyl(0.04, 0.26)
			var glass_m := Mats.solid(Color(0.4, 0.22, 0.06), 0.15, 0.1)
			_mesh(_cyl_mesh(0.032, 0.032, 0.15), glass_m, Vector3(0, -0.04, 0))
			_mesh(_cyl_mesh(0.012, 0.032, 0.07), glass_m, Vector3(0, 0.07, 0))
			_mesh(_cyl_mesh(0.014, 0.014, 0.02), Mats.solid(Color(0.8, 0.7, 0.2), 0.3, 0.8), Vector3(0, 0.115, 0))
			_mesh(_cyl_mesh(0.0325, 0.0325, 0.07), Mats.solid(Color(0.95, 0.9, 0.7)), Vector3(0, -0.04, 0))

func _shape_cyl(r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	add_child(cs)

## Flat triangular slab (pizza): apex toward -Z.
func _root_prism(size: Vector3, mat: Material, pos: Vector3) -> void:
	if _model != null:
		return
	var pm := PrismMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(-90, 0, 0)
	_root.add_child(mi)

func _build_body() -> void:
	_model = null if kind == "ball" else ModelLib.make(kind)
	if ITEMS.has(kind):
		_pv = Node3D.new()
		_pv.name = "Pivot"
		add_child(_pv)
		_root = _pv
		_build_item()
		_attach_model(_pv)
		return
	_build_toy()
	_attach_model(self)
	if is_car(kind):
		_paint_car()
		if _model != null:
			for nm in ["SirenR", "SirenB"]:
				var sn := ModelLib.find(_model, nm) as Node3D
				if sn != null:
					_siren_nodes.append(sn)
					sn.visible = false
	if kind == "coupe":
		if _model != null:
			CarPaint.apply(_model)
		_add_boosters()

## Puts the .glb model in place and hooks up its named nodes ("Flash", "Screen").
## Two rocket pods on the back of the coupe, with flames that only show while boosting.
func _add_boosters() -> void:
	var parent: Node3D = _model if _model != null else self
	var pod_mat := Mats.solid(Color(0.82, 0.84, 0.88), 0.3, 0.6)
	var band_mat := Mats.solid(Color(0.9, 0.12, 0.1), 0.4, 0.3)
	var nozzle_mat := Mats.solid(Color(0.15, 0.15, 0.17), 0.5, 0.8)
	var flame_mat := Mats.glow(Color(1.0, 0.55, 0.1), 3.5)
	for side in [-1.0, 1.0]:
		var x: float = 0.3 * side
		_booster_part(parent, 0.085, 0.085, 0.46, pod_mat, Vector3(x, 0.2, 0.66))                     # pod
		_booster_part(parent, 0.0, 0.085, 0.16, band_mat, Vector3(x, 0.2, 0.66 - 0.31), -90.0)       # red nose cone (front)
		_booster_part(parent, 0.092, 0.092, 0.05, band_mat, Vector3(x, 0.2, 0.66 + 0.1))             # red band
		_booster_part(parent, 0.11, 0.07, 0.11, nozzle_mat, Vector3(x, 0.2, 0.66 + 0.285))           # nozzle bell (wide end at the back)
		_booster_part(parent, 0.03, 0.03, 0.12, nozzle_mat, Vector3(x * 0.8, 0.2, 0.36)).rotation_degrees = Vector3(90, 0, 0)   # strut stub
		var fl := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.085
		fm.height = 0.6
		fl.mesh = fm
		fl.material_override = flame_mat
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.rotation_degrees = Vector3(90, 0, 0)     # tip points backward (+Z)
		fl.position = Vector3(x, 0.2, 0.66 + 0.34 + 0.3)
		fl.visible = false
		parent.add_child(fl)
		_flames.append(fl)

## A cylinder lying along the car's Z axis. top/bottom radius refer to the +Z end / -Z end.
func _booster_part(parent: Node3D, r_back: float, r_front: float, length: float, mat: Material, pos: Vector3, extra_x := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_back
	cm.bottom_radius = r_front
	cm.height = length
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.rotation_degrees = Vector3(extra_x if extra_x != 0.0 else 90.0, 0, 0)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _attach_model(parent: Node3D) -> void:
	if _model == null:
		return
	parent.add_child(_model)
	var f := ModelLib.find(_model, "Flash") as MeshInstance3D
	if f != null:
		if _flash != null:
			_flash.queue_free()
		_flash = f
		_flash.visible = false
	elif _flash != null:
		_flash.queue_free()
		_flash = null
	var sc := ModelLib.find(_model, "Screen") as MeshInstance3D
	if sc != null and sc.mesh != null and sc.mesh.surface_get_material(0) is StandardMaterial3D:
		_screen_mat = (sc.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		sc.set_surface_override_material(0, _screen_mat)

func _build_toy() -> void:
	match kind:
		"ball":
			_shape_sphere(0.4)
			var hue := fmod(float(name.hash() % 1000) / 1000.0, 1.0)
			_hue = hue
			_mesh(_sphere_mesh(0.4), Mats.solid(Color.from_hsv(hue, 0.75, 1.0), 0.4))
			var stripe := _sphere_mesh(0.402)
			_mesh(stripe, Mats.solid(Color.WHITE, 0.4), Vector3.ZERO, Vector3(1.0, 0.18, 1.0))
		"gloves":
			_shape_box(Vector3(0.3, 0.08, 0.26))
			var rubber := Mats.solid(Color(1.0, 0.85, 0.1), 0.35)
			for sx in [-0.08, 0.08]:
				_mesh(_sphere_mesh(0.06), rubber, Vector3(sx, 0.0, -0.03), Vector3(0.9, 0.45, 1.5))
				_mesh(_sphere_mesh(0.025), rubber, Vector3(sx + 0.05 * signf(sx), 0.0, 0.0), Vector3(1.0, 0.7, 1.6))
				_along_z(_cyl_mesh(0.05, 0.045, 0.08), rubber, Vector3(sx, 0.0, 0.08))
		"chair":
			_shape_box(Vector3(0.5, 0.08, 0.5))
			_shape_box(Vector3(0.5, 0.5, 0.06), Vector3(0, 0.29, -0.22))
			_shape_box(Vector3(0.44, 0.4, 0.44), Vector3(0, -0.24, 0))
			var wood := Mats.textured("planks", Color(0.9, 0.7, 0.5), 0.5)
			_mesh(_box_mesh(Vector3(0.5, 0.08, 0.5)), wood)
			_mesh(_box_mesh(Vector3(0.5, 0.5, 0.06)), wood, Vector3(0, 0.29, -0.22))
			for x in [-0.2, 0.2]:
				for z in [-0.2, 0.2]:
					_mesh(_box_mesh(Vector3(0.05, 0.42, 0.05)), wood, Vector3(x, -0.25, z))
		"melon":
			_shape_sphere(0.25)
			_mesh(_sphere_mesh(0.25), Mats.solid(Color(0.12, 0.45, 0.18), 0.5), Vector3.ZERO, Vector3(1.15, 0.9, 0.9))
		"duck":
			_shape_sphere(0.22)
			var yellow := Mats.solid(Color(1.0, 0.85, 0.1), 0.4)
			_mesh(_sphere_mesh(0.2), yellow, Vector3.ZERO, Vector3(1.0, 0.9, 1.25))
			_mesh(_sphere_mesh(0.12), yellow, Vector3(0, 0.2, -0.14))
			_mesh(_box_mesh(Vector3(0.1, 0.04, 0.1)), Mats.solid(Color(1.0, 0.5, 0.05)), Vector3(0, 0.18, -0.26))
			_mesh(_sphere_mesh(0.02), Mats.solid(Color.BLACK), Vector3(-0.05, 0.24, -0.23))
			_mesh(_sphere_mesh(0.02), Mats.solid(Color.BLACK), Vector3(0.05, 0.24, -0.23))
		"pin":
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.1
			cap.height = 0.6
			cs.shape = cap
			add_child(cs)
			var cm := CapsuleMesh.new()
			cm.radius = 0.1
			cm.height = 0.6
			_mesh(cm, Mats.solid(Color(0.97, 0.97, 0.95), 0.3))
			var ring := CylinderMesh.new()
			ring.top_radius = 0.102
			ring.bottom_radius = 0.102
			ring.height = 0.05
			_mesh(ring, Mats.solid(Color(0.85, 0.1, 0.1)), Vector3(0, 0.12, 0))
		"barrel":
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.35
			cyl.height = 1.0
			cs.shape = cyl
			add_child(cs)
			var m := CylinderMesh.new()
			m.top_radius = 0.35
			m.bottom_radius = 0.35
			m.height = 1.0
			_mesh(m, Mats.solid(Color(0.85, 0.12, 0.1), 0.5, 0.3))
			var band := CylinderMesh.new()
			band.top_radius = 0.36
			band.bottom_radius = 0.36
			band.height = 0.08
			_mesh(band, Mats.solid(Color(0.15, 0.15, 0.15), 0.4, 0.6), Vector3(0, 0.25, 0))
			_mesh(band, Mats.solid(Color(0.15, 0.15, 0.15), 0.4, 0.6), Vector3(0, -0.25, 0))
		"coupe":
			_shape_box(Vector3(0.72, 0.62, 1.14))
		"sedan", "taxi", "police", "sports", "truck":
			_shape_box(CARS[kind]["size"])
			if _model == null:
				_mesh(_box_mesh(CARS[kind]["size"]), Mats.solid(Color.html(tint) if tint != "" else Color(0.5, 0.5, 0.55), 0.4))
		"package":
			_shape_box(Vector3(0.5, 0.36, 0.4))
			_mesh(_box_mesh(Vector3(0.5, 0.36, 0.4)), Mats.textured("planks", Color(0.75, 0.58, 0.38), 0.6))
		"cart":
			_shape_box(Vector3(0.6, 0.62, 0.95), Vector3(0, 0.15, -0.04))   # basket
			_shape_box(Vector3(0.5, 0.36, 0.8), Vector3(0, -0.3, -0.04))    # undercarriage
		"rocket":
			_shape_box(Vector3(0.2, 0.2, 0.7))
		"bomb":
			_shape_sphere(0.25)
			_mesh(_sphere_mesh(0.25), Mats.glow(Color(0.1, 0.1, 0.1), 0.0))
			_mesh(_sphere_mesh(0.07), Mats.glow(Color(1.0, 0.2, 0.0), 3.0), Vector3(0, 0.27, 0))
		_:  # crate
			_shape_box(Vector3.ONE * 0.8)
			_mesh(_box_mesh(Vector3.ONE * 0.8), Mats.textured("planks", Color(0.85, 0.65, 0.4), 0.6))

# ------------------------------------------------------------------ physics
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id

## Server: keep speeds sane (nothing gets flung to orbit); rockets fly straight and steer to the rider's look.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not multiplayer.is_server() or visual_only:
		return
	if kind == "rocket":
		var delta := state.step
		if rider != 0:
			var world := get_tree().get_first_node_in_group("world") as GameWorld
			var pl: Player = null
			if world != null:
				pl = world.get_node_or_null(str(rider)) as Player
			if pl != null:
				var want := (Basis(Vector3.UP, pl.yaw) * Basis(Vector3.RIGHT, pl.pitch)) * Vector3.FORWARD
				_dir = _dir.slerp(want.normalized(), clampf(2.2 * delta, 0.0, 1.0)).normalized()
		_speed = minf(_speed + 9.0 * delta, 22.0)
		state.linear_velocity = _dir * _speed
		state.angular_velocity = Vector3.ZERO
		var up := Vector3.UP if absf(_dir.y) < 0.98 else Vector3.RIGHT
		state.transform = Transform3D(Basis.looking_at(_dir, up), state.transform.origin)
		return
	if is_vehicle(kind):
		_drive_step(state)
		return
	state.linear_velocity = state.linear_velocity.limit_length(MAX_SPEED)
	state.angular_velocity = state.angular_velocity.limit_length(14.0)

## Toy coupe: stays upright; with a driver it accelerates, steers and grips like a little car.
func _drive_step(state: PhysicsDirectBodyState3D) -> void:
	var t := state.transform
	# heading from the forward vector (the body may be pitched on a slope)
	var f3 := -t.basis.z
	var flat := Vector3(f3.x, 0.0, f3.z)
	var yaw := atan2(-flat.x, -flat.z) if flat.length() > 0.01 else t.basis.get_euler().y
	var upright := Basis(Vector3.UP, yaw)
	var fwd_flat := -upright.z
	var vel := state.linear_velocity
	var cart := kind == "cart"
	var car := is_car(kind)
	var driven := rider != 0 or driver_seed != 0
	var boost := boosting and rider != 0 and kind == "coupe"   # only the toy car has rockets
	var running := boosting and rider != 0 and cart
	gravity_scale = 0.5 if boost else 1.0   # the boosters take some weight off, so ramps become jumps

	# what am I driving on? average the floor-like contact normals
	var n := Vector3.ZERO
	var cnt := 0
	for i in state.get_contact_count():
		var cn := state.get_contact_local_normal(i)
		if cn.y < 0.0:
			cn = -cn
		if cn.y > 0.45:
			n += cn
			cnt += 1
	var grounded := cnt > 0
	if grounded:
		_ground_n = _ground_n.lerp((n / float(cnt)).normalized(), 0.35).normalized()
		_air_time = 0.0
	else:
		_air_time += state.step
		if _air_time > 0.15:
			_ground_n = _ground_n.lerp(Vector3.UP, 0.08).normalized()
	var up := _ground_n if driven else Vector3.UP
	var slope_fwd := (fwd_flat - up * fwd_flat.dot(up)).normalized()

	if driven:
		var fv := vel.dot(slope_fwd) if grounded else vel.dot(fwd_flat)
		var target := _thr * (7.0 if _thr > 0.0 else 3.5)
		if cart:
			target = _thr * ((7.5 if running else 4.6) if _thr > 0.0 else 2.4)
		var accel := 14.0 if absf(target) > 0.1 else 8.0
		if car:
			var spec: Dictionary = CARS[kind]
			target = _thr * (float(spec["top"]) if _thr > 0.0 else float(spec["rev"]))
			accel = float(spec["accel"]) if absf(target) > 0.1 else 5.0
			if signf(target) != signf(fv) and absf(fv) > 0.5 and absf(target) > 0.1:
				accel = 18.0   # braking is stronger than speeding up
		if boost:
			target = 17.0
			accel = 24.0
		fv = move_toward(fv, target, accel * state.step)
		if grounded:
			vel = slope_fwd * fv     # drives straight up and down slopes
			if not boost:
				vel -= up * 0.4      # stay glued to the ground
		else:
			vel = Vector3(fwd_flat.x * fv, vel.y, fwd_flat.z * fv)
		var turn := -_steer * (1.5 if boost else 2.2) * clampf(fv / 2.5, -1.0, 1.0)
		if cart:
			turn = -_steer * 2.4   # trolleys spin on the spot
		elif car:
			var top := float(CARS[kind]["top"])
			turn = -_steer * float(CARS[kind]["turn"]) * clampf(fv / 4.0, -1.0, 1.0) * (1.0 - 0.4 * clampf(absf(fv) / top, 0.0, 1.0))
		state.angular_velocity = Vector3(0.0, turn, 0.0)
	else:
		state.angular_velocity = Vector3(0.0, state.angular_velocity.y * 0.9, 0.0)
		vel.x *= 0.98
		vel.z *= 0.98
	state.linear_velocity = vel.limit_length(MAX_SPEED if not car else float(CARS[kind]["top"]) + 6.0)
	# keep the body level with the ground it is driving on
	var basis_out := upright
	if driven and up.y < 0.999:
		var right := fwd_flat.cross(up).normalized()
		var back := right.cross(up).normalized()
		basis_out = Basis(right, up, back)
	state.transform = Transform3D(basis_out, t.origin)

@rpc("any_peer", "call_local", "unreliable")
func drive(throttle: float, steer: float, boost := false) -> void:
	if not multiplayer.is_server() or not is_vehicle(kind) or _sender() != rider:
		return
	_thr = clampf(throttle, -1.0, 1.0)
	_steer = clampf(steer, -1.0, 1.0)
	boosting = boost
	_last_drive = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if is_car(kind) and not visual_only:
		_update_driver()
		_siren_fx()
		return
	if kind == "coupe" and not visual_only:
		_boost_fx(delta)
		_coupe_face(delta)
		return
	if kind != "rocket" or visual_only:
		return
	var flame: Node = null
	if _model != null:
		flame = ModelLib.find(_model, "Flame")
	if flame != null:
		(flame as Node3D).scale = Vector3(1.0, 1.0, randf_range(0.7, 1.4))
	_smoke_t -= delta
	if _smoke_t <= 0.0:
		_smoke_t = 0.04
		var world := get_tree().get_first_node_in_group("world") as Node3D
		if world != null:
			_smoke(world, global_position + global_basis * Vector3(0, 0, 0.7))

## The toy car's googly eyes look where it turns (and wander about when parked), and the whole car squashes
## down under a full-size driver and wobbles on its springs. Runs on every peer (rider is replicated).
func _coupe_face(delta: float) -> void:
	if _model == null:
		return
	if _pupils.is_empty():
		for n in ["PupilL", "PupilR"]:
			var p := ModelLib.find(_model, n) as Node3D
			if p != null:
				_pupils.append(p)
	var yaw := global_rotation.y
	var rate := wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw
	var t := Time.get_ticks_msec() * 0.001
	var want := -clampf(rate * 0.012, -0.03, 0.03)
	if rider == 0:
		want = sin(t * 0.7) * 0.025 * signf(sin(t * 0.23))   # idly glancing around
	_look = lerpf(_look, want, 1.0 - exp(-10.0 * delta))
	var shake := 0.006 if boosting else 0.0   # eyes rattle while the rockets fire
	for p in _pupils:
		p.position = Vector3(_look + randf_range(-shake, shake), randf_range(-shake, shake), 0.0)
	# springy squash: about 15 % lower with somebody in it, bouncing with speed
	var target := 0.85 if rider != 0 else 1.0
	var speed := (global_position - _last_pos).length() / maxf(delta, 0.001)
	_last_pos = global_position
	target += sin(t * 17.0) * minf(speed, 8.0) * 0.004
	_sag_v += (target - _sag) * 160.0 * delta
	_sag_v *= exp(-9.0 * delta)
	_sag += _sag_v * delta
	_model.scale = Vector3(1.0 + (1.0 - _sag) * 0.5, _sag, 1.0)
	_model.position.y = -0.3 * (1.0 - _sag)   # keep the wheels on the ground

## Flames, smoke and noise while the coupe's boosters fire (runs on every peer).
func _boost_fx(delta: float) -> void:
	for f in _flames:
		f.visible = boosting
		if boosting:
			f.scale = Vector3(randf_range(0.8, 1.15), randf_range(0.7, 1.4), randf_range(0.8, 1.15))
	if boosting and not _was_boost:
		_sfx("launch", 0.0)
	_was_boost = boosting
	if not boosting:
		return
	_boost_snd -= delta
	if _boost_snd <= 0.0:
		_boost_snd = 0.28
		_sfx("whoosh", -3.0)
	_smoke_t -= delta
	if _smoke_t <= 0.0:
		_smoke_t = 0.035
		var world := get_tree().get_first_node_in_group("world") as Node3D
		if world != null:
			for side in [-1.0, 1.0]:
				_smoke(world, global_position + global_basis * Vector3(0.26 * side, 0.26, 1.1))

func _physics_process(delta: float) -> void:
	_age += delta
	if not multiplayer.is_server():
		return
	_prev_speed = linear_velocity.length()  # speed BEFORE this step's collisions
	if kind == "cart":
		_carry_contents()
	if driver_seed != 0 and rider == 0:
		_ai_drive(delta)
	if is_vehicle(kind) and rider != 0 and Time.get_ticks_msec() - _last_drive > 1500:
		# the driver vanished (disconnected, respawned, fell over...): free the seat
		var old := get_tree().get_first_node_in_group("world")
		if old != null:
			var rp := old.get_node_or_null(str(rider)) as Node3D
			if rp != null:
				remove_collision_exception_with(rp)
		rider = 0
		boosting = false
		gravity_scale = 1.0
		_pm.friction = float(def_of(kind)["friction"])
	if passenger != 0 and Engine.get_physics_frames() % 30 == 0:
		var w0 := get_tree().get_first_node_in_group("world")
		if w0 == null or w0.get_node_or_null(str(passenger)) == null:
			passenger = 0   # they left the game
	if global_position.y < -25.0:
		queue_free()
		return
	# Water: float and drag
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null:
		var surface := world.water_surface(global_position)
		if is_nan(surface):
			linear_damp = 0.1
			angular_damp = 0.5
		else:
			var def: Dictionary = def_of(kind)
			var depth := surface - global_position.y
			var frac := clampf(depth / float(def["half"]) * 0.5 + 0.5, 0.0, 1.0)
			if depth > -float(def["half"]):
				apply_central_force(Vector3(0.0, mass * 16.0 * float(def["float"]) * frac, 0.0))
			linear_damp = 2.5
			angular_damp = 2.0

func _on_body_entered(body: Node) -> void:
	if kind == "rocket":
		explode()
		return
	if kind == "barrel" and _prev_speed > 10.0:
		explode()
		return
	# Driving into people: a moving cart or car bowls them over.
	if is_vehicle(kind) and (rider != 0 or driver_seed != 0) and _prev_speed > 2.2:
		var victim := body as Player
		var now0 := Time.get_ticks_msec()
		if victim != null and victim.get_multiplayer_authority() != rider and victim.get_multiplayer_authority() != passenger:
			var vid := victim.get_multiplayer_authority()
			if now0 - int(_bonk_cd.get(vid, 0)) > 700:
				_bonk_cd[vid] = now0
				var shove := linear_velocity.limit_length(8.0 if not is_car(kind) else 14.0) * 1.1 + Vector3.UP * (3.0 if not is_car(kind) else 5.0)
				victim.knock.rpc_id(vid, shove)
				_sfx_all("thud")
				var gw := get_tree().get_first_node_in_group("world") as GameWorld
				if gw != null:
					gw.maybe_sever_player(victim, victim.global_position + Vector3.UP * 0.45, 0.25, shove)
			return
		var npc := body as Npc
		if npc != null:
			var hard := 9.0 if not is_car(kind) else 14.0
			npc.damage(int(_prev_speed * hard), linear_velocity.limit_length(8.0 if not is_car(kind) else 14.0) + Vector3.UP * 3.0, rider, npc.global_position + Vector3.UP * 0.45)
			return
	var hit_npc := body as Npc
	if hit_npc != null and _prev_speed > 7.0 and _age > 0.15:
		hit_npc.damage(int(_prev_speed * 2.5 * clampf(mass, 0.5, 4.0)), linear_velocity.limit_length(6.0) * 0.6, shooter)
	# Bonk! A fast toy knocks players over.
	var player := body as Player
	if player != null and _prev_speed > 8.0:
		var now := Time.get_ticks_msec()
		var pid := player.get_multiplayer_authority()
		if pid == shooter and _age < 1.5:
			return   # your own throw does not knock you over
		if now - int(_bonk_cd.get(pid, 0)) > 900:
			_bonk_cd[pid] = now
			var push := linear_velocity.limit_length(9.0) * clampf(mass / 3.0, 0.4, 1.0) * 0.6
			player.knock.rpc_id(pid, push + Vector3.UP * 1.5)

# ------------------------------------------------------------------ actions
## A player picks this up: it disappears from the world and appears in their hand.
@rpc("any_peer", "call_local", "reliable")
func pickup() -> void:
	if not multiplayer.is_server() or exploded or kind == "rocket" or is_car(kind) or (is_vehicle(kind) and (rider != 0 or passenger != 0)):
		return
	var who := _sender()
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	var pl: Player = null
	if world != null:
		pl = world.get_node_or_null(str(who)) as Player
	if pl == null or pl.global_position.distance_to(global_position) > 5.5:
		return
	exploded = true  # nobody else can pick it up too
	if kind == "gloves":
		pl.wear_gloves.rpc_id(who)
	else:
		pl.equip.rpc_id(who, kind, tint)
	queue_free()

## Gentle push from a walking player or a ragdolling body.
@rpc("any_peer", "call_local", "unreliable")
func push(impulse: Vector3) -> void:
	if not multiplayer.is_server():
		return
	apply_central_impulse(impulse.limit_length(20.0 * maxf(mass, 1.0)))

## A proper shove (left click, bullets, bats).
@rpc("any_peer", "call_local", "reliable")
func hit(impulse: Vector3) -> void:
	if not multiplayer.is_server() or exploded:
		return
	if in_cart != null:
		leave_cart()   # a good whack knocks it out of the basket
	apply_central_impulse(impulse.limit_length(60.0))
	if kind == "barrel":
		hp -= 1
		if hp <= 0:
			explode()

func chain_explode() -> void:
	if exploded or not (kind == "barrel" or kind == "bomb"):
		return
	get_tree().create_timer(randf_range(0.1, 0.35)).timeout.connect(explode)

func explode() -> void:
	if exploded or not multiplayer.is_server() or not is_inside_tree():
		return
	for c in cart_contents.duplicate():
		if is_instance_valid(c):
			(c as Prop).leave_cart()
	exploded = true
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null:
		if rider != 0:
			var rp := world.get_node_or_null(str(rider)) as Player
			if rp != null:
				rp.stop_ride.rpc_id(rider)
		if passenger != 0:
			var pp := world.get_node_or_null(str(passenger)) as Player
			if pp != null:
				pp.stop_ride.rpc_id(passenger)
		world.explode_at(global_position, 5.5 if kind == "rocket" else 7.0, 20.0)
	queue_free()

## Sharp things (bullets, knives, explosions) pop beach balls.
func pop() -> void:
	if kind != "ball" or exploded or not multiplayer.is_server() or not is_inside_tree():
		return
	exploded = true
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null:
		world.pop_fx.rpc(global_position, _hue)
	queue_free()

## Jump on! A player near a flying rocket rides it and steers with their look direction.
@rpc("any_peer", "call_local", "reliable")
func ride() -> void:
	if not multiplayer.is_server() or (kind != "rocket" and not is_vehicle(kind)) or exploded:
		return
	if rider != 0 and not is_car(kind):
		return
	var who := _sender()
	if who == rider:
		return
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	var pl: Player = null
	if world != null:
		pl = world.get_node_or_null(str(who)) as Player
	var reach := 8.0 if kind == "rocket" else (4.2 if is_car(kind) else 3.2)
	if pl == null or pl.global_position.distance_to(global_position) > reach:
		return
	if is_car(kind) and world != null:
		# hijack! whoever is in the driver's seat gets dragged out
		if driver_seed != 0:
			world.npc_driver_ejected(self, driver_seed, who)
			driver_seed = 0
			ai_route = []
		if rider != 0:
			var old := world.get_node_or_null(str(rider)) as Player
			if old != null:
				remove_collision_exception_with(old)
				old.stop_ride.rpc_id(rider)
				old.knock.rpc_id(rider, global_basis * Vector3(-5.0, 0.0, 0.0) + Vector3.UP * 3.0)
			world.toast.rpc("%s got carjacked!" % str(Net.players.get(rider, {}).get("name", "Someone")))
			rider = 0
	rider = who
	sleeping = false
	_last_drive = Time.get_ticks_msec()
	_pm.friction = 0.0   # a driven coupe rolls freely; the drive code sets the speed itself
	add_collision_exception_with(pl)
	pl.begin_ride.rpc_id(who, get_path(), false)

## Climb into the cart's basket (someone else pushes).
@rpc("any_peer", "call_local", "reliable")
func sit_in() -> void:
	if not multiplayer.is_server() or kind != "cart" or passenger != 0 or exploded:
		return
	var who := _sender()
	if who == rider:
		return
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	var pl: Player = null
	if world != null:
		pl = world.get_node_or_null(str(who)) as Player
	if pl == null or pl.global_position.distance_to(global_position) > 3.2:
		return
	passenger = who
	sleeping = false
	add_collision_exception_with(pl)
	pl.begin_ride.rpc_id(who, get_path(), true)

@rpc("any_peer", "call_local", "reliable")
func leave_seat() -> void:
	if not multiplayer.is_server() or passenger == 0 or _sender() != passenger:
		return
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null:
		var pp := world.get_node_or_null(str(passenger)) as Node3D
		if pp != null:
			remove_collision_exception_with(pp)
	passenger = 0

@rpc("any_peer", "call_local", "reliable")
func end_ride() -> void:
	if not multiplayer.is_server() or rider == 0 or _sender() != rider:
		return
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world != null:
		var rp := world.get_node_or_null(str(rider)) as Player
		if rp != null:
			remove_collision_exception_with(rp)
	rider = 0
	_thr = 0.0
	_steer = 0.0
	boosting = false
	gravity_scale = 1.0
	_pm.friction = float(def_of(kind)["friction"])

## Car horn (LMB while driving). Police cars: RMB flips the lights on and off.
@rpc("any_peer", "call_local", "reliable")
func horn() -> void:
	if not multiplayer.is_server() or not is_car(kind) or _sender() != rider:
		return
	_sfx_all("honk")

@rpc("any_peer", "call_local", "reliable")
func toggle_siren() -> void:
	if not multiplayer.is_server() or kind != "police" or _sender() != rider:
		return
	siren = not siren

# ------------------------------------------------------------ cars: paint, driver, AI
func _paint_car() -> void:
	if _model == null:
		return
	var c := Color.html(tint) if tint != "" and Color.html_is_valid(tint) else Color(-1, 0, 0)
	if kind == "taxi" or kind == "police" or c.r < 0.0:
		return
	var paint := Mats.solid(c, 0.25, 0.3)
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and String(m.resource_name) == "paint":
				mi.set_surface_override_material(i, paint)

## A townsperson behind the wheel (everyone builds the same one from the seed).
func _update_driver() -> void:
	if driver_seed == _driver_shown:
		return
	_driver_shown = driver_seed
	if _driver_body != null:
		_driver_body.queue_free()
		_driver_body = null
	if driver_seed == 0:
		return
	_driver_body = NpcBody.new()
	add_child(_driver_body)
	if not _driver_body.load_npc(NpcLook.random(driver_seed)):
		_driver_body.queue_free()
		_driver_body = null
		return
	_driver_body.position = CARS[kind]["seat"]
	_driver_body.seat_ik = CARS[kind]["ik"]
	_driver_body.set_pose(6, 0)
	_driver_body.animate(0.0, false)

func _siren_fx() -> void:
	if _siren_nodes.size() < 2:
		return
	var on := siren
	var t := Time.get_ticks_msec() / 160
	_siren_nodes[0].visible = on and t % 2 == 0
	_siren_nodes[1].visible = on and t % 2 == 1

## Server: a townsperson drives this car round the town's roads (right-hand traffic), slowing for
## corners, braking (and honking) for anything in the way, and eventually just pushing through.
func _ai_drive(delta: float) -> void:
	var world := get_tree().get_first_node_in_group("world") as GameWorld
	if world == null or world.town == null or ai_route.size() < 2:
		_thr = 0.0
		return
	var town := world.town
	var a: Vector3 = town.road_nodes[int(ai_route[0])]
	var b: Vector3 = town.road_nodes[int(ai_route[1])]
	var seg := b - a
	seg.y = 0.0
	if seg.length() < 0.5:
		ai_route = [ai_route[1], town.next_road_node(int(ai_route[1]), int(ai_route[0]))]
		return
	var d := seg.normalized()
	var right := Vector3(-d.z, 0.0, d.x)
	var lane_a := a + right * 2.1
	var pos := global_position
	pos.y = 0.0
	var along := (pos - lane_a).dot(d)
	if along > seg.length() - 6.0:
		ai_route = [ai_route[1], town.next_road_node(int(ai_route[1]), int(ai_route[0]))]
		return
	var aim := lane_a + d * minf(along + 9.0, seg.length() + 3.0)
	var to := aim - pos
	var want_yaw := atan2(-to.x, -to.z)
	var diff := wrapf(want_yaw - global_rotation.y, -PI, PI)
	_steer = clampf(-diff * 2.2, -1.0, 1.0)
	var cruise := 0.55 if kind != "police" else 0.6
	var thr := cruise * (1.0 - clampf(absf(diff) * 1.2, 0.0, 0.65))
	# something in front?
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var half_len := float(CARS[kind]["size"].z) * 0.5
	var from := global_position + fwd * (half_len + 0.2) + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 9.0, 1 | 4)
	q.exclude = [get_rid()]
	var ray_hit := get_world_3d().direct_space_state.intersect_ray(q)
	var blocked := false
	if not ray_hit.is_empty():
		var col := ray_hit["collider"] as Node
		blocked = col is Player or col is Npc or col is Prop or (col != null and col.get_parent() is PlayerRagdoll)
	if blocked:
		_ai_block_t += delta
		_ai_honk_t -= delta
		if _ai_honk_t <= 0.0:
			_ai_honk_t = randf_range(1.5, 3.0)
			_sfx_all("honk")
		if _ai_block_t < 6.0:
			thr = 0.0 if linear_velocity.length() < 1.0 else -0.4
		else:
			thr = 0.35   # fine, I'm going through
	else:
		_ai_block_t = 0.0
	_thr = thr
	_last_drive = Time.get_ticks_msec()

# ---------------------------------------------------------------- effects
func play_fx(what: String) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	var tip := global_position + global_basis * Vector3(0, 0, -0.05)
	match what:
		"shoot":
			_sfx("shot", 2.0)
			if _flash != null:
				_flash.visible = true
				_flash.scale = Vector3.ONE * randf_range(0.7, 1.3)
				get_tree().create_timer(0.05).timeout.connect(_hide_flash)
			_kick()
		"rpg":
			_sfx("launch", 5.0)
			if _flash != null:
				_flash.visible = true
				get_tree().create_timer(0.12).timeout.connect(_hide_flash)
			_kick()
			if world != null:
				for k in 5:
					get_tree().create_timer(0.05 * k).timeout.connect(_smoke.bind(world, global_position + global_basis * Vector3(0, 0.05, 0.6)))
		"swing":
			_sfx("whoosh")
			var tw := create_tween()
			tw.tween_property(_pv, "rotation_degrees:x", -75.0, 0.12)
			tw.tween_property(_pv, "rotation_degrees:x", 0.0, 0.3)
		"stab":
			_sfx("stab")
			var tw2 := create_tween()
			tw2.tween_property(_pv, "position:z", -0.35, 0.07)
			tw2.tween_property(_pv, "position:z", 0.0, 0.2)
		"bleep":
			_sfx("bleep")
			if _screen_mat != null:
				var c := Color.from_hsv(randf(), 0.7, 1.0)
				_screen_mat.albedo_color = c
				_screen_mat.emission = c
		"puff":
			_sfx("puff", -6.0)
			if world != null:
				for k in 4:
					get_tree().create_timer(0.12 * k).timeout.connect(_smoke.bind(world, tip))
		"eat":
			if kind == "soda" or kind == "beer":
				_sfx("glug")
			else:
				_sfx("nom")
			if world != null:
				(world as GameWorld).burp_at(global_position)
			if world != null:
				_crumbs(world)

func _kick() -> void:
	if _pv == null:
		return
	_pv.rotation_degrees = Vector3(-18, 0, 0)
	_pv.position.z = 0.14
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_pv, "rotation_degrees", Vector3.ZERO, 0.15)
	tw.tween_property(_pv, "position:z", 0.0, 0.15)

func _sfx(kind_name: String, vol := 0.0) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world != null:
		Sfx.play_at(world, kind_name, global_position, vol)

func _hide_flash() -> void:
	if _flash != null:
		_flash.visible = false

func _smoke(world: Node3D, at: Vector3) -> void:
	if not is_instance_valid(world):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(0.04)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.85, 0.85, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = at + Vector3(randf_range(-0.03, 0.03), 0.0, randf_range(-0.03, 0.03))
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position:y", mi.global_position.y + 0.9, 1.6)
	tw.tween_property(mi, "scale", Vector3.ONE * 5.0, 1.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.6)
	tw.chain().tween_callback(mi.queue_free)

func _crumbs(world: Node3D) -> void:
	var col := Color(0.85, 0.6, 0.3) if kind != "beer" and kind != "soda" else Color(0.9, 0.9, 0.6)
	for k in 8:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(Vector3.ONE * 0.02)
		mi.material_override = Mats.solid(col)
		world.add_child(mi)
		mi.global_position = global_position
		var end := global_position + Vector3(randf_range(-0.3, 0.3), -0.6, randf_range(-0.3, 0.3))
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", end, 0.5)
		tw.tween_callback(mi.queue_free)

## Play a sound on this prop for everyone.
func _sfx_all(what: String) -> void:
	_sfx_rpc.rpc(what)

@rpc("authority", "call_local", "unreliable")
func _sfx_rpc(what: String) -> void:
	_sfx(what, 2.0)

## Torn-off arm / leg / head (gore). Long axis along Z: the hand / foot end (+Z) is where you hold it,
## the bloody stump (-Z) is the business end.
func _build_limb() -> void:
	var parts := tint.split("|")
	var skin: Color = Color.html(parts[0]) if parts.size() > 0 and parts[0].is_valid_html_color() else Color(0.96, 0.78, 0.66)
	var hair: Color = Color.html(parts[1]) if parts.size() > 1 and parts[1].is_valid_html_color() else Color(0.25, 0.16, 0.1)
	var skin_m := Mats.solid(skin, 0.7)
	var stump_m := Mats.solid(Color(0.65, 0.04, 0.05), 0.35)
	var bone_m := Mats.solid(Color(0.95, 0.93, 0.85), 0.5)
	match kind:
		"limb_head":
			_shape_sphere(0.13)
			_mesh(_sphere_mesh(0.13), skin_m)
			_mesh(_sphere_mesh(0.135), Mats.solid(hair, 0.9), Vector3(0, 0.05, 0.015), Vector3(1.0, 0.6, 1.0))
			for sx in [-0.045, 0.045]:
				_mesh(_sphere_mesh(0.02), Mats.solid(Color(0.05, 0.05, 0.05), 0.3), Vector3(sx, 0.02, -0.12), Vector3(1.0, 0.4, 1.0))   # eyes shut: x_x
			_mesh(_cyl_mesh(0.05, 0.05, 0.03), stump_m, Vector3(0, -0.125, 0))
		_:
			var leg := kind == "limb_leg"
			var length := 0.85 if leg else 0.62
			var r := 0.075 if leg else 0.055
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = length
			cs.shape = cap
			cs.rotation_degrees = Vector3(90, 0, 0)
			add_child(cs)
			var cm := CapsuleMesh.new()
			cm.radius = r
			cm.height = length
			_along_z(cm, skin_m, Vector3.ZERO)
			_along_z(_cyl_mesh(r * 0.96, r * 0.96, 0.02), stump_m, Vector3(0, 0, -length * 0.5 + r * 0.55))
			_along_z(_cyl_mesh(r * 0.35, r * 0.35, 0.05), bone_m, Vector3(0, 0, -length * 0.5 + r * 0.4))
			if leg:
				_mesh(_box_mesh(Vector3(0.11, 0.09, 0.24)), Mats.solid(Color(0.15, 0.15, 0.18), 0.8), Vector3(0, -0.06, length * 0.5 - 0.02))   # shoe
			else:
				_mesh(_sphere_mesh(0.055), skin_m, Vector3(0, 0, length * 0.5 - 0.01), Vector3(1.1, 0.8, 1.3))   # fist

# ------------------------------------------------------------ shopping cart contents
func _on_basket_body(body: Node) -> void:
	var p := body as Prop
	if p == null or p == self or p.in_cart != null or p.exploded or is_vehicle(p.kind) or p.kind == "rocket":
		return
	if float(def_of(p.kind)["half"]) > 0.3 or cart_contents.size() >= 10:
		return
	load_into_cart(p)

## Server: stick a prop in this cart's basket, where it landed (kept inside the basket walls).
func load_into_cart(p: Prop) -> void:
	var flat := Transform3D(Basis(Vector3.UP, global_rotation.y), global_position)
	var local := flat.affine_inverse() * p.global_position
	var h := float(def_of(p.kind)["half"])
	local.x = clampf(local.x, -0.22 + h * 0.5, 0.22 - h * 0.5)
	local.z = clampf(local.z, -0.4 + h * 0.5, 0.32 - h * 0.5)
	local.y = clampf(local.y, -0.05 + h, 0.45)
	p.in_cart = self
	p._saved_layers = Vector2i(p.collision_layer, p.collision_mask)
	p.collision_layer = 0
	p.collision_mask = 0
	p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.freeze = true
	p._cart_local = Transform3D((flat.basis.inverse() * p.global_basis).orthonormalized(), local)
	cart_contents.append(p)
	_sfx_all("thud")

## Server: let go of a prop (it was knocked out, or the cart is gone).
func leave_cart() -> void:
	if in_cart == null:
		return
	if is_instance_valid(in_cart):
		in_cart.cart_contents.erase(self)
	in_cart = null
	freeze = false
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y

func _carry_contents() -> void:
	if cart_contents.is_empty():
		return
	var flat := Transform3D(Basis(Vector3.UP, global_rotation.y), global_position)
	for c in cart_contents.duplicate():
		if not is_instance_valid(c):   # (check before casting: casting a freed object is an error)
			cart_contents.erase(c)
			continue
		var p := c as Prop
		if p == null or p.exploded:
			cart_contents.erase(c)
			continue
		p.global_transform = flat * p._cart_local

func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		for c in cart_contents.duplicate():
			if is_instance_valid(c):
				(c as Prop).leave_cart()
