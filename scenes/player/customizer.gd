class_name Customizer
extends Control
## Character creator overlay (uses the low-poly character maker models by Fernando Lopez, CC-BY 4.0).
## Live 3D preview, male / female, a prev/next picker and colour swatches for every part.
## Used from the main menu and in game (K). Emits finished(look, saved).
## Build it with setup(current_look) before adding to the tree.

signal finished(look: Dictionary, saved: bool)

var look := {}
var npc := {}
var _body: NpcBody
var _pivot: Node3D
var _spin := 0.0
var _rows := {}        # category -> {"label": Label, "swatches": Control, "box": Control}
var _skin_swatches: Control
var _type_buttons := {}
var _building := false

func setup(initial: Dictionary) -> void:
	look = Look.sanitize(initial)
	npc = (look["npc"] as Dictionary).duplicate(true)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.1, 0.94)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	center.add_child(row)

	row.add_child(_build_preview())

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)

	var title := Label.new()
	title.text = "Make your character"
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)

	var tp := HBoxContainer.new()
	tp.add_theme_constant_override("separation", 8)
	col.add_child(tp)
	for t in NpcLook.TYPES:
		var b := Button.new()
		b.text = String(t).capitalize()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 0)
		b.pressed.connect(_set_type.bind(t))
		tp.add_child(b)
		_type_buttons[t] = b
	var rnd := Button.new()
	rnd.text = "Randomize"
	rnd.pressed.connect(_randomize)
	tp.add_child(rnd)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	_build_skin_row(list)
	for entry in NpcLook.CATS:
		_build_part_row(list, entry[0], entry[1])

	var credit := Label.new()
	credit.text = "Characters: Low Poly Character Maker by Fernando Lopez (CC-BY 4.0)"
	credit.add_theme_font_size_override("font_size", 12)
	credit.modulate = Color(1, 1, 1, 0.6)
	col.add_child(credit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)
	var save := Button.new()
	save.text = "Save & close"
	save.pressed.connect(_on_save)
	buttons.add_child(save)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): finished.emit(look, false))
	buttons.add_child(cancel)

	_rebuild_body()
	_refresh_ui()

func _build_preview() -> Control:
	var c := SubViewportContainer.new()
	c.custom_minimum_size = Vector2(360, 580)
	c.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(360, 580)
	c.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.14, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.9)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	vp.add_child(rim)

	_pivot = Node3D.new()
	vp.add_child(_pivot)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(0, 1.0, 4.4)
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.0, 4.4), Vector3(0, 0.92, 0))
	return c

func _rebuild_body() -> void:
	if _body != null:
		_body.queue_free()
		_body = null
	_body = NpcBody.new()
	_pivot.add_child(_body)
	if not _body.load_npc(npc):
		_body.queue_free()
		_body = null

func _process(delta: float) -> void:
	_spin += delta * 0.5
	if _pivot != null:
		_pivot.rotation.y = PI + sin(_spin) * 0.7   # NpcBody turns the model to face -Z (game forward); PI turns it back toward the preview camera at +Z

# ----------------------------------------------------------------- rows
func _swatch_row(colors: Array, on_pick: Callable, current_hex: String, picker_target: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(26, 26)
		var sb := UITheme.box(Color.html(str(c)), Color(0.12, 0.08, 0.2), 6, 2)
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var hx := str(c)
		b.pressed.connect(func(): on_pick.call(hx))
		flow.add_child(b)
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(44, 26)
	pick.edit_alpha = false
	pick.color = Color.html(current_hex)
	pick.color_changed.connect(func(col: Color): on_pick.call(col.to_html(false)))
	flow.add_child(pick)
	picker_target.append(pick)
	return flow

var _pickers := {}   # category (or "skin") -> ColorPickerButton

func _build_skin_row(list: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	list.add_child(box)
	var l := Label.new()
	l.text = "Skin"
	l.add_theme_font_size_override("font_size", 20)
	box.add_child(l)
	var tgt := []
	box.add_child(_swatch_row(NpcLook.SKIN, _pick_skin, str(npc.get("skin", "ffc399")), tgt))
	_pickers["skin"] = tgt[0]

func _build_part_row(list: VBoxContainer, cat: String, label: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	list.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(130, 0)
	l.add_theme_font_size_override("font_size", 20)
	head.add_child(l)
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(40, 0)
	prev.pressed.connect(_step.bind(cat, -1))
	head.add_child(prev)
	var val := Label.new()
	val.custom_minimum_size = Vector2(80, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(val)
	var nxt := Button.new()
	nxt.text = ">"
	nxt.custom_minimum_size = Vector2(40, 0)
	nxt.pressed.connect(_step.bind(cat, 1))
	head.add_child(nxt)
	var cur: Dictionary = (npc["parts"] as Dictionary).get(cat, {})
	var tgt := []
	var sw := _swatch_row(NpcLook.palette(cat), func(hx: String): _pick_color(hx, cat), str(cur.get("c", "ffffff")), tgt)
	box.add_child(sw)
	_pickers[cat] = tgt[0]
	_rows[cat] = {"label": val, "box": box}

# ------------------------------------------------------------- actions
func _set_type(t: String) -> void:
	npc["type"] = t
	npc = NpcLook.sanitize(npc)
	_rebuild_body()
	_refresh_ui()

func _randomize() -> void:
	npc = NpcLook.random()
	_rebuild_body()
	_refresh_ui()

func _step(cat: String, dir: int) -> void:
	var type := str(npc["type"])
	var n := NpcLook.count(type, cat)
	if n == 0:
		return
	var e: Dictionary = (npc["parts"] as Dictionary)[cat]
	var i := int(e["i"]) + dir
	if i < -1:
		i = n - 1
	elif i >= n:
		i = -1
	e["i"] = i
	_apply_live()

func _pick_color(hex: String, cat: String) -> void:
	((npc["parts"] as Dictionary)[cat] as Dictionary)["c"] = hex
	# hair colour is shared by hair, eyebrows and facial hair so they always match
	if cat == "hair" or cat == "browns" or cat == "facial":
		for other in ["hair", "browns", "facial"]:
			((npc["parts"] as Dictionary)[other] as Dictionary)["c"] = hex
	_apply_live()

func _pick_skin(hex: String) -> void:
	npc["skin"] = hex
	_apply_live()

func _apply_live() -> void:
	if _body != null:
		_body.apply(npc)
	_refresh_ui()

func _refresh_ui() -> void:
	var type := str(npc["type"])
	for t in _type_buttons:
		(_type_buttons[t] as Button).set_pressed_no_signal(t == type)
	for entry in NpcLook.CATS:
		var cat: String = entry[0]
		var n := NpcLook.count(type, cat)
		var row: Dictionary = _rows[cat]
		(row["box"] as Control).visible = n > 0
		if n == 0:
			continue
		var e: Dictionary = (npc["parts"] as Dictionary)[cat]
		var i := int(e["i"])
		(row["label"] as Label).text = "None" if i < 0 else "%d / %d" % [i + 1, n]
		var pk := _pickers[cat] as ColorPickerButton
		pk.color = Color.html(str(e["c"]))
	(_pickers["skin"] as ColorPickerButton).color = Color.html(str(npc["skin"]))

func _on_save() -> void:
	var d := look.duplicate(true)
	d["npc"] = npc.duplicate(true)
	d["model"] = ""     # the maker character replaces any Workshop model
	var c := NpcLook.classic_colors(npc)
	for k in c:
		d[k] = c[k]
	finished.emit(Look.sanitize(d), true)
