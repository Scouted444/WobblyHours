class_name HouseFull
extends HouseBuilder
## The complete location: HouseBuilder's rooms plus the party room (disco floor, DJ booth,
## speakers), the ground with a swimming pool, a diving board, fence, trees and a trampoline.

signal trampoline_hit(body: Node3D)
signal board_hit(body: Node3D)

const POOL_RECT := Rect2(-7.0, -24.0, 14.0, 13.0)  # x, z, width, depth of the pool hole
const POOL_SURFACE := -0.35
const STREET_END := 92.0        # the map now reaches z = 92 (the street and shop are past the front fence)
const SHOP_Z0 := 62.0           # shop front wall
const SHOP_Z1 := 76.0           # shop back wall
const SHOP_X := 10.0            # shop half width
var shop_counter := Vector3(5.5, 1.0, 65.0)   # where you buy (press F near it)
var shop_pickup := Vector3(3.7, 1.05, 64.6)   # bought things appear on the end of the counter
var _cashier: NpcBody
var ladders: Array = []
var shelf_rows: Array = []      # [{kind, front (x of the shelf face), y, z0, z1}]: shop shelves you can take from         # [{pos, out}]: climbable pool ladders (out = the way onto the deck)
const POOL_FLOOR := -2.2

var _t := 0.0
var _disco_mats: Array[StandardMaterial3D] = []
var _disco_ball: Node3D
var _disco_lights: Array[OmniLight3D] = []
var _board: Node3D
var _board_tween: Tween

func build() -> void:
	super.build()
	_party_room()
	_ground_and_pool()
	_yard()
	_street()
	_shop()

# --------------------------------------------------------------- party room
func _speaker(pos: Vector3) -> void:
	var g := _g(pos, 180)  # face +Z (into the room)
	_m("speaker", Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 0.75, 0), Vector3(0.7, 1.5, 0.6))

func _beanbag(pos: Vector3, model_name: String) -> void:
	var g := _g(pos)
	_m(model_name, Vector3.ZERO, 0.0, 1.0, g)
	_solid_cyl(g, Vector3(0, 0.15, 0), 0.42, 0.3)

func _party_room() -> void:
	_light(Vector3(6, 2.6, -1.0), Color(1.0, 0.7, 0.9), 0.7, 9.0)
	# Glowing disco floor: 4x4 tiles that change colour
	for i in 16:
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		_disco_mats.append(m)
		_b(self, Vector3(4.5 + (i % 4), 0.016, -5.0 + (i / 4)), Vector3(0.92, 0.016, 0.92), m, false)
	# Disco ball and colour lights
	_disco_ball = _m("disco_ball", Vector3(6.0, 2.35, -3.0))
	for c in [Color(1, 0.2, 0.3), Color(0.2, 1, 0.4), Color(0.3, 0.4, 1)]:
		_disco_lights.append(_light(Vector3(6, 1.8, -3), c, 2.2, 6.0))
	# DJ booth and speakers (kept away from the doorways)
	_speaker(Vector3(3.6, 0, -6.3))
	_speaker(Vector3(8.4, 0, -6.3))
	var dj := _g(Vector3(6.0, 0, -6.1), 180)
	_m("dj_booth", Vector3.ZERO, 0.0, 1.0, dj)
	_solid(dj, Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 0.7))
	_m("neon_sign", Vector3(6.0, 2.3, -6.84), 180)
	_sofa(Vector3(9.2, 0, -2.8), 90, "sofa_pink", 2.4)
	_sofa(Vector3(9.2, 0, -0.5), 90, "loveseat_pink", 1.2)
	_beanbag(Vector3(3.2, 0, -0.5), "beanbag_yellow")
	_beanbag(Vector3(4.3, 0, -0.9), "beanbag_green")
	_beanbag(Vector3(8.0, 0, -5.0), "beanbag_blue")

func _process(delta: float) -> void:
	_t += delta
	for i in _disco_mats.size():
		var c := Color.from_hsv(fmod(_t * 0.15 + i * 0.07, 1.0), 0.9, 1.0)
		var m := _disco_mats[i]
		m.albedo_color = c
		m.emission = c
		m.emission_energy_multiplier = 0.4 + (0.5 + 0.5 * sin(_t * 4.0 + i)) * 1.6
	if _disco_ball != null:
		_disco_ball.rotate_y(delta * 0.6)
	for i in _disco_lights.size():
		var a := _t * 0.9 + i * TAU / 3.0
		_disco_lights[i].position = Vector3(6.0 + cos(a) * 2.6, 1.8, -3.0 + sin(a) * 2.2)

func _on_board_entered(body: Node3D) -> void:
	board_hit.emit(body)
	if _board != null:
		if _board_tween != null:
			_board_tween.kill()
		_board_tween = create_tween()
		_board_tween.tween_property(_board, "rotation_degrees:x", 9.0, 0.08).set_ease(Tween.EASE_OUT)
		_board_tween.tween_property(_board, "rotation_degrees:x", -7.0, 0.16).set_trans(Tween.TRANS_SINE)
		_board_tween.tween_property(_board, "rotation_degrees:x", 3.0, 0.14).set_trans(Tween.TRANS_SINE)
		_board_tween.tween_property(_board, "rotation_degrees:x", 0.0, 0.2).set_trans(Tween.TRANS_SINE)

# --------------------------------------------------------------- ground, pool
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _commit_mesh(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

func _ground_and_pool() -> void:
	var grass := Mats.textured("grass", Color.WHITE, 3.0, 0.95)
	var tile := Mats.textured("tiles", Color(0.55, 0.82, 0.95), 1.0, 0.35)
	var r := POOL_RECT
	var x0 := r.position.x
	var x1 := r.position.x + r.size.x
	var z0 := r.position.y
	var z1 := r.position.y + r.size.y
	var pf := POOL_FLOOR
	var ext := 46.0
	var thick := 3.0
	var ov := 0.6  # west/east pieces overlap north/south ones (same height, same material): no seams to snag on
	# Ground top is y = 0. The pool is the gap between the four slabs.
	_slab(Vector3(-ext, -thick, -ext), Vector3(ext, 0.0, z0), grass)
	_slab(Vector3(-ext, -thick, z1), Vector3(ext, 0.0, ext), grass)
	_slab(Vector3(-ext, -thick, z0 - ov), Vector3(x0, 0.0, z1 + ov), grass)
	_slab(Vector3(x1, -thick, z0 - ov), Vector3(ext, 0.0, z1 + ov), grass)
	_slab(Vector3(-ext, -thick, ext - ov), Vector3(ext, 0.0, STREET_END + 2.0), grass)   # the street and the shop across it
	# Pool floor and tiled inner walls
	_slab(Vector3(x0, pf - 1.0, z0), Vector3(x1, pf, z1), tile)
	_b(self, Vector3(x0 + 0.02, pf / 2.0, (z0 + z1) / 2.0), Vector3(0.04, -pf, r.size.y), tile, false)
	_b(self, Vector3(x1 - 0.02, pf / 2.0, (z0 + z1) / 2.0), Vector3(0.04, -pf, r.size.y), tile, false)
	_b(self, Vector3(0, pf / 2.0, z0 + 0.02), Vector3(r.size.x, -pf, 0.04), tile, false)
	_b(self, Vector3(0, pf / 2.0, z1 - 0.02), Vector3(r.size.x, -pf, 0.04), tile, false)

	var rim := Mats.textured("concrete", Color(0.9, 0.9, 0.85), 2.0)
	_b(self, Vector3(0, 0.012, z0 - 0.28), Vector3(r.size.x + 1.3, 0.012, 0.55), rim, false)
	_b(self, Vector3(0, 0.012, z1 + 0.28), Vector3(r.size.x + 1.3, 0.012, 0.55), rim, false)
	_b(self, Vector3(x0 - 0.28, 0.03, (z0 + z1) / 2.0), Vector3(0.55, 0.035, r.size.y), rim, false)
	_b(self, Vector3(x1 + 0.28, 0.03, (z0 + z1) / 2.0), Vector3(0.55, 0.035, r.size.y), rim, false)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.15, 0.5, 0.82, 0.5)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.04
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.emission_enabled = true
	water.emission = Color(0.25, 0.55, 0.75)
	water.emission_energy_multiplier = 0.18
	_b(self, Vector3(0, POOL_SURFACE, (z0 + z1) / 2.0), Vector3(r.size.x - 0.08, 0.04, r.size.y - 0.08), water, false)
	# Diving board: pedestal + bouncy board (the board model dips when someone lands on it)
	var db := _g(Vector3(2.5, 0, z1 + 0.45))
	_m("diving_board", Vector3.ZERO, 0.0, 1.0, db)
	_solid(db, Vector3(0, 0.32, 0), Vector3(0.7, 0.64, 0.85))
	_solid(db, Vector3(0, 0.69, -1.1), Vector3(0.62, 0.07, 3.0), 0.0)
	_board = db.find_child("Board", true, false) as Node3D
	var bpad := Area3D.new()
	bpad.position = Vector3(0, 1.15, -1.7)
	bpad.collision_mask = 1 | 4
	var bs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.56, 0.9, 1.6)
	bs.shape = bb
	bpad.add_child(bs)
	db.add_child(bpad)
	bpad.body_entered.connect(_on_board_entered)
	_pool_ladder(x1 - 0.08, (z0 + z1) * 0.5)
	_pool_ladder(x0 + 0.08, (z0 + z1) * 0.5 - 3.0, 180.0)
	_ramp(Vector3(-4.5, 0, z1 - 1.7), 0.0, 2.8, 3.3, pf + 0.02, -0.04, tile)   # steps, nowhere near the board

# ---------------------------------------------------------------------- yard
func _tree(pos: Vector3, scale_f := 1.0, pine := false) -> void:
	var g := _g(pos)
	_m("pine_tree" if pine else "tree", Vector3.ZERO, randf_range(0.0, 360.0), scale_f, g)
	_solid_cyl(g, Vector3(0, 1.5 * scale_f, 0), 0.26 * scale_f, 3.0 * scale_f)

func _yard() -> void:
	var concrete := Mats.textured("concrete", Color(0.85, 0.85, 0.82), 2.0)
	_b(self, Vector3(5.0, 0.012, -9.2), Vector3(14.0, 0.012, 3.6), concrete, false)
	_b(self, Vector3(0.0, 0.012, 12.8), Vector3(2.2, 0.012, 11.2), concrete, false)
	var fence := Mats.textured("planks", Color(0.9, 0.85, 0.75), 1.0)
	_b(self, Vector3(0, 0.88, -44.2), Vector3(88.8, 1.68, 0.18), fence, true, Vector3.ZERO, 0.12)
	# front fence with a gate gap onto the street
	_b(self, Vector3(-23.6, 0.88, 44.2), Vector3(41.2, 1.68, 0.18), fence, true, Vector3.ZERO, 0.12)
	_b(self, Vector3(23.6, 0.88, 44.2), Vector3(41.2, 1.68, 0.18), fence, true, Vector3.ZERO, 0.12)
	for gx in [-3.0, 3.0]:
		_b(self, Vector3(gx, 1.0, 44.2), Vector3(0.3, 2.0, 0.3), Mats.solid(Color(0.95, 0.93, 0.88)), true)
	# outer boundary now runs round the street too
	var side_len := STREET_END + 44.2
	var side_mid := (STREET_END - 44.2) * 0.5
	_b(self, Vector3(-44.2, 0.88, side_mid), Vector3(0.18, 1.68, side_len), fence, true, Vector3.ZERO, 0.12)
	# east side: open where Main St carries on into town (the town builds the rest, south of the road)
	_b(self, Vector3(44.2, 0.88, (-44.2 + 45.4) * 0.5), Vector3(0.18, 1.68, 45.4 + 44.2), fence, true, Vector3.ZERO, 0.12)
	_b(self, Vector3(0, 0.88, STREET_END), Vector3(88.8, 1.68, 0.18), fence, true, Vector3.ZERO, 0.12)
	for p in [Vector3(-14, 0, -10), Vector3(16, 0, -14), Vector3(15, 0, 16), Vector3(-18, 0, 9), Vector3(22, 0, -3), Vector3(-24, 0, -16), Vector3(-16, 0, 22), Vector3(26, 0, 20)]:
		_tree(p, randf_range(0.95, 1.45), int(absf(p.x + p.z)) % 3 == 0)
	for p in [Vector3(-8, 0, -12), Vector3(11, 0, -16), Vector3(-22, 0, 4), Vector3(18, 0, 8), Vector3(8, 0, 24), Vector3(-28, 0, -8)]:
		_bush(p, randf_range(0.85, 1.25))
	_ramp(Vector3(8.0, 0, 16.5), 180.0, 3.6, 5.2, -0.18, 1.15, Mats.solid(Color(0.72, 0.52, 0.28), 0.85))
	_m("trampoline", Vector3(-8, 0, 15.5))
	_solid_cyl(self, Vector3(-8, 0.15, 15.5), 1.45, 0.3)
	var pad := Area3D.new()
	pad.position = Vector3(-8, 0.6, 15.5)
	pad.collision_mask = 1 | 4  # players (1) and ragdoll limbs (4)
	var pad_shape := CollisionShape3D.new()
	var pad_box := BoxShape3D.new()
	pad_box.size = Vector3(2.6, 0.6, 2.6)
	pad_shape.shape = pad_box
	pad.add_child(pad_shape)
	add_child(pad)
	pad.body_entered.connect(func(body: Node3D): trampoline_hit.emit(body))
	_porch()
	var box := _g(Vector3(2.6, 0, 11.2))
	_m("mailbox", Vector3.ZERO, 0.0, 1.0, box)
	_solid(box, Vector3(0, 0.55, 0), Vector3(0.1, 1.1, 0.1))
	_solid(box, Vector3(0, 1.05, 0), Vector3(0.3, 0.3, 0.42), 0.0)
	# lawn and patio decor
	for k in 2:
		var ch := _g(Vector3(-8.6, 0, -19.0 + k * 2.6), 90)
		_m("lounge_chair", Vector3.ZERO, 0.0, 1.0, ch)
		_solid(ch, Vector3(0, 0.2, 0.25), Vector3(0.72, 0.4, 1.32))                       # seat
		_solid(ch, Vector3(0, 0.58, -0.73), Vector3(0.72, 0.1, 0.85), 0.0, Vector3(38, 0, 0))   # backrest
	var bq := _g(Vector3(10.5, 0, -9.0), 180)
	_m("bbq", Vector3.ZERO, 0.0, 1.0, bq)
	_solid_cyl(bq, Vector3(0, 0.7, 0), 0.4, 1.4)
	for gp in [Vector3(-1.9, 0, 10.5), Vector3(1.9, 0, 12.0), Vector3(-1.9, 0, 15.0)]:
		var gn := _g(gp, randf_range(0.0, 360.0))
		_m("gnome", Vector3.ZERO, 0.0, 1.0, gn)
		_solid_cyl(gn, Vector3(0, 0.3, 0), 0.16, 0.6)
	for fp in [Vector3(2.0, 0, 15.8), Vector3(-2.2, 0, 17.5)]:
		var fl := _g(fp, randf_range(0.0, 360.0))
		_m("flamingo", Vector3.ZERO, 0.0, 1.0, fl)
		_solid_cyl(fl, Vector3(0, 0.45, 0), 0.1, 0.9)

# ------------------------------------------------------------- yard helpers
## Sloped slab. Local -Z is the low end (y_start), local +Z the high end (y_end).
func _ramp(pos: Vector3, yaw_deg: float, width: float, length: float, y_start: float, y_end: float, mat: Material) -> void:
	var rise := y_end - y_start
	var ang := atan2(rise, length)
	var thick := 0.3
	var mid := Vector3(0.0, (y_start + y_end) * 0.5, 0.0)
	var normal := Vector3(0.0, cos(ang), -sin(ang))
	var local_center := mid - normal * thick * 0.5
	var c := pos + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * local_center
	var slope := sqrt(length * length + rise * rise)
	_b(self, c, Vector3(width, thick, slope), mat, true, Vector3(-rad_to_deg(ang), yaw_deg, 0.0), 0.0)

func _pool_ladder(x: float, z: float, yaw := 0.0) -> void:
	ladders.append({"pos": Vector3(x, 0.0, z), "out": Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT})
	_m("pool_ladder", Vector3(x, 0.0, z), yaw)

func _bush(pos: Vector3, s := 1.0) -> void:
	_m("bush", pos, randf_range(0.0, 360.0), s)

func _porch() -> void:
	var concrete := Mats.textured("concrete", Color(0.8, 0.8, 0.78), 2.0)
	_b(self, Vector3(0, 0.012, 8.3), Vector3(4.6, 0.012, 2.5), concrete, false)
	_b(self, Vector3(0, 0.02, 7.7), Vector3(1.3, 0.01, 0.8), Mats.solid(Color(0.7, 0.15, 0.15), 0.95), false)  # doormat
	for x in [-2.0, 2.0]:
		_cyl(self, Vector3(x, 1.45, 9.3), 0.11, 2.9, Mats.solid(Color(0.95, 0.93, 0.88)), true)
	_b(self, Vector3(0, 3.0, 8.3), Vector3(4.8, 0.18, 2.8), Mats.solid(Color(0.95, 0.93, 0.88)), false)
	_b(self, Vector3(0, 3.18, 8.3), Vector3(5.0, 0.1, 3.0), Mats.textured("shingles", Color(0.72, 0.28, 0.2), 1.4, 0.92), false)
	_light(Vector3(0, 2.7, 8.3), Color(1.0, 0.9, 0.7), 1.0, 6.0)

## Solid box from two corners.
func _slab(lo: Vector3, hi: Vector3, mat: Material) -> void:
	_b(self, (lo + hi) * 0.5, hi - lo, mat, true, Vector3.ZERO, 0.0)

# ------------------------------------------------------------------ street
func _street() -> void:
	var asphalt := Mats.textured("concrete", Color(0.25, 0.25, 0.27), 3.0, 0.95)
	var walk := Mats.textured("concrete", Color(0.82, 0.82, 0.8), 1.5)
	var yellow := Mats.solid(Color(0.98, 0.82, 0.15), 0.6)
	var white := Mats.solid(Color(0.95, 0.95, 0.95), 0.6)
	_b(self, Vector3(0, 0.006, 47.2), Vector3(88.0, 0.012, 3.6), walk, false)             # pavement by our fence
	_b(self, Vector3(0, 0.012, 45.4), Vector3(4.0, 0.012, 2.2), walk, false)              # path through the gate
	_b(self, Vector3(0, 0.008, 53.0), Vector3(88.0, 0.012, 8.0), asphalt, false)           # road
	for i in 22:                                                                           # dashed centre line
		_b(self, Vector3(-42.0 + i * 4.0, 0.016, 53.0), Vector3(2.0, 0.01, 0.15), yellow, false)
	for i in 7:                                                                            # zebra crossing to the shop
		_b(self, Vector3(-3.0 + i * 1.0, 0.017, 53.0), Vector3(0.55, 0.01, 7.0), white, false)
	_b(self, Vector3(0, 0.006, 59.0), Vector3(88.0, 0.012, 4.0), walk, false)             # pavement by the shop
	_b(self, Vector3(0, 0.006, 61.2), Vector3(2 * SHOP_X + 4.0, 0.012, 1.0), walk, false)
	var pole := Mats.solid(Color(0.3, 0.32, 0.35), 0.4, 0.6)
	for x in [-24.0, -12.0, 14.0, 26.0]:                                                  # street lights
		for side in [0, 1]:
			var z: float = 49.3 if side == 0 else 56.8
			_cyl(self, Vector3(x, 2.2, z), 0.07, 4.4, pole, true)
			_b(self, Vector3(x, 4.42, z + (0.45 if side == 0 else -0.45)), Vector3(0.16, 0.08, 1.0), pole, false)
			_sph(self, Vector3(x, 4.33, z + (0.85 if side == 0 else -0.85)), 0.12, Mats.glow(Color(1.0, 0.92, 0.7), 2.0))
			_light(Vector3(x, 4.1, z + (0.85 if side == 0 else -0.85)), Color(1.0, 0.9, 0.7), 1.2, 11.0)
	for p in [Vector3(-34, 0, 70), Vector3(-22, 0, 80), Vector3(24, 0, 70), Vector3(34, 0, 84), Vector3(-36, 0, 86), Vector3(15, 0, 86)]:
		_tree(p, randf_range(1.0, 1.4), int(absf(p.x)) % 2 == 0)
	for p in [Vector3(-13, 0, 63), Vector3(13, 0, 63), Vector3(-30, 0, 61), Vector3(30, 0, 61)]:
		_bush(p, 0.9)
	for x in [-16.0, 16.0]:                                                                 # benches out front
		var g := _g(Vector3(x, 0, 60.2), 180)
		_m("bench", Vector3.ZERO, 0.0, 1.0, g)
		_solid(g, Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 0.5))

# -------------------------------------------------------------------- shop
func _shop() -> void:
	var outer := Mats.textured("concrete", Color(0.95, 0.86, 0.68), 1.6)
	var keep := wall_mat
	wall_mat = outer
	var x0 := -SHOP_X
	var x1 := SHOP_X
	var z0 := SHOP_Z0
	var z1 := SHOP_Z1
	_floor(x0, z0, x1, z1, Mats.textured("checker", Color(0.95, 0.95, 1.0), 1.2, 0.3))
	# big shop windows either side of a wide open doorway
	wall_x(z0, x0, x1, [[-1.6, 1.6, 0.0, 2.5], [-8.6, -2.4, 0.5, 2.5], [2.4, 8.6, 0.5, 2.5]])
	wall_x(z1, x0, x1)
	wall_z(x0, z0, z1, [_window(66.0, 70.0)])
	wall_z(x1, z0, z1)
	wall_mat = keep
	_b(self, Vector3(0, H + 0.1, (z0 + z1) * 0.5), Vector3(2 * SHOP_X + 0.5, 0.2, z1 - z0 + 0.5), Mats.solid(Color(0.97, 0.97, 0.95)))
	_b(self, Vector3(0, H + 0.3, (z0 + z1) * 0.5), Vector3(2 * SHOP_X + 1.2, 0.2, z1 - z0 + 1.2), Mats.solid(Color(0.4, 0.4, 0.42), 0.8), true, Vector3.ZERO, 0.0)
	# sign board, name and an OPEN sign
	_b(self, Vector3(0, H + 0.85, z0 - 0.2), Vector3(12.0, 1.0, 0.2), Mats.solid(Color(0.12, 0.2, 0.45), 0.5), false)
	var name_lbl := Label3D.new()
	name_lbl.text = "CORNER SHOP"
	name_lbl.font_size = 160
	name_lbl.pixel_size = 0.004
	name_lbl.modulate = Color(1.0, 0.85, 0.3)
	name_lbl.outline_size = 24
	name_lbl.outline_modulate = Color(0.5, 0.2, 0.0)
	name_lbl.position = Vector3(0, H + 0.85, z0 - 0.32)
	name_lbl.rotation_degrees = Vector3(0, 180, 0)
	add_child(name_lbl)
	var open_lbl := Label3D.new()
	open_lbl.text = "OPEN"
	open_lbl.font_size = 64
	open_lbl.pixel_size = 0.005
	open_lbl.modulate = Color(1.0, 0.25, 0.35)
	open_lbl.outline_size = 10
	open_lbl.position = Vector3(-5.5, 2.15, z0 - 0.06)
	open_lbl.rotation_degrees = Vector3(0, 180, 0)
	add_child(open_lbl)
	# striped awning over the door
	for i in 8:
		var c: Color = Color(0.85, 0.15, 0.15) if i % 2 == 0 else Color(0.97, 0.97, 0.95)
		_b(self, Vector3(-1.75 + i * 0.5, 2.85, z0 - 0.7), Vector3(0.5, 0.06, 1.4), Mats.solid(c, 0.8), false, Vector3(-18, 0, 0))
	_light(Vector3(0, 2.6, z0 - 1.0), Color(1.0, 0.9, 0.7), 1.0, 6.0)
	# lights inside
	for lx in [-5.0, 0.0, 5.0]:
		for lz in [65.5, 71.5]:
			_b(self, Vector3(lx, H - 0.03, lz), Vector3(2.2, 0.05, 0.35), Mats.glow(Color(0.95, 0.98, 1.0), 1.6), false)
			_light(Vector3(lx, H - 0.4, lz), Color(0.95, 0.97, 1.0), 1.1, 8.0)
	# counter with till, and the shopkeeper behind it
	var wood := Mats.textured("planks", Color(0.75, 0.55, 0.35), 1.0)
	_b(self, Vector3(5.5, 0.5, 64.6), Vector3(5.0, 1.0, 0.9), wood, true)
	_b(self, Vector3(5.5, 1.02, 64.6), Vector3(5.1, 0.05, 1.0), Mats.solid(Color(0.2, 0.22, 0.25), 0.4), false)
	_b(self, Vector3(6.4, 1.17, 64.6), Vector3(0.45, 0.25, 0.4), Mats.solid(Color(0.15, 0.15, 0.17), 0.5), false)    # till
	_b(self, Vector3(6.4, 1.38, 64.45), Vector3(0.36, 0.2, 0.04), Mats.glow(Color(0.3, 1.0, 0.5), 1.2), false, Vector3(-20, 0, 0))
	_b(self, Vector3(5.2, 1.1, 64.45), Vector3(0.8, 0.12, 0.35), Mats.solid(Color(0.85, 0.15, 0.2), 0.6), false)    # sweets rack
	var price_lbl := Label3D.new()
	price_lbl.text = "PRESS F TO SHOP"
	price_lbl.font_size = 48
	price_lbl.pixel_size = 0.005
	price_lbl.outline_size = 8
	price_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	price_lbl.position = Vector3(5.5, 2.3, 64.6)
	add_child(price_lbl)
	_cashier = NpcBody.new()
	add_child(_cashier)
	_cashier.position = Vector3(5.8, 0.0, 65.6)
	# NpcBody already faces -Z, toward the counter and the door
	_cashier.load_npc(NpcLook.random(777))
	_solid(self, Vector3(5.8, 0.9, 65.6), Vector3(0.6, 1.8, 0.6))
	# aisles of shelves with goods on them
	for ax in [-7.5, -4.0, -0.5]:
		_shelf_unit(Vector3(ax, 0, 69.0))
	# drinks fridges along the back wall
	for fx in [-8.0, -6.6, -5.2, -3.8]:
		var fr := _g(Vector3(fx, 0, z1 - 0.55))
		_m("fridge", Vector3.ZERO, 0.0, 0.85, fr)
		_solid(fr, Vector3(0, 0.85, 0), Vector3(1.2, 1.7, 0.85))
	# toys corner: a crate pile and a stack of beach balls (decoration)
	for i in 3:
		_m("crate", Vector3(7.5 - i * 0.9, 0.42, 74.6), 0.0, 1.0)
		_solid(self, Vector3(7.5 - i * 0.9, 0.42, 74.6), Vector3(0.84, 0.84, 0.84))
	_sph(self, Vector3(8.3, 0.4, 72.6), 0.4, Mats.textured("stripes", Color.WHITE, 0.8, 0.5))
	_sph(self, Vector3(7.5, 0.35, 72.0), 0.35, Mats.textured("stripes", Color(1.0, 0.9, 0.6), 0.7, 0.5))
	_m("coupe", Vector3(4.5, 0.3, 72.2), 200.0)
	_solid(self, Vector3(4.5, 0.3, 72.2), Vector3(0.8, 0.6, 1.2))

## The shop shelf row the camera ray points at (within arm's reach), or "".
func shelf_kind_at(origin: Vector3, dir: Vector3) -> String:
	var best := ""
	var best_t := 2.2
	for r in shelf_rows:
		if absf(dir.x) < 0.05:
			continue
		var t := (float(r["front"]) - origin.x) / dir.x
		if t <= 0.0 or t >= best_t:
			continue
		var hit := origin + dir * t
		var ry: float = r["y"]
		if hit.z >= float(r["z0"]) and hit.z <= float(r["z1"]) and hit.y >= ry - 0.05 and hit.y <= ry + 0.45:
			best = str(r["kind"])
			best_t = t
	return best

## Two-sided shop shelf, 1.1 wide and 4 long (along Z), stocked with item models.
func _shelf_unit(pos: Vector3) -> void:
	var metal := Mats.solid(Color(0.82, 0.84, 0.86), 0.4, 0.5)
	var back := Mats.solid(Color(0.3, 0.45, 0.75), 0.7)
	_b(self, pos + Vector3(0, 0.08, 0), Vector3(1.1, 0.16, 4.0), metal, false)
	_b(self, pos + Vector3(0, 0.95, 0), Vector3(0.08, 1.8, 4.0), back, false)
	for y in [0.5, 1.0, 1.5]:
		_b(self, pos + Vector3(0, y, 0), Vector3(1.1, 0.04, 4.0), metal, false)
	_solid(self, pos + Vector3(0, 0.95, 0), Vector3(1.1, 1.9, 4.0))
	var goods := ["soda", "beer", "burger", "pizza", "console", "duck", "cig", "melon", "knife", "bat"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100.0)
	for side in [-1.0, 1.0]:
		for y in [0.18, 0.52, 1.02]:
			var kind: String = goods[rng.randi() % goods.size()]
			shelf_rows.append({"kind": kind, "front": pos.x + side * 0.56, "y": pos.y + y, "z0": pos.z - 1.85, "z1": pos.z + 1.85})
			var step: float = 0.3 if kind in ["soda", "beer", "cig", "knife"] else 0.45
			var n := int(3.6 / step)
			for i in n:
				var z := -1.8 + step * 0.5 + i * step
				var p := pos + Vector3(side * 0.3, y + 0.02, z)
				match kind:
					"soda":
						_m(kind, p + Vector3(0, 0.06, 0), 0.0, 1.0)
					"beer":
						_m(kind, p + Vector3(0, 0.13, 0), 0.0, 1.0)
					"melon":
						_m(kind, p + Vector3(0, 0.12, 0), rng.randf() * 360.0, 0.5)
					"bat", "knife":
						_m(kind, p + Vector3(0, 0.03, 0), 90.0, 0.8)
					"duck":
						_m(kind, p + Vector3(0, 0.08, 0), 90.0 * side, 0.7)
					_:
						_m(kind, p + Vector3(0, 0.05, 0), 90.0 * side, 1.0)
