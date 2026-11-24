class_name Look
extends RefCounted
## A character's customization as a plain Dictionary (JSON / RPC friendly):
##   skin, hair_color, shirt, pants, shoes, hat_color : "rrggbb" hex strings
##   hair_style, hat, glasses, beard                   : ints (index into the lists below)
##   stripes                                           : bool (striped shirt)
##   head_size                                         : float (goofy big heads allowed)
## Everything goes through sanitize() so a modified client can't send nonsense.

const HAIR_STYLES := ["Bald", "Short", "Long", "Spiky", "Mohawk", "Afro", "Bun", "Pigtails"]
const HATS := ["None", "Traffic cone", "Top hat", "Cowboy hat", "Crown", "Beanie", "Propeller cap", "Rubber duck"]
const GLASSES := ["None", "Round", "Sunglasses", "Goofy giant", "3D glasses", "Monocle"]
const BEARDS := ["None", "Mustache", "Full beard", "Goatee"]

const SKIN_TONES := ["f5cdb0", "deac85", "ae7854", "734d33", "4d3324", "ffe0c9", "c58c62"]
const HAIR_COLORS := ["1a120d", "59331a", "d9b359", "99261a", "33333d", "e8e8e8", "ff4fa3", "3fa9ff"]

const COLOR_KEYS := ["skin", "hair_color", "shirt", "pants", "shoes", "hat_color"]
const SAVE_PATH := "user://look.json"

static func default_look() -> Dictionary:
	return {
		"skin": "deac85", "hair_color": "59331a", "shirt": "e0562f", "pants": "2f3f6b",
		"shoes": "f2f2f2", "hat_color": "e8452c", "hair_style": 1, "hat": 0,
		"glasses": 0, "beard": 0, "stripes": false, "head_size": 1.0, "model": "",
		"npc": NpcLook.random(),
	}

## Random look. Pass the player id for a stable look per player.
static func random_look(seed_value := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value * 7919 + 13
	else:
		rng.randomize()
	var d := default_look()
	d["skin"] = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	d["hair_color"] = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	d["shirt"] = Color.from_hsv(rng.randf(), 0.6, 0.9).to_html(false)
	d["pants"] = Color.from_hsv(0.6, rng.randf_range(0.2, 0.6), rng.randf_range(0.25, 0.5)).to_html(false)
	d["shoes"] = Color.from_hsv(rng.randf(), 0.15, rng.randf_range(0.7, 1.0)).to_html(false)
	d["hat_color"] = Color.from_hsv(rng.randf(), 0.8, 0.95).to_html(false)
	d["hair_style"] = rng.randi() % HAIR_STYLES.size()
	d["hat"] = (rng.randi() % (HATS.size() - 1)) + 1 if rng.randf() < 0.3 else 0
	d["glasses"] = (rng.randi() % (GLASSES.size() - 1)) + 1 if rng.randf() < 0.35 else 0
	d["beard"] = (rng.randi() % (BEARDS.size() - 1)) + 1 if rng.randf() < 0.2 else 0
	d["stripes"] = rng.randf() < 0.3
	d["head_size"] = 1.0
	d["npc"] = NpcLook.random(seed_value)
	_sync_classic(d)
	return d

## The ragdoll dummy (shown while knocked out) takes its colours from the character.
static func _sync_classic(d: Dictionary) -> void:
	var c := NpcLook.classic_colors(d["npc"])
	for k in c:
		d[k] = c[k]

## Clamp every field to something valid. Unknown keys are dropped.
static func sanitize(raw: Dictionary) -> Dictionary:
	var d := default_look()
	for key in COLOR_KEYS:
		var v := str(raw.get(key, d[key])).trim_prefix("#")
		if v.length() == 6 and v.is_valid_html_color():
			d[key] = v.to_lower()
	d["hair_style"] = clampi(int(raw.get("hair_style", d["hair_style"])), 0, HAIR_STYLES.size() - 1)
	d["hat"] = clampi(int(raw.get("hat", d["hat"])), 0, HATS.size() - 1)
	d["glasses"] = clampi(int(raw.get("glasses", d["glasses"])), 0, GLASSES.size() - 1)
	d["beard"] = clampi(int(raw.get("beard", d["beard"])), 0, BEARDS.size() - 1)
	d["stripes"] = bool(raw.get("stripes", d["stripes"]))
	var mid := str(raw.get("model", ""))
	d["model"] = mid if is_model_id(mid) else ""
	d["head_size"] = clampf(float(raw.get("head_size", d["head_size"])), 0.7, 2.0)
	d["npc"] = NpcLook.sanitize(raw.get("npc", {}))
	return d

static func color_of(look: Dictionary, key: String) -> Color:
	return Color.html(str(look.get(key, "ffffff")))

static func save(look: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(look))

## The saved look, or a fresh random one the first time the game is run.
static func load_saved() -> Dictionary:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				return sanitize(parsed)
	return random_look()

## Workshop model ids are the first 16 hex characters of the file's SHA-256.
static func is_model_id(id: String) -> bool:
	return id.length() == 16 and id.is_valid_hex_number(false)
