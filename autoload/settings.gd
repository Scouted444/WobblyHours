extends Node
## Player settings (autoload "Settings"): saved to user://settings.json. Also gives every
## button in the game a little click / hover sound.

signal changed

const PATH := "user://settings.json"
var sensitivity := 1.0   # multiplier on mouse look
var fov := 75.0
var volume := 0.8
var music := 0.5
var fullscreen := false
var gore := false        # blood and dismemberment (only on this computer)

func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			sensitivity = clampf(float(d.get("sensitivity", sensitivity)), 0.2, 4.0)
			fov = clampf(float(d.get("fov", fov)), 60.0, 110.0)
			volume = clampf(float(d.get("volume", volume)), 0.0, 1.0)
			music = clampf(float(d.get("music", music)), 0.0, 1.0)
			fullscreen = bool(d.get("fullscreen", fullscreen))
			gore = bool(d.get("gore", gore))
	apply()
	get_tree().node_added.connect(_on_node_added)

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"sensitivity": sensitivity, "fov": fov, "volume": volume, "music": music, "fullscreen": fullscreen, "gore": gore}))

func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(_click)
		n.mouse_entered.connect(_hover)

func _click() -> void:
	Sfx.play_ui(self, "click")

func _hover() -> void:
	Sfx.play_ui(self, "hover", -12.0)
