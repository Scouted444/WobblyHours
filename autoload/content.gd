extends Node
## Workshop content (autoload "Content"): installed characters and maps (.glb files),
## drag-and-drop import, downloads from URLs / catalogs, and sending models to other
## players in a party so everyone sees your character and the host's map.
##
## Files live in user://content/characters and user://content/maps and are named
## "<Name>__<id>.glb", where id = first 16 hex chars of the file's SHA-256.

signal changed                     # an installed list changed
signal blob_ready(id: String)      # a model received from the network is now available
signal status(text: String)        # progress / error text for the UI
signal dropped(paths: PackedStringArray)

const KINDS := ["characters", "maps"]
const ROOT := "user://content/"
const CACHE := "user://content/cache/"
const SETTINGS := "user://content/settings.json"
const MAX_BYTES := 40 * 1024 * 1024
const CHUNK := 48 * 1024

var catalog_url := ""
var selected_map := ""   # map (id) I use when I host; "" = the party house
var _incoming := {}   # id -> {"total": int, "chunks": {index: bytes}}
var _requested := {}  # ids we asked for (we accept data only for these)
var _waiting := {}    # server only: id -> [peer ids waiting for it]

func _ready() -> void:
	for k in KINDS:
		DirAccess.make_dir_recursive_absolute(ROOT + k)
	DirAccess.make_dir_recursive_absolute(CACHE)
	get_window().files_dropped.connect(func(p: PackedStringArray): dropped.emit(p))
	Net.players_changed.connect(_on_players_changed)
	Net.map_changed.connect(func(): ensure(str(Net.map.get("id", "")), 1))
	if FileAccess.file_exists(SETTINGS):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
		if parsed is Dictionary:
			catalog_url = str(parsed.get("catalog_url", ""))
			selected_map = str(parsed.get("map_id", ""))
	if not selected_map.is_empty() and not has(selected_map):
		selected_map = ""

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"catalog_url": catalog_url, "map_id": selected_map}))

# ---------------------------------------------------------------- installed
## [{name, id, path, kind}] sorted by name
func list(kind: String) -> Array:
	var out := []
	var dir := DirAccess.open(ROOT + kind)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.to_lower().ends_with(".glb"):
			continue
		var base := f.get_basename()
		var idx := base.rfind("__")
		if idx < 0:
			continue
		out.append({"name": base.substr(0, idx).replace("_", " "), "id": base.substr(idx + 2), "path": ROOT + kind + "/" + f, "kind": kind})
	out.sort_custom(func(a, b): return a["name"].to_lower() < b["name"].to_lower())
	return out

func path_of(id: String) -> String:
	if id.is_empty():
		return ""
	for k in KINDS:
		for it in list(k):
			if it["id"] == id:
				return it["path"]
	var cached := CACHE + id + ".glb"
	return cached if FileAccess.file_exists(cached) else ""

func has(id: String) -> bool:
	return not path_of(id).is_empty()

func name_of(id: String) -> String:
	for k in KINDS:
		for it in list(k):
			if it["id"] == id:
				return it["name"]
	return id

static func hash_bytes(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 16)

static func is_glb(b: PackedByteArray) -> bool:
	return b.size() > 12 and b.slice(0, 4).get_string_from_ascii() == "glTF"

static func clean_name(raw: String) -> String:
	var out := ""
	for c in raw.get_file().get_basename():
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == " " or c == "-":
			out += c
	out = out.strip_edges().replace(" ", "_").left(40)
	return out if not out.is_empty() else "Model"

## Install a .glb from memory. Returns the item, or {} if it isn't a valid .glb.
func import_bytes(bytes: PackedByteArray, display_name: String, kind: String) -> Dictionary:
	if not kind in KINDS or bytes.size() > MAX_BYTES or not is_glb(bytes):
		return {}
	var id := hash_bytes(bytes)
	for it in list(kind):
		if it["id"] == id:
			return it
	var path := "%s%s/%s__%s.glb" % [ROOT, kind, clean_name(display_name), id]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_buffer(bytes)
	f.close()
	changed.emit()
	return {"name": clean_name(display_name).replace("_", " "), "id": id, "path": path, "kind": kind}

func import_file(path: String, kind: String) -> Dictionary:
	if not path.to_lower().ends_with(".glb"):
		status.emit("Only .glb files are supported (export as 'glTF Binary').")
		return {}
	var item := import_bytes(FileAccess.get_file_as_bytes(path), path, kind)
	status.emit(("Installed %s" % item["name"]) if not item.is_empty() else "%s is not a valid .glb (max 40 MB)" % path.get_file())
	return item

func delete_item(item: Dictionary) -> void:
	DirAccess.remove_absolute(item["path"])
	changed.emit()

# ---------------------------------------------------------------- loading
static func load_scene(path: String) -> Node3D:
	if path.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	return doc.generate_scene(state) as Node3D

## Bounding box of all meshes under root, in root's local space (root must be in the tree).
static func scene_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := (inv * mi.global_transform) * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box

# ---------------------------------------------------------------- downloads
func download(url: String, kind: String, display_name: String) -> void:
	status.emit("Downloading %s ..." % display_name)
	var http := HTTPRequest.new()
	http.body_size_limit = MAX_BYTES
	add_child(http)
	if http.request(url) != OK:
		status.emit("That doesn't look like a valid URL")
		http.queue_free()
		return
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		status.emit("Download failed (HTTP %d)" % res[1])
		return
	var item := import_bytes(res[3], display_name, kind)
	status.emit(("Installed %s" % item["name"]) if not item.is_empty() else "That file is not a valid .glb (max 40 MB)")

## Built-in catalog plus (optionally) an online one: JSON array of {name, kind, url, author, license}.
func fetch_catalog() -> Array:
	var out := []
	if FileAccess.file_exists("res://content/catalog.json"):
		var local: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/catalog.json"))
		if local is Array:
			out.append_array(local)
	if not catalog_url.is_empty():
		var http := HTTPRequest.new()
		add_child(http)
		if http.request(catalog_url) == OK:
			var res: Array = await http.request_completed
			if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200:
				var online: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
				if online is Array:
					out.append_array(online)
				else:
					status.emit("The online catalog isn't a JSON list")
			else:
				status.emit("Couldn't load the online catalog (HTTP %d)" % res[1])
		http.queue_free()
	return out

# ------------------------------------------------- sharing with other players
func _on_players_changed() -> void:
	if Net.players.is_empty():
		_requested.clear()
		_waiting.clear()
		return
	for pid in Net.players:
		ensure(str(Net.players[pid].get("look", {}).get("model", "")), int(pid))

## Make sure we have this model; fetch it over the network if not. owner_peer = who has it.
func ensure(id: String, owner_peer: int) -> void:
	if id.is_empty() or has(id) or _requested.has(id) or multiplayer.multiplayer_peer == null:
		return
	_requested[id] = true
	if multiplayer.is_server():
		if owner_peer > 1:
			send_me.rpc_id(owner_peer, id)
	else:
		request.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func request(id: String) -> void:  # runs on the server
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if has(id):
		_send_blob(peer, id)
		return
	_requested[id] = true
	if not _waiting.has(id):
		_waiting[id] = []
	_waiting[id].append(peer)
	var owner_peer := Net.owner_of_model(id)
	if owner_peer > 1:
		send_me.rpc_id(owner_peer, id)

@rpc("any_peer", "call_remote", "reliable")
func send_me(id: String) -> void:  # runs on the owner; uploads to whoever asked (the server)
	if has(id):
		_send_blob(multiplayer.get_remote_sender_id(), id)

func _send_blob(peer: int, id: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path_of(id))
	var total := ceili(float(bytes.size()) / CHUNK)
	for i in total:
		rx_chunk.rpc_id(peer, id, i, total, bytes.slice(i * CHUNK, (i + 1) * CHUNK))
		if i % 8 == 7:
			await get_tree().process_frame

@rpc("any_peer", "call_remote", "reliable")
func rx_chunk(id: String, index: int, total: int, data: PackedByteArray) -> void:
	if not _requested.has(id) or total <= 0 or index < 0 or index >= total or data.size() > CHUNK:
		return
	if total * CHUNK > MAX_BYTES + CHUNK:
		return
	var inc: Dictionary = _incoming.get(id, {"total": total, "chunks": {}})
	inc["chunks"][index] = data
	_incoming[id] = inc
	if inc["chunks"].size() < total:
		return
	var all := PackedByteArray()
	for i in total:
		all.append_array(inc["chunks"][i])
	_incoming.erase(id)
	if not is_glb(all) or hash_bytes(all) != id:  # the hash is the id, so a tampered file is rejected
		status.emit("Rejected a corrupted model from the network")
		return
	var f := FileAccess.open(CACHE + id + ".glb", FileAccess.WRITE)
	if f != null:
		f.store_buffer(all)
		f.close()
	blob_ready.emit(id)
	if multiplayer.is_server() and _waiting.has(id):
		for p in _waiting[id]:
			_send_blob(p, id)
		_waiting.erase(id)
