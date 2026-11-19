extends Node

## Persistent settings + lifetime stats. Saved to user://average_combat.cfg
##
## Headless suites and any other res://tests entry scene redirect this file
## in _init, before load_game(), so a documented `godot res://tests/...`
## invocation cannot read or write the player's save.

const PATH := "user://average_combat.cfg"

var save_path: String = PATH
var _test_dir: DirAccess

const DEFAULT_SETTINGS := {
	"volume": 0.8,
	"difficulty": 2,
	"screen_shake": true,
	"hitstop": true,
	"show_hitboxes": false,
	"fullscreen": false,
}

const DEFAULT_STATS := {
	"matches": 0,
	"wins": 0,
	"best_combo": 0,
	"arcade_clears": 0,
	"damage_dealt": 0.0,
}

const DEFAULT_PICKS := {"p1": "dave", "p2": "karen", "stage": "breakroom"}

var settings: Dictionary = {}
var stats: Dictionary = {}
var last_picks: Dictionary = DEFAULT_PICKS.duplicate()


func _init() -> void:
	if _cmdline_requests_test_isolation():
		save_path = ""
		_test_dir = DirAccess.create_temp("average_combat_test")
		if _test_dir == null:
			push_error("Could not create a temporary save directory for the test scene.")
		else:
			save_path = _test_dir.get_current_dir().path_join(PATH.get_file())


func is_isolated() -> bool:
	return _test_dir != null


func _ready() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	stats = DEFAULT_STATS.duplicate(true)
	load_game()
	apply_settings()


func load_game() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return

	var volume := _read_number(cfg, "settings", "volume", DEFAULT_SETTINGS["volume"])
	settings["volume"] = clampf(volume, 0.0, 1.0)
	var difficulty := _read_number(cfg, "settings", "difficulty", DEFAULT_SETTINGS["difficulty"])
	settings["difficulty"] = int(clampf(difficulty, 1.0, 3.0))
	for key in ["screen_shake", "hitstop", "show_hitboxes", "fullscreen"]:
		var value: Variant = cfg.get_value("settings", key, DEFAULT_SETTINGS[key])
		settings[key] = value if value is bool else DEFAULT_SETTINGS[key]

	for key in ["matches", "wins", "best_combo", "arcade_clears"]:
		var value: Variant = cfg.get_value("stats", key, DEFAULT_STATS[key])
		stats[key] = value if value is int and value >= 0 else DEFAULT_STATS[key]
	var damage := _read_number(cfg, "stats", "damage_dealt", DEFAULT_STATS["damage_dealt"])
	stats["damage_dealt"] = maxf(0.0, damage)

	for key in DEFAULT_PICKS:
		var pick: Variant = cfg.get_value("last", key, DEFAULT_PICKS[key])
		var choices := StageDB.ORDER if key == "stage" else CharacterDB.ORDER
		last_picks[key] = pick if pick is String and pick in choices else DEFAULT_PICKS[key]


func _read_number(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = cfg.get_value(section, key, fallback)
	if value is int or (value is float and is_finite(value)):
		return float(value)
	return fallback


func save_game() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	for key in stats:
		cfg.set_value("stats", key, stats[key])
	for key in last_picks:
		cfg.set_value("last", key, last_picks[key])
	cfg.save(save_path)


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	var vol := clampf(float(settings["volume"]), 0.0, 1.0)
	AudioServer.set_bus_mute(bus, vol <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.001)))
	_apply_fullscreen()


func _apply_fullscreen() -> void:
	var want: bool = settings["fullscreen"]
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want != is_full:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if want else DisplayServer.WINDOW_MODE_WINDOWED
		)


func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	save_game()


func record_match(player_won: bool, best_combo: int, damage: float) -> void:
	stats["matches"] = int(stats["matches"]) + 1
	if player_won:
		stats["wins"] = int(stats["wins"]) + 1
	stats["best_combo"] = maxi(int(stats["best_combo"]), best_combo)
	stats["damage_dealt"] = float(stats["damage_dealt"]) + damage
	save_game()


func record_arcade_clear() -> void:
	stats["arcade_clears"] = int(stats["arcade_clears"]) + 1
	save_game()


func reset_stats() -> void:
	stats = DEFAULT_STATS.duplicate(true)
	save_game()


func discard_isolated_save() -> void:
	if _test_dir != null:
		save_path = ""
		_test_dir = null


func _cmdline_requests_test_isolation() -> bool:
	for arg in OS.get_cmdline_args():
		if _is_test_entry(arg):
			return true
	return false


func _is_test_entry(arg: String) -> bool:
	var path := arg.replace("\\", "/")
	if path.begins_with("--"):
		return false
	if not (path.ends_with(".tscn") or path.ends_with(".scn") or path.ends_with(".gd")):
		return false
	path = ProjectSettings.localize_path(path.simplify_path())
	if path.begins_with("res://tests/") or path.begins_with("tests/"):
		return true
	# An absolute entry can retain a symlink to the project, such as macOS /tmp.
	return path.is_absolute_path() and path.get_base_dir().get_file() == "tests"
