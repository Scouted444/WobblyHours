class_name Grips
extends RefCounted
## How the first-person hands hold each item. Numbers were tuned in a small offline preview of the hands.
##
## spec(kind) = { "pos": item position in camera space, "rot": (pitch, yaw, roll) degrees,
##   "hands": [ { "side": 1 right / -1 left, "at": grip point on the item, "B": item axes -> hand axes,
##                "G": where that point sits inside the fist (hand space), "curls": ..., "thumb": ... } ] }
## Hand space: +Y toward the fingertips, -X palm side, +Z thumb side (see fp_hand.gd).

static func h_fwd() -> Basis:
	# hand space -> camera space for a hand that points straight ahead with the palm facing left and the thumb up
	return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

static func mirror_x() -> Basis:
	return Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

## Camera-space rotation from (pitch, yaw, roll) degrees.
static func cam_rot(e: Vector3) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(e.y)) * Basis(Vector3.RIGHT, deg_to_rad(e.x)) * Basis(Vector3(0, 0, -1), deg_to_rad(e.z))

# item axes -> hand axes
static func b_pistol() -> Basis:   # handle up the hand's knuckle line, muzzle out through the fingers' side
	return Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

static func b_saber() -> Basis:    # blade / bat sticks out of the thumb side
	return Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))

static func b_palm() -> Basis:     # item rests on an upturned palm
	return Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0))

const FIST := [70.0, 80.0, 60.0]
const FIST_THICK := [58.0, 68.0, 50.0]
const FIST_PINCH := [75.0, 85.0, 65.0]
const FLAT := [8.0, 8.0, 4.0]

static func _h(side: int, at: Vector3, b: Basis, g: Vector3, curls: Array, thumb: Array) -> Dictionary:
	return {"side": side, "at": at, "B": b, "G": g, "curls": curls, "thumb": thumb}

## {} when this kind has no special grip (crates, balls, ...: the generic two-handed carry is used).
static func spec(kind: String) -> Dictionary:
	match kind:
		"limb_arm":   # held by the wrist like a club, stump end out
			return {"pos": Vector3(0.28, -0.26, -0.45), "rot": Vector3(32, 8, 0), "hands": [
				_h(1, Vector3(0, 0, 0.24), b_saber(), Vector3(-0.045, 0.04, 0), [FIST, FIST, FIST, FIST], [25, 20])]}
		"limb_leg":   # held by the ankle
			return {"pos": Vector3(0.3, -0.28, -0.45), "rot": Vector3(35, 8, 0), "hands": [
				_h(1, Vector3(0, 0, 0.3), b_saber(), Vector3(-0.05, 0.04, 0), [FIST_THICK, FIST_THICK, FIST_THICK, FIST_THICK], [25, 20])]}
		"limb_head":  # carried on an open palm
			return {"pos": Vector3(0.17, -0.08, -0.55), "rot": Vector3(0, 180, 0), "hands": [
				_h(1, Vector3(0, 0, 0), b_palm(), Vector3(-0.16, 0.065, 0), [[30, 40, 25], [30, 40, 25], [30, 40, 25], [30, 40, 25]], [25, 25])]}
		"pistol":
			return {"pos": Vector3(0.17, -0.16, -0.5), "rot": Vector3(4, 8, 0), "hands": [
				_h(1, Vector3(0, -0.035, 0.09), b_pistol(), Vector3(-0.045, 0.035, 0), [[8, 12, 5], FIST, FIST, FIST], [12, 6])]}
		"knife":
			return {"pos": Vector3(0.2, -0.18, -0.5), "rot": Vector3(30, 10, 0), "hands": [
				_h(1, Vector3(0, 0, 0.05), b_saber(), Vector3(-0.04, 0.04, 0), [FIST, FIST, FIST, FIST], [25, 20])]}
		"bat":
			return {"pos": Vector3(0.3, -0.28, -0.45), "rot": Vector3(30, 8, 0), "hands": [
				_h(1, Vector3(0, 0, 0.03), b_saber(), Vector3(-0.04, 0.04, 0), [FIST, FIST, FIST, FIST], [25, 20])]}
		"soda":
			return {"pos": Vector3(0.2, -0.19, -0.5), "rot": Vector3(0, 0, 0), "hands": [
				_h(1, Vector3(0, 0, 0), b_pistol(), Vector3(-0.055, 0.04, 0), [FIST_THICK, FIST_THICK, FIST_THICK, FIST_THICK], [20, 15])]}
		"beer":
			return {"pos": Vector3(0.2, -0.16, -0.5), "rot": Vector3(0, 0, 0), "hands": [
				_h(1, Vector3(0, -0.03, 0), b_pistol(), Vector3(-0.053, 0.04, 0), [FIST_THICK, FIST_THICK, FIST_THICK, FIST_THICK], [20, 15])]}
		"console":
			var edge := [[85, 5, 0], [85, 5, 0], [85, 5, 0], [85, 5, 0]]
			return {"pos": Vector3(0, -0.15, -0.5), "rot": Vector3(-20, 0, 0), "hands": [
				_h(1, Vector3(0.1, 0, 0), b_pistol(), Vector3(-0.03, 0.045, 0), edge, [5, 5]),
				_h(-1, Vector3(-0.1, 0, 0), b_pistol(), Vector3(-0.03, 0.045, 0), edge, [5, 5])]}
		"rpg":
			return {"pos": Vector3(0.15, -0.18, -0.75), "rot": Vector3(3, 5, 0), "hands": [
				_h(1, Vector3(0, -0.04, 0), b_pistol(), Vector3(-0.045, 0.035, 0), [[10, 15, 5], FIST, FIST, FIST], [12, 6]),
				_h(-1, Vector3(0, -0.03, -0.25), b_pistol(), Vector3(-0.045, 0.035, 0), [FIST, FIST, FIST, FIST], [25, 20])]}
		"cig":
			return {"pos": Vector3(0.2, -0.17, -0.45), "rot": Vector3(0, 0, 0), "hands": [
				_h(1, Vector3(0, 0, 0.06), b_pistol(), Vector3(-0.078, 0.087, 0.043), [[40, 45, 25], FIST_PINCH, FIST_PINCH, FIST_PINCH], [32, 34])]}
		"pizza":
			return {"pos": Vector3(0.17, -0.17, -0.55), "rot": Vector3(0, 0, 0), "hands": [
				_h(1, Vector3(0, 0, 0.1), b_palm(), Vector3(-0.035, 0.07, 0), [FLAT, FLAT, FLAT, FLAT], [25, 15])]}
		"burger":
			return {"pos": Vector3(0.17, -0.1, -0.55), "rot": Vector3(0, 0, 0), "hands": [
				_h(1, Vector3(0, 0, 0), b_palm(), Vector3(-0.12, 0.065, 0), [[30, 40, 25], [30, 40, 25], [30, 40, 25], [30, 40, 25]], [25, 25])]}
	return {}

## For one hand of a grip: returns {"basis": node basis (includes the mirror for left hands), "wrist": position}
## in camera space, given the item's camera-space transform.
static func place_hand(item: Transform3D, h: Dictionary) -> Dictionary:
	var side: int = h["side"]
	var b: Basis = h["B"]
	var ri := item.basis.orthonormalized()
	var rn: Basis
	var s := Basis.IDENTITY
	if side == 1:
		rn = ri * b.transposed()
	else:
		var m := mirror_x()
		b = b * m
		rn = ri * b.transposed() * m
		s = m
	var node := rn * s
	var p := item * (h["at"] as Vector3)
	var wrist := p - node * ((h["G"] as Vector3) * FpHand.SCALE)
	return {"basis": node, "wrist": wrist}

## Hand frame for a free hand: aims the fingers by (pitch, yaw) degrees from straight ahead.
static func free_hand(side: int, wrist: Vector3, e: Vector3) -> Dictionary:
	var rn := cam_rot(Vector3(e.x, e.y * float(side), e.z)) * h_fwd()
	var node: Basis = rn if side == 1 else rn * mirror_x()
	return {"basis": node, "wrist": wrist}
