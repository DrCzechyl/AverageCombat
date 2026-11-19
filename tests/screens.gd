extends Node

## Screenshot harness: boots each screen, waits for it to draw, writes a PNG to
## screenshots/. Run windowed (not --headless):
##   godot res://tests/screens.tscn

const OUT := "res://screenshots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Game.mode = "versus"
	Game.p1_id = "dave"
	Game.p2_id = "karen"
	Game.stage_id = "breakroom"
	SaveData.stats["matches"] = 12
	SaveData.stats["wins"] = 7
	SaveData.stats["arcade_clears"] = 1

	await _shot("main_menu", "res://scenes/ui/main_menu.tscn")
	await _shot("character_select", "res://scenes/ui/character_select.tscn")
	await _shot("stage_select", "res://scenes/ui/stage_select.tscn")
	await _shot("options", "res://scenes/ui/options.tscn")

	Game.results = {
		"mode": "versus", "p1": "dave", "p2": "karen", "stage": "breakroom",
		"winner": 0, "wins": [2, 1], "best_combo": [4, 2],
		"damage": [1840.0, 1210.0], "rounds": 3, "duration": 96.0,
	}
	await _shot("results", "res://scenes/ui/results.tscn")
	await _fight_shots()

	print("SCREENSHOTS DONE")
	get_tree().quit(0)


func _shot(name: String, path: String) -> void:
	var scene: Node = load(path).instantiate()
	add_child(scene)
	await _wait(12)
	await _save(name)
	scene.queue_free()
	await _wait(3)


func _fight_shots() -> void:
	Game.match_config = {
		"mode": "versus", "p1": "dave", "p2": "karen", "stage": "breakroom",
		"p2_is_ai": false, "difficulty": 2, "round_wins_needed": 2,
	}
	var arena: Arena = load("res://scenes/fight/arena.tscn").instantiate()
	arena.auto_report = false
	add_child(arena)
	await _wait(4)

	arena.phase = Arena.Phase.INTRO
	arena.phase_ticks = 200
	for i in 130:
		arena._step()
	await _wait(4)
	await _save("fight_intro")

	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	arena.p1.pos = Vector2(600, CharacterDB.GROUND_Y)
	arena.p2.pos = Vector2(706, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p2.position = arena.p2.pos
	arena.p1.facing = 1
	arena.p2.facing = -1
	arena.p1.meter = 74.0
	arena.p2.meter = 38.0
	arena.p1.start_move("heavy")
	for i in 14:
		arena._step()
	arena.hud._process(0.016)
	await _wait(3)
	await _save("fight_hit")

	# Crouching low attack (sprite row 11).
	arena.p1.crouching = true
	arena.p1.start_move("low")
	for i in 9:
		arena._step()
	arena.hud._process(0.016)
	await _wait(3)
	await _save("fight_low")
	arena.p1.crouching = false

	arena.p2.health = 40.0
	arena.p2.knockout = false
	arena.p2.state = Fighter.State.IDLE
	arena.p2.stun_ticks = 0
	arena.p2.pos = Vector2(700, CharacterDB.GROUND_Y)
	arena.p2.position = arena.p2.pos
	arena.p2.facing = -1
	arena.p1.pos = Vector2(600, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p1.start_move("heavy")
	for i in 24:
		arena._step()
	arena.hud._process(0.016)
	await _wait(3)
	await _save("fight_ko")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT, name])


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
