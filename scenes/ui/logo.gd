class_name Logo
extends VBoxContainer
## WOBBLY HOURS: every letter wobbles on its own, next to a bobbing rubber duck.

const COLORS := [Color(1.0, 0.35, 0.4), Color(1.0, 0.65, 0.2), Color(1.0, 0.9, 0.3), Color(0.4, 0.9, 0.5), Color(0.3, 0.8, 1.0), Color(0.7, 0.5, 1.0)]
const TAGLINES := [
	"a chill hangout with questionable physics",
	"please do not feed the barrels",
	"now with 100% more flopping",
	"everybody is welcome. especially ducks",
	"gravity is just a suggestion",
	"hang out. fall over. repeat",
]
var _letters: Array[Label] = []
var _duck: Control
var _t := 0.0

class Duck extends Control:
	var t := 0.0
	func _draw() -> void:
		var bob := sin(t * 3.0) * 3.0
		var yellow := Color(1.0, 0.85, 0.15)
		var ink := Color(0.12, 0.08, 0.2)
		draw_circle(Vector2(40, 56 + bob), 26, ink)
		draw_circle(Vector2(40, 56 + bob), 23, yellow)
		draw_circle(Vector2(58, 30 + bob), 19, ink)
		draw_circle(Vector2(58, 30 + bob), 16, yellow)
		draw_colored_polygon(PackedVector2Array([Vector2(72, 31 + bob), Vector2(88, 35 + bob), Vector2(72, 40 + bob)]), Color(1.0, 0.5, 0.1))
		draw_circle(Vector2(62, 26 + bob), 2.5, ink)
		draw_circle(Vector2(30, 56 + bob), 11, Color(1.0, 0.75, 0.0))
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	alignment = BoxContainer.ALIGNMENT_CENTER
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 2)
	add_child(top)
	_duck = Duck.new()
	_duck.custom_minimum_size = Vector2(96, 90)
	top.add_child(_duck)
	_row(top, "WOBBLY", 0)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 2)
	add_child(bottom)
	_row(bottom, "HOURS", 3)
	var tag := Label.new()
	tag.text = TAGLINES[randi() % TAGLINES.size()]
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	add_child(tag)

func _row(parent: Control, word: String, offset: int) -> void:
	for i in word.length():
		var l := Label.new()
		l.text = word[i]
		l.add_theme_font_size_override("font_size", 76)
		l.add_theme_color_override("font_color", COLORS[(i + offset) % COLORS.size()])
		l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.2))
		l.add_theme_constant_override("outline_size", 16)
		l.resized.connect(func(): l.pivot_offset = l.size * 0.5)
		parent.add_child(l)
		_letters.append(l)

func _process(delta: float) -> void:
	_t += delta
	for i in _letters.size():
		var l := _letters[i]
		l.rotation = sin(_t * 2.2 + i * 0.8) * 0.12
		var s := 1.0 + sin(_t * 3.1 + i * 1.3) * 0.06
		l.scale = Vector2(s, s)
