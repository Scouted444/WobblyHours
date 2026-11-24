class_name HouseBuilder
extends Node3D
## Builds the party house from boxes: shell, walls with doors and windows, and furnished
## rooms (living room, kitchen, bedroom, bathroom). The party room and yard live in
## house_full.gd, which extends this class.
##
## Layout (top view, +Z is the front of the house, the front door):
##   back  z=-7 : [ bedroom | bathroom | party room ]
##   front z= 7 : [ living room         | kitchen    ]

const H := 3.0   # wall height
const T := 0.25  # wall thickness
const WALL_BASE := -0.25  # buried in the ground so the capsule cannot snag the wall bottom

var wall_mat: Material
var wood_mat: Material
var trim_mat: Material

func build() -> void:
	wall_mat = Mats.textured("stripes", Color(0.94, 0.9, 0.82), 1.2)
	wood_mat = Mats.textured("planks", Color(0.8, 0.62, 0.45), 0.8)
	trim_mat = Mats.solid(Color(0.96, 0.94, 0.9))
	_shell()
	_living()
	_kitchen()
	_bedroom()
	_bathroom()

# ------------------------------------------------------------------ helpers
func _b(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, collide := true, rot := Vector3.ZERO, sink := 0.08) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation_degrees = rot
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		# Extend the collider down through the floor so feet don't catch the bottom edge.
		if sink > 0.0:
			bs.size.y += sink
			cs.position.y -= sink * 0.5
		cs.shape = bs
		body.add_child(cs)
		body.add_child(mesh)
		parent.add_child(body)
		return body
	mesh.position = pos
	mesh.rotation_degrees = rot
	parent.add_child(mesh)
	return mesh

func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material, collide := false, rot := Vector3.ZERO) -> Node3D:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mesh.mesh = cm
	mesh.material_override = mat
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation_degrees = rot
		var cs := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = r
		s.height = h + 0.08
		cs.position.y = -0.04
		cs.shape = s
		body.add_child(cs)
		body.add_child(mesh)
		parent.add_child(body)
		return body
	mesh.position = pos
	mesh.rotation_degrees = rot
	parent.add_child(mesh)
	return mesh

func _sph(parent: Node3D, pos: Vector3, r: float, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mesh.mesh = sm
	mesh.material_override = mat
	mesh.position = pos
	mesh.scale = scl
	parent.add_child(mesh)
	return mesh

func _g(pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = yaw_deg
	add_child(g)
	return g

func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	add_child(l)
	return l

## A real model (res://models/<name>.glb) placed in the house. Never null, so callers stay simple.
func _m(model_name: String, pos: Vector3, yaw_deg := 0.0, scl := 1.0, parent: Node3D = null) -> Node3D:
	var n := ModelLib.make(model_name)
	if n == null:
		n = Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	if scl != 1.0:
		n.scale = Vector3.ONE * scl
	(parent if parent != null else self).add_child(n)
	return n

## Invisible box collider (the model supplies the looks). Extends down into the floor by `sink`.
func _solid(parent: Node3D, pos: Vector3, size: Vector3, sink := 0.06, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	if sink > 0.0:
		bs.size.y += sink
		cs.position.y -= sink * 0.5
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
	return body

func _solid_cyl(parent: Node3D, pos: Vector3, r: float, h: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h + 0.06
	cs.position.y = -0.03
	cs.shape = s
	body.add_child(cs)
	parent.add_child(body)
	return body

## Ceiling lamp: model plus a light.
func _ceiling_lamp(x: float, z: float, color := Color(1.0, 0.93, 0.8), energy := 1.6) -> void:
	_m("ceiling_lamp", Vector3(x, H - 0.04, z))
	_light(Vector3(x, H - 0.5, z), color, energy, 8.0)

func _floor(x0: float, z0: float, x1: float, z1: float, mat: Material) -> void:
	# Visual only. The yard ground is the single walkable collider, so rooms don't z-fight or snag.
	_b(self, Vector3((x0 + x1) / 2.0, 0.004, (z0 + z1) / 2.0), Vector3(x1 - x0, 0.008, z1 - z0), mat, false)

# -------------------------------------------------------------------- walls
## Splits [a0,a1] around openings into wall pieces: [from, to, y_bottom, y_top].
func _segments(a0: float, a1: float, openings: Array) -> Array:
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p[0] < q[0])
	var segs := []
	var cursor := a0
	for o in ops:
		if o[0] > cursor + 0.02:
			segs.append([cursor, o[0], WALL_BASE, H])
		if o[2] > 0.05:
			segs.append([o[0], o[1], WALL_BASE, o[2]])
		if H - o[3] > 0.02:
			segs.append([o[0], o[1], o[3], H])
		cursor = o[1]
	if cursor < a1 - 0.02:
		segs.append([cursor, a1, WALL_BASE, H])
	return segs

## Wall running along X at depth z. Openings: [x_from, x_to, y_bottom, y_top].
func wall_x(z: float, x0: float, x1: float, openings := []) -> void:
	for s in _segments(x0, x1, openings):
		_b(self, Vector3((s[0] + s[1]) / 2.0, (s[2] + s[3]) / 2.0, z), Vector3(s[1] - s[0], s[3] - s[2], T), wall_mat, true, Vector3.ZERO, 0.0)
	for o in openings:
		_frame_x(z, o)
		if o[2] > 0.05:
			_b(self, Vector3((o[0] + o[1]) / 2.0, (o[2] + o[3]) / 2.0, z), Vector3(o[1] - o[0] + 0.06, o[3] - o[2] + 0.06, 0.06), Mats.glass(), true, Vector3.ZERO, 0.0)

## Wall running along Z at x.
func wall_z(x: float, z0: float, z1: float, openings := []) -> void:
	for s in _segments(z0, z1, openings):
		_b(self, Vector3(x, (s[2] + s[3]) / 2.0, (s[0] + s[1]) / 2.0), Vector3(T, s[3] - s[2], s[1] - s[0]), wall_mat, true, Vector3.ZERO, 0.0)
	for o in openings:
		_frame_z(x, o)
		if o[2] > 0.05:
			_b(self, Vector3(x, (o[2] + o[3]) / 2.0, (o[0] + o[1]) / 2.0), Vector3(0.06, o[3] - o[2] + 0.06, o[1] - o[0] + 0.06), Mats.glass(), true, Vector3.ZERO, 0.0)

func _frame_x(z: float, o: Array) -> void:
	var a: float = o[0]
	var b: float = o[1]
	var c: float = o[2]
	var d: float = o[3]
	var depth := T + 0.08
	_b(self, Vector3((a + b) * 0.5, d + 0.045, z), Vector3(b - a + 0.18, 0.09, depth), trim_mat, false)
	_b(self, Vector3(a - 0.045, (c + d) * 0.5, z), Vector3(0.09, d - c, depth), trim_mat, false)
	_b(self, Vector3(b + 0.045, (c + d) * 0.5, z), Vector3(0.09, d - c, depth), trim_mat, false)
	if c > 0.05:
		_b(self, Vector3((a + b) * 0.5, c - 0.045, z), Vector3(b - a + 0.18, 0.09, depth), trim_mat, false)

func _frame_z(x: float, o: Array) -> void:
	var a: float = o[0]
	var b: float = o[1]
	var c: float = o[2]
	var d: float = o[3]
	var depth := T + 0.08
	_b(self, Vector3(x, d + 0.045, (a + b) * 0.5), Vector3(depth, 0.09, b - a + 0.18), trim_mat, false)
	_b(self, Vector3(x, (c + d) * 0.5, a - 0.045), Vector3(depth, d - c, 0.09), trim_mat, false)
	_b(self, Vector3(x, (c + d) * 0.5, b + 0.045), Vector3(depth, d - c, 0.09), trim_mat, false)
	if c > 0.05:
		_b(self, Vector3(x, c - 0.045, (a + b) * 0.5), Vector3(depth, 0.09, b - a + 0.18), trim_mat, false)

func _door(a: float, b: float) -> Array:
	return [a, b, 0.0, 2.4]

func _window(a: float, b: float) -> Array:
	return [a, b, 0.9, 2.2]

func _shell() -> void:
	# Floors (top of each floor is y = 0)
	_floor(-10, -1, 2, 7, wood_mat)                                                # living
	_floor(-10, -7, -4, -1, Mats.textured("carpet", Color(0.55, 0.65, 0.85), 1.0))  # bedroom
	_floor(-4, -7, 2, -1, Mats.textured("tiles", Color.WHITE, 1.0, 0.3))           # bathroom
	_floor(2, 0.5, 10, 7, Mats.textured("tiles", Color(1.0, 0.95, 0.85), 1.0, 0.3))  # kitchen
	_floor(2, -7, 10, 0.5, Mats.textured("checker", Color.WHITE, 2.0, 0.25))       # party room

	# Ceiling
	_b(self, Vector3(0, H + 0.1, 0), Vector3(20.5, 0.2, 14.5), Mats.solid(Color(0.97, 0.97, 0.95)))

	# Outer walls
	wall_x(7, -10, 10, [_door(-0.9, 0.9), _window(-8, -5), _window(4, 7)])
	wall_x(-7, -10, 10, [_door(5.2, 6.8), _window(-8, -6), [-2.5, -1.0, 1.4, 2.2]])
	wall_z(-10, -7, 7, [_window(1.05, 2.35), _window(-5, -3)])
	wall_z(10, -7, 7, [_window(2.5, 5.5), _window(-5, -2)])
	# Inner walls
	wall_z(2, -7, 7, [_door(2.5, 4.1), _door(-4.5, -2.9)])
	wall_x(-1, -10, 2, [_door(-8.0, -6.4), _door(-1.8, -0.2)])
	wall_z(-4, -7, -1)
	wall_x(0.5, 2, 10, [_door(5.2, 6.8)])
	_roof()

func _roof() -> void:
	var roof := Mats.textured("shingles", Color(0.72, 0.28, 0.2), 1.4, 0.92)
	var fascia := Mats.solid(Color(0.93, 0.9, 0.84))
	_b(self, Vector3(0, H + 0.28, 0), Vector3(22.8, 0.16, 16.8), roof, true, Vector3.ZERO, 0.0)
	_b(self, Vector3(0, H + 0.1, 8.32), Vector3(22.8, 0.32, 0.18), fascia, false)
	_b(self, Vector3(0, H + 0.1, -8.32), Vector3(22.8, 0.32, 0.18), fascia, false)
	_b(self, Vector3(-11.32, H + 0.1, 0), Vector3(0.18, 0.32, 16.8), fascia, false)
	_b(self, Vector3(11.32, H + 0.1, 0), Vector3(0.18, 0.32, 16.8), fascia, false)
	_b(self, Vector3(-7.6, H + 1.05, -5.2), Vector3(0.85, 1.55, 0.85), Mats.textured("concrete", Color(0.62, 0.32, 0.26), 0.8), false)
	_b(self, Vector3(-7.6, H + 1.85, -5.2), Vector3(1.0, 0.12, 1.0), Mats.solid(Color(0.35, 0.18, 0.14)), false)

# ------------------------------------------------------------------ furniture
## Sofa model with simple box colliders. Seats face local -Z.
func _sofa(pos: Vector3, yaw: float, model_name: String, width := 2.4) -> void:
	var g := _g(pos, yaw)
	_m(model_name, Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 0.26, 0), Vector3(width, 0.52, 0.95))
	_solid(g, Vector3(0, 0.8, 0.37), Vector3(width, 0.6, 0.24), 0.0)
	_solid(g, Vector3(-width / 2.0 + 0.14, 0.58, 0), Vector3(0.28, 0.6, 0.95), 0.0)
	_solid(g, Vector3(width / 2.0 - 0.14, 0.58, 0), Vector3(0.28, 0.6, 0.95), 0.0)

func _coffee_table(pos: Vector3, yaw: float) -> void:
	var g := _g(pos, yaw)
	_m("coffee_table", Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 0.42, 0), Vector3(1.3, 0.06, 0.7), 0.0)
	for x in [-1.0, 1.0]:
		_solid(g, Vector3(x * 0.58, 0.2, 0), Vector3(0.07, 0.4, 0.6), 0.0)

func _plant(pos: Vector3) -> void:
	var g := _g(pos)
	_m("plant", Vector3.ZERO, 0.0, 1.0, g)
	_solid_cyl(g, Vector3(0, 0.25, 0), 0.22, 0.5)

func _picture(pos: Vector3, yaw: float, model_name: String) -> void:
	_m(model_name, pos, yaw)

func _bookshelf(pos: Vector3, yaw: float) -> void:
	var g := _g(pos, yaw)  # front faces local -Z
	_m("bookshelf", Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 1.1, 0.0), Vector3(1.6, 2.2, 0.38))

# --------------------------------------------------------------------- rooms
func _living() -> void:
	_ceiling_lamp(-6.0, 1.5)
	_ceiling_lamp(-6.0, 5.0)
	_m("rug_red", Vector3(-5.5, 0.0, 3.6))
	_sofa(Vector3(-3.6, 0, 3.6), 90, "sofa_purple", 2.8)       # faces the TV (-X)
	_sofa(Vector3(-6.0, 0, 6.3), 0, "sofa_blue", 2.0)          # against the front wall, faces the room
	_coffee_table(Vector3(-6.2, 0, 3.6), 90)
	# TV on a stand against the left wall
	var tv := _g(Vector3(-9.62, 0, 3.6), -90)
	_m("tv_unit", Vector3.ZERO, 0.0, 1.0, tv)
	_solid(tv, Vector3(0, 0.3, 0), Vector3(2.4, 0.6, 0.5))
	_solid(tv, Vector3(0, 1.3, 0.0), Vector3(1.9, 1.05, 0.1), 0.0)
	_light(Vector3(-8.2, 1.3, 3.6), Color(0.4, 0.6, 1.0), 0.8, 5.0)
	_bookshelf(Vector3(-9.68, 0, 0.2), -90)
	_bookshelf(Vector3(-9.68, 0, 6.0), -90)
	var lamp := _g(Vector3(-3.0, 0, 6.4))
	_m("floor_lamp", Vector3.ZERO, 0.0, 1.0, lamp)
	_solid_cyl(lamp, Vector3(0, 0.8, 0), 0.18, 1.6)
	_light(Vector3(-3.0, 1.6, 6.4), Color(1.0, 0.85, 0.55), 1.0, 5.0)
	_plant(Vector3(1.4, 0, 6.2))
	_plant(Vector3(-9.2, 0, -0.3))
	_picture(Vector3(-4.0, 1.7, 6.84), 0, "painting_sun")
	_picture(Vector3(-4.2, 1.7, -0.86), 180, "painting_waves")
	_picture(Vector3(1.86, 1.7, 5.5), 90, "painting_dots")

func _kitchen() -> void:
	_ceiling_lamp(4.5, 2.8, Color(1.0, 1.0, 0.95))
	_ceiling_lamp(7.5, 5.0, Color(1.0, 1.0, 0.95))
	# counter run along the right wall: base cabinets + wall cabinets
	var g := _g(Vector3(9.375, 0, 4.2), 90)
	_m("counter_run", Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 0.46, 0), Vector3(4.8, 0.92, 1.0))
	_solid(g, Vector3(0, 2.0, 0.3), Vector3(4.8, 0.8, 0.4), 0.0)
	# fridge
	var f := _g(Vector3(9.4, 0, 1.2), 90)
	_m("fridge", Vector3.ZERO, 0.0, 1.0, f)
	_solid(f, Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0.9))
	# island with stools
	var isl := _g(Vector3(5.5, 0, 4.2))
	_m("kitchen_island", Vector3.ZERO, 0.0, 1.0, isl)
	_solid(isl, Vector3(0, 0.45, 0), Vector3(2.2, 0.9, 0.8))
	_solid(isl, Vector3(0, 0.93, 0), Vector3(2.4, 0.06, 1.0), 0.0)
	for x in [4.8, 5.5, 6.2]:
		var st := _g(Vector3(x, 0, 5.2))
		_m("stool", Vector3.ZERO, 0.0, 1.0, st)
		_solid_cyl(st, Vector3(0, 0.31, 0), 0.2, 0.62)
	_plant(Vector3(2.7, 0, 6.3))

func _bedroom() -> void:
	_ceiling_lamp(-7.0, -4.0, Color(1.0, 0.85, 0.7), 1.2)
	var g := _g(Vector3(-8.0, 0, -5.6))
	_m("bed", Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 0.37, 0.02), Vector3(2.0, 0.74, 2.3))
	_solid(g, Vector3(0, 0.65, -1.14), Vector3(2.0, 1.3, 0.12), 0.0)
	var ns := _g(Vector3(-9.45, 0, -4.4), -90)
	_m("nightstand", Vector3.ZERO, 0.0, 1.0, ns)
	_solid(ns, Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5))
	var wr := _g(Vector3(-4.44, 0, -3.6), 90)
	_m("wardrobe", Vector3.ZERO, 0.0, 1.0, wr)
	_solid(wr, Vector3(0, 1.1, 0), Vector3(1.6, 2.2, 0.6))
	_m("bathmat", Vector3(-7.6, 0.0, -3.0))     # rug beside the bed
	_retro_pc(Vector3(-5.2, 0, -1.55), 0)   # the 1995 computer (press F near it)
	_picture(Vector3(-9.84, 1.8, -6.0), -90, "painting_shape")

func _bathroom() -> void:
	_ceiling_lamp(-1.0, -4.0, Color(1.0, 1.0, 1.0), 1.4)
	var t := _g(Vector3(-3.3, 0, -6.4), 180)  # tank against the back wall, faces the room
	_m("toilet", Vector3.ZERO, 0.0, 1.0, t)
	_solid(t, Vector3(0, 0.2, -0.04), Vector3(0.4, 0.4, 0.52))
	_solid(t, Vector3(0, 0.65, 0.23), Vector3(0.4, 0.5, 0.2), 0.0)
	var tub := _g(Vector3(0.7, 0, -5.7))
	_m("bathtub", Vector3.ZERO, 0.0, 1.0, tub)
	_solid(tub, Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 2.4))
	var v := _g(Vector3(-1.2, 0, -6.6), 180)
	_m("vanity", Vector3.ZERO, 0.0, 1.0, v)
	_solid(v, Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.5))
	_m("bathmat", Vector3(-2.0, 0.0, -3.0), 0.0)

## A beige 1995 desktop on a desk. Group "retro_pc" marks it for the F key.
func _retro_pc(pos: Vector3, yaw: float) -> void:
	var g := _g(pos, yaw)
	g.add_to_group("retro_pc")
	_m("retro_pc", Vector3.ZERO, 0.0, 1.0, g)
	_solid(g, Vector3(0, 0.75, 0), Vector3(1.6, 0.05, 0.7), 0.0)
	for x in [-0.74, 0.74]:
		_solid(g, Vector3(x, 0.37, 0), Vector3(0.05, 0.74, 0.62))
	_solid(g, Vector3(0.98, 0.26, 0.05), Vector3(0.22, 0.52, 0.46))
	_solid(g, Vector3(0.0, 0.33, -0.85), Vector3(0.5, 0.66, 0.5), 0.0)   # chair
	var label := Label3D.new()
	label.text = "WOBBLY 95\nC:\\>_"
	label.font_size = 44
	label.pixel_size = 0.0016
	label.modulate = Color(0.75, 1.0, 0.85)
	label.rotation_degrees = Vector3(0, 180, 0)
	label.position = Vector3(0, 1.09, -0.123)
	label.shaded = false
	g.add_child(label)
	_light(g.to_global(Vector3(0, 1.05, -0.6)), Color(0.4, 0.8, 1.0), 0.5, 2.5)
