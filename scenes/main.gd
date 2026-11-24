extends Node
## Start menu, pause menu and the switch between menu and world. Everything is built in code.

const TIPS := [
	"Tip: right-click a toy to hold it, left-click to use it.",
	"Tip: the barrels are not a hot tub.",
	"Tip: press Tab for the spawn menu.",
	"Tip: there is a 1995 computer in the bedroom. It has games.",
	"Tip: beer makes the camera wobble. Responsibly.",
	"Tip: press R to flop on purpose.",
	"Tip: the trampoline in the yard is load-bearing fun.",
	"Tip: drag a .glb onto the Workshop to become a traffic cone.",
	"Tip: there's a whole town east along Main Street. Say hi to people (T to chat).",
	"Tip: F next to a car with someone in it... borrows it. Permanently.",
	"Tip: Campaign mode: no spawning, you earn cash with jobs from the job board.",
]

var layer: CanvasLayer
var menu: Control
var status: Label
var name_edit: LineEdit
var ip_edit: LineEdit
var lan_box: VBoxContainer
const LAST_JOIN := "user://last_join.txt"
var world: GameWorld
var _music: AudioStreamPlayer
var _pause_layer: CanvasLayer
var _pause_sub: CanvasLayer

func _ready() -> void:
	Net.disconnected.connect(_teardown)
	Settings.changed.connect(_update_music_volume)
	_build_menu()
	_start_music()
	if "--smoke" in OS.get_cmdline_user_args():
		SmokeTest.run(self)

func _unhandled_input(event: InputEvent) -> void:
	if world == null or not event.is_action_pressed("pause"):
		return
	if _pause_layer != null:
		_resume()
		return
	var me := _my_player()
	if me != null and not me.input_locked:
		_open_pause(me)

func _my_player() -> Player:
	if world == null or multiplayer.multiplayer_peer == null:
		return null
	return world.get_node_or_null(str(multiplayer.get_unique_id())) as Player

# --------------------------------------------------------------------- menu
func _build_menu() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	menu = Control.new()
	menu.theme = UITheme.shared()
	layer.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(MenuBackground.new())

	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(Logo.new())
	box.add_child(_spacer(6))

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.text = "Player%d" % randi_range(100, 999)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.max_length = 16
	box.add_child(name_edit)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	box.add_child(host_row)
	var host_btn := _btn("HOST A PARTY", _on_host, Color(0.45, 0.9, 0.5))
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(host_btn)
	var mode_pick := OptionButton.new()
	mode_pick.add_item("Sandbox")
	mode_pick.add_item("Campaign")
	mode_pick.tooltip_text = "Sandbox: spawn anything, free money.\nCampaign: no spawning - do jobs in town to earn cash."
	mode_pick.custom_minimum_size = Vector2(150, 50)
	mode_pick.selected = 1 if Net.mode == "campaign" else 0
	mode_pick.item_selected.connect(func(i: int): Net.mode = "campaign" if i == 1 else "sandbox")
	host_row.add_child(mode_pick)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Paste an invite code (ABCDE-FGHIJ) or an IP"
	ip_edit.tooltip_text = "The host gets an invite code when they host (shown in game and in the pause menu).\nPlain IP addresses work too (LAN, Radmin, Hamachi...)."
	if FileAccess.file_exists(LAST_JOIN):
		ip_edit.text = FileAccess.get_file_as_string(LAST_JOIN).strip_edges()
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(func(_t: String): _on_join())
	join_row.add_child(ip_edit)
	var join_btn := _btn("JOIN", _on_join, Color(0.4, 0.8, 1.0))
	join_btn.custom_minimum_size = Vector2(140, 0)
	join_row.add_child(join_btn)
	# parties on the same network (found automatically)
	lan_box = VBoxContainer.new()
	lan_box.add_theme_constant_override("separation", 4)
	box.add_child(lan_box)
	Net.link.lan_games_changed.connect(_refresh_lan)
	Net.link.listen_lan()

	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	box.add_child(row)
	row.add_child(_btn("Customize", _on_customize))
	row.add_child(_btn("Workshop", _on_workshop))
	row.add_child(_btn("Settings", func(): _open_settings(layer)))
	row.add_child(_btn("Quit", func(): get_tree().quit()))
	for c in row.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color(1, 1, 0.7))
	box.add_child(status)

	box.add_child(LauncherPanel.new())   # version, check for updates, install them

	var tip := Label.new()
	tip.text = TIPS[randi() % TIPS.size()]
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	box.add_child(tip)

## In-game updater: pick the new wobbly_hours.zip and its files are copied over this game folder
## (works when you run the game from the project folder / Godot editor; for an exported .exe use update.bat
## and export again). Your settings and characters live in your user folder and are not touched.
func _on_update() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.zip ; Game update"])
	fd.use_native_dialog = true
	fd.title = "Pick the new wobbly_hours.zip"
	layer.add_child(fd)
	fd.file_selected.connect(func(path: String):
		status.text = Updater.apply(path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(900, 600))

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _btn(text: String, on: Callable, color := Color(-1, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(on)
	if color.r >= 0.0:
		var ink := Color(0.12, 0.08, 0.2)
		b.add_theme_stylebox_override("normal", UITheme.box(color, ink, 12, 3, 4))
		b.add_theme_stylebox_override("hover", UITheme.box(color.lightened(0.25), ink, 12, 3, 6))
		b.add_theme_stylebox_override("pressed", UITheme.box(color.darkened(0.2), ink, 12, 3, 1))
		b.add_theme_font_size_override("font_size", 24)
	return b

func _start_music() -> void:
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_update_music_volume()
	# the song is rendered on a background thread so the menu opens instantly
	Sfx.tune_async("Menu Groove", func(st: AudioStreamWAV):
		if _music == null or not is_instance_valid(_music):
			return
		_music.stream = st
		if menu != null and menu.visible:
			_music.play())

func _update_music_volume() -> void:
	if _music != null:
		_music.volume_db = linear_to_db(maxf(Settings.music * 0.5, 0.0001))

func _on_host() -> void:
	Net.my_name = _clean_name()
	if Net.host():
		Net.link.stop_listening()
		_start_world()
	else:
		status.text = "Could not host (is the port already in use?)"

func _on_join() -> void:
	_join_text(ip_edit.text)

func _join_text(text: String) -> void:
	var cands := Invite.candidates(text, Net.PORT)
	if cands.is_empty():
		status.text = "That doesn't look like an invite code or an IP address"
		return
	var f := FileAccess.open(LAST_JOIN, FileAccess.WRITE)
	if f != null:
		f.store_string(text.strip_edges())
	Net.my_name = _clean_name()
	Net.link.stop_listening()
	_start_world()  # world must exist on the client before the server's spawns arrive
	_try_addresses(cands)

## Tries each address from the invite in turn (IPv6, the internet address, the home-network one),
## a few seconds each, over the (camera-less) world. Gives up with advice if none answer.
func _try_addresses(cands: Array) -> void:
	var note := Label.new()
	note.position = Vector2(14, 200)
	note.add_theme_font_size_override("font_size", 22)
	note.add_theme_color_override("font_outline_color", Color.BLACK)
	note.add_theme_constant_override("outline_size", 8)
	layer.add_child(note)
	var world_ref := world
	var joined := false
	Net.quiet_fail = true
	for ci in cands.size():
		var c: Dictionary = cands[ci]
		var shown := str(c["host"]) if not str(c["host"]).contains(":") else "[" + str(c["host"]) + "]"
		note.text = "Connecting to %s:%d ...  (%d of %d)" % [shown, int(c["port"]), ci + 1, cands.size()]
		if not Net.join(str(c["host"]), int(c["port"])):
			continue
		var wait := 12 if cands.size() == 1 else 8
		for i in wait:
			await get_tree().create_timer(0.5).timeout
			if world != world_ref or world == null:
				break
			if Net.players.has(multiplayer.get_unique_id()):
				joined = true
				break
			var peer := multiplayer.multiplayer_peer
			if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				break
		if joined or world != world_ref or world == null:
			break
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	Net.quiet_fail = false
	if is_instance_valid(note):
		note.queue_free()
	if world == world_ref and world != null and not joined:
		Net.leave()
		_teardown("Couldn't reach that party. Make sure the code is right and the host is still in the game. " +
			"If it keeps failing, the host's router may not have opened the port: the host's pause menu says what to do.")

## The "on your network" list under the join box.
func _refresh_lan() -> void:
	if lan_box == null:
		return
	for c in lan_box.get_children():
		c.queue_free()
	if Net.link.lan_games.is_empty():
		return
	var head := Label.new()
	head.text = "Parties on your network:"
	head.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	lan_box.add_child(head)
	for ip in Net.link.lan_games:
		var g: Dictionary = Net.link.lan_games[ip]
		var b := _btn("JOIN  %s  (%d player%s)" % [g["name"], g["players"], "" if int(g["players"]) == 1 else "s"],
			_join_text.bind("%s:%d" % [ip, int(g["port"])]), Color(0.55, 0.95, 0.75))
		lan_box.add_child(b)

func _clean_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if not n.is_empty() else "Player"

# -------------------------------------------------------------------- world
func _start_world() -> void:
	menu.hide()
	if _music != null:
		_music.stop()
	world = GameWorld.new()
	world.name = "World"  # identical node path on every peer, required for RPCs
	add_child(world)

func _teardown(message: String) -> void:
	_close_pause_ui()
	if world != null:
		remove_child(world)  # remove now so a quick rejoin gets the name "World" again
		world.queue_free()
		world = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show()
	status.text = message
	Net.link.listen_lan()
	if _music != null and _music.stream != null:
		_music.play()

# ------------------------------------------------------------------ overlays
func _on_customize() -> void:
	var layer2 := CanvasLayer.new()
	layer2.layer = 30
	add_child(layer2)
	var c := Customizer.new()
	c.theme = UITheme.shared()
	c.setup(Net.my_look)
	layer2.add_child(c)
	c.finished.connect(func(look: Dictionary, saved: bool):
		if saved:
			Net.set_my_look(look)
		layer2.queue_free())

func _on_workshop() -> void:
	var layer2 := CanvasLayer.new()
	layer2.layer = 30
	add_child(layer2)
	var w := Workshop.new()
	w.theme = UITheme.shared()
	layer2.add_child(w)
	w.closed.connect(layer2.queue_free)

func _open_settings(parent: Node) -> void:
	var l := CanvasLayer.new()
	l.layer = 40
	add_child(l)
	var sp := SettingsPanel.new()
	l.add_child(sp)
	sp.closed.connect(l.queue_free)

# -------------------------------------------------------------------- pause
func _open_pause(me: Player) -> void:
	me.input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 25
	add_child(_pause_layer)
	var pm := PauseMenu.new()
	_pause_layer.add_child(pm)
	pm.resume.connect(_resume)
	pm.open_settings.connect(func(): _open_settings(_pause_layer))
	pm.open_customizer.connect(_on_customize)
	pm.stuck.connect(func():
		var me2 := _my_player()
		if me2 != null:
			me2.stuck_respawn()
		_resume())
	pm.leave.connect(func():
		Net.leave()
		_teardown("You left the party"))
	pm.quit.connect(func(): get_tree().quit())

func _resume() -> void:
	_close_pause_ui()
	var me := _my_player()
	if me != null:
		me.input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _close_pause_ui() -> void:
	if _pause_layer != null:
		_pause_layer.queue_free()
		_pause_layer = null
