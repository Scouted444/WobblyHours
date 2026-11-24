class_name WeaponWheel
extends Control
## Hold Q: a ring of the things you carry. Point the mouse at one and let go of Q to take it out
## (what you were holding goes back into its place). The middle / "Empty hands" puts your item away.

const R_OUT := 230.0
const R_IN := 90.0

var _player: Player
var _sel := -2          # -2 nothing, -1 empty hands, 0.. slot
var _font: Font

func setup(p: Player) -> void:
	_player = p

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font

func _slots() -> int:
	return Player.INVENTORY_SIZE + 1   # +1: the "empty hands" slice at the top

func _process(_delta: float) -> void:
	var c := size * 0.5
	var m := get_local_mouse_position() - c
	if m.length() < 40.0:
		_sel = -2
	else:
		var n := _slots()
		var ang := fposmod(atan2(m.x, -m.y), TAU)   # 0 at the top, clockwise
		var idx := int(round(ang / (TAU / n))) % n
		_sel = -1 if idx == 0 else idx - 1
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, R_OUT + 8.0, Color(0, 0, 0, 0.45))
	var n := _slots()
	var step := TAU / n
	for i in n:
		var a := i * step
		var slot := i - 1
		var chosen := (slot == _sel)
		var col: Color = Color(1.0, 0.85, 0.3, 0.85) if chosen else Color(0.2, 0.2, 0.3, 0.75)
		var pts := PackedVector2Array()
		for k in 9:
			var aa := a - step * 0.45 + step * 0.9 * k / 8.0
			pts.append(c + Vector2(sin(aa), -cos(aa)) * R_OUT)
		for k in 9:
			var aa := a + step * 0.45 - step * 0.9 * k / 8.0
			pts.append(c + Vector2(sin(aa), -cos(aa)) * R_IN)
		draw_colored_polygon(pts, col)
		var label := ""
		if slot < 0:
			label = "Empty hands"
		elif slot < _player.inventory.size():
			var k2 := String((_player.inventory[slot] as Array)[0])
			label = String(Prop.LABELS.get(k2, k2))
		else:
			label = "-"
		var mid := c + Vector2(sin(a), -cos(a)) * (R_IN + R_OUT) * 0.5
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(_font, mid - Vector2(tw * 0.5, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.1, 0.05, 0.15) if chosen else Color.WHITE)
	# centre: what's in my hand now
	draw_circle(c, R_IN - 10.0, Color(0.1, 0.1, 0.15, 0.85))
	var held: String = "nothing" if _player.equipped == "" else String(Prop.LABELS.get(_player.equipped, _player.equipped))
	var t1 := "In hand:"
	var w1 := _font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var w2 := _font.get_string_size(held, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(_font, c + Vector2(-w1 * 0.5, -6.0), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
	draw_string(_font, c + Vector2(-w2 * 0.5, 18.0), held, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.9, 0.5))
	var hint := "Let go of Q to pick  -  items you pick up go in here too (%d/%d)" % [_player.inventory.size(), Player.INVENTORY_SIZE]
	var w3 := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(_font, c + Vector2(-w3 * 0.5, R_OUT + 40.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))

func _input(event: InputEvent) -> void:
	if event.is_action_released("wheel"):
		get_viewport().set_input_as_handled()
		if _sel != -2 and is_instance_valid(_player):
			_player.wheel_pick(_sel)
		queue_free()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
