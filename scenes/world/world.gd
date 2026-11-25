class_name GameWorld
extends Node3D
## The party house and everything around it, plus the networking glue for spawning
## players and props, explosions, water and the HUD. Everything is built in code.

## Key 1..8 spawns these (see autoload/input_setup.gd)
const PROP_ORDER := ["crate", "ball", "chair", "melon", "duck", "pin", "barrel", "bomb"]
const PROP_LABELS := ["crate", "beach ball", "chair", "watermelon", "duck", "bowling pin", "barrel (boom)", "bomb (boom)"]
const MAX_PROPS := 80
const MAX_NPCS := 24

var player_spawner: MultiplayerSpawner
var prop_spawner: MultiplayerSpawner
var house: HouseFull
var town: Town
var missions: Missions
var _prop_counter := 0
var map_ready := false          # false until the map (house or Workshop .glb) is built; players wait
var spawn_point := Vector3(-4.6, 0.2, 1.7)
var custom_map := false
var _map_started := false
signal map_loaded

func _ready() -> void:
	add_to_group("world")
	_build_environment()

	# Spawn functions must be set on EVERY peer so clients can build what the server spawns.
	player_spawner = MultiplayerSpawner.new()
	player_spawner.name = "PlayerSpawner"
	player_spawner.spawn_path = NodePath("..")
	player_spawner.spawn_function = _spawn_player
	add_child(player_spawner)

	prop_spawner = MultiplayerSpawner.new()
	prop_spawner.name = "PropSpawner"
	prop_spawner.spawn_path = NodePath("..")
	prop_spawner.spawn_function = _spawn_prop_node
	add_child(prop_spawner)

	_build_hud()
	missions = Missions.new()
	missions.name = "Missions"
	add_child(missions)

	Content.blob_ready.connect(func(_id): _try_load_map())
	if multiplayer.is_server():
		Net.player_joined.connect(_on_player_joined)
		Net.player_left.connect(_on_player_left)
		_try_load_map()
		if not map_ready:   # the default house is built instantly; a Workshop map takes a moment
			await map_loaded
		_on_player_joined(1)  # the host plays too
		_spawn_starting_props()
	else:
		Net.map_changed.connect(_try_load_map)   # the host tells us which map to build

# --------------------------------------------------------------------- map
func _try_load_map() -> void:
	if _map_started or Net.map.is_empty():
		return
	var id := str(Net.map.get("id", ""))
	if id.is_empty():
		_map_started = true
		_build_house()
	elif Content.has(id):
		_map_started = true
		await _build_custom_map(id)
	else:
		return   # still downloading it; blob_ready will call us again
	map_ready = true
	map_loaded.emit()

func _build_house() -> void:
	house = HouseFull.new()
	house.name = "House"
	add_child(house)
	house.build()
	house.trampoline_hit.connect(_on_trampoline)
	house.board_hit.connect(_on_board)
	spawn_point = Vector3(-4.6, 0.2, 1.7)
	town = Town.new()
	town.name = "Town"
	add_child(town)
	town.build_town()

## A Workshop .glb map: every mesh becomes solid (trimesh), spawn at a node named "spawn*" or on the ground.
func _build_custom_map(id: String) -> void:
	var scene := Content.load_scene(Content.path_of(id))
	if scene == null:
		push_warning("Could not load map %s, using the house" % id)
		_build_house()
		return
	custom_map = true
	scene.name = "CustomMap"
	add_child(scene)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			(mi as MeshInstance3D).create_trimesh_collision()
	var marker := scene.find_child("spawn*", true, false) as Node3D
	await get_tree().physics_frame
	await get_tree().physics_frame
	if marker != null:
		spawn_point = marker.global_position + Vector3.UP * 0.5
	else:
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 300, 0), Vector3(0, -300, 0), 1)
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		spawn_point = (res["position"] + Vector3.UP * 0.6) if not res.is_empty() else Vector3(0, 5, 0)

# -------------------------------------------------------------------- water
## Surface height if this point is above the pool, otherwise NAN.
## A pool ladder I can climb from here, or {}.
func ladder_near(pos: Vector3) -> Dictionary:
	if house == null or custom_map:
		return {}
	for l in house.ladders:
		var lp: Vector3 = l["pos"]
		var flat := Vector2(pos.x - lp.x, pos.z - lp.z)
		if flat.length() < 0.85 and pos.y > HouseFull.POOL_FLOOR - 0.6 and pos.y < 0.25:
			return l
	return {}

func water_surface(pos: Vector3) -> float:
	if custom_map:
		return NAN
	if HouseFull.POOL_RECT.has_point(Vector2(pos.x, pos.z)) and pos.y > HouseFull.POOL_FLOOR - 1.0:
		return HouseFull.POOL_SURFACE
	return NAN

# ------------------------------------------------------------------ spawning
func _spawn_player(data: Variant) -> Node:
	var p := Player.new()
	p.name = str(int(data["id"]))
	p.position = data["pos"]
	return p

func _spawn_prop_node(data: Variant) -> Node:
	if str(data["kind"]) == "npc":
		var n := Npc.new()
		n.name = "Npc_%d" % int(data["id"])
		n.position = data["pos"]
		n.rotation.y = float(data.get("yaw", 0.0))
		n.look_seed = int(data.get("seed", 0))
		n.owner_id = int(data.get("by", 0))
		n.resident = bool(data.get("res", false))
		n.troublemaker = bool(data.get("trouble", false))
		return n
	var p := Prop.new()
	p.kind = data["kind"]
	p.name = "Prop_%d" % int(data["id"])
	p.position = data["pos"]
	p.rotation.y = float(data.get("yaw", 0.0))
	p.init_vel = data["vel"]
	p.shooter = int(data.get("by", 0))
	p.tint = str(data.get("tint", ""))
	p.driver_seed = int(data.get("drv", 0))
	return p

func _on_player_joined(id: int) -> void:
	if not map_ready:
		await map_loaded
	var pos := Vector3(randf_range(-1.5, 0.8), 1.0, randf_range(1.5, 5.0))
	if custom_map:
		pos = spawn_point + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
	player_spawner.spawn({"id": id, "pos": pos})
	if not money.has(id):
		money[id] = START_MONEY if not Net.is_campaign() else CAMPAIGN_START_MONEY
	_send_money(id)
	if Net.is_campaign():
		get_tree().create_timer(3.0).timeout.connect(_toast_to.bind(id, "CAMPAIGN: no spawning, no free money. Head east along Main St to the JOB BOARD in town and earn your cash!"))

func _on_player_left(id: int) -> void:
	money.erase(id)
	var node := get_node_or_null(str(id))
	if node != null:
		node.queue_free()

func _spawn_prop(kind: String, pos: Vector3, vel := Vector3.ZERO, by := 0, tint := "") -> Node:
	if kind == "npc":
		return spawn_npc(pos, randi() % 100000, by)
	var props := get_tree().get_nodes_in_group("props")
	if props.size() >= MAX_PROPS:
		for old in props:   # the oldest toy goes away (never a car)
			if not Prop.is_car((old as Prop).kind):
				old.queue_free()
				break
	_prop_counter += 1
	if Prop.is_car(kind) and tint == "":
		tint = Prop.CAR_COLORS[randi() % Prop.CAR_COLORS.size()]
	return prop_spawner.spawn({"kind": kind, "pos": pos, "id": _prop_counter, "vel": vel, "by": by, "tint": tint})

## Server: a person with a given look. Spawned ones count towards MAX_NPCS; townspeople don't.
func spawn_npc(pos: Vector3, look_seed: int, by := 0, res := false, trouble := false, yaw := 0.0) -> Npc:
	if not res and not trouble:
		var mine: Array = []
		for n in get_tree().get_nodes_in_group("npcs"):
			if not (n as Npc).resident and not (n as Npc).troublemaker:
				mine.append(n)
		if mine.size() >= MAX_NPCS:
			mine[0].queue_free()
	_prop_counter += 1
	return prop_spawner.spawn({"kind": "npc", "pos": pos, "id": _prop_counter, "vel": Vector3.ZERO, "by": by,
		"seed": look_seed, "res": res, "trouble": trouble, "yaw": yaw}) as Npc

## Server: a car, optionally with a townsperson driving it along `route` ([from, to] road nodes).
func spawn_car(kind: String, pos: Vector3, yaw: float, driver := 0, route: Array = [], tint := "") -> Prop:
	_prop_counter += 1
	if tint == "":
		tint = Prop.CAR_COLORS[randi() % Prop.CAR_COLORS.size()]
	var h: float = float(Prop.CARS[kind]["size"].y) * 0.5 + 0.08
	var p := prop_spawner.spawn({"kind": kind, "pos": Vector3(pos.x, h, pos.z), "id": _prop_counter, "vel": Vector3.ZERO,
		"by": 0, "tint": tint, "yaw": yaw, "drv": driver}) as Prop
	if p != null:
		p.ai_route = route
	return p

@rpc("any_peer", "call_local", "reliable")
func request_spawn(kind: String, pos: Vector3) -> void:
	if not multiplayer.is_server() or (kind != "npc" and (not Prop.is_valid_kind(kind) or Prop.is_restricted(kind))):
		return
	if not pos.is_finite() or pos.length() > 300.0:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if Net.is_campaign():
		_toast_to(id, "Campaign: no spawning. Earn cash with jobs (job board at WOBBLY JOBS, Main St) and buy stuff.")
		return
	if id != 1 and not guests_can_spawn:
		_toast_to(id, "The host has turned spawning off")
		return
	var mine := 0
	if kind == "npc":
		for n in get_tree().get_nodes_in_group("npcs"):
			if int(n.get("owner_id")) == id:
				mine += 1
		if mine >= SPAWN_LIMIT_PEOPLE:
			_toast_to(id, "You already have %d people out (limit)" % SPAWN_LIMIT_PEOPLE)
			return
	else:
		for n in get_tree().get_nodes_in_group("props"):
			if (n as Prop).shooter == id:
				mine += 1
		if mine >= SPAWN_LIMIT:
			_toast_to(id, "Spawn limit reached (%d things each). The host can clear stuff in the pause menu." % SPAWN_LIMIT)
			return
	if Prop.is_car(kind):
		var pl := get_node_or_null(str(id)) as Node3D
		var yaw := pl.global_rotation.y if pl != null else 0.0
		var c := spawn_car(kind, pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, -2.0), yaw)
		if c != null:
			c.shooter = id
		return
	_spawn_prop(kind, pos, Vector3.ZERO, id)

# ---------------------------------------------------------------- spawn rules + host tools
const SPAWN_LIMIT := 20         # things each player can have out at once
const SPAWN_LIMIT_PEOPLE := 8   # people each player can have out at once
var guests_can_spawn := true    # host switch

## Host tools (pause menu). Run on the host only.
func host_clear(what: String) -> void:
	if not multiplayer.is_server():
		return
	match what:
		"props":
			for n in get_tree().get_nodes_in_group("props"):
				if (n as Prop).kind != "rpg":
					n.queue_free()
		"people":
			for n in get_tree().get_nodes_in_group("npcs"):
				n.queue_free()
		"traffic":
			for n in get_tree().get_nodes_in_group("props"):
				if Prop.is_car((n as Prop).kind) and (n as Prop).rider == 0:
					n.queue_free()
		"gore":
			for n in get_tree().get_nodes_in_group("props"):
				if Prop.is_limb((n as Prop).kind):
					n.queue_free()
			clear_blood.rpc()
		"all":
			for n in get_tree().get_nodes_in_group("props"):
				n.queue_free()
			for n in get_tree().get_nodes_in_group("npcs"):
				n.queue_free()
			clear_blood.rpc()
			get_tree().create_timer(0.3).timeout.connect(_spawn_starting_props)
	toast.rpc("The host cleared %s" % {"props": "all the props", "people": "all the people", "gore": "the blood and body parts", "traffic": "the cars", "all": "everything (fresh start)"}.get(what, what))
	toast("Cleared")

@rpc("authority", "call_local", "reliable")
func clear_blood() -> void:
	for n in get_tree().get_nodes_in_group("blood_splat"):
		n.queue_free()

func _spawn_starting_props() -> void:
	if custom_map:
		for i in 3:
			_spawn_prop("ball", spawn_point + Vector3(2.0 + i * 0.8, 1.5, 0))
		_spawn_prop("crate", spawn_point + Vector3(0, 1.5, 3.0))
		return
	for i in 5:   # beach balls in the living room
		_spawn_prop("ball", Vector3(-7.5 + i * 0.9, 1.0, 0.8))
	for i in 2:
		_spawn_prop("chair", Vector3(-2.6 + i * 1.0, 0.5, 1.2))
	for row in 3:   # crate pyramid in the party room
		for i in 3 - row:
			_spawn_prop("crate", Vector3(7.2 + i * 0.85 + row * 0.42, 0.42 + row * 0.82, -5.6))
	for r in 4:     # bowling pins on the front lawn
		for i in 4 - r:
			_spawn_prop("pin", Vector3((i - (3 - r) / 2.0) * 0.32, 0.35, 18.0 - r * 0.28))
	for i in 4:     # ducks and a ball in the pool
		_spawn_prop("duck", Vector3(-2.0 + i * 1.3, -0.2, -15.0 + (i % 2) * 1.2))
	_spawn_prop("ball", Vector3(1.0, -0.2, -13.5))
	for i in 3:
		_spawn_prop("melon", Vector3(7.0 + i * 0.5, 0.3, 6.0))
	_spawn_rpg()
	_spawn_prop("coupe", Vector3(4.0, 0.5, 13.0))
	for i in 3:     # trolleys outside the shop
		_spawn_prop("cart", Vector3(-6.0 + i * 0.75, 0.55, 60.2))
	for i in 3:     # explosives live far away in the back yard
		_spawn_prop("barrel", Vector3(-10.0 - i * 0.9, 0.6, -10.0))
	_populate_town(true)

## The RPG is on the roof: you need the trampoline (or a very good jump) to get up there.
## It comes back a while after somebody takes it.
const RPG_SPOT := Vector3(-6.0, 3.65, 2.0)

func _spawn_rpg() -> void:
	if custom_map or not multiplayer.is_server():
		return
	for n in get_tree().get_nodes_in_group("props"):
		var p := n as Prop
		if p != null and p.kind == "rpg" and p.global_position.distance_to(RPG_SPOT) < 4.0 and not p.exploded:
			return
	_spawn_prop("rpg", RPG_SPOT)
	rpg_watch()

func rpg_watch() -> void:
	# poll until the roof RPG is gone, then bring a new one back after 75 seconds
	var timer := get_tree().create_timer(5.0)
	await timer.timeout
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("props"):
		var p := n as Prop
		if p != null and p.kind == "rpg" and not p.exploded and p.global_position.distance_to(RPG_SPOT) < 4.0:
			rpg_watch()
			return
	await get_tree().create_timer(75.0).timeout
	if is_inside_tree():
		_spawn_rpg()

## Beach ball pop!
@rpc("authority", "call_local", "reliable")
func pop_fx(pos: Vector3, hue: float) -> void:
	Sfx.play_at(self, "pop", pos, 3.0)
	var mat := Mats.solid(Color.from_hsv(hue, 0.75, 1.0), 0.5)
	for k in 14:
		var mi := MeshInstance3D.new()
		var qm := BoxMesh.new()
		qm.size = Vector3(0.12, 0.01, 0.08)
		mi.mesh = qm
		mi.material_override = mat if k % 2 == 0 else Mats.solid(Color.WHITE, 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = pos
		mi.rotation = Vector3(randf() * 6.0, randf() * 6.0, randf() * 6.0)
		var end := pos + Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.2), randf_range(-1.0, 1.0))
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", end, 0.45).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation", mi.rotation + Vector3(4.0, 3.0, 5.0), 0.9)
		tw.chain().tween_property(mi, "global_position:y", pos.y - 0.4, 0.5).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

# --------------------------------------------------------------- explosions
## Server only: shove everything nearby, chain-react other barrels and bombs.
func explode_at(pos: Vector3, radius: float, power: float) -> void:
	if not multiplayer.is_server():
		return
	boom_fx.rpc(pos, radius)
	alarm(pos, 0, 1.0, radius * 6.0)
	for n in get_tree().get_nodes_in_group("props"):
		var prop := n as Prop
		if prop == null or prop.exploded:
			continue
		var off := prop.global_position - pos
		var d := off.length()
		if d > radius:
			continue
		var falloff := 1.0 - d / radius
		var dir := (off.normalized() + Vector3.UP * 0.6).normalized()
		if prop.kind == "ball":
			prop.pop()
			continue
		if prop.in_cart != null:
			prop.leave_cart()
		if Prop.is_car(prop.kind):
			prop.car_blast(dir * power * falloff * prop.mass * 0.9, int(85.0 * falloff) + 10)
			continue
		prop.apply_central_impulse(dir * power * falloff * minf(prop.mass, 3.0))
		prop.chain_explode()
	for n2 in get_tree().get_nodes_in_group("npcs"):
		var npc := n2 as Npc
		if npc == null:
			continue
		var off2 := (npc.global_position + Vector3.UP * 0.9) - pos
		var d2 := off2.length()
		if d2 > radius:
			continue
		var fall2 := 1.0 - d2 / radius
		npc.damage(int(30.0 + 140.0 * fall2), (off2.normalized() + Vector3.UP * 0.7).normalized() * (4.0 + 6.0 * fall2), 0, npc.global_position + Vector3.UP, true)
	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl == null:
			continue
		var off := (pl.global_position + Vector3.UP * 0.9) - pos
		var d := off.length()
		if d > radius:
			continue
		var falloff := 1.0 - d / radius
		var flat := Vector3(off.x, 0.0, off.z)
		var away := flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
		var dir := (away + Vector3.UP * 0.55).normalized()
		# a decent shove back (4 to 9 m/s), never a launch off the map
		pl.knock.rpc_id(pl.get_multiplayer_authority(), dir * clampf(power * falloff * 0.6, 4.0, 9.0))
		if falloff > 0.4:
			maybe_sever_player(pl, pl.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 1.7), 0.0), 0.45 * falloff, dir * 6.0)

## Everyone sees (and feels) the boom.
@rpc("authority", "call_local", "reliable")
func boom_fx(pos: Vector3, radius: float) -> void:
	Sfx.play_at(self, "boom", pos, 5.0, 2.5)
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.6, 0.1)
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.5, 0.05)
	fire_mat.emission_energy_multiplier = 3.0

	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	flash.mesh = sm
	flash.material_override = fire_mat
	flash.position = pos
	flash.scale = Vector3.ONE * 0.3
	add_child(flash)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 8.0
	light.omni_range = radius * 2.0
	light.position = pos + Vector3.UP * 0.5
	add_child(light)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * radius * 0.5, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(flash.queue_free)
	tw.tween_callback(light.queue_free)

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.08
	spark_mesh.height = 0.16
	spark_mesh.material = fire_mat
	var sparks := CPUParticles3D.new()
	sparks.mesh = spark_mesh
	sparks.position = pos
	sparks.amount = 48
	sparks.lifetime = 1.0
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 5.0
	sparks.initial_velocity_max = 14.0
	sparks.gravity = Vector3(0, -16, 0)
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(1.6).timeout.connect(sparks.queue_free)

	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl != null and pl.is_multiplayer_authority():
			var d := pl.global_position.distance_to(pos)
			pl.shake(clampf(1.0 - d / (radius * 3.0), 0.0, 1.0) * 0.8)

# ----------------------------------------------------------------- trampoline
func _on_trampoline(body: Node3D) -> void:
	_launch(body, 14.0, Vector3.ZERO)

## Diving board: a springy boost up and out over the pool.
func _on_board(body: Node3D) -> void:
	_launch(body, 10.5, Vector3(0, 0, -1) * 4.5)

func _launch(body: Node3D, up: float, push: Vector3) -> void:
	if body is Player or body is Prop:
		Sfx.play_at(self, "boing", body.global_position, 2.0)
	if body is Player:
		var p := body as Player
		if p.is_multiplayer_authority() and not p.ragdolled:
			p.velocity.y = up
			p.velocity.x = push.x
			p.velocity.z = push.z if push != Vector3.ZERO else p.velocity.z
	elif body is Prop:
		if multiplayer.is_server():
			(body as Prop).linear_velocity = Vector3(push.x, up * 0.9, push.z)
	elif body is RigidBody3D and body.get_parent() is PlayerRagdoll:
		var pl := body.get_parent().get_parent() as Player
		if pl != null and pl.is_multiplayer_authority():
			(body as RigidBody3D).linear_velocity = Vector3(push.x, up * 0.85, push.z)

# --------------------------------------------------------------- environment
var _sun: DirectionalLight3D
var _env: Environment
var _gfx := -1          # which look is applied (0 normal, 1 realistic)
var _vp_defaults := {}

func _build_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -30, 0)
	_sun.shadow_enabled = true
	add_child(_sun)
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = Sky.new()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	Settings.changed.connect(_apply_graphics)
	_apply_graphics()

## Normal look (cheap, cartoony) or Settings.realistic: physically based sky, global illumination
## (SDFGI), screen-space reflections and bounce light, soft high-res shadows, sun rays through
## volumetric fog, ACES colour, and 4x anti-aliasing. Switches live from the settings.
func _apply_graphics() -> void:
	var real := 1 if Settings.realistic else 0
	if real == _gfx or _env == null:
		return
	_gfx = real
	var vp := get_viewport()
	if _vp_defaults.is_empty():
		_vp_defaults = {"msaa": vp.msaa_3d, "ssaa": vp.screen_space_aa, "lod": vp.mesh_lod_threshold}
	var env := _env
	var on := real == 1
	if on:
		var psky := PhysicalSkyMaterial.new()
		psky.turbidity = 8.0
		psky.mie_coefficient = 0.004
		psky.sun_disk_scale = 1.5
		psky.ground_color = Color(0.25, 0.27, 0.22)
		psky.energy_multiplier = 1.0
		env.sky.sky_material = psky
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.1
		env.tonemap_white = 6.0
		env.ambient_light_energy = 1.0
		env.ambient_light_sky_contribution = 1.0
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_energy = 1.0
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.2
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 2.0
		env.ssil_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.9, 0.92, 1.0)
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_sky_affect = 0.25
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.07
		env.adjustment_saturation = 1.08
		_sun.light_color = Color(1.0, 0.95, 0.88)
		_sun.light_energy = 1.25
		_sun.light_angular_distance = 0.6
		_sun.shadow_blur = 1.3
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_sun.directional_shadow_max_distance = 160.0
		_sun.light_volumetric_fog_energy = 1.6
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
		vp.msaa_3d = Viewport.MSAA_4X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.mesh_lod_threshold = 0.5
	else:
		env.sky.sky_material = ProceduralSkyMaterial.new()
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.0
		env.tonemap_white = 1.0
		env.ambient_light_energy = 0.9
		env.sdfgi_enabled = false
		env.ssr_enabled = false
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 2.0
		env.ssil_enabled = false
		env.glow_intensity = 0.8
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.volumetric_fog_enabled = false
		env.adjustment_enabled = false
		_sun.light_color = Color.WHITE
		_sun.light_energy = 1.0
		_sun.light_angular_distance = 0.0
		_sun.shadow_blur = 1.0
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_sun.directional_shadow_max_distance = 80.0
		_sun.light_volumetric_fog_energy = 1.0
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
		vp.msaa_3d = _vp_defaults["msaa"]
		vp.screen_space_aa = _vp_defaults["ssaa"]
		vp.mesh_lod_threshold = _vp_defaults["lod"]

func _exit_tree() -> void:
	# leaving the party: put the viewport back how the menu expects it
	if _gfx == 1 and not _vp_defaults.is_empty():
		var vp := get_viewport()
		vp.msaa_3d = _vp_defaults["msaa"]
		vp.screen_space_aa = _vp_defaults["ssaa"]
		vp.mesh_lod_threshold = _vp_defaults["lod"]

# ---------------------------------------------------------------------- HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# controls live in the pause menu now; just a hint that fades away
	var info := Label.new()
	info.position = Vector2(14, 10)
	info.text = "Esc: pause menu (controls are in there)"
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 6)
	layer.add_child(info)
	var tw := info.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(info, "modulate:a", 0.0, 1.5)
	_money_label = Label.new()
	_money_label.text = "$0"
	_money_label.add_theme_font_size_override("font_size", 30)
	_money_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))
	_money_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_money_label.add_theme_constant_override("outline_size", 8)
	_money_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_money_label.offset_left = -200
	_money_label.offset_right = -18
	_money_label.offset_top = 10
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(_money_label)
	if multiplayer.is_server():
		_invite_banner(layer)

## Host: show the invite code for a while after hosting (and copy it, ready to paste to friends).
func _invite_banner(layer: CanvasLayer) -> void:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = -120
	l.offset_bottom = -70
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	layer.add_child(l)
	var link := Net.link
	var copied := [false]
	var show := func():
		if not is_instance_valid(l):
			return
		if link.invite_short == "":
			l.text = "Setting up your party for friends..."
			return
		if not copied[0] and link.public_v4 != "":
			copied[0] = true
			DisplayServer.clipboard_set(link.invite_full)
		l.text = "Invite code: %s%s   (Esc for details)\n%s" % [link.invite_short, "  - copied!" if copied[0] else "",
			"Router port opened - friends can join with the code" if link.router_ok else link.router_msg]
	show.call()
	link.host_info_changed.connect(show)
	tree_exiting.connect(func():
		if link.host_info_changed.is_connected(show):
			link.host_info_changed.disconnect(show))
	var tw := l.create_tween()
	tw.tween_interval(35.0)
	tw.tween_property(l, "modulate:a", 0.0, 2.0)

# ----------------------------------------------------------- shots + menu
## Tracer line and impact spark for a gunshot (everyone sees it).
@rpc("authority", "call_local", "unreliable")
func shot_fx(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, dist)
	tracer.mesh = bm
	tracer.material_override = Mats.glow(Color(1.0, 0.85, 0.4), 5.0)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)
	var dir := (to - from) / dist
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	tracer.look_at_from_position((from + to) * 0.5, to, up)
	get_tree().create_timer(0.06).timeout.connect(tracer.queue_free)
	var spark := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	spark.mesh = sm
	spark.material_override = Mats.glow(Color(1.0, 0.7, 0.2), 4.0)
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spark)
	spark.global_position = to
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(spark.queue_free)

var _menu_layer: CanvasLayer

## Opens the spawn menu for this machine's player.
func open_menu(player: Player) -> void:
	if _menu_layer != null:
		return
	if Net.is_campaign():
		toast("Campaign: no spawn menu. Earn cash with jobs at the WOBBLY JOBS board in town, then shop!")
		return
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 15
	add_child(_menu_layer)
	var menu := SpawnMenu.new()
	_menu_layer.add_child(menu)
	player.input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.picked.connect(player.spawn_kind)
	menu.closed.connect(func():
		if _menu_layer == null:
			return
		_menu_layer.queue_free()
		_menu_layer = null
		if is_instance_valid(player):
			player.input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

# ------------------------------------------------- items in players' hands
@rpc("any_peer", "call_local", "reliable")
func request_throw(kind: String, pos: Vector3, vel: Vector3, tint := "") -> void:
	if not multiplayer.is_server() or not Prop.is_valid_kind(kind) or kind == "rocket":
		return
	if not pos.is_finite() or not vel.is_finite() or pos.length() > 300.0:
		return
	var sender := multiplayer.get_remote_sender_id()
	_spawn_prop(kind, pos, vel.limit_length(18.0), 1 if sender == 0 else sender, tint)

var _next_use := {}

## A player used the item in their hand (LMB). Server does the hit detection.
@rpc("any_peer", "call_local", "reliable")
func use_item(kind: String, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server() or not Prop.ITEMS.has(kind):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var pl := get_node_or_null(str(sender)) as Player
	if pl == null or not origin.is_finite() or not dir.is_finite() or dir.length() < 0.5:
		return
	var now := Time.get_ticks_msec()
	if now < int(_next_use.get(sender, 0)):
		return
	_next_use[sender] = now + int(float(Prop.ITEMS[kind]["cd"]) * 900.0)
	dir = dir.normalized()
	match kind:
		"pistol":
			_shoot(pl, origin, dir)
		"knife":
			pl.item_fx.rpc("stab")
			_melee(pl, origin, dir, 1.9, 6.0)   # (normally melee goes through melee_swing)
		"rpg":
			_fire_rpg(pl, origin, dir, sender)
		"bat":
			pl.item_fx.rpc("swing")
			_melee(pl, origin, dir, 2.7, 16.0)
		"limb_arm":
			pl.item_fx.rpc("swing")
			_melee(pl, origin, dir, 2.4, 11.0)
		"limb_leg":
			pl.item_fx.rpc("swing")
			_melee(pl, origin, dir, 2.6, 15.0)
		"limb_head":
			pl.item_fx.rpc("swing")
			_melee(pl, origin, dir, 2.1, 9.0)
		"cig":
			pl.item_fx.rpc("puff")
		"console":
			pl.item_fx.rpc("bleep")
		_:
			pl.item_fx.rpc("eat")
			pl.consume.rpc_id(sender, kind)

func _fire_rpg(pl: Player, origin: Vector3, dir: Vector3, sender: int) -> void:
	pl.item_fx.rpc("rpg")
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1.8, 1)
	q.exclude = [pl.get_rid()]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var dist := 1.4
	if not res.is_empty():
		dist = maxf(0.3, origin.distance_to(res["position"]) - 0.3)
	_spawn_prop("rocket", origin + dir * dist, dir * 9.0, sender)

func _shoot(pl: Player, origin: Vector3, dir: Vector3) -> void:
	pl.item_fx.rpc("shoot")
	alarm(origin, pl.get_multiplayer_authority(), 0.9, 30.0)
	var far := origin + dir * 60.0
	var q := PhysicsRayQueryParameters3D.create(origin, far, 1 | 4)
	q.exclude = [pl.get_rid()]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var end := far
	if not res.is_empty():
		end = res["position"]
		var col := res["collider"] as Node
		if col is Npc:
			(col as Npc).damage(40, dir * 3.0 + Vector3.UP, pl.get_multiplayer_authority(), res["position"])
		elif col is Prop:
			if (col as Prop).kind == "ball":
				(col as Prop).pop()
			else:
				(col as Prop).hit(dir * 8.0 * minf(maxf((col as Prop).mass, 1.0), 3.0))
		else:
			var target: Player = col as Player
			if target == null and col != null and col.get_parent() is PlayerRagdoll:
				target = col.get_parent().get_parent() as Player
			if target != null:
				target.knock.rpc_id(target.get_multiplayer_authority(), dir * 5.0 + Vector3.UP * 1.5)
				maybe_sever_player(target, res["position"], 0.3, dir * 4.0)
	shot_fx.rpc(origin + dir * 0.5, end)

## Cone-shaped swing: shoves toys and knocks players back (no gore, just comedy).
func _melee(pl: Player, origin: Vector3, dir: Vector3, reach: float, power: float) -> void:
	for n in get_tree().get_nodes_in_group("props"):
		var other := n as Prop
		if other == null:
			continue
		var off := other.global_position - origin
		if off.length() < reach and off.normalized().dot(dir) > 0.55:
			if other.kind == "ball" and power < 10.0:   # the knife pops it; a bat just whacks it
				other.pop()
			else:
				other.hit(dir * power * minf(maxf(other.mass, 1.0), 3.0) + Vector3.UP * 1.5)
	for n3 in get_tree().get_nodes_in_group("npcs"):
		var npc3 := n3 as Npc
		if npc3 == null:
			continue
		var off3 := (npc3.global_position + Vector3.UP * 0.9) - origin
		if off3.length() < reach + 0.3 and off3.normalized().dot(dir) > 0.5:
			var hit_pt := npc3.global_position + Vector3.UP * clampf(origin.y - npc3.global_position.y, 0.5, 1.7) + Vector3(randf_range(-0.25, 0.25), 0.0, 0.0)
			npc3.damage(int(maxf(power * 4.0, 45.0)), dir * minf(power * 0.5, 7.0) + Vector3.UP * 1.5, pl.get_multiplayer_authority(), hit_pt)
	for n in get_tree().get_nodes_in_group("players"):
		var other_pl := n as Player
		if other_pl == null or other_pl == pl:
			continue
		var off2 := (other_pl.global_position + Vector3.UP * 1.0) - origin
		if off2.length() < reach and off2.normalized().dot(dir) > 0.55:
			other_pl.knock.rpc_id(other_pl.get_multiplayer_authority(), dir * minf(power * 0.4, 6.0) + Vector3.UP * 2.0)
			var pt := other_pl.global_position + Vector3.UP * clampf(origin.y - other_pl.global_position.y, 0.5, 1.7)
			maybe_sever_player(other_pl, pt, 0.35 if power >= 10.0 else 0.25, dir * 4.0)

func burp_at(pos: Vector3) -> void:
	get_tree().create_timer(0.4).timeout.connect(func(): Sfx.play_at(self, "burp", pos, 3.0))

# ------------------------------------------------------------- chat + computer
signal chat_message(sender: String, text: String)
var chat_log: Array = []          # [[name, text, time], ...]
var _chat_feed: Label
var _overlay_open := false
var _juke: AudioStreamPlayer3D
var _juke_want := ""

func nearest_pc(from: Vector3) -> Node3D:
	for n in get_tree().get_nodes_in_group("retro_pc"):
		var pc := n as Node3D
		if pc != null and from.distance_to(pc.to_global(Vector3(0, 1.0, -0.5))) < 1.7:
			return pc
	return null

## Shared helper: show a full-screen UI, freeze the player's controls until it closes.
func _open_overlay(player: Player, ui: Control, layer_index: int) -> void:
	if _overlay_open:
		ui.queue_free()
		return
	_overlay_open = true
	var l := CanvasLayer.new()
	l.layer = layer_index
	add_child(l)
	l.add_child(ui)
	player.input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.tree_exited.connect(func():
		_overlay_open = false
		l.queue_free()
		if is_instance_valid(player):
			player.input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

func open_pc(player: Player, pc: Node3D) -> void:
	var ui := RetroPC.new()
	ui.setup(self, player, pc)
	_open_overlay(player, ui, 18)

func open_chat(player: Player) -> void:
	var box := ChatBox.new()
	_open_overlay(player, box, 17)

@rpc("any_peer", "call_local", "reliable")
func chat_say(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	text = text.strip_edges().left(140)
	if text.is_empty():
		return
	var nm := str(Net.players.get(id, {}).get("name", "?"))
	if multiplayer.is_server():
		_npcs_hear(text, id)
	chat_log.append([nm, text, Time.get_ticks_msec()])
	if chat_log.size() > 50:
		chat_log.pop_front()
	chat_message.emit(nm, text)
	Sfx.play_ui(self, "chat", -10.0)
	_refresh_chat_feed()

func _refresh_chat_feed() -> void:
	if _chat_feed == null:
		_chat_feed = Label.new()
		_chat_feed.position = Vector2(14, 0)
		_chat_feed.add_theme_color_override("font_outline_color", Color.BLACK)
		_chat_feed.add_theme_constant_override("outline_size", 6)
		_chat_feed.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_chat_feed.anchor_top = 1.0
		_chat_feed.anchor_bottom = 1.0
		_chat_feed.offset_top = -190
		_chat_feed.offset_bottom = -20
		_chat_feed.offset_left = 14
		_chat_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl := CanvasLayer.new()
		add_child(cl)
		cl.add_child(_chat_feed)
	var now := Time.get_ticks_msec()
	var lines := []
	for m in chat_log:
		if now - int(m[2]) < 12000:
			lines.append("%s: %s" % [m[0], m[1]])
	_chat_feed.text = "\n".join(lines.slice(maxi(0, lines.size() - 7)))
	if not lines.is_empty():
		get_tree().create_timer(12.2).timeout.connect(_refresh_chat_feed)

## The bedroom computer's jukebox: everybody hears the same tune coming from the PC.
@rpc("any_peer", "call_local", "reliable")
func jukebox(track: String, at: Vector3) -> void:
	if _juke == null:
		_juke = AudioStreamPlayer3D.new()
		_juke.unit_size = 10.0
		_juke.max_distance = 60.0
		_juke.volume_db = 4.0
		add_child(_juke)
	if track.is_empty() or not Sfx.TUNES.has(track):
		_juke_want = ""
		_juke.stop()
		return
	_juke.global_position = at
	_juke_want = track
	_juke.stop()
	Sfx.tune_async(track, func(st: AudioStreamWAV):
		if _juke != null and is_instance_valid(_juke) and _juke_want == track:
			_juke.stream = st
			_juke.play())

func jukebox_playing() -> bool:
	return _juke != null and _juke.playing

## Full controls list, shown in the pause menu.
func controls_text() -> String:
	var text := "WASD move   Shift sprint   Space jump / swim up   C swim down   R flop (ragdoll)\n"
	text += "Hold RMB grab   LMB throw / shove   scroll: hold distance   walk into people to push them\n"
	text += "Tab spawn menu (guns, food, props, people)   1-8 quick spawn   RMB pick up / put down   LMB use   G throw\n"
	text += "F: computer / shop counter / drive the toy car / push or sit in a cart / lift a knocked-out player / ride a rocket\n"
	text += "Hold Q: weapon wheel (pick up more things and switch between them)   Melee: hold LMB to wind up, let go to swing\n"
	text += "K character   V camera   U I'm stuck   T chat   Esc pause menu\n"
	text += "TOWN: east along Main St. F talks to people, T chat (they answer: hi, dance, follow me, sorry...). F at a car gets in (or hijacks it). In a car: LMB horn, police RMB lights.\n"
	text += "JOBS: the job board outside WOBBLY JOBS in town: deliveries, pizza runs, cars for the Chop Shop, trouble-makers.\n"
	if Net.is_campaign():
		text += "CAMPAIGN: no spawning and no free money - do jobs to earn cash, spend it at the CORNER SHOP.\n"
	else:
		text += "You earn $%d every %d s: spend it at the CORNER SHOP across the street (out the front gate).\n" % [INCOME, int(INCOME_EVERY)]
	text += "Rumour: there is an RPG on the roof..."
	if multiplayer.is_server():
		var ips: Array[String] = []
		for a in IP.get_local_addresses():
			if "." in a and not a.begins_with("127.") and not a.begins_with("169.254."):
				ips.append(a)
		text += "\nHosting on port %d. Friends on your network/VPN join: %s" % [Net.PORT, ", ".join(ips)]
	return text

# ------------------------------------------------------------------ money + shop
const START_MONEY := 100
const CAMPAIGN_START_MONEY := 40
const INCOME := 10
const INCOME_EVERY := 30.0
## What things cost at the Corner Shop (the RPG is not for sale: it lives on the roof).
const PRICES := {
	"soda": 4, "beer": 6, "burger": 12, "pizza": 10, "cig": 8,
	"ball": 5, "duck": 5, "pin": 3, "melon": 8, "crate": 10, "chair": 15, "barrel": 20, "bomb": 60, "coupe": 150, "cart": 25,
	"console": 70, "knife": 40, "bat": 35, "pistol": 90, "gloves": 30,
	"sedan": 400, "truck": 550, "sports": 1200,
}
const SHOP_SECTIONS := {
	"Snacks & drinks": ["soda", "beer", "burger", "pizza", "cig"],
	"Toys": ["ball", "duck", "pin", "melon", "crate", "chair", "barrel", "bomb", "coupe", "cart"],
	"Gear": ["console", "knife", "bat", "pistol", "gloves"],
	"Cars (parked on the street)": ["sedan", "truck", "sports"],
}
signal money_changed(amount: int)
var money := {}          # server only: peer id -> dollars
var my_money := 0        # this machine's balance, as told by the server
var _income_t := 0.0
var _money_label: Label

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_town_tick(delta)
	if Net.is_campaign():
		return   # no free money in the campaign: work for it
	_income_t += delta
	if _income_t >= INCOME_EVERY:
		_income_t = 0.0
		for id in money.keys():
			money[id] = int(money[id]) + INCOME
			_send_money(int(id))

func _send_money(id: int) -> void:
	var amount := int(money.get(id, 0))
	if id == multiplayer.get_unique_id():
		_set_money(amount)
	else:
		_set_money.rpc_id(id, amount)

## Server: pay (or charge) a player.
func add_money(id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	money[id] = maxi(0, int(money.get(id, 0)) + amount)
	_send_money(id)

@rpc("authority", "call_remote", "reliable")
func _set_money(amount: int) -> void:
	if amount < my_money:
		Sfx.play_ui(self, "ding", -2.0)   # cha-ching
	my_money = amount
	if _money_label != null:
		_money_label.text = "$%d" % amount
	money_changed.emit(amount)

## Standing at the town's job board?
func near_job_board(from: Vector3) -> bool:
	return town != null and not custom_map and from.distance_to(town.job_board) < 2.8

## The shop counter, if `from` is close enough to buy (only on the default map).
func near_shop(from: Vector3) -> bool:
	return house != null and not custom_map and from.distance_to(house.shop_counter) < 2.6

func open_jobs(player: Player) -> void:
	var ui := JobBoard.new()
	ui.setup(self)
	_open_overlay(player, ui, 16)

func open_shop(player: Player) -> void:
	var ui := ShopMenu.new()
	ui.setup(self)
	_open_overlay(player, ui, 16)

## Server: take the money and put the item on the end of the counter.
@rpc("any_peer", "call_local", "reliable")
func buy(kind: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not PRICES.has(kind) or not Prop.is_valid_kind(kind) or house == null:
		return
	var pl := get_node_or_null(str(id)) as Player
	if pl == null or pl.global_position.distance_to(house.shop_counter) > 6.0:
		return
	var price := int(PRICES[kind])
	if int(money.get(id, 0)) < price:
		return
	money[id] = int(money[id]) - price
	_send_money(id)
	if Prop.is_car(kind):
		var c := spawn_car(kind, Vector3(randf_range(-20.0, 20.0), 0.0, 55.1), -PI * 0.5)   # kerbside, facing town
		if c != null:
			c.shooter = id
		_toast_to(id, "Your %s is parked on the street outside. Enjoy!" % Prop.CARS[kind]["label"])
		return
	var drop := house.shop_pickup + Vector3(randf_range(-0.4, 0.4), 0.35, randf_range(-0.15, 0.15))
	if kind in ["coupe", "barrel", "crate", "chair", "cart"]:
		drop = Vector3(randf_range(-2.0, 2.0), 0.8, 60.0)   # big things are left outside the door
	_spawn_prop(kind, drop, Vector3.ZERO, id)

# ------------------------------------------------------------------ gore (server)
## Roughly where each limb is on a standing person (their local space, facing -Z, left = -X).
const LIMB_OFFSET := {"head": Vector3(0, 1.65, 0), "arm_l": Vector3(-0.32, 1.25, 0), "arm_r": Vector3(0.32, 1.25, 0),
	"leg_l": Vector3(-0.12, 0.5, 0), "leg_r": Vector3(0.12, 0.5, 0)}

## Knock a limb off a person or a player, and drop it in the world (or straight into `give_to`'s hand).
## Only when the HOST has "Blood & dismemberment" on. Returns false if nothing came off.
func sever_limb(target: Node3D, limb: String, push: Vector3, give_to: Player = null) -> bool:
	if not multiplayer.is_server() or not Settings.gore or not Npc.LIMB_BITS.has(limb):
		return false
	var bit := int(Npc.LIMB_BITS[limb])
	var tint := ""
	if target is Npc:
		var n := target as Npc
		if n.severed & bit:
			return false
		n.severed |= bit
		n._regrow_t = 0.0
		tint = n.tint_string()
	elif target is Player:
		var p := target as Player
		if p.severed & bit:
			return false
		p.severed |= bit   # the owner sets it too; this stops a second cut before their update arrives
		p.lose_limb.rpc_id(p.get_multiplayer_authority(), bit)
		tint = p.tint_string()
	else:
		return false
	var kind := "limb_head" if limb == "head" else ("limb_arm" if limb.begins_with("arm") else "limb_leg")
	if give_to != null and give_to.equipped == "":
		give_to.equip.rpc_id(give_to.get_multiplayer_authority(), kind, tint)
	else:
		var at := target.global_position + Basis(Vector3.UP, target.global_rotation.y) * (LIMB_OFFSET[limb] as Vector3)
		_spawn_prop(kind, at, push.limit_length(8.0) + Vector3.UP * 2.5, 0, tint)
	return true

## A player got hit hard: sometimes the limb at `at` comes off.
func maybe_sever_player(pl: Player, at: Vector3, chance: float, push: Vector3) -> void:
	if not Settings.gore or randf() > chance:
		return
	var limb := _limb_on(pl, at)
	if limb != "":
		sever_limb(pl, limb, push)
		gore_fx_at.rpc(at, push)

func _limb_on(body: Node3D, p: Vector3) -> String:
	var lp := Basis(Vector3.UP, body.global_rotation.y).inverse() * (p - body.global_position)
	if lp.y > 1.45:
		return "head"
	if lp.y > 0.95:
		if absf(lp.x) < 0.17:
			return ""
		return "arm_l" if lp.x < 0.0 else "arm_r"
	return "leg_l" if lp.x < 0.0 else "leg_r"

## Blood spray for everyone who has gore turned on.
@rpc("authority", "call_local", "unreliable")
func gore_fx_at(at: Vector3, push: Vector3) -> void:
	if Settings.gore:
		Gore.burst(self, at, push + Vector3.UP * 1.5, 40)
		Gore.splat(self, Vector3(at.x, at.y - 1.0, at.z), 0.3)

## Rubber gloves: LMB on a person (alive or not) or another player tears off the limb you are looking at,
## and you are left holding it.
@rpc("any_peer", "call_local", "reliable")
func rip(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var pl := get_node_or_null(str(id)) as Player
	if pl == null or not pl.gloves_on or not origin.is_finite() or not dir.is_finite():
		return
	if not Settings.gore:
		_toast_to(id, "The host has Blood & dismemberment turned off")
		return
	dir = dir.normalized()
	var best: Node3D = null
	var best_limb := ""
	var best_d := 0.45
	var cands: Array = get_tree().get_nodes_in_group("npcs")
	for n in get_tree().get_nodes_in_group("players"):
		if n != pl:
			cands.append(n)
	for c in cands:
		var body := c as Node3D
		if body == null or body.global_position.distance_to(origin) > 3.2:
			continue
		var mask := int(body.get("severed"))
		var yaw_b := Basis(Vector3.UP, body.global_rotation.y)
		var lying: bool = body is Npc and (body as Npc).dead
		for limb in LIMB_OFFSET:
			if mask & int(Npc.LIMB_BITS[limb]):
				continue
			var off: Vector3 = LIMB_OFFSET[limb]
			if lying:
				off = Vector3(off.x, 0.25, off.y * 0.9)   # rough: the body lies flat
			var pt := body.global_position + yaw_b * off
			var rel := pt - origin
			var along := rel.dot(dir)
			if along < 0.0 or along > 2.6:
				continue
			var miss := (rel - dir * along).length()
			if miss < best_d:
				best_d = miss
				best = body
				best_limb = limb
	if best == null:
		return
	if sever_limb(best, best_limb, -dir * 3.0, pl):
		gore_fx_at.rpc(best.global_position + Basis(Vector3.UP, best.global_rotation.y) * (LIMB_OFFSET[best_limb] as Vector3), -dir * 2.0)
		Sfx.play_at(self, "stab", best.global_position + Vector3.UP, 3.0)
		if best is Npc:
			(best as Npc).damage(40 if best_limb != "head" else 999, dir * 2.0, id, Vector3.ZERO, false, false)
		elif best is Player:
			(best as Player).knock.rpc_id(best.get_multiplayer_authority(), -dir * 2.0 + Vector3.UP * 2.0)

# ------------------------------------------------------------------ toasts
var _toast_label: Label

func _toast_to(id: int, text: String) -> void:
	if id == multiplayer.get_unique_id():
		toast(text)
	else:
		toast.rpc_id(id, text)

## A short message in the middle of the screen.
@rpc("authority", "call_remote", "reliable")
func toast(text: String) -> void:
	if _toast_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 12
		add_child(layer)
		_toast_label = Label.new()
		_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_toast_label.offset_top = 90
		_toast_label.offset_left = -400
		_toast_label.offset_right = 400
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.add_theme_font_size_override("font_size", 24)
		_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_toast_label.add_theme_constant_override("outline_size", 8)
		layer.add_child(_toast_label)
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	var tw := _toast_label.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.6)

# ------------------------------------------------------------------ physical melee
## A melee swing: the weapon really sweeps an arc in front of the swinger, a moment after the click,
## and whatever it passes through gets smacked ALONG the swing (so things fly sideways, spin, and
## people get bowled over the way you swung). Holding the button longer winds up a bigger hit.
@rpc("any_peer", "call_local", "reliable")
func melee_swing(kind: String, origin: Vector3, dir: Vector3, charge: float, side: float) -> void:
	if not multiplayer.is_server() or not Player.MELEE.has(kind):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var pl := get_node_or_null(str(sender)) as Player
	if pl == null or pl.equipped != kind or not origin.is_finite() or not dir.is_finite() or dir.length() < 0.5:
		return
	if origin.distance_to(pl.global_position) > 3.0:
		return
	var now := Time.get_ticks_msec()
	if now < int(_next_use.get(sender, 0)):
		return
	_next_use[sender] = now + int(float(Prop.ITEMS[kind]["cd"]) * 800.0)
	pl.item_fx.rpc("swing")
	get_tree().create_timer(0.09).timeout.connect(_melee_sweep.bind(pl, kind, origin, dir.normalized(), clampf(charge, 0.0, 1.0), signf(side) if side != 0.0 else 1.0))

func _melee_sweep(pl: Player, kind: String, origin: Vector3, dir: Vector3, charge: float, side: float) -> void:
	if not is_instance_valid(pl):
		return
	var spec: Array = Player.MELEE[kind]
	var reach: float = spec[0]
	var power: float = float(spec[1]) * (1.0 + charge * 1.6)
	var arc := deg_to_rad(float(spec[2]))
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.42
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 | 4
	q.exclude = [pl.get_rid()]
	var hit := {}
	var total := 0.0
	var steps := 8
	var prev_tip := Vector3.ZERO
	for i in steps + 1:
		var f := float(i) / float(steps)
		var ang := lerpf(arc * 0.5, -arc * 0.5, f) * side      # sweeps across the view
		var tip_dir := (Basis(Vector3.UP, ang) * dir + Vector3.DOWN * 0.15 * sin(f * PI)).normalized()
		var tip := origin + tip_dir * reach * 0.8
		if i == 0:
			prev_tip = tip
			continue
		var tangent := (tip - prev_tip).normalized()
		prev_tip = tip
		q.transform = Transform3D(Basis(), tip)
		for r in space.intersect_shape(q, 12):
			var col := r["collider"] as Node
			if col == null:
				continue
			var target: Node = col
			if col.get_parent() is PlayerRagdoll:
				target = col.get_parent().get_parent()   # a ragdoll limb: the player it belongs to
			if target == pl or hit.has(target.get_instance_id()):
				continue
			hit[target.get_instance_id()] = true
			var swing_v := tangent * 0.75 + dir * 0.45          # sideways along the swing, and away from me
			if target is Prop:
				var prop := target as Prop
				if prop.kind == "ball" and kind == "knife":
					prop.pop()
				else:
					var imp := swing_v * power * minf(maxf(prop.mass, 1.0), 4.0) + Vector3.UP * power * 0.3
					if prop.in_cart != null:
						prop.leave_cart()
					prop.sleeping = false
					prop.apply_impulse(imp.limit_length(80.0), (tip - prop.global_position) * 0.6)   # off-centre: it spins
				total += 1.0
			elif target is Npc:
				var npc := target as Npc
				npc.damage(int(maxf(power * 3.2, 25.0)), swing_v * minf(power * 0.6, 10.0) + Vector3.UP * (2.0 + charge * 3.0), pl.get_multiplayer_authority(), tip)
				total += 2.0
			elif target is Player:
				var other := target as Player
				var fling := swing_v * minf(power * 0.5, 9.5) + Vector3.UP * (2.5 + charge * 3.5)
				other.knock.rpc_id(other.get_multiplayer_authority(), fling)
				maybe_sever_player(other, tip, 0.15 + 0.25 * charge, fling)
				total += 2.0
	if total > 0.0:
		pl.melee_hit.rpc_id(pl.get_multiplayer_authority(), power * minf(total, 3.0) * 0.5)
		Sfx.play_at(self, "thud", origin + dir * reach * 0.8, clampf(power * 0.15, 0.0, 6.0))

## Take something off a shop shelf: pay for it and it goes straight into your hand.
@rpc("any_peer", "call_local", "reliable")
func take_from_shelf(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server() or house == null or custom_map:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var pl := get_node_or_null(str(id)) as Player
	if pl == null or not origin.is_finite() or not dir.is_finite() or origin.distance_to(pl.global_position) > 3.0:
		return
	var kind := house.shelf_kind_at(origin, dir.normalized())
	if kind == "" or not PRICES.has(kind):
		return
	var price := int(PRICES[kind])
	if int(money.get(id, 0)) < price:
		_toast_to(id, "Not enough money for that ($%d)" % price)
		return
	money[id] = int(money[id]) - price
	_send_money(id)
	pl.equip.rpc_id(id, kind, "")

# ------------------------------------------------------------------ the town (server)
const TOWN_PEOPLE := 22        # townspeople walking about
const TOWN_TRAFFIC := 7        # cars driving round with a townsperson at the wheel
const TOWN_CAR_CAP := 24       # cars in the world at most (abandoned ones far away get towed)
var _town_t := 0.0
var _aim_t := 0.0

## Fill the town with people, traffic and parked cars. `start` = also park cars in the lot.
func _populate_town(start := false) -> void:
	if not multiplayer.is_server() or town == null or custom_map:
		return
	if start:
		var kinds := ["sedan", "sedan", "sports", "truck", "taxi", "sedan", "truck", "sedan"]
		var spots := town.parking.duplicate()
		spots.shuffle()
		var n := 0
		for sp in spots:
			var k: String = str(sp.get("kind", kinds[n % kinds.size()]))
			if sp.has("kind") or n < 7:
				var pc := spawn_car(k, sp["pos"], float(sp["yaw"]))
				if pc != null:
					pc.has_alarm = true
				n += 1
	for i in 6:
		_town_tick(10.0)   # a few cars and a dozen people straight away, the rest arrive over the next minute

## Keep the town alive: top up people and traffic (out of sight when possible), tow abandoned cars,
## and make people react to guns pointed at them.
func _town_tick(delta: float) -> void:
	if town == null or custom_map:
		return
	_aim_t -= delta
	if _aim_t <= 0.0:
		_aim_t = 0.35
		_check_aims()
	_town_t -= delta
	if _town_t > 0.0:
		return
	_town_t = 4.0
	var people := 0
	for n in get_tree().get_nodes_in_group("residents"):
		if not (n as Npc).dead:
			people += 1
	for extra in clampi(TOWN_PEOPLE - people, 0, 2):
		for tries in 6:
			var spot := town.random_walk_spot()
			if _far_from_players(spot["pos"], 30.0) or tries == 5:
				var npc := spawn_npc(spot["pos"] + Vector3.UP * 0.1, randi() % 100000, 0, true)
				if npc != null:
					var wp: Dictionary = town.walk_paths[int(spot["path"])]
					npc.path = wp["pts"]
					npc.path_loop = bool(wp["loop"])
					npc._wp = int(spot["wp"])
				break
	var cars: Array = []
	var driving := 0
	for n2 in get_tree().get_nodes_in_group("props"):
		var c := n2 as Prop
		if c != null and Prop.is_car(c.kind) and not c.exploded:
			cars.append(c)
			if c.driver_seed != 0:
				driving += 1
	if driving < TOWN_TRAFFIC and cars.size() < TOWN_CAR_CAP:
		for tries2 in 6:
			var ls := town.random_lane_spot()
			if _far_from_players(ls["pos"], 35.0) and _lane_clear(ls["pos"]):
				var kinds2 := ["sedan", "sedan", "taxi", "sedan", "truck", "sports", "taxi", "police"]
				spawn_car(kinds2[randi() % kinds2.size()], ls["pos"], float(ls["yaw"]), 1 + randi() % 100000, ls["route"])
				break
	elif cars.size() >= TOWN_CAR_CAP:
		# tow the abandoned car furthest from everybody
		var worst: Prop = null
		var worst_d := 60.0
		for c2 in cars:
			var car := c2 as Prop
			if car.rider != 0 or car.driver_seed != 0 or car.passenger != 0:
				continue
			var d := _nearest_player_dist(car.global_position)
			if d > worst_d:
				worst_d = d
				worst = car
		if worst != null:
			worst.queue_free()

func _far_from_players(p: Vector3, dist: float) -> bool:
	return _nearest_player_dist(p) > dist

func _nearest_player_dist(p: Vector3) -> float:
	var best := 1e9
	for n in get_tree().get_nodes_in_group("players"):
		best = minf(best, (n as Node3D).global_position.distance_to(p))
	return best

func _lane_clear(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("props"):
		if (n as Node3D).global_position.distance_to(p) < 7.0:
			return false
	return true

## Server: something violent happened at `at` (by = the player responsible, 0 = nobody):
## people within `radius` scream and run, or (the brave ones) come for whoever did it.
func alarm(at: Vector3, by: int, severity: float, radius: float, except: Node = null) -> void:
	if not multiplayer.is_server():
		return
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as Npc
		if npc == null or npc == except or npc.dead:
			continue
		if npc.global_position.distance_to(at) < radius:
			npc.witness(at, by, severity)

## Server: anybody pointing a gun at a person makes their hands go up.
func _check_aims() -> void:
	var cos_lim := cos(deg_to_rad(9.0))
	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl == null or pl.ragdolled or not (pl.equipped == "pistol" or pl.equipped == "rpg"):
			continue
		var eye := pl.global_position + Vector3.UP * 1.55
		var dir := (Basis(Vector3.UP, pl.yaw) * Basis(Vector3.RIGHT, pl.pitch)) * Vector3.FORWARD
		for m in get_tree().get_nodes_in_group("npcs"):
			var npc := m as Npc
			if npc == null or npc.dead:
				continue
			var to := npc.global_position + Vector3.UP * 1.2 - eye
			var d := to.length()
			if d < 22.0 and d > 0.5 and to.normalized().dot(dir) > cos_lim:
				npc.aimed_at(pl.get_multiplayer_authority())

## Server: the nearest people to a chatting player hear what they said.
func _npcs_hear(text: String, id: int) -> void:
	var pl := get_node_or_null(str(id)) as Node3D
	if pl == null:
		return
	var near: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as Npc
		if npc == null or npc.dead:
			continue
		var d := npc.global_position.distance_to(pl.global_position)
		if d < 9.0:
			near.append([d, npc])
	near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(2, near.size()):
		var who: Npc = near[i][1]
		get_tree().create_timer(0.4 + i * 0.7).timeout.connect(func():
			if is_instance_valid(who):
				who.hear(text, id))

## Server: the townsperson driving `car` got dragged out by player `by`.
func npc_driver_ejected(car: Prop, look_seed: int, by: int) -> void:
	var size: Vector3 = Prop.CARS[car.kind]["size"]
	var at := car.global_position + car.global_basis * Vector3(-size.x * 0.5 - 0.9, 0.0, 0.3)
	at.y = car.global_position.y - size.y * 0.5 + 0.1
	var npc := spawn_npc(at, look_seed, 0, true, false, car.global_rotation.y)
	if npc == null:
		return
	npc.grudge[by] = 1.0
	if town != null and not town.walk_paths.is_empty():
		var spot := town.random_walk_spot()
		var wp: Dictionary = town.walk_paths[int(spot["path"])]
		npc.path = wp["pts"]
		npc.path_loop = bool(wp["loop"])
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	rng.randi()
	var will_fight := rng.randf() < 0.22
	var pl := get_node_or_null(str(by)) as Node3D
	get_tree().create_timer(0.3).timeout.connect(func():
		if not is_instance_valid(npc):
			return
		if will_fight:
			npc.hostile = by
			npc._say_line(["HEY! That's MY car!", "Get out of my car, you maniac!", "Oh no you DON'T!"][randi() % 3], true)
		else:
			npc._flee_t = 6.0
			npc._flee_from = pl.global_position if is_instance_valid(pl) else car.global_position
			npc._say_line(["MY CAR!", "Take it! Take it!", "I just had it washed!", "Help! Carjacker!"][randi() % 4], true))
	alarm(car.global_position, by, 0.7, 18.0, npc)
