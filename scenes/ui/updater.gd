class_name Updater
extends RefCounted
## Unpacks a new version of the game (the zip Claude sends) over the current project folder.
## Backs the old files up first into a sibling folder "wobbly_hours_backups".

static func version() -> String:
	return GameVersion.VERSION

static func apply(zip_path: String) -> String:
	if OS.has_feature("template"):
		return "This is an exported build: close the game and use update.bat in the project folder, then export again."
	var game := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return "Could not open that zip."
	var files := zr.get_files()
	# find the folder inside the zip that holds project.godot ("wobbly_hours/" in my zips)
	var prefix := ""
	var found := false
	for f in files:
		if f.get_file() == "project.godot":
			prefix = f.get_base_dir()
			found = true
			break
	if not found:
		zr.close()
		return "That zip doesn't contain the game (no project.godot)."
	if prefix != "":
		prefix += "/"
	var old_ver := version()
	# back up what we are about to overwrite
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup_dir := game.get_base_dir() + "/wobbly_hours_backups/backup_" + stamp
	var written := 0
	for f in files:
		if not f.begins_with(prefix) or f.ends_with("/"):
			continue
		var rel := f.substr(prefix.length())
		if rel.begins_with(".godot/"):
			continue
		var dst := game + "/" + rel
		if FileAccess.file_exists(dst):
			DirAccess.make_dir_recursive_absolute((backup_dir + "/" + rel).get_base_dir())
			DirAccess.copy_absolute(dst, backup_dir + "/" + rel)
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var out := FileAccess.open(dst, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(zr.read_file(f))
		out.close()
		written += 1
	zr.close()
	var new_ver := "?"
	var vf := FileAccess.open(game + "/version.txt", FileAccess.READ)
	if vf != null:
		new_ver = vf.get_as_text().strip_edges()
	return "Updated %s -> %s (%d files). Restart the game (and let Godot re-import). Old files backed up in wobbly_hours_backups." % [old_ver, new_ver, written]
