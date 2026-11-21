class_name StageDB
extends RefCounted

## Stage metadata. All backgrounds are 1280x720 with the floor line at y=600.

const STAGES := {
	"breakroom": {
		"name": "THE BREAK ROOM",
		"subtitle": "FLOOR 3 - 4:59 PM",
		"bg": "res://assets/stages/breakroom.png",
		"ambience": "ambience_breakroom",
		"accent": Color("8fb8c9"),
		"start": Vector2(440, 840),
		"bounds": Vector2(200, 1080),
	},
	"parkinglot": {
		"name": "THE PARKING LOT",
		"subtitle": "AVERAGE MART - DUSK",
		"bg": "res://assets/stages/parkinglot.png",
		"ambience": "ambience_parkinglot",
		"accent": Color("e08a5a"),
		"start": Vector2(440, 840),
		"bounds": Vector2(200, 1080),
	},
	"backyard": {
		"name": "THE BACKYARD",
		"subtitle": "SATURDAY - SOMEONE'S BBQ",
		"bg": "res://assets/stages/backyard.png",
		"ambience": "ambience_backyard",
		"accent": Color("7fb07a"),
		"start": Vector2(440, 840),
		"bounds": Vector2(220, 1060),
	},
}

const ORDER := ["breakroom", "parkinglot", "backyard"]


static func get_stage(id: String) -> Dictionary:
	var stage: Dictionary = STAGES.get(id, STAGES["breakroom"]).duplicate(true)
	stage["id"] = id if STAGES.has(id) else "breakroom"
	return stage


static func random_id() -> String:
	return ORDER[randi() % ORDER.size()]
