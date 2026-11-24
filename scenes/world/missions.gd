class_name Missions
extends Node
## Jobs from the job board outside Wobbly Jobs (Main St, in town): parcel deliveries, pizza runs,
## "collecting" cars for the Chop Shop and sorting out trouble-makers. They pay cash, which is the
## only way to earn money in Campaign mode (Sandbox players can do them too).
##
## The server hands jobs out, checks them a few times a second and pays. Each player only sees their
## own job: the objective and a countdown at the top of the screen, and a beam of light on the target.

const JOBS := {
	"delivery": {"title": "Parcel delivery", "desc": "Carry a package to an address in town. Hand it over at the door (or just drop it there).", "pay": "$45 - $130"},
	"pizza": {"title": "Pizza run", "desc": "Grab a hot pizza from the Pizza Palace counter and get it to the customer before it goes cold. Do NOT eat it.", "pay": "$35 - $90 + tips"},
	"chop": {"title": "Car 'collection'", "desc": "The Chop Shop wants a particular car. Find one, take it (however you like) and drive it into their garage at the parking lot.", "pay": "$150 - $320"},
	"trouble": {"title": "Trouble-maker", "desc": "Somebody is picking fights in town. Go and knock them out. They hit back.", "pay": "$110"},
}
const CHOP_PAY := {"sedan": 150, "taxi": 170, "truck": 190, "sports": 260, "police": 320}

var active := {}      # server: peer id -> job
var mine := {}        # this machine's job, for the HUD: {text, pos, node, ends_at}
var _check_t := 0.0
var _hud: Label
var _beam: MeshInstance3D
var _world: GameWorld

func _ready() -> void:
	_world = get_parent() as GameWorld

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_check_t -= delta
		if _check_t <= 0.0:
			_check_t = 0.25
			_check_all()
	_update_hud()

# ======================================================================= server
## Take a job (from the job board UI). Only next to the board, one job at a time.
@rpc("any_peer", "call_local", "reliable")
func accept(kind: String) -> void:
	if not multiplayer.is_server() or not JOBS.has(kind):
		return
	var id := _sender()
	var pl := _player(id)
	if pl == null or _world == null or _world.town == null:
		return
	var town: Town = _world.town
	if town == null:
		return
	if pl.global_position.distance_to(town.job_board) > 7.0:
		return
	if active.has(id):
		_world._toast_to(id, "Finish (or quit) the job you've got first")
		return
	var job := {"type": kind, "stage": 0, "pay": 0, "away": 0.0}
	match kind:
		"delivery":
			var ad := _pick_address(town.job_board, 40.0)
			var dist := town.job_board.distance_to(ad["pos"])
			job["addr"] = ad["name"]
			job["pos"] = ad["pos"]
			job["pay"] = int(40.0 + dist * 0.4)
			job["ends"] = _now() + int((50.0 + dist / 3.0) * 1000.0)
			job["stage"] = 1
			job["text"] = "Deliver the package to %s" % ad["name"]
			pl.equip.rpc_id(id, "package", "")
		"pizza":
			job["pos"] = town.pizza_counter
			job["ends"] = _now() + 120000
			job["text"] = "Pick up the pizza at Pizza Palace (Main St)"
		"chop":
			var kinds := CHOP_PAY.keys()
			var want: String = kinds[randi() % kinds.size()]
			job["want"] = want
			job["pay"] = int(CHOP_PAY[want])
			job["ends"] = _now() + 420000
			job["text"] = "Steal a %s and drive it into the CHOP SHOP (back of the parking lot)" % Prop.CARS[want]["label"]
			var car := _find_car(want, pl.global_position)
			if car == null:
				car = _spawn_mark(want)
			job["node"] = str(car.name) if car != null else ""
			job["pos"] = car.global_position if car != null else town.chop_shop
		"trouble":
			var spot := town.random_walk_spot()
			for tries in 8:
				if (spot["pos"] as Vector3).distance_to(pl.global_position) > 45.0:
					break
				spot = town.random_walk_spot()
			var npc := _world.spawn_npc(spot["pos"] + Vector3.UP * 0.1, randi() % 100000, 0, false, true)
			if npc == null:
				return
			var wp: Dictionary = town.walk_paths[int(spot["path"])]
			npc.path = wp["pts"]
			npc.path_loop = bool(wp["loop"])
			npc.resident = true
			job["node"] = str(npc.name)
			job["pos"] = npc.global_position
			job["pay"] = 110
			job["ends"] = _now() + 300000
			job["text"] = "Knock out the trouble-maker (%s)" % npc.npc_name
	active[id] = job
	_send(id, job)
	_world._toast_to(id, "JOB: " + str(job["text"]))

@rpc("any_peer", "call_local", "reliable")
func quit() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if active.has(id):
		_end(id, false, "You quit the job.")

func _check_all() -> void:
	for id in active.keys():
		var job: Dictionary = active[id]
		var pl := _player(int(id))
		if pl == null:
			active.erase(id)
			continue
		if _now() > int(job["ends"]):
			_end(int(id), false, "Out of time! The job's off.")
			continue
		match str(job["type"]):
			"delivery":
				_check_delivery(int(id), pl, job)
			"pizza":
				_check_pizza(int(id), pl, job)
			"chop":
				_check_chop(int(id), pl, job)
			"trouble":
				_check_trouble(int(id), job)

func _check_delivery(id: int, pl: Player, job: Dictionary) -> void:
	var target: Vector3 = job["pos"]
	if pl.equipped == "package" and _flat_dist(pl.global_position, target) < 3.5:
		pl.take_item.rpc_id(id, "package")
		_end(id, true, "Package delivered to %s!" % job["addr"])
		return
	for n in get_tree().get_nodes_in_group("props"):
		var p := n as Prop
		if p != null and p.kind == "package" and not p.exploded and _flat_dist(p.global_position, target) < 3.5:
			p.queue_free()
			_end(id, true, "Package left at %s. Signed for by... nobody. Good enough!" % job["addr"])
			return

func _check_pizza(id: int, pl: Player, job: Dictionary) -> void:
	var town := _world.town
	if int(job["stage"]) == 0:
		if _flat_dist(pl.global_position, town.pizza_counter) < 3.2 and pl.ride_name == "":
			var ad := _pick_address(town.pizza_counter, 35.0)
			var dist := town.pizza_counter.distance_to(ad["pos"])
			job["stage"] = 1
			job["addr"] = ad["name"]
			job["pos"] = ad["pos"]
			job["pay"] = int(30.0 + dist * 0.3)
			job["secs"] = 35.0 + dist / 3.5
			job["ends"] = _now() + int(float(job["secs"]) * 1000.0)
			job["text"] = "Deliver the HOT pizza to %s (don't eat it!)" % ad["name"]
			pl.equip.rpc_id(id, "pizza", "")
			_send(id, job)
			_world._toast_to(id, "Hot pizza! Get it to %s" % ad["name"])
		return
	if pl.equipped == "pizza" and _flat_dist(pl.global_position, job["pos"]) < 3.5:
		pl.take_item.rpc_id(id, "pizza")
		var left := maxf(0.0, float(int(job["ends"]) - _now()) / 1000.0)
		var tip := int(left * 0.6)
		job["pay"] = int(job["pay"]) + tip
		_end(id, true, "Pizza delivered! Tip: $%d" % tip)
		return
	if pl.ride_name == "" and pl.equipped != "pizza":
		job["away"] = float(job["away"]) + 0.25
		if float(job["away"]) > 4.0:
			_end(id, false, "Where's the pizza?! (Did you EAT it?) The customer cancelled.")
	else:
		job["away"] = 0.0

func _check_chop(id: int, pl: Player, job: Dictionary) -> void:
	var want := str(job["want"])
	var town := _world.town
	var riding: Prop = null
	if pl.ride_name != "":
		riding = _world.get_node_or_null(pl.ride_name) as Prop
	if riding != null and riding.kind == want and riding.rider == id:
		if int(job["stage"]) != 1 or str(job.get("node", "")) != "":
			job["stage"] = 1
			job["node"] = ""
			job["pos"] = town.chop_shop
			job["text"] = "Drive the %s into the CHOP SHOP (back of the parking lot)" % Prop.CARS[want]["label"]
			_send(id, job)
		if _flat_dist(riding.global_position, town.chop_shop) < 6.5:
			pl.stop_ride.rpc_id(id)
			riding.rider = 0
			var car := riding
			get_tree().create_timer(0.6).timeout.connect(func():
				if is_instance_valid(car):
					car.queue_free())
			_end(id, true, "The %s is in bits already. Pleasure doing business." % Prop.CARS[want]["label"])
		return
	# not in the right car: point at the nearest one
	if int(job["stage"]) == 1 or Engine.get_physics_frames() % 20 == 0:
		var car2 := _find_car(want, pl.global_position)
		if car2 == null:
			car2 = _spawn_mark(want)
		var nm := str(car2.name) if car2 != null else ""
		if nm != str(job.get("node", "")) or int(job["stage"]) == 1:
			job["stage"] = 0
			job["node"] = nm
			job["text"] = "Steal a %s and drive it into the CHOP SHOP (back of the parking lot)" % Prop.CARS[want]["label"]
			_send(id, job)

func _check_trouble(id: int, job: Dictionary) -> void:
	var npc := _world.get_node_or_null(str(job["node"])) as Npc
	if npc == null:
		_end(id, false, "The trouble-maker got away.")
		return
	if npc.dead:
		_end(id, true, "Trouble sorted. The town thanks you (in cash).")

func _end(id: int, ok: bool, msg: String) -> void:
	var job: Dictionary = active.get(id, {})
	active.erase(id)
	if ok:
		var pay := int(job.get("pay", 0))
		_world.add_money(id, pay)
		_world._toast_to(id, "%s  +$%d" % [msg, pay])
	else:
		_world._toast_to(id, msg)
		if str(job.get("type", "")) == "trouble":
			var npc := _world.get_node_or_null(str(job.get("node", ""))) as Npc
			if npc != null and not npc.dead:
				npc.troublemaker = false
				npc.hostile = 0
	_send(id, {"done": ok, "pay": int(job.get("pay", 0)) if ok else 0})

func _pick_address(from: Vector3, min_dist: float) -> Dictionary:
	var town := _world.town
	var far: Array = []
	for ad in town.addresses:
		if from.distance_to(ad["pos"]) >= min_dist:
			far.append(ad)
	if far.is_empty():
		far = town.addresses
	return far[randi() % far.size()]

func _find_car(kind: String, near: Vector3) -> Prop:
	var best: Prop = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("props"):
		var p := n as Prop
		if p == null or p.kind != kind or p.exploded:
			continue
		var d := p.global_position.distance_to(near)
		if d < best_d:
			best_d = d
			best = p
	return best

## No car of that kind about: one turns up, parked somewhere in town.
func _spawn_mark(kind: String) -> Prop:
	var town := _world.town
	var spots := town.parking.duplicate()
	spots.shuffle()
	for sp in spots:
		if _world._lane_clear(sp["pos"]):
			return _world.spawn_car(kind, sp["pos"], float(sp["yaw"]))
	var ls := town.random_lane_spot()
	return _world.spawn_car(kind, ls["pos"], float(ls["yaw"]), 1 + randi() % 100000, ls["route"])

func _send(id: int, job: Dictionary) -> void:
	var info := {}
	if job.has("done"):
		info = job
	else:
		info = {"text": str(job.get("text", "")), "pos": job.get("pos", Vector3.ZERO), "node": str(job.get("node", "")),
			"secs": maxf(0.0, float(int(job.get("ends", 0)) - _now()) / 1000.0)}
	if id == multiplayer.get_unique_id():
		_show(info)
	else:
		_show.rpc_id(id, info)

func _player(id: int) -> Player:
	if _world == null:
		return null
	return _world.get_node_or_null(str(id)) as Player

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id

func _now() -> int:
	return Time.get_ticks_msec()

static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ======================================================================= client
@rpc("authority", "call_remote", "reliable")
func _show(info: Dictionary) -> void:
	if info.has("done"):
		mine = {}
		if bool(info["done"]):
			Sfx.play_ui(self, "ding", 0.0)
		else:
			Sfx.play_ui(self, "error", -4.0)
		return
	mine = info.duplicate()
	mine["ends_at"] = Time.get_ticks_msec() + int(float(info.get("secs", 0.0)) * 1000.0)

func has_job() -> bool:
	return not mine.is_empty()

func _update_hud() -> void:
	if mine.is_empty():
		if _hud != null:
			_hud.visible = false
		if _beam != null:
			_beam.visible = false
		return
	if _hud == null:
		var layer := CanvasLayer.new()
		layer.layer = 11
		add_child(layer)
		_hud = Label.new()
		_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_hud.offset_top = 12
		_hud.offset_left = -480
		_hud.offset_right = 480
		_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hud.add_theme_font_size_override("font_size", 22)
		_hud.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
		_hud.add_theme_color_override("font_outline_color", Color.BLACK)
		_hud.add_theme_constant_override("outline_size", 8)
		layer.add_child(_hud)
	if _beam == null:
		_beam = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7
		cm.bottom_radius = 0.7
		cm.height = 90.0
		cm.radial_segments = 12
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		_beam.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.2, 0.32)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam.material_override = m
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam)
	var pos: Vector3 = mine.get("pos", Vector3.ZERO)
	var nm := str(mine.get("node", ""))
	if nm != "" and _world != null:
		var n := _world.get_node_or_null(nm) as Node3D
		if n != null:
			pos = n.global_position
	_beam.visible = true
	_beam.global_position = Vector3(pos.x, 45.0, pos.z)
	var left := maxi(0, int(mine.get("ends_at", 0)) - Time.get_ticks_msec()) / 1000
	var dist_txt := ""
	var me: Node3D = null
	if _world != null:
		me = _world.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	if me != null:
		dist_txt = "   %d m" % int(_flat_dist(me.global_position, pos))
	_hud.visible = true
	_hud.text = "JOB: %s%s   %d:%02d" % [str(mine.get("text", "")), dist_txt, left / 60, left % 60]
