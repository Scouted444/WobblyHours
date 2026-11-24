class_name ShopMenu
extends Control
## The Corner Shop: pick something, pay for it, it appears on the counter (big things outside the door).
## Opened with F at the counter. Esc / F / Close to leave.

var _world: GameWorld
var _cash: Label
var _buttons := {}   # kind -> Button

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
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "CORNER SHOP"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_cash = Label.new()
	_cash.add_theme_font_size_override("font_size", 28)
	_cash.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))
	head.add_child(_cash)
	var hint := Label.new()
	hint.text = "Click to buy. Small things land on the counter, big ones outside the door."
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	var sections: Dictionary = GameWorld.SHOP_SECTIONS
	var prices: Dictionary = GameWorld.PRICES
	for sec in sections:
		var l := Label.new()
		l.text = String(sec)
		l.add_theme_font_size_override("font_size", 20)
		box.add_child(l)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		box.add_child(grid)
		for k in sections[sec]:
			var kind := String(k)
			var b := Button.new()
			b.text = "%s\n$%d" % [Prop.LABELS.get(kind, kind), int(prices[kind])]
			b.custom_minimum_size = Vector2(112, 58)
			b.pressed.connect(func(): _buy(kind))
			grid.add_child(b)
			_buttons[kind] = b
	var close := Button.new()
	close.text = "Leave the shop"
	close.pressed.connect(queue_free)
	box.add_child(close)
	_world.money_changed.connect(_refresh)
	_refresh(_world.my_money)

func _buy(kind: String) -> void:
	var prices: Dictionary = GameWorld.PRICES
	if _world.my_money < int(prices[kind]):
		Sfx.play_ui(self, "error")
		return
	_world.buy.rpc_id(1, kind)

func _refresh(amount: int) -> void:
	_cash.text = "$%d" % amount
	var prices: Dictionary = GameWorld.PRICES
	for kind in _buttons:
		(_buttons[kind] as Button).disabled = amount < int(prices[kind])

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		queue_free()
