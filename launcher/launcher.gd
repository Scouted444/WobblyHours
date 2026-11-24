extends Control
## Wobbly Hours Launcher. Lives next to the game:
##
##   Wobbly Hours/
##     WobblyLauncher.exe      <- this
##     launcher.json           <- {"url": "<link to latest.json>"}  (made by tools/make_release.ps1)
##     game/WobblyHours.exe    <- the game (+ .pck, version.txt)
##
## On start it checks the link for a newer version. "UPDATE" (or "INSTALL" when there is no game yet)
## downloads the zip with a progress bar and unpacks it into game/. "PLAY" starts the game and closes
## the launcher. "Update from a zip..." installs a zip you were sent.

const GAME_DIR := "game"
const GAME_EXE := "WobblyHours.exe"

var _root := ""             # folder the launcher sits in
var _installed := ""        # version in game/version.txt ("" = not installed)
var _latest := {}
var _downloading := false
var _zip_path := ""

var _title: Label
var _ver: Label
var _status: Label
var _notes: Label
var _bar: ProgressBar
var _play: Button
var _update: Button
var _url_edit: LineEdit
var _http: HTTPRequest

func _ready() -> void:
	_root = OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	_root = _root.trim_suffix("/")
	_build_ui()
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_refresh_installed()
	_check()

# -------------------------------------------------------------------------- UI
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.1, 0.25)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stripes := ColorRect.new()
	stripes.color = Color(1.0, 0.45, 0.6, 0.12)
	stripes.position = Vector2(-200, 330)
	stripes.size = Vector2(1400, 90)
	stripes.rotation = -0.2
	add_child(stripes)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 36)
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	m.add_child(box)

	_title = Label.new()
	_title.text = "WOBBLY HOURS"
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_title.add_theme_color_override("font_outline_color", Color(0.45, 0.1, 0.35))
	_title.add_theme_constant_override("outline_size", 18)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_ver = Label.new()
	_ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ver.add_theme_font_size_override("font_size", 18)
	box.add_child(_ver)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	box.add_child(_status)

	_notes = Label.new()
	_notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(_notes)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 22)
	_bar.visible = false
	box.add_child(_bar)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_update = _big_button("UPDATE", Color(0.4, 0.8, 1.0))
	_update.pressed.connect(_download)
	_update.visible = false
	row.add_child(_update)
	_play = _big_button("PLAY", Color(0.45, 0.9, 0.5))
	_play.pressed.connect(_launch)
	row.add_child(_play)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row2)
	for e in [["Check for updates", _check], ["Update from a zip...", _pick_zip], ["Update link...", _toggle_link], ["Open game folder", _open_folder]]:
		var b := Button.new()
		b.text = e[0]
		b.pressed.connect(e[1])
		row2.add_child(b)
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "Paste the update link (…/latest.json) and press Enter"
	_url_edit.visible = false
	_url_edit.text_submitted.connect(func(t: String):
		_save_url(t.strip_edges())
		_url_edit.visible = false
		_check())
	box.add_child(_url_edit)

func _big_button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 64)
	b.add_theme_font_size_override("font_size", 28)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.2) if st == "hover" else (col.darkened(0.25) if st == "pressed" else (col.darkened(0.5) if st == "disabled" else col))
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.12, 0.08, 0.2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(0.12, 0.08, 0.2))
	b.add_theme_color_override("font_hover_color", Color(0.12, 0.08, 0.2))
	return b

func _process(_delta: float) -> void:
	if _downloading:
		var total := _http.get_body_size()
		var got := _http.get_downloaded_bytes()
		if total > 0:
			_bar.value = 100.0 * got / total
			_status.text = "Downloading... %.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0]
		else:
			_status.text = "Downloading... %.1f MB" % (got / 1048576.0)

# ------------------------------------------------------------------- versions
func _game_dir() -> String:
	return _root + "/" + GAME_DIR

func _refresh_installed() -> void:
	_installed = ""
	if FileAccess.file_exists(_game_dir() + "/" + GAME_EXE):
		_installed = "?"
		var f := FileAccess.open(_game_dir() + "/version.txt", FileAccess.READ)
		if f != null:
			_installed = f.get_as_text().strip_edges().split(" ")[0]
	_ver.text = "Installed: version %s" % _installed if _installed != "" else "The game isn't installed yet"
	_play.disabled = _installed == ""

static func _compare(a: String, b: String) -> int:
	var pa := a.strip_edges().split(" ")[0].split(".")
	var pb := b.strip_edges().split(" ")[0].split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0

# ---------------------------------------------------------------- update link
func _url() -> String:
	var path := _root + "/launcher.json"
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			return str(d.get("url", "")).strip_edges()
	return ""

func _save_url(u: String) -> void:
	var f := FileAccess.open(_root + "/launcher.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"url": u}, "\t"))

func _toggle_link() -> void:
	_url_edit.visible = not _url_edit.visible
	_url_edit.text = _url()

func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(_game_dir())
	OS.shell_open(_game_dir())

# ------------------------------------------------------------------- checking
func _check() -> void:
	var u := _url()
	_update.visible = false
	if u == "":
		_status.text = "No update link yet. Press \"Update link...\" and paste the one the host gave you,\nor use \"Update from a zip...\"."
		return
	if _downloading:
		return
	_http.cancel_request()
	_http.download_file = ""
	_status.text = "Checking for updates..."
	for c in _http.request_completed.get_connections():
		_http.request_completed.disconnect(c["callable"])
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(u + ("&" if "?" in u else "?") + "t=%d" % int(Time.get_unix_time_from_system())) != OK:
		_status.text = "That update link doesn't work."

func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		_status.text = "Couldn't reach the update link (error %d / %d). You can still play." % [result, code]
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary) or not (d as Dictionary).has("version") or str((d as Dictionary).get("windows", "")) == "":
		_status.text = "The update link didn't give a proper latest.json."
		return
	_latest = d
	var v := str(_latest["version"])
	_notes.text = str(_latest.get("notes", ""))
	if _installed == "":
		_status.text = "Version %s is ready to install." % v
		_update.text = "INSTALL"
		_update.visible = true
	elif _installed == "?" or _compare(v, _installed) > 0:
		_status.text = "Update available: version %s" % v
		_update.text = "UPDATE"
		_update.visible = true
	else:
		_status.text = "You have the latest version."

# ----------------------------------------------------------------- downloading
func _download() -> void:
	var u := str(_latest.get("windows", ""))
	if u == "" or _downloading:
		return
	_zip_path = OS.get_user_data_dir() + "/download.zip"
	for c in _http.request_completed.get_connections():
		_http.request_completed.disconnect(c["callable"])
	_http.download_file = _zip_path
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	_update.disabled = true
	_play.disabled = true
	_bar.visible = true
	_bar.value = 0.0
	_downloading = true
	if _http.request(u) != OK:
		_downloading = false
		_status.text = "Couldn't start the download."
		_update.disabled = false
		_refresh_installed()

func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_downloading = false
	_http.download_file = ""
	_update.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		_status.text = "Download failed (error %d / %d). Try again." % [result, code]
		_bar.visible = false
		_refresh_installed()
		return
	_bar.value = 100.0
	_install(_zip_path)
	DirAccess.remove_absolute(_zip_path)

func _pick_zip() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.zip ; Wobbly Hours build"])
	fd.use_native_dialog = true
	fd.title = "Pick the Wobbly Hours zip (the exported game)"
	add_child(fd)
	fd.file_selected.connect(func(path: String):
		_install(path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(800, 500))

# ------------------------------------------------------------------ installing
## Unpacks the zip into game/. Takes the folder inside the zip that holds WobblyHours.exe / the .pck.
func _install(zip_path: String) -> void:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		_status.text = "Couldn't open that zip."
		return
	var files := zr.get_files()
	var prefix := ""
	var found := false
	for p in files:
		if p.get_file() == GAME_EXE or p.ends_with(".pck"):
			prefix = p.get_base_dir()
			found = true
			break
	if not found:
		zr.close()
		_status.text = "That zip isn't an exported Wobbly Hours build (no %s inside).\n(Project zips are installed with update.bat instead.)" % GAME_EXE
		return
	if prefix != "":
		prefix += "/"
	DirAccess.make_dir_recursive_absolute(_game_dir())
	var n := 0
	for p in files:
		if not p.begins_with(prefix) or p.ends_with("/"):
			continue
		var out_path := _game_dir() + "/" + p.substr(prefix.length())
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(zr.read_file(p))
		out.close()
		n += 1
	zr.close()
	if _latest.has("version") and not FileAccess.file_exists(_game_dir() + "/version.txt"):
		var vf := FileAccess.open(_game_dir() + "/version.txt", FileAccess.WRITE)
		if vf != null:
			vf.store_string(str(_latest["version"]))
	_bar.visible = false
	_update.visible = false
	_refresh_installed()
	_status.text = "Installed version %s (%d files). Ready to play!" % [_installed, n]

# -------------------------------------------------------------------- playing
func _launch() -> void:
	var exe := _game_dir() + "/" + GAME_EXE
	if not FileAccess.file_exists(exe):
		_status.text = "The game isn't installed yet."
		return
	var pid := OS.create_process(exe, [])
	if pid <= 0:
		_status.text = "Couldn't start the game."
		return
	get_tree().quit()
