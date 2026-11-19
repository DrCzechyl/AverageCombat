extends Node

## Regressions for menu confirm, intro input, and Karen's clipboard.
##   godot --headless --path . res://tests/review_fixes.tscn

const Harness := preload("res://tests/harness.gd")

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	if not bool(get_meta("drive", false)):
		var driver := Node.new()
		driver.name = "ReviewDriver"
		driver.process_mode = Node.PROCESS_MODE_ALWAYS
		driver.set_script(load("res://tests/review_fixes.gd"))
		driver.set_meta("drive", true)
		get_tree().root.add_child.call_deferred(driver)
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	_ok(SaveData.is_isolated(), "controller suite could not isolate the save")
	if not _failures.is_empty():
		_report()
		return
	await _frames(1)
	await _run()
	_report()


func _run() -> void:
	_check_bindings()
	await _check_menus()
	await _release_all()
	get_tree().paused = false
	await _goto_blank()
	await _check_intro_edges()
	await _check_reset_edges()
	await _check_clipboard()


func _check_bindings() -> void:
	_ok(_has_key("p1_left", KEY_A) and _has_key("p1_right", KEY_D), "P1 move keys changed")
	_ok(_has_key("p1_up", KEY_W) and _has_key("p1_down", KEY_S), "P1 vertical keys changed")
	_ok(_has_key("p1_light", KEY_F) and _has_key("p1_heavy", KEY_G), "P1 attack keys changed")
	_ok(_has_key("p1_special", KEY_H) and _has_key("p1_block", KEY_V), "P1 special/block keys changed")
	_ok(_has_key("p1_confirm", KEY_ENTER), "P1 confirm key changed")
	_ok(_has_key("p2_left", KEY_LEFT) and _has_key("p2_up", KEY_UP), "P2 move keys changed")
	_ok(_has_key("p2_light", KEY_KP_1) and _has_key("p2_light", KEY_COMMA), "P2 light keys changed")
	_ok(_has_key("p2_heavy", KEY_KP_2) and _has_key("p2_special", KEY_KP_3), "P2 heavy/special keys changed")
	_ok(_has_key("p2_block", KEY_KP_0) and _has_key("p2_block", KEY_APOSTROPHE), "P2 block keys changed")
	_ok(_has_joy("p1_light", JOY_BUTTON_A, 0), "P1 pad A is no longer light")
	_ok(_has_joy("p1_heavy", JOY_BUTTON_B, 0), "P1 pad B is no longer heavy")
	_ok(_has_joy("p1_special", JOY_BUTTON_X, 0), "P1 pad X is no longer special")
	_ok(_has_joy("p1_block", JOY_BUTTON_Y, 0), "P1 pad Y is no longer block")
	_ok(_has_joy("p2_light", JOY_BUTTON_A, 1), "P2 pad A is no longer light")
	_ok(_has_joy("p2_heavy", JOY_BUTTON_B, 1) and _has_joy("p2_special", JOY_BUTTON_X, 1),
			"P2 pad combat buttons changed")
	_ok(_has_joy("p1_confirm", JOY_BUTTON_START, 0), "P1 confirm is no longer Start")
	_ok(_has_joy("p2_confirm", JOY_BUTTON_START, 1), "P2 confirm is no longer Start")
	_ok(_has_joy("pause", JOY_BUTTON_START, 0) and _has_joy("pause", JOY_BUTTON_START, 1),
			"Start no longer pauses on both pads")
	_ok(_has_key("pause", KEY_ESCAPE), "Escape no longer pauses")
	_ok(not _has_joy("pause", JOY_BUTTON_A, 0), "pad A was bound to pause")
	_ok(_has_joy("ui_accept", JOY_BUTTON_A, -1), "pad A is not bound to ui_accept")
	_ok(_has_key("ui_accept", KEY_ENTER) and _has_key("ui_accept", KEY_SPACE),
			"ui_accept lost its keyboard bindings")


func _check_menus() -> void:
	Game.mode = "versus"
	Game.p1_id = "dave"
	Game.p2_id = "karen"
	get_tree().change_scene_to_file(Game.MAIN_MENU)
	await _frames(4)

	var focus := get_viewport().gui_get_focus_owner() as Button
	_ok(focus != null and focus.text == "LOCAL VERSUS",
			"title screen did not focus LOCAL VERSUS (got %s)" % _focus_text())
	await _tap_joy(0, JOY_BUTTON_DPAD_DOWN)
	focus = get_viewport().gui_get_focus_owner() as Button
	_ok(focus != null and focus.text == "ARCADE",
			"D-pad down did not move to ARCADE (got %s)" % _focus_text())
	await _tap_joy(0, JOY_BUTTON_DPAD_UP)
	focus = get_viewport().gui_get_focus_owner() as Button
	_ok(focus != null and focus.text == "LOCAL VERSUS",
			"D-pad up did not return to LOCAL VERSUS (got %s)" % _focus_text())

	await _tap_joy(0, JOY_BUTTON_A)
	await _frames(3)
	_ok(_scene_is(Game.CHAR_SELECT), "pad A did not confirm the title button")
	if not _scene_is(Game.CHAR_SELECT):
		return

	var select := get_tree().current_scene
	_ok(select != null and str(select.mode) == "versus", "versus select did not open")
	await _tap_joy(0, JOY_BUTTON_A)
	await _frames(2)
	_ok(_scene_is(Game.CHAR_SELECT), "one pad A skipped character select")
	if not is_instance_valid(select):
		return
	_ok(bool(select.locked[0]) and not bool(select.locked[1]),
			"P1 pad A should lock only P1 (locked=%s)" % str(select.locked))
	await _tap_joy(1, JOY_BUTTON_A)
	await _frames(3)
	_ok(_scene_is(Game.STAGE_SELECT), "P2 pad A did not lock the second fighter")

	await _tap_joy(0, JOY_BUTTON_A)
	await _frames(4)
	_ok(_scene_is(Game.ARENA), "pad A did not confirm the stage")

	var arena := get_tree().current_scene as Arena
	_ok(arena != null and arena.pause_menu != null, "arena has no pause menu")
	if arena == null:
		return
	await _tap_joy(0, JOY_BUTTON_START)
	await _frames(2)
	_ok(get_tree().paused and arena.pause_menu.visible, "Start did not open pause")
	await _tap_joy(0, JOY_BUTTON_A)
	await _frames(2)
	_ok(not get_tree().paused and not arena.pause_menu.visible, "pad A did not confirm resume")
	_ok(get_viewport().gui_get_focus_owner() == null, "resume left a hidden button focused")

	arena.phase = Arena.Phase.FIGHT
	arena.p1.state = Fighter.State.IDLE
	arena.p1.move_name = ""
	arena.p1.move = {}
	arena.p2.state = Fighter.State.IDLE
	await _tick([_joy_event(0, JOY_BUTTON_A, true)])
	await _tick()
	_ok(arena.p1.state == Fighter.State.ATTACK and arena.p1.move_name == "jab",
			"pad A during a match did not throw P1 light (state %s %s)" % [arena.p1.state, arena.p1.move_name])
	_ok(not arena.pause_menu.visible and not get_tree().paused, "combat A opened the pause menu")
	await _tick([_joy_event(0, JOY_BUTTON_A, false)])

	var before := float(SaveData.settings["volume"])
	get_tree().change_scene_to_file("res://scenes/ui/options.tscn")
	await _frames(4)
	_ok(_scene_is("res://scenes/ui/options.tscn"), "options did not open")
	await _tap_joy(0, JOY_BUTTON_A)
	var after := float(SaveData.settings["volume"])
	_ok(int(round(after * 100.0)) == _next_volume_step(before),
			"pad A cycled volume from %s to %s" % [before, after])

	Game.mode = "versus"
	Game.results = {
		"mode": "versus", "p1": "dave", "p2": "karen", "stage": "breakroom",
		"winner": 0, "wins": [2, 0], "best_combo": [1, 0],
		"damage": [100.0, 0.0], "rounds": 2, "duration": 10.0,
	}
	get_tree().change_scene_to_file(Game.RESULTS)
	await _frames(4)
	focus = get_viewport().gui_get_focus_owner() as Button
	_ok(focus != null and focus.text == "REMATCH",
			"results did not focus REMATCH (got %s)" % _focus_text())
	await _tap_joy(1, JOY_BUTTON_A)
	await _frames(4)
	_ok(_scene_is(Game.ARENA), "P2 pad A did not confirm results")


func _check_intro_edges() -> void:
	var arena := await _spawn_arena("dave", "karen", "versus")
	arena.phase = Arena.Phase.INTRO
	arena.phase_ticks = 16
	arena._accum = 0.0
	await _tick([_joy_event(0, JOY_BUTTON_A, true)])
	await _tick([_joy_event(0, JOY_BUTTON_A, false)])
	await _tick([_joy_event(0, JOY_BUTTON_DPAD_UP, true)])
	await _tick([_joy_event(0, JOY_BUTTON_DPAD_UP, false)])
	_ok(arena.phase == Arena.Phase.INTRO, "intro taps already reached FIGHT")
	var guard := 0
	while arena.phase == Arena.Phase.INTRO and guard < 40:
		await _tick()
		guard += 1
	_ok(arena.phase == Arena.Phase.FIGHT, "intro never became FIGHT")
	for i in 8:
		await _tick()
	_ok(arena.p1.state != Fighter.State.ATTACK and arena.p1.move_name == "",
			"released intro attack fired in FIGHT (%s)" % arena.p1.move_name)
	_ok(not arena.p1.airborne and arena.p1.vel.y >= -1.0,
			"released intro jump fired in FIGHT")
	arena.queue_free()
	await _frames(2)

	arena = await _spawn_arena("dave", "karen", "versus")
	arena.phase = Arena.Phase.INTRO
	arena.phase_ticks = 1
	arena._accum = 0.0
	var origin := arena.p1.pos.x
	guard = 0
	await _tick([_joy_event(0, JOY_BUTTON_DPAD_RIGHT, true)])
	while arena.phase == Arena.Phase.INTRO and guard < 8:
		await _tick()
		guard += 1
	_ok(arena.phase == Arena.Phase.FIGHT, "held direction never reached FIGHT")
	var at_fight := arena.p1.pos.x
	for i in 6:
		await _tick()
	_ok(arena.p1.pos.x > at_fight + 4.0,
			"held direction was dropped at the first fight ticks (%.1f -> %.1f, origin %.1f)" % [at_fight, arena.p1.pos.x, origin])
	_ok(arena.p1.state != Fighter.State.ATTACK, "held direction started an attack")
	await _tick([_joy_event(0, JOY_BUTTON_DPAD_RIGHT, false)])
	arena.queue_free()
	await _frames(2)

	arena = await _spawn_arena("dave", "karen", "versus")
	arena.phase = Arena.Phase.INTRO
	arena.phase_ticks = 1
	arena._accum = 0.0
	await _tick([_joy_event(0, JOY_BUTTON_A, true)])
	_ok(arena.phase == Arena.Phase.FIGHT, "boundary press did not leave the intro")
	if arena.p1.state != Fighter.State.ATTACK:
		await _tick([_joy_event(0, JOY_BUTTON_A, false)])
	_ok(arena.p1.state == Fighter.State.ATTACK and arena.p1.move_name == "jab",
			"press on the first playable tick did not attack (%s %s)" % [arena.p1.state, arena.p1.move_name])
	await _tick([_joy_event(0, JOY_BUTTON_A, false)])
	arena.queue_free()
	await _frames(2)


func _check_reset_edges() -> void:
	var arena := await _spawn_arena("dave", "karen", "training")
	arena.phase = Arena.Phase.KO
	arena.phase_ticks = 10
	arena.training = true
	await _tick([_joy_event(0, JOY_BUTTON_A, true)])
	await _tick([_joy_event(0, JOY_BUTTON_A, false)])
	await _tick([_joy_event(0, JOY_BUTTON_DPAD_UP, true)])
	await _tick([_joy_event(0, JOY_BUTTON_DPAD_UP, false)])
	var guard := 0
	while arena.phase != Arena.Phase.FIGHT and guard < 30:
		await _tick()
		guard += 1
	_ok(arena.phase == Arena.Phase.FIGHT, "training reset did not return to FIGHT")
	for i in 10:
		await _tick()
	_ok(arena.p1.state != Fighter.State.ATTACK and arena.p1.move_name == "",
			"KO tap fired after training reset (%s)" % arena.p1.move_name)
	_ok(not arena.p1.airborne, "KO jump fired after training reset")

	arena.phase = Arena.Phase.KO
	arena.phase_ticks = 1
	arena.slowmo = 0
	await _tick([_joy_event(0, JOY_BUTTON_A, true)])
	_ok(arena.phase == Arena.Phase.FIGHT, "boundary press did not leave the training KO")
	await _tick([_joy_event(0, JOY_BUTTON_A, false)])
	_ok(arena.p1.state == Fighter.State.ATTACK and arena.p1.move_name == "jab",
			"the first playable training tick ignored a fresh light press")
	arena.queue_free()
	await _frames(2)


func _check_clipboard() -> void:
	var arena := await _spawn_arena("karen", "dave", "versus")
	_place(arena)
	arena.p1.move = arena.p1.data["moves"]["special"]
	var proj := Projectile.new()
	proj.setup(arena.p1, arena.p1.move["projectile"])
	proj.position.x = arena.p2.pos.x
	var hb := proj.hitbox()
	var crouch := Rect2(CharacterDB.CROUCH_HURTBOX.position + arena.p2.pos, CharacterDB.CROUCH_HURTBOX.size)
	var stand := Rect2(CharacterDB.BASE_HURTBOX.position + arena.p2.pos, CharacterDB.BASE_HURTBOX.size)
	var board: Rect2 = proj.info["rect"]
	var linked := Rect2(board.position + proj.position, board.size)
	_ok(hb.position.is_equal_approx(linked.position) and hb.size.is_equal_approx(linked.size),
			"clipboard hitbox is not the drawn board")
	_ok(str(proj.info.get("height", "")) == "mid", "clipboard height is %s" % str(proj.info.get("height", "")))
	_ok(hb.intersects(crouch), "mid clipboard misses a stationary crouch hurtbox %s vs %s" % [hb, crouch])
	_ok(hb.intersects(stand), "clipboard misses a standing hurtbox %s vs %s" % [hb, stand])
	var crouch_top := arena.p2.pos.y + CharacterDB.CROUCH_HURTBOX.position.y
	_ok(hb.position.y < crouch_top and hb.end.y > crouch_top,
			"clipboard should cross the crouch line, not sit entirely above or below it")
	proj.free()

	var open_drop := await _throw_at(arena, true, false)
	_ok(open_drop > 70.0 and open_drop < 120.0,
			"free crouch should take full clipboard damage (drop %.1f)" % open_drop)
	arena.queue_free()
	await _frames(2)

	arena = await _spawn_arena("karen", "dave", "versus")
	var chip_drop := await _throw_at(arena, true, true)
	_ok(chip_drop > 8.0 and chip_drop < 20.0,
			"crouch block should take chip, not full damage (drop %.1f)" % chip_drop)
	arena.queue_free()
	await _frames(2)

	arena = await _spawn_arena("karen", "dave", "versus")
	var stand_drop := await _throw_at(arena, false, false)
	_ok(stand_drop > 70.0 and stand_drop < 120.0,
			"standing opponent should still take the clipboard (drop %.1f)" % stand_drop)
	arena.queue_free()
	await _frames(1)


func _throw_at(arena: Arena, crouch: bool, block: bool) -> float:
	_place(arena)
	arena.p1.meter = CharacterDB.METER_MAX
	arena.p1.state = Fighter.State.IDLE
	arena.p2.state = Fighter.State.IDLE
	var events: Array = []
	if crouch:
		events.append(_joy_event(1, JOY_BUTTON_DPAD_DOWN, true))
	if block:
		events.append(_joy_event(1, JOY_BUTTON_Y, true))
	await _tick(events)
	await _tick()
	_ok(arena.p2.crouching == crouch, "defender crouch state is %s" % arena.p2.crouching)
	_ok(arena.p2.blocking == block, "defender block state is %s" % arena.p2.blocking)
	var before: float = arena.p2.health
	await _tick([_joy_event(0, JOY_BUTTON_X, true)])
	await _tick([_joy_event(0, JOY_BUTTON_X, false)])
	var guard := 0
	while arena.p2.health >= before - 0.5 and guard < 90:
		await _tick()
		guard += 1
	var drop := before - arena.p2.health
	if block:
		_ok(arena.p2.state == Fighter.State.BLOCKSTUN,
				"crouch block did not enter blockstun (state %s)" % arena.p2.state)
	elif drop > 0.5:
		_ok(arena.p2.state == Fighter.State.HITSTUN or arena.p2.state == Fighter.State.KO,
				"clean hit did not stun (state %s)" % arena.p2.state)
	if crouch:
		await _tick([_joy_event(1, JOY_BUTTON_DPAD_DOWN, false)])
	if block:
		await _tick([_joy_event(1, JOY_BUTTON_Y, false)])
	return drop


func _place(arena: Arena) -> void:
	get_viewport().gui_release_focus()
	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	arena._accum = 0.0
	arena.p1.pos = Vector2(480, CharacterDB.GROUND_Y)
	arena.p2.pos = Vector2(640, CharacterDB.GROUND_Y)
	arena.p1.position = arena.p1.pos
	arena.p2.position = arena.p2.pos
	arena.p1.facing = 1
	arena.p2.facing = -1
	arena.p1.vel = Vector2.ZERO
	arena.p2.vel = Vector2.ZERO


func _spawn_arena(p1_id: String, p2_id: String, mode: String) -> Arena:
	Game.mode = mode
	Game.match_config = {
		"mode": mode, "p1": p1_id, "p2": p2_id, "stage": "breakroom",
		"p2_is_ai": false, "difficulty": 2,
		"round_wins_needed": Game.rounds_to_win(mode),
	}
	var arena: Arena = load(Game.ARENA).instantiate()
	arena.auto_report = false
	add_child(arena)
	arena._accum = 0.0
	get_viewport().gui_release_focus()
	await _frames(1)
	return arena


func _next_volume_step(volume: float) -> int:
	var steps := [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
	var current := int(round(volume * 100.0))
	for step in steps:
		if step > current:
			return step
	return 0


func _joy_event(device: int, button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	ev.pressed = pressed
	return ev


func _joy(device: int, button: JoyButton, pressed: bool) -> void:
	Input.parse_input_event(_joy_event(device, button, pressed))


func _tap_joy(device: int, button: JoyButton) -> void:
	_joy(device, button, true)
	await get_tree().process_frame
	_joy(device, button, false)
	await get_tree().process_frame


func _tick(events: Array = []) -> void:
	await get_tree().physics_frame
	for ev in events:
		Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _release_all() -> void:
	var buttons: Array[JoyButton] = [
		JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START,
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	]
	for device in [0, 1]:
		for button in buttons:
			_joy(device, button, false)
	await _frames(2)


func _goto_blank() -> void:
	var packed := PackedScene.new()
	var blank := Node.new()
	blank.name = "Blank"
	var err := packed.pack(blank)
	blank.free()
	_ok(err == OK, "could not pack a blank scene")
	get_tree().change_scene_to_packed(packed)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _scene_is(path: String) -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == path


func _focus_text() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button:
		return (focus as Button).text
	return "<none>"


func _has_key(action: String, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			# Built-in UI actions use keycode; the game's own map uses physical_keycode.
			if k.physical_keycode == key or k.keycode == key:
				return true
	return false


func _has_joy(action: String, button: JoyButton, device: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			var joy := ev as InputEventJoypadButton
			if joy.button_index == button and joy.device == device:
				return true
	return false


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _report() -> void:
	var code := 0
	if _failures.is_empty():
		print("REVIEW PASS: %d checks" % _checks)
	else:
		code = 1
		printerr("REVIEW FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
	Harness.quiet_quit(self, code)
