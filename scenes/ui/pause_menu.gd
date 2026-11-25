class_name PauseMenu
extends Control
## Esc in game. The party keeps running behind it.

signal resume
signal leave
signal quit
signal open_settings
signal open_customizer
signal stuck

var _pages := {}

## One short list of buttons; the invite code (host) is a single line at the top, and the host
## tools, controls and connection help each open as their own little page with a Back button.
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
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	col.add_child(title)
	var who := Label.new()
	who.text = "%d in the party" % Net.players.size()
	var names := []
	for id in Net.players:
		names.append(str(Net.players[id].get("name", "?")))
	who.tooltip_text = ", ".join(names)
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 14)
	who.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	col.add_child(who)
	var host := multiplayer.is_server()

	# ---- main page
	var main := _page(col, "main")
	if host:
		_invite_row(main)
	main.add_child(_btn("Resume", func(): resume.emit(), true))
	main.add_child(_btn("Character", func(): open_customizer.emit()))
	main.add_child(_btn("I'm stuck! (respawn)", func(): stuck.emit()))
	main.add_child(_btn("Settings", func(): open_settings.emit()))
	var more := HBoxContainer.new()
	more.add_theme_constant_override("separation", 8)
	main.add_child(more)
	var ctl_b := _btn("Controls", func(): _show("controls"))
	ctl_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more.add_child(ctl_b)
	if host:
		var ht := _btn("Host tools", func(): _show("host"))
		ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		more.add_child(ht)
	main.add_child(_gap(4))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	main.add_child(bottom)
	for e in [["Leave party", func(): leave.emit()], ["Quit game", func(): quit.emit()]]:
		var b := _btn(str(e[0]), e[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", Color(1.0, 0.7, 0.65))
		bottom.add_child(b)

	# ---- controls page
	var ctl := _page(col, "controls")
	ctl.add_child(_heading("Controls"))
	var tips := Label.new()
	var gw := get_tree().get_first_node_in_group("world") as GameWorld
	tips.text = gw.controls_text() if gw != null else "Tab: spawn menu    T: chat    F: use / drive    V: camera    U: I'm stuck"
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size = Vector2(560, 0)
	tips.add_theme_font_size_override("font_size", 14)
	tips.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	ctl.add_child(tips)
	ctl.add_child(_btn("Back", func(): _show("main")))

	# ---- host pages
	if host:
		var ht2 := _page(col, "host")
		ht2.add_child(_heading("Host tools"))
		_host_tools(ht2)
		ht2.add_child(_btn("Back", func(): _show("main")))
		var net := _page(col, "net")
		net.add_child(_heading("Connection"))
		_net_help(net)
		net.add_child(_btn("Back", func(): _show("main")))
	_show("main")

func _page(parent: Control, id: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 8)
	parent.add_child(p)
	_pages[id] = p
	return p

func _show(id: String) -> void:
	for k in _pages:
		(_pages[k] as Control).visible = k == id

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _btn(text: String, on: Callable, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48 if big else 40)
	if big:
		b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on)
	return b

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume.emit()

## Host: "Invite: ABCDE-FGHIJ  [Copy]  [?]" on one line (the ? page explains connection problems).
func _invite_row(box: VBoxContainer) -> void:
	var link := Net.link
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var dot := Label.new()
	dot.add_theme_font_size_override("font_size", 18)
	row.add_child(dot)
	var code := Label.new()
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.add_theme_font_size_override("font_size", 20)
	code.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
	row.add_child(code)
	var copy := _btn("Copy", func():
		DisplayServer.clipboard_set(link.invite_full)
		Sfx.play_ui(self, "pickup", -6.0))
	copy.custom_minimum_size = Vector2(70, 36)
	row.add_child(copy)
	var help := _btn("?", func(): _show("net"))
	help.custom_minimum_size = Vector2(36, 36)
	help.tooltip_text = "Friends can't join?"
	row.add_child(help)
	var refresh := func():
		code.text = ("Invite: " + link.invite_short) if link.invite_short != "" else "Getting invite code..."
		copy.disabled = link.invite_full == ""
		# green = router port open, yellow = still checking, red = friends may not get in
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if link.router_ok else (Color(1.0, 0.85, 0.3) if not link.router_checked else Color(1.0, 0.4, 0.35)))
		dot.tooltip_text = link.router_msg
	refresh.call()
	link.host_info_changed.connect(refresh)
	tree_exiting.connect(func():
		if link.host_info_changed.is_connected(refresh):
			link.host_info_changed.disconnect(refresh))

## The connection-help page: is the router port open, and what to do if friends can't get in.
func _net_help(box: VBoxContainer) -> void:
	var link := Net.link
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(460, 0)
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	box.add_child(info)
	var refresh := func():
		info.text = "\n\n".join(link.status_lines())
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
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	box.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	box.add_child(row2)
	for e in [[row1, "Clear props", "props"], [row1, "Clear people", "people"], [row1, "Clear cars", "traffic"], [row2, "Clear blood", "gore"], [row2, "Reset everything", "all"]]:
		var what: String = e[2]
		var b := _btn(String(e[1]), func(): gw.host_clear(what))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(e[0] as HBoxContainer).add_child(b)
	var cb := CheckBox.new()
	cb.text = "Let guests spawn things"
	cb.button_pressed = gw.guests_can_spawn
	cb.toggled.connect(func(on: bool): gw.guests_can_spawn = on)
	box.add_child(cb)
