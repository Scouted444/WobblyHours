class_name NpcLook
extends RefCounted
## Character description for the low-poly character maker models (models/chmaker_male.glb, chmaker_female.glb,
## by Fernando Lopez, CC-BY 4.0). A plain Dictionary so it syncs over RPC and saves as JSON:
##   {"type": "male"|"female", "skin": "rrggbb", "parts": {category: {"i": item index (-1 = none), "c": "rrggbb"}}}

const TYPES := ["male", "female"]

# [category key, label]
const CATS := [
	["hair", "Hair"], ["browns", "Eyebrows"], ["eyes", "Eyes"], ["mouth", "Mouth"], ["facial", "Facial hair"],
	["glasses", "Glasses"], ["shirt", "Shirt"], ["jacket", "Jacket"], ["bodysuit", "Bodysuit"],
	["pants", "Pants"], ["belt", "Belt"], ["shoes", "Shoes"], ["cyber", "Cyber arm"]]

## How many variants of each category exist in each model.
const COUNTS := {
	"male": {"hair": 8, "browns": 4, "eyes": 4, "mouth": 3, "facial": 5, "glasses": 5, "shirt": 3, "jacket": 2,
		"bodysuit": 3, "pants": 3, "belt": 4, "shoes": 2, "cyber": 3},
	"female": {"hair": 9, "browns": 4, "eyes": 3, "mouth": 4, "facial": 0, "glasses": 6, "shirt": 5, "jacket": 2,
		"bodysuit": 4, "pants": 4, "belt": 4, "shoes": 3, "cyber": 3},
}

# [roughness, metallic] per category
const LOOK := {
	"hair": [0.5, 0.0], "browns": [0.5, 0.0], "eyes": [0.2, 0.0], "mouth": [0.35, 0.0], "facial": [0.55, 0.0],
	"glasses": [0.25, 0.4], "shirt": [0.85, 0.0], "jacket": [0.8, 0.0], "bodysuit": [0.7, 0.0],
	"pants": [0.85, 0.0], "belt": [0.6, 0.1], "shoes": [0.6, 0.0], "cyber": [0.35, 0.7]}

const SKIN := ["dfd2c8", "ffe4d1", "ffc399", "ebc2a6", "e2c1aa", "ffcba7", "ffba8a", "e19d66", "bf7942", "935d34", "6d4425"]
const HAIR := ["adadad", "e1dd78", "d45d2e", "92562b", "6a4830", "2a221f", "531103", "353535", "141414", "ff4fa3", "3fa9ff"]
const EYES := ["0b0908", "21140a", "4e2e18", "5d5737", "1c4522", "144954", "2d393f"]
const MOUTH := ["a44c2e", "994220", "e26060", "de4d4d", "ca3636", "881919"]
const CLOTHES := ["d2d2d2", "3c3c3c", "a82020", "5d8f1b", "1b4c07", "142835", "204760", "3b7d7f", "b6b01a", "68820b",
	"aa1a02", "8a103b", "2c3333", "a5c9ca", "e83a14", "009dae", "ffe652", "7d9d9c"]
const SHOES := ["181818", "424242", "210505", "2f1a08", "062524", "39270d", "989898", "e83a14", "f4f9f9"]

static func palette(cat: String) -> Array:
	match cat:
		"hair", "browns", "facial":
			return HAIR
		"eyes":
			return EYES
		"mouth":
			return MOUTH
		"shoes":
			return SHOES
		_:
			return CLOTHES

static func count(type: String, cat: String) -> int:
	return int((COUNTS.get(type, COUNTS["male"]) as Dictionary).get(cat, 0))

## Name of the mesh node inside the .glb for category + index.
static func node_name(type: String, cat: String, i: int) -> String:
	var c := cat
	if cat == "facial":
		c = "beard"
	elif cat == "bodysuit":
		c = "body"
	elif cat == "eyes" and type == "female":
		c = "eye"
	return "%s_%s_%d" % [type, c, i + 1]

static func _pick(rng: RandomNumberGenerator, a: Array) -> String:
	return str(a[rng.randi() % a.size()])

static func random(seed_value := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value * 104729 + 7
	else:
		rng.randomize()
	var type: String = TYPES[rng.randi() % 2]
	var hair_c := _pick(rng, HAIR)
	var parts := {}
	for entry in CATS:
		var cat: String = entry[0]
		var n := count(type, cat)
		if n == 0:
			continue
		var chance := 0.0
		match cat:
			"hair": chance = 0.88
			"browns", "eyes", "mouth", "shirt", "pants", "shoes": chance = 1.0
			"jacket", "glasses", "facial": chance = 0.25
			"belt": chance = 0.2
			"cyber": chance = 0.04
			_: chance = 0.0
		var color := _pick(rng, palette(cat))
		if cat == "hair" or cat == "browns" or cat == "facial":
			color = hair_c
		parts[cat] = {"i": (rng.randi() % n) if rng.randf() < chance else -1, "c": color}
	return {"type": type, "skin": _pick(rng, SKIN), "parts": parts}

static func _hex(v: Variant, fallback: String) -> String:
	var s := str(v).trim_prefix("#")
	if s.length() == 6 and s.is_valid_html_color():
		return s.to_lower()
	return fallback

## Clamp everything to valid values; an empty / bad dictionary becomes a random character.
static func sanitize(raw: Variant, seed_value := -1) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return random(seed_value)
	var src: Dictionary = raw
	var type := str(src.get("type", "male"))
	if not TYPES.has(type):
		type = "male"
	var out := {"type": type, "skin": _hex(src.get("skin", ""), "ffc399"), "parts": {}}
	var in_parts: Dictionary = src.get("parts", {}) if src.get("parts", {}) is Dictionary else {}
	for entry in CATS:
		var cat: String = entry[0]
		var n := count(type, cat)
		var e: Dictionary = in_parts.get(cat, {}) if in_parts.get(cat, {}) is Dictionary else {}
		var idx := clampi(int(e.get("i", -1)), -1, n - 1)
		if n == 0:
			idx = -1
		(out["parts"] as Dictionary)[cat] = {"i": idx, "c": _hex(e.get("c", ""), str(palette(cat)[0]))}
	return out

## Fields for the classic ragdoll dummy so it matches the character (used while you are knocked out).
static func classic_colors(npc: Dictionary) -> Dictionary:
	var parts: Dictionary = npc.get("parts", {})
	var d := {"skin": str(npc.get("skin", "ffc399"))}
	d["hair_color"] = str((parts.get("hair", {}) as Dictionary).get("c", "59331a"))
	d["shirt"] = str((parts.get("shirt", {}) as Dictionary).get("c", "e0562f"))
	d["pants"] = str((parts.get("pants", {}) as Dictionary).get("c", "2f3f6b"))
	d["shoes"] = str((parts.get("shoes", {}) as Dictionary).get("c", "f2f2f2"))
	return d
