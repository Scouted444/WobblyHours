class_name ChatBox
extends Control
## Press T, type, Enter. Esc cancels.

func _ready() -> void:
	theme = UITheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var le := LineEdit.new()
	le.placeholder_text = "Say something... (Enter to send, Esc to cancel)"
	le.max_length = 140
	le.anchor_top = 1.0
	le.anchor_bottom = 1.0
	le.anchor_right = 0.6
	le.offset_left = 14
	le.offset_top = -70
	le.offset_bottom = -22
	add_child(le)
	le.text_submitted.connect(func(t: String):
		var world := get_tree().get_first_node_in_group("world") as GameWorld
		if world != null and not t.strip_edges().is_empty():
			world.chat_say.rpc(t)
		queue_free())
	le.call_deferred("grab_focus")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
