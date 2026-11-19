extends Node

## Drives the real scene router: main menu -> character select -> stage select
## -> arena, then pauses and returns to the menu. Lives under the root so it is
## not freed by the scene changes it causes.

const Harness := preload("res://tests/harness.gd")

var _failures: Array[String] = []
var _checks := 0
var _save_stamp := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_stamp = Harness.normal_save_stamp()
	_ok(SaveData.is_isolated(),
			"flow did not isolate the save (args: %s)" % " ".join(OS.get_cmdline_args()))
	_ok(Harness.save_is_outside_user_dir(), "flow save is inside user://")
	if not _failures.is_empty():
		_report()
		return
	await _frames(3)

	# --- main menu ---------------------------------------------------------
	_ok(_in_scene("res://scenes/ui/main_menu.tscn"), "did not boot on the main menu")
	var focus := get_viewport().gui_get_focus_owner()
	_ok(focus is Button, "main menu had no focused button")
	if focus is Button:
		(focus as Button).pressed.emit()
	await _frames(3)
	_ok(_in_scene("res://scenes/ui/character_select.tscn"),
		"LOCAL VERSUS did not open character select")

	# --- character select (P1 and P2 lock in) ------------------------------
	await _tap("p1_light")
	await _tap("p2_light")
	await _frames(3)
	_ok(_in_scene("res://scenes/ui/stage_select.tscn"),
		"locking both fighters did not open stage select")
	_ok(Game.p1_id != "" and Game.p2_id != "", "character picks were not saved")

	# --- stage select -> arena --------------------------------------------
	await _tap("p1_light")
	await _frames(4)
	_ok(_in_scene("res://scenes/fight/arena.tscn"), "confirming a stage did not open the arena")

	var arena := get_tree().current_scene as Arena
	_ok(arena != null, "arena scene is not an Arena")
	if arena != null:
		_ok(arena.p1 != null and arena.p2 != null, "arena spawned no fighters")
		_ok(arena.p1.char_id == Game.p1_id, "arena P1 does not match the pick")
		_ok(arena.p2.char_id == Game.p2_id, "arena P2 does not match the pick")
		_ok(arena.hud != null, "arena has no HUD")

		# --- pause menu ----------------------------------------------------
		await _key(KEY_ESCAPE, true)
		await _frames(2)
		_ok(get_tree().paused, "pause did not pause the tree")
		_ok(arena.pause_menu.visible, "pause menu did not appear")
		await _key(KEY_ESCAPE, false)
		await _key(KEY_ESCAPE, true)
		await _frames(2)
		await _key(KEY_ESCAPE, false)
		_ok(not get_tree().paused, "second pause press did not resume")
		_ok(not arena.pause_menu.visible, "pause menu stayed visible")

	# --- back to the menu ---------------------------------------------------
	Game.go_main_menu()
	await _frames(4)
	_ok(_in_scene("res://scenes/ui/main_menu.tscn"), "could not return to the main menu")
	_ok(Harness.normal_save_stamp() == _save_stamp, "flow touched the normal save")

	_report()


func _in_scene(path: String) -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == path


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _report() -> void:
	var code := 0
	if _failures.is_empty():
		print("FLOW PASS: %d checks" % _checks)
	else:
		code = 1
		printerr("FLOW FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
	Harness.quiet_quit(self, code)
