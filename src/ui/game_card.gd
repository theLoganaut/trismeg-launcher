extends PanelContainer
## One game in the library grid: its cover with status badges, its name, and the one
## action that matters right now (Play, Update, Install, Cancel or Open in Steam). Click it
## for details.

signal opened(id: String)

const CoverView := preload("res://src/ui/cover_view.gd")

var lib: Library
var id := ""

var _border := Style.box(Color(0, 0, 0, 0), 14, Color(1, 1, 1, 0.06))
var _cover_box := Control.new()
var _cover := CoverView.new()
var _placeholder := Label.new()
var _badges := HBoxContainer.new()
var _bar := ProgressBar.new()
var _title := Label.new()
var _tagline := Label.new()
var _info := Label.new()
var _action := Button.new()
var _hover: Tween


func setup(library: Library, game_id: String) -> void:
	lib = library
	id = game_id
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	clip_children = CLIP_CHILDREN_AND_DRAW
	add_theme_stylebox_override("panel", Style.box(Style.PANEL, 14))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)

	_cover_box.mouse_filter = MOUSE_FILTER_IGNORE
	_cover_box.clip_contents = true
	col.add_child(_cover_box)
	_cover.set_anchors_preset(PRESET_FULL_RECT)
	_cover_box.add_child(_cover)
	Style.placeholder_title(_placeholder, 30)
	_cover_box.add_child(_placeholder)
	var top := MarginContainer.new()
	top.set_anchors_preset(PRESET_TOP_WIDE)
	top.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right"]:
		top.add_theme_constant_override("margin_" + side, 12)
	_cover_box.add_child(top)
	_badges.mouse_filter = MOUSE_FILTER_IGNORE
	_badges.add_theme_constant_override("separation", 6)
	top.add_child(_badges)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	_bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_bar.offset_top = -4
	_bar.add_theme_stylebox_override("background", Style.box(Color(0, 0, 0, 0.5), 0))
	_bar.add_theme_stylebox_override("fill", Style.box(Style.GOLD, 0))
	_cover_box.add_child(_bar)

	var body := MarginContainer.new()
	body.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("margin_left", 18)
	body.add_theme_constant_override("margin_right", 14)
	body.add_theme_constant_override("margin_top", 14)
	body.add_theme_constant_override("margin_bottom", 14)
	col.add_child(body)
	var v := VBoxContainer.new()
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	body.add_child(v)
	_title.add_theme_font_override("font", Style.sans(620))
	_title.add_theme_font_size_override("font_size", 17)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_title)
	_tagline.theme_type_variation = "Dim"
	_tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(gap)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_info.theme_type_variation = "Mono"
	_info.size_flags_horizontal = SIZE_EXPAND_FILL
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_info)
	_action.custom_minimum_size.x = 92
	_action.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_action.pressed.connect(func() -> void: lib.act(id))
	row.add_child(_action)

	var outline := Panel.new()  # drawn last, so the hover outline sits over the cover
	outline.mouse_filter = MOUSE_FILTER_IGNORE
	outline.add_theme_stylebox_override("panel", _border)
	add_child(outline)

	resized.connect(_on_resized)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(func() -> void:
		if not get_global_rect().has_point(get_global_mouse_position()):
			_set_hover(false))
	lib.game_changed.connect(func(g: String) -> void:
		if g == id:
			refresh())
	lib.progress.connect(func(g: String) -> void:
		if g == id:
			_show_progress())
	refresh()


func refresh() -> void:
	var g: Library.Game = lib.games.get(id)
	if g == null:
		return
	var st := lib.status(g)
	var b := lib.latest(g)
	_title.text = g.name
	_tagline.text = g.tagline
	_tagline.visible = not g.tagline.is_empty()
	_cover.show_game(g)
	_placeholder.text = g.name
	_placeholder.visible = g.cover == null
	var dim := st in [Library.Status.INSTALL, Library.Status.BLOCKED, Library.Status.UNAVAILABLE]
	_cover.mat.set_shader_parameter("shade", 0.62 if dim else 1.0)

	for c in _badges.get_children():
		c.queue_free()
	var look := Style.look(lib, g)
	_badges.add_child(Style.pill(look[0], look[1], st == Library.Status.UPDATE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	_badges.add_child(spacer)
	if lib.is_recent(g):
		_badges.add_child(Style.pill("New · " + Fmt.ago(Fmt.unix(b.published)), Style.GOLD_PALE, true))

	var text := ""
	var color := Style.DIM
	match st:
		Library.Status.READY, Library.Status.RUNNING:
			text = "%s · %s" % [Fmt.short_version(g.installed.version), g.installed.channel]
		Library.Status.UPDATE:
			text = "%s → %s" % [Fmt.short_version(g.installed.version), Fmt.short_version(b.version)]
			color = Style.GOLD
		Library.Status.INSTALL:
			text = "%s · %s" % [Fmt.bytes(int(b.size)), lib.channel_of(g)]
		Library.Status.BLOCKED:
			text = lib.blocked_reason(g)
			color = Style.BLOCKED
		Library.Status.UNAVAILABLE:
			text = "Can't reach the server" if not lib.online else "Nothing published yet"
	if g.error and st != Library.Status.BUSY:
		text = g.error
		color = Style.BLOCKED
	_info.text = text
	_info.add_theme_color_override("font_color", color)
	_info.tooltip_text = g.installed.get("version", b.get("version", ""))

	_action.visible = true
	_action.disabled = false
	match st:
		Library.Status.READY:
			_set_action("Play", "PrimaryButton")
		Library.Status.UPDATE:
			_set_action("Update", "PrimaryButton")
		Library.Status.INSTALL:
			_set_action("Install", "Button")
		Library.Status.BUSY:
			_set_action("Cancel", "GhostButton")
		Library.Status.RUNNING:
			_set_action("Running", "Button")
			_action.disabled = true
		Library.Status.STEAM:
			_set_action("Open in Steam", "PrimaryButton")
		_:
			_action.visible = false
	_bar.visible = st == Library.Status.BUSY
	_show_progress()


func _set_action(text: String, type: String) -> void:
	_action.text = text
	_action.theme_type_variation = type


func _show_progress() -> void:
	var g: Library.Game = lib.games.get(id)
	if g == null or g.task.is_empty():
		return
	if g.task == "verify":
		_info.text = "Checking files…"
		_bar.value = 1.0
	else:
		var frac := float(g.done) / maxf(1.0, g.total)
		_info.text = "%d%% · %s/s" % [floori(frac * 100.0), Fmt.bytes(int(g.speed))]
		_bar.value = frac
	_info.add_theme_color_override("font_color", Style.GOLD_PALE)


func _on_resized() -> void:
	_cover_box.custom_minimum_size.y = roundf(size.x * 9.0 / 16.0)
	pivot_offset = size / 2.0


func _set_hover(on: bool) -> void:
	if _hover:
		_hover.kill()
	_hover = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover.tween_property(self, "scale", Vector2.ONE * (1.015 if on else 1.0), 0.22)
	_hover.tween_property(_border, "border_color", Color(Style.GOLD, 0.55) if on else Color(1, 1, 1, 0.06), 0.22)
	_cover.tween_param(_hover, "zoom", 1.045 if on else 1.0, 0.45)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		opened.emit(id)
		accept_event()
