extends Node

## Session/flow state. Screens write their picks here and arena.tscn reads
## match_config when it boots, which keeps the fight scene self-contained.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const CHAR_SELECT := "res://scenes/ui/character_select.tscn"
const STAGE_SELECT := "res://scenes/ui/stage_select.tscn"
const RESULTS := "res://scenes/ui/results.tscn"
const ARENA := "res://scenes/fight/arena.tscn"

const VERSION := "0.1.0"

var mode := "versus"  # "versus" | "arcade" | "training"
var p1_id := "dave"
var p2_id := "karen"
var stage_id := "breakroom"
var p2_is_ai := false
var difficulty := 2

var arcade := {"ladder": [], "index": 0, "cleared": false}
var results: Dictionary = {}
var match_config: Dictionary = {}
var _quitting := false


func _ready() -> void:
	p1_id = SaveData.last_picks.get("p1", "dave")
	p2_id = SaveData.last_picks.get("p2", "karen")
	stage_id = SaveData.last_picks.get("stage", "breakroom")
	difficulty = int(SaveData.settings.get("difficulty", 2))
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(quit)


func goto(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)


func go_main_menu() -> void:
	goto(MAIN_MENU)


func quit() -> void:
	if _quitting:
		return
	_quitting = true
	await Sfx.drain_for_exit()
	get_tree().quit()


# ---------------------------------------------------------------------------
# Flow entry points (called by menu buttons)
# ---------------------------------------------------------------------------


func start_versus() -> void:
	mode = "versus"
	p2_is_ai = false
	goto(CHAR_SELECT)


func start_arcade() -> void:
	mode = "arcade"
	p2_is_ai = true
	difficulty = int(SaveData.settings.get("difficulty", 2))
	arcade = {"ladder": _pick_ladder(p1_id), "index": 0, "cleared": false}
	goto(CHAR_SELECT)


func start_training() -> void:
	mode = "training"
	p2_is_ai = true
	p2_id = CharacterDB.random_other(p1_id)
	goto(CHAR_SELECT)


func _pick_ladder(player_id: String) -> Array:
	var pool: Array = CharacterDB.ORDER.filter(func(c): return c != player_id)
	pool.shuffle()
	return pool


func characters_confirmed(new_p1: String, new_p2: String, versus: bool) -> void:
	p1_id = new_p1
	if versus:
		p2_id = new_p2
	elif mode == "arcade":
		# The ladder is built from the *chosen* fighter, not the previous pick.
		if new_p2 != "" and new_p2 != p1_id and CharacterDB.ROSTER.has(new_p2):
			var rest: Array = CharacterDB.ORDER.filter(func(c): return c != p1_id and c != new_p2)
			rest.shuffle()
			arcade["ladder"] = [new_p2] + rest
		else:
			arcade["ladder"] = _pick_ladder(p1_id)
		arcade["index"] = 0
		arcade["cleared"] = false
		p2_id = arcade["ladder"][0]
	else:
		p2_id = new_p2 if new_p2 != "" else CharacterDB.random_other(p1_id)
	if not versus and p2_id == p1_id:
		p2_id = CharacterDB.random_other(p1_id)
	SaveData.last_picks["p1"] = p1_id
	SaveData.last_picks["p2"] = p2_id
	SaveData.save_game()
	goto(STAGE_SELECT)


func stage_confirmed(new_stage: String) -> void:
	stage_id = new_stage
	SaveData.last_picks["stage"] = stage_id
	SaveData.save_game()
	begin_match()


## Training displays one round and resets both fighters after a KO.
func rounds_to_win(for_mode: String) -> int:
	return 1 if for_mode == "arcade" or for_mode == "training" else 2


func begin_match() -> void:
	if mode == "arcade":
		if int(arcade["index"]) >= arcade["ladder"].size():
			go_main_menu()
			return
		p2_id = arcade["ladder"][arcade["index"]]
		p2_is_ai = true
	difficulty = int(SaveData.settings.get("difficulty", difficulty))
	match_config = {
		"mode": mode,
		"p1": p1_id,
		"p2": p2_id,
		"stage": stage_id,
		"p2_is_ai": p2_is_ai,
		"difficulty": difficulty,
		"round_wins_needed": rounds_to_win(mode),
	}
	results = {}
	goto(ARENA)


func on_match_end(result: Dictionary) -> void:
	results = result
	var winner := int(result.get("winner", -1))
	var p1_won := winner == 0
	var combos: Array = result.get("best_combo", [0, 0])
	var damage: Array = result.get("damage", [0.0, 0.0])
	SaveData.record_match(p1_won, int(combos[0]), float(damage[0]))

	if mode == "arcade" and p1_won:
		arcade["index"] = int(arcade["index"]) + 1
		if int(arcade["index"]) >= arcade["ladder"].size():
			arcade["cleared"] = true
			SaveData.record_arcade_clear()
	goto(RESULTS)


func arcade_continue() -> void:
	if bool(arcade.get("cleared", false)):
		go_main_menu()
		return
	stage_id = StageDB.random_id()
	begin_match()


func rematch() -> void:
	begin_match()


func back_to_characters() -> void:
	goto(CHAR_SELECT)


func next_arcade_opponent_id() -> String:
	var index: int = int(arcade.get("index", 0))
	var ladder: Array = arcade.get("ladder", [])
	if index < ladder.size():
		return ladder[index]
	return ""


func arcade_progress_text() -> String:
	var ladder: Array = arcade.get("ladder", [])
	var index: int = int(arcade.get("index", 0))
	return "%d / %d" % [mini(index + 1, ladder.size()), ladder.size()]
