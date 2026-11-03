class_name Style
## The launcher's look, taken from trismegstudios.com: the logo's void, gold and paper,
## Inter Tight for text, Instrument Serif for headings, JetBrains Mono for versions.

const VOID := Color("#0b0a12")
const VOID_LIFT := Color("#100f18")
const PANEL := Color("#15141d")
const PANEL_HI := Color("#1c1a26")
const RULE := Color("#24212e")
const RULE_GOLD := Color("#4a4436")
const GOLD := Color("#d4b373")
const GOLD_PALE := Color("#efdda8")
const GOLD_DEEP := Color("#b8955a")
const PAPER := Color("#f3f3f8")
const MIST := Color("#b9b5c2")
const DIM := Color("#8c8898")

# what each game state reads as, everywhere it shows
const READY := Color("#8fd6a8")
const UPDATE := GOLD
const RUNNING := Color("#8ab4f8")
const BLOCKED := Color("#e8836b")

static var _fonts := {}


static func sans(weight := 450) -> Font:
	return _font("res://assets/fonts/InterTight.ttf", weight)


static func mono(weight := 450, spacing := 0) -> Font:
	return _font("res://assets/fonts/JetBrainsMono.ttf", weight, spacing)


static func serif() -> Font:
	return load("res://assets/fonts/InstrumentSerif-Regular.ttf")


static func _font(path: String, weight: int, spacing := 0) -> Font:
	var key := "%s:%d:%d" % [path, weight, spacing]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load(path)
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]


static func box(bg: Color, radius := 10, border := Color(0, 0, 0, 0), mx := 0.0, my := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 15
	t.set_color("font_color", "Label", PAPER)

	_button(t, "Button", box(PANEL_HI, 10, RULE, 16, 9), box(Color("#262330"), 10, RULE_GOLD, 16, 9), PAPER)
	_button(t, "PrimaryButton", box(GOLD, 10, Color(0, 0, 0, 0), 18, 9), box(GOLD_PALE, 10, Color(0, 0, 0, 0), 18, 9), VOID)
	t.set_font("font", "PrimaryButton", sans(620))
	_button(t, "GhostButton", box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 12, 7), box(Color(1, 1, 1, 0.05), 8, Color(0, 0, 0, 0), 12, 7), MIST, PAPER)
	_button(t, "DangerButton", box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 12, 7), box(Color(BLOCKED, 0.1), 8, Color(0, 0, 0, 0), 12, 7), BLOCKED, Color("#ffb4a3"))
	_button(t, "NavButton", box(Color(0, 0, 0, 0), 9, Color(0, 0, 0, 0), 14, 9), box(Color(1, 1, 1, 0.04), 9, Color(0, 0, 0, 0), 14, 9), MIST, PAPER)
	var nav_on := box(Color(GOLD, 0.09), 9, Color(GOLD, 0.16), 14, 9)
	t.set_stylebox("pressed", "NavButton", nav_on)
	t.set_stylebox("hover_pressed", "NavButton", nav_on)
	t.set_color("font_pressed_color", "NavButton", GOLD_PALE)
	t.set_color("font_hover_pressed_color", "NavButton", GOLD_PALE)
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		(t.get_stylebox(s, "NavButton") as StyleBoxFlat).content_margin_left = 36
	_button(t, "SegButton", box(Color(0, 0, 0, 0), 7, Color(0, 0, 0, 0), 12, 7), box(Color(1, 1, 1, 0.04), 7, Color(0, 0, 0, 0), 12, 7), DIM, PAPER)
	var seg_on := box(PANEL_HI, 7, RULE_GOLD, 12, 7)
	t.set_stylebox("pressed", "SegButton", seg_on)
	t.set_stylebox("hover_pressed", "SegButton", seg_on)
	t.set_color("font_pressed_color", "SegButton", GOLD_PALE)
	t.set_color("font_hover_pressed_color", "SegButton", GOLD_PALE)

	_label(t, "H1", PAPER, serif(), 46)
	_label(t, "H2", PAPER, serif(), 36)
	_label(t, "Mist", MIST, null, 15)
	_label(t, "Dim", DIM, null, 13)
	_label(t, "Mono", DIM, mono(), 12)
	_label(t, "Caps", DIM, mono(500, 1), 11)

	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), 3))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, 3))

	var bar := box(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 3, 3)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, bar)
		t.set_stylebox("grabber", sb, box(Color(1, 1, 1, 0.1), 4))
		t.set_stylebox("grabber_highlight", sb, box(Color(1, 1, 1, 0.18), 4))
		t.set_stylebox("grabber_pressed", sb, box(Color(1, 1, 1, 0.26), 4))

	t.set_color("font_color", "CheckButton", MIST)
	t.set_color("font_hover_color", "CheckButton", PAPER)
	t.set_color("font_pressed_color", "CheckButton", MIST)
	t.set_color("font_hover_pressed_color", "CheckButton", PAPER)
	t.set_color("font_focus_color", "CheckButton", MIST)
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(s, "CheckButton", box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 4, 6))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	t.set_stylebox("panel", "TooltipPanel", box(PANEL_HI, 8, RULE, 10, 6))
	t.set_color("font_color", "TooltipLabel", PAPER)
	return t


static func _button(t: Theme, type: String, normal: StyleBoxFlat, hover: StyleBoxFlat, font: Color, font_hover := Color(0, 0, 0, 0)) -> void:
	if font_hover.a == 0.0:
		font_hover = font
	if type != "Button":
		t.set_type_variation(type, "Button")
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = hover.bg_color.darkened(0.06)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(normal.bg_color, normal.bg_color.a * 0.45)
	disabled.border_color = Color(normal.border_color, normal.border_color.a * 0.45)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for c in ["font_color", "font_focus_color"]:
		t.set_color(c, type, font)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, type, font_hover)
	t.set_color("font_disabled_color", type, Color(font, 0.45))


static func _label(t: Theme, type: String, color: Color, font: Font, size: int) -> void:
	t.set_type_variation(type, "Label")
	t.set_color("font_color", type, color)
	if font:
		t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)


# --- pieces ----------------------------------------------------------------

static func dot(color: Color, d := 7.0, glow := false) -> Panel:
	var p := Panel.new()
	var s := box(color, 99)
	if glow:
		s.shadow_color = Color(color, 0.55)
		s.shadow_size = 5
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## A dark badge with a coloured dot, readable over cover art.
static func pill(text: String, color: Color, glow := false) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color(VOID, 0.78), 99, Color(color, 0.32), 10, 4)
	if glow:
		s.shadow_color = Color(color, 0.22)
		s.shadow_size = 10
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	row.add_child(dot(color, 6, glow))
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", mono(560, 1))
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", color.lightened(0.18))
	row.add_child(l)
	return p


## The game's name drawn over a cover-less placeholder.
static func placeholder_title(l: Label, size: int) -> void:
	l.add_theme_font_override("font", serif())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(GOLD_PALE, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 24
	l.offset_right = -24


## [label, colour] for a game's state.
static func look(lib: Library, g: Library.Game) -> Array:
	match lib.status(g):
		Library.Status.READY:
			return ["Ready", READY]
		Library.Status.UPDATE:
			return ["Update available", UPDATE]
		Library.Status.INSTALL:
			return ["Not installed", MIST]
		Library.Status.BUSY:
			if g.task == "verify":
				return ["Checking", GOLD_PALE]
			return ["Updating" if not g.installed.is_empty() else "Installing", GOLD_PALE]
		Library.Status.RUNNING:
			return ["Playing", RUNNING]
		Library.Status.BLOCKED:
			return ["Needs launcher update", BLOCKED]
	return ["Offline" if not lib.online else "No build yet", DIM]
