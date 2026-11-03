extends SceneTree
## Drives Library against the live bucket: refresh, install the smallest game, check its
## status, and launch it. Run with:
##   godot --headless --path . -s tools/smoke_test.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lib := Library.new()
	root.add_child(lib)
	while lib.refreshing:
		await process_frame
	print("online=", lib.online, " games=", lib.games.keys())
	for g in lib.ordered():
		print("  %s  status=%s  latest=%s  channel=%s  blocked='%s'" % [g.id, Library.Status.keys()[lib.status(g)], lib.latest(g).get("version", "-"), lib.channel_of(g), lib.blocked_reason(g)])
	var id := "outer-rim-racers"
	lib.install(id)
	while lib.games[id].task:
		await process_frame
	var g: Library.Game = lib.games[id]
	print("after install: status=%s error='%s' installed=%s" % [Library.Status.keys()[lib.status(g)], g.error, g.installed.get("version")])
	lib.play(id)
	print("launched pid=", g.pid)
	await create_timer(3.0).timeout
	print("running after 3s: ", OS.is_process_running(g.pid))
	if g.pid:
		OS.kill(g.pid)
	quit()
