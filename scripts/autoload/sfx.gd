extends Node

## Small pooled SFX player. Call Sfx.play("hit_heavy") from anywhere.

const SOUNDS := {
	"hit_light": "res://assets/audio/hit_light.wav",
	"hit_heavy": "res://assets/audio/hit_heavy.wav",
	"block": "res://assets/audio/block.wav",
	"swing": "res://assets/audio/swing.wav",
	"ko": "res://assets/audio/ko.wav",
	"round_start": "res://assets/audio/round_start.wav",
	"bell": "res://assets/audio/bell.wav",
	"projectile": "res://assets/audio/projectile.wav",
	"land": "res://assets/audio/land.wav",
	"menu_move": "res://assets/audio/menu_move.wav",
	"menu_confirm": "res://assets/audio/menu_confirm.wav",
	"menu_back": "res://assets/audio/menu_back.wav",
}

const POOL_SIZE := 12
const SILENT := ["swing"]  # can be toggled off in options later

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next := 0
var _released := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		var path: String = SOUNDS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func play(name: String, volume_db := 0.0, pitch := 1.0, pitch_variance := 0.06) -> void:
	if _released or _players.is_empty() or not _streams.has(name):
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[name]
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_variance, pitch_variance))
	player.play()


## Stop pooled players but keep their streams until the audio thread mixes.
## Nulling or freeing a WAV in the same tick orphans AudioStreamPlaybackWAV.
func release_for_exit() -> void:
	if _released:
		return
	_released = true
	for player in _players:
		if is_instance_valid(player):
			player.stop()


func finish_release() -> void:
	for player in _players:
		if not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null
		player.free()
	_players.clear()
	_streams.clear()


func _exit_tree() -> void:
	if _released:
		return
	for player in _players:
		if is_instance_valid(player):
			player.stop()
	_streams.clear()


func play_ui(name: String) -> void:
	match name:
		"move":
			play("menu_move", -6.0, 1.0, 0.0)
		"confirm":
			play("menu_confirm", -8.0, 1.0, 0.0)
		"back":
			play("menu_back", -8.0, 1.0, 0.0)
