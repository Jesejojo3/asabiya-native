class_name UiTheme
extends RefCounted
## Modern historical atlas: ink, parchment and brass. Shared visual tokens.

const BG := Color(0.035, 0.065, 0.09, 0.98)
const BG_SOFT := Color(0.065, 0.105, 0.135, 0.98)
const LINE := Color(0.23, 0.30, 0.33, 1.0)
const GOLD := Color(0.84, 0.73, 0.50)
const TEXT := Color(0.92, 0.91, 0.85)
const MUTED := Color(0.62, 0.70, 0.72)
const MISSING := Color(0.55, 0.55, 0.58)
const OK := Color(0.45, 0.78, 0.55)
const WARN := Color(0.93, 0.66, 0.30)


static func panel_style(bg := BG, radius := 4, border := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(16)
	if border:
		s.border_color = LINE
		s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


static func build() -> Theme:
	var t := Theme.new()
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "DejaVu Sans"])
	t.default_font = body
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 0.97))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.47))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var btn := StyleBoxFlat.new()
	btn.bg_color = BG_SOFT
	btn.set_corner_radius_all(2)
	btn.set_content_margin_all(9)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.12, 0.19, 0.23)
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = Color(0.19, 0.24, 0.25)
	prs.border_color = GOLD
	prs.set_border_width_all(1)
	var dis := btn.duplicate() as StyleBoxFlat
	dis.bg_color = Color(0.10, 0.11, 0.13, 0.6)
	var focus := btn.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = GOLD
	focus.set_border_width_all(1)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hov)
		t.set_stylebox("pressed", cls, prs)
		t.set_stylebox("hover_pressed", cls, prs)
		t.set_stylebox("disabled", cls, dis)
		t.set_stylebox("focus", cls, focus)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.05, 0.06, 0.08, 0.95)
	le.border_color = LINE
	le.set_border_width_all(1)
	le.set_corner_radius_all(2)
	le.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	var tip := panel_style(Color(0.05, 0.06, 0.08, 0.96), 4)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	var il := StyleBoxFlat.new()
	il.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	il.set_content_margin_all(4)
	t.set_stylebox("panel", "ItemList", il)
	t.set_stylebox("panel", "Tree", il)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


static func heading(text: String, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	var face := SystemFont.new()
	face.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	l.add_theme_font_override("font", face)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	return l


static func muted(text: String, size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func badge(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col.r, col.g, col.b, 0.18)
	s.border_color = col
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col.lightened(0.25))
	p.add_child(l)
	return p
