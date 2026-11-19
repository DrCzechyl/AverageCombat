extends Node

## Persistent settings + lifetime stats. Saved to user://average_combat.cfg

const PATH := "user://average_combat.cfg"

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


func _ready() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	stats = DEFAULT_STATS.duplicate(true)
	load_game()
	apply_settings()


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
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


func save_game() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	for key in stats:
		cfg.set_value("stats", key, stats[key])
	for key in last_picks:
		cfg.set_value("last", key, last_picks[key])
	cfg.save(PATH)


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
