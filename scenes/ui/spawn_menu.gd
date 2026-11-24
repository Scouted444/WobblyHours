class_name SpawnMenu
extends Control
## Tab menu: click an item to spawn it in front of you.

signal picked(kind: String)
signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Spawn  (click an item, Tab / Esc to close)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var tabs := TabContainer.new()
	box.add_child(tabs)
	for cat in Prop.CATEGORIES:
		var grid := GridContainer.new()
		grid.name = cat
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		tabs.add_child(grid)
		for k in Prop.CATEGORIES[cat]:
			var b := Button.new()
			b.text = Prop.LABELS[k]
			b.custom_minimum_size = Vector2(125, 52)
			b.pressed.connect(func(): picked.emit(k))
			grid.add_child(b)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): closed.emit())
	box.add_child(close)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
