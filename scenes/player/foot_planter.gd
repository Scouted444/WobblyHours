class_name FootPlanter
extends RefCounted
## Procedural, raycast-driven foot placement for a walking body (players and NPCs alike).
## Ported from ProceduralCharacterController's foot logic: each foot stays planted where it landed
## until the body has moved (or turned) far enough away, then takes an arcing step to where it
## should be (a little ahead in the direction of travel). Feet alternate, never both lift at once
## (until the first step is past `gait_overlap`), re-plant after turning on the spot, settle when
## idle, tuck up in the air, and snap after a teleport. Movement itself is left to the game.
##
## NpcBody calls update() every frame with where the body is, which way it faces and how fast it's
## going, then bends each leg (two-bone IK) to put the ankle on foot.cur_pos.

# stepping
var step_distance_threshold := 0.32
var step_height := 0.13
var step_duration := 0.24
var min_step_duration := 0.11
var turn_step_angle_deg := 35.0
var idle_settle_distance := 0.08
var stride_lead := 0.6
var gait_overlap := 0.65
var snap_distance_multiplier := 4.0
var idle_speed_threshold := 0.15
# feet
var foot_spacing := 0.1
var foot_forward_offset := 0.0
var max_foot_slope_deg := 40.0
var ray_start_height := 0.8
var ray_length := 1.4
var ground_mask := 1
var airborne_foot_lift := 0.25

## Fired when a foot lands: (is_left, position, normal).
var on_planted: Callable

class Foot:
	var is_left: bool
	var side: float          # -1 left, +1 right (along the facing's right vector)
	var partner: Foot
	var planted_pos: Vector3
	var planted_normal := Vector3.UP
	var planted_yaw := 0.0
	var ideal_pos: Vector3
	var ideal_normal := Vector3.UP
	var stepping := false
	var step_elapsed := 0.0
	var step_time := 0.2
	var turn_step := false
	var from_pos: Vector3
	var from_normal := Vector3.UP
	var cur_pos: Vector3
	var cur_normal := Vector3.UP
	var lift := 0.0          # 0..1 how far through the arc (0 = on the ground)

	func progress() -> float:
		return clampf(step_elapsed / step_time, 0.0, 1.0) if stepping else 1.0

var left := Foot.new()
var right := Foot.new()
var feet: Array[Foot] = []
var _last_stepped: Foot
var _pending_partner: Foot
var _was_airborne := false
var _needs_plant := true

# what the body is doing this frame (set by update)
var _origin := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _vel := Vector3.ZERO
var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []

func _init() -> void:
	left.is_left = true
	left.side = -1.0
	right.is_left = false
	right.side = 1.0
	left.partner = right
	right.partner = left
	feet = [left, right]

## Forget where the feet were (after a teleport, ragdoll, getting out of a car...): plant afresh.
func reset() -> void:
	_needs_plant = true

func update(delta: float, origin: Vector3, facing: Vector3, velocity: Vector3, grounded: bool,
		space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	_origin = origin
	_fwd = _flatten(facing, Vector3.FORWARD)
	_right = Vector3(-_fwd.z, 0.0, _fwd.x)
	_vel = Vector3(velocity.x, 0.0, velocity.z)
	_space = space
	_exclude = exclude
	if _needs_plant:
		_needs_plant = false
		_plant_all()
		return
	if not grounded:
		_was_airborne = true
		for f in feet:
			_dangle(f, delta)
		return
	if _was_airborne:
		_was_airborne = false
		_plant_all()
		for f2 in feet:
			_planted(f2)
		return
	for f3 in feet:
		_compute_ideal(f3)
	for f4 in feet:
		if f4.stepping:
			_advance(f4, delta)
	_try_start_step()

## Height of the lower foot that is actually on the ground (for dropping the hips on stairs).
func support_height() -> float:
	var y := INF
	for f in feet:
		y = minf(y, f.ideal_pos.y if f.stepping else f.cur_pos.y)
	return y

# ------------------------------------------------------------------ stepping
func _compute_ideal(f: Foot) -> void:
	var lead := _vel * _step_time() * stride_lead
	var rest := _rest_point(f) + lead
	var hit := _ray(rest)
	if hit.is_empty():
		f.ideal_pos = Vector3(rest.x, _origin.y, rest.z)
		f.ideal_normal = Vector3.UP
	else:
		f.ideal_pos = hit["position"]
		f.ideal_normal = _limit_slope(hit["normal"])

func _try_start_step() -> void:
	for f in feet:
		if f.stepping and f.progress() < gait_overlap:
			return
	var moving := _vel.length() > idle_speed_threshold
	var dist_threshold := step_distance_threshold if moving else idle_settle_distance
	var turn_threshold := deg_to_rad(turn_step_angle_deg)
	var yaw := _yaw()
	var best: Foot = null
	var best_score := 0.0
	var best_turn := false
	for f2 in feet:
		if f2.stepping:
			continue
		var dist := f2.planted_pos.distance_to(f2.ideal_pos)
		if dist > step_distance_threshold * snap_distance_multiplier:
			_plant(f2)   # moved a long way at once: don't animate a giant step
			continue
		var yaw_err := absf(wrapf(yaw - f2.planted_yaw, -PI, PI))
		var score := 0.0
		var is_turn := false
		if dist > dist_threshold:
			score = dist / dist_threshold
		if yaw_err > turn_threshold and yaw_err / turn_threshold > score:
			score = yaw_err / turn_threshold
			is_turn = true
		# second half of a turn on the spot: the other foot follows even if it's under the threshold
		if f2 == _pending_partner and (yaw_err > deg_to_rad(4.0) or dist > idle_settle_distance * 0.5):
			if score <= 1.0:
				score = 1.001
				is_turn = true
		if score <= 1.0:
			continue
		if f2 == _last_stepped:
			score *= 0.5   # prefer alternating feet
		if best == null or score > best_score:
			best = f2
			best_score = score
			best_turn = is_turn
	if best != null:
		best.stepping = true
		best.turn_step = best_turn
		best.step_elapsed = 0.0
		best.step_time = _step_time()
		best.from_pos = best.planted_pos
		best.from_normal = best.planted_normal
		_last_stepped = best
		if best == _pending_partner:
			_pending_partner = null

## Moves a stepping foot along its arc; the landing spot follows the live ideal position.
func _advance(f: Foot, delta: float) -> void:
	f.step_elapsed += delta
	var t := f.progress()
	if t >= 1.0:
		f.stepping = false
		f.lift = 0.0
		_set_planted(f, f.ideal_pos, f.ideal_normal)
		if f.turn_step and not f.partner.stepping:
			_pending_partner = f.partner
		f.turn_step = false
		_planted(f)
		return
	var eased := smoothstep(0.0, 1.0, t)
	var arc := sin(t * PI)
	f.lift = arc
	f.cur_pos = f.from_pos.lerp(f.ideal_pos, eased) + Vector3.UP * (arc * step_height)
	f.cur_normal = f.from_normal.slerp(f.ideal_normal, eased).normalized()

func _step_time() -> float:
	var speed := _vel.length()
	if speed < 0.01:
		return step_duration
	var keep_up := (step_distance_threshold / speed) * 1.5
	return clampf(minf(step_duration, keep_up), min_step_duration, step_duration)

# ------------------------------------------------------------------ planting
func _plant_all() -> void:
	_pending_partner = null
	for f in feet:
		_plant(f)

func _plant(f: Foot) -> void:
	_compute_ideal(f)
	f.stepping = false
	f.turn_step = false
	f.lift = 0.0
	_set_planted(f, f.ideal_pos, f.ideal_normal)

func _set_planted(f: Foot, pos: Vector3, normal: Vector3) -> void:
	f.planted_pos = pos
	f.planted_normal = normal
	f.planted_yaw = _yaw()
	f.cur_pos = pos
	f.cur_normal = normal

## In the air the feet tuck up under the body and follow it.
func _dangle(f: Foot, delta: float) -> void:
	var target := _rest_point(f) + Vector3.UP * airborne_foot_lift
	var w := 1.0 - exp(-15.0 * delta)
	f.stepping = false
	f.lift = 1.0
	f.cur_pos = f.cur_pos.lerp(target, w)
	f.cur_normal = f.cur_normal.slerp(Vector3.UP, w).normalized()
	f.planted_pos = f.cur_pos
	f.ideal_pos = f.cur_pos

func _planted(f: Foot) -> void:
	if on_planted.is_valid():
		on_planted.call(f.is_left, f.planted_pos, f.planted_normal)

# ------------------------------------------------------------------ geometry
func _rest_point(f: Foot) -> Vector3:
	return _origin + _right * (f.side * foot_spacing) + _fwd * foot_forward_offset

func _ray(p: Vector3) -> Dictionary:
	if _space == null:
		return {}
	var from := Vector3(p.x, _origin.y + ray_start_height, p.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * ray_length, ground_mask, _exclude)
	return _space.intersect_ray(q)

func _limit_slope(n: Vector3) -> Vector3:
	var angle := n.angle_to(Vector3.UP)
	var max_angle := deg_to_rad(max_foot_slope_deg)
	if angle <= max_angle or angle < 0.0001:
		return n
	return Vector3.UP.slerp(n, max_angle / angle).normalized()

func _yaw() -> float:
	return atan2(-_fwd.x, -_fwd.z)

static func _flatten(v: Vector3, fallback: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.000001 else fallback
