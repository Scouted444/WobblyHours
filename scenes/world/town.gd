class_name Town
extends HouseBuilder
## The town east of the party house: a grid of streets with traffic lanes, blocks of shops, offices
## and houses (every door has an address), a parking lot with the Chop Shop, Wobbly Jobs (the job
## board), Pizza Palace, a police station, street lights and trees.
##
## Everything is built from boxes into a handful of batched meshes (one per material) plus one
## static body with all the colliders, so the whole town costs only a few draw calls.
## The layout is fixed (seeded), so every machine builds the identical town.
##
##   z = 0   North Rd   x 86..200
##   z = 53  Main St    the street in front of the house, carried on east to x = 200
##   z = 106 South Rd   x 86..200
##   x = 90 Oak Ave, x = 150 Elm Ave, x = 196 Bay Ave   (z -4..110)

const X0 := 44.2       # town west edge (the yard's east fence)
const X1 := 204.0
const Z0 := -10.0
const Z1 := 114.0
const ROAD_HALF := 4.0
const LANE := 2.1      # lane centre, right of the middle line
const SETBACK := 5.0   # pavement between the road and the buildings (parking + people)

## Road graph for the traffic AI.
var road_nodes: Array[Vector3] = [
	Vector3(-34, 0, 53),                                          # 0 west end of Main St (by the house)
	Vector3(90, 0, 0), Vector3(150, 0, 0), Vector3(196, 0, 0),    # 1 2 3
	Vector3(90, 0, 53), Vector3(150, 0, 53), Vector3(196, 0, 53), # 4 5 6
	Vector3(90, 0, 106), Vector3(150, 0, 106), Vector3(196, 0, 106)]  # 7 8 9
var road_links := {0: [4], 1: [2, 4], 2: [1, 3, 5], 3: [2, 6], 4: [0, 1, 5, 7], 5: [2, 4, 6, 8],
	6: [3, 5, 9], 7: [4, 8], 8: [5, 7, 9], 9: [6, 8]}

## People walk these (pavement loops round each block). [{pts: Array[Vector3], loop: bool}]
var walk_paths: Array = []
## Delivery addresses: [{name, pos (on the pavement in front of the door), door (the door itself)}]
var addresses: Array = []
## Parking spaces: [{pos, yaw}]
var parking: Array = []
## Points of interest (the job board, the pizza counter, where stolen cars go, the parcel depot).
var job_board := Vector3.ZERO
var pizza_counter := Vector3.ZERO
var chop_shop := Vector3.ZERO
var police_station := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _batch := {}         # Material -> SurfaceTool
var _body: StaticBody3D
var _labels: Node3D

# palette
var _m_asphalt: Material
var _m_pave: Material
var _m_lot: Material
var _m_line: Material
var _m_yellow: Material
var _m_glass: Material
var _m_frame: Material
var _m_door: Material
var _m_dark: Material
var _m_pole: Material
var _m_lamp: Material
var _m_grass: Material
var _walls: Array[Material] = []
var _trims: Array[Material] = []
var _awnings: Array[Material] = []

func build_town() -> void:
	_rng.seed = 424242
	_m_asphalt = Mats.textured("concrete", Color(0.24, 0.24, 0.26), 3.0, 0.95)
	_m_pave = Mats.textured("concrete", Color(0.8, 0.8, 0.78), 1.5)
	_m_lot = Mats.textured("concrete", Color(0.36, 0.36, 0.38), 3.0, 0.95)
	_m_line = Mats.solid(Color(0.95, 0.95, 0.95), 0.6)
	_m_yellow = Mats.solid(Color(0.98, 0.82, 0.15), 0.6)
	_m_glass = Mats.solid(Color(0.16, 0.24, 0.32), 0.08, 0.5)
	_m_frame = Mats.solid(Color(0.92, 0.92, 0.9), 0.6)
	_m_door = Mats.solid(Color(0.32, 0.2, 0.12), 0.7)
	_m_dark = Mats.solid(Color(0.15, 0.15, 0.17), 0.8)
	_m_pole = Mats.solid(Color(0.3, 0.32, 0.35), 0.4, 0.6)
	_m_lamp = Mats.glow(Color(1.0, 0.92, 0.7), 2.0)
	_m_grass = Mats.textured("grass", Color.WHITE, 3.0, 0.95)
	for c in [Color(0.72, 0.36, 0.28), Color(0.85, 0.78, 0.62), Color(0.62, 0.66, 0.7), Color(0.9, 0.88, 0.82),
			Color(0.55, 0.42, 0.32), Color(0.78, 0.55, 0.42), Color(0.6, 0.72, 0.66), Color(0.86, 0.72, 0.55)]:
		_walls.append(Mats.textured("concrete", c, 1.6))
	for c2 in [Color(0.95, 0.95, 0.93), Color(0.3, 0.3, 0.32), Color(0.55, 0.3, 0.22)]:
		_trims.append(Mats.solid(c2, 0.7))
	for c3 in [Color(0.8, 0.15, 0.15), Color(0.15, 0.45, 0.8), Color(0.15, 0.6, 0.3), Color(0.95, 0.6, 0.1), Color(0.55, 0.2, 0.6)]:
		_awnings.append(Mats.solid(c3, 0.8))
	_body = StaticBody3D.new()
	_body.name = "TownSolid"
	add_child(_body)
	_labels = Node3D.new()
	_labels.name = "Signs"
	add_child(_labels)

	_ground()
	_roads()
	_fences()
	_blocks()
	_street_furniture()
	_commit()

# ============================================================== batching helpers
func _st(mat: Material) -> SurfaceTool:
	if not _batch.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batch[mat] = st
	return _batch[mat]

## A box in the batched town mesh (and optionally a collider). xf = where the box centre is.
func _box(xf: Transform3D, size: Vector3, mat: Material, collide := false) -> void:
	var st := _st(mat)
	var h := size * 0.5
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for ai in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = axes[ai] * sgn
			var u: Vector3 = axes[(ai + 1) % 3]
			var v: Vector3 = axes[(ai + 2) % 3]
			var hn: float = h[ai]
			var hu: float = h[(ai + 1) % 3]
			var hv: float = h[(ai + 2) % 3]
			var c := n * hn
			var p00 := xf * (c - u * hu - v * hv)
			var p10 := xf * (c + u * hu - v * hv)
			var p11 := xf * (c + u * hu + v * hv)
			var p01 := xf * (c - u * hu + v * hv)
			var wn := (xf.basis * n).normalized()
			_tri(st, p00, p10, p11, wn)
			_tri(st, p00, p11, p01, wn)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = xf
		_body.add_child(cs)

## Godot draws clockwise triangles as front faces: flip any that face the wrong way.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)

func _abox(center: Vector3, size: Vector3, mat: Material, collide := false) -> void:
	_box(Transform3D(Basis(), center), size, mat, collide)

## Flat piece of ground cover (visual only), top at y.
func _flat(x0: float, z0: float, x1: float, z1: float, y: float, mat: Material) -> void:
	_abox(Vector3((x0 + x1) * 0.5, y - 0.01, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), 0.02, absf(z1 - z0)), mat)

func _commit() -> void:
	for mat in _batch:
		var st: SurfaceTool = _batch[mat]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)
	_batch.clear()

func _sign(text: String, pos: Vector3, facing: Vector3, size := 64, col := Color.WHITE, outline := Color(0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = maxi(4, size / 8)
	l.modulate = col
	l.outline_modulate = outline
	l.double_sided = false
	_labels.add_child(l)
	l.position = pos
	l.basis = Basis.looking_at(-facing, Vector3.UP)
	return l

# ===================================================================== ground
func _ground() -> void:
	var grass := Mats.textured("grass", Color.WHITE, 3.0, 0.95)
	var thick := 3.0
	_b(self, Vector3((46.0 + X1 + 1.0) * 0.5, -thick * 0.5, (Z0 - 0.5 + Z1 + 0.5) * 0.5), Vector3(X1 + 1.0 - 46.0, thick, Z1 - Z0 + 1.0), grass, true, Vector3.ZERO, 0.0)
	# the strip south of the old map's edge, west of x = 46
	_b(self, Vector3(42.0, -thick * 0.5, (94.0 + Z1 + 0.5) * 0.5), Vector3(8.0, thick, Z1 + 0.5 - 94.0), grass, true, Vector3.ZERO, 0.0)

func _fences() -> void:
	var fence := Mats.textured("planks", Color(0.9, 0.85, 0.75), 1.0)
	var y := 0.88
	_b(self, Vector3((X0 + X1) * 0.5, y, Z0), Vector3(X1 - X0, 1.68, 0.18), fence, true, Vector3.ZERO, 0.12)
	_b(self, Vector3((X0 + X1) * 0.5, y, Z1), Vector3(X1 - X0, 1.68, 0.18), fence, true, Vector3.ZERO, 0.12)
	_b(self, Vector3(X1, y, (Z0 + Z1) * 0.5), Vector3(0.18, 1.68, Z1 - Z0), fence, true, Vector3.ZERO, 0.12)
	# the yard's east fence south of Main St carries on down to the town's south edge
	_b(self, Vector3(X0, y, (60.6 + Z1) * 0.5), Vector3(0.18, 1.68, Z1 - 60.6), fence, true, Vector3.ZERO, 0.12)

# ====================================================================== roads
func _roads() -> void:
	# east-west: [z, x0, x1]   north-south: [x, z0, z1]
	var ew := [[53.0, 44.0, 200.0], [0.0, 86.0, 200.0], [106.0, 86.0, 200.0]]
	var ns := [[90.0, -4.0, 110.0], [150.0, -4.0, 110.0], [196.0, -4.0, 110.0]]
	for r in ew:
		var z: float = r[0]
		_flat(r[1], z - ROAD_HALF, r[2], z + ROAD_HALF, 0.016, _m_asphalt)
	for r2 in ns:
		var x: float = r2[0]
		_flat(x - ROAD_HALF, r2[1], x + ROAD_HALF, r2[2], 0.017, _m_asphalt)
	var xs := [90.0, 150.0, 196.0]
	var zs := [0.0, 53.0, 106.0]
	# dashed middle lines (not across the junctions)
	for r3 in ew:
		var z3: float = r3[0]
		var x := float(r3[1]) + 2.0
		while x < float(r3[2]) - 2.0:
			var near_junction := false
			for jx in xs:
				if absf(x - float(jx)) < ROAD_HALF + 1.5:
					near_junction = true
			if not near_junction:
				_flat(x - 1.0, z3 - 0.08, x + 1.0, z3 + 0.08, 0.022, _m_yellow)
			x += 4.0
	for r4 in ns:
		var x4: float = r4[0]
		var z4 := float(r4[1]) + 2.0
		while z4 < float(r4[2]) - 2.0:
			var near := false
			for jz in zs:
				if absf(z4 - float(jz)) < ROAD_HALF + 1.5:
					near = true
			if not near:
				_flat(x4 - 0.08, z4 - 1.0, x4 + 0.08, z4 + 1.0, 0.022, _m_yellow)
			z4 += 4.0
	# zebra crossings on every road leaving a junction
	for ni in range(1, road_nodes.size()):
		var c := road_nodes[ni]
		for nb in road_links[ni]:
			var dir := (road_nodes[int(nb)] - c)
			dir.y = 0.0
			dir = dir.normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			for k in 6:
				var cp := c + dir * (ROAD_HALF + 1.4) + side * (-2.6 + k * 1.05)
				var ext := dir.abs() * 1.0 + side.abs() * 0.25
				_flat(cp.x - ext.x, cp.z - ext.z, cp.x + ext.x, cp.z + ext.z, 0.023, _m_line)
	# street name signs at the junctions
	var names_ew := {0.0: "North Rd", 53.0: "Main St", 106.0: "South Rd"}
	var names_ns := {90.0: "Oak Ave", 150.0: "Elm Ave", 196.0: "Bay Ave"}
	for jx3 in xs:
		for jz3 in zs:
			var p := Vector3(float(jx3) + ROAD_HALF + 0.8, 0.0, float(jz3) - ROAD_HALF - 0.8)
			_abox(p + Vector3(0, 1.4, 0), Vector3(0.08, 2.8, 0.08), _m_pole, true)
			_abox(p + Vector3(0, 2.75, 0), Vector3(0.05, 0.3, 1.6), Mats.solid(Color(0.1, 0.45, 0.25), 0.6))
			_abox(p + Vector3(0, 2.4, 0), Vector3(1.6, 0.3, 0.05), Mats.solid(Color(0.1, 0.45, 0.25), 0.6))
			_sign(str(names_ew[jz3]), p + Vector3(0, 2.75, 0), Vector3.RIGHT, 24)
			_sign(str(names_ew[jz3]), p + Vector3(0, 2.75, 0), Vector3.LEFT, 24)
			_sign(str(names_ns[jx3]), p + Vector3(0, 2.4, 0), Vector3.BACK, 24)
			_sign(str(names_ns[jx3]), p + Vector3(0, 2.4, 0), Vector3.FORWARD, 24)

# ===================================================================== blocks
## One side of a block with buildings along it. rect = the block's pavement area (inside the roads).
## side: "n" (faces -Z), "s" (+Z), "w" (-X), "e" (+X). Returns nothing; fills addresses.
func _row(rect: Rect2, side: String, street: String, depth_lo: float, depth_hi: float, kinds: Array, inset0 := 0.0, inset1 := 0.0, start_no := 1) -> void:
	var f := Vector3.ZERO
	var a := 0.0
	var b := 0.0
	match side:
		"n":
			f = Vector3.FORWARD
			a = rect.position.x + inset0
			b = rect.end.x - inset1
		"s":
			f = Vector3.BACK
			a = rect.position.x + inset0
			b = rect.end.x - inset1
		"w":
			f = Vector3.LEFT
			a = rect.position.y + inset0
			b = rect.end.y - inset1
		"e":
			f = Vector3.RIGHT
			a = rect.position.y + inset0
			b = rect.end.y - inset1
	var t := a
	var no := start_no
	var ki := 0
	while t < b - 6.0:
		var w := _rng.randf_range(9.0, 15.0)
		if b - (t + w) < 7.0:
			w = b - t
		var kind: String = kinds[ki % kinds.size()] if not kinds.is_empty() else "shop"
		if kind == "gap":
			t += _rng.randf_range(3.0, 5.0)
			ki += 1
			continue
		var d := _rng.randf_range(depth_lo, depth_hi)
		var mid := t + w * 0.5
		var front := Vector3.ZERO
		match side:
			"n":
				front = Vector3(mid, 0.0, rect.position.y + SETBACK)
			"s":
				front = Vector3(mid, 0.0, rect.end.y - SETBACK)
			"w":
				front = Vector3(rect.position.x + SETBACK, 0.0, mid)
			"e":
				front = Vector3(rect.end.x - SETBACK, 0.0, mid)
		_building(front, f, w - 0.6, d, kind, "%d %s" % [no, street])
		no += 2
		t += w
		ki += 1

## A building whose front wall's middle is at `front` (ground level), facing f (unit, horizontal).
func _building(front: Vector3, f: Vector3, w: float, d: float, kind: String, address: String) -> void:
	var right := Vector3.UP.cross(f)   # building's +X when you face its front from the street
	var xf := Transform3D(Basis(right, Vector3.UP, f), front)
	var floors := 1
	var h := 4.0
	var wall: Material = _walls[_rng.randi() % _walls.size()]
	var trim: Material = _trims[_rng.randi() % _trims.size()]
	var shop_front := true
	var sign_text := ""
	var sign_col := Color(1.0, 0.95, 0.8)
	match kind:
		"house":
			floors = _rng.randi_range(1, 2)
			h = 3.0 * floors + 0.4
			shop_front = false
		"tower":
			floors = _rng.randi_range(4, 6)
			h = 3.2 * floors + 0.6
			shop_front = _rng.randf() < 0.5
		"office":
			floors = _rng.randi_range(2, 4)
			h = 3.2 * floors + 0.6
			shop_front = _rng.randf() < 0.6
		_:
			floors = _rng.randi_range(1, 3)
			h = 3.4 * floors + 0.6
	if kind.begins_with("sign:"):
		sign_text = kind.substr(5)
	# body (solid), plinth and cornice
	_box(xf * Transform3D(Basis(), Vector3(0, h * 0.5, -d * 0.5)), Vector3(w, h, d), wall, true)
	_box(xf * Transform3D(Basis(), Vector3(0, 0.3, 0.03)), Vector3(w + 0.06, 0.6, 0.1), _m_dark)
	_box(xf * Transform3D(Basis(), Vector3(0, h + 0.15, -d * 0.5)), Vector3(w + 0.3, 0.3, d + 0.3), trim)
	# roof junk
	if kind != "house":
		for k in _rng.randi_range(1, 3):
			var rp := Vector3(_rng.randf_range(-w * 0.35, w * 0.35), h + 0.6, -_rng.randf_range(d * 0.3, d * 0.7))
			_box(xf * Transform3D(Basis(), rp), Vector3(1.4, 0.9, 1.2), Mats.solid(Color(0.7, 0.72, 0.74), 0.5, 0.4))
	else:
		# a pitched roof
		var pitch := 0.55
		var half_d := d * 0.5 + 0.4
		var slope_len := half_d / cos(pitch)
		var roof_m := Mats.textured("shingles", [Color(0.55, 0.25, 0.2), Color(0.3, 0.32, 0.38), Color(0.4, 0.3, 0.25)][_rng.randi() % 3], 1.2)
		for s in [-1.0, 1.0]:
			var rb := Basis(Vector3.RIGHT, float(s) * pitch)
			var c := Vector3(0, h + 0.2 + tan(pitch) * half_d * 0.5, -d * 0.5 + float(s) * half_d * 0.5)
			_box(xf * Transform3D(rb, c), Vector3(w + 0.5, 0.15, slope_len), roof_m)
		_box(xf * Transform3D(Basis(), Vector3(0, h + 0.2 + tan(pitch) * half_d * 0.45, -d * 0.5)), Vector3(w - 0.1, tan(pitch) * half_d * 0.9, d - 0.2), wall)
	# upper floor windows
	var first := 1 if shop_front else 0
	var win_w := 1.2
	var n_win := maxi(1, int((w - 1.2) / 2.6))
	var span := (n_win - 1) * 2.6
	for fl in range(first, floors):
		var y: float = 1.2 + fl * (h - 0.6) / floors + 0.4
		for i in n_win:
			var x := -span * 0.5 + i * 2.6
			if kind == "house" and fl == 0 and absf(x) < 1.4:
				continue   # the front door goes here
			_box(xf * Transform3D(Basis(), Vector3(x, y, 0.02)), Vector3(win_w + 0.16, 1.56, 0.06), _m_frame)
			_box(xf * Transform3D(Basis(), Vector3(x, y, 0.05)), Vector3(win_w, 1.4, 0.04), _m_glass)
			_box(xf * Transform3D(Basis(), Vector3(x, y - 0.8, 0.1)), Vector3(win_w + 0.3, 0.08, 0.16), _m_frame)
	# side windows (the visible ends of the building)
	for sx in [-1.0, 1.0]:
		for fl2 in range(first, floors):
			var y2: float = 1.2 + fl2 * (h - 0.6) / floors + 0.4
			for j in maxi(1, int((d - 2.0) / 3.0)):
				var z := -1.5 - j * 3.0
				if z < -d + 1.0:
					break
				_box(xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx * (w * 0.5 + 0.03), y2, z)), Vector3(1.2, 1.4, 0.05), _m_glass)
	# ground floor: shop window + door + awning, or a house's front door and steps
	var door_x := 0.0
	if shop_front:
		var ww := w - 3.0
		door_x = w * 0.5 - 1.2
		_box(xf * Transform3D(Basis(), Vector3(-0.9, 1.75, 0.03)), Vector3(ww, 2.3, 0.08), _m_frame)
		_box(xf * Transform3D(Basis(), Vector3(-0.9, 1.75, 0.06)), Vector3(ww - 0.2, 2.1, 0.05), _m_glass)
		var aw: Material = _awnings[_rng.randi() % _awnings.size()]
		_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 3.3, 0.75)), Vector3(w - 0.4, 0.08, 1.6), aw)
		_box(xf * Transform3D(Basis(), Vector3(0, 3.05, 1.48)), Vector3(w - 0.4, 0.3, 0.05), aw)
		if sign_text != "":
			_box(xf * Transform3D(Basis(), Vector3(0, minf(h - 0.6, 4.6), 0.1)), Vector3(minf(w - 1.0, sign_text.length() * 0.62 + 1.2), 0.95, 0.12), Mats.solid(Color(0.12, 0.12, 0.14), 0.6))
			_sign(sign_text, xf * Vector3(0, minf(h - 0.6, 4.6), 0.18), f, 72, sign_col, Color(0.6, 0.1, 0.05))
	else:
		_box(xf * Transform3D(Basis(), Vector3(0, 0.12, 0.6)), Vector3(2.0, 0.24, 1.2), _m_pave)
	_box(xf * Transform3D(Basis(), Vector3(door_x, 1.1, 0.04)), Vector3(1.15, 2.2, 0.1), _m_door)
	_box(xf * Transform3D(Basis(), Vector3(door_x + 0.38, 1.05, 0.11)), Vector3(0.06, 0.06, 0.06), Mats.solid(Color(0.85, 0.75, 0.4), 0.3, 0.8))
	# house number over the door
	var num := address.get_slice(" ", 0)
	_sign(num, xf * Vector3(door_x, 2.5, 0.12), f, 40, Color(1, 1, 1), Color(0.1, 0.1, 0.1))
	var door_world := xf * Vector3(door_x, 0.0, 0.0)
	addresses.append({"name": address, "door": door_world, "pos": door_world + f * 1.6, "facing": f})

func _lot_lines(x0: float, z0: float, x1: float, z1: float, along_x: bool, spacing: float) -> void:
	if along_x:
		var x := x0
		while x <= x1 + 0.01:
			_flat(x - 0.06, z0, x + 0.06, z1, 0.03, _m_line)
			x += spacing
	else:
		var z := z0
		while z <= z1 + 0.01:
			_flat(x0, z - 0.06, x1, z + 0.06, 0.03, _m_line)
			z += spacing

func _blocks() -> void:
	# block pavements (between the road edges)
	var A := Rect2(94, 4, 52, 45)
	var B := Rect2(154, 4, 38, 45)
	var C := Rect2(94, 57, 52, 45)
	var D := Rect2(154, 57, 38, 45)
	var W1 := Rect2(X0 + 0.2, Z0, 86.0 - X0 - 0.2, 49.0 - Z0)
	var W2 := Rect2(X0 + 0.2, 57, 86.0 - X0 - 0.2, Z1 - 57.0)
	for r in [A, B, C, D]:
		var rr: Rect2 = r
		_flat(rr.position.x, rr.position.y, rr.end.x, rr.end.y, 0.03, _m_pave)
		_flat(rr.position.x + 8.0, rr.position.y + 8.0, rr.end.x - 8.0, rr.end.y - 8.0, 0.035, _m_grass)   # back yards
	# edge strips (outside the outer roads)
	_flat(86.0, Z0, X1, -4.0, 0.03, _m_pave)
	_flat(86.0, 110.0, X1, Z1, 0.03, _m_pave)
	_flat(200.0, -4.0, X1, 110.0, 0.03, _m_pave)
	_flat(W2.position.x, W2.position.y, W2.end.x, W2.end.y, 0.025, _m_grass)
	_flat(81.5, 57.0, 86.0, Z1, 0.03, _m_pave)       # W2's pavements along Oak Ave and Main St
	_flat(W2.position.x, 57.0, 86.0, 61.5, 0.031, _m_pave)

	# ---- A: Wobbly Jobs on the Main St corner, shops, offices
	_row(A, "s", "Main St", 10.0, 13.0, ["sign:WOBBLY JOBS", "sign:BURGER BARN", "office", "sign:LAUNDROMAT"], 0.0, 0.0, 101)
	_row(A, "n", "North Rd", 10.0, 13.0, ["tower", "gap", "office", "sign:BANK", "tower"], 0.0, 0.0, 2)
	_row(A, "w", "Oak Ave", 9.0, 11.0, ["shop", "office"], 19.0, 19.0, 10)
	_row(A, "e", "Elm Ave", 9.0, 11.0, ["sign:ARCADE", "gap", "office"], 19.0, 19.0, 11)
	# ---- B: the police station on Main St
	_row(B, "s", "Main St", 12.0, 13.0, ["sign:POLICE", "sign:HOTEL"], 0.0, 0.0, 201)
	_row(B, "n", "North Rd", 10.0, 12.0, ["office", "tower", "office"], 0.0, 0.0, 30)
	_row(B, "e", "Bay Ave", 9.0, 10.0, ["office", "gap", "shop"], 19.0, 19.0, 21)
	# ---- C: Pizza Palace facing Main St, flats behind
	_row(C, "n", "Main St", 10.0, 13.0, ["sign:PIZZA PALACE", "shop", "sign:BARBER", "office"], 0.0, 0.0, 102)
	_row(C, "s", "South Rd", 10.0, 12.0, ["tower", "office", "gap", "tower"], 0.0, 0.0, 3)
	_row(C, "w", "Oak Ave", 9.0, 11.0, ["house", "house"], 19.0, 19.0, 60)
	_row(C, "e", "Elm Ave", 9.0, 11.0, ["shop", "gap", "house"], 19.0, 19.0, 61)
	# ---- D: shops and houses
	_row(D, "n", "Main St", 10.0, 12.0, ["sign:PAWN SHOP", "sign:DINER", "shop"], 0.0, 0.0, 202)
	_row(D, "s", "South Rd", 9.0, 11.0, ["house", "house", "house"], 0.0, 0.0, 40)
	_row(D, "e", "Bay Ave", 9.0, 10.0, ["house", "gap", "house"], 19.0, 19.0, 70)
	# ---- W2: houses along Oak Ave and Main St
	_row(W2, "e", "Oak Ave", 9.0, 11.0, ["house", "house", "gap", "house", "house", "house"], 2.0, 4.0, 80)
	_row(W2, "n", "Main St", 9.0, 11.0, ["house", "gap", "house"], 2.0, 16.0, 150)

	# ---- W1: the parking lot with the Chop Shop at the back
	_flat(W1.position.x, W1.position.y, W1.end.x, W1.end.y, 0.03, _m_lot)
	_lot_lines(56.0, 14.0, 82.0, 19.0, true, 3.0)
	_lot_lines(56.0, 30.0, 82.0, 35.0, true, 3.0)
	for i in 8:
		parking.append({"pos": Vector3(57.5 + i * 3.0, 0.0, 16.5), "yaw": 0.0})
		parking.append({"pos": Vector3(57.5 + i * 3.0, 0.0, 32.5), "yaw": PI})
	# chop shop: a garage with a big open door, sign, oil stains
	var g := Transform3D(Basis(Vector3.UP.cross(Vector3.BACK), Vector3.UP, Vector3.BACK), Vector3(60.0, 0.0, 4.0))
	var gw := 16.0
	var gd := 12.0
	var gh := 6.0
	var corr := Mats.textured("stripes", Color(0.55, 0.6, 0.62), 0.8)
	_box(g * Transform3D(Basis(), Vector3(-gw * 0.5 + 0.2, gh * 0.5, -gd * 0.5)), Vector3(0.4, gh, gd), corr, true)
	_box(g * Transform3D(Basis(), Vector3(gw * 0.5 - 0.2, gh * 0.5, -gd * 0.5)), Vector3(0.4, gh, gd), corr, true)
	_box(g * Transform3D(Basis(), Vector3(0, gh * 0.5, -gd + 0.2)), Vector3(gw, gh, 0.4), corr, true)
	_box(g * Transform3D(Basis(), Vector3(0, gh + 0.15, -gd * 0.5)), Vector3(gw + 0.4, 0.3, gd + 0.4), _m_dark, true)
	_box(g * Transform3D(Basis(), Vector3(-gw * 0.5 + 1.6, gh * 0.5 + 1.5, -0.1)), Vector3(3.0, gh - 3.0, 0.3), corr, true)
	_box(g * Transform3D(Basis(), Vector3(gw * 0.5 - 1.6, gh * 0.5 + 1.5, -0.1)), Vector3(3.0, gh - 3.0, 0.3), corr, true)
	_box(g * Transform3D(Basis(), Vector3(0, gh - 0.75, -0.1)), Vector3(gw, 1.5, 0.3), corr, true)
	_box(g * Transform3D(Basis(), Vector3(0, gh - 0.75, 0.08)), Vector3(9.0, 1.1, 0.1), Mats.solid(Color(0.12, 0.12, 0.12), 0.6))
	_sign("CHOP SHOP", g * Vector3(0, gh - 0.75, 0.15), Vector3.BACK, 96, Color(1.0, 0.75, 0.2), Color(0.3, 0.1, 0.0))
	_sign("no questions asked", g * Vector3(0, gh - 1.45, 0.15), Vector3.BACK, 32, Color(0.9, 0.9, 0.9))
	for k in 5:
		_flat(52.0 + k * 3.2, -6.0 + (k % 2) * 2.5, 53.5 + k * 3.2, -4.6 + (k % 2) * 2.5, 0.033, Mats.solid(Color(0.08, 0.08, 0.09), 0.3))
	for k2 in 3:   # tyre stacks and a workbench inside
		_abox(Vector3(54.0 + k2 * 1.2, 0.45, -5.5), Vector3(0.9, 0.9, 0.9), Mats.solid(Color(0.07, 0.07, 0.08), 0.9), true)
	_abox(Vector3(66.0, 0.5, -6.5), Vector3(3.0, 1.0, 1.0), Mats.textured("planks", Color(0.7, 0.55, 0.4), 0.6), true)
	chop_shop = Vector3(60.0, 0.0, 0.0)
	_flat(55.0, -3.0, 65.0, 4.0, 0.034, Mats.solid(Color(0.75, 0.6, 0.1), 0.6))   # yellow drop-off box
	_flat(55.4, -2.6, 64.6, 3.6, 0.035, _m_lot)
	# lot booth + sign at the entrance
	_abox(Vector3(79.0, 1.3, 24.0), Vector3(2.2, 2.6, 2.2), _walls[3], true)
	_abox(Vector3(79.0, 2.75, 24.0), Vector3(2.6, 0.3, 2.6), _trims[1])
	_sign("PARKING", Vector3(80.15, 2.0, 24.0), Vector3.RIGHT, 48, Color(1, 1, 1))

	# ---- points of interest (in front of their buildings)
	for ad in addresses:
		var nm := str(ad["name"])
		var fc: Vector3 = ad["facing"]
		var rt := Vector3.UP.cross(fc)
		if nm == "101 Main St":
			job_board = (ad["door"] as Vector3) + fc * 1.0 - rt * 2.6
		elif nm == "102 Main St":
			pizza_counter = (ad["door"] as Vector3) + fc * 0.8 - rt * 2.6
		elif nm == "201 Main St":
			police_station = (ad["pos"] as Vector3)
	_job_board(job_board)
	_pizza_stand(pizza_counter, Vector3.FORWARD)
	# special buildings don't take deliveries
	var keep: Array = []
	for ad2 in addresses:
		var n2 := str(ad2["name"])
		if n2 != "101 Main St" and n2 != "102 Main St" and n2 != "201 Main St":
			keep.append(ad2)
	addresses = keep
	# police parking in front of the station
	parking.append({"pos": police_station + Vector3(-4.0, 0.0, 2.0), "yaw": PI * 0.5, "kind": "police"})
	parking.append({"pos": police_station + Vector3(4.0, 0.0, 2.0), "yaw": PI * 0.5, "kind": "police"})

	# ---- people walk round every block, along the pavement between parked cars and shop fronts
	for r2 in [A, B, C, D]:
		var q: Rect2 = r2
		var i0 := 3.0
		walk_paths.append({"loop": true, "pts": [
			Vector3(q.position.x + i0, 0, q.position.y + i0), Vector3(q.end.x - i0, 0, q.position.y + i0),
			Vector3(q.end.x - i0, 0, q.end.y - i0), Vector3(q.position.x + i0, 0, q.end.y - i0)]})
	walk_paths.append({"loop": false, "pts": [Vector3(83.0, 0, -6.0), Vector3(83.0, 0, 46.0), Vector3(48.0, 0, 46.0)]})
	walk_paths.append({"loop": false, "pts": [Vector3(48.0, 0, 60.0), Vector3(83.0, 0, 60.0), Vector3(83.0, 0, 111.0)]})
	walk_paths.append({"loop": false, "pts": [Vector3(-30.0, 0, 59.5), Vector3(40.0, 0, 59.5)]})   # the shop's side of the street

func _job_board(p: Vector3) -> void:
	var f := Vector3.BACK
	_abox(p + Vector3(-1.1, 1.1, 0), Vector3(0.12, 2.2, 0.12), _m_pole, true)
	_abox(p + Vector3(1.1, 1.1, 0), Vector3(0.12, 2.2, 0.12), _m_pole, true)
	_abox(p + Vector3(0, 1.55, 0), Vector3(2.4, 1.3, 0.1), Mats.textured("planks", Color(0.7, 0.5, 0.32), 0.6), true)
	for k in 6:   # pinned job notes
		var nx := -0.85 + (k % 3) * 0.85
		var ny := 1.85 - (k / 3) * 0.55
		_abox(p + Vector3(nx, ny, 0.07), Vector3(0.5, 0.38, 0.02), Mats.solid([Color(1, 1, 0.85), Color(0.85, 0.95, 1), Color(1, 0.9, 0.9)][k % 3], 0.9))
	_sign("JOB BOARD", p + Vector3(0, 2.45, 0.06), f, 40, Color(1.0, 0.95, 0.5))
	_sign("press F", p + Vector3(0, 0.75, 0.06), f, 24, Color(1, 1, 1))

## The pizza counter: p = its middle on the ground, f = the way it faces (towards the street).
func _pizza_stand(p: Vector3, f: Vector3) -> void:
	var red := Mats.solid(Color(0.8, 0.15, 0.12), 0.6)
	var along := Vector3.UP.cross(f).abs()
	_abox(p + Vector3(0, 0.55, 0), along * 2.2 + f.abs() * 0.7 + Vector3(0, 1.1, 0), red, true)
	_abox(p + Vector3(0, 1.13, 0), along * 2.4 + f.abs() * 0.9 + Vector3(0, 0.06, 0), _m_frame)
	for k in 3:
		_abox(p + along * (-0.6 + k * 0.6) + Vector3(0, 1.2, 0), Vector3(0.45, 0.06, 0.45), Mats.solid(Color(0.85, 0.7, 0.45), 0.8))
	_sign("PIZZA PICK-UP", p + Vector3(0, 1.7, 0) + f * 0.3, f, 32, Color(1, 0.9, 0.5))
	pizza_counter = p + f * 1.0

# ============================================================ street furniture
func _street_furniture() -> void:
	# street lights every ~24 m on both sides of every road
	var spots: Array[Vector3] = []
	for x in range(100, 196, 24):
		spots.append(Vector3(x, 0, 53.0 - ROAD_HALF - 0.6))
		spots.append(Vector3(x + 12, 0, 53.0 + ROAD_HALF + 0.6))
		spots.append(Vector3(x, 0, -ROAD_HALF - 0.6))
		spots.append(Vector3(x + 12, 0, 106.0 + ROAD_HALF + 0.6))
	for z in range(10, 104, 24):
		for ax in [90.0, 150.0, 196.0]:
			spots.append(Vector3(ax + ROAD_HALF + 0.6, 0, z))
			spots.append(Vector3(ax - ROAD_HALF - 0.6, 0, z + 12))
	for x2 in range(52, 86, 16):
		spots.append(Vector3(x2, 0, 53.0 - ROAD_HALF - 0.6))
		spots.append(Vector3(x2 + 8, 0, 53.0 + ROAD_HALF + 0.6))
	var lit := 0
	for s in spots:
		var p: Vector3 = s
		if _on_road(p, 0.3):
			continue
		# arm reaches out over the road: find which road is nearest
		var arm := _towards_road(p)
		_abox(p + Vector3(0, 2.4, 0), Vector3(0.14, 4.8, 0.14), _m_pole, true)
		_abox(p + Vector3(0, 4.8, 0) + arm * 0.5, Vector3(0.1, 0.08, 0.1) + arm.abs() * 0.9, _m_pole)
		_abox(p + Vector3(0, 4.7, 0) + arm * 0.95, Vector3(0.36, 0.12, 0.36), _m_lamp)
		lit += 1
		if lit % 4 == 0:
			_light(p + Vector3(0, 4.4, 0) + arm, Color(1.0, 0.9, 0.7), 1.0, 12.0)
	# trees on the pavements where nobody parks
	var tree_spots := [Vector3(100, 0, 5.2), Vector3(122, 0, 5.2), Vector3(140, 0, 5.2), Vector3(160, 0, 5.2), Vector3(184, 0, 5.2),
		Vector3(100, 0, 100.8), Vector3(120, 0, 100.8), Vector3(140, 0, 100.8), Vector3(160, 0, 100.8), Vector3(184, 0, 100.8),
		Vector3(95.2, 0, 28), Vector3(144.8, 0, 82), Vector3(155.2, 0, 28), Vector3(190.8, 0, 82),
		Vector3(52, 0, 88), Vector3(60, 0, 100), Vector3(66, 0, 84), Vector3(50, 0, 108), Vector3(120, 0, 112), Vector3(170, 0, 112),
		Vector3(120, 0, -7), Vector3(176, 0, -7), Vector3(202, 0, 30), Vector3(202, 0, 80)]
	for t in tree_spots:
		var g := _g(t)
		_m("tree" if _rng.randf() < 0.7 else "pine_tree", Vector3.ZERO, _rng.randf_range(0.0, 360.0), _rng.randf_range(0.9, 1.3), g)
		_solid_cyl(g, Vector3(0, 1.5, 0), 0.26, 3.0)
	# benches, bins and hydrants along Main St
	for x3 in [118.0, 136.0, 168.0, 184.0]:
		for side in [-1.0, 1.0]:
			var z3: float = 53.0 + side * (ROAD_HALF + 4.3)
			var g2 := _g(Vector3(x3, 0, z3), 0.0 if side < 0 else 180.0)
			_m("bench", Vector3.ZERO, 0.0, 1.0, g2)
			_solid(g2, Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 0.5))
			_abox(Vector3(x3 + 2.0, 0.45, z3), Vector3(0.5, 0.9, 0.5), Mats.solid(Color(0.2, 0.35, 0.25), 0.7), true)
	for hp in [Vector3(96, 0, 47.6), Vector3(156, 0, 58.4), Vector3(144, 0, 5.4), Vector3(190, 0, 100.6)]:
		_abox(hp + Vector3(0, 0.4, 0), Vector3(0.3, 0.8, 0.3), Mats.solid(Color(0.85, 0.12, 0.1), 0.5), true)
		_abox(hp + Vector3(0, 0.82, 0), Vector3(0.4, 0.12, 0.4), Mats.solid(Color(0.85, 0.12, 0.1), 0.5))
	# welcome sign by the town entrance
	_abox(Vector3(48.0, 1.6, 45.0), Vector3(0.15, 3.2, 0.15), _m_pole, true)
	_abox(Vector3(52.0, 1.6, 45.0), Vector3(0.15, 3.2, 0.15), _m_pole, true)
	_abox(Vector3(50.0, 2.7, 45.0), Vector3(4.6, 1.4, 0.15), Mats.solid(Color(0.15, 0.45, 0.3), 0.6), true)
	_sign("WOBBLYTOWN", Vector3(50.0, 2.9, 45.1), Vector3.BACK, 56, Color(1, 1, 0.9))
	_sign("pop. wobbly", Vector3(50.0, 2.4, 45.1), Vector3.BACK, 28, Color(0.9, 0.95, 0.9))

## Is p on a road surface (with a margin)?
func _on_road(p: Vector3, margin := 0.0) -> bool:
	var h := ROAD_HALF + margin
	for r in [[53.0, 44.0, 200.0], [0.0, 86.0, 200.0], [106.0, 86.0, 200.0]]:
		if absf(p.z - float(r[0])) < h and p.x > float(r[1]) - margin and p.x < float(r[2]) + margin:
			return true
	for r2 in [[90.0, -4.0, 110.0], [150.0, -4.0, 110.0], [196.0, -4.0, 110.0]]:
		if absf(p.x - float(r2[0])) < h and p.z > float(r2[1]) - margin and p.z < float(r2[2]) + margin:
			return true
	return false

## Unit vector from a pavement spot towards the road it stands beside.
func _towards_road(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := 1e9
	for z in [0.0, 53.0, 106.0]:
		var d := absf(p.z - float(z))
		if d < best_d:
			best_d = d
			best = Vector3(0, 0, signf(float(z) - p.z))
	for x in [90.0, 150.0, 196.0]:
		var d2 := absf(p.x - float(x))
		if d2 < best_d:
			best_d = d2
			best = Vector3(signf(float(x) - p.x), 0, 0)
	return best

# =================================================================== queries
## Is this point inside the town (east of the yard)?
func contains(p: Vector3) -> bool:
	return p.x > X0 and p.x < X1 and p.z > Z0 and p.z < Z1

## Next junction for a car at `at` that came from `from` (never straight back unless it's a dead end).
func next_road_node(at: int, from: int) -> int:
	var opts: Array = []
	for n in road_links.get(at, []):
		if int(n) != from:
			opts.append(int(n))
	if opts.is_empty():
		return from
	return int(opts[randi() % opts.size()])

## A random spot in a traffic lane: {pos, yaw, route: [from, to]}.
func random_lane_spot() -> Dictionary:
	var a := randi() % road_nodes.size()
	var links: Array = road_links[a]
	var b := int(links[randi() % links.size()])
	var pa := road_nodes[a]
	var pb := road_nodes[b]
	var d := (pb - pa)
	var length := d.length()
	d = d / maxf(length, 0.01)
	var right := Vector3(-d.z, 0.0, d.x)
	var t := randf_range(12.0, maxf(13.0, length - 14.0))
	return {"pos": pa + d * t + right * LANE, "yaw": atan2(-d.x, -d.z), "route": [a, b]}

## A random point on a pavement path (for people), and which path it is on.
func random_walk_spot() -> Dictionary:
	var wi := randi() % walk_paths.size()
	var pts: Array = walk_paths[wi]["pts"]
	var i := randi() % pts.size()
	var j := (i + 1) % pts.size()
	if not bool(walk_paths[wi]["loop"]) and i == pts.size() - 1:
		j = i - 1
	var p: Vector3 = (pts[i] as Vector3).lerp(pts[j] as Vector3, randf())
	return {"pos": p, "path": wi, "wp": j}
