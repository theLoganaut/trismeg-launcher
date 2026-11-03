extends Node
## The launcher ships in two layers: a thin engine exe that rarely changes, and the UI
## (src/ui, src/library.gd, src/fmt.gd and the assets) as a .pck that updates itself the
## way games do. Library downloads a newer UI pack into user://launcher/ui/ and records it
## in ui.json; this loads it over the UI built into the exe.
##
## A pack that never gets as far as showing the library (Library.mark_started) is marked
## bad on the next start, which then falls back to the UI built into the exe.
##
## This file ships inside the exe, so a UI pack can't change it. A UI pack also can't add
## class_name scripts (the exe's list of global classes is fixed); preload new ones.

const STATE := "user://launcher/ui.json"
const MAIN := "res://src/ui/main.tscn"


func _ready() -> void:
	if not OS.has_feature("editor"):
		_load_ui_pack()
	get_tree().change_scene_to_file.call_deferred(MAIN)


func _load_ui_pack() -> void:
	if not FileAccess.file_exists(STATE):
		return
	var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE))
	if not state is Dictionary or not state.get("current", ""):
		return
	if state.get("engine", "") != ProjectSettings.get_setting("trismeg/engine_version", ""):
		return  # downloaded by an older exe; this one's built-in UI is at least as new
	if state.get("booting", false):
		push_warning("UI pack %s didn't start last time; using the built-in UI" % state.get("version", "?"))
		var bad: Array = state.get("bad", [])
		bad.append(state.get("version", ""))
		state.bad = bad
		state.current = ""
		state.booting = false
	elif FileAccess.file_exists(state.current) and ProjectSettings.load_resource_pack(state.current):
		state.booting = true
	else:
		return
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state, "\t"))
