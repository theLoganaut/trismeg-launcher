extends Node
## The launcher ships in two layers: a thin engine exe that rarely changes, and the UI
## (everything under src/ui and src/library.gd) as a .pck that updates itself like a game
## does (step 3.7). If a newer UI pack has been downloaded, it replaces the one built in.

const UI_PACK := "user://launcher/ui.pck"
const MAIN := "res://src/ui/main.tscn"


func _ready() -> void:
	if FileAccess.file_exists(UI_PACK) and not OS.has_feature("editor"):
		if not ProjectSettings.load_resource_pack(UI_PACK):
			push_warning("couldn't load %s; using the built-in UI" % UI_PACK)
	get_tree().change_scene_to_file.call_deferred(MAIN)
