extends Control
## One game's details: versions, channel, release notes, rollback and uninstall. Slides
## in from the right over a dimmed library; Esc or a click outside closes it.

const CoverView := preload("res://src/ui/cover_view.gd")
const WIDTH := 470.0

var lib: Library
var id := ""
var slide := 0.0:
	set(v):
		slide = v
		_place()

var _tween: Tween
var _scrim := ColorRect.new()
var _panel := PanelContainer.new()
var _scroll := ScrollContainer.new()
var _cover := CoverView.new()
var _placeholder := Label.new()
var _title := Label.new()
var _tagline := Label.new()
var _pills := HBoxContainer.new()
var _primary := Button.new()
var _play_old := Button.new()
var _progress := VBoxContainer.new()
var _bar := ProgressBar.new()
var _progress_label := Label.new()
var _error := Label.new()
var _channels := {}
var _channel_note := Label.new()
var _facts := GridContainer.new()
var _notes := Label.new()
var _rollback := Button.new()
var _files := Button.new()
var _uninstall := Button.new()
var _confirm_uninstall := false


func setup(library: Library) -> void:
	lib = library
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false

	_scrim.color = Color(0.02, 0.02, 0.04, 0.6)
	_scrim.set_anchors_preset(PRESET_FULL_RECT)
	_scrim.modulate.a = 0.0
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_scrim)

	var ps := Style.box(Color("#121119"), 0)
	ps.border_color = Style.RULE
	ps.border_width_left = 1
	ps.shadow_color = Color(0, 0, 0, 0.45)
	ps.shadow_size = 40
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	_scroll.add_child(col)

	var cover_box := Control.new()
	cover_box.custom_minimum_size = Vector2(WIDTH, roundf(WIDTH * 9.0 / 16.0))
	cover_box.clip_contents = true
	col.add_child(cover_box)
	_cover.set_anchors_preset(PRESET_FULL_RECT)
	_cover.mat.set_shader_parameter("fade", 0.9)
	_cover.mat.set_shader_parameter("fade_color", Color("#121119"))
	cover_box.add_child(_cover)
	Style.placeholder_title(_placeholder, 40)
	cover_box.add_child(_placeholder)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.add_theme_stylebox_override("normal", Style.box(Color(Style.VOID, 0.7), 99, Color(1, 1, 1, 0.1), 11, 1))
	close_btn.add_theme_stylebox_override("hover", Style.box(Color(Style.VOID, 0.9), 99, Color(Style.GOLD, 0.5), 11, 1))
	close_btn.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	close_btn.position = Vector2(WIDTH - 54, 16)
	close_btn.pressed.connect(close)
	cover_box.add_child(close_btn)

	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 28)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 32)
	col.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)

	_title.theme_type_variation = "H2"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_tagline.theme_type_variation = "Mist"
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tagline)
	_pills.add_theme_constant_override("separation", 6)
	v.add_child(_pills)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	v.add_child(actions)
	_primary.size_flags_horizontal = SIZE_EXPAND_FILL
	_primary.custom_minimum_size.y = 46
	_primary.add_theme_font_size_override("font_size", 16)
	_primary.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_primary.pressed.connect(func() -> void: lib.act(id))
	actions.add_child(_primary)
	_play_old.custom_minimum_size.y = 46
	_play_old.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_play_old.pressed.connect(func() -> void: lib.play(id))
	actions.add_child(_play_old)

	_progress.add_theme_constant_override("separation", 8)
	v.add_child(_progress)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.custom_minimum_size.y = 6
	_progress.add_child(_bar)
	var prow := HBoxContainer.new()
	_progress.add_child(prow)
	_progress_label.theme_type_variation = "Mono"
	_progress_label.size_flags_horizontal = SIZE_EXPAND_FILL
	prow.add_child(_progress_label)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.theme_type_variation = "GhostButton"
	cancel.pressed.connect(func() -> void: lib.cancel(id))
	prow.add_child(cancel)

	_error.add_theme_color_override("font_color", Style.BLOCKED)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_error)

	v.add_child(_rule())
	v.add_child(_caps("Channel"))
	var seg := PanelContainer.new()
	seg.add_theme_stylebox_override("panel", Style.box(Style.VOID_LIFT, 10, Style.RULE, 4, 4))
	v.add_child(seg)
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 4)
	seg.add_child(seg_row)
	var group := ButtonGroup.new()
	for ch in ["stable", "beta"]:
		var b := Button.new()
		b.text = ch.capitalize()
		b.theme_type_variation = "SegButton"
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void: lib.set_channel(id, ch))
		seg_row.add_child(b)
		_channels[ch] = b
	_channel_note.theme_type_variation = "Dim"
	_channel_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_channel_note)

	v.add_child(_caps("Build"))
	_facts.columns = 2
	_facts.add_theme_constant_override("h_separation", 18)
	_facts.add_theme_constant_override("v_separation", 8)
	v.add_child(_facts)

	v.add_child(_caps("What's new"))
	var notes_box := PanelContainer.new()
	notes_box.add_theme_stylebox_override("panel", Style.box(Style.PANEL, 10, Style.RULE, 16, 14))
	v.add_child(notes_box)
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.theme_type_variation = "Mist"
	notes_box.add_child(_notes)

	v.add_child(_rule())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	v.add_child(foot)
	_rollback.theme_type_variation = "GhostButton"
	_rollback.pressed.connect(func() -> void: lib.rollback(id))
	foot.add_child(_rollback)
	_files.text = "Show files"
	_files.theme_type_variation = "GhostButton"
	_files.pressed.connect(func() -> void:
		var g: Library.Game = lib.games.get(id)
		if g and not g.installed.is_empty():
			OS.shell_show_in_file_manager(ProjectSettings.globalize_path(g.installed.path)))
	foot.add_child(_files)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	foot.add_child(spacer)
	_uninstall.theme_type_variation = "DangerButton"
	_uninstall.pressed.connect(_on_uninstall)
	foot.add_child(_uninstall)

	resized.connect(_place)
	lib.game_changed.connect(func(g: String) -> void:
		if g == id and visible:
			refresh())
	lib.catalog_changed.connect(func() -> void:
		if visible:
			refresh())
	lib.progress.connect(func(g: String) -> void:
		if g == id:
			_show_progress())


func open(game_id: String) -> void:
	id = game_id
	_confirm_uninstall = false
	refresh()
	_scroll.scroll_vertical = 0
	visible = true
	_animate(1.0, 0.38, Tween.EASE_OUT)


func close() -> void:
	if visible:
		_animate(0.0, 0.24, Tween.EASE_IN).finished.connect(func() -> void: visible = false)


func _animate(to: float, time: float, easing: Tween.EaseType) -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(easing)
	_tween.tween_property(self, "slide", to, time)
	_tween.tween_property(_scrim, "modulate:a", to, time)
	return _tween


func _place() -> void:
	_panel.size = Vector2(WIDTH, size.y)
	_panel.position = Vector2(size.x - WIDTH * slide, 0)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var g: Library.Game = lib.games.get(id)
	if g == null:
		close()
		return
	var st := lib.status(g)
	var b := lib.latest(g)
	var channel := lib.channel_of(g)
	_cover.show_game(g)
	_placeholder.text = g.name
	_placeholder.visible = g.cover == null
	_title.text = g.name
	_tagline.text = g.tagline
	_tagline.visible = not g.tagline.is_empty()

	for c in _pills.get_children():
		c.queue_free()
	var look := Style.look(lib, g)
	_pills.add_child(Style.pill(look[0], look[1], st == Library.Status.UPDATE))
	if lib.is_recent(g):
		_pills.add_child(Style.pill("Updated " + Fmt.ago(Fmt.unix(b.published)), Style.GOLD_PALE, true))
	if channel:
		_pills.add_child(Style.pill(channel, Style.MIST))

	_primary.visible = st != Library.Status.BUSY
	_primary.disabled = false
	_primary.theme_type_variation = "PrimaryButton"
	match st:
		Library.Status.READY:
			_primary.text = "Play"
		Library.Status.UPDATE:
			_primary.text = "Update to %s" % Fmt.short_version(b.version)
		Library.Status.INSTALL:
			_primary.text = "Install  ·  %s" % Fmt.bytes(int(b.size))
		Library.Status.RUNNING:
			_primary.text = "Playing…"
			_primary.disabled = true
			_primary.theme_type_variation = "Button"
		Library.Status.BLOCKED:
			_primary.text = lib.blocked_reason(g)
			_primary.disabled = true
			_primary.theme_type_variation = "Button"
		_:
			_primary.text = "Unavailable offline" if not lib.online else "No build published yet"
			_primary.disabled = true
			_primary.theme_type_variation = "Button"
	_play_old.visible = st == Library.Status.UPDATE
	if _play_old.visible:
		_play_old.text = "Play %s" % Fmt.short_version(g.installed.version)
	_progress.visible = st == Library.Status.BUSY
	_show_progress()
	_error.text = g.error
	_error.visible = not g.error.is_empty()

	for ch: String in _channels:
		_channels[ch].set_pressed_no_signal(g.channel == ch)
	var channels: Dictionary = g.manifest.get("channels", {})
	if g.manifest.is_empty():
		_channel_note.text = "Builds show up here once the server has one."
	elif not channels.has(g.channel) and channel:
		_channel_note.text = "No %s build yet, so you get %s builds until there is one." % [g.channel, channel]
	elif g.channel == "beta":
		_channel_note.text = "Beta builds land as soon as they're published. Expect rough edges."
	else:
		_channel_note.text = "Stable builds are the ones marked ready to play."

	for c in _facts.get_children():
		c.queue_free()
	_fact("Installed", g.installed.get("version", "—"))
	_fact("Latest", ("%s  (%s)" % [b.version, channel]) if b else "—")
	if b:
		var t := Fmt.unix(b.get("published", ""))
		_fact("Published", "%s  ·  %s" % [Fmt.ago(t), Time.get_datetime_string_from_unix_time(t, true).left(16)])
		_fact("Download", Fmt.bytes(int(b.get("size", 0))))
		_fact("Commit", b.get("commit", "—"))
	if g.manifest:
		_fact("Engine", "Godot %s" % g.manifest.get("godot", "?"))
	var notes: String = b.get("notes", "") if b else ""
	_notes.text = notes if notes else "No notes for this build."

	var idle := st not in [Library.Status.BUSY, Library.Status.RUNNING]
	_rollback.visible = not g.previous.is_empty()
	_rollback.disabled = not idle
	if _rollback.visible:
		_rollback.text = "Roll back to %s" % Fmt.short_version(g.previous.version)
	_files.visible = not g.installed.is_empty()
	_uninstall.visible = not g.installed.is_empty()
	_uninstall.disabled = not idle
	_uninstall.text = "Click again to uninstall" if _confirm_uninstall else "Uninstall"


func _show_progress() -> void:
	var g: Library.Game = lib.games.get(id)
	if g == null or g.task.is_empty():
		return
	if g.task == "verify":
		_bar.value = 1.0
		_progress_label.text = "Checking files…"
	else:
		_bar.value = float(g.done) / maxf(1.0, g.total)
		_progress_label.text = "%s of %s  ·  %s/s" % [Fmt.bytes(g.done), Fmt.bytes(g.total), Fmt.bytes(int(g.speed))]


func _on_uninstall() -> void:
	if not _confirm_uninstall:
		_confirm_uninstall = true
		refresh()
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			_confirm_uninstall = false
			if visible:
				refresh())
		return
	_confirm_uninstall = false
	lib.uninstall(id)


func _fact(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.theme_type_variation = "Dim"
	_facts.add_child(k)
	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", Style.mono())
	val.add_theme_font_size_override("font_size", 13)
	val.size_flags_horizontal = SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_facts.add_child(val)


func _caps(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "Caps"
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Style.RULE
	r.custom_minimum_size.y = 1
	return r
