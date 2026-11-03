extends Control
## The launcher window: a sidebar of views (Library, Ready to play, Updates, Recently
## updated, Not installed), a grid of game cards for the current view, and a drawer with
## one game's details. All state lives in Library; this only shows it.

const Card := preload("res://src/ui/game_card.gd")
const Drawer := preload("res://src/ui/game_drawer.gd")
const BACKGROUND := preload("res://src/ui/background.gdshader")

## key: [title, what it shows, dot colour, what it says when empty]
var views := {
	"all": ["Library", "", Style.PAPER, ["Nothing here yet", "Games show up once they're published."]],
	"ready": ["Ready to play", "Installed and on the latest build", Style.READY, ["Nothing installed yet", "Install a game from the Library."]],
	"updates": ["Updates", "A newer build is waiting", Style.UPDATE, ["All up to date", "Every installed game is on its latest build."]],
	"recent": ["Recently updated", "New builds in the last 3 days", Style.GOLD_PALE, ["Quiet lately", "Nothing new in the last 3 days."]],
	"available": ["Not installed", "On the server, not on this computer", Style.MIST, ["You have everything", "Every game is installed."]],
}

var lib := Library.new()
var view := "all"

var _cards := {}
var _nav := {}
var _nav_group := ButtonGroup.new()
var _grid := GridContainer.new()
var _scroll := ScrollContainer.new()
var _heading := Label.new()
var _subheading := Label.new()
var _update_all := Button.new()
var _banner := PanelContainer.new()
var _banner_text := Label.new()
var _empty := VBoxContainer.new()
var _empty_title := Label.new()
var _empty_body := Label.new()
var _status_dot: Panel
var _status_text := Label.new()
var _check := Button.new()
var _auto := CheckButton.new()
var _toasts := VBoxContainer.new()
var _banner_button := Button.new()
var _update_card := PanelContainer.new()
var _update_text := Label.new()
var _drawer := Drawer.new()
var _shown := 0


func _ready() -> void:
	theme = Style.theme()
	_fit_window()
	add_child(lib)
	_build()
	lib.catalog_changed.connect(_sync)
	lib.game_changed.connect(func(_id: String) -> void: _apply_view())
	lib.installed.connect(func(id: String, version: String) -> void:
		_toast("%s is ready" % lib.games[id].name, version))
	var tick := Timer.new()  # keeps "checked 2m ago" and "New · 3h ago" honest
	tick.wait_time = 30.0
	tick.autostart = true
	tick.timeout.connect(_sync)
	add_child(tick)
	_auto.set_pressed_no_signal(lib.auto_update)
	lib.launcher_changed.connect(_apply_view)
	_sync()
	lib.mark_started()
	_dev_flags()


## On a high-DPI screen, draw at the screen's scale so text isn't tiny.
func _fit_window() -> void:
	var w := get_window()
	var s := DisplayServer.screen_get_scale()
	w.content_scale_factor = s
	w.min_size = Vector2i(Vector2(960, 620) * s)
	if s > 1.0:  # the window's size is in physical pixels, so grow it to match
		var screen := DisplayServer.screen_get_usable_rect(w.current_screen)
		w.size = Vector2i(Vector2(1280, 800) * s).min(screen.size)
		w.position = screen.position + (screen.size - w.size) / 2


# --- layout ----------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.material = ShaderMaterial.new()
	(bg.material as ShaderMaterial).shader = BACKGROUND
	bg.resized.connect(func() -> void: (bg.material as ShaderMaterial).set_shader_parameter("rect_size", bg.size))
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.add_child(_build_sidebar())
	row.add_child(_build_library())

	add_child(_drawer)
	_drawer.setup(lib)

	_toasts.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	_toasts.grow_horizontal = GROW_DIRECTION_BEGIN
	_toasts.grow_vertical = GROW_DIRECTION_BEGIN
	_toasts.offset_right = -28
	_toasts.offset_bottom = -28
	_toasts.mouse_filter = MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 10)
	add_child(_toasts)


func _build_sidebar() -> Control:
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 252
	var s := Style.box(Color(Style.VOID, 0.55), 0)
	s.border_color = Style.RULE
	s.border_width_right = 1
	side.add_theme_stylebox_override("panel", s)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_bottom", 20)
	side.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/brand/title_trismeg.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(0, 40)
	var logo_pad := MarginContainer.new()
	logo_pad.add_theme_constant_override("margin_left", 12)
	logo_pad.add_theme_constant_override("margin_right", 60)
	logo_pad.add_child(logo)
	v.add_child(logo_pad)
	var sub := Label.new()
	sub.text = "STUDIOS LAUNCHER"
	sub.add_theme_font_override("font", Style.mono(500, 3))
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Style.GOLD_DEEP)
	var sub_pad := MarginContainer.new()
	sub_pad.add_theme_constant_override("margin_left", 14)
	sub_pad.add_child(sub)
	v.add_child(sub_pad)

	v.add_child(_gap(34))
	for key: String in views:
		v.add_child(_nav_button(key))
	_nav["all"].button_pressed = true

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(spacer)

	var card := Style.box(Color(Style.GOLD, 0.08), 12, Color(Style.GOLD, 0.3), 14, 12)
	_update_card.add_theme_stylebox_override("panel", card)
	_update_card.visible = false
	v.add_child(_update_card)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", 8)
	_update_card.add_child(uv)
	var ut := Label.new()
	ut.text = "Launcher update ready"
	ut.add_theme_font_override("font", Style.sans(600))
	ut.add_theme_color_override("font_color", Style.GOLD_PALE)
	uv.add_child(ut)
	_update_text.theme_type_variation = "Mono"
	uv.add_child(_update_text)
	var restart := Button.new()
	restart.text = "Restart to update"
	restart.theme_type_variation = "PrimaryButton"
	restart.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	restart.pressed.connect(lib.restart)
	uv.add_child(restart)
	v.add_child(_gap(14))

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 9)
	var status_pad := MarginContainer.new()
	status_pad.add_theme_constant_override("margin_left", 14)
	status_pad.add_child(status)
	v.add_child(status_pad)
	_status_dot = Style.dot(Style.DIM, 7, true)
	status.add_child(_status_dot)
	_status_text.theme_type_variation = "Dim"
	_status_text.size_flags_horizontal = SIZE_EXPAND_FILL
	_status_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(_status_text)
	v.add_child(_gap(6))
	_check.text = "Check for updates"
	_check.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_check.pressed.connect(lib.refresh)
	v.add_child(_check)
	_auto.text = "Update games automatically"
	_auto.add_theme_font_size_override("font_size", 13)
	_auto.toggled.connect(lib.set_auto_update)
	v.add_child(_auto)
	v.add_child(_gap(6))
	var version := Label.new()
	version.text = "Launcher %s  ·  engine %s" % [lib.ui_version, lib.engine_build]
	version.tooltip_text = "Godot %s" % lib.engine_version
	version.mouse_filter = MOUSE_FILTER_PASS
	version.add_theme_font_override("font", Style.mono())
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(Style.DIM, 0.7))
	var version_pad := MarginContainer.new()
	version_pad.add_theme_constant_override("margin_left", 14)
	version_pad.add_child(version)
	v.add_child(version_pad)
	return side


func _nav_button(key: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "NavButton"
	b.toggle_mode = true
	b.button_group = _nav_group
	b.text = views[key][0]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 40
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.pressed.connect(_set_view.bind(key))
	var d := Style.dot(views[key][2], 7, key == "recent")
	d.position = Vector2(17, 16.5)
	b.add_child(d)
	var count := Label.new()
	count.name = "Count"
	count.add_theme_font_override("font", Style.mono(500))
	count.add_theme_font_size_override("font_size", 11)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.anchor_left = 1.0
	count.anchor_right = 1.0
	count.anchor_top = 0.5
	count.anchor_bottom = 0.5
	count.offset_left = -44
	count.offset_right = -12
	count.offset_top = -10
	count.offset_bottom = 10
	count.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(count)
	_nav[key] = b
	return b


func _build_library() -> Control:
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 44)
	m.add_theme_constant_override("margin_right", 32)
	m.add_theme_constant_override("margin_top", 30)
	m.add_child(VBoxContainer.new())
	var v: VBoxContainer = m.get_child(0)
	v.add_theme_constant_override("separation", 22)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	_heading.theme_type_variation = "H1"
	titles.add_child(_heading)
	_subheading.theme_type_variation = "Mist"
	titles.add_child(_subheading)
	_update_all.theme_type_variation = "PrimaryButton"
	_update_all.size_flags_vertical = SIZE_SHRINK_END
	_update_all.custom_minimum_size.y = 42
	_update_all.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_update_all.pressed.connect(lib.update_all)
	head.add_child(_update_all)

	_banner.add_theme_stylebox_override("panel", Style.box(Color(Style.BLOCKED, 0.08), 10, Color(Style.BLOCKED, 0.3), 16, 8))
	v.add_child(_banner)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	_banner.add_child(brow)
	brow.add_child(Style.dot(Style.BLOCKED, 7))
	_banner_text.size_flags_horizontal = SIZE_EXPAND_FILL
	_banner_text.add_theme_color_override("font_color", Color("#f2b8aa"))
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brow.add_child(_banner_text)
	_banner_button.theme_type_variation = "GhostButton"
	_banner_button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_banner_button.pressed.connect(func() -> void:
		if lib.engine_outdated or lib.launcher_outdated:
			OS.shell_open(lib.launcher_download_url())
		else:
			lib.refresh())
	brow.add_child(_banner_button)

	var area := Control.new()  # the grid and the empty state share this space
	area.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(area)
	_scroll.set_anchors_preset(PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.resized.connect(_fit_columns)
	area.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 6)  # room for a hovered card to grow
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_bottom", 40)
	_scroll.add_child(pad)
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 22)
	pad.add_child(_grid)

	_empty.set_anchors_preset(PRESET_FULL_RECT)
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.offset_bottom = -80
	_empty.add_theme_constant_override("separation", 6)
	area.add_child(_empty)
	_empty_title.theme_type_variation = "H2"
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(_empty_title)
	_empty_body.theme_type_variation = "Mist"
	_empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(_empty_body)
	return m


func _fit_columns() -> void:
	_grid.columns = clampi(floori((_scroll.size.x + 22.0) / 340.0), 1, 4)


# --- state -----------------------------------------------------------------

func _sync() -> void:
	var ordered := lib.ordered()
	for g in ordered:
		if not _cards.has(g.id):
			var c := Card.new()
			c.setup(lib, g.id)
			c.opened.connect(_drawer.open)
			_grid.add_child(c)
			_cards[g.id] = c
			_animate_in(c)
	for id: String in _cards.keys():
		if not lib.games.has(id):
			_cards[id].queue_free()
			_cards.erase(id)
	for i in ordered.size():
		_grid.move_child(_cards[ordered[i].id], i)
		_cards[ordered[i].id].refresh()
	_apply_view()


func _in_view(g: Library.Game, key: String) -> bool:
	var st := lib.status(g)
	match key:
		"ready":
			return st in [Library.Status.READY, Library.Status.RUNNING]
		"updates":
			return st == Library.Status.UPDATE or (st == Library.Status.BUSY and not g.installed.is_empty())
		"recent":
			return lib.is_recent(g)
		"available":
			return g.installed.is_empty() and st != Library.Status.UNAVAILABLE
	return true


func _set_view(key: String) -> void:
	if key == view:
		return
	view = key
	_apply_view()
	_scroll.scroll_vertical = 0
	var shown := 0
	for g in lib.ordered():
		if _in_view(g, view) and _cards.has(g.id):
			_animate_in(_cards[g.id], shown)
			shown += 1


func _apply_view() -> void:
	var counts := {}
	for key: String in views:
		counts[key] = 0
	var games := lib.ordered()
	for g in games:
		for key: String in views:
			if _in_view(g, key):
				counts[key] += 1
		if _cards.has(g.id):
			_cards[g.id].visible = _in_view(g, view)

	for key: String in views:
		var count: Label = _nav[key].get_node("Count")
		var n: int = counts[key]
		count.text = str(n) if n else ""
		var hot: bool = n > 0 and key == "updates"
		count.add_theme_color_override("font_color", Style.VOID if hot else Style.DIM)
		count.add_theme_stylebox_override("normal", Style.box(Style.GOLD, 99) if hot else StyleBoxEmpty.new())

	_heading.text = views[view][0]
	if view == "all":
		var parts := ["%d game%s" % [games.size(), "" if games.size() == 1 else "s"]]
		if counts.ready:
			parts.append("%d ready" % counts.ready)
		if counts.updates:
			parts.append("%d to update" % counts.updates)
		_subheading.text = "  ·  ".join(parts)
	else:
		_subheading.text = views[view][1]
	var updatable := 0
	for g in games:
		if lib.status(g) == Library.Status.UPDATE:
			updatable += 1
	_update_all.visible = updatable > 1 or (updatable == 1 and view == "updates")
	_update_all.text = "Update all  (%d)" % updatable if updatable > 1 else "Update"

	_empty.visible = counts[view] == 0 and not (lib.refreshing and games.is_empty())
	_scroll.visible = not _empty.visible
	var empty: Array = views[view][3]
	if view == "all" and not lib.online and not lib.refreshing:
		empty = ["Can't reach the server", "Check your connection, then try again."]
	_empty_title.text = empty[0]
	_empty_body.text = empty[1]

	var new_exe := lib.engine_outdated or lib.launcher_outdated
	_banner.visible = new_exe or (not lib.online and not lib.refreshing and lib.last_check > 0)
	if new_exe:
		_banner_text.text = "A new version of the launcher is out. Download it to keep getting updates."
		_banner_button.text = "Download"
	else:
		_banner_text.text = "Offline. Showing the library from %s; installed games still play." % Fmt.ago(lib.last_check)
		_banner_button.text = "Try again"
	_update_card.visible = not lib.ui_ready.is_empty()
	_update_text.text = "%s → %s" % [Fmt.short_version(lib.ui_version), Fmt.short_version(lib.ui_ready)]

	if lib.refreshing:
		_status_text.text = "Checking for updates…"
		_status_dot.get_theme_stylebox("panel").bg_color = Style.GOLD
	elif lib.online:
		_status_text.text = "Online · checked %s" % Fmt.ago(lib.last_check)
		_status_dot.get_theme_stylebox("panel").bg_color = Style.READY
	else:
		_status_text.text = "Offline"
		_status_dot.get_theme_stylebox("panel").bg_color = Style.BLOCKED
	_check.disabled = lib.refreshing


# --- motion ----------------------------------------------------------------

func _animate_in(c: Control, order := -1) -> void:
	if order < 0:
		order = _shown
		_shown += 1
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * 0.97
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(order * 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.45).set_delay(order * 0.06)


func _toast(title: String, body: String) -> void:
	var p := PanelContainer.new()
	var s := Style.box(Style.PANEL_HI, 12, Style.RULE_GOLD, 18, 12)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 18
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size.x = 300
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	row.add_child(Style.dot(Style.READY, 8, true))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	row.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", Style.sans(600))
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.theme_type_variation = "Mono"
	v.add_child(b)
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## Development only: `-- --play=<id>` installs and starts a game; `-- --screenshot=out.png
## [--open=<id>] [--view=<key>]` saves the window a few seconds after start and quits.
func _dev_flags() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			shot = a.get_slice("=", 1)
		elif a.begins_with("--play="):
			_dev_play(a.get_slice("=", 1))
		elif a.begins_with("--view="):
			_nav[a.get_slice("=", 1)].button_pressed = true
			_set_view(a.get_slice("=", 1))
	if shot.is_empty():
		return
	await get_tree().create_timer(4.0).timeout
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--open="):
			_drawer.open(a.get_slice("=", 1))
			await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


func _dev_play(id: String) -> void:
	while lib.refreshing or not lib.games.has(id):
		await get_tree().process_frame
	if lib.games[id].installed.is_empty():
		await lib.install(id)
	lib.play(id)
