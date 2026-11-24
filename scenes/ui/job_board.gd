class_name JobBoard
extends Control
## The job board outside Wobbly Jobs (in town): pick a job, earn cash. Opened with F at the board.

var _world: GameWorld

func setup(world: GameWorld) -> void:
	_world = world

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "WOBBLY JOBS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var cash := Label.new()
	cash.text = "$%d" % _world.my_money
	cash.add_theme_font_size_override("font_size", 28)
	cash.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))
	head.add_child(cash)
	var hint := Label.new()
	hint.text = "No experience needed. No questions asked. Paid in cash." if not Net.is_campaign() else "Campaign: jobs are how you make money. Spend it at the Corner Shop."
	hint.modulate = Color(1, 1, 1, 0.75)
	box.add_child(hint)
	if _world.missions != null and _world.missions.has_job():
		var cur := Label.new()
		cur.text = "Your job: " + str(_world.missions.mine.get("text", ""))
		cur.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cur.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
		box.add_child(cur)
		var q := Button.new()
		q.text = "Quit this job"
		q.pressed.connect(func():
			_world.missions.quit.rpc_id(1)
			queue_free())
		box.add_child(q)
	else:
		for k in Missions.JOBS:
			var job: Dictionary = Missions.JOBS[k]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			box.add_child(row)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var t := Label.new()
			t.text = "%s   %s" % [job["title"], job["pay"]]
			t.add_theme_font_size_override("font_size", 20)
			info.add_child(t)
			var d := Label.new()
			d.text = str(job["desc"])
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(440, 0)
			d.modulate = Color(1, 1, 1, 0.8)
			info.add_child(d)
			var b := Button.new()
			b.text = "Take it"
			b.custom_minimum_size = Vector2(110, 48)
			var kind := String(k)
			b.pressed.connect(func():
				_world.missions.accept.rpc_id(1, kind)
				queue_free())
			row.add_child(b)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	box.add_child(close)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		queue_free()
