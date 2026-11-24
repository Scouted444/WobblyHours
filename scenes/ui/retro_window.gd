class_name RetroWindow
extends PanelContainer
## A draggable Windows-95-style window. Build with RetroWindow.make(...).

signal closed
signal minimized
signal focused

var title := ""
var _drag := false
var _drag_off := Vector2.ZERO
var _title_label: Label

static func make(title_text: String, content: Control, pos: Vector2) -> RetroWindow:
	var w := RetroWindow.new()
	w.title = title_text
	w.position = pos
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	w.add_child(box)
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.5)
	sb.content_margin_left = 4
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	bar.add_theme_stylebox_override("panel", sb)
	box.add_child(bar)
	var hb := HBoxContainer.new()
	bar.add_child(hb)
	w._title_label = Label.new()
	w._title_label.text = title_text
	w._title_label.add_theme_color_override("font_color", Color.WHITE)
	w._title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w._title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(w._title_label)
	var mn := Button.new()
	mn.text = "_"
	mn.custom_minimum_size = Vector2(22, 20)
	mn.pressed.connect(func(): w.minimized.emit())
	hb.add_child(mn)
	var cl := Button.new()
	cl.text = "X"
	cl.custom_minimum_size = Vector2(22, 20)
	cl.pressed.connect(func(): w.close())
	hb.add_child(cl)
	bar.gui_input.connect(w._bar_input.bind(bar))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_child(content)
	box.add_child(margin)
	return w

func close() -> void:
	closed.emit()
	queue_free()

func _bar_input(event: InputEvent, bar: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		_drag_off = event.global_position - global_position
		if event.pressed:
			move_to_front()
			focused.emit()

func _input(event: InputEvent) -> void:
	if _drag and event is InputEventMouseMotion:
		var p: Vector2 = event.global_position - _drag_off
		var par := get_parent_control()
		if par != null:
			p.x = clampf(p.x, -size.x + 80.0, par.size.x - 80.0)
			p.y = clampf(p.y, 0.0, par.size.y - 60.0)
		global_position = p
	elif _drag and event is InputEventMouseButton and not event.pressed:
		_drag = false
	elif event is InputEventMouseButton and event.pressed and visible and get_global_rect().has_point(event.global_position):
		move_to_front()
		focused.emit()
