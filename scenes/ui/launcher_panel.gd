class_name LauncherPanel
extends PanelContainer
## The launcher bar on the main menu: shows your version, checks online for a newer one and installs it.
##
## Where updates come from: a small "latest.json" on the web (see release/latest.json and the README):
##   {"version": "1.24", "notes": "...", "windows": "<zip of the exported game>", "project": "<zip of the project>"}
## Its address goes in update_url.txt in the game folder (the host sets it once and shares the game),
## or players can paste it in here. Both GitHub "raw" links and GitHub release downloads work.
##
## Installing: the zip is downloaded and unpacked into a staging folder. A Godot project folder is
## updated in place (restart afterwards). An exported game can't overwrite itself while running, so
## it writes a tiny helper script that waits for the game to close, copies the new files in, and
## starts the game again.

const SAVE := "user://launcher.json"

var _status: Label
var _btn_check: Button
var _btn_update: Button
var _bar: ProgressBar
var _url_edit: LineEdit
var _http: HTTPRequest
var _latest := {}
var _downloading := false
var _zip_path := ""

func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	var ver := Label.new()
	ver.text = "Version %s" % GameVersion.VERSION
	ver.add_theme_font_size_override("font_size", 18)
	top.add_child(ver)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(260, 0)
	top.add_child(_status)
	_bar = ProgressBar.new()
	_bar.visible = false
	_bar.custom_minimum_size = Vector2(0, 18)
	box.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_btn_check = Button.new()
	_btn_check.text = "Check for updates"
	_btn_check.pressed.connect(check)
	row.add_child(_btn_check)
	_btn_update = Button.new()
	_btn_update.text = "Update now"
	_btn_update.visible = false
	_btn_update.pressed.connect(_download)
	row.add_child(_btn_update)
	var from_file := Button.new()
	from_file.text = "Update from a zip..."
	from_file.pressed.connect(_pick_zip)
	row.add_child(from_file)
	var url_btn := Button.new()
	url_btn.text = "Update link..."
	url_btn.pressed.connect(func(): _url_edit.visible = not _url_edit.visible)
	row.add_child(url_btn)
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "Paste the latest.json link from the host, then press Enter"
	_url_edit.visible = false
	_url_edit.text = _url()
	_url_edit.text_submitted.connect(func(t: String):
		_save_url(t.strip_edges())
		_url_edit.visible = false
		check())
	box.add_child(_url_edit)
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	if _url() == "":
		_status.text = "No update link set (press \"Update link...\")"
	else:
		check()

func _process(_delta: float) -> void:
	if _downloading:
		var total := _http.get_body_size()
		var got := _http.get_downloaded_bytes()
		if total > 0:
			_bar.value = 100.0 * got / total
			_status.text = "Downloading... %.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0]
		else:
			_status.text = "Downloading... %.1f MB" % (got / 1048576.0)

# --------------------------------------------------------------- the update link
func _url() -> String:
	if FileAccess.file_exists(SAVE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary and str(d.get("url", "")) != "":
			return str(d["url"])
	var f := FileAccess.open("res://update_url.txt", FileAccess.READ)
	if f != null:
		return f.get_as_text().strip_edges()
	return ""

func _save_url(u: String) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"url": u}))

# ---------------------------------------------------------------- checking
func check() -> void:
	var u := _url()
	if u == "":
		_status.text = "No update link set (press \"Update link...\")"
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	_status.text = "Checking for updates..."
	_btn_update.visible = false
	for c in _http.request_completed.get_connections():
		_http.request_completed.disconnect(c["callable"])
	_http.download_file = ""
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(u + ("&" if "?" in u else "?") + "t=%d" % Time.get_unix_time_from_system()) != OK:
		_status.text = "Could not check (bad link?)"

func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		_status.text = "Could not reach the update link (error %d / %d)" % [result, code]
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary) or not (d as Dictionary).has("version"):
		_status.text = "The update link didn't return a latest.json"
		return
	_latest = d
	var newer := GameVersion.compare(str(_latest["version"]), GameVersion.VERSION)
	if newer > 0:
		_status.text = "Update available: %s  %s" % [_latest["version"], str(_latest.get("notes", ""))]
		_btn_update.visible = _zip_url() != ""
		if _zip_url() == "":
			_status.text += "\n(no download for this kind of install)"
	else:
		_status.text = "Up to date"

## Exported game -> the "windows" zip; running the project in Godot -> the "project" zip.
func _zip_url() -> String:
	if OS.has_feature("template"):
		return str(_latest.get("windows", ""))
	return str(_latest.get("project", ""))

# ---------------------------------------------------------------- downloading
func _download() -> void:
	var u := _zip_url()
	if u == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://update"))
	_zip_path = ProjectSettings.globalize_path("user://update/download.zip")
	_http.download_file = _zip_path
	for c in _http.request_completed.get_connections():
		_http.request_completed.disconnect(c["callable"])
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	_btn_update.disabled = true
	_btn_check.disabled = true
	_bar.visible = true
	_bar.value = 0.0
	_downloading = true
	if _http.request(u) != OK:
		_downloading = false
		_status.text = "Could not start the download"
		_btn_update.disabled = false
		_btn_check.disabled = false

func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_downloading = false
	_http.download_file = ""
	_btn_update.disabled = false
	_btn_check.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		_status.text = "Download failed (error %d / %d)" % [result, code]
		_bar.visible = false
		return
	_bar.value = 100.0
	_install(_zip_path)

func _pick_zip() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.zip ; Game update"])
	fd.use_native_dialog = true
	fd.title = "Pick the new Wobbly Hours zip"
	add_child(fd)
	fd.file_selected.connect(func(path: String):
		_install(path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(900, 600))

# ---------------------------------------------------------------- installing
func _install(zip_path: String) -> void:
	if not OS.has_feature("template"):
		_status.text = Updater.apply(zip_path)   # project folder: copy straight in
		return
	# exported game: unpack next to us, then let a helper swap the files once we have closed
	var exe := OS.get_executable_path()
	var game_dir := exe.get_base_dir()
	var staging := ProjectSettings.globalize_path("user://update/staging")
	_wipe(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	var n := _unzip(zip_path, staging)
	if n <= 0:
		_status.text = "That zip doesn't look like a Wobbly Hours build (no .exe / .pck inside)"
		return
	var bat := ProjectSettings.globalize_path("user://update/apply_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		_status.text = "Could not write the update helper"
		return
	f.store_string("@echo off\r\n")
	f.store_string("echo Updating Wobbly Hours, one moment...\r\n")
	f.store_string("timeout /t 2 /nobreak >nul\r\n")
	f.store_string("robocopy \"%s\" \"%s\" /E /NFL /NDL /NJH /NJS /NP >nul\r\n" % [staging.replace("/", "\\"), game_dir.replace("/", "\\")])
	f.store_string("start \"\" \"%s\"\r\n" % exe.replace("/", "\\"))
	f.close()
	_status.text = "Installing and restarting..."
	OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	get_tree().create_timer(0.4).timeout.connect(func(): get_tree().quit())

## Unpack an exported build: finds the folder holding the .exe / .pck and copies it (flattened) to dst.
func _unzip(zip_path: String, dst: String) -> int:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return 0
	var files := zr.get_files()
	var prefix := ""
	var found := false
	for p in files:
		if p.ends_with(".pck") or p.ends_with(".exe"):
			prefix = p.get_base_dir()
			found = true
			break
	if not found:
		zr.close()
		return 0
	if prefix != "":
		prefix += "/"
	var n := 0
	for p in files:
		if not p.begins_with(prefix) or p.ends_with("/"):
			continue
		var out_path := dst + "/" + p.substr(prefix.length())
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(zr.read_file(p))
		out.close()
		n += 1
	zr.close()
	return n

func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(dir + "/" + sub)
		d.remove(sub)
