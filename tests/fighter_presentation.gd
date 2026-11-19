extends Node

## Regressions for buffered stance, projectile release frames, and jump shadows.
##   godot --headless --path . res://tests/fighter_presentation.tscn

const Harness := preload("res://tests/harness.gd")

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_ok(SaveData.is_isolated(),
			"presentation suite did not isolate the save (args: %s)" % " ".join(OS.get_cmdline_args()))
	if not _failures.is_empty():
		_report()
		return
	await get_tree().process_frame
	_check_crouch_on_consume()
	_check_buffer_window()
	_check_hitstop_buffer()
	_check_air_buffer()
	_check_release_pose()
	_check_jump_shadow()
	_check_arena_presentation()
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_report()


func _check_crouch_on_consume() -> void:
	# Standing heavy, down held through the buffered light. The crouch flag is
	# still false from the standing move, so the light has to read the hold
	# when it is spent.
	var held := _spawn("dave")
	var heavy_total := _total(held, "heavy")
	var press := heavy_total - Fighter.INPUT_BUFFER
	var fired := _buffer_normal(held, "heavy", press, "light", 1, heavy_total, false)
	_ok(fired == heavy_total and held.move_name == "low" and held.crouching,
			"down-held light during heavy recovery came out as %s on tick %d" % [held.move_name, fired])

	# Light is buffered standing; down is taken up before the heavy ends.
	var entered := _spawn("dave")
	fired = _buffer_normal(entered, "heavy", press, "light", press + 1, heavy_total, false)
	_ok(fired == heavy_total and entered.move_name == "low" and entered.crouching,
			"entering crouch while a light was buffered came out as %s" % entered.move_name)

	# Crouching low, down released before the buffered light is spent.
	var left := _spawn("dave")
	var low_total := _total(left, "low")
	var low_press := low_total - Fighter.INPUT_BUFFER
	fired = _buffer_normal(left, "low", low_press, "light", 1, low_total - 1, true)
	_ok(fired == low_total and left.move_name == "jab" and not left.crouching,
			"releasing down before a buffered light came out as %s crouch=%s" % [left.move_name, left.crouching])

	# Tap on the tick the heavy ends, down held only then.
	var same_tick := _spawn("dave")
	fired = _buffer_normal(same_tick, "heavy", heavy_total, "light", heavy_total, heavy_total, false)
	_ok(fired == heavy_total and same_tick.move_name == "low" and same_tick.crouching,
			"last-tick light while holding down came out as %s" % same_tick.move_name)

	var swept := _spawn("dave")
	fired = _buffer_normal(swept, "heavy", press, "heavy", 1, heavy_total, false)
	_ok(fired == heavy_total and swept.move_name == "sweep" and swept.crouching,
			"down-held heavy during recovery came out as %s" % swept.move_name)


func _check_buffer_window() -> void:
	var connected := _spawn("dave")
	var total := _total(connected, "heavy")
	var fired := _buffer_normal(connected, "heavy", total - Fighter.INPUT_BUFFER, "light", 1, total, false)
	_ok(fired == total and connected.move_name == "low",
			"light on the last live buffer tick did not come out (tick %d, %s)" % [fired, connected.move_name])

	var expired := _spawn("dave")
	fired = _buffer_normal(expired, "heavy", total - Fighter.INPUT_BUFFER - 1, "light", 1, total, false)
	_ok(fired < 0 and expired.move_name == "" and expired.state == Fighter.State.IDLE,
			"light one tick outside the buffer came out as %s" % expired.move_name)

	# A jump buffered on that same edge still jumps when down is held.
	var jumper := _spawn("dave")
	fired = _buffer_normal(jumper, "heavy", total, "jump", total, total, false)
	_ok(jumper.jumped_flag and jumper.state == Fighter.State.AIR and jumper.move_name == ""
			and fired < 0,
			"buffered jump while holding down came out as %s" % jumper.move_name)


func _check_hitstop_buffer() -> void:
	var fighter := _spawn("dave")
	var total := _total(fighter, "heavy")
	var press := total - Fighter.INPUT_BUFFER
	fighter.start_move("heavy")
	for t in range(1, press + 1):
		fighter.tick(_inp(t == press, false, false, true))
	_ok(fighter.move_name == "heavy" and fighter.move_tick == press
			and fighter._buf_action == "light" and fighter._buf_ticks == Fighter.INPUT_BUFFER,
			"late light did not latch a full buffer")
	var frozen_move := fighter.move_tick
	var frozen_buf := fighter._buf_ticks
	fighter.apply_hitstop(5)
	for _i in 5:
		fighter.tick(_inp(false, false, false, true))
	_ok(fighter.hitstop == 0 and fighter.move_tick == frozen_move
			and fighter._buf_ticks == frozen_buf and fighter._buf_action == "light"
			and fighter.move_name == "heavy",
			"hitstop advanced the heavy or spent the buffer")
	var guard := 0
	while fighter.move_name == "heavy" and guard < total:
		fighter.tick(_inp(false, false, false, true))
		guard += 1
	_ok(fighter.move_name == "low" and fighter.crouching,
			"buffered crouching light did not survive hitstop (got %s)" % fighter.move_name)

	# Hitstop freezes the move and the buffer together, so a press that was
	# already outside the window stays outside.
	var early := _spawn("dave")
	var early_press := total - Fighter.INPUT_BUFFER - 1
	early.start_move("heavy")
	for t in range(1, early_press + 1):
		early.tick(_inp(t == early_press, false, false, true))
	early.apply_hitstop(5)
	for _i in 5:
		early.tick(_inp(false, false, false, true))
	guard = 0
	while early.move_name == "heavy" and guard < total:
		early.tick(_inp(false, false, false, true))
		guard += 1
	_ok(early.move_name == "" and early.state == Fighter.State.IDLE,
			"hitstop extended a light that was already outside the buffer (%s)" % early.move_name)


func _check_air_buffer() -> void:
	var fighter := _spawn("dave")
	fighter.pos = Vector2(480, 40)
	fighter.position = fighter.pos
	fighter.vel = Vector2.ZERO
	fighter.airborne = true
	fighter.crouching = false
	fighter.state = Fighter.State.AIR
	var total := _total(fighter, "air")
	var press := total - Fighter.INPUT_BUFFER
	fighter.start_move("air")
	var stayed_up := true
	for t in range(1, total + 1):
		fighter.tick(_inp(t == press, false, false, true))
		if not fighter.airborne:
			stayed_up = false
	_ok(stayed_up and fighter.pos.y < CharacterDB.GROUND_Y - 100.0,
			"air buffer sample reached the ground")
	_ok(fighter.move_name == "air" and fighter.airborne and not fighter.crouching,
			"down-held air light came out as %s crouch=%s" % [fighter.move_name, fighter.crouching])


func _check_release_pose() -> void:
	var karen := _spawn("karen")
	var move: Dictionary = karen.data["moves"]["special"]
	_ok(int(move.get("release_frame", -1)) == 2 and move.has("projectile"),
			"Karen's projectile special is missing release frame 2")
	var startup := int(move["startup"])
	var active := int(move["active"])
	_ok(startup == 14 and active == 4, "clipboard startup/active changed")
	var frames := _record_poses(karen, "special")
	_ok(int(frames[1]) == 0 and int(frames[8]) == 1 and int(frames[13]) == 1,
			"startup reached the release pose early (tick 8 is %s)" % str(frames.get(8, "?")))
	_ok(int(frames[startup]) == 2 and int(frames[startup + active - 1]) == 2,
			"release frame was not up at the spawn tick (tick 14 is %s, tick 17 is %s)" % [frames.get(14), frames.get(17)])
	_ok(int(frames[8]) != 2 and int(frames[startup]) != 4,
			"tick 8 is still the release pose or tick 14 is still recovery pose 4")
	_ok(int(frames[startup + active]) == 3 and int(frames[27]) == 4 and int(frames[43]) == 5,
			"hold/recover/settle after the throw changed (%s, %s, %s)" % [frames.get(18), frames.get(27), frames.get(43)])

	var dave := _spawn("dave")
	_ok(not dave.data["moves"]["heavy"].has("release_frame")
			and not dave.data["moves"]["special"].has("release_frame"),
			"melee moves picked up a projectile release frame")
	var heavy := _record_poses(dave, "heavy")
	_ok(int(heavy[1]) == 0 and int(heavy[8]) == 2 and int(heavy[11]) == 3
			and int(heavy[14]) == 3 and int(heavy[15]) == 4 and int(heavy[34]) == 4,
			"standing heavy poses moved (tick 8=%s, startup=%s, recovery=%s)" % [heavy.get(8), heavy.get(11), heavy.get(15)])
	dave.meter = CharacterDB.METER_MAX
	var special := _record_poses(dave, "special")
	_ok(int(special[8]) == 2 and int(special[15]) == 4 and int(special[19]) == 4
			and int(special[20]) == 5 and int(special[43]) == 5,
			"melee special poses moved (tick 8=%s, startup=%s, recovery=%s)" % [special.get(8), special.get(15), special.get(20)])


func _check_jump_shadow() -> void:
	var fighter := _spawn("dave")
	fighter.state = Fighter.State.IDLE
	var grounded := fighter.pos
	fighter.tick(_inp(false, false, true, false))
	var risen := fighter.pos
	var rise := grounded.y - risen.y
	var expected := -(float(fighter.data["build"]["jump_velocity"]) + Fighter.GRAVITY * Fighter.TICK) * Fighter.TICK
	_ok(is_equal_approx(rise, expected) and rise > 15.0 and rise < 17.0,
			"first jump tick rose %.3f px" % rise)
	_ok(fighter.airborne and fighter.state == Fighter.State.AIR, "jump did not leave the ground")
	var sim := fighter.pos
	# Alpha 0: the body is still on the previous sample while pos is already up.
	fighter.present_at(grounded)
	_ok(fighter.position.is_equal_approx(grounded), "present_at did not apply the rendered point")
	_ok(fighter.pos.is_equal_approx(sim), "present_at wrote the simulated position")
	_ok(is_equal_approx(fighter.shadow.global_position.y, CharacterDB.GROUND_Y),
			"shadow sank to %.2f on the first interpolated jump frame (rise %.2f)" % [fighter.shadow.global_position.y, rise])
	_ok(is_equal_approx(fighter.shadow.position.y, 0.0)
			and is_equal_approx(fighter.shadow.scale.x, 2.2)
			and is_equal_approx(fighter.shadow.modulate.a, 0.6),
			"grounded presentation kept the airborne shadow")
	var mid := grounded.lerp(risen, 0.25)
	fighter.present_at(mid)
	_ok(fighter.position.is_equal_approx(mid)
			and is_equal_approx(fighter.shadow.global_position.y, CharacterDB.GROUND_Y),
			"shadow left the floor between jump samples")
	fighter.present_at(risen)
	_ok(is_equal_approx(fighter.shadow.global_position.y, CharacterDB.GROUND_Y)
			and is_equal_approx(fighter.shadow.position.y, rise),
			"shadow did not sit on the floor under the risen body")


func _check_arena_presentation() -> void:
	Game.match_config = {"mode": "versus", "p1": "karen", "p2": "dave", "p2_is_ai": false}
	var arena := (load(Game.ARENA) as PackedScene).instantiate() as Arena
	arena.auto_report = false
	add_child(arena)
	arena.set_physics_process(false)
	arena._enter_fight()
	arena.router._press[0]["up"] = true
	arena._step()
	arena._present(0.0)
	_ok(arena.p1.pos.y < CharacterDB.GROUND_Y and arena.p1.position.y == CharacterDB.GROUND_Y
			and arena.p1.shadow.global_position.y == CharacterDB.GROUND_Y,
			"arena interpolation did not keep the jump shadow grounded")

	arena._start_round()
	arena._enter_fight()
	arena.p1.meter = CharacterDB.METER_COST
	arena.router._press[0]["special"] = true
	arena._step()
	var startup := int(arena.p1.move["startup"])
	for tick in startup - 1:
		arena._step()
	_ok(arena.projectiles.is_empty(), "arena spawned the clipboard before the release")
	arena._step()
	_ok(arena.projectiles.size() == 1 and arena.p1.sprite.frame == 2,
			"arena did not spawn the clipboard in the release pose")


func _buffer_normal(fighter: Fighter, move_id: String, press_tick: int, button: String,
		crouch_from: int, crouch_to: int, started_crouched: bool) -> int:
	fighter.crouching = started_crouched
	fighter.start_move(move_id)
	var total := CharacterDB.move_total(fighter.move)
	var fired := -1
	for t in range(1, total + 1):
		var inp := _inp(false, false, false, t >= crouch_from and t <= crouch_to)
		if t == press_tick:
			inp[button] = true
		fighter.tick(inp)
		if fired >= 0:
			continue
		if fighter.move_name != move_id and fighter.move_name != "":
			fired = t
		elif t > 1 and fighter.move_name == move_id and fighter.move_tick == 0:
			fired = t
	return fired


func _record_poses(fighter: Fighter, move_id: String) -> Dictionary:
	if move_id == "special":
		fighter.meter = CharacterDB.METER_MAX
	fighter.start_move(move_id)
	var frames := {}
	for t in range(1, CharacterDB.move_total(fighter.move)):
		fighter.tick(_inp())
		frames[t] = fighter.sprite.frame
		if fighter.sprite.animation != str(fighter.move.get("anim", "")):
			frames[t] = -1
	return frames


func _total(fighter: Fighter, move_id: String) -> int:
	return CharacterDB.move_total(fighter.data["moves"][move_id])


func _spawn(id: String) -> Fighter:
	var fighter: Fighter = load("res://scenes/fight/fighter.tscn").instantiate()
	add_child(fighter)
	fighter.setup(id, 0)
	fighter.reset_for_round(Vector2(480, CharacterDB.GROUND_Y), 1)
	return fighter


func _inp(light := false, heavy := false, jump := false, crouch := false) -> Dictionary:
	return {
		"dir": 0,
		"jump": jump,
		"crouch": crouch,
		"light": light,
		"heavy": heavy,
		"special": false,
		"block": false,
	}


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _report() -> void:
	var code := 0
	if _failures.is_empty():
		print("PRESENTATION PASS: %d checks" % _checks)
	else:
		code = 1
		printerr("PRESENTATION FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
	Harness.quiet_quit(self, code)
