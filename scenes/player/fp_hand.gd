class_name FpHand
extends Node3D
## A blocky first-person hand: a palm, four fingers with three joints each and a two-joint thumb.
## Hand space: +Y runs toward the fingertips, -X is the palm side (fingers curl toward -X), +Z is the thumb / index side.
## Left hands are the same model mirrored on X by the caller.

const SCALE := 1.3
const KNUCKLE := Vector3(-0.006, 0.08, 0.0)
const FINGER_Z := [0.033, 0.011, -0.011, -0.033]          # index, middle, ring, pinky
const FINGER_LEN := [[0.046, 0.034, 0.027], [0.05, 0.036, 0.029], [0.047, 0.034, 0.027], [0.04, 0.028, 0.023]]
const THUMB_BASE := Vector3(-0.012, 0.018, 0.054)
const THUMB_LEN := [0.04, 0.032]

var _fingers: Array = []   # per finger: [prox, mid, dist] pivot nodes
var _thumb: Array = []     # [base, tip] pivot nodes
var _cur := PackedFloat32Array()   # current joint angles in degrees: 12 finger joints, then 2 thumb joints

func build(skin: Color) -> void:
	var mat := Mats.solid(skin, 0.8)
	var nail := Mats.solid(skin.lerp(Color(1.0, 0.92, 0.9), 0.55), 0.35)
	_add_palm(mat)
	for i in 4:   # knuckle bumps on the back of the hand
		_add_ball(self, 0.0105, Vector3(0.017, 0.079, float(FINGER_Z[i])), mat)
	for i in 4:
		var chain: Array = []
		var parent: Node3D = self
		var pos := KNUCKLE + Vector3(0, 0, float(FINGER_Z[i]))
		for j in 3:
			var piv := Node3D.new()
			piv.position = pos
			parent.add_child(piv)
			var length := float(FINGER_LEN[i][j])
			_add_capsule(piv, 0.0105, length, mat)
			if j == 2:
				_add_nail(piv, length, nail)
			chain.append(piv)
			parent = piv
			pos = Vector3(0, length, 0)
		_fingers.append(chain)
	var tparent: Node3D = self
	var tpos := THUMB_BASE
	for j in 2:
		var piv2 := Node3D.new()
		piv2.position = tpos
		tparent.add_child(piv2)
		var tl := float(THUMB_LEN[j])
		_add_capsule(piv2, 0.0115, tl, mat)
		if j == 1:
			_add_nail(piv2, tl, nail)
		_thumb.append(piv2)
		tparent = piv2
		tpos = Vector3(0, tl, 0)
	_cur.resize(14)

## Outline of the palm seen from the side of the hand (z across, y along), wide at the knuckles, narrow at the wrist.
const PALM := [Vector2(-0.030, 0.000), Vector2(0.030, 0.000), Vector2(0.040, 0.020), Vector2(0.047, 0.045), Vector2(0.046, 0.068),
		Vector2(0.040, 0.082), Vector2(0.020, 0.087), Vector2(-0.020, 0.087), Vector2(-0.040, 0.082), Vector2(-0.046, 0.068),
		Vector2(-0.046, 0.045), Vector2(-0.040, 0.020)]

## A rounded, tapered slab instead of a box: the outline above, extruded 0.045 thick with bevelled faces.
func _add_palm(mat: Material) -> void:
	var n := PALM.size()
	var centre := Vector2(0.0, 0.0435)
	var rings := [[-0.0225, 0.86], [-0.0155, 1.0], [0.0155, 1.0], [0.0225, 0.86]]
	var verts: Array = []
	for r in rings:
		for pt in PALM:
			var q: Vector2 = centre + ((pt as Vector2) - centre) * float(r[1])
			verts.append(Vector3(float(r[0]), q.y, q.x))
	var mid := Vector3(0.0, 0.0435, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		for i in n:
			var j := (i + 1) % n
			_tri(st, verts[k * n + i], verts[k * n + j], verts[(k + 1) * n + j], mid)
			_tri(st, verts[k * n + i], verts[(k + 1) * n + j], verts[(k + 1) * n + i], mid)
	for i in range(1, n - 1):
		_tri(st, verts[0], verts[i], verts[i + 1], mid)
		_tri(st, verts[3 * n], verts[3 * n + i], verts[3 * n + i + 1], mid)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.layers = 4
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Adds a triangle wound so it faces away from `inside` (Godot: clockwise = front).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var nrm := (b - a).cross(c - a)
	var out := ((a + b + c) / 3.0) - inside
	if nrm.dot(out) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

## Rounded finger segment from the joint (local origin) along +Y. The rounded ends overlap at the joints.
func _add_capsule(parent: Node3D, radius: float, length: float, mat: Material) -> void:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = length + radius * 2.0
	m.radial_segments = 10
	m.rings = 3
	_add_mesh(parent, m, Vector3(0, length * 0.5, 0), mat)

func _add_ball(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 5
	_add_mesh(parent, m, pos, mat)

## Fingernail on the back (+X) of the last segment.
func _add_nail(parent: Node3D, length: float, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(0.003, length * 0.55, 0.014)
	_add_mesh(parent, m, Vector3(0.0095, length * 0.62, 0), mat)

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = 4
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.layers = 4
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Move the joints toward the wanted angles (degrees). curls = 4 fingers (index..pinky) x [knuckle, middle, tip]; thumb = [base, tip].
## k = 1 snaps, smaller values glide.
func pose(curls: Array, thumb: Array, k: float) -> void:
	for i in 4:
		var c: Array = curls[i]
		for j in 3:
			var idx := i * 3 + j
			_cur[idx] = lerpf(_cur[idx], float(c[j]), k)
			(_fingers[i][j] as Node3D).rotation.z = deg_to_rad(_cur[idx])
	for j in 2:
		_cur[12 + j] = lerpf(_cur[12 + j], float(thumb[j]), k)
		(_thumb[j] as Node3D).rotation.z = deg_to_rad(_cur[12 + j])
