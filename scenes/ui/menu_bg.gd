class_name MenuBackground
extends Control
## Animated menu background: a sunset gradient with drifting shapes and a big sun.

var _shapes := []
var _t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 34:
		_shapes.append({
			"p": Vector2(rng.randf(), rng.randf()),
			"v": Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.05, -0.012)),
			"s": rng.randf_range(14.0, 56.0), "r": rng.randf() * TAU, "w": rng.randf_range(-0.8, 0.8),
			"k": rng.randi() % 3, "c": Color.from_hsv(rng.randf(), 0.55, 1.0, 0.28)})

func _process(delta: float) -> void:
	_t += delta
	for s in _shapes:
		s["p"] += s["v"] * delta
		s["r"] += s["w"] * delta
		if s["p"].y < -0.1:
			s["p"] = Vector2(randf(), 1.1)
		if s["p"].x < -0.1:
			s["p"].x = 1.1
		elif s["p"].x > 1.1:
			s["p"].x = -0.1
	queue_redraw()

func _draw() -> void:
	var sz := size
	var top := Color(0.3, 0.18, 0.62)
	var bot := Color(1.0, 0.5, 0.45)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]), PackedColorArray([top, top, bot, bot]))
	draw_circle(Vector2(sz.x * 0.78, sz.y * 0.8), sz.y * 0.32, Color(1.0, 0.85, 0.4, 0.55))
	draw_circle(Vector2(sz.x * 0.78, sz.y * 0.8), sz.y * 0.24, Color(1.0, 0.95, 0.6, 0.6))
	for s in _shapes:
		var c: Vector2 = Vector2(s["p"].x * sz.x, s["p"].y * sz.y)
		var r: float = s["s"]
		match int(s["k"]):
			0:
				draw_circle(c, r * 0.6, s["c"])
			1:
				var a: float = s["r"]
				var pts := PackedVector2Array()
				for k in 4:
					pts.append(c + Vector2(cos(a + k * PI / 2.0 + PI / 4.0), sin(a + k * PI / 2.0 + PI / 4.0)) * r * 0.7)
				draw_colored_polygon(pts, s["c"])
			_:
				var a2: float = s["r"]
				var pts2 := PackedVector2Array()
				for k in 3:
					pts2.append(c + Vector2(cos(a2 + k * TAU / 3.0), sin(a2 + k * TAU / 3.0)) * r * 0.75)
				draw_colored_polygon(pts2, s["c"])
