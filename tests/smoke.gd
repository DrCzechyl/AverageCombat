extends Node

## Headless smoke test. Run with:
##   godot --headless res://tests/smoke.tscn
##
## It instantiates every screen and drives the simulation directly (no input, no
## real time) so regressions in parsing, scene wiring or combat math show up in
## CI instead of at the couch.

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	_report()


func _run() -> void:
	_check_databases()
	await _check_melee()
	await _check_projectile()
	await _check_training_reset()
	await _check_time_over()
	await _check_ai_match()
	await _check_menus()
	_check_save_roundtrip()


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _check_databases() -> void:
	for path in [Game.MAIN_MENU, Game.CHAR_SELECT, Game.STAGE_SELECT,
			Game.RESULTS, Game.ARENA]:
		_ok(ResourceLoader.exists(path), "scene is missing: %s" % path)

	var ladder: Array = Game._pick_ladder("dave")
	_ok(ladder.size() == 3, "arcade ladder should have 3 opponents")
	_ok(not ladder.has("dave"), "arcade ladder should exclude the player")

	_ok(CharacterDB.ORDER.size() == 4, "roster should have 4 fighters")
	for id in CharacterDB.ORDER:
		var data := CharacterDB.get_character(id)
		_ok(str(data.get("name", "")) != "", "%s is missing a name" % id)
		_ok(str(data.get("sheet", "")) != "" and ResourceLoader.exists(data["sheet"]),
			"%s sprite sheet is missing" % id)
		for move_name in ["jab", "heavy", "low", "sweep", "air", "special"]:
			_ok(data["moves"].has(move_name), "%s is missing move %s" % [id, move_name])
		_ok(ResourceLoader.exists(load(data["sheet"]).resource_path), "%s sheet unloadable" % id)

	_ok(StageDB.ORDER.size() == 3, "there should be 3 stages")
	for id in StageDB.ORDER:
		var stage := StageDB.get_stage(id)
		_ok(ResourceLoader.exists(stage["bg"]), "%s background is missing" % id)
		_ok(stage["start"].x < stage["start"].y, "%s start positions are malformed" % id)
		_ok(ResourceLoader.exists("res://assets/audio/hit_light.wav"), "hit sfx missing")


func _make_arena(p1_id: String, p2_id: String, mode := "versus") -> Arena:
	Game.match_config = {
		"mode": mode, "p1": p1_id, "p2": p2_id, "stage": "breakroom",
		"p2_is_ai": false, "difficulty": 2,
		"round_wins_needed": 1 if mode == "training" else 2,
	}
	var arena: Arena = load("res://scenes/fight/arena.tscn").instantiate()
	arena.auto_report = false
	add_child(arena)
	await get_tree().process_frame
	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	return arena


func _check_melee() -> void:
	var arena := await _make_arena("dave", "karen")
	_ok(arena.p1 != null and arena.p2 != null, "arena failed to spawn fighters")
	_ok(arena.p1.char_id == "dave", "p1 has the wrong fighter")
	_ok(arena.p2.char_id == "karen", "p2 has the wrong fighter")
	_ok(is_equal_approx(arena.p1.pos.y, CharacterDB.GROUND_Y), "p1 is not on the ground")
	_ok(arena.hud.arena == arena, "hud is not wired to the arena")

	var start_health: float = arena.p2.health
	arena.p1.pos = Vector2(600, CharacterDB.GROUND_Y)
	arena.p2.pos = Vector2(700, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p2.position = arena.p2.pos
	arena.p1.start_move("jab")
	for i in 20:
		arena._step()
	_ok(arena.p2.health < start_health, "jab did not damage the opponent")
	_ok(arena.p1.meter > 0.0, "landing a hit did not build meter")

	# Blocking should cut damage to chip. Input is blank in this harness, so the
	# block is applied directly to the damage pipeline.
	var info: Dictionary = arena.p1.data["moves"]["heavy"].duplicate(true)
	var hp_before: float = arena.p2.health
	var blocked_result: Dictionary = arena.p2.take_hit(info, true, 1, 1.0)
	var chip: float = hp_before - arena.p2.health
	_ok(bool(blocked_result["blocked"]), "hit was not flagged as blocked")
	_ok(chip > 0.0, "blocked heavy did no chip damage")
	_ok(chip < 30.0, "block did not reduce damage (chip was %.1f)" % chip)
	arena.p2.blocking = true
	_ok(arena.p2.is_guarding("mid"), "standing guard should stop mid attacks")
	_ok(not arena.p2.is_guarding("low"), "standing guard should not stop lows")
	arena.p2.crouching = true
	_ok(arena.p2.is_guarding("low"), "crouch guard should stop lows")
	_ok(not arena.p2.is_guarding("high"), "crouch guard should not stop highs")
	arena.p2.crouching = false
	arena.p2.blocking = false
	arena.p2.state = Fighter.State.IDLE
	arena.p2.stun_ticks = 0

	# KO should advance the round and award it to the attacker.
	arena.p2.health = 1.0
	arena.p2.blocking = false
	arena.p2.pos = Vector2(700, CharacterDB.GROUND_Y)
	arena.p2.position = arena.p2.pos
	arena.p1.pos = Vector2(600, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p1.start_move("heavy")
	for i in 40:
		arena._step()
	_ok(arena.p2.knockout, "lethal hit did not KO the defender")
	for i in 220:
		arena._step()
		if arena.round_wins[0] == 1:
			break
	_ok(arena.round_wins[0] == 1, "round win was not recorded")

	for i in 180:
		arena._step()
	_ok(arena.round_number == 2, "the second round did not start")
	_ok(is_equal_approx(arena.p1.health, float(arena.p1.data["build"]["health"])),
		"p1 health did not refill for round two")
	_ok(is_equal_approx(arena.p2.health, float(arena.p2.data["build"]["health"])),
		"p2 health did not refill for round two")

	arena.pause_menu.open()
	_ok(get_tree().paused, "pause menu did not pause the tree")
	arena.pause_menu.close()
	_ok(not get_tree().paused, "closing the pause menu did not resume")
	arena.set_hitboxes_visible(true)
	_ok(arena.p1.debug_boxes and arena.p2.debug_boxes, "hitbox overlay did not toggle")

	arena.queue_free()
	await get_tree().process_frame


func _check_time_over() -> void:
	var arena := await _make_arena("dave", "karen")
	arena.time_accum = 0.99
	arena.round_time = 0.5
	arena._step()
	_ok(arena.phase == Arena.Phase.KO, "time over did not end the round")
	_ok(arena.announce_text == "TIME", "time over did not announce TIME")
	arena.queue_free()
	await get_tree().process_frame


func _check_projectile() -> void:
	var arena := await _make_arena("karen", "dave")
	arena.p1.meter = CharacterDB.METER_MAX
	arena.p1.pos = Vector2(360, CharacterDB.GROUND_Y)
	arena.p2.pos = Vector2(860, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p2.position = arena.p2.pos
	arena.p1.start_move("special")
	var spawned := false
	var hp_before: float = arena.p2.health
	for i in 90:
		arena._step()
		if not arena.projectiles.is_empty():
			spawned = true
	_ok(spawned, "Karen's special never spawned a projectile")
	_ok(arena.p2.health < hp_before, "projectile did not damage the opponent")
	_ok(arena.p1.meter < CharacterDB.METER_MAX, "special did not spend meter")
	arena.queue_free()
	await get_tree().process_frame


func _check_training_reset() -> void:
	var arena := await _make_arena("tony", "chad", "training")
	_ok(arena.round_wins_needed == 1, "training should only need one round")
	_ok(arena.training, "training mode flag is off")
	arena.p2.health = 1.0
	arena.p2.pos = Vector2(760, CharacterDB.GROUND_Y)
	arena.p2.position = arena.p2.pos
	arena.p1.pos = Vector2(660, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p1.start_move("jab")
	for i in 200:
		arena._step()
	_ok(arena.phase == Arena.Phase.FIGHT, "training did not reset after the KO")
	_ok(arena.p2.health > 1.0, "training reset did not heal the dummy")
	arena.queue_free()
	await get_tree().process_frame


func _check_ai_match() -> void:
	Game.match_config = {
		"mode": "versus", "p1": "chad", "p2": "tony", "stage": "backyard",
		"p2_is_ai": true, "difficulty": 3, "round_wins_needed": 2,
	}
	var arena: Arena = load("res://scenes/fight/arena.tscn").instantiate()
	arena.auto_report = false
	add_child(arena)
	await get_tree().process_frame
	_ok(arena.ai != null, "AI opponent was not created")

	var ticks := 0
	while not arena.finished and ticks < 16000:
		arena._step()
		ticks += 1
	_ok(arena.finished, "AI match never finished (ran %d ticks)" % ticks)
	_ok(arena.p1.health <= float(arena.p1.data["build"]["health"]),
		"p1 health exceeded its maximum")
	_ok(arena.p2.health <= float(arena.p2.data["build"]["health"]),
		"p2 health exceeded its maximum")
	_ok(arena.round_wins[0] + arena.round_wins[1] > 0, "no rounds were awarded")
	arena.queue_free()
	await get_tree().process_frame


func _check_menus() -> void:
	Game.mode = "versus"
	Game.p1_id = "dave"
	Game.p2_id = "karen"
	Game.stage_id = "breakroom"
	Game.results = {
		"mode": "versus", "p1": "dave", "p2": "karen", "stage": "breakroom",
		"winner": 0, "wins": [2, 1], "best_combo": [3, 2],
		"damage": [840.0, 610.0], "rounds": 3, "duration": 71.4,
	}

	for path in [
		"res://scenes/ui/main_menu.tscn",
		"res://scenes/ui/character_select.tscn",
		"res://scenes/ui/stage_select.tscn",
		"res://scenes/ui/options.tscn",
		"res://scenes/ui/results.tscn",
	]:
		var packed: PackedScene = load(path)
		_ok(packed != null, "could not load %s" % path)
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		_ok(scene.get_child_count() > 0, "%s built no UI" % path)
		scene.queue_free()
		await get_tree().process_frame


func _check_save_roundtrip() -> void:
	SaveData.settings["volume"] = 0.55
	SaveData.save_game()
	SaveData.settings["volume"] = 0.8
	SaveData.load_game()
	_ok(is_equal_approx(float(SaveData.settings["volume"]), 0.55), "settings did not persist")
	SaveData.settings["volume"] = 0.8
	SaveData.save_game()


func _report() -> void:
	if _failures.is_empty():
		print("SMOKE PASS: %d checks" % _checks)
		get_tree().quit(0)
	else:
		printerr("SMOKE FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
		get_tree().quit(1)
