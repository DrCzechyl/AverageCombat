class_name InputRouter
extends RefCounted

## Turns raw input into per-tick frames. Latches presses between playable ticks
## and samples held directions when a fighter consumes the frame.
##
## This is the seam where online play will eventually plug in: replace
## get_frame() with frames received from the netcode and nothing else changes.

const EDGE_ACTIONS := ["up", "light", "heavy", "special"]

var _press: Array = [{}, {}]
var _ignore_through: Array = [{}, {}]


func poll() -> void:
	var tick := Engine.get_physics_frames()
	for i in 2:
		var prefix := "p%d_" % (i + 1)
		for action in EDGE_ACTIONS:
			if tick > int(_ignore_through[i].get(action, -1)) \
					and Input.is_action_just_pressed(prefix + action):
				_press[i][action] = true


func consume_menu_press(event: InputEvent) -> void:
	# GUI consumption does not affect Input polling. The pause event can also
	# be reported as a fresh combat press on the next physics tick.
	var through := Engine.get_physics_frames() + 1
	for i in 2:
		var prefix := "p%d_" % (i + 1)
		for action in EDGE_ACTIONS:
			if event.is_action_pressed(prefix + action):
				_press[i].erase(action)
				_ignore_through[i][action] = through


## Drops latched attack and jump edges. The arena calls this outside FIGHT and
## on round resets so a tap that already ended cannot fire on a later tick.
func discard() -> void:
	for i in 2:
		_press[i].clear()


func get_frame(i: int) -> Dictionary:
	var prefix := "p%d_" % (i + 1)
	var left := Input.is_action_pressed(prefix + "left")
	var right := Input.is_action_pressed(prefix + "right")
	var dir := 0
	if left and not right:
		dir = -1
	elif right and not left:
		dir = 1
	var frame := {
		"dir": dir,
		"jump": _take(i, "up"),
		"crouch": Input.is_action_pressed(prefix + "down"),
		"light": _take(i, "light"),
		"heavy": _take(i, "heavy"),
		"special": _take(i, "special"),
		"block": Input.is_action_pressed(prefix + "block"),
	}
	return frame


func _take(i: int, action: String) -> bool:
	if _press[i].has(action) and bool(_press[i][action]):
		_press[i].erase(action)
		return true
	return false


static func blank() -> Dictionary:
	return {
		"dir": 0, "jump": false, "crouch": false,
		"light": false, "heavy": false, "special": false, "block": false,
	}
