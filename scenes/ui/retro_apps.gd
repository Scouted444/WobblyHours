class_name RetroApps
extends RefCounted
## The programs on the 1995 computer. Each builder returns the content Control for a window.

const NOTE_PATH := "user://notepad.txt"

static func mono() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return f

# ----------------------------------------------------------------- Notepad
static func notepad() -> Control:
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(440, 300)
	te.add_theme_font_override("font", mono())
	if FileAccess.file_exists(NOTE_PATH):
		te.text = FileAccess.get_file_as_string(NOTE_PATH)
	else:
		te.text = "Dear diary,\n\ntoday I fell in the pool again.\n"
	te.text_changed.connect(func():
		var f := FileAccess.open(NOTE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(te.text))
	return te

# ------------------------------------------------------------------- About
static func about(player_name: String) -> Control:
	var rt := RichTextLabel.new()
	rt.custom_minimum_size = Vector2(430, 300)
	rt.bbcode_enabled = true
	rt.text = "[b]WELCOME.TXT[/b]\n\nHello, %s! This is [b]Wobbly 95[/b], the only operating system that is 40%% duck.\n\n[b]Programs[/b]\n- Notepad: it saves by itself\n- Paint: draw something, then Save (goes in your user folder)\n- Minesweeper: right-click flags a mine\n- Snake: arrow keys or WASD\n- Party Chat: talk to everyone in the party\n- Jukebox: everyone near this computer hears the music\n\n[b]In the house[/b]\nTab = spawn menu, RMB = pick up, LMB = use, G = throw, T = chat.\n\nPlease do not click FREE_PRIZE.exe." % player_name
	return rt

# ------------------------------------------------------------------- Paint
class PaintCanvas extends Control:
	var img: Image
	var tex: ImageTexture
	var color := Color.BLACK
	var radius := 3
	var _last := Vector2(-1, -1)

	func _init() -> void:
		custom_minimum_size = Vector2(440, 270)
		img = Image.create(440, 270, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		tex = ImageTexture.create_from_image(img)

	func clear() -> void:
		img.fill(Color.WHITE)
		tex.update(img)
		queue_redraw()

	func _draw() -> void:
		draw_texture(tex, Vector2.ZERO)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_last = event.position
				_stamp(event.position)
				_commit()
			else:
				_last = Vector2(-1, -1)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _last.x >= 0.0:
			var d: float = _last.distance_to(event.position)
			var n := maxi(1, int(d / 2.0))
			for i in n + 1:
				_stamp(_last.lerp(event.position, float(i) / n))
			_last = event.position
			_commit()

	func _stamp(p: Vector2) -> void:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
						img.set_pixel(x, y, color)

	func _commit() -> void:
		tex.update(img)
		queue_redraw()

static func paint() -> Control:
	var box := VBoxContainer.new()
	var canvas := PaintCanvas.new()
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var colors := [Color.BLACK, Color(0.5, 0.5, 0.5), Color(0.8, 0.1, 0.1), Color(1, 0.55, 0.1), Color(1, 0.9, 0.1), Color(0.1, 0.7, 0.2), Color(0.1, 0.8, 0.8), Color(0.1, 0.2, 0.9), Color(0.6, 0.2, 0.8), Color(1, 0.5, 0.7), Color(0.5, 0.3, 0.15), Color.WHITE]
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(24, 24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_border_width_all(1)
		sb.border_color = Color.BLACK
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func(): canvas.color = c)
		bar.add_child(b)
	var sl := HSlider.new()
	sl.min_value = 1
	sl.max_value = 14
	sl.value = 3
	sl.custom_minimum_size = Vector2(80, 0)
	sl.value_changed.connect(func(v: float): canvas.radius = int(v))
	bar.add_child(sl)
	var clr := Button.new()
	clr.text = "New"
	clr.pressed.connect(canvas.clear)
	bar.add_child(clr)
	var save := Button.new()
	save.text = "Save"
	var info := Label.new()
	save.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute("user://paintings")
		var path := "user://paintings/painting_%d.png" % Time.get_unix_time_from_system()
		canvas.img.save_png(path)
		info.text = "Saved to " + ProjectSettings.globalize_path(path))
	bar.add_child(save)
	box.add_child(canvas)
	info.clip_text = true
	info.custom_minimum_size = Vector2(440, 0)
	box.add_child(info)
	return box

# ------------------------------------------------------------- Minesweeper
class Mines extends VBoxContainer:
	const W := 9
	const H := 9
	const M := 10
	var mine := []
	var count := []
	var state := []     # 0 hidden, 1 open, 2 flag
	var buttons := []
	var placed := false
	var over := false
	var elapsed := 0.0
	var face: Button
	var info: Label

	func _ready() -> void:
		var top := HBoxContainer.new()
		add_child(top)
		info = Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(info)
		face = Button.new()
		face.text = ":)"
		face.custom_minimum_size = Vector2(40, 28)
		face.pressed.connect(reset)
		top.add_child(face)
		var grid := GridContainer.new()
		grid.columns = W
		grid.add_theme_constant_override("h_separation", 0)
		grid.add_theme_constant_override("v_separation", 0)
		add_child(grid)
		for i in W * H:
			var b := Button.new()
			b.custom_minimum_size = Vector2(28, 28)
			b.focus_mode = Control.FOCUS_NONE
			b.gui_input.connect(_cell_input.bind(i))
			grid.add_child(b)
			buttons.append(b)
		reset()

	func reset() -> void:
		mine = []
		count = []
		state = []
		for i in W * H:
			mine.append(false)
			count.append(0)
			state.append(0)
		placed = false
		over = false
		elapsed = 0.0
		face.text = ":)"
		_refresh()

	func _process(delta: float) -> void:
		if placed and not over:
			elapsed += delta
		var flags := 0
		for s in state:
			if s == 2:
				flags += 1
		info.text = "Mines: %02d    Time: %03d" % [M - flags, int(elapsed)]

	func _neighbors(i: int) -> Array:
		var out := []
		var x := i % W
		var y := i / W
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if nx >= 0 and ny >= 0 and nx < W and ny < H:
					out.append(ny * W + nx)
		return out

	func _place(safe: int) -> void:
		placed = true
		var n := 0
		while n < M:
			var c := randi() % (W * H)
			if c != safe and not mine[c]:
				mine[c] = true
				n += 1
		for i in W * H:
			var k := 0
			for nb in _neighbors(i):
				if mine[nb]:
					k += 1
			count[i] = k

	func _cell_input(event: InputEvent, i: int) -> void:
		if over or not (event is InputEventMouseButton) or not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if state[i] == 0:
				state[i] = 2
			elif state[i] == 2:
				state[i] = 0
		elif event.button_index == MOUSE_BUTTON_LEFT and state[i] == 0:
			if not placed:
				_place(i)
			_reveal(i)
		_refresh()
		_check_win()

	func _reveal(start: int) -> void:
		var stack := [start]
		while not stack.is_empty():
			var i: int = stack.pop_back()
			if state[i] != 0:
				continue
			state[i] = 1
			if mine[i]:
				over = true
				face.text = "X("
				for k in W * H:
					if mine[k]:
						state[k] = 1
				return
			if count[i] == 0:
				for nb in _neighbors(i):
					if state[nb] == 0:
						stack.append(nb)

	func _check_win() -> void:
		if over:
			return
		for i in W * H:
			if not mine[i] and state[i] != 1:
				return
		over = true
		face.text = "B)"

	func _refresh() -> void:
		var cols := [Color.BLACK, Color(0, 0, 1), Color(0, 0.5, 0), Color(1, 0, 0), Color(0, 0, 0.5), Color(0.5, 0, 0), Color(0, 0.5, 0.5), Color.BLACK, Color(0.5, 0.5, 0.5)]
		for i in W * H:
			var b: Button = buttons[i]
			b.add_theme_color_override("font_color", Color.BLACK)
			b.flat = state[i] == 1
			match int(state[i]):
				0:
					b.text = ""
				2:
					b.text = "P"
					b.add_theme_color_override("font_color", Color(0.8, 0, 0))
				_:
					if mine[i]:
						b.text = "*"
					else:
						b.text = str(count[i]) if count[i] > 0 else ""
						b.add_theme_color_override("font_color", cols[count[i]])

static func minesweeper() -> Control:
	return Mines.new()

# ------------------------------------------------------------------- Snake
class Snake extends Control:
	const CW := 22
	const CH := 16
	const CELL := 16
	var body: Array[Vector2i] = []
	var dir := Vector2i(1, 0)
	var queued := Vector2i(1, 0)
	var food := Vector2i(10, 8)
	var acc := 0.0
	var alive := true
	var score := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(CW * CELL, CH * CELL + 22)
		focus_mode = Control.FOCUS_ALL
		reset()
		call_deferred("grab_focus")

	func reset() -> void:
		body = [Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8)]
		dir = Vector2i(1, 0)
		queued = dir
		alive = true
		score = 0
		_new_food()

	func _new_food() -> void:
		for t in 100:
			var f := Vector2i(randi() % CW, randi() % CH)
			if not body.has(f):
				food = f
				return

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			grab_focus()
		if event is InputEventKey and event.pressed:
			var d := Vector2i.ZERO
			match event.keycode:
				KEY_UP, KEY_W: d = Vector2i(0, -1)
				KEY_DOWN, KEY_S: d = Vector2i(0, 1)
				KEY_LEFT, KEY_A: d = Vector2i(-1, 0)
				KEY_RIGHT, KEY_D: d = Vector2i(1, 0)
				KEY_SPACE, KEY_ENTER:
					if not alive:
						reset()
			if d != Vector2i.ZERO and d != -dir:
				queued = d
			accept_event()

	func _process(delta: float) -> void:
		if not alive or not is_visible_in_tree():
			return
		acc += delta
		if acc < 0.11:
			return
		acc = 0.0
		dir = queued
		var head := body[0] + dir
		if head.x < 0 or head.y < 0 or head.x >= CW or head.y >= CH or body.has(head):
			alive = false
			queue_redraw()
			return
		body.push_front(head)
		if head == food:
			score += 1
			_new_food()
		else:
			body.pop_back()
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0, 0, CW * CELL, CH * CELL), Color(0.05, 0.12, 0.05))
		draw_rect(Rect2(food.x * CELL + 2, food.y * CELL + 2, CELL - 4, CELL - 4), Color(1, 0.2, 0.2))
		for i in body.size():
			draw_rect(Rect2(body[i].x * CELL + 1, body[i].y * CELL + 1, CELL - 2, CELL - 2), Color(0.4, 1, 0.4) if i == 0 else Color(0.2, 0.8, 0.2))
		var f := ThemeDB.fallback_font
		var msg := "Score: %d" % score if alive else "GAME OVER  (Space to retry)   Score: %d" % score
		draw_string(f, Vector2(4, CH * CELL + 16), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)

static func snake() -> Control:
	return Snake.new()

# ---------------------------------------------------------------- Party Chat
class ChatApp extends VBoxContainer:
	var feed: RichTextLabel
	var entry: LineEdit
	var world: GameWorld

	func _ready() -> void:
		feed = RichTextLabel.new()
		feed.custom_minimum_size = Vector2(400, 230)
		feed.scroll_following = true
		feed.bbcode_enabled = true
		add_child(feed)
		var h := HBoxContainer.new()
		add_child(h)
		entry = LineEdit.new()
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.max_length = 140
		entry.placeholder_text = "type a message and press Enter"
		entry.text_submitted.connect(_send)
		h.add_child(entry)
		var b := Button.new()
		b.text = "Send"
		b.pressed.connect(func(): _send(entry.text))
		h.add_child(b)
		if world != null:
			for m in world.chat_log:
				_add(str(m[0]), str(m[1]))
			world.chat_message.connect(_add)
		else:
			feed.text = "(not connected)"

	func _add(sender: String, text: String) -> void:
		feed.append_text("[b]%s[/b]: %s\n" % [sender.replace("[", "("), text.replace("[", "(")])

	func _send(t: String) -> void:
		if world != null and not t.strip_edges().is_empty():
			world.chat_say.rpc(t)
		entry.text = ""
		entry.grab_focus()

static func chat(world: GameWorld) -> Control:
	var c := ChatApp.new()
	c.world = world
	return c

# ------------------------------------------------------------------ Jukebox
class JukeboxApp extends VBoxContainer:
	var world: GameWorld
	var at := Vector3.ZERO
	var now: Label
	var local := AudioStreamPlayer.new()

	func _ready() -> void:
		custom_minimum_size = Vector2(340, 0)
		local.bus = &"Music"
		local.add_to_group("user_music")   # the background radio fades out while this plays
		add_child(local)
		now = Label.new()
		now.text = "Pick a song. Everyone near this computer hears it."
		now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(now)
		for t in Sfx.TUNE_NAMES:
			var b := Button.new()
			b.text = "> " + t
			b.pressed.connect(_play.bind(t))
			add_child(b)
		var stop := Button.new()
		stop.text = "[] Stop"
		stop.pressed.connect(_stop)
		add_child(stop)
		var hint := Label.new()
		hint.text = "Drop an .mp3 or .ogg file on the game window to play your own music (only you hear that)."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
		Content.dropped.connect(_on_drop)

	func _play(t: String) -> void:
		local.stop()
		if world != null:
			world.jukebox.rpc(t, at)
		now.text = "Now playing: " + t

	func _stop() -> void:
		local.stop()
		if world != null:
			world.jukebox.rpc("", Vector3.ZERO)
		now.text = "Stopped."

	func _on_drop(paths: PackedStringArray) -> void:
		for p in paths:
			var ext := p.get_extension().to_lower()
			var bytes := FileAccess.get_file_as_bytes(p)
			var st: AudioStream = null
			if ext == "mp3":
				var m := AudioStreamMP3.new()
				m.data = bytes
				st = m
			elif ext == "ogg":
				st = AudioStreamOggVorbis.load_from_buffer(bytes)
			if st != null:
				if world != null:
					world.jukebox.rpc("", Vector3.ZERO)
				local.stream = st
				local.play()
				now.text = "Playing " + p.get_file() + " (just for you)"
				return

static func jukebox(world: GameWorld, at: Vector3) -> Control:
	var j := JukeboxApp.new()
	j.world = world
	j.at = at
	return j

# --------------------------------------------------------- jokes and popups
const ERRORS := [
	"Wobbly 95 has performed an illegal flop and will be shut down.",
	"Not enough duck. Insert more duck.",
	"A fatal exception 0E has occurred at 0028:C0011E36. Just kidding. Congratulations!",
	"The pool is full. Please empty your pool.",
	"Keyboard not found. Press F1 to continue.",
	"You have won a free prize! (prize not found)",
	"Gravity.dll is missing. Floating is now enabled.",
]

static func popup(pc: Control, depth := 0) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	var l := Label.new()
	l.text = ERRORS[randi() % ERRORS.size()]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(290, 50)
	box.add_child(l)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(80, 26)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ok)
	var rect := pc.get_viewport_rect().size
	var w := RetroWindow.make("Error", box, Vector2(randf_range(80, maxf(100, rect.x - 400)), randf_range(40, maxf(60, rect.y - 220))))
	pc.get_node("Windows").add_child(w)
	Sfx.play_ui(pc, "error")
	ok.pressed.connect(func():
		w.close()
		if depth < 6 and randf() < 0.45:
			popup(pc, depth + 1)
			popup(pc, depth + 1))

static func recycle_bin(player: Player) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	var l := Label.new()
	l.text = "Recycle Bin contains 1 object:\n\n   duck.exe   (squeaky, 0 KB)"
	box.add_child(l)
	var b := Button.new()
	b.text = "Restore duck.exe"
	b.pressed.connect(func():
		if is_instance_valid(player):
			player.spawn_kind("duck")
		b.text = "Restored! Check the room.")
	box.add_child(b)
	return box
