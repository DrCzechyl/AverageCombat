extends Node

## Drives Game's real scene router. Versus stays first to two, training stays
## endless, and arcade is one round per opponent with advance, retry, and clear.

const Harness := preload("res://tests/harness.gd")

var _failures: Array[String] = []
var _checks := 0
var _save_stamp := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_stamp = Harness.normal_save_stamp()
	_ok(SaveData.is_isolated(),
			"mode suite did not isolate the save (args: %s)" % " ".join(OS.get_cmdline_args()))
	_ok(Harness.save_is_outside_user_dir(), "mode suite save is inside user://")
	if not _failures.is_empty():
		_report()
		return

	await _check_versus()
	await _check_training()
	await _check_arcade()

	_ok(Harness.normal_save_stamp() == _save_stamp, "mode suite touched the normal save")
	_report()


func _check_versus() -> void:
	Game.start_versus()
	Game.characters_confirmed("dave", "karen", true)
	Game.stage_confirmed("breakroom")
	await _frames(4)
	var arena := get_tree().current_scene as Arena
	_ok(arena != null, "versus did not open an arena through Game.begin_match")
	if arena == null:
		return
	_ok(str(arena.cfg.get("mode", "")) == "versus", "versus match has the wrong mode")
	_ok(int(Game.match_config.get("round_wins_needed", -1)) == 2,
			"Game.begin_match did not ask versus for two round wins")
	_ok(arena.round_wins_needed == 2, "versus arena is not first to two")
	_strike(arena, true)
	var guard := 0
	while guard < 3000 and not arena.finished:
		arena._step()
		guard += 1
		if arena.round_number >= 2 and arena.phase == Arena.Phase.FIGHT:
			break
	_ok(not arena.finished, "versus ended after a single round")
	_ok(arena.round_wins[0] == 1, "versus did not award the first round")
	_ok(arena.round_number == 2, "versus did not start round two")


func _check_training() -> void:
	Game.start_training()
	Game.characters_confirmed("tony", "chad", false)
	Game.stage_confirmed("backyard")
	await _frames(4)
	var arena := get_tree().current_scene as Arena
	_ok(arena != null, "training did not open an arena through Game.begin_match")
	if arena == null:
		return
	_ok(arena.training, "training match did not set the endless flag")
	_ok(int(Game.match_config.get("round_wins_needed", -1)) == 1,
			"Game.begin_match did not keep training at one round")
	_ok(arena.round_wins_needed == 1, "training arena requested a multi-round match")
	_strike(arena, true)
	var guard := 0
	while guard < 800:
		arena._step()
		guard += 1
		if guard > 40 and arena.phase == Arena.Phase.FIGHT and arena.p2.health > 50.0:
			break
	_ok(not arena.finished, "training ended the match on a KO")
	_ok(arena.phase == Arena.Phase.FIGHT, "training did not return to fight after the KO")
	_ok(arena.p2.health > 50.0, "training reset did not heal the dummy")


func _check_arcade() -> void:
	Game.p1_id = "dave"
	Game.start_arcade()
	Game.characters_confirmed("dave", "", false)
	var ladder: Array = Game.arcade["ladder"].duplicate()
	_ok(ladder.size() == 3, "arcade ladder should have 3 opponents")
	_ok(not ladder.has("dave"), "arcade ladder should exclude the player")
	_ok(int(Game.arcade["index"]) == 0, "a new arcade run should start at the first opponent")
	Game.stage_confirmed("parkinglot")
	await _frames(4)

	var arena := get_tree().current_scene as Arena
	_ok(arena != null, "arcade did not open an arena through Game.begin_match")
	if arena == null:
		return
	_ok(str(arena.cfg.get("mode", "")) == "arcade", "arcade match has the wrong mode")
	_ok(int(Game.match_config.get("round_wins_needed", -1)) == 1,
			"Game.begin_match did not ask arcade for one round")
	_ok(arena.round_wins_needed == 1, "arcade arena is not one round")
	_ok(arena.p2.char_id == str(ladder[0]), "first arcade opponent does not match the ladder")

	await _win_round(arena)
	_ok(int(Game.results.get("winner", -1)) == 0, "arcade win was not recorded")
	_ok(int(Game.arcade["index"]) == 1, "one arcade win should advance the ladder")
	_ok(not bool(Game.arcade.get("cleared", false)), "one win should not clear the ladder")
	_ok(_in_scene(Game.RESULTS), "arcade win should open the results screen")
	_ok(_press("NEXT OPPONENT"), "arcade win should offer the next opponent")
	await _frames(4)

	arena = get_tree().current_scene as Arena
	_ok(arena != null, "next opponent did not start a match")
	if arena == null:
		return
	_ok(arena.round_wins_needed == 1, "later arcade fights should still be one round")
	_ok(arena.p2.char_id == str(ladder[1]), "second opponent does not match the ladder")
	var index_before := int(Game.arcade["index"])
	await _lose_round(arena)
	_ok(int(Game.arcade["index"]) == index_before, "an arcade loss should not advance the ladder")
	_ok(not bool(Game.arcade.get("cleared", false)), "an arcade loss should not clear the ladder")
	_ok(_press("TRY AGAIN"), "arcade loss should offer a retry")
	await _frames(4)
	_ok(_in_scene(Game.CHAR_SELECT), "retry should return to character select")
	_ok(int(Game.arcade["index"]) == 0, "retry should restart the ladder")
	_ok(not bool(Game.arcade.get("cleared", false)), "retry should clear the cleared flag")

	Game.characters_confirmed("dave", "", false)
	ladder = Game.arcade["ladder"].duplicate()
	_ok(ladder.size() == 3 and not ladder.has("dave"), "retry should build a fresh ladder")
	var clears_before := int(SaveData.stats.get("arcade_clears", 0))
	Game.stage_confirmed("breakroom")
	for i in ladder.size():
		await _frames(4)
		arena = get_tree().current_scene as Arena
		_ok(arena != null, "arcade fight %d did not start" % (i + 1))
		if arena == null:
			return
		_ok(arena.round_wins_needed == 1, "cleared-run fight %d is not one round" % (i + 1))
		_ok(arena.p2.char_id == str(ladder[i]), "cleared-run opponent %d mismatched" % (i + 1))
		await _win_round(arena)
		if i < ladder.size() - 1:
			_ok(not bool(Game.arcade.get("cleared", false)), "ladder cleared before the last opponent")
			_ok(_press("NEXT OPPONENT"), "mid-ladder win should offer the next opponent")
		else:
			_ok(bool(Game.arcade.get("cleared", false)), "beating the ladder should set cleared")
			_ok(int(Game.arcade["index"]) == ladder.size(), "cleared ladder index should sit past the end")
			_ok(int(SaveData.stats.get("arcade_clears", 0)) == clears_before + 1,
					"clearing the ladder should record an arcade clear")
			_ok(_has_button("RUN IT BACK"), "a clear should offer another run")
			Game.arcade_continue()
			await _frames(4)
			_ok(_in_scene(Game.MAIN_MENU), "continuing after a clear should leave the ladder")


func _win_round(arena: Arena) -> void:
	await _finish_round(arena, true)
	_ok(arena.round_wins[0] == 1, "one round should be enough for an arcade win")
	_ok(arena.round_number == 1, "arcade should not start a second round")
	await _frames(4)


func _lose_round(arena: Arena) -> void:
	await _finish_round(arena, false)
	_ok(arena.round_wins[1] == 1, "one round should be enough for an arcade loss")
	_ok(arena.round_number == 1, "a lost arcade fight started a second round")
	await _frames(4)


func _finish_round(arena: Arena, victim_is_p2: bool) -> void:
	_strike(arena, victim_is_p2)
	var guard := 0
	while not arena.finished and guard < 3000:
		arena._step()
		guard += 1
	_ok(arena.finished, "arcade match did not finish after one round (%d steps)" % guard)


func _strike(arena: Arena, victim_is_p2: bool) -> void:
	arena.ai = null
	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	var attacker: Fighter = arena.p1 if victim_is_p2 else arena.p2
	var victim: Fighter = arena.p2 if victim_is_p2 else arena.p1
	attacker.pos = Vector2(600, CharacterDB.GROUND_Y)
	victim.pos = Vector2(700, CharacterDB.GROUND_Y)
	attacker.position = attacker.pos
	victim.position = victim.pos
	attacker.vel = Vector2.ZERO
	victim.vel = Vector2.ZERO
	victim.health = 1.0
	victim.knockout = false
	victim.blocking = false
	victim.crouching = false
	victim.invuln = 0
	victim.state = Fighter.State.IDLE
	attacker.state = Fighter.State.IDLE
	attacker.start_move("jab")


func _press(label: String) -> bool:
	var button := _find_button(label)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _has_button(label: String) -> bool:
	return _find_button(label) != null


func _find_button(label: String) -> Button:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("", "Button", true, false):
		if node is Button and (node as Button).text == label:
			return node as Button
	return null


func _in_scene(path: String) -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == path


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _report() -> void:
	var code := 0
	if _failures.is_empty():
		print("MODES PASS: %d checks" % _checks)
	else:
		code = 1
		printerr("MODES FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
	Harness.quiet_quit(self, code)
