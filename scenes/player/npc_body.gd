class_name NpcBody
extends CustomBody
## Player body built from the low-poly character maker models (see npc_look.gd). Meshes are switched on/off
## and tinted from a NpcLook dictionary. Idle animation comes from the model; walking is a procedural
## leg / arm swing layered on top of the animated pose.

var npc := {}
var _type := ""
var _holder: Node3D
var _sk: Skeleton3D
var _meshes := {}
var _speed := 0.0
var _amt := 0.0
var _state := 0         # 0 ground, 1 air, 2 swim, 3 sitting in the coupe, 4 hanging on a rocket
var _hold := 0          # 0 hands free, 1 one item, 2 big item, 3 carrying a person
var _w := 0.0           # how much of the procedural pose is blended over the model's own animation
var _a := {}            # smoothed pose angles
var _anim_now := ""
var _phase := 0.0
var _bone := {}
var _fp := false
var _rag: Array = []

func _init() -> void:
	process_priority = 1000   # run after the AnimationPlayer so the pose is added on top of it

func load_npc(desc: Dictionary) -> bool:
	_type = str(desc.get("type", "male"))
	var scene := ModelLib.make("chmaker_" + _type)
	if scene == null:
		return false
	_holder = Node3D.new()
	_holder.rotation.y = PI    # glTF models face +Z, the game faces -Z
	add_child(_holder)
	_holder.add_child(scene)
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	_sk = sks[0] as Skeleton3D
	for c in _sk.get_children():
		if c is MeshInstance3D:
			_meshes[String(c.name)] = c
	for key in ["Pelvis", "Thigh.L", "Thigh.R", "Leg.L", "Leg.R", "Foot.L", "Foot.R", "UpperArm.L", "UpperArm.R",
			"LowerArm.L", "LowerArm.R", "Fingers.L", "Fingers.R", "Spine", "SpineUpper", "Neck", "Head"]:
		_bone[key] = _find_bone(key)
	var missing := []
	for key in _bone:
		if int(_bone[key]) < 0:
			missing.append(key)
	if not missing.is_empty():
		push_error("NpcBody: bones not found %s. The skeleton's bones are: %s" % [str(missing), str(_bone_names())])
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0] as AnimationPlayer
		var idle := "%s_idle_1" % _type
		if _anim.has_animation(idle):
			_anim.get_animation(idle).loop_mode = Animation.LOOP_LINEAR
			_anim.play(idle)
	apply(desc)
	return true

## Letters and digits only, lower case: "Thigh.L", "Thigh_L" and "ThighL" all become "thighl".
func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out

func _bone_names() -> Array:
	var out := []
	for i in _sk.get_bone_count():
		out.append(_sk.get_bone_name(i))
	return out

## Bone names can lose their dots on import (Thigh.L -> Thigh_L), so compare them loosely.
func _find_bone(key: String) -> int:
	var b := _sk.find_bone(key)
	if b >= 0:
		return b
	var want := _norm(key)
	for i in _sk.get_bone_count():
		if _norm(_sk.get_bone_name(i)) == want:
			return i
	return -1

func _mat(hex: String, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html(hex)
	m.roughness = rough
	m.metallic = metal
	return m

## Show the chosen parts and colour them (can be called again live, e.g. by the editor).
func apply(desc: Dictionary) -> void:
	npc = desc
	for k in _meshes:
		(_meshes[k] as MeshInstance3D).visible = false
	var base := _meshes.get(_type) as MeshInstance3D
	if base != null:
		base.visible = true
		base.set_surface_override_material(0, _mat(str(desc.get("skin", "ffc399")), 0.8, 0.0))
	var parts: Dictionary = desc.get("parts", {})
	for entry in NpcLook.CATS:
		var cat: String = entry[0]
		var e: Dictionary = parts.get(cat, {})
		var i := int(e.get("i", -1))
		if i < 0:
			continue
		if _fp and cat in ["hair", "browns", "eyes", "mouth", "facial", "glasses"]:
			continue
		var mi := _meshes.get(NpcLook.node_name(_type, cat, i)) as MeshInstance3D
		if mi == null:
			continue
		var rm: Array = NpcLook.LOOK.get(cat, [0.8, 0.0])
		mi.visible = true
		mi.set_surface_override_material(0, _mat(str(e.get("c", "ffffff")), float(rm[0]), float(rm[1])))
	_joint_fillers()

## The character maker's meshes have little gaps at the joints that open up as soon as an arm or leg
## bends (so people looked like they were coming apart). Small balls glued to the joint bones fill them,
## coloured like whatever covers that joint (sleeve, trouser leg, or skin).
var _fillers: Array[Node] = []
func _joint_fillers() -> void:
	for f in _fillers:
		if is_instance_valid(f):
			f.queue_free()
	_fillers.clear()
	if _sk == null:
		return
	var parts: Dictionary = npc.get("parts", {})
	var skin := Color.html(str(npc.get("skin", "ffc399")))
	var female := _type == "female"
	var sleeve := _part_col(parts, ["bodysuit", "jacket"])    # long sleeves
	var top := _part_col(parts, ["bodysuit", "jacket", "shirt"])
	var legs := _part_col(parts, ["bodysuit", "pants"])
	var shoes := _part_col(parts, ["shoes"])
	var arm_c: Color = sleeve if sleeve.a > 0.0 else skin
	var top_c: Color = top if top.a > 0.0 else skin
	var leg_c: Color = legs if legs.a > 0.0 else skin
	var ankle_c: Color = shoes if shoes.a > 0.0 else leg_c
	# sized a bit INSIDE the limb, so they only show through the gaps instead of as bumps
	var spec := [
		["LowerArm", (0.034 if female else 0.04) * (1.0 if sleeve.a > 0.0 else 0.85), arm_c],
		["Fingers", (0.022 if female else 0.026) * 0.85, skin],
		["Leg", (0.072 if female else 0.068) * 0.82, leg_c]]
	for e in spec:
		for side in [".L", ".R"]:
			var b := int(_bone.get(String(e[0]) + side, -1))
			if b < 0:
				continue
			var ba := BoneAttachment3D.new()
			_sk.add_child(ba)
			ba.bone_name = _sk.get_bone_name(b)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = float(e[1])
			sm.height = float(e[1]) * 2.0
			sm.radial_segments = 10
			sm.rings = 6
			mi.mesh = sm
			mi.material_override = _mat((e[2] as Color).to_html(false), 0.8, 0.0)
			ba.add_child(mi)
			_fillers.append(ba)

func _part_col(parts: Dictionary, cats: Array) -> Color:
	for c in cats:
		var e: Dictionary = parts.get(c, {})
		if int(e.get("i", -1)) >= 0:
			return Color.html(str(e.get("c", "ffffff")))
	return Color(0, 0, 0, 0)

## First-person: hide the parts around the face so the camera never sees them from inside.
func set_first_person(on: bool) -> void:
	if on == _fp:
		return
	_fp = on
	if not npc.is_empty():
		apply(npc)

## Pose state, set every frame by the player: see _state / _hold above.
func set_pose(state: int, hold: int) -> void:
	_state = state
	_hold = hold

func animate(speed: float, ragdolled: bool) -> void:
	_speed = 0.0 if ragdolled else speed

## Play one of the model's own animations (idle, seat...) if it is not already playing.
func _play(name_suffix: String) -> void:
	if _anim == null:
		return
	var n := "%s_%s" % [_type, name_suffix]
	if n == _anim_now or not _anim.has_animation(n):
		return
	_anim_now = n
	_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play(n, 0.15)

## Car seat targets (prop.gd CARS "ik"): {foot: Vector2(forward, height), hand: Vector2, recline}.
var seat_ik := {}

## World-space transforms of the 10 ragdoll parts (PlayerRig order), or [] when standing.
func set_ragdoll(parts: Array) -> void:
	_rag = parts

## Where the right hand is (for items shown in the hand), in world space.
func hand_point() -> Vector3:
	var b := int(_bone.get("Fingers.R", -1))
	if b < 0 or _sk == null:
		return global_position + Vector3(0, 1.0, 0)
	return (_sk.global_transform * _sk.get_bone_global_pose(b)).origin

## bone, child bone, ragdoll part (PlayerRig index). Fixed left/right: the model's ".L" is the body's left.
const RAG_CHAINS := [
	["Thigh.L", "Leg.L", 6], ["Thigh.R", "Leg.R", 7],
	["Leg.L", "Foot.L", 8], ["Leg.R", "Foot.R", 9],
	["UpperArm.L", "LowerArm.L", 2], ["UpperArm.R", "LowerArm.R", 3],
	["LowerArm.L", "Fingers.L", 4], ["LowerArm.R", "Fingers.R", 5]]

## Point each limb bone the way its ragdoll capsule points, so the model flops like the physics body.
func _apply_ragdoll() -> void:
	_holder.basis = Basis(Vector3.UP, PI)
	_holder.position = Vector3.ZERO
	var skg := _sk.global_transform
	for ch in RAG_CHAINS:
		var b := int(_bone.get(ch[0], -1))
		var c := int(_bone.get(ch[1], -1))
		var idx := int(ch[2])
		if b < 0 or c < 0 or idx >= _rag.size():
			continue
		var gb: Transform3D = skg * _sk.get_bone_global_pose(b)
		var gc: Transform3D = skg * _sk.get_bone_global_pose(c)
		var cur_dir := gc.origin - gb.origin
		if cur_dir.length() < 0.001:
			continue
		var part: Transform3D = _rag[idx]
		_aim_dir(b, (-part.basis.y).normalized(), 1.0, cur_dir.normalized())

## Rotate bone b (and so everything below it) by the shortest arc that makes the bone -> child direction
## match `want` (world space), blended by weight w. Needs no knowledge of the bone's own axes.
## Returns the world rotation that was applied.
func _aim(bone_name: String, child_name: String, want: Vector3, w: float) -> Quaternion:
	var b := int(_bone.get(bone_name, -1))
	var c := int(_bone.get(child_name, -1))
	if b < 0 or c < 0 or w <= 0.001:
		return Quaternion.IDENTITY
	var skg := _sk.global_transform
	var gb: Transform3D = skg * _sk.get_bone_global_pose(b)
	var gc: Transform3D = skg * _sk.get_bone_global_pose(c)
	var cur := gc.origin - gb.origin
	if cur.length() < 0.001:
		return Quaternion.IDENTITY
	return _aim_dir(b, want, w, cur.normalized())

func _aim_dir(b: int, want: Vector3, w: float, cur_in := Vector3.ZERO) -> Quaternion:
	var skg := _sk.global_transform
	var gb: Transform3D = skg * _sk.get_bone_global_pose(b)
	var cur := cur_in
	if cur == Vector3.ZERO:
		# find this bone's first child to get its current direction
		for i in _sk.get_bone_count():
			if _sk.get_bone_parent(i) == b:
				cur = ((skg * _sk.get_bone_global_pose(i)).origin - gb.origin)
				break
		if cur.length() < 0.001:
			return Quaternion.IDENTITY
		cur = cur.normalized()
	var q_full := Quaternion(cur, want.normalized())
	var q := Quaternion.IDENTITY.slerp(q_full, w)
	var new_world := Basis(q) * gb.basis.orthonormalized()
	var new_sk := _sk.global_basis.orthonormalized().inverse() * new_world
	var parent := _sk.get_bone_parent(b)
	var pb := Basis.IDENTITY
	if parent >= 0:
		pb = _sk.get_bone_global_pose(parent).basis.orthonormalized()
	_sk.set_bone_pose_rotation(b, (pb.inverse() * new_sk).get_rotation_quaternion())
	return q

## Rotate a bone by `angle` about a world axis, on top of whatever pose it has now.
func _turn(bone_name: String, axis: Vector3, angle: float) -> void:
	var b := int(_bone.get(bone_name, -1))
	if b < 0 or absf(angle) < 0.0001 or axis.length() < 0.001:
		return
	var skg := _sk.global_transform
	var gb: Transform3D = skg * _sk.get_bone_global_pose(b)
	var new_world := Basis(axis.normalized(), angle) * gb.basis.orthonormalized()
	var new_sk := skg.basis.orthonormalized().inverse() * new_world
	var parent := _sk.get_bone_parent(b)
	var pb := Basis.IDENTITY
	if parent >= 0:
		pb = _sk.get_bone_global_pose(parent).basis.orthonormalized()
	_sk.set_bone_pose_rotation(b, (pb.inverse() * new_sk).get_rotation_quaternion())

## Keep a bone (a foot) pointing the way it did before its parents were rotated by `undo`.
func _level(bone_name: String, undo: Quaternion, w: float) -> void:
	var b := int(_bone.get(bone_name, -1))
	if b < 0:
		return
	var gb: Transform3D = _sk.global_transform * _sk.get_bone_global_pose(b)
	var q := Quaternion.IDENTITY.slerp(undo.inverse(), w)
	var new_world := Basis(q) * gb.basis.orthonormalized()
	var new_sk := _sk.global_basis.orthonormalized().inverse() * new_world
	var parent := _sk.get_bone_parent(b)
	var pb := Basis.IDENTITY
	if parent >= 0:
		pb = _sk.get_bone_global_pose(parent).basis.orthonormalized()
	_sk.set_bone_pose_rotation(b, (pb.inverse() * new_sk).get_rotation_quaternion())

func _smooth(key: String, target: float, k: float) -> float:
	var cur: float = float(_a.get(key, target))
	cur = lerpf(cur, target, k)
	_a[key] = cur
	return cur

## Limbs knocked off (gore): bone keys whose bones are shrunk to nothing every frame.
var _removed: Array[String] = []
const LIMB_BONES := {"head": "Head", "arm_l": "UpperArm.L", "arm_r": "UpperArm.R", "leg_l": "Thigh.L", "leg_r": "Thigh.R"}
const STUMP_BONES := {"head": "SpineUpper", "arm_l": "SpineUpper", "arm_r": "SpineUpper", "leg_l": "Pelvis", "leg_r": "Pelvis"}

func has_limb(limb: String) -> bool:
	return LIMB_BONES.has(limb) and not (LIMB_BONES[limb] in _removed)

## Hide a limb (and everything below it). Returns where it was, in world space (or Vector3.INF).
func remove_limb(limb: String) -> Vector3:
	if _sk == null or not has_limb(limb):
		return Vector3.INF
	var key: String = LIMB_BONES[limb]
	var b := int(_bone.get(key, -1))
	if b < 0:
		return Vector3.INF
	var at := _sk.global_transform * _sk.get_bone_global_pose(b).origin
	_removed.append(key)
	# a little fountain from the stump (only for people who want blood)
	var sb := int(_bone.get(String(STUMP_BONES[limb]), -1))
	if sb >= 0 and Settings.gore:
		var ba := BoneAttachment3D.new()
		_sk.add_child(ba)
		ba.bone_name = _sk.get_bone_name(sb)
		var spurt := Gore.spurt()
		ba.add_child(spurt)
		spurt.global_position = at
	return at

## Show exactly the limbs in this bit mask as missing (bits: head 1, arm_l 2, arm_r 4, leg_l 8, leg_r 16).
var _sev_mask := 0
func set_severed(mask: int) -> void:
	if mask == _sev_mask:
		return
	var bits := {"head": 1, "arm_l": 2, "arm_r": 4, "leg_l": 8, "leg_r": 16}
	for l in bits:
		var bit := int(bits[l])
		var key: String = LIMB_BONES[l]
		if (mask & bit) and not (_sev_mask & bit):
			remove_limb(String(l))
		elif not (mask & bit) and (_sev_mask & bit):
			# grown back: put the bone's size back explicitly (the animation doesn't always rewrite it)
			_removed.erase(key)
			var b := int(_bone.get(key, -1))
			if b >= 0 and _sk != null:
				_sk.set_bone_pose_scale(b, _sk.get_bone_rest(b).basis.get_scale())
	_sev_mask = mask

## World position of a limb's root bone (even if it has been removed).
func limb_origin(limb: String) -> Vector3:
	if _sk == null or not LIMB_BONES.has(limb):
		return global_position + Vector3.UP
	var b := int(_bone.get(String(LIMB_BONES[limb]), -1))
	if b < 0:
		return global_position + Vector3.UP
	return _sk.global_transform * _sk.get_bone_global_pose(b).origin

func skin_color() -> Color:
	return Color.html(str(npc.get("skin", "ffc399")))

func hair_color() -> Color:
	var parts: Dictionary = npc.get("parts", {})
	var h: Dictionary = parts.get("hair", {})
	return Color.html(str(h.get("c", "3a2a1a")))

func _apply_removed() -> void:
	for key in _removed:
		var b := int(_bone.get(key, -1))
		if b >= 0:
			_sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)

func _process(delta: float) -> void:
	if _sk == null or not visible:
		return
	_pose_step(delta)
	if not _removed.is_empty():
		_apply_removed()

## Bones that only ever get turned RELATIVE to their current pose. The model's idle animation doesn't key
## them, so nothing rewrites them between frames: put them back to rest first or the turns pile up
## (that was the head slowly spinning / tipping over).
const RELATIVE_BONES := ["Spine", "SpineUpper", "Neck", "Head", "Foot.L", "Foot.R"]
## Two-bone IK: bend b1 -> b2 -> b3 so the end of b2 (where b3 starts) reaches `target`, with the
## middle joint (knee / elbow) bending towards `pole`. Returns the two applied rotations.
func _ik2(b1: String, b2: String, b3: String, target: Vector3, pole: Vector3, w: float) -> Array:
	var i1 := int(_bone.get(b1, -1))
	var i2 := int(_bone.get(b2, -1))
	var i3 := int(_bone.get(b3, -1))
	if i1 < 0 or i2 < 0 or i3 < 0 or _sk == null:
		return [Quaternion(), Quaternion()]
	var skg := _sk.global_transform
	var p1 := (skg * _sk.get_bone_global_pose(i1)).origin
	var p2 := (skg * _sk.get_bone_global_pose(i2)).origin
	var p3 := (skg * _sk.get_bone_global_pose(i3)).origin
	var l1 := p1.distance_to(p2)
	var l2 := p2.distance_to(p3)
	if l1 < 0.01 or l2 < 0.01:
		return [Quaternion(), Quaternion()]
	var t := target - p1
	var r := clampf(t.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var n := t.normalized()
	var pp := pole - n * pole.dot(n)
	if pp.length() < 0.001:
		pp = Vector3.UP
	pp = pp.normalized()
	var a := acos(clampf((l1 * l1 + r * r - l2 * l2) / (2.0 * l1 * r), -1.0, 1.0))
	var d1 := (n * cos(a) + pp * sin(a)).normalized()
	var mid := p1 + d1 * l1
	var d2 := (p1 + n * r - mid).normalized()
	var q1 := _aim(b1, b2, d1, w)
	var q2 := _aim(b2, b3, d2, w)
	return [q1, q2]

## How high the hip joints are above my feet when standing (the model's own proportions).
var _thigh_cache := -1.0
func _thigh_h() -> float:
	if _thigh_cache > 0.0:
		return _thigh_cache
	var b := int(_bone.get("Thigh.L", -1))
	if b < 0 or _sk == null:
		return 1.0
	var p := _holder.global_transform.affine_inverse() * (_sk.global_transform * _sk.get_bone_global_rest(b).origin)
	_thigh_cache = clampf(p.y, 0.6, 1.3)
	return _thigh_cache

func _reset_relative() -> void:
	for n in RELATIVE_BONES:
		var b := int(_bone.get(n, -1))
		if b >= 0:
			_sk.set_bone_pose_rotation(b, _sk.get_bone_rest(b).basis.get_rotation_quaternion())

func _pose_step(delta: float) -> void:
	_reset_relative()
	if not _rag.is_empty():
		_apply_ragdoll()
		return

	var k := 1.0 - exp(-14.0 * delta)
	var amt := clampf(_speed / 5.0, 0.0, 1.35)
	var moving := _state == 0 and amt > 0.05
	_phase += delta * ((6.0 + _speed * 1.8) if _state == 0 else (3.0 + _speed * 1.2))

	# which of the model's own animations to play underneath
	if _state == 3:
		_play("seat_1")
	else:
		_play("idle_1")

	# swimming lays the body out flat (about the hips); everything else stands up
	var lean := _smooth("lean", 1.15 if _state == 2 else 0.0, k)
	var rot := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, lean)
	_holder.basis = rot
	var hip := Vector3(0, 0.95, 0)
	_holder.position = hip - rot * hip

	# target pose (angles in radians, positive = swinging forward)
	var tl := 0.0
	var tq := 0.0   # thighs
	var kl := 0.0
	var kq := 0.0   # knees (flexion)
	var al := 0.0
	var aq := 0.0   # upper arms
	var el := 0.0
	var eq := 0.0   # elbows (flexion)
	var out := 0.1                  # arms away from the body
	var knee_out := 0.0             # knees spread apart (seated in the toy car)
	var want_w := 0.0
	var bob := 0.0
	var lean_t := 0.0               # upper body leaning forward (running)
	var sway := 0.0                 # shoulders rocking side to side
	var s := sin(_phase)
	var c := cos(_phase)
	match _state:
		0:
			if moving:
				want_w = 1.0
				var run := clampf((amt - 0.85) / 0.4, 0.0, 1.0)   # 0 = walk, 1 = sprint
				var stride := lerpf(0.5, 0.78, run) * minf(amt, 1.0)
				tl = stride * s + 0.06 * run
				tq = -stride * s + 0.06 * run
				# the knee bends most while the leg swings through, and stays a little soft on the ground
				kl = 0.08 + minf(amt, 1.0) * lerpf(0.9, 1.45, run) * maxf(0.0, c) * (0.6 + 0.4 * maxf(0.0, s + 0.3))
				kq = 0.08 + minf(amt, 1.0) * lerpf(0.9, 1.45, run) * maxf(0.0, -c) * (0.6 + 0.4 * maxf(0.0, -s + 0.3))
				var arm_sw := lerpf(0.45, 0.85, run) * minf(amt, 1.0)
				al = -arm_sw * s
				aq = arm_sw * s
				el = lerpf(0.35, 1.45, run) + 0.25 * maxf(0.0, -s)   # bend more on the forward swing
				eq = lerpf(0.35, 1.45, run) + 0.25 * maxf(0.0, s)
				out = lerpf(0.1, 0.18, run)
				bob = (absf(c) - 0.6) * lerpf(0.03, 0.06, run) * minf(amt, 1.0)
				lean_t = lerpf(0.06, 0.32, run) * minf(amt, 1.0)
				sway = 0.06 * s * minf(amt, 1.0)
		1:
			want_w = 1.0
			# in the air: one knee up, arms out for balance, flailing a bit the longer it lasts
			var ta := Time.get_ticks_msec() * 0.001
			tl = 0.75; tq = -0.2 + 0.15 * sin(ta * 6.0)
			kl = 1.2; kq = 0.6 + 0.2 * sin(ta * 6.0 + 1.0)
			al = 1.25 + 0.35 * sin(ta * 9.0); aq = 1.25 + 0.35 * sin(ta * 9.0 + 2.2)
			el = 0.4 + 0.2 * sin(ta * 7.0); eq = 0.4 + 0.2 * sin(ta * 7.0 + 1.3)
			out = 0.6
			lean_t = -0.08
		2:
			want_w = 1.0
			var sw := 0.45 + 0.35 * amt
			tl = 0.3 * sin(_phase * 1.6); tq = -tl
			kl = 0.25 + 0.2 * maxf(0.0, sin(_phase * 1.6 + 1.0)); kq = 0.25 + 0.2 * maxf(0.0, -sin(_phase * 1.6 + 1.0))
			al = 1.55 + 1.15 * sin(_phase * 0.9)
			aq = 1.55 + 1.15 * sin(_phase * 0.9 + PI)
			el = 0.45 + 0.35 * maxf(0.0, -cos(_phase * 0.9))
			eq = 0.45 + 0.35 * maxf(0.0, cos(_phase * 0.9))
			out = 0.25 + sw * 0.0
		3:
			want_w = 1.0
			# a grown-up squeezed into a toy car: knees jammed up past the dashboard and splayed out,
			# jiggling with the bumps, hands reaching down to the tiny steering wheel between them
			var tj := Time.get_ticks_msec() * 0.001
			tl = 2.2 + 0.07 * sin(tj * 11.0); tq = 2.2 + 0.07 * sin(tj * 11.0 + 1.7)
			kl = 1.85; kq = 1.85
			knee_out = 0.5
			al = 0.8 + 0.06 * sin(tj * 7.0); aq = 0.8 + 0.06 * sin(tj * 7.0 + 2.0)
			el = 0.5; eq = 0.5
			out = 0.05
		6:
			# sitting in a real car seat: thighs level, shins down, hands on the wheel
			want_w = 1.0
			var tc := Time.get_ticks_msec() * 0.001
			tl = 1.45; tq = 1.45
			kl = 1.45; kq = 1.45
			al = 1.05 + 0.04 * sin(tc * 1.3); aq = 1.05 + 0.04 * sin(tc * 1.3 + 1.0)
			el = 0.55; eq = 0.55
			out = 0.08
		4:
			want_w = 1.0
			tl = 0.15; tq = 0.0
			kl = 0.8; kq = 0.8
			al = 1.7; aq = 1.7
			el = 0.25; eq = 0.25
			out = 0.15
	# holding things overrides the arms (not while swimming / sitting)
	if _state == 0 or _state == 1:
		if _hold == 1:
			aq = 0.95; eq = 0.95; want_w = 1.0
		elif _hold == 2:
			al = 0.95; aq = 0.95; el = 0.9; eq = 0.9; want_w = 1.0
		elif _hold == 3:
			al = 2.3; aq = 2.3; el = 0.5; eq = 0.5; out = 0.2; want_w = 1.0

	_w = lerpf(_w, want_w, 1.0 - exp(-10.0 * delta))
	if _w < 0.02:
		return
	var w := _w
	var tl_s := _smooth("tl", tl, k)
	var tr_s := _smooth("tq", tq, k)
	var kl_s := _smooth("kl", kl, k)
	var kr_s := _smooth("kq", kq, k)
	var al_s := _smooth("al", al, k)
	var ar_s := _smooth("aq", aq, k)
	var el_s := _smooth("el", el, k)
	var er_s := _smooth("eq", eq, k)
	var out_s := _smooth("out", out, k)
	var bob_s := _smooth("bob", bob, k)

	var hb := _holder.global_basis.orthonormalized()
	var fwd := hb * Vector3(0, 0, 1)      # the way the character faces
	var up := hb * Vector3(0, 1, 0)
	var left := hb * Vector3(1, 0, 0)      # the character's left side

	_holder.position.y += bob_s   # a little hip bounce while walking

	# ducking: hunch the back and drop the head (to fit under the toy car's roof);
	# running: lean into it and rock the shoulders, but keep the head looking ahead
	var duck_s := _smooth("duck", 1.0 if _state == 3 else 0.0, k)
	var lean_s := _smooth("leanf", lean_t, k)
	var sway_s := _smooth("sway", sway, k)
	# All of these turn the bones RELATIVE to the model's own pose (aiming them at fixed directions
	# ignored the natural forward tilt of the neck and tipped the head backwards).
	var bend_ax := up.cross(fwd).normalized()     # turning about this tips the top forward
	var side_ax := up.cross(left).normalized()    # ... and this tips it to the left
	var fwd_bend := (0.35 * duck_s + lean_s * 0.6) * w
	var top_bend := (0.45 * duck_s + lean_s * 0.4) * w
	var neck_bend := (0.25 * duck_s - (lean_s + lean_s) * 0.45) * w   # running: look ahead, not at the floor
	_turn("Spine", bend_ax, fwd_bend)
	_turn("Spine", side_ax, sway_s * w)
	_turn("SpineUpper", bend_ax, top_bend)
	_turn("SpineUpper", side_ax, -sway_s * 0.5 * w)
	_turn("Neck", bend_ax, neck_bend)
	var car_seat := _state == 6 and not seat_ik.is_empty()
	if car_seat:
		# sit back in the seat (but keep the eyes on the road), hips at the height the car was built for
		var rc := float(seat_ik.get("recline", 0.18)) * w
		_turn("Spine", bend_ax, -rc)
		_turn("Neck", bend_ax, rc * 0.7)
		_holder.position.y += (1.0 - _thigh_h()) * w
	var ko_s := _smooth("ko", knee_out, k)
	if car_seat:
		# feet on the pedals (two-bone IK: knees come up as far as they need to)
		var foot: Vector2 = seat_ik.get("foot", Vector2(0.8, 0.78))
		for side in [1, -1]:
			var sf: String = "L" if side == 1 else "R"
			var tgt := global_transform * Vector3(-0.12 * float(side), foot.y, -foot.x)
			var qs := _ik2("Thigh." + sf, "Leg." + sf, "Foot." + sf, tgt, global_basis * Vector3(0, 1, -1), w)
			_level("Foot." + sf, (qs[1] as Quaternion) * (qs[0] as Quaternion), w * 0.9)
	else:
		for side in [1, -1]:
			var sfx: String = "L" if side == 1 else "R"
			var th: float = tl_s if side == 1 else tr_s
			var kn: float = kl_s if side == 1 else kr_s
			var d1 := (-up * cos(th) + fwd * sin(th) + left * float(side) * ko_s).normalized()
			var q1 := _aim("Thigh." + sfx, "Leg." + sfx, d1, w)
			var d2 := -up * cos(th - kn) + fwd * sin(th - kn)
			var q2 := _aim("Leg." + sfx, "Foot." + sfx, d2, w)
			_level("Foot." + sfx, q2 * q1, w * 0.9)
	# arms
	if car_seat:
		# both hands on the steering wheel
		var hand: Vector2 = seat_ik.get("hand", Vector2(0.44, 1.44))
		for side in [1, -1]:
			var sh: String = "L" if side == 1 else "R"
			var tg := global_transform * Vector3(-0.17 * float(side), hand.y, -hand.x)
			_ik2("UpperArm." + sh, "LowerArm." + sh, "Fingers." + sh, tg, global_basis * Vector3(-0.6 * float(side), -1.0, 0.0), w)
	else:
		for side in [1, -1]:
			var sfx2: String = "L" if side == 1 else "R"
			var ua: float = al_s if side == 1 else ar_s
			var ea: float = el_s if side == 1 else er_s
			var outv := left * float(side) * out_s
			var d3 := (-up * cos(ua) + fwd * sin(ua) + outv).normalized()
			_aim("UpperArm." + sfx2, "LowerArm." + sfx2, d3, w)
			var d4 := (-up * cos(ua + ea) + fwd * sin(ua + ea) + outv * 0.5).normalized()
			_aim("LowerArm." + sfx2, "Fingers." + sfx2, d4, w)
