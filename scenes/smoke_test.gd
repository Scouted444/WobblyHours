class_name SmokeTest
extends Node
## Automatic test run, used by the build server: `godot --headless --path . -- --smoke`
## Hosts a game, spawns everything, drives and hijacks cars, chats with people, does every job,
## switches to campaign rules, then quits. Any script error shows up in the log and fails the build.

var main: Node
var world: GameWorld
var me: Player

static func run(m: Node) -> void:
	var t := SmokeTest.new()
	t.main = m
	m.add_child.call_deferred(t)

func _ready() -> void:
	_go()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _log(msg: String) -> void:
	print("[smoke] ", msg)

func _go() -> void:
	await _wait(0.5)
	_log("hosting")
	main.call("_on_host")
	for i in 100:
		await _wait(0.1)
		world = main.get("world") as GameWorld
		if world != null and world.map_ready:
			me = world.get_node_or_null("1") as Player
			if me != null:
				break
	if me == null:
		push_error("SMOKE: no player after hosting")
		get_tree().quit(1)
		return
	_log("town: %s, addresses %d, paths %d" % [world.town != null, world.town.addresses.size() if world.town else 0, world.town.walk_paths.size() if world.town else 0])
	await _wait(2.0)
	_check_layout()
	_report_town()
	await _seat_report()
	await _ragdoll_test()
	await _crash_test()

	# --- spawn one of everything next to me
	_log("spawning")
	var at := me.global_position + Vector3(2, 1, 2)
	for cat in Prop.CATEGORIES:
		for k in Prop.CATEGORIES[cat]:
			world.request_spawn(String(k), at)
			await _wait(0.05)
	await _wait(2.0)

	# --- town life
	_log("people %d, props %d" % [get_tree().get_nodes_in_group("npcs").size(), get_tree().get_nodes_in_group("props").size()])
	_tp(Vector3(120, 0.5, 48))
	await _wait(3.0)
	world.chat_say("hello everyone")
	await _wait(0.3)
	world.chat_say("dance for me")
	await _wait(0.3)
	world.chat_say("you idiot")
	await _wait(0.3)
	world.chat_say("sorry! follow me")
	await _wait(0.3)
	world.chat_say("any jobs? where is the pizza?")
	await _wait(2.0)
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as Npc
		if npc != null and not npc.dead and npc.global_position.distance_to(me.global_position) < 40.0:
			_tp(npc.global_position + Vector3(1.5, 0.3, 0))
			await _wait(0.2)
			npc.talk()
			npc.aimed_at(1)
			npc.witness(me.global_position, 1, 1.0)
			npc.hear("hands up", 1)
			break
	me.equip("pistol")
	await _wait(1.0)
	world.use_item("pistol", me.global_position + Vector3.UP * 1.5, -me.global_basis.z)
	await _wait(0.5)
	world.explode_at(me.global_position + Vector3(8, 0, 0), 5.0, 10.0)
	await _wait(1.5)

	# --- cars: get in, drive, honk, lights, get out; then hijack a moving one
	_log("cars")
	var car: Prop = null
	for n2 in get_tree().get_nodes_in_group("props"):
		var p := n2 as Prop
		if p != null and p.kind == "police" and p.rider == 0:
			car = p
			break
	if car != null:
		me.velocity = Vector3.ZERO
		_tp(car.global_position + Vector3(2.5, 0, 0))
		await _wait(0.3)
		car.ride()
		await _wait(0.5)
		car.drive(1.0, 0.3, false)
		car.horn()
		car.toggle_siren()
		await _wait(1.5)
		me.call("_dismount", Vector3.ZERO)
		await _wait(0.5)
	var ai: Prop = null
	for n3 in get_tree().get_nodes_in_group("props"):
		var p2 := n3 as Prop
		if p2 != null and p2.driver_seed != 0:
			ai = p2
			break
	if ai != null:
		_log("hijacking a %s" % ai.kind)
		_tp(ai.global_position + Vector3(2.5, 0, 0))
		await _wait(0.1)
		ai.ride()
		await _wait(1.5)
		me.call("_dismount", Vector3.ZERO)
		await _wait(0.5)
	else:
		push_warning("SMOKE: no AI traffic found")

	# --- jobs
	var town := world.town
	var ms := world.missions
	for kind in ["delivery", "pizza", "chop", "trouble"]:
		_log("job " + kind)
		_tp(town.job_board + Vector3(0, 0.5, 1.5))
		await _wait(0.4)
		ms.accept(kind)
		await _wait(0.6)
		var job: Dictionary = ms.active.get(1, {})
		if job.is_empty():
			push_error("SMOKE: job %s did not start" % kind)
			continue
		match kind:
			"delivery":
				_tp(job["pos"] + Vector3(0, 0.5, 0))
				await _wait(0.8)
			"pizza":
				_tp(town.pizza_counter + Vector3(0, 0.5, 0))
				await _wait(0.8)
				job = ms.active.get(1, {})
				if not job.is_empty():
					_tp(job["pos"] + Vector3(0, 0.5, 0))
					await _wait(0.8)
			"chop":
				var target := world.get_node_or_null(str(job.get("node", ""))) as Prop
				if target != null:
					target.ai_route = []        # pull over first (a moving car drives off before we reach it)
					target.linear_velocity = Vector3.ZERO
					await _wait(0.5)
					_tp(target.global_position + Vector3(2.5, 0, 0))
					await _wait(0.3)
					target.ride()
					await _wait(0.6)
					_log("chop: riding '%s', car rider %d" % [me.ride_name, target.rider])
					target.global_position = town.chop_shop + Vector3(0, 1.0, 0)
					await _wait(1.2)
			"trouble":
				var npc2 := world.get_node_or_null(str(job.get("node", ""))) as Npc
				if npc2 != null:
					npc2.damage(999, Vector3.ZERO, 1)
				await _wait(0.8)
		_log("job %s -> still active: %s, money %d" % [kind, ms.active.has(1), int(world.money.get(1, 0))])
		if ms.active.has(1):
			ms.quit()
			await _wait(0.3)

	# --- UI screens
	_log("ui")
	world.open_jobs(me)
	await _wait(0.3)
	world.open_shop(me)
	await _wait(0.3)
	for c in world.get_children():
		if c is CanvasLayer:
			for u in c.get_children():
				if u is JobBoard or u is ShopMenu:
					u.queue_free()
	await _wait(0.3)

	# --- campaign rules
	_log("campaign")
	Net.map["mode"] = "campaign"
	world.request_spawn("crate", me.global_position + Vector3(1, 1, 0))
	world.open_menu(me)
	await _wait(0.5)
	Net.map["mode"] = "sandbox"

	# --- let the town run for a while, then tidy up
	_tp(Vector3(150, 0.5, 60))
	await _wait(8.0)
	_report_town()
	world.host_clear("all")
	await _wait(2.0)
	_log("people %d, props %d" % [get_tree().get_nodes_in_group("npcs").size(), get_tree().get_nodes_in_group("props").size()])
	print("SMOKE TEST DONE")
	get_tree().quit(0)

func _tp(p: Vector3) -> void:
	if is_instance_valid(me):
		if me.ragdolled:
			me.set_ragdoll(false)
		me.global_position = p
		me.velocity = Vector3.ZERO

## Layout check: walk the pavement paths and the traffic lanes and report anything solid in the way.
func _check_layout() -> void:
	var space := world.get_world_3d().direct_space_state
	var town := world.town
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	q.shape = sph
	q.collision_mask = 1
	var blocked := 0
	var total := 0
	for wp in town.walk_paths:
		var pts: Array = wp["pts"]
		var n := pts.size() if bool(wp["loop"]) else pts.size() - 1
		for i in n:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % pts.size()]
			var steps := int(a.distance_to(b))
			for k in steps:
				var p := a.lerp(b, float(k) / maxf(1.0, float(steps))) + Vector3.UP * 0.9
				q.transform = Transform3D(Basis(), p)
				total += 1
				var hits := space.intersect_shape(q, 4)
				for h in hits:
					var col := h["collider"] as Node
					if col is StaticBody3D:
						blocked += 1
						if blocked <= 12:
							_log("pavement blocked at %s by %s" % [p.round(), col.name])
						break
	_log("pavement samples %d, blocked %d" % [total, blocked])
	var lb := 0
	var lt := 0
	sph.radius = 0.9
	for a_i in town.road_links:
		for b_i in town.road_links[a_i]:
			var a2: Vector3 = town.road_nodes[int(a_i)]
			var b2: Vector3 = town.road_nodes[int(b_i)]
			var d := (b2 - a2).normalized()
			var right := Vector3(-d.z, 0.0, d.x)
			var steps2 := int(a2.distance_to(b2) / 2.0)
			for k2 in steps2:
				var p2 := a2.lerp(b2, float(k2) / maxf(1.0, float(steps2))) + right * Town.LANE + Vector3.UP * 1.2
				q.transform = Transform3D(Basis(), p2)
				lt += 1
				for h2 in space.intersect_shape(q, 4):
					if (h2["collider"] as Node) is StaticBody3D:
						lb += 1
						if lb <= 12:
							_log("lane blocked at %s by %s" % [p2.round(), (h2["collider"] as Node).name])
						break
	_log("lane samples %d, blocked %d" % [lt, lb])

func _report_town() -> void:
	var walking := 0
	var res := 0
	for n in get_tree().get_nodes_in_group("residents"):
		var npc := n as Npc
		if npc != null and not npc.dead:
			res += 1
			if npc.move_speed > 0.5:
				walking += 1
	var moving := 0
	var ai := 0
	for n2 in get_tree().get_nodes_in_group("props"):
		var p := n2 as Prop
		if p != null and p.driver_seed != 0:
			ai += 1
			if p.linear_velocity.length() > 2.0:
				moving += 1
	_log("townspeople %d (%d walking), traffic %d (%d moving)" % [res, walking, ai, moving])


## Car seats: where a seated driver's head, hands, knees and feet end up, in car space.
func _seat_report() -> void:
	var cars := {}
	var i := 0
	for kind in Prop.CARS:
		var c := world.spawn_car(String(kind), Vector3(110.0 + i * 9.0, 0.0, -7.0), PI * 0.5, 4242 + i)
		cars[kind] = c
		i += 1
	await _wait(1.5)
	for kind2 in cars:
		var c2: Prop = cars[kind2]
		var nb := c2._driver_body
		if nb == null or nb._sk == null:
			_log("seat %s: no driver body" % kind2)
			continue
		var inv := c2.global_transform.affine_inverse()
		var parts := []
		for bn in ["Head", "Thigh.L", "Leg.L", "Foot.L", "Foot.R", "Fingers.L", "Fingers.R"]:
			var b := int(nb._bone.get(bn, -1))
			if b < 0:
				continue
			var wp: Vector3 = (nb._sk.global_transform * nb._sk.get_bone_global_pose(b)).origin
			var lp := inv * wp
			parts.append("%s(%.2f %.2f %.2f)" % [bn, lp.x, lp.y, lp.z])
		_log("seat %s: %s" % [kind2, " ".join(parts)])
		c2.queue_free()
	await _wait(0.3)

func _ragdoll_test() -> void:
	var npc: Npc = null
	for n in get_tree().get_nodes_in_group("residents"):
		if not (n as Npc).dead:
			npc = n
			break
	if npc == null:
		_log("ragdoll: nobody to test on")
		return
	npc.damage(15, Vector3(8, 3, 0), 0)
	await _wait(0.5)
	_log("ragdoll: knocked=%s pose=%d" % [npc._ragdoll != null and npc._ragdoll.active, npc.rag_pose.size()])
	await _wait(5.0)
	if is_instance_valid(npc):
		_log("ragdoll: got up=%s hp=%d" % [npc.rag_pose.is_empty(), npc.hp])
		npc.damage(999, Vector3(3, 2, 0), 0)
		await _wait(4.0)
		if is_instance_valid(npc):
			_log("ragdoll: dead=%s frozen=%s" % [npc.dead, npc._ragdoll != null and npc._ragdoll.active and npc._ragdoll.torso().freeze])


func _crash_test() -> void:
	var a := world.spawn_car("sedan", Vector3(112.0, 0.0, -7.0), -PI * 0.5)
	var b := world.spawn_car("truck", Vector3(128.0, 0.0, -7.0), PI * 0.5)
	b.has_alarm = true
	await _wait(0.6)
	a.linear_velocity = Vector3(24.0, 0.0, 0.0)
	await _wait(1.5)
	_log("crash: sedan hp %d, truck hp %d, truck alarm %s" % [a.car_hp, b.car_hp, b.alarm_on])
	a.car_damage(500)
	await _wait(9.5)
	if is_instance_valid(a):
		_log("crash: burnt out = %s" % a.wrecked)
	if is_instance_valid(a):
		a.queue_free()
	if is_instance_valid(b):
		b.queue_free()
