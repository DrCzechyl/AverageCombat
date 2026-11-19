extends Node

## Headless combat-resolution regressions. Run with:
##   godot --headless --path . res://tests/combat.tscn
##
## Covers round-lock projectile resolution, symmetric melee trades,
## match-damage accounting, hitstop exchanges, the FIGHT cue, and F5.
## Smoke, flow, and the runner live elsewhere.

const Harness := preload("res://tests/harness.gd")

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame
	SaveData.settings["hitstop"] = true
	await _check_outcome_lock()
	await _check_symmetric_trades()
	await _check_match_damage()
	await _check_hitstop_exchange()
	await _check_fight_cue()
	await _check_reset_is_training_only()
	_report()


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: ", message)


func _make_arena(p1_id: String, p2_id: String) -> Arena:
	Game.match_config = {
		"mode": "versus", "p1": p1_id, "p2": p2_id, "stage": "breakroom",
		"p2_is_ai": false, "difficulty": 2, "round_wins_needed": 2,
	}
	var arena: Arena = load("res://scenes/fight/arena.tscn").instantiate()
	arena.auto_report = false
	add_child(arena)
	await get_tree().process_frame
	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	arena.slowmo = 0
	return arena


func _place(left: Fighter, right: Fighter, x1 := 600.0, x2 := 700.0) -> void:
	left.pos = Vector2(x1, CharacterDB.GROUND_Y)
	right.pos = Vector2(x2, CharacterDB.GROUND_Y)
	left.position = left.pos
	right.position = right.pos


func _prime(fighter: Fighter, move_id: String) -> void:
	if move_id == "special":
		fighter.meter = CharacterDB.METER_MAX
	fighter.start_move(move_id)
	fighter.move_tick = int(fighter.move["startup"])


func _nominal(fighter: Fighter, move_id: String) -> float:
	var move: Dictionary = fighter.data["moves"][move_id]
	return float(move["damage"]) * float(fighter.data["build"]["damage_scale"])


func _spawn_clipboard(arena: Arena, owner: Fighter, at: Vector2) -> Projectile:
	owner.meter = CharacterDB.METER_MAX
	owner.start_move("special")
	var proj := Projectile.new()
	proj.setup(owner, owner.move["projectile"])
	proj.position = at
	arena.projectiles_root.add_child(proj)
	arena.projectiles.append(proj)
	return proj


func _check_outcome_lock() -> void:
	# Dave is ahead on ratio but low enough that a 95-damage clipboard would KO
	# him. TIME must freeze that result while the clipboard keeps moving.
	var arena := await _make_arena("karen", "dave")
	_place(arena.p1, arena.p2, 400.0, 900.0)
	var proj := _spawn_clipboard(arena, arena.p1, Vector2(850, CharacterDB.GROUND_Y - 196.0))
	var start_x := proj.position.x
	arena.p1.health = 50.0
	arena.p2.health = 90.0
	arena.p1.meter = 20.0
	arena.p2.meter = 0.0
	arena.damage_done = [0.0, 0.0]
	arena.combo = [0, 0]
	arena._time_over()
	_ok(arena.phase == Arena.Phase.KO, "TIME did not lock the round")
	_ok(arena.ko_winner == 1, "TIME should announce Dave, the higher health ratio")
	_ok(arena.announce_text == "TIME", "TIME announcement was replaced")

	arena._step()
	_ok(proj in arena.projectiles, "clipboard was removed on the locked frame")
	_ok(proj.position.x > start_x, "clipboard did not keep moving after TIME")
	_ok(is_equal_approx(arena.p2.health, 90.0),
			"clipboard damaged the announced winner after TIME (health %.1f)" % arena.p2.health)
	_ok(not arena.p2.knockout, "clipboard KO'd the announced winner after TIME")
	_ok(arena.ko_winner == 1, "ko_winner changed after TIME")
	_ok(is_equal_approx(arena.damage_done[0], 0.0) and is_equal_approx(arena.damage_done[1], 0.0),
			"match damage changed after TIME")
	_ok(arena.combo[0] == 0 and arena.combo[1] == 0, "combo stats changed after TIME")
	_ok(is_equal_approx(arena.p1.meter, 20.0) and is_equal_approx(arena.p2.meter, 0.0),
			"meter changed when the locked clipboard advanced")

	var guard := 0
	while arena.round_wins[1] == 0 and guard < 200:
		arena._step()
		guard += 1
	_ok(arena.round_wins[0] == 0 and arena.round_wins[1] == 1,
			"TIME round was not awarded to the locked winner")
	_ok(not arena.p2.knockout and arena.p2.state == Fighter.State.WIN,
			"announced winner could not celebrate")
	_ok(is_equal_approx(arena.p2.health, 90.0), "winner health changed before the next round")
	_ok(is_equal_approx(arena.p1.meter, 20.0),
			"clipboard granted meter while the round was locked")
	_ok(is_equal_approx(arena.damage_done[0], 0.0),
			"match damage accumulated after the outcome locked")
	arena.queue_free()
	await get_tree().process_frame

	# A whiffing normal and an expiring clipboard must not mint meter either.
	var locked := await _make_arena("dave", "karen")
	locked.phase = Arena.Phase.KO
	locked.ko_winner = 0
	locked.phase_ticks = 40
	locked.slowmo = 0
	locked.p1.start_move("jab")
	var jab: Dictionary = locked.p1.move
	locked.p1.move_tick = int(jab["startup"]) + int(jab["active"]) - 1
	locked.p1.meter = 17.0
	var miss := _spawn_clipboard(locked, locked.p2, Vector2(200, CharacterDB.GROUND_Y - 196.0))
	miss.life = Arena.TICK
	miss.position = Vector2(200, CharacterDB.GROUND_Y - 196.0)
	locked.p2.meter = 11.0
	locked.p1.meter = 17.0
	locked._step()
	_ok(is_equal_approx(locked.p1.meter, 17.0),
			"whiffing jab granted meter after the outcome locked")
	_ok(is_equal_approx(locked.p2.meter, 11.0),
			"expired clipboard granted meter after the outcome locked")
	_ok(miss not in locked.projectiles, "expired clipboard was not retired visually")
	_ok(is_equal_approx(locked.p1.health, float(locked.p1.data["build"]["health"])),
			"locked-phase presentation changed health")
	locked.queue_free()
	await get_tree().process_frame


func _check_symmetric_trades() -> void:
	var lethal := await _make_arena("dave", "karen")
	_place(lethal.p1, lethal.p2)
	lethal.p1.health = 1.0
	lethal.p2.health = 1.0
	lethal.p1.start_move("jab")
	lethal.p2.start_move("jab")
	var hit_tick := 0
	for i in 12:
		lethal._step()
		hit_tick = i + 1
		if lethal.p1.knockout or lethal.p2.knockout:
			break
	_ok(hit_tick == int(lethal.p1.data["moves"]["jab"]["startup"]),
			"equal jabs did not meet on the shared startup frame (tick %d)" % hit_tick)
	_ok(lethal.p1.knockout and lethal.p2.knockout,
			"overlapping lethal jabs did not KO both fighters")
	_ok(is_equal_approx(lethal.p1.health, 0.0) and is_equal_approx(lethal.p2.health, 0.0),
			"a traded KO left health on the bar")
	_ok(lethal.ko_winner == -1, "equal lethal jabs awarded a sole KO to P1")
	_ok(lethal.announce_text == "K.O." and lethal.announce_sub == "DOUBLE KO",
			"double KO was not announced")
	_ok(lethal.p1.vel.x < 0.0 and lethal.p2.vel.x > 0.0,
			"traded KO knockback did not follow facing at contact")
	lethal.queue_free()
	await get_tree().process_frame

	var final_tick := await _make_arena("dave", "dave")
	_place(final_tick.p1, final_tick.p2)
	final_tick.p1.health = 1.0
	final_tick.p2.health = 1.0
	final_tick.round_time = 1.0
	final_tick.time_accum = 1.0 - Arena.TICK * 0.5
	for fighter in [final_tick.p1, final_tick.p2]:
		_prime(fighter, "jab")
		fighter.move_tick -= 1
	SaveData.settings["hitstop"] = false
	final_tick._step()
	SaveData.settings["hitstop"] = true
	_ok(final_tick.announce_text == "K.O." and final_tick.announce_sub == "DOUBLE KO",
			"timer overrode simultaneous lethal hits on the last playable tick")
	final_tick.queue_free()
	await get_tree().process_frame

	var trade := await _make_arena("dave", "karen")
	_place(trade.p1, trade.p2)
	var hp1: float = trade.p1.health
	var hp2: float = trade.p2.health
	trade.p1.start_move("jab")
	trade.p2.start_move("jab")
	for i in 12:
		trade._step()
		if trade.p1.state == Fighter.State.HITSTUN and trade.p2.state == Fighter.State.HITSTUN:
			break
	var dave_jab := _nominal(trade.p1, "jab")
	var karen_jab := _nominal(trade.p2, "jab")
	_ok(trade.p1.state == Fighter.State.HITSTUN and trade.p2.state == Fighter.State.HITSTUN,
			"a jab trade landed on only one side")
	_ok(is_equal_approx(hp1 - trade.p1.health, karen_jab),
			"P1 did not take P2's jab damage in a trade")
	_ok(is_equal_approx(hp2 - trade.p2.health, dave_jab),
			"P2 did not take P1's jab damage in a trade")
	_ok(is_equal_approx(trade.damage_done[0], dave_jab)
			and is_equal_approx(trade.damage_done[1], karen_jab),
			"trade match damage did not match health lost")
	_ok(trade.p1.vel.x < 0.0 and trade.p2.vel.x > 0.0,
			"trade knockback did not use each attacker's facing at contact")
	_ok(trade.ko_winner == -1 and trade.phase == Arena.Phase.FIGHT,
			"a nonlethal trade ended the round")
	trade.queue_free()
	await get_tree().process_frame

	var one := await _make_arena("dave", "karen")
	_place(one.p1, one.p2)
	var one_hp: float = one.p2.health
	one.p1.start_move("jab")
	for i in 12:
		one._step()
		if one.p2.health < one_hp:
			break
	_ok(one.p2.state == Fighter.State.HITSTUN and one.p1.state == Fighter.State.ATTACK,
			"a one-sided jab did not hit only the defender")
	_ok(is_equal_approx(one_hp - one.p2.health, _nominal(one.p1, "jab")),
			"a one-sided jab dealt the wrong damage")
	_ok(is_equal_approx(one.p1.health, float(one.p1.data["build"]["health"])),
			"a one-sided jab damaged the attacker")
	_ok(one.p2.vel.x > 0.0, "one-sided jab knockback ignored P1 facing")
	_ok(one.combo[0] == 1 and one.combo[1] == 0, "one-sided jab combo was attributed wrong")
	one.queue_free()
	await get_tree().process_frame

	await _check_armor_trade(true)
	await _check_armor_trade(false)


func _check_armor_trade(armored_is_p1: bool) -> void:
	var arena := await _make_arena(
			"tony" if armored_is_p1 else "dave",
			"dave" if armored_is_p1 else "tony")
	_place(arena.p1, arena.p2)
	var tony: Fighter = arena.p1 if armored_is_p1 else arena.p2
	var dave: Fighter = arena.p2 if armored_is_p1 else arena.p1
	tony.health = 400.0
	dave.health = 1000.0
	_prime(tony, "special")
	_prime(dave, "jab")
	var tony_index := 0 if armored_is_p1 else 1
	var dave_index := 1 - tony_index
	arena._resolve_melee()
	var jab := _nominal(dave, "jab")
	var special := _nominal(tony, "special")
	_ok(bool(tony.move.get("armor", false)) and tony.move_armor_used
			and tony.state == Fighter.State.ATTACK and not tony.knockout,
			"armored fighter did not absorb and return a same-frame jab (P%d)" % (tony_index + 1))
	_ok(is_equal_approx(400.0 - tony.health, jab),
			"armor trade removed the wrong health from Tony (P%d)" % (tony_index + 1))
	_ok(dave.state == Fighter.State.HITSTUN and is_equal_approx(1000.0 - dave.health, special),
			"armored special did not hit on the same frame (P%d)" % (tony_index + 1))
	_ok(is_equal_approx(arena.damage_done[tony_index], special)
			and is_equal_approx(arena.damage_done[dave_index], jab),
			"armor trade match damage was not health lost on each side")
	var dave_dir := 1.0 if tony.facing > 0 else -1.0
	_ok(dave.vel.x * dave_dir > 0.0 and absf(tony.vel.x) < 0.01,
			"armor trade did not keep contact direction (knockback on Dave, armor holds Tony)")
	arena.queue_free()
	await get_tree().process_frame

	var lethal := await _make_arena(
			"tony" if armored_is_p1 else "dave",
			"dave" if armored_is_p1 else "tony")
	_place(lethal.p1, lethal.p2)
	var ltony: Fighter = lethal.p1 if armored_is_p1 else lethal.p2
	var ldave: Fighter = lethal.p2 if armored_is_p1 else lethal.p1
	ltony.health = 1.0
	ldave.health = 1.0
	_prime(ltony, "special")
	_prime(ldave, "jab")
	lethal._resolve_melee()
	lethal._check_ko()
	_ok(ltony.knockout and ldave.knockout,
			"lethal armor trade did not KO both fighters (armored P%d)" % (tony_index + 1))
	_ok(lethal.ko_winner == -1, "lethal armor trade awarded a sole KO")
	_ok(ldave.vel.x * (1.0 if ltony.facing > 0 else -1.0) > 0.0,
			"lethal armor trade lost the special's contact direction")
	lethal.queue_free()
	await get_tree().process_frame


func _check_match_damage() -> void:
	var blocked := await _make_arena("dave", "karen")
	_place(blocked.p1, blocked.p2)
	_prime(blocked.p1, "heavy")
	blocked.p2.blocking = true
	var before: float = blocked.p2.health
	var nominal := _nominal(blocked.p1, "heavy")
	var chip := nominal * float(blocked.p1.move["chip"])
	blocked._resolve_melee()
	var lost := before - blocked.p2.health
	_ok(blocked.p2.state == Fighter.State.BLOCKSTUN and blocked.combo[0] == 0
			and is_equal_approx(blocked.combo_damage[0], 0.0),
			"nonlethal chip changed combo feedback")
	_ok(chip > 0.0 and chip < nominal and is_equal_approx(lost, chip),
			"blocked heavy did not deal chip (lost %.2f, chip %.2f)" % [lost, chip])
	_ok(is_equal_approx(blocked.damage_done[0], chip),
			"match damage omitted nonlethal chip (recorded %.2f)" % blocked.damage_done[0])
	_ok(blocked.p1.hitstop == 4 and blocked.p2.hitstop == 4
			and is_equal_approx(blocked.shake, 2.5),
			"block hitstop or shake changed")
	var blocked_gain := float(blocked.p1.move["meter_gain"]) * 0.4
	_ok(is_equal_approx(blocked.p1.meter, blocked_gain),
			"blocked hit did not grant partial meter")
	blocked.queue_free()
	await get_tree().process_frame

	var over := await _make_arena("dave", "karen")
	_place(over.p1, over.p2)
	_prime(over.p1, "heavy")
	over.p2.health = 1.0
	var heavy := _nominal(over.p1, "heavy")
	over._resolve_melee()
	_ok(over.p2.knockout and is_equal_approx(over.p2.health, 0.0),
			"overkill heavy did not KO")
	_ok(is_equal_approx(over.damage_done[0], 1.0),
			"match damage counted overkill (recorded %.2f, 1 HP left)" % over.damage_done[0])
	_ok(over.combo[0] == 1 and is_equal_approx(over.combo_damage[0], heavy),
			"overkill changed combo damage feedback")
	_ok(over.p1.hitstop == 9 and over.p2.hitstop == 9,
			"overkill changed heavy hitstop")
	_ok(is_equal_approx(over.shake, 5.0 + minf(6.0, heavy * 0.045)),
			"overkill changed hit shake")
	_ok(over.p2.vel.x > 0.0, "overkill knockback ignored facing at contact")
	over.queue_free()
	await get_tree().process_frame

	var proj_arena := await _make_arena("karen", "dave")
	_place(proj_arena.p1, proj_arena.p2, 400.0, 900.0)
	var clip := _spawn_clipboard(proj_arena, proj_arena.p1,
			Vector2(proj_arena.p2.pos.x, CharacterDB.GROUND_Y - 196.0))
	clip.speed = 0.0
	proj_arena.p2.blocking = true
	proj_arena.p1.meter = 0.0
	var proj_before: float = proj_arena.p2.health
	proj_arena._update_projectiles()
	var proj_chip := 95.0 * 0.12
	_ok(proj_arena.p2.state == Fighter.State.BLOCKSTUN and proj_arena.combo[0] == 0,
			"blocked clipboard changed combo feedback")
	_ok(is_equal_approx(proj_before - proj_arena.p2.health, proj_chip)
			and is_equal_approx(proj_arena.damage_done[0], proj_chip),
			"blocked clipboard match damage was not chip")
	proj_arena.queue_free()
	await get_tree().process_frame

	var kill_clip := await _make_arena("karen", "dave")
	_place(kill_clip.p1, kill_clip.p2, 400.0, 900.0)
	var finisher := _spawn_clipboard(kill_clip, kill_clip.p1,
			Vector2(kill_clip.p2.pos.x, CharacterDB.GROUND_Y - 196.0))
	finisher.speed = 0.0
	kill_clip.p2.health = 1.0
	kill_clip._update_projectiles()
	_ok(kill_clip.p2.knockout and is_equal_approx(kill_clip.damage_done[0], 1.0),
			"clipboard match damage counted overkill instead of remaining HP")
	_ok(kill_clip.combo[0] == 1 and is_equal_approx(kill_clip.combo_damage[0], 95.0),
			"clipboard overkill changed combo feedback")
	_ok(kill_clip.p2.vel.x > 0.0, "clipboard knockback ignored facing at contact")
	kill_clip.queue_free()
	await get_tree().process_frame


func _check_hitstop_exchange() -> void:
	# 72px is the closest the bodies can stand. Karen's clipboard leaves her
	# hand on the same tick Dave's jab connects. Hitstop must not turn that
	# trade into a Dave win.
	for hitstop_on in [false, true]:
		SaveData.settings["hitstop"] = hitstop_on
		var arena := await _make_arena("dave", "karen")
		_place(arena.p1, arena.p2, 600.0, 672.0)
		arena.p1.health = 1.0
		arena.p2.health = 1.0
		_prime(arena.p1, "jab")
		arena.p1.move_tick -= 1
		_prime(arena.p2, "special")
		arena.p2.move_tick -= 1
		arena.damage_done = [0.0, 0.0]
		arena._step()
		var label := "on" if hitstop_on else "off"
		_ok(arena.p1.knockout and arena.p2.knockout,
				"lethal jab/clipboard at 72px did not KO both with hitstop %s" % label)
		_ok(is_equal_approx(arena.p1.health, 0.0) and is_equal_approx(arena.p2.health, 0.0),
				"lethal jab/clipboard at 72px left health with hitstop %s" % label)
		_ok(arena.ko_winner == -1 and arena.phase == Arena.Phase.KO,
				"lethal jab/clipboard at 72px awarded a sole winner with hitstop %s" % label)
		_ok(arena.announce_text == "K.O." and arena.announce_sub == "DOUBLE KO",
				"lethal jab/clipboard at 72px was not a double KO with hitstop %s (%s / %s)" % [label, arena.announce_text, arena.announce_sub])
		_ok(is_equal_approx(arena.damage_done[0], 1.0) and is_equal_approx(arena.damage_done[1], 1.0),
				"lethal jab/clipboard match damage was not remaining HP with hitstop %s" % label)
		if hitstop_on:
			_ok(arena.p1.hitstop == 9 and arena.p2.hitstop == 9,
					"same-tick trade stored hitstop %d/%d for later ticks" % [arena.p1.hitstop, arena.p2.hitstop])
		else:
			_ok(arena.p1.hitstop == 0 and arena.p2.hitstop == 0,
					"hitstop off still froze the jab/clipboard trade")
		arena.queue_free()
		await get_tree().process_frame

	var double_contact := await _make_arena("karen", "dave")
	_place(double_contact.p1, double_contact.p2, 600.0, 672.0)
	double_contact.p2.health = 1.0
	var incoming := _spawn_clipboard(double_contact, double_contact.p1,
			Vector2(660.0, CharacterDB.GROUND_Y - 158.0))
	_prime(double_contact.p1, "jab")
	double_contact.p1.move_tick -= 1
	double_contact._step()
	_ok(double_contact.p2.knockout and double_contact.best_combo[0] == 1,
			"a second same-tick contact counted as a hit on a defeated fighter")
	_ok(incoming not in double_contact.projectiles,
			"the same-tick projectile contact was not retired")
	double_contact.queue_free()
	await get_tree().process_frame

	# A tick that is already frozen does not move or connect a clipboard.
	# The next open tick does. Leftover hitstop after K.O. still lets it travel.
	SaveData.settings["hitstop"] = true
	var held := await _make_arena("karen", "dave")
	_place(held.p1, held.p2, 400.0, 900.0)
	var clip := _spawn_clipboard(held, held.p1, Vector2(held.p2.pos.x, CharacterDB.GROUND_Y - 196.0))
	var start_x := clip.position.x
	var hp := held.p2.health
	held.p1.hitstop = 1
	held.p2.hitstop = 1
	held._step()
	_ok(clip in held.projectiles and is_equal_approx(clip.position.x, start_x),
			"frozen tick advanced or removed the clipboard")
	_ok(is_equal_approx(held.p2.health, hp) and not held.p2.knockout and held.phase == Arena.Phase.FIGHT,
			"frozen tick resolved an overlapping clipboard")
	_ok(held.p1.hitstop == 0 and held.p2.hitstop == 0,
			"the last point of hitstop did not finish counting down")
	held._step()
	_ok(held.p2.health < hp and clip not in held.projectiles,
			"clipboard did not connect on the first tick after hitstop")
	held.queue_free()
	await get_tree().process_frame

	var ko := await _make_arena("karen", "dave")
	_place(ko.p1, ko.p2, 400.0, 900.0)
	var shown := _spawn_clipboard(ko, ko.p1, Vector2(ko.p2.pos.x, CharacterDB.GROUND_Y - 196.0))
	var shown_x := shown.position.x
	ko.phase = Arena.Phase.KO
	ko.phase_ticks = 40
	ko.slowmo = 0
	ko.ko_winner = 1
	ko.p1.hitstop = 8
	ko.p2.hitstop = 8
	ko.p2.health = 90.0
	ko._step()
	_ok(shown in ko.projectiles and shown.position.x > shown_x,
			"KO presentation froze the clipboard during hitstop")
	_ok(is_equal_approx(ko.p2.health, 90.0) and not ko.p2.knockout and ko.ko_winner == 1,
			"KO presentation resolved a clipboard during hitstop")
	ko.queue_free()
	await get_tree().process_frame


func _check_fight_cue() -> void:
	var arena := await _make_arena("dave", "karen")
	arena.phase = Arena.Phase.INTRO
	arena.phase_ticks = 81
	arena.announce_text = "ROUND 1"
	arena.announce_ticks = 40
	_stop_sfx()
	arena._step_intro()
	_ok(arena.phase == Arena.Phase.INTRO and arena.phase_ticks == 80,
			"intro reached FIGHT before the cue")
	_ok(arena.announce_text == "ROUND 1" and not _bell_playing(),
			"FIGHT cue fired while the round was still in the intro")
	arena.phase_ticks = 1
	arena._step_intro()
	_ok(arena.phase == Arena.Phase.FIGHT and arena.phase_ticks == 0,
			"FIGHT cue did not unlock controls")
	_ok(arena.announce_text == "FIGHT!" and arena.announce_ticks == 60 and _bell_playing(),
			"bell and FIGHT did not land on the tick the phase became FIGHT")
	arena.queue_free()
	await get_tree().process_frame

	var reset := await _make_arena("dave", "karen")
	reset.training = true
	reset.p1.meter = 40.0
	reset.p2.meter = 15.0
	_stop_sfx()
	reset._training_reset()
	_ok(reset.phase == Arena.Phase.FIGHT and reset.announce_text == "RESET"
			and reset.announce_ticks == 40,
			"training reset lost the RESET cue")
	_ok(not _bell_playing(), "training reset played the fight bell")
	_ok(is_equal_approx(reset.p1.meter, 40.0) and is_equal_approx(reset.p2.meter, 15.0),
			"training reset cleared meter")
	reset.queue_free()
	await get_tree().process_frame


func _check_reset_is_training_only() -> void:
	var arena := await _make_arena("dave", "karen")
	arena.training = false
	arena.round_number = 2
	arena.round_wins = [1, 0]
	arena.phase = Arena.Phase.KO
	arena.phase_ticks = 40
	arena.ko_winner = 0
	arena.p1.health = 12.0
	arena.p2.health = 0.0
	arena.announce_text = "K.O."
	arena.announce_sub = "DAVE WINS THE ROUND"
	_press_reset(arena)
	_ok(arena.phase == Arena.Phase.KO and arena.ko_winner == 0 and arena.phase_ticks == 40,
			"F5 reopened a decided round")
	_ok(arena.round_number == 2 and arena.round_wins[0] == 1 and arena.round_wins[1] == 0,
			"F5 changed the score of a decided round")
	_ok(is_equal_approx(arena.p1.health, 12.0) and arena.announce_text == "K.O.",
			"F5 restarted fighters after the round was decided")

	arena.phase = Arena.Phase.ROUND_END
	arena.phase_ticks = 25
	_press_reset(arena)
	_ok(arena.phase == Arena.Phase.ROUND_END and arena.phase_ticks == 25 and arena.round_number == 2,
			"F5 reopened a round that was already awarded")

	arena.phase = Arena.Phase.MATCH_END
	arena.phase_ticks = 30
	arena.finished = false
	arena.round_wins = [2, 0]
	arena.announce_text = "DAVE WINS"
	_press_reset(arena)
	_ok(arena.phase == Arena.Phase.MATCH_END and not arena.finished
			and arena.round_wins[0] == 2 and arena.round_wins[1] == 0,
			"F5 reopened a decided match")
	_ok(arena.announce_text == "DAVE WINS" and arena.round_number == 2,
			"F5 restarted a finished match")

	arena.phase = Arena.Phase.FIGHT
	arena.phase_ticks = 0
	arena.round_time = 40.0
	arena.p1.health = 80.0
	_press_reset(arena)
	_ok(arena.phase == Arena.Phase.FIGHT and is_equal_approx(arena.round_time, 40.0)
			and is_equal_approx(arena.p1.health, 80.0) and arena.round_number == 2,
			"F5 reset a competitive round that was still being fought")

	arena.training = true
	arena.phase = Arena.Phase.KO
	arena.phase_ticks = 10
	arena.ko_winner = 1
	arena.finished = false
	arena.p1.health = 80.0
	arena.p2.health = 0.0
	arena.p1.meter = 33.0
	_press_reset(arena)
	_ok(arena.phase == Arena.Phase.FIGHT and arena.announce_text == "RESET",
			"training F5 did not reset into FIGHT with the RESET cue")
	_ok(is_equal_approx(arena.p1.health, float(arena.p1.data["build"]["health"]))
			and is_equal_approx(arena.p2.health, float(arena.p2.data["build"]["health"])),
			"training F5 did not heal both fighters")
	_ok(is_equal_approx(arena.p1.meter, 33.0), "training F5 cleared meter")
	_ok(arena.round_wins[0] == 2 and arena.round_number == 2,
			"training F5 changed the match score")
	arena.queue_free()
	await get_tree().process_frame


func _press_reset(arena: Arena) -> void:
	var event := InputEventAction.new()
	event.action = "reset_round"
	event.pressed = true
	arena._unhandled_input(event)


func _stop_sfx() -> void:
	if not is_instance_valid(Sfx):
		return
	for child in Sfx.get_children():
		if child is AudioStreamPlayer:
			child.stop()


func _bell_playing() -> bool:
	if not is_instance_valid(Sfx):
		return false
	for child in Sfx.get_children():
		if child is AudioStreamPlayer and child.playing and child.stream != null:
			if str(child.stream.resource_path).ends_with("bell.wav"):
				return true
	return false


func _report() -> void:
	var code := 0
	if _failures.is_empty():
		print("COMBAT PASS: %d checks" % _checks)
	else:
		code = 1
		printerr("COMBAT FAIL: %d of %d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - ", failure)
	Harness.quiet_quit(self, code)
