class_name Workshop
extends Control
## GMod-style Workshop: install characters and maps (.glb files) by drag and drop, from a link,
## or from the built-in / online catalog, then choose which ones to use.

signal closed

var _lists := {}      # kind -> VBoxContainer with the installed items
var _catalog_box := {}  # kind -> VBoxContainer with catalog entries
var _tabs: TabContainer
var _status: Label
var _url: LineEdit
var _name: LineEdit
var _cat_url: LineEdit
var _catalog: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.12, 0.96)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 560)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "WORKSHOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Drag a .glb file onto this window to install it into the open tab.  Models are shared with everyone in your party automatically."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for kind in Content.KINDS:
		_build_tab(kind)

	var dl := HBoxContainer.new()
	box.add_child(dl)
	_url = LineEdit.new()
	_url.placeholder_text = "Direct link to a .glb file (https://...)"
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.add_child(_url)
	_name = LineEdit.new()
	_name.placeholder_text = "Name"
	_name.custom_minimum_size = Vector2(150, 0)
	dl.add_child(_name)
	var get_btn := Button.new()
	get_btn.text = "Download"
	get_btn.pressed.connect(_on_download)
	dl.add_child(get_btn)

	var cat := HBoxContainer.new()
	box.add_child(cat)
	_cat_url = LineEdit.new()
	_cat_url.placeholder_text = "Optional: link to an online catalog (JSON list)"
	_cat_url.text = Content.catalog_url
	_cat_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat.add_child(_cat_url)
	var cat_btn := Button.new()
	cat_btn.text = "Refresh catalog"
	cat_btn.pressed.connect(_load_catalog)
	cat.add_child(cat_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func(): closed.emit())
	box.add_child(close)

	Content.changed.connect(_refresh)
	Content.status.connect(_on_status)
	Content.dropped.connect(_on_dropped)
	_refresh()
	_load_catalog()

func _build_tab(kind: String) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Characters" if kind == "characters" else "Maps"
	tab.add_theme_constant_override("separation", 6)
	_tabs.add_child(tab)
	var h := Label.new()
	h.text = "Installed"
	h.add_theme_font_size_override("font_size", 18)
	tab.add_child(h)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 140)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(sc)
	var lst := VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lst)
	_lists[kind] = lst
	var h2 := Label.new()
	h2.text = "Catalog"
	h2.add_theme_font_size_override("font_size", 18)
	tab.add_child(h2)
	var sc2 := ScrollContainer.new()
	sc2.custom_minimum_size = Vector2(0, 110)
	tab.add_child(sc2)
	var cb := VBoxContainer.new()
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(cb)
	_catalog_box[kind] = cb

func _kind() -> String:
	return Content.KINDS[_tabs.current_tab]

func _refresh() -> void:
	for kind in Content.KINDS:
		var lst: VBoxContainer = _lists[kind]
		for c in lst.get_children():
			c.queue_free()
		var using := str(Net.my_look.get("model", "")) if kind == "characters" else Content.selected_map
		var default_btn := Button.new()
		default_btn.text = ("Default body" if kind == "characters" else "Party house") + ("   (in use)" if using.is_empty() else "")
		default_btn.pressed.connect(_use.bind(kind, ""))
		lst.add_child(default_btn)
		for it in Content.list(kind):
			var row := HBoxContainer.new()
			lst.add_child(row)
			var l := Label.new()
			l.text = it["name"] + ("   (in use)" if it["id"] == using else "")
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var use_btn := Button.new()
			use_btn.text = "Use"
			use_btn.pressed.connect(_use.bind(kind, it["id"]))
			row.add_child(use_btn)
			var del := Button.new()
			del.text = "Delete"
			del.pressed.connect(_delete.bind(it))
			row.add_child(del)
	_fill_catalog()

func _use(kind: String, id: String) -> void:
	if kind == "characters":
		var look := Net.my_look.duplicate()
		look["model"] = id
		Net.set_my_look(look)
		_status.text = "Character set"
	else:
		Content.selected_map = id
		Content.save_settings()
		_status.text = "Map selected. It is used the next time you host a party."
	_refresh()

func _delete(item: Dictionary) -> void:
	if item["id"] == str(Net.my_look.get("model", "")):
		_use("characters", "")
	if item["id"] == Content.selected_map:
		_use("maps", "")
	Content.delete_item(item)

func _on_dropped(paths: PackedStringArray) -> void:
	for p in paths:
		Content.import_file(p, _kind())

func _on_download() -> void:
	var url := _url.text.strip_edges()
	if url.is_empty():
		_status.text = "Paste a link to a .glb file first"
		return
	var nm := _name.text.strip_edges()
	if nm.is_empty():
		nm = url.get_file().get_basename()
	Content.download(url, _kind(), nm)

func _load_catalog() -> void:
	Content.catalog_url = _cat_url.text.strip_edges()
	Content.save_settings()
	_catalog = await Content.fetch_catalog()
	_fill_catalog()

func _fill_catalog() -> void:
	for kind in Content.KINDS:
		var cb: VBoxContainer = _catalog_box[kind]
		for c in cb.get_children():
			c.queue_free()
		for e in _catalog:
			if str(e.get("kind", "")) != kind:
				continue
			var row := HBoxContainer.new()
			cb.add_child(row)
			var l := Label.new()
			l.text = "%s   (%s, %s)" % [e.get("name", "?"), e.get("author", "?"), e.get("license", "?")]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			row.add_child(l)
			var b := Button.new()
			b.text = "Get"
			b.pressed.connect(Content.download.bind(str(e.get("url", "")), kind, str(e.get("name", "model"))))
			row.add_child(b)

func _on_status(t: String) -> void:
	_status.text = t
