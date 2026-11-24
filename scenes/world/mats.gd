class_name Mats
extends RefCounted
## Cached materials, including procedurally generated textures (no image files needed).

static var _cache := {}

static func solid(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "s%s_%s_%s" % [color.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m

static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "g%s_%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m

static func glass(color := Color(0.7, 0.85, 1.0, 0.25)) -> StandardMaterial3D:
	var key := "gl%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	_cache[key] = m
	return m

## kind: planks, tiles, carpet, checker, stripes, shingles, grass, bricks, corrugated, concrete
## tile_m = how many metres one texture repeat covers (world-space, so any box tiles evenly).
static func textured(kind: String, tint := Color.WHITE, tile_m := 2.0, rough := 0.85) -> StandardMaterial3D:
	var key := "t%s_%s_%s_%s" % [kind, tint.to_html(), tile_m, rough]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(kind)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

static func _texture(kind: String) -> ImageTexture:
	var key := "tex_" + kind
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	match kind:
		"planks":
			for row in 8:
				var tone := rng.randf_range(0.82, 1.08)
				var seam := rng.randi_range(16, 112)
				for y in 16:
					for x in 128:
						var g := 0.05 * sin(x * 0.3 + row * 3.1 + y * 0.15) + rng.randf_range(-0.015, 0.015)
						var c := Color(0.75 * tone + g, 0.55 * tone + g, 0.36 * tone + g)
						if y == 0 or x == seam:
							c = c.darkened(0.4)
						img.set_pixel(x, row * 16 + y, c)
		"tiles":
			for ty in 4:
				for tx in 4:
					var tone := rng.randf_range(0.9, 1.05)
					for y in 32:
						for x in 32:
							var c := Color(0.9 * tone, 0.92 * tone, 0.95 * tone)
							if x < 2 or y < 2:
								c = Color(0.55, 0.57, 0.6)
							img.set_pixel(tx * 32 + x, ty * 32 + y, c)
		"carpet":
			for y in 128:
				for x in 128:
					var n := rng.randf_range(0.88, 1.08)
					img.set_pixel(x, y, Color(n, n, n))
		"checker":
			for y in 128:
				for x in 128:
					var dark := ((x / 32) + (y / 32)) % 2 == 0
					var v := 0.18 if dark else 0.92
					img.set_pixel(x, y, Color(v, v, v))
		"stripes":
			for y in 128:
				for x in 128:
					var v := 1.0 if (x / 16) % 2 == 0 else 0.9
					img.set_pixel(x, y, Color(v, v, v))
		"shingles":
			for row in 8:
				var off := 0 if row % 2 == 0 else 16
				for y in 16:
					for x in 128:
						var n := rng.randf_range(0.9, 1.05)
						var c := Color(0.85 * n, 0.85 * n, 0.85 * n)
						if y < 2 or (x + off) % 32 < 2:
							c = Color(0.35, 0.35, 0.35)
						img.set_pixel(x, row * 16 + y, c)
		"grass":
			for y in 128:
				for x in 128:
					# soft patches (periodic, so the texture tiles seamlessly) plus blade flecks
					var patch := 0.5 + 0.25 * sin(x * TAU / 128.0) * sin(y * TAU / 128.0) + 0.15 * sin((x + y) * TAU / 64.0)
					var n := rng.randf_range(0.85, 1.08) * (0.82 + 0.3 * patch)
					var roll := rng.randf()
					if roll < 0.04:
						n *= 1.25
					elif roll > 0.95:
						n *= 0.72
					img.set_pixel(x, y, Color(0.25 * n, 0.55 * n, 0.19 * n))
		"bricks":
			for row in 8:
				var off2 := 0 if row % 2 == 0 else 16
				for y in 16:
					for x in 128:
						var bi := int((x + off2) / 32) + row * 7
						var tone2 := 0.85 + 0.15 * sin(float(bi) * 12.9898)
						var n2 := rng.randf_range(0.92, 1.04) * tone2
						var c2 := Color(0.62 * n2, 0.3 * n2, 0.22 * n2)
						if y < 2 or (x + off2) % 32 < 2:
							c2 = Color(0.72, 0.7, 0.66)
						img.set_pixel(x, row * 16 + y, c2)
		"corrugated":
			for y in 128:
				for x in 128:
					var ridge := 0.78 + 0.22 * sin(float(x) * TAU / 16.0)
					var rust := 1.0 - 0.25 * maxf(0.0, sin(float(x) * 0.07 + float(y) * 0.05) * sin(float(y) * 0.11)) + rng.randf_range(-0.04, 0.03)
					img.set_pixel(x, y, Color(ridge * rust, ridge * rust * 0.97, ridge * rust * 0.93))
		_:  # concrete
			for y in 128:
				for x in 128:
					var n := rng.randf_range(0.82, 1.0)
					img.set_pixel(x, y, Color(n, n, n))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
