class_name Library
extends Node
## Everything the launcher knows about the games: what the server offers (games/index.json
## and each game's manifest.json, cached so the library still shows offline), what is
## installed under user://games/<id>/, and the downloads and game processes in flight.
## Follows "Build format v1" on the Trismeg Launcher page in Notion. The UI reads this
## and calls its actions; it never touches files or the network itself.

signal catalog_changed  ## games came or went, a refresh started or finished
signal game_changed(id: String)
signal progress(id: String)  ## a download moved; read done, total and speed off the game
signal installed(id: String, version: String)
signal launcher_changed  ## a launcher update was found or finished downloading

enum Status { INSTALL, UPDATE, READY, BUSY, RUNNING, BLOCKED, UNAVAILABLE }

const SCHEMA := 1
const RECENT := 3 * 86400  ## builds newer than this count as "recently updated"
const REFRESH_EVERY := 300.0
const STALL_MS := 30000
const RETRIES := 3
const STATE := "user://state.json"
const CACHE := "user://cache/"
const GAMES := "user://games/"
const UI_DIR := "user://launcher/ui/"
const UI_STATE := "user://launcher/ui.json"  ## shared with boot.gd


class Game:
	var id := ""
	var name := ""
	var tagline := ""
	var order := 100
	var manifest := {}
	var channel := "stable"  ## the player's pick; latest() falls back to whatever exists
	var installed := {}  ## the manifest entry of the build on disk, plus channel and path
	var previous := {}  ## the build before it, kept for rollback
	var task := ""  ## "download" or "verify" while installing
	var cancelled := false
	var done := 0
	var total := 0
	var speed := 0.0  ## bytes per second, smoothed
	var error := ""
	var pid := 0
	var cover: Texture2D
	var cover_checked := false


class Transfer:
	signal finished(problem: String)
	var http: HTTPRequest
	var last_bytes := 0
	var change_ms := 0
	var mark_bytes := 0
	var mark_ms := 0


var games := {}
var online := false
var refreshing := false
var last_check := 0
var auto_update := false
var launcher_outdated := false  ## the server speaks a newer format than this launcher
var engine_version := "%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor]
## The bucket. TRISMEG_BASE points a launcher at a copy of it, e.g. ".../_test/" for testing.
var base := OS.get_environment("TRISMEG_BASE").trim_suffix("/") + "/" if OS.has_environment("TRISMEG_BASE") else "https://builds.trismegstudios.com/"
var ui_version: String = _build_info().get("version", "dev")  ## this UI's build, from the publish script
var engine_build: String = ProjectSettings.get_setting("trismeg/engine_version", "dev")  ## the exe's
var ui_ready := ""  ## a newer UI that is downloaded and starts with the next launch
var engine_outdated := false  ## a newer exe is out; only a fresh download gets it

var _transfers := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE + "covers")
	DirAccess.make_dir_recursive_absolute(GAMES)
	_load()
	var timer := Timer.new()
	timer.wait_time = REFRESH_EVERY
	timer.autostart = true
	timer.timeout.connect(refresh)
	add_child(timer)
	var watch := Timer.new()
	watch.wait_time = 1.0
	watch.autostart = true
	watch.timeout.connect(_watch_processes)
	add_child(watch)
	refresh()


# --- reading ---------------------------------------------------------------

func ordered() -> Array[Game]:
	var out: Array[Game] = []
	for g: Game in games.values():
		out.append(g)
	out.sort_custom(func(a: Game, b: Game) -> bool:
		return a.id < b.id if a.order == b.order else a.order < b.order)
	return out


## The channel the player actually gets: their pick if the game has it, else the other.
func channel_of(g: Game) -> String:
	var channels: Dictionary = g.manifest.get("channels", {})
	if channels.has(g.channel):
		return g.channel
	for c in ["stable", "beta"]:
		if channels.has(c):
			return c
	return ""


func latest(g: Game) -> Dictionary:
	var c := channel_of(g)
	return g.manifest.channels[c] if c else {}


func blocked_reason(g: Game) -> String:
	if g.manifest.is_empty():
		return ""
	if int(g.manifest.get("schema", 1)) > SCHEMA:
		return "Needs a newer launcher"
	var godot: String = g.manifest.get("godot", engine_version)
	if godot != engine_version:
		return "Needs a launcher on Godot %s" % godot
	var extensions: Dictionary = g.manifest.get("extensions", {})
	for ext: String in extensions:
		if extensions[ext] == "required" and not has_extension(ext):
			return "Needs a launcher with %s" % ext
	return ""


func has_extension(ext: String) -> bool:
	match ext:
		"godotsteam":
			return Engine.has_singleton("Steam") or ClassDB.class_exists("Steam")
	return false


func status(g: Game) -> Status:
	if g.pid:
		return Status.RUNNING
	if g.task:
		return Status.BUSY
	var b := latest(g)
	if g.installed.is_empty():
		if b.is_empty():
			return Status.UNAVAILABLE
		return Status.BLOCKED if blocked_reason(g) else Status.INSTALL
	if not b.is_empty() and b.version != g.installed.get("version") and not blocked_reason(g):
		return Status.UPDATE
	return Status.READY


func is_recent(g: Game) -> bool:
	var t := Fmt.unix(latest(g).get("published", ""))
	return t > 0 and Fmt.now() - t < RECENT


# --- actions ---------------------------------------------------------------

## Whatever the game's main button means right now.
func act(id: String) -> void:
	var g: Game = games.get(id)
	if g == null:
		return
	match status(g):
		Status.READY:
			play(id)
		Status.UPDATE, Status.INSTALL:
			install(id)
		Status.BUSY:
			cancel(id)


func update_all() -> void:
	for g in ordered():
		if status(g) == Status.UPDATE:
			install(g.id)


func refresh() -> void:
	if refreshing:
		return
	refreshing = true
	catalog_changed.emit()
	var index: Variant = await _fetch_json("games/index.json")
	online = index is Dictionary
	if online:
		_write_json(CACHE + "index.json", index)
		_apply_index(index)
		for id: String in games.keys():
			var m: Variant = await _fetch_json("games/%s/manifest.json" % id)
			if m is Dictionary and games.has(id):
				games[id].manifest = m
				_write_json(CACHE + id + ".json", m)
		last_check = Fmt.now()
		_save()
	refreshing = false
	catalog_changed.emit()
	if online:
		for g: Game in games.values():
			_fetch_cover(g)
		if auto_update:
			update_all()
	_check_launcher()


## Downloads the latest build of the game's channel, checks it, and swaps it in. The build
## it replaces stays on disk for rollback.
func install(id: String) -> void:
	var g: Game = games.get(id)
	if g == null or g.task or g.pid:
		return
	var b := latest(g)
	if b.is_empty() or blocked_reason(g):
		return
	var dir := GAMES + id + "/builds/"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + String(b.file).get_file()
	g.error = ""
	g.cancelled = false
	g.total = int(b.size)
	g.done = 0
	g.speed = 0.0
	var problem := "missing"
	if FileAccess.file_exists(path):  # e.g. switching back to a channel's build we still have
		g.task = "verify"
		game_changed.emit(id)
		problem = await _verify(path, b)
	if problem:
		problem = await _download_verified(g, base + "games/%s/%s" % [id, b.file], path, b)
	g.task = ""
	if problem == "cancelled":
		pass
	elif problem:
		g.error = problem
	else:
		if not g.installed.is_empty() and g.installed.get("version") != b.version:
			g.previous = g.installed
		var entry := b.duplicate()
		entry.channel = channel_of(g)
		entry.path = path
		entry.installed_at = Fmt.now()
		g.installed = entry
		_prune(g)
		_save()
		installed.emit(id, b.version)
	game_changed.emit(id)
	catalog_changed.emit()


func cancel(id: String) -> void:
	var g: Game = games.get(id)
	if g == null or not g.task:
		return
	g.cancelled = true
	var t: Transfer = _transfers.get(id)
	if t:
		t.http.cancel_request()
		t.finished.emit("cancelled")


func play(id: String) -> void:
	var g: Game = games.get(id)
	if g == null or g.pid or g.task or g.installed.is_empty():
		return
	var path := ProjectSettings.globalize_path(g.installed.get("path", ""))
	if not FileAccess.file_exists(path):
		g.error = "The installed build is missing; install it again"
		g.installed = {}
		_save()
		game_changed.emit(id)
		catalog_changed.emit()
		return
	var exe := OS.get_executable_path()
	var args := PackedStringArray()
	if OS.has_feature("editor"):  # the editor binary takes --main-pack; export templates don't
		args.append_array(["--main-pack", path])
	else:
		exe = _runner(g)
	for a: Variant in g.manifest.get("args", []):
		args.append(str(a))
	var pid := OS.create_process(exe, args) if exe else -1
	if pid <= 0:
		g.error = "Couldn't start the game"
	else:
		g.pid = pid
		g.error = ""
		g.installed.last_played = Fmt.now()
		_save()
	game_changed.emit(id)


# Official export templates ignore --main-pack, so each game runs from its own copy of the
# launcher's engine in user://games/<id>/run/: the executable (on macOS its whole .app) with
# the game's build beside it under the executable's name, which Godot loads as its main
# pack, and the native libraries the engine ships with (GodotSteam), which Godot looks for
# next to the executable. Copies are hard links or APFS clones where the disk allows.

## The executable that runs the game's installed build, or "" if it couldn't be set up.
func _runner(g: Game) -> String:
	var exe := OS.get_executable_path()
	var run := ProjectSettings.globalize_path(GAMES + g.id + "/run")
	var build := ProjectSettings.globalize_path(g.installed.path)
	var stamp := "%s|%d|%s" % [exe, FileAccess.get_modified_time(exe), build]
	var target := run.path_join(exe.get_file())
	if OS.get_name() == "macOS":
		var app := exe.get_base_dir().get_base_dir().get_base_dir()  # …/Trismeg Launcher.app
		target = run.path_join(app.get_file()).path_join("Contents/MacOS").path_join(exe.get_file())
	if FileAccess.file_exists(target) and FileAccess.get_file_as_string(run.path_join("runner.txt")) == stamp:
		return target
	if DirAccess.dir_exists_absolute(run):
		_remove_dir(run)
	DirAccess.make_dir_recursive_absolute(run)
	var pck := run.path_join(exe.get_file().get_basename() + ".pck")
	if OS.get_name() == "macOS":
		var app := exe.get_base_dir().get_base_dir().get_base_dir()
		var copy := run.path_join(app.get_file())
		# -X leaves the download's quarantine flag behind; -c clones instead of copying
		if OS.execute("cp", ["-R", "-c", "-X", app, copy]) != 0 and OS.execute("cp", ["-R", "-X", app, copy]) != 0:
			return ""
		pck = copy.path_join("Contents/Resources").path_join(exe.get_file() + ".pck")
	else:
		if _link(exe, target) != OK:
			return ""
		FileAccess.set_unix_permissions(target, 493)  # rwxr-xr-x
		for f in DirAccess.get_files_at(exe.get_base_dir()):
			if f.get_extension() in ["dll", "so"]:
				_link(exe.get_base_dir().path_join(f), run.path_join(f))
	if _link(build, pck) != OK:
		return ""
	var f := FileAccess.open(run.path_join("runner.txt"), FileAccess.WRITE)
	f.store_string(stamp)
	return target


## Hard link (APFS clone on macOS), falling back to a plain copy.
func _link(from: String, to: String) -> Error:
	DirAccess.remove_absolute(to)
	var code := -1
	match OS.get_name():
		"Windows":
			code = OS.execute("cmd.exe", ["/c", "mklink", "/H", to.replace("/", "\\"), from.replace("/", "\\")])
		"macOS":
			code = OS.execute("cp", ["-c", from, to])
		_:
			code = OS.execute("ln", [from, to])
	if code == 0 and FileAccess.file_exists(to):
		return OK
	return DirAccess.copy_absolute(from, to)


func rollback(id: String) -> void:
	var g: Game = games.get(id)
	if g == null or g.task or g.pid or g.previous.is_empty():
		return
	if not FileAccess.file_exists(g.previous.get("path", "")):
		g.previous = {}
	else:
		var current := g.installed
		g.installed = g.previous
		g.previous = current
	_save()
	game_changed.emit(id)
	catalog_changed.emit()


func uninstall(id: String) -> void:
	var g: Game = games.get(id)
	if g == null or g.task or g.pid:
		return
	_remove_dir(GAMES + id)
	g.installed = {}
	g.previous = {}
	g.error = ""
	if g.manifest.is_empty():
		games.erase(id)
	_save()
	game_changed.emit(id)
	catalog_changed.emit()


func set_channel(id: String, channel: String) -> void:
	var g: Game = games.get(id)
	if g == null or g.channel == channel:
		return
	g.channel = channel
	_save()
	game_changed.emit(id)
	catalog_changed.emit()


func set_auto_update(on: bool) -> void:
	auto_update = on
	_save()
	if on:
		update_all()


# --- downloads -------------------------------------------------------------

func _download_verified(g: Game, url: String, path: String, b: Dictionary) -> String:
	var part := path + ".part"
	var problem := ""
	for attempt in RETRIES:
		if attempt > 0:
			await get_tree().create_timer(2.0 * attempt).timeout
		if g.cancelled:
			problem = "cancelled"
			break
		g.task = "download"
		g.done = 0
		game_changed.emit(g.id)
		problem = await _download(g, url, part)
		if problem == "cancelled":
			break
		if problem.is_empty():
			g.task = "verify"
			game_changed.emit(g.id)
			problem = await _verify(part, b)
			if g.cancelled:
				problem = "cancelled"
				break
			if problem.is_empty():
				DirAccess.remove_absolute(path)
				if DirAccess.rename_absolute(part, path) != OK:
					problem = "Couldn't move the download into place"
				return problem
	DirAccess.remove_absolute(part)
	return problem


func _download(g: Game, url: String, path: String) -> String:
	var t := Transfer.new()
	t.http = HTTPRequest.new()
	t.http.download_file = path
	t.http.download_chunk_size = 1 << 18
	t.http.use_threads = true
	add_child(t.http)
	t.http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		t.finished.emit(_http_problem(result, code)))
	t.change_ms = Time.get_ticks_msec()
	t.mark_ms = t.change_ms
	var problem := ""
	var err := t.http.request(url)
	if err != OK:
		problem = "Couldn't start the download (error %d)" % err
	else:
		_transfers[g.id] = t
		problem = await t.finished
		_transfers.erase(g.id)
	t.http.queue_free()
	return problem


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id: String in _transfers.keys():
		var t: Transfer = _transfers[id]
		var g: Game = games.get(id)
		var bytes := t.http.get_downloaded_bytes()
		if bytes != t.last_bytes:
			t.last_bytes = bytes
			t.change_ms = now
		elif now - t.change_ms > STALL_MS:
			t.http.cancel_request()
			t.finished.emit("Download stalled")
			continue
		if now - t.mark_ms >= 500:
			var rate := (bytes - t.mark_bytes) * 1000.0 / (now - t.mark_ms)
			g.speed = rate if g.speed == 0.0 else lerpf(g.speed, rate, 0.3)
			t.mark_ms = now
			t.mark_bytes = bytes
		g.done = bytes
		progress.emit(id)


## "" if the file matches the manifest's size and sha256. Hashing runs on a thread so a
## big build doesn't freeze the window.
func _verify(path: String, b: Dictionary) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() != int(b.get("size", -1)):
		return "The download was the wrong size"
	f.close()
	var thread := Thread.new()
	thread.start(_sha256.bind(ProjectSettings.globalize_path(path)))
	while thread.is_alive():
		await get_tree().process_frame
	var digest: String = thread.wait_to_finish()
	if digest != String(b.get("sha256", "")).to_lower():
		return "The download was corrupted (checksum mismatch)"
	return ""


func _sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


## Keeps the installed build and the one before it; everything else in builds/ goes.
func _prune(g: Game) -> void:
	var dir := GAMES + g.id + "/builds/"
	var keep := [g.installed.get("path", ""), g.previous.get("path", "")]
	for f in DirAccess.get_files_at(dir):
		if not (dir + f) in keep:
			DirAccess.remove_absolute(dir + f)


func _watch_processes() -> void:
	for g: Game in games.values():
		if g.pid and not OS.is_process_running(g.pid):
			g.pid = 0
			game_changed.emit(g.id)


# --- the server ------------------------------------------------------------

func _apply_index(index: Dictionary) -> void:
	launcher_outdated = int(index.get("schema", 1)) > SCHEMA
	var listed := {}
	for e: Variant in index.get("games", []):
		if not e is Dictionary or not e.has("id") or e.get("hidden", false):
			continue
		var g := _game(e.id)
		g.name = e.get("name", e.id)
		g.tagline = e.get("tagline", "")
		g.order = int(e.get("order", 100))
		listed[e.id] = true
	for id: String in games.keys():
		if not listed.has(id) and games[id].installed.is_empty():
			games.erase(id)


func _fetch_json(path: String) -> Variant:
	var r := await _request(base + path)
	if r.problem:
		return null
	return JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())


func _fetch_cover(g: Game) -> void:
	if g.cover_checked:
		return
	g.cover_checked = true
	var path := CACHE + "covers/%s.png" % g.id
	var r := await _request(base + "games/%s/cover.png" % g.id, path + ".tmp")
	if r.problem:
		DirAccess.remove_absolute(path + ".tmp")
		return
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path + ".tmp", path)
	_load_cover(g)
	game_changed.emit(g.id)


func _load_cover(g: Game) -> void:
	var cached := CACHE + "covers/%s.png" % g.id
	if FileAccess.file_exists(cached):
		var img := Image.load_from_file(cached)
		if img:
			g.cover = ImageTexture.create_from_image(img)
			return
	for ext in ["png", "jpg"]:
		var bundled := "res://assets/covers/%s.%s" % [g.id, ext]
		if ResourceLoader.exists(bundled):
			g.cover = load(bundled)
			return


func _request(url: String, to_file := "", timeout := 15.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.download_file = to_file
	add_child(http)
	var out := {"problem": "Couldn't start the request", "body": PackedByteArray()}
	if http.request(url, PackedStringArray(["Cache-Control: no-cache"])) == OK:
		var r: Array = await http.request_completed
		out = {"problem": _http_problem(r[0], r[1]), "body": r[3]}
	http.queue_free()
	return out


static func _http_problem(result: int, code: int) -> String:
	if result == HTTPRequest.RESULT_SUCCESS:
		return "" if code == 200 else "The server said %d" % code
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "Can't reach the server"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "The connection dropped"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Secure connection failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Couldn't write to disk"
		HTTPRequest.RESULT_TIMEOUT:
			return "Timed out"
	return "Download failed (%d)" % result


# --- the launcher itself ---------------------------------------------------
# launcher/manifest.json names the current UI pack and engine. A newer UI pack downloads in
# the background and starts with the next launch (boot.gd loads it). A newer engine needs a
# fresh download from the website, so that only shows a notice.

func platform() -> String:
	return {"Windows": "windows", "macOS": "macos"}.get(OS.get_name(), "linux")


func launcher_download_url() -> String:
	return base + "launcher/TrismegLauncher-%s.zip" % platform()


## The library is on screen, so the UI pack boot.gd loaded (if any) works.
func mark_started() -> void:
	var state: Variant = _read_json(UI_STATE)
	if state is Dictionary and state.get("booting", false):
		state.booting = false
		_write_json(UI_STATE, state)


func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


func _check_launcher() -> void:
	var m: Variant = await _fetch_json("launcher/manifest.json")
	if not m is Dictionary:
		return
	var engine: Dictionary = m.get("engine", {})
	engine_outdated = engine_build != "dev" and _semver_less(engine_build, engine.get("version", "0.0.0"))
	launcher_changed.emit()
	var ui: Dictionary = m.get("ui", {})
	if ui.is_empty() or engine_build == "dev" or OS.has_feature("editor"):
		return  # a dev build runs its own source, never a downloaded UI
	var version: String = ui.get("version", "")
	if version in [ui_version, ui_ready] or _semver_less(engine_build, ui.get("min_engine", "0.0.0")):
		return
	var state: Variant = _read_json(UI_STATE)
	if not state is Dictionary:
		state = {}
	if version in state.get("bad", []):
		return
	DirAccess.make_dir_recursive_absolute(UI_DIR)
	var path := UI_DIR + version + ".pck"
	var r := await _request(base + "launcher/" + ui.file, path + ".part", 300.0)
	var problem: String = r.problem
	if problem.is_empty():
		problem = await _verify(path + ".part", ui)
	if problem:
		DirAccess.remove_absolute(path + ".part")
		push_warning("launcher update %s: %s" % [version, problem])
		return
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path + ".part", path)
	state.previous = state.get("current", "")
	state.current = path
	state.version = version
	state.engine = engine_build
	state.booting = false
	_write_json(UI_STATE, state)
	for f in DirAccess.get_files_at(UI_DIR):
		if not (UI_DIR + f) in [state.current, state.previous]:
			DirAccess.remove_absolute(UI_DIR + f)
	ui_ready = version
	launcher_changed.emit()


static func _build_info() -> Dictionary:
	if not FileAccess.file_exists("res://build_info.json"):
		return {}
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
	return info if info is Dictionary else {}


static func _semver_less(a: String, b: String) -> bool:
	var x := a.trim_prefix("v").split(".")
	var y := b.trim_prefix("v").split(".")
	for i in 3:
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p < q
	return false


# --- disk ------------------------------------------------------------------

func _game(id: String) -> Game:
	if not games.has(id):
		var g := Game.new()
		g.id = id
		g.name = id
		games[id] = g
	return games[id]


func _load() -> void:
	var state: Variant = _read_json(STATE)
	if not state is Dictionary:
		state = {}
	auto_update = state.get("auto_update", false)
	last_check = int(state.get("last_check", 0))
	var index: Variant = _read_json(CACHE + "index.json")
	if index is Dictionary:
		_apply_index(index)
	var saved: Dictionary = state.get("games", {})
	for id: String in saved:
		var s: Dictionary = saved[id]
		var g := _game(id)
		if g.name == id:
			g.name = s.get("name", id)
		g.channel = s.get("channel", "stable")
		g.installed = s.get("installed", {})
		g.previous = s.get("previous", {})
		if not FileAccess.file_exists(g.installed.get("path", "")):
			g.installed = {}
		if not FileAccess.file_exists(g.previous.get("path", "")):
			g.previous = {}
	for g: Game in games.values():
		var m: Variant = _read_json(CACHE + g.id + ".json")
		if m is Dictionary:
			g.manifest = m
		_load_cover(g)


func _save() -> void:
	var out := {}
	for g: Game in games.values():
		out[g.id] = {"name": g.name, "channel": g.channel, "installed": g.installed, "previous": g.previous}
	_write_json(STATE, {"auto_update": auto_update, "last_check": last_check, "games": out})


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path + ".tmp", path)


func _remove_dir(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
