class_name PauseMenu
extends Control
## Esc in game. The party keeps running behind it.

signal resume
signal leave
signal quit
signal open_settings
signal open_customizer
signal stuck

func _ready() -> void:
	theme = UITheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.15, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	box.add_child(title)
	var who := Label.new()
	var names := []
	for id in Net.players:
		names.append(str(Net.players[id].get("name", "?")))
	who.text = "In the party (%d): %s" % [names.size(), ", ".join(names)]
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(who)
	if multiplayer.is_server():
		_invite(box)
	box.add_child(_btn("Resume", func(): resume.emit()))
	box.add_child(_btn("Customize character  (K)", func(): open_customizer.emit()))
	box.add_child(_btn("I'm stuck!  (respawn)  (U)", func(): stuck.emit()))
	box.add_child(_btn("Settings", func(): open_settings.emit()))
	box.add_child(_btn("Leave party", func(): leave.emit()))
	if multiplayer.is_server():
		_host_tools(box)
	box.add_child(_btn("Quit game", func(): quit.emit()))
	var ctl := Label.new()
	ctl.text = "Controls"
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctl.add_theme_font_size_override("font_size", 20)
	box.add_child(ctl)
	var tips := Label.new()
	var gw := get_tree().get_first_node_in_group("world") as GameWorld
	tips.text = gw.controls_text() if gw != null else "Tab: spawn menu    T: chat    F: use / drive    V: camera    U: I'm stuck"
	tips.add_theme_font_size_override("font_size", 14)
	tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(tips)

func _btn(text: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(on)
	return b

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume.emit()

## Host: the invite code friends paste into Join, and how reachable this party is.
func _invite(box: VBoxContainer) -> void:
	var link := Net.link
	var code := Label.new()
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 30)
	code.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
	box.add_child(code)
	var copy := _btn("Copy invite  (send it to your friends)", func():
		DisplayServer.clipboard_set(link.invite_full)
		Sfx.play_ui(self, "pickup", -6.0))
	box.add_child(copy)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(400, 0)
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	box.add_child(info)
	var refresh := func():
		code.text = ("Invite code:  " + link.invite_short) if link.invite_short != "" else "Getting your invite code..."
		copy.disabled = link.invite_full == ""
		info.text = "\n".join(link.status_lines())
	refresh.call()
	link.host_info_changed.connect(refresh)
	tree_exiting.connect(func():
		if link.host_info_changed.is_connected(refresh):
			link.host_info_changed.disconnect(refresh))

## Only the host sees these: clean up the map and control spawning.
func _host_tools(box: VBoxContainer) -> void:
	var gw := get_tree().get_first_node_in_group("world") as GameWorld
	if gw == null:
		return
	var l := Label.new()
	l.text = "Host tools"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	box.add_child(l)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	box.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	box.add_child(row2)
	for e in [[row1, "Clear props", "props"], [row1, "Clear people", "people"], [row1, "Clear cars", "traffic"], [row2, "Clear blood & body parts", "gore"], [row2, "Reset everything", "all"]]:
		var what: String = e[2]
		var b := _btn(String(e[1]), func(): gw.host_clear(what))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(e[0] as HBoxContainer).add_child(b)
	var cb := CheckBox.new()
	cb.text = "Let guests spawn things"
	cb.button_pressed = gw.guests_can_spawn
	cb.toggled.connect(func(on: bool): gw.guests_can_spawn = on)
	box.add_child(cb)
