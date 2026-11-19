extends Node

## Entry scene for the mode-rules regression. The observer lives on the root
## so Game.goto() scene changes don't free it. Run with:
##   godot --headless --path . res://tests/arcade.tscn

func _ready() -> void:
	var observer := Node.new()
	observer.name = "ArcadeObserver"
	observer.set_script(load("res://tests/arcade_observer.gd"))
	get_tree().root.add_child.call_deferred(observer)
