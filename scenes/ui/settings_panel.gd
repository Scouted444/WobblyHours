class_name SettingsPanel
extends Control
## Settings in four short sections. Everything applies straight away and is saved on Done / Esc.

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
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	_section(box, "Graphics")
	_check(box, "Realistic graphics", Settings.realistic,
		"Global illumination, reflections, soft shadows, sun rays and better colours. Needs a decent graphics card.",
		func(on: bool): Settings.realistic = on)
	_check(box, "Fullscreen", Settings.fullscreen, "", func(on: bool): Settings.fullscreen = on)
	_slider(box, "Field of view", 60.0, 110.0, Settings.fov, func(v: float): Settings.fov = v)

	_section(box, "Controls")
	_slider(box, "Mouse sensitivity", 0.3, 3.0, Settings.sensitivity, func(v: float): Settings.sensitivity = v)

	_section(box, "Sound")
	_slider(box, "Volume", 0.0, 1.0, Settings.volume, func(v: float): Settings.volume = v)
	_slider(box, "Menu music", 0.0, 1.0, Settings.music, func(v: float): Settings.music = v)

	_section(box, "Gameplay")
	_check(box, "Blood & dismemberment", Settings.gore, "Only on your screen (the host decides whether limbs come off).", func(on: bool): Settings.gore = on)

	box.add_child(_gap(6))
	var back := Button.new()
	back.text = "Done"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func():
		Settings.save()
		closed.emit())
	box.add_child(back)

func _section(parent: Control, text: String) -> void:
	parent.add_child(_gap(4))
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	parent.add_child(l)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.15)
	line.custom_minimum_size = Vector2(0, 2)
	parent.add_child(line)

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _check(parent: Control, label: String, value: bool, hint: String, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.toggled.connect(func(on: bool):
		setter.call(on)
		Settings.apply())
	parent.add_child(c)
	if hint != "":
		var h := Label.new()
		h.text = hint
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		parent.add_child(h)

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
