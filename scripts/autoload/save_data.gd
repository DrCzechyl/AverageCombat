extends Node

## Persistent settings + lifetime stats. Saved to user://average_combat.cfg
##
## Headless suites and any other res://tests entry scene redirect this file
## in _init, before load_game(), so a documented `godot res://tests/...`
## invocation cannot read or write the player's save.

const PATH := "user://average_combat.cfg"

## Active file. Tests replace this with an absolute temp path before _ready.
var save_path: String = PATH

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

var settings: Dictionary = {}
var stats: Dictionary = {}
var last_picks: Dictionary = {"p1": "dave", "p2": "karen", "stage": "breakroom"}


func _init() -> void:
	if _cmdline_requests_test_isolation():
		save_path = _isolated_save_path()


func is_isolated() -> bool:
	return save_path != PATH


func _ready() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	stats = DEFAULT_STATS.duplicate(true)
	load_game()
	apply_settings()


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	for key in settings.keys():
		settings[key] = cfg.get_value("settings", key, settings[key])
	for key in stats.keys():
		stats[key] = cfg.get_value("stats", key, stats[key])
	for key in last_picks.keys():
		last_picks[key] = cfg.get_value("last", key, last_picks[key])
	# Clamp anything a hand-edited config might have broken.
	settings["volume"] = clampf(float(settings["volume"]), 0.0, 1.0)
	settings["difficulty"] = clampi(int(settings["difficulty"]), 1, 3)
	for key in ["screen_shake", "hitstop", "show_hitboxes", "fullscreen"]:
		if not (settings[key] is bool):
			settings[key] = DEFAULT_SETTINGS[key]
	if last_picks["p1"] not in CharacterDB.ORDER:
		last_picks["p1"] = "dave"
	if last_picks["p2"] not in CharacterDB.ORDER:
		last_picks["p2"] = "karen"
	if last_picks["stage"] not in StageDB.ORDER:
		last_picks["stage"] = "breakroom"


func save_game() -> void:
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
	if save_path == PATH:
		return
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


func _cmdline_requests_test_isolation() -> bool:
	var groups: Array = [OS.get_cmdline_args(), OS.get_cmdline_user_args()]
	for group in groups:
		var args: PackedStringArray = group
		for i in args.size():
			var arg := str(args[i])
			if arg == "--scene" or arg == "--script":
				if i + 1 < args.size() and _is_test_entry(str(args[i + 1])):
					return true
				continue
			if _is_test_entry(arg):
				return true
	return false


func _is_test_entry(arg: String) -> bool:
	var path := arg.replace("\\", "/")
	if path.begins_with("--"):
		return false
	if not (path.ends_with(".tscn") or path.ends_with(".scn") or path.ends_with(".gd")):
		return false
	if path.begins_with("res://tests/") or path.begins_with("tests/"):
		return true
	var marker := "/tests/"
	var at := path.rfind(marker)
	if at == -1:
		return false
	var rest := path.substr(at + marker.length())
	return rest != "" and not rest.contains("/")


func _isolated_save_path() -> String:
	# Outside user://. A unique file so overlapping suite processes don't clobber
	# each other, and a failure to mkdir never falls back to the real save.
	var dir := OS.get_temp_dir().path_join("average_combat_tests")
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return OS.get_temp_dir().path_join("average_combat_%d.cfg" % OS.get_process_id())
	return dir.path_join("average_combat_%d.cfg" % OS.get_process_id())
