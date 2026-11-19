extends Node

## Entry scene for the end-to-end flow test. It spawns a controller that lives
## under the scene tree root (so it survives change_scene_to_file) and then
## idles. Fresh checkouts need an import first (see README). Then:
##   godot --headless --path . res://tests/flow.tscn

func _ready() -> void:
	var observer := Node.new()
	observer.name = "FlowObserver"
	observer.set_script(load("res://tests/flow_observer.gd"))
	get_tree().root.add_child.call_deferred(observer)
	get_tree().change_scene_to_file.call_deferred(Game.MAIN_MENU)
