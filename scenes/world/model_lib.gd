class_name ModelLib
extends RefCounted
## Loads the real .glb models from res://models/ (made by tools/make_models.py, or your own files
## with the same names). Falls back to parsing the file at runtime if the editor has not imported it yet.

static var _scenes := {}
static var _templates := {}
static var _missing := {}

## A fresh instance of the model, or null if it does not exist.
static func make(model_name: String) -> Node3D:
	if _missing.has(model_name):
		return null
	if _scenes.has(model_name):
		return (_scenes[model_name] as PackedScene).instantiate() as Node3D
	if _templates.has(model_name):
		return (_templates[model_name] as Node3D).duplicate() as Node3D
	var path := "res://models/%s.glb" % model_name
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			_scenes[model_name] = res
			return (res as PackedScene).instantiate() as Node3D
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) == OK:
			var n := doc.generate_scene(state) as Node3D
			if n != null:
				_templates[model_name] = n
				return n.duplicate() as Node3D
	_missing[model_name] = true
	push_warning("Model not found: " + path)
	return null

## Re-colour materials by their name in the .glb (e.g. "skin", "shirt").
static func tint(root: Node, colors: Dictionary) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null:
				continue
			var key := String(mat.resource_name)
			if colors.has(key):
				mi.set_surface_override_material(s, Mats.solid(colors[key] as Color, 0.8))

## First node with this name anywhere under root.
static func find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)
