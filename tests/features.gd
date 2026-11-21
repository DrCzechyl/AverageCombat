extends Node

## Comprehensive headless feature test suite. Run with:
##   godot --headless --path . res://tests/features.tscn
##
## Covers typed specs, art sheets & audio assets, cancel routes, throws & 7-tick
## tech window, knockdown & wakeup invuln & air-hit gravity, corner pushback
## transfer, armor feedback & silhouettes & mirror palette, decoupled events &
## rollback snapshot determinism, training mode tools, options (keybind
## remapping, shake scale, colorblind HUD), and mouse pickers.

const Harness := preload("res://tests/harness.gd")

var _failures: Array[String] = []
var _checks := 0
var _save_stamp := ""


func _ready() -> void:
	if not bool(get_meta("drive", false)):
		var driver := Node.new()
		driver.name = "FeaturesDriver"
		driver.process_mode = Node.PROCESS_MODE_ALWAYS
		driver.set_script(load("res://tests/features.gd"))
		driver.set_meta("drive", true)
		get_tree().root.add_child.call_deferred(driver)
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_stamp = Harness.normal_save_stamp()
	_ok(SaveData.is_isolated(),
			"features did not isolate the save (args: %s)" % " ".join(OS.get_cmdline_args()))
	_ok(Harness.save_is_outside_user_dir(), "features save is inside user://")
	if not _failures.is_empty():
		_report()
		return
	await _frames(1)
	await _run()
	_ok(Harness.normal_save_stamp() == _save_stamp, "features suite touched the normal save")
	_report()


func _run() -> void:
	await _check_specs_art_audio()
	await _check_cancel_routes()
	await _check_throws_and_tech()
	await _check_knockdown_wakeup_and_air_gravity()
	await _check_corner_pushback_transfer()
	await _check_armor_silhouettes_and_mirror_palette()
	await _check_events_and_rollback_determinism()
	await _check_training_tools()
	await _check_options_and_mouse_pickers()
	await _goto_blank()


# ---------------------------------------------------------------------------
# 1. Typed Specs, Art Sheets & Audio Assets
# ---------------------------------------------------------------------------


func _check_specs_art_audio() -> void:
	for id in CharacterDB.ORDER:
		var spec := CharacterDB.get_fighter_spec(id)
		_ok(spec is FighterSpec and spec.id == id and not spec.name.is_empty(),
				"%s get_fighter_spec did not return a valid FighterSpec" % id)
		var jab := CharacterDB.get_move_spec(id, "jab")
		_ok(jab is MoveSpec and jab.id == "jab" and jab.total() == jab.startup + jab.active + jab.recovery,
				"%s get_move_spec('jab') did not return a valid MoveSpec" % id)
		_ok("heavy" in jab.cancel_into and "special" in jab.cancel_into,
				"%s jab MoveSpec missing expected cancel_into entries (%s)" % [id, str(jab.cancel_into)])
		var tex: Texture2D = load(spec.sheet)
		var expected_w := CharacterDB.SHEET_COLS * CharacterDB.CELL_W
		var expected_h := 16 * CharacterDB.CELL_H
		_ok(tex != null and tex.get_width() == expected_w and tex.get_height() == expected_h,
				"%s sheet is not %dx%d (got %s)" % [
					id, expected_w, expected_h, str(tex.get_size()) if tex != null else "null"])
		_ok(not spec.portrait.is_empty() and ResourceLoader.exists(spec.portrait),
				"%s portrait is missing (%s)" % [id, spec.portrait])
		var ptex: Texture2D = load(spec.portrait)
		_ok(ptex != null and ptex.get_width() >= 256 and ptex.get_height() >= 256,
				"%s portrait failed to load or is too small" % id)

	var tony := CharacterDB.get_fighter_spec("tony")
	_ok(is_equal_approx(tony.throw_range, 132.0),
			"Tony spec throw_range was %.1f, expected 132.0" % tony.throw_range)
	_ok(is_equal_approx(tony.throw_damage, 140.0),
			"Tony spec throw_damage was %.1f, expected 140.0" % tony.throw_damage)

	var arena := await _make_arena("dave", "karen")
	var sf := arena.p1.sprite.sprite_frames
	_ok(sf != null, "Fighter sprite_frames is null")
	if sf != null:
		for anim_name in ["sweep", "air", "crouch_block", "throw"]:
			_ok(sf.has_animation(anim_name), "Fighter sprite_frames missing '%s' animation" % anim_name)
			if sf.has_animation(anim_name):
				var expected_frames := int(CharacterDB.ANIMS[anim_name]["frames"])
				_ok(sf.get_frame_count(anim_name) == expected_frames,
						"Fighter '%s' frame count was %d, expected %d" % [
							anim_name, sf.get_frame_count(anim_name), expected_frames])
	arena.queue_free()
	await _frames(1)

	for stage_id in StageDB.ORDER:
		var st := StageDB.get_stage(stage_id)
		var amb := str(st.get("ambience", ""))
		_ok(amb != "" and Sfx._ambience_streams.has(amb) and Sfx._ambience_streams[amb] != null,
				"Stage %s ambience '%s' is not loaded in Sfx" % [stage_id, amb])

	for sfx_key in ["armor", "throw", "tech"]:
		_ok(Sfx._streams.has(sfx_key) and Sfx._streams[sfx_key] != null,
				"Sfx._streams missing '%s'" % sfx_key)


# ---------------------------------------------------------------------------
# 2. Cancel Routes (cancel_into)
# ---------------------------------------------------------------------------


func _check_cancel_routes() -> void:
	SaveData.settings["hitstop"] = false

	# 2a. Dave's jab cancels into heavy on hit well before jab recovery finishes.
	var a_hit := await _make_arena("dave", "karen")
	_place(a_hit.p1, a_hit.p2, 600.0, 690.0)
	var jab_total := CharacterDB.move_total(a_hit.p1.data["moves"]["jab"])
	var jab_startup := int(a_hit.p1.data["moves"]["jab"]["startup"])
	a_hit.p1.start_move("jab")
	for _i in jab_startup:
		a_hit._step()
	_ok(a_hit.p1.move_has_hit and a_hit.p1.move_name == "jab",
			"Dave jab did not connect on startup tick (hit=%s move=%s)" % [a_hit.p1.move_has_hit, a_hit.p1.move_name])
	var tick_before_cancel := a_hit.p1.move_tick
	a_hit.p1.tick(_inp(0, false, false, false, true, false, false))
	_ok(a_hit.p1.state == Fighter.State.ATTACK and a_hit.p1.move_name == "heavy",
			"Dave jab did not cancel into heavy on hit (state=%s move=%s)" % [a_hit.p1.state, a_hit.p1.move_name])
	_ok(tick_before_cancel < jab_total - 5 and a_hit.p1.move_tick == 0,
			"Dave jab->heavy cancel did not happen early (from tick %d / total %d, new tick %d)" % [
				tick_before_cancel, jab_total, a_hit.p1.move_tick])
	a_hit.queue_free()
	await _frames(1)

	# 2b. Dave's jab cancels into special on block (with meter) once move_has_hit == true.
	var a_blk := await _make_arena("dave", "karen")
	_place(a_blk.p1, a_blk.p2, 600.0, 690.0)
	a_blk.p1.meter = CharacterDB.METER_MAX
	a_blk.p2.blocking = true
	a_blk.p2.crouching = false
	_prime(a_blk.p1, "jab")
	a_blk._resolve_melee()
	_ok(a_blk.p2.state == Fighter.State.BLOCKSTUN and a_blk.p1.move_has_hit,
			"Blocked jab did not set BLOCKSTUN and move_has_hit (state=%s hit=%s)" % [a_blk.p2.state, a_blk.p1.move_has_hit])
	var blk_tick := a_blk.p1.move_tick
	a_blk.p1.tick(_inp(0, false, false, false, false, true, false))
	_ok(a_blk.p1.state == Fighter.State.ATTACK and a_blk.p1.move_name == "special",
			"Dave jab did not cancel into special on block (state=%s move=%s)" % [a_blk.p1.state, a_blk.p1.move_name])
	_ok(blk_tick < jab_total - 5 and a_blk.p1.meter < CharacterDB.METER_MAX,
			"Dave jab->special block cancel did not happen early or spend meter (tick=%d meter=%.1f)" % [
				blk_tick, a_blk.p1.meter])
	a_blk.queue_free()
	await _frames(1)

	# 2c. Dave's jab does NOT cancel on whiff (move_has_hit == false).
	var a_whiff := await _make_arena("dave", "karen")
	_place(a_whiff.p1, a_whiff.p2, 300.0, 900.0)
	a_whiff.p1.meter = CharacterDB.METER_MAX
	a_whiff.p1.start_move("jab")
	for _i in jab_startup:
		a_whiff._step()
	_ok(not a_whiff.p1.move_has_hit and a_whiff.p1.move_name == "jab",
			"Whiffed jab unexpectedly marked move_has_hit")
	a_whiff.p1.tick(_inp(0, false, false, false, true, false, false))
	_ok(a_whiff.p1.move_name == "jab" and a_whiff.p1.move_tick == jab_startup + 1,
			"Dave jab canceled into %s on whiff" % a_whiff.p1.move_name)
	a_whiff.p1.tick(_inp(0, false, false, false, false, true, false))
	_ok(a_whiff.p1.move_name == "jab",
			"Dave jab canceled into %s (special) on whiff" % a_whiff.p1.move_name)
	a_whiff.queue_free()
	await _frames(1)

	# 2d. Dave's heavy cancels into special on hit with meter, and does NOT cancel into jab.
	var a_hvy := await _make_arena("dave", "karen")
	_place(a_hvy.p1, a_hvy.p2, 600.0, 690.0)
	a_hvy.p1.meter = CharacterDB.METER_MAX
	_prime(a_hvy.p1, "heavy")
	a_hvy._resolve_melee()
	_ok(a_hvy.p1.move_has_hit and a_hvy.p1.move_name == "heavy",
			"Dave heavy did not connect")
	# Try canceling heavy into jab (disallowed).
	a_hvy.p1.tick(_inp(0, false, false, true, false, false, false))
	_ok(a_hvy.p1.move_name == "heavy",
			"Dave heavy illegally canceled into %s on light input" % a_hvy.p1.move_name)
	# Try canceling heavy into special with insufficient meter (disallowed).
	a_hvy.p1.meter = CharacterDB.METER_COST - 1.0
	a_hvy.p1.tick(_inp(0, false, false, false, false, true, false))
	_ok(a_hvy.p1.move_name == "heavy",
			"Dave heavy canceled into special without enough meter")
	# Now with meter: cancels into special!
	a_hvy.p1.meter = CharacterDB.METER_MAX
	a_hvy.p1.tick(_inp(0, false, false, false, false, true, false))
	_ok(a_hvy.p1.state == Fighter.State.ATTACK and a_hvy.p1.move_name == "special",
			"Dave heavy did not cancel into special on hit with meter (move=%s)" % a_hvy.p1.move_name)
	a_hvy.queue_free()
	await _frames(1)

	SaveData.settings["hitstop"] = true

	# 2e. Buffered cancel during hitstop: jab hits with hitstop ON, heavy is pressed during hitstop,
	# and cancels immediately on the first post-hitstop tick.
	var a_hs := await _make_arena("dave", "karen")
	_place(a_hs.p1, a_hs.p2, 600.0, 690.0)
	_prime(a_hs.p1, "jab")
	a_hs._resolve_melee()
	_ok(a_hs.p1.move_has_hit and a_hs.p1.hitstop > 0,
			"Hitstop cancel setup failed (hit=%s hitstop=%d)" % [a_hs.p1.move_has_hit, a_hs.p1.hitstop])
	a_hs.p1.tick(_inp(0, false, false, false, true, false, false))
	var guard := 0
	while a_hs.p1.hitstop > 0 and guard < 20:
		a_hs.p1.tick(_inp())
		guard += 1
	a_hs.p1.tick(_inp())
	_ok(a_hs.p1.state == Fighter.State.ATTACK and a_hs.p1.move_name == "heavy",
			"Buffered heavy during jab hitstop did not cancel into heavy (state=%s move=%s)" % [
				a_hs.p1.state, a_hs.p1.move_name])
	a_hs.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# 3. Throw + 7-tick Tech Window
# ---------------------------------------------------------------------------


func _check_throws_and_tech() -> void:
	# 3a. Close-range throw connects against a grounded blocking defender,
	# deals spec.throw_damage, knocks defender down, updates damage_done & combo.
	var a_throw := await _make_arena("dave", "karen")
	_place(a_throw.p1, a_throw.p2, 600.0, 680.0)
	var hp_before := a_throw.p2.health
	var expected_dmg := a_throw.p1.spec.throw_damage
	Input.action_press("p2_block")
	a_throw.p2.tick(_inp(0, false, false, false, false, false, true))
	_ok(a_throw.p2.blocking and not a_throw.p2.airborne,
			"Defender was not in grounded blocking state before throw")
	a_throw.p1.start_throw()
	var reached_grab := false
	var completed := false
	var landed_kd := false
	for _i in 80:
		a_throw._step()
		if a_throw.p2.state == Fighter.State.GRABBED:
			reached_grab = true
		if is_equal_approx(hp_before - a_throw.p2.health, expected_dmg) and a_throw.combo[0] >= 1:
			completed = true
		if a_throw.p2.state == Fighter.State.KNOCKDOWN:
			landed_kd = true
			break
	Input.action_release("p2_block")
	_ok(reached_grab, "Throw did not grab a grounded blocking defender")
	_ok(completed, "Throw did not deal spec.throw_damage (%.1f vs %.1f) or record combo (%d)" % [
		hp_before - a_throw.p2.health, expected_dmg, a_throw.combo[0]])
	_ok(is_equal_approx(a_throw.damage_done[0], expected_dmg),
			"Throw did not update arena.damage_done (got %.1f, expected %.1f)" % [
				a_throw.damage_done[0], expected_dmg])
	_ok(landed_kd, "Throw did not knock defender down into KNOCKDOWN")
	a_throw.queue_free()
	await _frames(1)

	# 3b. Tony throws Dave from 122.0 px apart (<= 132.0); Dave whiffs from 122.0 px (> 108.0).
	var a_range := await _make_arena("tony", "dave")
	_place(a_range.p1, a_range.p2, 500.0, 622.0)
	a_range.p1.start_throw()
	for _i in CharacterDB.THROW_STARTUP:
		a_range._step()
	_ok(a_range.p1.throw_connected and a_range.p2.state == Fighter.State.GRABBED,
			"Tony failed to grab Dave from 122px (connected=%s p2_state=%s)" % [
				a_range.p1.throw_connected, a_range.p2.state])
	a_range.queue_free()
	await _frames(1)

	var a_whiff := await _make_arena("dave", "tony")
	_place(a_whiff.p1, a_whiff.p2, 500.0, 622.0)
	a_whiff.p1.start_throw()
	for _i in CharacterDB.THROW_STARTUP:
		a_whiff._step()
	_ok(not a_whiff.p1.throw_connected and a_whiff.p2.state != Fighter.State.GRABBED,
			"Dave grabbed Tony from 122px despite 108px throw_range")
	a_whiff.queue_free()
	await _frames(1)

	# 3c. Defender inputting throw (and also light+block) during the 7-tick tech window triggers THROW TECH.
	for method in ["throw_btn", "light_plus_block"]:
		var a_tech := await _make_arena("dave", "karen")
		_place(a_tech.p1, a_tech.p2, 600.0, 680.0)
		var p1_hp := a_tech.p1.health
		var p2_hp := a_tech.p2.health
		a_tech.p1.start_throw()
		for _i in CharacterDB.THROW_STARTUP:
			a_tech._step()
		_ok(a_tech.p1.throw_connected and a_tech.p2.state == Fighter.State.GRABBED,
				"Setup failed: throw did not enter GRABBED for tech test (%s)" % method)
		# Step 2 ticks into the 7-tick tech window, then input tech on tick 3.
		a_tech._step()
		a_tech._step()
		if method == "throw_btn":
			a_tech.router._press[1]["throw"] = true
		else:
			a_tech.router._press[1]["light"] = true
			Input.action_press("p2_block")
		a_tech._step()
		Input.action_release("p2_block")
		_ok(is_equal_approx(a_tech.p1.health, p1_hp) and is_equal_approx(a_tech.p2.health, p2_hp),
				"Throw tech (%s) still dealt damage" % method)
		_ok(a_tech.p1.vel.x < -100.0 and a_tech.p2.vel.x > 100.0,
				"Throw tech (%s) did not push both fighters apart (vel %.1f / %.1f)" % [
					method, a_tech.p1.vel.x, a_tech.p2.vel.x])
		_ok(a_tech.p1.invuln > 0 and a_tech.p2.invuln > 0,
				"Throw tech (%s) did not grant invuln (%d / %d)" % [method, a_tech.p1.invuln, a_tech.p2.invuln])
		_ok(a_tech.announce_text == "TECH!",
				"Throw tech (%s) did not announce TECH! (got '%s')" % [method, a_tech.announce_text])
		_ok(a_tech.p1.state == Fighter.State.IDLE and a_tech.p2.state == Fighter.State.IDLE,
				"Throw tech (%s) did not return both fighters to IDLE (%s / %s)" % [
					method, a_tech.p1.state, a_tech.p2.state])
		a_tech.queue_free()
		await _frames(1)

	# 3d. Throw whiffs cleanly against an airborne defender and recovers to IDLE.
	var a_air := await _make_arena("dave", "karen")
	_place(a_air.p1, a_air.p2, 600.0, 680.0)
	a_air.p2.pos = Vector2(680.0, CharacterDB.GROUND_Y - 140.0)
	a_air.p2.position = a_air.p2.pos
	a_air.p2.vel = Vector2(0.0, -300.0)
	a_air.p2.airborne = true
	a_air.p2.state = Fighter.State.AIR
	var air_hp := a_air.p2.health
	a_air.p1.start_throw()
	for _i in CharacterDB.THROW_STARTUP:
		a_air._step()
	_ok(not a_air.p1.throw_connected and a_air.p2.state != Fighter.State.GRABBED,
			"Throw grabbed an airborne defender")
	for _i in CharacterDB.THROW_RECOVERY + 2:
		a_air._step()
	_ok(a_air.p1.state == Fighter.State.IDLE and a_air.p1.move_name == "",
			"Whiffed throw did not recover to IDLE (state=%s move=%s)" % [a_air.p1.state, a_air.p1.move_name])
	_ok(is_equal_approx(a_air.p2.health, air_hp),
			"Whiffed throw damaged airborne defender")
	a_air.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# 4. Knockdown + Wakeup Invuln + Air-Hit Gravity
# ---------------------------------------------------------------------------


func _check_knockdown_wakeup_and_air_gravity() -> void:
	SaveData.settings["hitstop"] = false

	# 4a. Sweep launches with pending_knockdown, lands into KNOCKDOWN, wakes up with WAKEUP_INVULN.
	var arena := await _make_arena("dave", "karen")
	_place(arena.p1, arena.p2, 600.0, 690.0)
	_prime(arena.p1, "sweep")
	arena._resolve_melee()
	_ok(arena.p2.pending_knockdown and arena.p2.airborne and arena.p2.state == Fighter.State.HITSTUN,
			"Sweep did not launch defender with pending_knockdown (kd=%s air=%s state=%s)" % [
				arena.p2.pending_knockdown, arena.p2.airborne, arena.p2.state])

	var guard := 0
	while arena.p2.state != Fighter.State.KNOCKDOWN and guard < 80:
		arena._step()
		guard += 1
	_ok(arena.p2.state == Fighter.State.KNOCKDOWN,
			"Swept defender did not transition to KNOCKDOWN upon landing (state=%s)" % arena.p2.state)
	_ok(not arena.p2.can_be_hit(), "Knocked-down defender reported can_be_hit() == true")
	_ok(arena.p2.sprite.animation == "ko" and arena.p2.sprite.frame == 1,
			"KNOCKDOWN sprite was '%s' frame %d, expected 'ko' frame 1" % [
				arena.p2.sprite.animation, arena.p2.sprite.frame])

	# Wait for knockdown to end and trigger wakeup invuln.
	guard = 0
	while arena.p2.state == Fighter.State.KNOCKDOWN and guard < 60:
		arena._step()
		guard += 1
	_ok(arena.p2.state == Fighter.State.IDLE and arena.p2.invuln == CharacterDB.WAKEUP_INVULN,
			"Wakeup did not grant WAKEUP_INVULN (state=%s invuln=%d expected=%d)" % [
				arena.p2.state, arena.p2.invuln, CharacterDB.WAKEUP_INVULN])
	_ok(not arena.p2.can_be_hit(), "Defender with wakeup invuln should not be hittable")

	# Attempt overlapping melee hit during wakeup invuln: must not connect.
	_place(arena.p1, arena.p2, 600.0, 680.0)
	var hp_wake := arena.p2.health
	_prime(arena.p1, "jab")
	arena._resolve_melee()
	_ok(is_equal_approx(arena.p2.health, hp_wake) and not arena.p1.move_has_hit,
			"Attack connected during wakeup invuln (hp %.1f -> %.1f, hit=%s)" % [
				hp_wake, arena.p2.health, arena.p1.move_has_hit])
	arena.queue_free()
	await _frames(1)

	# 4b. Hitting an airborne rising defender (vel.y = -900.0) with a non-launching jab sets vel.y == -280.0.
	var air := await _make_arena("dave", "karen")
	_place(air.p1, air.p2, 600.0, 680.0)
	air.p2.pos = Vector2(680.0, CharacterDB.GROUND_Y - 120.0)
	air.p2.position = air.p2.pos
	air.p2.vel = Vector2(0.0, -900.0)
	air.p2.airborne = true
	air.p2.state = Fighter.State.AIR
	_prime(air.p1, "jab")
	air._resolve_melee()
	_ok(air.p1.move_has_hit and air.p2.state == Fighter.State.HITSTUN,
			"Jab did not connect against rising airborne defender")
	_ok(is_equal_approx(air.p2.vel.y, -280.0),
			"Air-hit gravity did not clamp rising vel.y to -280.0 (got %.2f)" % air.p2.vel.y)
	air.queue_free()
	await _frames(1)

	SaveData.settings["hitstop"] = true


# ---------------------------------------------------------------------------
# 5. Corner Pushback Transfer
# ---------------------------------------------------------------------------


func _check_corner_pushback_transfer() -> void:
	# Cornered at bounds.y (right corner): attacker velocity reflects negative.
	var corner := await _make_arena("dave", "karen")
	var right_edge := corner.p2.bounds.y
	_place(corner.p1, corner.p2, right_edge - 90.0, right_edge)
	corner.p1.facing = 1
	corner.p1.vel = Vector2.ZERO
	_prime(corner.p1, "heavy")
	corner._resolve_melee()
	_ok(corner.p1.vel.x < -50.0,
			"Cornered hit at bounds.y did not reflect negative vel.x onto attacker (vel.x=%.2f)" % corner.p1.vel.x)
	corner.queue_free()
	await _frames(1)

	# Mid-screen: attacker velocity stays non-negative.
	var mid := await _make_arena("dave", "karen")
	_place(mid.p1, mid.p2, 560.0, 650.0)
	mid.p1.facing = 1
	mid.p1.vel = Vector2.ZERO
	_prime(mid.p1, "heavy")
	mid._resolve_melee()
	_ok(mid.p1.vel.x >= 0.0,
			"Mid-screen hit reflected unexpected negative vel.x onto attacker (vel.x=%.2f)" % mid.p1.vel.x)
	mid.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# 6. Armor Feedback, Distinct Silhouettes & Mirror Palette
# ---------------------------------------------------------------------------


func _check_armor_silhouettes_and_mirror_palette() -> void:
	# 6a. Non-lethal hit against Tony during armored special.
	var armor_arena := await _make_arena("dave", "tony")
	_place(armor_arena.p1, armor_arena.p2, 600.0, 690.0)
	armor_arena.p2.meter = CharacterDB.METER_MAX
	armor_arena.p2.start_move("special")
	armor_arena.p2.move_tick = 2  # Active startup window, before special hits Dave.
	_prime(armor_arena.p1, "jab")
	var expected_jab := float(armor_arena.p1.data["moves"]["jab"]["damage"]) \
			* float(armor_arena.p1.data["build"]["damage_scale"])
	armor_arena._resolve_melee()
	_ok(armor_arena.p2.armor_flash_ticks > 0,
			"Armored hit did not set armor_flash_ticks > 0 (got %d)" % armor_arena.p2.armor_flash_ticks)
	_ok(armor_arena.p2.state == Fighter.State.ATTACK,
			"Armored Tony was interrupted out of ATTACK (state=%s)" % armor_arena.p2.state)
	_ok(armor_arena.combo[0] == 0,
			"Armored hit incremented attacker combo (%d)" % armor_arena.combo[0])
	_ok(is_equal_approx(armor_arena.damage_done[0], expected_jab),
			"Armored hit did not record damage_done (got %.1f, expected %.1f)" % [
				armor_arena.damage_done[0], expected_jab])
	armor_arena.queue_free()
	await _frames(1)

	# 6b. Crouching defender in BLOCKSTUN plays "crouch_block" (distinct from standing "block").
	var blk := await _make_arena("dave", "karen")
	blk.p2.state = Fighter.State.BLOCKSTUN
	blk.p2.stun_ticks = 10
	blk.p2.blocking = true
	blk.p2.crouching = false
	blk.p2.tick(_inp(0, false, false, false, false, false, true))
	var stand_anim := str(blk.p2.sprite.animation)
	blk.p2.tick(_inp(0, false, true, false, false, false, true))
	var crouch_anim := str(blk.p2.sprite.animation)
	_ok(stand_anim == "block",
			"Standing BLOCKSTUN played '%s', expected 'block'" % stand_anim)
	_ok(crouch_anim == "crouch_block" and crouch_anim != stand_anim,
			"Crouching BLOCKSTUN played '%s', expected 'crouch_block'" % crouch_anim)
	blk.queue_free()
	await _frames(1)

	# 6c. Mirror match sets p2.mirror_palette and ShaderMaterial; p1 stays default.
	var mirror := await _make_arena("dave", "dave")
	_ok(mirror.p2.mirror_palette and mirror.p2.sprite.material is ShaderMaterial,
			"Mirror match did not apply mirror_palette ShaderMaterial to P2 (flag=%s mat=%s)" % [
				mirror.p2.mirror_palette, str(mirror.p2.sprite.material)])
	_ok(not mirror.p1.mirror_palette and mirror.p1.sprite.material == null,
			"Mirror match unexpectedly tinted P1 (flag=%s mat=%s)" % [
				mirror.p1.mirror_palette, str(mirror.p1.sprite.material)])
	mirror.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# 7. Decoupled Events & Rollback Determinism
# ---------------------------------------------------------------------------


func _check_events_and_rollback_determinism() -> void:
	# 7a. Standalone fighter.start_move("jab") appends a "swing" event; drain_events returns & clears.
	var standalone: Fighter = Arena.FIGHTER_SCENE.instantiate()
	add_child(standalone)
	standalone.setup("dave", 0)
	standalone.events.clear()
	standalone.start_move("jab")
	_ok(standalone.events.size() == 1 and str(standalone.events[0].get("type", "")) == "sfx"
			and str(standalone.events[0].get("name", "")) == "swing",
			"start_move('jab') did not emit a 'swing' sfx event (%s)" % str(standalone.events))
	var drained := standalone.drain_events()
	_ok(drained.size() == 1 and str(drained[0].get("name", "")) == "swing",
			"drain_events() did not return the swing event (%s)" % str(drained))
	_ok(standalone.events.is_empty(), "drain_events() did not empty fighter.events")
	standalone.queue_free()
	await _frames(1)

	# 7b. Arena rollback determinism (Karen vs Dave, live clipboard projectile + active movement/attacks).
	SaveData.settings["hitstop"] = true
	var arena := await _make_arena("karen", "dave")
	_place(arena.p1, arena.p2, 260.0, 820.0)
	arena.p1.meter = CharacterDB.METER_MAX
	arena.p1.start_move("special")
	var karen_startup := int(arena.p1.data["moves"]["special"]["startup"])
	for _i in karen_startup:
		arena._step()
	_ok(arena.projectiles.size() == 1,
			"Expected 1 live clipboard projectile before snapshot (got %d)" % arena.projectiles.size())

	# Scripted 25-tick sequence with movement, jumps, crouch/block, and attacks for both fighters.
	var snap := arena.capture_snapshot()
	var run1 := _run_deterministic_25_ticks(arena)
	arena.restore_snapshot(snap)
	_ok(arena.projectiles.size() == 1 and arena.projectiles[0].z_index == 3,
			"Restored projectile did not preserve z_index == 3")
	var run2 := _run_deterministic_25_ticks(arena)

	_ok(run1["p1_pos"] == run2["p1_pos"],
			"Rollback p1.pos diverged (%s vs %s)" % [run1["p1_pos"], run2["p1_pos"]])
	_ok(run1["p2_pos"] == run2["p2_pos"],
			"Rollback p2.pos diverged (%s vs %s)" % [run1["p2_pos"], run2["p2_pos"]])
	_ok(run1["p1_health"] == run2["p1_health"],
			"Rollback p1.health diverged (%s vs %s)" % [run1["p1_health"], run2["p1_health"]])
	_ok(run1["p2_health"] == run2["p2_health"],
			"Rollback p2.health diverged (%s vs %s)" % [run1["p2_health"], run2["p2_health"]])
	_ok(run1["p1_meter"] == run2["p1_meter"],
			"Rollback p1.meter diverged (%s vs %s)" % [run1["p1_meter"], run2["p1_meter"]])
	_ok(run1["p2_meter"] == run2["p2_meter"],
			"Rollback p2.meter diverged (%s vs %s)" % [run1["p2_meter"], run2["p2_meter"]])
	_ok(run1["p1_state"] == run2["p1_state"],
			"Rollback p1.state diverged (%s vs %s)" % [run1["p1_state"], run2["p1_state"]])
	_ok(run1["p2_state"] == run2["p2_state"],
			"Rollback p2.state diverged (%s vs %s)" % [run1["p2_state"], run2["p2_state"]])
	_ok(run1["proj_count"] == run2["proj_count"] and int(run1["proj_count"]) == 1,
			"Rollback projectile count diverged or did not stay live (%s vs %s)" % [
				run1["proj_count"], run2["proj_count"]])
	_ok(run1["proj_positions"] == run2["proj_positions"],
			"Rollback projectile sim_pos diverged (%s vs %s)" % [
				str(run1["proj_positions"]), str(run2["proj_positions"])])

	# Also verify determinism across a live projectile impact + hitstop + damage + meter gain!
	_place(arena.p1, arena.p2, 360.0, 560.0)
	arena.clear_projectiles_now()
	arena.p1.state = Fighter.State.IDLE
	arena.p1._move_clear()
	arena.p2.state = Fighter.State.IDLE
	arena.p2._move_clear()
	arena.p1.meter = CharacterDB.METER_MAX
	arena.p1.start_move("special")
	for _i in karen_startup:
		arena._step()
	_ok(arena.projectiles.size() == 1, "Impact rollback setup missing projectile")
	var snap_hit := arena.capture_snapshot()
	var hit1 := _run_deterministic_25_ticks(arena)
	arena.restore_snapshot(snap_hit)
	var hit2 := _run_deterministic_25_ticks(arena)
	_ok(float(hit1["p2_health"]) < float(arena.p2.data["build"]["health"]),
			"Impact rollback test did not actually register projectile damage")
	_ok(hit1 == hit2, "Rollback with projectile hit/hitstop diverged (%s vs %s)" % [str(hit1), str(hit2)])

	arena.queue_free()
	await _frames(1)


func _run_deterministic_25_ticks(arena: Arena) -> Dictionary:
	arena.router.discard()
	_release_fight_actions()
	for t in 25:
		_release_fight_actions()
		if t >= 0 and t < 8:
			Input.action_press("p1_right")
			Input.action_press("p2_left")
		elif t >= 8 and t < 16:
			Input.action_press("p1_left")
			Input.action_press("p2_down")
		else:
			Input.action_press("p1_right")
			Input.action_press("p2_right")
		if t == 3:
			arena.router._press[1]["light"] = true
		if t == 10:
			arena.router._press[0]["light"] = true
		if t == 14:
			arena.router._press[1]["heavy"] = true
		if t == 19:
			arena.router._press[0]["up"] = true
		arena._step()
	_release_fight_actions()
	var proj_positions: Array[Vector2] = []
	for proj in arena.projectiles:
		if is_instance_valid(proj):
			proj_positions.append(proj.sim_pos)
	return {
		"p1_pos": arena.p1.pos,
		"p2_pos": arena.p2.pos,
		"p1_health": arena.p1.health,
		"p2_health": arena.p2.health,
		"p1_meter": arena.p1.meter,
		"p2_meter": arena.p2.meter,
		"p1_state": arena.p1.state,
		"p2_state": arena.p2.state,
		"proj_count": arena.projectiles.size(),
		"proj_positions": proj_positions,
	}


# ---------------------------------------------------------------------------
# 8. Training Mode Tools
# ---------------------------------------------------------------------------


func _check_training_tools() -> void:
	var arena := await _make_arena("dave", "karen", "training")
	_ok(arena.training and arena.auto_refill_meter and arena.show_frame_data,
			"Training arena defaults were wrong (training=%s meter=%s fd=%s)" % [
				arena.training, arena.auto_refill_meter, arena.show_frame_data])

	# 8a. Dummy AI behaviors: crouch, block (standing & vs low), jump.
	var ai_crouch := AIController.new(2, "dummy_crouch")
	var out_crouch := ai_crouch.decide(arena.p2, arena.p1)
	_ok(bool(out_crouch["crouch"]), "dummy_crouch did not output crouch=true")

	var ai_block := AIController.new(2, "dummy_block")
	arena.p1.state = Fighter.State.IDLE
	arena.p1._move_clear()
	var out_idle := ai_block.decide(arena.p2, arena.p1)
	_ok(not bool(out_idle["block"]), "dummy_block blocked while foe was idle")

	arena.p1.start_move("jab")
	var out_blk_high := ai_block.decide(arena.p2, arena.p1)
	_ok(bool(out_blk_high["block"]) and not bool(out_blk_high["crouch"]),
			"dummy_block did not stand-block high/mid attack (%s)" % str(out_blk_high))

	arena.p1.start_move("low")
	var out_blk_low := ai_block.decide(arena.p2, arena.p1)
	_ok(bool(out_blk_low["block"]) and bool(out_blk_low["crouch"]),
			"dummy_block did not crouch-block low attack (%s)" % str(out_blk_low))
	arena.p1._move_clear()
	arena.p1.state = Fighter.State.IDLE

	var ai_jump := AIController.new(2, "dummy_jump")
	var jump_ticks: Array[int] = []
	for t in 105:
		var out_j := ai_jump.decide(arena.p2, arena.p1)
		if bool(out_j["jump"]):
			jump_ticks.append(t)
	_ok(jump_ticks.size() >= 2,
			"dummy_jump did not output jump=true periodically (ticks=%s)" % str(jump_ticks))

	# 8b. auto_refill_meter refills P1 meter toward METER_MAX after idle ticks.
	arena.p1.meter = 0.0
	arena._meter_idle_ticks = 0
	arena.auto_refill_meter = true
	for _i in 90:
		arena._step()
	_ok(is_equal_approx(arena.p1.meter, CharacterDB.METER_MAX),
			"auto_refill_meter did not refill P1 meter (got %.1f)" % arena.p1.meter)

	arena.auto_refill_meter = false
	arena.p1.meter = 10.0
	arena._meter_idle_ticks = 0
	for _i in 60:
		arena._step()
	_ok(is_equal_approx(arena.p1.meter, 10.0),
			"meter refilled while auto_refill_meter was false (got %.1f)" % arena.p1.meter)
	arena.auto_refill_meter = true

	# 8c. Landing a hit in training populates arena.last_frame_data.
	_place(arena.p1, arena.p2, 600.0, 690.0)
	arena.last_frame_data = {}
	arena.router._press[0]["light"] = true
	var jab_info: Dictionary = arena.p1.data["moves"]["jab"]
	for _i in int(jab_info["startup"]) + 2:
		arena._step()
	var fd := arena.last_frame_data
	_ok(str(fd.get("move", "")) == "JAB"
			and int(fd.get("startup", -1)) == int(jab_info["startup"])
			and int(fd.get("active", -1)) == int(jab_info["active"])
			and int(fd.get("recovery", -1)) == int(jab_info["recovery"])
			and fd.has("advantage")
			and str(fd.get("outcome", "")) == "HIT",
			"Training hit did not populate expected last_frame_data (%s)" % str(fd))

	# 8d. P1 inputs populate arena.p1_input_history capped at 10 entries.
	arena.p1_input_history.clear()
	arena._last_input_sig = ""
	var held_actions := ["p1_left", "p1_right", "p1_down", "p1_block"]
	for step_i in 15:
		_release_fight_actions()
		Input.action_press(held_actions[step_i % held_actions.size()])
		arena._step()
	_release_fight_actions()
	_ok(arena.p1_input_history.size() == 10,
			"p1_input_history was not capped at 10 entries (got %d)" % arena.p1_input_history.size())

	# 8e. Pause menu in training shows DUMMY / METER / FRAME DATA buttons and updates arena state.
	arena.pause_menu.open()
	_ok(get_tree().paused and arena.pause_menu.visible, "Training pause menu did not open")
	var dummy_btn: Button = arena.pause_menu._dummy_button
	var meter_btn: Button = arena.pause_menu._meter_button
	var fd_btn: Button = arena.pause_menu._frame_data_button
	_ok(dummy_btn.visible and dummy_btn.text.begins_with("DUMMY:"),
			"Training pause menu missing visible DUMMY: button ('%s' vis=%s)" % [dummy_btn.text, dummy_btn.visible])
	_ok(meter_btn.visible and meter_btn.text.begins_with("METER:"),
			"Training pause menu missing visible METER: button ('%s' vis=%s)" % [meter_btn.text, meter_btn.visible])
	_ok(fd_btn.visible and fd_btn.text.begins_with("FRAME DATA:"),
			"Training pause menu missing visible FRAME DATA: button ('%s' vis=%s)" % [fd_btn.text, fd_btn.visible])

	dummy_btn.pressed.emit()
	_ok(arena.dummy_mode == "crouch" and arena.ai.behavior == "dummy_crouch",
			"Pressing DUMMY button did not cycle to crouch (%s / %s)" % [arena.dummy_mode, arena.ai.behavior])
	dummy_btn.pressed.emit()
	_ok(arena.dummy_mode == "block" and arena.ai.behavior == "dummy_block",
			"Pressing DUMMY button did not cycle to block (%s / %s)" % [arena.dummy_mode, arena.ai.behavior])
	dummy_btn.pressed.emit()
	_ok(arena.dummy_mode == "jump" and arena.ai.behavior == "dummy_jump",
			"Pressing DUMMY button did not cycle to jump (%s / %s)" % [arena.dummy_mode, arena.ai.behavior])
	dummy_btn.pressed.emit()
	_ok(arena.dummy_mode == "stand" and arena.ai.behavior == "dummy",
			"Pressing DUMMY button did not wrap back to stand (%s / %s)" % [arena.dummy_mode, arena.ai.behavior])

	meter_btn.pressed.emit()
	_ok(not arena.auto_refill_meter and meter_btn.text == "METER: NORMAL",
			"Pressing METER button did not toggle auto_refill_meter off (%s / '%s')" % [
				arena.auto_refill_meter, meter_btn.text])
	meter_btn.pressed.emit()
	_ok(arena.auto_refill_meter and meter_btn.text == "METER: AUTO-REFILL",
			"Pressing METER button did not toggle auto_refill_meter back on")

	fd_btn.pressed.emit()
	_ok(not arena.show_frame_data and fd_btn.text == "FRAME DATA: OFF",
			"Pressing FRAME DATA button did not toggle show_frame_data off (%s / '%s')" % [
				arena.show_frame_data, fd_btn.text])
	fd_btn.pressed.emit()
	_ok(arena.show_frame_data and fd_btn.text == "FRAME DATA: ON",
			"Pressing FRAME DATA button did not toggle show_frame_data back on")

	arena.pause_menu.close()
	_ok(not get_tree().paused, "Training pause menu did not unpause on close")
	arena.queue_free()
	await _frames(1)

	# Non-training pause menu must hide training-only buttons.
	var vs_arena := await _make_arena("dave", "karen", "versus")
	vs_arena.pause_menu.open()
	_ok(not vs_arena.pause_menu._dummy_button.visible
			and not vs_arena.pause_menu._meter_button.visible
			and not vs_arena.pause_menu._frame_data_button.visible,
			"Versus pause menu unexpectedly showed training buttons")
	vs_arena.pause_menu.close()
	vs_arena.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# 9. Options (Keybind Remapping, Shake Scale, Colorblind HUD) & Mouse Pickers
# ---------------------------------------------------------------------------


func _check_options_and_mouse_pickers() -> void:
	# 9a. Controls keybind remapping + persistence + reset.
	Controls.rebind_key("p1_light", KEY_J)
	_ok(_action_has_key("p1_light", KEY_J), "InputMap 'p1_light' did not accept KEY_J after rebind")
	_ok(not _action_has_key("p1_light", KEY_F), "InputMap 'p1_light' still contained KEY_F after rebind")
	_ok(Controls.key_label("p1_light") == "J",
			"Controls.key_label('p1_light') returned '%s', expected 'J'" % Controls.key_label("p1_light"))
	_ok(int(SaveData.settings.get("keybinds", {}).get("p1_light", 0)) == KEY_J,
			"SaveData.settings['keybinds']['p1_light'] was not KEY_J")

	SaveData.settings["keybinds"] = {}
	SaveData.load_game()
	_ok(int(SaveData.settings.get("keybinds", {}).get("p1_light", 0)) == KEY_J,
			"Keybind override did not persist across SaveData.load_game()")

	Controls.reset_keybinds()
	_ok(_action_has_key("p1_light", KEY_F) and not _action_has_key("p1_light", KEY_J),
			"Controls.reset_keybinds() did not restore KEY_F on 'p1_light'")
	_ok(Controls.key_label("p1_light") == "F",
			"Controls.key_label('p1_light') after reset was '%s', expected 'F'" % Controls.key_label("p1_light"))
	_ok((SaveData.settings.get("keybinds", {}) as Dictionary).is_empty(),
			"Controls.reset_keybinds() did not clear SaveData.settings['keybinds']")

	# 9b. shake_scale persistence + camera shake scaling, colorblind_hud + UITheme colors.
	SaveData.set_setting("shake_scale", 0.5)
	SaveData.settings["shake_scale"] = 1.0
	SaveData.load_game()
	_ok(is_equal_approx(float(SaveData.settings["shake_scale"]), 0.5),
			"shake_scale=0.5 did not persist across SaveData.load_game()")

	var shake_arena := await _make_arena("dave", "karen")
	shake_arena.shake = 10.0
	shake_arena._kick_dir = Vector2(1.0, 0.0)
	shake_arena._kick_time = 0.0
	SaveData.set_setting("shake_scale", 1.0)
	shake_arena._apply_camera(0.0)
	var full_offset := shake_arena.camera.offset.x
	SaveData.set_setting("shake_scale", 0.5)
	shake_arena._apply_camera(0.0)
	var half_offset := shake_arena.camera.offset.x
	_ok(is_equal_approx(full_offset, 10.0) and is_equal_approx(half_offset, 5.0),
			"shake_scale did not scale camera shake offset (full=%.1f half=%.1f)" % [full_offset, half_offset])
	shake_arena.queue_free()
	await _frames(1)

	SaveData.set_setting("colorblind_hud", true)
	_ok(UITheme.is_colorblind(), "UITheme.is_colorblind() was false after enabling colorblind_hud")
	_ok(UITheme.p1_color() == UITheme.CB_P1 and UITheme.p2_color() == UITheme.CB_P2,
			"UITheme p1/p2 colors did not switch to CB_P1/CB_P2")
	SaveData.set_setting("shake_scale", 1.0)
	SaveData.set_setting("colorblind_hud", false)
	_ok(not UITheme.is_colorblind()
			and UITheme.p1_color() == UITheme.P1 and UITheme.p2_color() == UITheme.P2,
			"Restoring colorblind_hud=false did not restore default P1/P2 colors")

	# 9c. options.tscn: keybind overlay + SCREEN SHAKE & COLORBLIND HUD toggles.
	var opts: Control = load("res://scenes/ui/options.tscn").instantiate()
	add_child(opts)
	await _frames(2)
	_ok(opts._keybind_overlay != null and opts._keybind_buttons.size() == 18,
			"options.tscn did not build 18 keybind overlay buttons (got %d)" % opts._keybind_buttons.size())
	opts._controls_button.pressed.emit()
	_ok(opts._keybind_overlay.visible, "CONTROLS button did not show keybind overlay")
	opts._keybind_buttons["p1_light"].pressed.emit()
	_ok(opts._capturing_action == "p1_light", "Clicking p1_light row did not enter key capture")
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = KEY_K
	key_ev.pressed = true
	opts._input(key_ev)
	_ok(opts._capturing_action == "" and Controls.key_label("p1_light") == "K",
			"Keybind overlay did not capture KEY_K (label='%s')" % Controls.key_label("p1_light"))
	opts._keybind_reset_button.pressed.emit()
	_ok(Controls.key_label("p1_light") == "F",
			"Keybind overlay RESET DEFAULTS did not restore KEY_F")
	opts._keybind_done_button.pressed.emit()
	_ok(not opts._keybind_overlay.visible, "Keybind overlay DONE did not hide overlay")

	var shake_row := _find_options_row(opts, "SCREEN SHAKE")
	var cb_row := _find_options_row(opts, "COLORBLIND HUD")
	_ok(shake_row != null and cb_row != null, "options.tscn missing SCREEN SHAKE or COLORBLIND HUD row")
	if shake_row != null:
		shake_row.pressed.emit()  # 100% -> OFF (0.0)
		_ok(is_equal_approx(float(SaveData.settings["shake_scale"]), 0.0),
				"SCREEN SHAKE click 1 did not set 0.0 (got %.2f)" % float(SaveData.settings["shake_scale"]))
		shake_row.pressed.emit()  # OFF -> 50% (0.5)
		_ok(is_equal_approx(float(SaveData.settings["shake_scale"]), 0.5),
				"SCREEN SHAKE click 2 did not set 0.5 (got %.2f)" % float(SaveData.settings["shake_scale"]))
		shake_row.pressed.emit()  # 50% -> 100% (1.0)
		_ok(is_equal_approx(float(SaveData.settings["shake_scale"]), 1.0),
				"SCREEN SHAKE click 3 did not restore 1.0 (got %.2f)" % float(SaveData.settings["shake_scale"]))
	if cb_row != null:
		cb_row.pressed.emit()
		_ok(UITheme.is_colorblind(), "COLORBLIND HUD toggle did not enable colorblind mode")
		cb_row.pressed.emit()
		_ok(not UITheme.is_colorblind(), "COLORBLIND HUD second toggle did not restore default mode")
	opts.queue_free()
	await _frames(2)

	# 9d. character_select.tscn mouse hover + click in versus mode.
	Game.mode = "versus"
	Game.p1_id = "dave"
	Game.p2_id = "karen"
	get_tree().change_scene_to_file(Game.CHAR_SELECT)
	await _frames(3)
	var cs_vs := get_tree().current_scene
	_ok(cs_vs != null and cs_vs.scene_file_path == Game.CHAR_SELECT,
			"character_select.tscn did not load for versus mouse picker test")
	if cs_vs != null and cs_vs.scene_file_path == Game.CHAR_SELECT:
		var card2: Panel = cs_vs.cards[2]["panel"]
		var card3: Panel = cs_vs.cards[3]["panel"]
		await _mouse_hover(card2)
		_ok(int(cs_vs.index[0]) == 2 and not bool(cs_vs.locked[0]),
				"Versus mouse hover on card 2 did not move P1 index (index=%s locked=%s)" % [
					str(cs_vs.index), str(cs_vs.locked)])
		await _mouse_left_click(card2)
		_ok(int(cs_vs.index[0]) == 2 and bool(cs_vs.locked[0]) and not bool(cs_vs.locked[1]),
				"Versus mouse click on card 2 did not lock P1 (index=%s locked=%s)" % [
					str(cs_vs.index), str(cs_vs.locked)])
		await _mouse_hover(card3)
		_ok(int(cs_vs.index[1]) == 3 and not bool(cs_vs.locked[1]),
				"Versus mouse hover on card 3 did not move P2 index (index=%s)" % str(cs_vs.index))
		await _mouse_left_click(card3)
		await _frames(3)
		_ok(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == Game.STAGE_SELECT,
				"Versus P2 mouse click did not confirm to stage select")
		_ok(Game.p1_id == "tony" and Game.p2_id == "chad",
				"Versus mouse picks were wrong (p1=%s p2=%s)" % [Game.p1_id, Game.p2_id])

	# 9e. character_select.tscn mouse hover + click in single-player (training) mode.
	Game.mode = "training"
	Game.p1_id = "dave"
	Game.p2_id = "karen"
	get_tree().change_scene_to_file(Game.CHAR_SELECT)
	await _frames(3)
	var cs_sp := get_tree().current_scene
	_ok(cs_sp != null and cs_sp.scene_file_path == Game.CHAR_SELECT,
			"character_select.tscn did not load for single-player mouse picker test")
	if cs_sp != null and cs_sp.scene_file_path == Game.CHAR_SELECT:
		var card1: Panel = cs_sp.cards[1]["panel"]
		await _mouse_hover(card1)
		_ok(int(cs_sp.index[0]) == 1 and int(cs_sp.index[1]) != 1,
				"Single-player hover on card 1 did not update P1 or separate CPU (index=%s)" % str(cs_sp.index))
		await _mouse_left_click(card1)
		await _frames(3)
		_ok(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == Game.STAGE_SELECT,
				"Single-player mouse click did not confirm to stage select")
		_ok(Game.p1_id == "karen",
				"Single-player mouse pick was '%s', expected 'karen'" % Game.p1_id)

	# 9f. stage_select.tscn mouse hover + left-click updates index and confirms cleanly.
	Game.mode = "versus"
	Game.p1_id = "dave"
	Game.p2_id = "karen"
	Game.stage_id = "breakroom"
	get_tree().change_scene_to_file(Game.STAGE_SELECT)
	await _frames(3)
	var ss := get_tree().current_scene
	_ok(ss != null and ss.scene_file_path == Game.STAGE_SELECT,
			"stage_select.tscn did not load for mouse picker test")
	if ss != null and ss.scene_file_path == Game.STAGE_SELECT:
		var stage_card: Panel = ss.cards[2]["panel"]
		await _mouse_hover(stage_card)
		_ok(int(ss.index) == 2, "Stage mouse hover did not update index to 2 (got %d)" % int(ss.index))
		await _mouse_left_click(stage_card)
		await _frames(4)
		_ok(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == Game.ARENA,
				"Stage mouse click did not confirm into arena")
		_ok(Game.stage_id == StageDB.ORDER[2],
				"Stage mouse pick was '%s', expected '%s'" % [Game.stage_id, StageDB.ORDER[2]])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_arena(p1_id: String, p2_id: String, mode := "versus") -> Arena:
	Game.match_config = {
		"mode": mode, "p1": p1_id, "p2": p2_id, "stage": "breakroom",
		"p2_is_ai": false, "difficulty": 2,
		"round_wins_needed": Game.rounds_to_win(mode),
	}
	var arena: Arena = load("res://scenes/fight/arena.tscn").instantiate()
	arena.auto_report = false
	add_child(arena)
	await _frames(1)
	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	arena.slowmo = 0
	arena._accum = 0.0
	arena.p1.state = Fighter.State.IDLE
	arena.p2.state = Fighter.State.IDLE
	return arena


func _place(left: Fighter, right: Fighter, x1 := 600.0, x2 := 700.0) -> void:
	left.pos = Vector2(x1, CharacterDB.GROUND_Y)
	right.pos = Vector2(x2, CharacterDB.GROUND_Y)
	left.position = left.pos
	right.position = right.pos
	left.facing = 1 if right.pos.x >= left.pos.x else -1
	right.facing = -left.facing


func _prime(fighter: Fighter, move_id: String) -> void:
	if move_id == "special":
		fighter.meter = CharacterDB.METER_MAX
	fighter.start_move(move_id)
	fighter.move_tick = int(fighter.move["startup"])


func _inp(dir := 0, jump := false, crouch := false, light := false, heavy := false,
		special := false, block := false, throw_btn := false) -> Dictionary:
	return {
		"dir": dir,
		"jump": jump,
		"crouch": crouch,
		"light": light,
		"heavy": heavy,
		"special": special,
		"block": block,
		"throw": throw_btn,
	}


func _release_fight_actions() -> void:
	for p in ["p1", "p2"]:
		for suffix in ["left", "right", "up", "down", "light", "heavy", "special", "block", "throw"]:
			var act := "%s_%s" % [p, suffix]
			if Input.is_action_pressed(act):
				Input.action_release(act)


func _action_has_key(action: String, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.physical_keycode == key or k.keycode == key:
				return true
	return false


func _find_options_row(opts: Control, title: String) -> Button:
	for b in opts._rows:
		if str(b.get_meta("title", "")) == title:
			return b
	return null


func _mouse_hover(ctrl: Control) -> void:
	var vp := ctrl.get_viewport()
	var pos := ctrl.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	vp.push_input(motion, true)
	await _frames(2)


func _mouse_left_click(ctrl: Control) -> void:
	var vp := ctrl.get_viewport()
	var pos := ctrl.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	vp.push_input(down, true)
	await _frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	vp.push_input(up, true)
	await _frames(1)


func _goto_blank() -> void:
	var packed := PackedScene.new()
	var blank := Node.new()
	blank.name = "Blank"
	var err := packed.pack(blank)
	blank.free()
	_ok(err == OK, "could not pack blank scene")
	get_tree().change_scene_to_packed(packed)
	await _frames(2)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _report() -> void:
	var code := 0
	if _failures.is_empty():
		print("FEATURES PASS: %d checks" % _checks)
	else:
		code = 1
		printerr("FEATURES FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
	Harness.quiet_quit(self, code)
