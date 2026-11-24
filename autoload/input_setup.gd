extends Node
## Registers all input actions in code so you never have to touch the Input Map.
## Want to rebind a key? Change it here.

func _ready() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("flop", KEY_R)
	_key("leave", KEY_BACKSPACE)
	_key("view", KEY_V)       # first / third person
	_key("stuck", KEY_U)      # I am stuck: respawn
	_key("customize", KEY_K)  # open the character creator
	_key("pause", KEY_ESCAPE)
	_key("interact", KEY_F)  # use the computer
	_key("chat", KEY_T)
	_key("throw", KEY_G)    # throw what you hold
	_key("menu", KEY_TAB)   # spawn menu
	_key("crouch", KEY_C)   # swim down
	_key("wheel", KEY_Q)    # hold for the weapon wheel
	_key("spawn_1", KEY_1)  # crate
	_key("spawn_2", KEY_2)  # beach ball
	_key("spawn_3", KEY_3)  # chair
	_key("spawn_4", KEY_4)  # watermelon
	_key("spawn_5", KEY_5)  # rubber duck
	_key("spawn_6", KEY_6)  # bowling pin
	_key("spawn_7", KEY_7)  # barrel
	_key("spawn_8", KEY_8)  # bomb
	_mouse("shove", MOUSE_BUTTON_LEFT)   # throw when holding something, shove otherwise
	_mouse("grab", MOUSE_BUTTON_RIGHT)   # hold to carry

func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

func _key(action: StringName, keycode: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
