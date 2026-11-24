class_name RetroPC
extends Control
## The 1995 computer in the bedroom: BIOS boot, teal desktop, taskbar, draggable windows,
## and a handful of programs. Esc powers it off.

signal closed

var world: GameWorld
var player: Player
var pc: Node3D
var _windows: Control
var _task_buttons: HBoxContainer
var _start_menu: PanelContainer
var _clock: Label
var _boot: Control
var _saver: Control
var _idle := 0.0
var _taskbar: PanelContainer
var _tab_for := {}   # RetroWindow -> Button
var _skip_boot := false
var _saver_pos := Vector2(100, 100)
var _saver_vel := Vector2(130, 95)
var _booted := false

const PROGRAMS := [
	["Notepad", "notepad"], ["Paint", "paint"], ["Minesweeper", "mines"], ["Snake", "snake"],
	["Party Chat", "chat"], ["Jukebox", "jukebox"], ["WELCOME.TXT", "about"],
	["Recycle Bin", "bin"], ["FREE_PRIZE.exe", "prize"],
]

func setup(w: GameWorld, p: Player, node: Node3D) -> void:
	world = w
	player = p
	pc = node

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = _make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.5, 0.5)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_start_menu.hide())
	var mark := Label.new()
	mark.text = "Wobbly 95"
	mark.add_theme_font_size_override("font_size", 40)
	mark.add_theme_color_override("font_color", Color(0.0, 0.4, 0.4))
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.anchor_top = 1.0
	mark.anchor_bottom = 1.0
	mark.offset_left = -260
	mark.offset_top = -110
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)

	var icons := Control.new()
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icons)
	icons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in PROGRAMS.size():
		var ic := DeskIcon.new()
		ic.label = PROGRAMS[i][0]
		ic.kind = PROGRAMS[i][1]
		ic.position = Vector2(14 + (i / 6) * 96, 12 + (i % 6) * 92)
		ic.opened.connect(_open.bind(PROGRAMS[i][1]))
		icons.add_child(ic)

	_windows = Control.new()
	_windows.name = "Windows"
	_windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_windows)
	_windows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_taskbar()
	_build_start_menu()

	_saver = Control.new()
	_saver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saver.hide()
	add_child(_saver)
	_saver.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_saver.draw.connect(_draw_saver)

	var scan := Scanlines.new()
	add_child(scan)
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_boot = Control.new()
	add_child(_boot)
	_boot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_boot()

# ------------------------------------------------------------------- theme
static func _bevel(raised: bool, center: Color) -> StyleBoxTexture:
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(center)
	var white := Color(1, 1, 1)
	var light := Color(0.87, 0.87, 0.87)
	var gray := Color(0.5, 0.5, 0.5)
	var black := Color(0.05, 0.05, 0.05)
	var o_tl := white if raised else gray
	var o_br := black if raised else white
	var i_tl := light if raised else black
	var i_br := gray if raised else light
	for k in 6:
		img.set_pixel(k, 0, o_tl)
		img.set_pixel(0, k, o_tl)
		img.set_pixel(k, 5, o_br)
		img.set_pixel(5, k, o_br)
	for k in range(1, 5):
		img.set_pixel(k, 1, i_tl)
		img.set_pixel(1, k, i_tl)
		img.set_pixel(k, 4, i_br)
		img.set_pixel(4, k, i_br)
	img.set_pixel(5, 0, o_br if raised else white)
	img.set_pixel(0, 5, o_br if raised else white)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = 2
	sb.texture_margin_right = 2
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 2
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

static func _make_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Tahoma", "MS Sans Serif", "Segoe UI", "Arial"])
	t.default_font = f
	t.default_font_size = 14
	var face := Color(0.75, 0.75, 0.75)
	t.set_stylebox("normal", "Button", _bevel(true, face))
	t.set_stylebox("hover", "Button", _bevel(true, face))
	t.set_stylebox("pressed", "Button", _bevel(false, face))
	t.set_stylebox("disabled", "Button", _bevel(true, face))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", _bevel(true, face))
	t.set_stylebox("panel", "Panel", _bevel(true, face))
	t.set_stylebox("normal", "LineEdit", _bevel(false, Color.WHITE))
	t.set_stylebox("focus", "LineEdit", _bevel(false, Color.WHITE))
	t.set_stylebox("normal", "TextEdit", _bevel(false, Color.WHITE))
	t.set_stylebox("focus", "TextEdit", _bevel(false, Color.WHITE))
	t.set_stylebox("normal", "RichTextLabel", _bevel(false, Color.WHITE))
	for type in ["Button", "Label", "LineEdit", "TextEdit", "RichTextLabel", "CheckBox"]:
		t.set_color("font_color", type, Color.BLACK)
	t.set_color("default_color", "RichTextLabel", Color.BLACK)
	t.set_color("font_hover_color", "Button", Color.BLACK)
	t.set_color("font_pressed_color", "Button", Color.BLACK)
	t.set_color("caret_color", "TextEdit", Color.BLACK)
	t.set_color("caret_color", "LineEdit", Color.BLACK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.4, 0.4, 0.4))
	t.set_color("font_readonly_color", "TextEdit", Color.BLACK)
	t.set_color("selection_color", "TextEdit", Color(0, 0, 0.5, 0.5))
	t.set_color("selection_color", "LineEdit", Color(0, 0, 0.5, 0.5))
	return t

# --------------------------------------------------------------- taskbar
func _build_taskbar() -> void:
	_taskbar = PanelContainer.new()
	_taskbar.anchor_top = 1.0
	_taskbar.anchor_bottom = 1.0
	_taskbar.anchor_right = 1.0
	_taskbar.offset_top = -36
	add_child(_taskbar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	_taskbar.add_child(h)
	var start := Button.new()
	start.text = " Start "
	start.add_theme_font_size_override("font_size", 16)
	start.pressed.connect(func(): _start_menu.visible = not _start_menu.visible)
	h.add_child(start)
	_task_buttons = HBoxContainer.new()
	_task_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_buttons.add_theme_constant_override("separation", 3)
	h.add_child(_task_buttons)
	_clock = Label.new()
	_clock.custom_minimum_size = Vector2(80, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(_clock)

func _build_start_menu() -> void:
	_start_menu = PanelContainer.new()
	_start_menu.anchor_top = 1.0
	_start_menu.anchor_bottom = 1.0
	_start_menu.offset_top = -330
	_start_menu.offset_bottom = -36
	_start_menu.offset_right = 220
	_start_menu.hide()
	add_child(_start_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_start_menu.add_child(v)
	var head := Label.new()
	head.text = "  Wobbly 95  Programs"
	head.add_theme_font_size_override("font_size", 15)
	v.add_child(head)
	for p in PROGRAMS:
		var b := Button.new()
		b.text = p[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_start_menu.hide()
			_open(p[1]))
		v.add_child(b)
	var sd := Button.new()
	sd.text = "Shut Down..."
	sd.alignment = HORIZONTAL_ALIGNMENT_LEFT
	sd.pressed.connect(_shutdown)
	v.add_child(sd)

# --------------------------------------------------------------- windows
func _open(kind: String) -> void:
	_start_menu.hide()
	var title := ""
	var content: Control = null
	match kind:
		"notepad":
			title = "Notepad - Untitled"
			content = RetroApps.notepad()
		"paint":
			title = "Paint"
			content = RetroApps.paint()
		"mines":
			title = "Minesweeper"
			content = RetroApps.minesweeper()
		"snake":
			title = "Snake"
			content = RetroApps.snake()
		"chat":
			title = "Party Chat"
			content = RetroApps.chat(world)
		"jukebox":
			title = "Jukebox"
			content = RetroApps.jukebox(world, pc.global_position + Vector3(0, 1.0, 0) if pc != null else Vector3.ZERO)
		"about":
			title = "WELCOME.TXT - Notepad"
			content = RetroApps.about(str(Net.my_name))
		"bin":
			title = "Recycle Bin"
			content = RetroApps.recycle_bin(player)
		"prize":
			RetroApps.popup(self)
			return
	if content == null:
		return
	var w := RetroWindow.make(title, content, Vector2(randf_range(120, 260), randf_range(30, 90)))
	_windows.add_child(w)
	Sfx.play_ui(self, "pop")
	var tb := Button.new()
	tb.text = title.left(18)
	tb.custom_minimum_size = Vector2(130, 0)
	tb.pressed.connect(func():
		if w.visible and w.get_index() == _windows.get_child_count() - 1:
			w.hide()
		else:
			w.show()
			w.move_to_front())
	_task_buttons.add_child(tb)
	_tab_for[w] = tb
	w.minimized.connect(func(): w.hide())
	w.closed.connect(func():
		tb.queue_free()
		_tab_for.erase(w))

# ------------------------------------------------------------------ boot
func _run_boot() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	_boot.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := Label.new()
	l.position = Vector2(30, 24)
	l.add_theme_font_override("font", RetroApps.mono())
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	_boot.add_child(l)
	_boot.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_skip_boot = true)
	var lines := [
		"WOBBLY BIOS v1.04  (C) 1995 Wobbly Systems",
		"CPU: 486DX2 @ 66MHz ...... OK",
		"Memory test: 4096K OK",
		"Detecting drives ... C: (the pool)",
		"Loading duck.sys ... squeak",
		"Loading flop.drv ... OK",
		"",
		"Starting Wobbly 95..."]
	for line in lines:
		if _skip_boot or not is_inside_tree():
			break
		l.text += line + "\n"
		await get_tree().create_timer(0.28).timeout
	if not is_inside_tree():
		return
	if not _skip_boot:
		Sfx.play_ui(self, "boot")
		await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	_boot.queue_free()
	_booted = true

# --------------------------------------------------------------- shutdown
func _shutdown() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := Label.new()
	l.text = "It's now safe to turn off your computer."
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	black.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.position -= Vector2(300, 0)
	await get_tree().create_timer(1.4).timeout
	if is_inside_tree():
		closed.emit()
		queue_free()

# ---------------------------------------------------------- idle + saver
func _process(delta: float) -> void:
	_clock.text = Time.get_time_string_from_system().left(5)
	if not _booted:
		return
	_idle += delta
	if _idle > 25.0:
		_saver.show()
		var r := get_viewport_rect().size
		_saver_pos += _saver_vel * delta
		if _saver_pos.x < 0.0 or _saver_pos.x > r.x - 260.0:
			_saver_vel.x = -_saver_vel.x
		if _saver_pos.y < 40.0 or _saver_pos.y > r.y - 80.0:
			_saver_vel.y = -_saver_vel.y
		_saver_pos = _saver_pos.clamp(Vector2(0, 40), Vector2(maxf(r.x - 260.0, 1.0), maxf(r.y - 80.0, 41.0)))
		_saver.queue_redraw()

func _draw_saver() -> void:
	_saver.draw_rect(Rect2(Vector2.ZERO, _saver.size), Color.BLACK)
	var hue := fmod(Time.get_ticks_msec() / 3000.0, 1.0)
	_saver.draw_string(ThemeDB.fallback_font, _saver_pos, "WOBBLY 95", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color.from_hsv(hue, 0.8, 1.0))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		_idle = 0.0
		_saver.hide()
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()

# ----------------------------------------------------------- helper classes
class Scanlines extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.07), 1.0)
			y += 3.0

class DeskIcon extends Control:
	signal opened
	var label := ""
	var kind := ""
	var _sel := false

	func _ready() -> void:
		custom_minimum_size = Vector2(86, 84)
		size = Vector2(86, 84)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_sel = true
			queue_redraw()
			if event.double_click:
				opened.emit()
			else:
				get_tree().create_timer(2.0).timeout.connect(_unsel)

	func _unsel() -> void:
		_sel = false
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(43, 28)
		var ink := Color.BLACK
		match kind:
			"notepad":
				draw_rect(Rect2(c + Vector2(-16, -22), Vector2(32, 42)), Color.WHITE)
				draw_rect(Rect2(c + Vector2(-16, -22), Vector2(32, 42)), ink, false, 2.0)
				for i in 5:
					draw_line(c + Vector2(-11, -14 + i * 8), c + Vector2(11, -14 + i * 8), Color(0.2, 0.3, 0.8), 1.5)
			"paint":
				draw_rect(Rect2(c + Vector2(-20, -16), Vector2(40, 34)), Color(0.95, 0.9, 0.8))
				draw_rect(Rect2(c + Vector2(-20, -16), Vector2(40, 34)), ink, false, 2.0)
				for i in 4:
					draw_circle(c + Vector2(-10 + i * 7, -4 + (i % 2) * 8), 4.0, Color.from_hsv(i * 0.25, 0.9, 1.0))
			"mines":
				draw_rect(Rect2(c + Vector2(-18, -18), Vector2(36, 36)), Color(0.75, 0.75, 0.75))
				draw_rect(Rect2(c + Vector2(-18, -18), Vector2(36, 36)), ink, false, 2.0)
				draw_circle(c, 9.0, ink)
				for a in 4:
					var d := Vector2(cos(a * PI / 4.0), sin(a * PI / 4.0)) * 13.0
					draw_line(c - d, c + d, ink, 2.0)
				draw_circle(c + Vector2(-3, -3), 2.5, Color.WHITE)
			"snake":
				draw_rect(Rect2(c + Vector2(-20, -18), Vector2(40, 36)), Color(0.05, 0.15, 0.05))
				for i in 5:
					draw_rect(Rect2(c + Vector2(-16 + i * 7, -2 + (i % 2) * -8), Vector2(6, 6)), Color(0.4, 1.0, 0.4))
				draw_rect(Rect2(c + Vector2(12, 8), Vector2(6, 6)), Color(1, 0.2, 0.2))
			"chat":
				draw_rect(Rect2(c + Vector2(-20, -18), Vector2(40, 26)), Color(1, 0.9, 0.3))
				draw_rect(Rect2(c + Vector2(-20, -18), Vector2(40, 26)), ink, false, 2.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 8), c + Vector2(-14, 20), c + Vector2(2, 8)]), Color(1, 0.9, 0.3))
				for i in 3:
					draw_circle(c + Vector2(-10 + i * 10, -5), 2.5, ink)
			"jukebox":
				draw_rect(Rect2(c + Vector2(-17, -20), Vector2(34, 40)), Color(0.8, 0.3, 0.5))
				draw_rect(Rect2(c + Vector2(-17, -20), Vector2(34, 40)), ink, false, 2.0)
				draw_circle(c + Vector2(-4, 8), 5.0, ink)
				draw_line(c + Vector2(0, 8), c + Vector2(0, -10), ink, 2.5)
				draw_line(c + Vector2(0, -10), c + Vector2(9, -6), ink, 2.5)
			"about":
				draw_rect(Rect2(c + Vector2(-16, -22), Vector2(32, 42)), Color(1, 1, 0.8))
				draw_rect(Rect2(c + Vector2(-16, -22), Vector2(32, 42)), ink, false, 2.0)
				draw_string(ThemeDB.fallback_font, c + Vector2(-8, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.8, 0.1, 0.1))
			"bin":
				draw_rect(Rect2(c + Vector2(-13, -14), Vector2(26, 34)), Color(0.7, 0.75, 0.8))
				draw_rect(Rect2(c + Vector2(-13, -14), Vector2(26, 34)), ink, false, 2.0)
				draw_rect(Rect2(c + Vector2(-17, -20), Vector2(34, 6)), Color(0.55, 0.6, 0.65))
				for i in 3:
					draw_line(c + Vector2(-6 + i * 6, -8), c + Vector2(-6 + i * 6, 14), ink, 1.5)
			_:
				draw_rect(Rect2(c + Vector2(-18, -18), Vector2(36, 36)), Color(1, 0.3, 0.6))
				draw_rect(Rect2(c + Vector2(-18, -18), Vector2(36, 36)), ink, false, 2.0)
				draw_string(ThemeDB.fallback_font, c + Vector2(-10, 10), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
		var f := ThemeDB.fallback_font
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var tp := Vector2(43 - tw * 0.5, 72)
		if _sel:
			draw_rect(Rect2(tp + Vector2(-2, -13), Vector2(tw + 4, 17)), Color(0, 0, 0.5))
		draw_string(f, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
