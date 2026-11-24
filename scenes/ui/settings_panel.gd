class_name SettingsPanel
extends Control
## Sliders for mouse, FOV, volume, music, fullscreen. Applies and saves live.

signal closed

func _ready() -> void:
	theme = UITheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	_slider(box, "Mouse sensitivity", 0.3, 3.0, Settings.sensitivity, func(v: float): Settings.sensitivity = v)
	_slider(box, "Field of view", 60.0, 110.0, Settings.fov, func(v: float): Settings.fov = v)
	_slider(box, "Volume", 0.0, 1.0, Settings.volume, func(v: float): Settings.volume = v)
	_slider(box, "Menu music", 0.0, 1.0, Settings.music, func(v: float): Settings.music = v)
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on: bool):
		Settings.fullscreen = on
		Settings.apply())
	box.add_child(fs)
	var gore := CheckBox.new()
	gore.text = "Blood & dismemberment (people only)"
	gore.button_pressed = Settings.gore
	gore.toggled.connect(func(on: bool): Settings.gore = on)
	box.add_child(gore)
	var back := Button.new()
	back.text = "Done"
	back.pressed.connect(func():
		Settings.save()
		closed.emit())
	box.add_child(back)

func _slider(parent: Control, label: String, lo: float, hi: float, value: float, setter: Callable) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 28)
	s.value_changed.connect(func(v: float):
		setter.call(v)
		Settings.apply())
	h.add_child(s)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Settings.save()
		closed.emit()
