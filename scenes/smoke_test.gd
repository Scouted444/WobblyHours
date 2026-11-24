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
					_tp(target.global_position + Vector3(2.5, 0, 0))
					await _wait(0.3)
					target.ride()
					await _wait(0.6)
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
	world.host_clear("all")
	await _wait(2.0)
	_log("people %d, props %d" % [get_tree().get_nodes_in_group("npcs").size(), get_tree().get_nodes_in_group("props").size()])
	print("SMOKE TEST DONE")
	get_tree().quit(0)

func _tp(p: Vector3) -> void:
	if is_instance_valid(me):
		me.global_position = p
		me.velocity = Vector3.ZERO
