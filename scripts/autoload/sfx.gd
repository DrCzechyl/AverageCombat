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
	"armor": "res://assets/audio/armor.wav",
	"throw": "res://assets/audio/throw.wav",
	"tech": "res://assets/audio/tech.wav",
}

const AMBIENCE := {
	"ambience_breakroom": "res://assets/audio/ambience_breakroom.wav",
	"ambience_parkinglot": "res://assets/audio/ambience_parkinglot.wav",
	"ambience_backyard": "res://assets/audio/ambience_backyard.wav",
}

const POOL_SIZE := 12

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _ambience_player: AudioStreamPlayer
var _ambience_streams: Dictionary = {}
var _next := 0
var _released := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		var path: String = SOUNDS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for key in AMBIENCE:
		var path: String = AMBIENCE[key]
		if ResourceLoader.exists(path):
			var loaded: Resource = load(path)
			if loaded is AudioStreamWAV:
				var wav := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
				var channels := 2 if wav.stereo else 1
				var frame_bytes := bytes_per_sample * channels
				wav.loop_end = floori(float(wav.data.size()) / float(frame_bytes)) if frame_bytes > 0 else 0
				_ambience_streams[key] = wav
			elif loaded is AudioStream:
				_ambience_streams[key] = loaded
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = "Master"
	add_child(_ambience_player)


func play(name: String, volume_db := 0.0, pitch := 1.0, pitch_variance := 0.06) -> void:
	if _released or _players.is_empty() or not _streams.has(name):
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[name]
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_variance, pitch_variance))
	player.play()


func play_ambience(name: String, volume_db := -16.0) -> void:
	if _released or not is_instance_valid(_ambience_player):
		return
	if not _ambience_streams.has(name):
		stop_ambience()
		return
	var stream: AudioStream = _ambience_streams[name]
	if _ambience_player.playing and _ambience_player.stream == stream:
		_ambience_player.volume_db = volume_db
		return
	_ambience_player.stop()
	_ambience_player.stream = stream
	_ambience_player.volume_db = volume_db
	_ambience_player.play()


func stop_ambience() -> void:
	if is_instance_valid(_ambience_player):
		_ambience_player.stop()


## Stop pooled players but keep their streams until the audio thread mixes.
## Nulling or freeing a WAV in the same tick orphans AudioStreamPlaybackWAV.
func release_for_exit() -> void:
	if _released:
		return
	_released = true
	for player in _players:
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(_ambience_player):
		_ambience_player.stop()


func finish_release() -> void:
	for player in _players:
		if not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null
		player.free()
	_players.clear()
	_streams.clear()
	if is_instance_valid(_ambience_player):
		_ambience_player.stop()
		_ambience_player.stream = null
		_ambience_player.free()
	_ambience_player = null
	_ambience_streams.clear()


func drain_for_exit() -> void:
	release_for_exit()
	# Let the audio thread finish with the stopped playbacks before freeing them.
	await get_tree().create_timer(0.15, true, false, true).timeout
	finish_release()
	await get_tree().create_timer(0.05, true, false, true).timeout


func _exit_tree() -> void:
	if _released:
		return
	for player in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_streams.clear()
	if is_instance_valid(_ambience_player):
		_ambience_player.stop()
		_ambience_player.stream = null
	_ambience_player = null
	_ambience_streams.clear()


func play_ui(name: String) -> void:
	match name:
		"move":
			play("menu_move", -6.0, 1.0, 0.0)
		"confirm":
			play("menu_confirm", -8.0, 1.0, 0.0)
		"back":
			play("menu_back", -8.0, 1.0, 0.0)
