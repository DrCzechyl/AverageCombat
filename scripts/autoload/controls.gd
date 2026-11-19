extends Node

## Builds the input map in code so all controls live in one editable place.
## Two players share one keyboard, and up to two gamepads (device 0 = P1,
## device 1 = P2) work at the same time.
##
## P1: A/D move, W jump, S crouch, F light, G heavy, H special, V block
## P2: arrows, numpad 1/2/3 light/heavy/special, numpad 0 block
##     (laptop alt: , . / and ')
## Pads: device 0 is P1, device 1 is P2. A/B/X/Y are light/heavy/special/block.
## Start pauses. Pad A also confirms native Button menus (ui_accept).
## Blocking also works by holding away from the opponent, Mortal Kombat style.

const KEYMAP := {
	"p1": {
		"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"light": [KEY_F], "heavy": [KEY_G], "special": [KEY_H], "block": [KEY_V],
		"confirm": [KEY_ENTER],
	},
	"p2": {
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"light": [KEY_KP_1, KEY_COMMA], "heavy": [KEY_KP_2, KEY_PERIOD],
		"special": [KEY_KP_3, KEY_SLASH], "block": [KEY_KP_0, KEY_APOSTROPHE],
		"confirm": [KEY_KP_ENTER],
	},
}

const PAD_BUTTONS := {
	"light": JOY_BUTTON_A,
	"heavy": JOY_BUTTON_B,
	"special": JOY_BUTTON_X,
	"block": JOY_BUTTON_Y,
}

const PAD_DIRS := {
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
}

const ACTIONS := [
	"left", "right", "up", "down", "light", "heavy", "special", "block", "confirm",
]


func _ready() -> void:
	setup()


func setup() -> void:
	for p in ["p1", "p2"]:
		for action in ACTIONS:
			var name := "%s_%s" % [p, action]
			if InputMap.has_action(name):
				InputMap.erase_action(name)
			InputMap.add_action(name, 0.35)
			for key in KEYMAP[p].get(action, []):
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(name, ev)

	# Gamepad: each pad is bound to one player, so two pads never fight.
	for i in 2:
		var p: String = "p1" if i == 0 else "p2"
		var prefix := "%s_" % p
		for action in ["left", "right", "up", "down"]:
			for btn in PAD_DIRS[action]:
				var ev := InputEventJoypadButton.new()
				ev.device = i
				ev.button_index = btn
				InputMap.action_add_event(prefix + action, ev)
		for action in PAD_BUTTONS:
			var ev2 := InputEventJoypadButton.new()
			ev2.device = i
			ev2.button_index = PAD_BUTTONS[action]
			InputMap.action_add_event(prefix + action, ev2)
		var confirm := InputEventJoypadButton.new()
		confirm.device = i
		confirm.button_index = JOY_BUTTON_START
		InputMap.action_add_event(prefix + "confirm", confirm)

		# left stick
		for axis_dir in [["left", -1.0, JOY_AXIS_LEFT_X], ["right", 1.0, JOY_AXIS_LEFT_X],
				["up", -1.0, JOY_AXIS_LEFT_Y], ["down", 1.0, JOY_AXIS_LEFT_Y]]:
			var motion := InputEventJoypadMotion.new()
			motion.device = i
			motion.axis = axis_dir[2]
			motion.axis_value = axis_dir[1]
			InputMap.action_add_event(prefix + axis_dir[0], motion)

	# Pause + debug
	_ensure_action("pause", [KEY_ESCAPE])
	_ensure_action("debug_hitboxes", [KEY_F1])
	_ensure_action("reset_round", [KEY_F5])
	for i in 2:
		var start := InputEventJoypadButton.new()
		start.device = i
		start.button_index = JOY_BUTTON_START
		InputMap.action_add_event("pause", start)

	# Godot 4.7 ships ui_accept with Enter / Space only. D-pad and stick already
	# move focus, but a pad-only player can never activate a Button. Pad A on
	# every device confirms menus. Combat keeps A as light on device 0 and 1,
	# and Start stays pause plus p1/p2 confirm.
	_ensure_joy_button("ui_accept", JOY_BUTTON_A, -1)


func _ensure_joy_button(action: String, button: JoyButton, device: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton:
			var joy := existing as InputEventJoypadButton
			if joy.button_index == button and joy.device == device:
				return
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _ensure_action(name: String, keys: Array) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(name, ev)
