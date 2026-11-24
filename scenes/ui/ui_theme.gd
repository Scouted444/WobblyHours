class_name UITheme
extends RefCounted
## One chunky, colourful theme for all menus.

static var _shared: Theme

static func shared() -> Theme:
	if _shared == null:
		_shared = _make()
	return _shared

static func box(bg: Color, border: Color, radius := 12, bw := 3, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.6)
	return s

static func _make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var ink := Color(0.12, 0.08, 0.2)
	t.set_stylebox("normal", "Button", box(Color(1.0, 0.8, 0.25), ink, 12, 3, 4))
	t.set_stylebox("hover", "Button", box(Color(1.0, 0.9, 0.45), ink, 12, 3, 6))
	t.set_stylebox("pressed", "Button", box(Color(0.95, 0.6, 0.15), ink, 12, 3, 1))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.8), 12, 2))
	t.set_stylebox("disabled", "Button", box(Color(0.6, 0.6, 0.65), ink, 12, 3))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", ink)
	t.set_font_size("font_size", "Button", 20)
	t.set_stylebox("panel", "PanelContainer", box(Color(0.16, 0.12, 0.34, 0.97), Color(1.0, 0.8, 0.25), 18, 4, 10))
	t.set_stylebox("panel", "Panel", box(Color(0.16, 0.12, 0.34, 0.97), Color(1.0, 0.8, 0.25), 18, 4, 10))
	t.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1), ink, 10, 3))
	t.set_stylebox("focus", "LineEdit", box(Color(1, 1, 0.9), Color(0.95, 0.5, 0.2), 10, 3))
	t.set_color("font_color", "LineEdit", ink)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.45, 0.6))
	t.set_color("caret_color", "LineEdit", ink)
	t.set_color("font_color", "Label", Color(1, 1, 1))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(1.0, 0.8, 0.25), ink, 10, 3))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.35, 0.28, 0.6), ink, 10, 3))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.5, 0.4, 0.8), ink, 10, 3))
	t.set_color("font_selected_color", "TabContainer", ink)
	t.set_color("font_unselected_color", "TabContainer", Color(1, 1, 1))
	t.set_color("font_hovered_color", "TabContainer", Color(1, 1, 1))
	t.set_stylebox("panel", "TabContainer", box(Color(0.1, 0.07, 0.24, 0.9), ink, 10, 3))
	return t
