class_name Arena
extends Node2D

## Owns the match: fixed 60 Hz simulation, hit resolution, rounds and rules.
## The rest of the project only talks to it through Game.match_config and the
## match_finished signal.

signal match_finished(result: Dictionary)
signal round_finished(winner: int)

enum Phase { INTRO, FIGHT, KO, ROUND_END, MATCH_END }

const TICK := 1.0 / 60.0
const FIGHTER_SCENE := preload("res://scenes/fight/fighter.tscn")

const INTRO_TICKS := 200
const KO_TICKS := 140
const ROUND_END_TICKS := 150
const MATCH_END_TICKS := 180
const ROUND_TIME := 99.0

@onready var bg: Sprite2D = $Background
@onready var fighters_root: Node2D = $Fighters
@onready var projectiles_root: Node2D = $Projectiles
@onready var fx_root: Node2D = $FX
@onready var camera: Camera2D = $Camera
@onready var hud: FightHud = $HudLayer/Hud
@onready var pause_menu: PauseMenu = $PauseLayer/Pause

var cfg: Dictionary = {}
var stage: Dictionary = {}
var p1: Fighter
var p2: Fighter
var ai: AIController
var router := InputRouter.new()

var auto_report := true  # tests disable this so they don't change scenes
var round_wins_needed := 2

var phase: int = Phase.INTRO
var phase_ticks := 0
var round_number := 1
var round_wins := [0, 0]
var round_time := ROUND_TIME
var time_accum := 0.0
var training := false
var ko_winner := -1
var slowmo := 0
var finished := false

var announce_text := ""
var announce_sub := ""
var announce_ticks := 0
var announce_total := 0
var announce_color := UITheme.ACCENT

var combo := [0, 0]
var combo_damage := [0.0, 0.0]
var best_combo := [0, 0]
var damage_done := [0.0, 0.0]

var hitboxes_visible := false
var shake := 0.0
var total_ticks := 0
var match_duration := 0.0
var projectiles: Array = []

var auto_refill_meter := false
var show_frame_data := false
var dummy_mode := "stand"
var p1_input_history: Array[Dictionary] = []
var last_frame_data: Dictionary = {}
var _meter_idle_ticks := 0
var _last_input_sig := ""

var _accum := 0.0
var _fx_cache: Dictionary = {}
var _start_positions := [Vector2.ZERO, Vector2.ZERO]

var _vis_prev_p1 := Vector2.ZERO
var _vis_prev_p2 := Vector2.ZERO
var _vis_curr_p1 := Vector2.ZERO
var _vis_curr_p2 := Vector2.ZERO
var _since_physics := 0.0
var _physics_presented := false
var _kick_dir := Vector2(0, 1)
var _kick_time := 0.0


func _ready() -> void:
	cfg = _build_config()
	training = str(cfg.get("mode", "versus")) == "training"
	auto_refill_meter = training
	show_frame_data = training
	round_wins_needed = int(cfg.get("round_wins_needed", 2))
	stage = StageDB.get_stage(str(cfg.get("stage", "breakroom")))
	bg.texture = load(stage["bg"])
	bg.position = Vector2(640, 360)
	camera.position = Vector2(640, 360)
	hitboxes_visible = bool(SaveData.settings.get("show_hitboxes", false))
	Sfx.play_ambience(str(stage.get("ambience", "")))
	_spawn_fighters()
	hud.arena = self
	pause_menu.arena = self
	p1.debug_boxes = hitboxes_visible
	p2.debug_boxes = hitboxes_visible
	_start_match()


func _exit_tree() -> void:
	if is_instance_valid(Sfx):
		Sfx.stop_ambience()


func _build_config() -> Dictionary:
	if not Game.match_config.is_empty():
		return Game.match_config.duplicate(true)
	return {
		"mode": "versus", "p1": "dave", "p2": "karen", "stage": "breakroom",
		"p2_is_ai": true, "difficulty": 2, "round_wins_needed": 2,
	}


func _spawn_fighters() -> void:
	var start: Vector2 = stage["start"]
	_start_positions[0] = Vector2(start.x, CharacterDB.GROUND_Y)
	_start_positions[1] = Vector2(start.y, CharacterDB.GROUND_Y)
	var bounds: Vector2 = stage["bounds"]

	p1 = FIGHTER_SCENE.instantiate()
	fighters_root.add_child(p1)
	p1.setup(str(cfg["p1"]), 0)
	p1.bounds = bounds
	p1.position = _start_positions[0]

	p2 = FIGHTER_SCENE.instantiate()
	fighters_root.add_child(p2)
	p2.setup(str(cfg["p2"]), 1)
	p2.bounds = bounds
	p2.position = _start_positions[1]

	p1.opponent = p2
	p2.opponent = p1
	if p1.char_id == p2.char_id:
		p2.set_mirror_palette(true)

	if training:
		ai = AIController.new(int(cfg.get("difficulty", 2)), "dummy")
	elif bool(cfg.get("p2_is_ai", true)):
		ai = AIController.new(int(cfg.get("difficulty", 2)), "fight")


func _start_match() -> void:
	round_wins = [0, 0]
	round_number = 1
	best_combo = [0, 0]
	damage_done = [0.0, 0.0]
	finished = false
	p1.reset_for_match()
	p2.reset_for_match()
	_start_round()


func _start_round() -> void:
	p1.reset_for_round(_start_positions[0], 1)
	p2.reset_for_round(_start_positions[1], -1)
	round_time = ROUND_TIME
	time_accum = 0.0
	combo = [0, 0]
	combo_damage = [0.0, 0.0]
	p1_input_history.clear()
	last_frame_data = {}
	_meter_idle_ticks = 0
	_last_input_sig = ""
	phase = Phase.INTRO
	phase_ticks = INTRO_TICKS
	ko_winner = -1
	slowmo = 0
	_clear_projectiles()
	_sync_visual_endpoints()
	_announce("ROUND %d" % round_number, 130)
	Sfx.play("round_start", -8.0, 1.0, 0.0)
	hud.snap_health()
	if ai != null:
		ai.reset()
	router.discard()


# ---------------------------------------------------------------------------
# Fixed-tick loop
# ---------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if finished:
		return
	if phase == Phase.FIGHT:
		router.poll()
	else:
		router.discard()
	_accum = minf(_accum + delta, TICK * 4.0)
	var guard := 0
	while _accum >= TICK and guard < 8:
		_accum -= TICK
		guard += 1
		var previous_phase := phase
		_step()
		# Preserve fresh presses on the frame that opens play.
		if phase == Phase.FIGHT and previous_phase != Phase.FIGHT:
			router.poll()
		queue_redraw()
	_since_physics = 0.0
	_physics_presented = true


func _process(delta: float) -> void:
	if finished or p1 == null or p2 == null:
		return
	if _physics_presented:
		_physics_presented = false
		_present(clampf(_accum / TICK, 0.0, 1.0))
		return
	_since_physics += delta
	_present(clampf((_accum + _since_physics) / TICK, 0.0, 1.0))


func _step() -> void:
	_capture_visual_previous()
	total_ticks += 1
	if announce_ticks > 0:
		announce_ticks -= 1
	if shake > 0.0:
		shake = maxf(0.0, shake - 0.6)
	_update_camera()

	match phase:
		Phase.INTRO:
			_step_intro()
		Phase.FIGHT:
			_step_fight()
		Phase.KO:
			_step_ko()
		Phase.ROUND_END:
			_step_round_end()
		Phase.MATCH_END:
			_step_match_end()

	_dispatch_fighter_events()
	_separate_bodies()
	_capture_visual_current()
	_apply_camera(0.0)


func _separate_bodies() -> void:
	if p1.airborne or p2.airborne:
		return
	var min_dist := CharacterDB.BODY_HALF_WIDTH * 2.0
	var pos1 := p1.pos
	var pos2 := p2.pos
	var delta := pos2.x - pos1.x
	var dist := absf(delta)
	if dist >= min_dist:
		return
	var sign := 1.0 if delta >= 0.0 else -1.0
	var half := (min_dist - dist) * 0.5
	pos1.x -= sign * half
	pos2.x += sign * half
	pos1.x = clampf(pos1.x, p1.bounds.x, p1.bounds.y)
	pos2.x = clampf(pos2.x, p2.bounds.x, p2.bounds.y)
	delta = pos2.x - pos1.x
	dist = absf(delta)
	if dist < min_dist:
		var leftover := min_dist - dist
		sign = 1.0 if delta >= 0.0 else -1.0
		var room1 := (pos1.x - p1.bounds.x) if sign > 0.0 else (p1.bounds.y - pos1.x)
		var room2 := (p2.bounds.y - pos2.x) if sign > 0.0 else (pos2.x - p2.bounds.x)
		room1 = maxf(0.0, room1)
		room2 = maxf(0.0, room2)
		if room2 >= room1:
			var push2 := minf(leftover, room2)
			pos2.x += sign * push2
			leftover -= push2
			if leftover > 0.0:
				pos1.x -= sign * minf(leftover, room1)
		else:
			var push1 := minf(leftover, room1)
			pos1.x -= sign * push1
			leftover -= push1
			if leftover > 0.0:
				pos2.x += sign * minf(leftover, room2)
		pos1.x = clampf(pos1.x, p1.bounds.x, p1.bounds.y)
		pos2.x = clampf(pos2.x, p2.bounds.x, p2.bounds.y)
	p1.pos = pos1
	p2.pos = pos2
	p1.position = pos1
	p2.position = pos2


func _step_intro() -> void:
	p1.tick(InputRouter.blank())
	p2.tick(InputRouter.blank())
	phase_ticks -= 1
	if phase_ticks <= 0:
		# Bell and FIGHT land on the tick that unlocks controls. Training reset
		# also enters FIGHT, through _training_reset, and keeps the RESET cue.
		_announce("FIGHT!", 60)
		Sfx.play("bell", -7.0, 1.0, 0.0)
		_enter_fight()


func _enter_fight() -> void:
	phase = Phase.FIGHT
	phase_ticks = 0
	for fighter in [p1, p2]:
		fighter.state = Fighter.State.IDLE
		fighter.state_tick = 0


func _step_fight() -> void:
	# Freeze carried in from an earlier tick. Hits resolved below apply new
	# hitstop only after this tick's melee and projectile contacts are known,
	# so a jab cannot erase a clipboard released on the same tick.
	var frozen := p1.hitstop > 0 or p2.hitstop > 0
	var in1 := router.get_frame(0)
	var in2: Dictionary
	if ai != null:
		in2 = InputRouter.blank() if frozen else ai.decide(p2, p1)
	else:
		in2 = router.get_frame(1)

	if training:
		_record_p1_input(in1)

	var prev_p1_move := p1.move_name
	var prev_p1_tick := p1.move_tick

	p1.tick(in1)
	p2.tick(in2)

	if training and not frozen:
		if p1.state == Fighter.State.ATTACK and not p1.move.is_empty() \
				and (p1.move_name != prev_p1_move or p1.move_tick < prev_p1_tick):
			last_frame_data = {
				"move": p1.move_name.to_upper(),
				"startup": int(p1.move.get("startup", 0)),
				"active": int(p1.move.get("active", 0)),
				"recovery": int(p1.move.get("recovery", 0)),
				"advantage": 0,
				"outcome": "WHIFF",
			}
		_step_training_meter()

	_handle_throws()

	if not frozen:
		_resolve_fight_contacts()
	_handle_landings()
	_update_combos()
	_check_ko()
	_dispatch_fighter_events()
	# The clock still stops while hitstop remains after the tick. The frame
	# that spends the last point is not frozen for the clock; a KO this tick
	# has already left FIGHT and still beats TIME.
	if phase == Phase.FIGHT and p1.hitstop <= 0 and p2.hitstop <= 0:
		_update_timer()


func _step_ko() -> void:
	phase_ticks -= 1
	var simulate := true
	if slowmo > 0:
		slowmo -= 1
		if phase_ticks % 2 == 1:
			simulate = false
	if simulate:
		_tick_fighters_presentation()
		_update_projectiles()
		_handle_landings()
		_update_combos()
	if phase_ticks <= 0:
		if training:
			_training_reset()
		else:
			_end_round(ko_winner)


func _step_round_end() -> void:
	phase_ticks -= 1
	_tick_fighters_presentation()
	if phase_ticks <= 0:
		round_number += 1
		_start_round()


func _step_match_end() -> void:
	phase_ticks -= 1
	_tick_fighters_presentation()
	if phase_ticks <= 0:
		_finish_match()


func _update_camera() -> void:
	if shake > 0.0:
		_kick_time += TICK
	else:
		_kick_time = 0.0
	_apply_camera(0.0)
	var target_zoom := 1.055 if phase == Phase.KO else 1.0
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 0.06)


func _apply_camera(extra: float) -> void:
	var offset := Vector2.ZERO
	var scale := float(SaveData.settings.get("shake_scale", 1.0))
	if shake > 0.0 and bool(SaveData.settings.get("screen_shake", true)) and scale > 0.001:
		var t := maxf(0.0, _kick_time + extra)
		var omega := 9.0
		var response := exp(-omega * t) * (1.0 + omega * t)
		offset = _kick_dir * shake * scale * response
	camera.offset = _quantize_px(offset)


# ---------------------------------------------------------------------------
# Hits
# ---------------------------------------------------------------------------


func _resolve_melee() -> void:
	_apply_contacts(_collect_melee_contacts())


func _resolve_fight_contacts() -> void:
	# Melee and projectiles that spawn or move this tick are all eligible
	# before any of them mutate health, armor, or hitstop. New hitstop then
	# freezes later ticks only.
	_handle_spawns()
	var contacts := _collect_melee_contacts()
	contacts.append_array(_collect_projectile_contacts(true))
	_apply_contacts(contacts)


func _collect_melee_contacts() -> Array[Dictionary]:
	# Capture every eligible contact before either fighter is mutated. Applying
	# P1 first used to cancel an overlapping P2 hit, so equal lethal jabs became
	# a sole P1 KO and an armored P1 never took the trade.
	var contacts: Array[Dictionary] = []
	for i in 2:
		var attacker: Fighter = p1 if i == 0 else p2
		var defender: Fighter = p2 if i == 0 else p1
		if not defender.can_be_hit():
			continue
		var hit := attacker.active_hit()
		if hit.is_empty():
			continue
		if not hit["rect"].intersects(defender.hurtbox()):
			continue
		var info: Dictionary = hit["move"].duplicate()
		info["damage"] = float(hit["damage"])
		contacts.append({
			"attacker_index": i,
			"defender": defender,
			"info": info,
			"rect": hit["rect"],
			"blocked": defender.is_guarding(str(hit["height"])),
			"dir": attacker.facing,
		})
	return contacts


func _apply_contacts(contacts: Array[Dictionary]) -> void:
	for contact in contacts:
		var attacker_index: int = contact["attacker_index"]
		var defender: Fighter = contact["defender"]
		var projectile: Projectile = contact.get("projectile")
		# A knocked-out attacker can still trade. A knocked-out defender has
		# already lost this exchange, so a second contact adds no hit or meter.
		if not defender.knockout:
			if projectile == null:
				_fighter(attacker_index).move_has_hit = true
			_apply_contact(attacker_index, defender, contact["info"], contact["rect"],
					contact["blocked"], contact["dir"], projectile == null)
		if projectile != null:
			_retire_projectile(projectile)
	_dispatch_fighter_events()


func _apply_contact(attacker_index: int, defender: Fighter, info: Dictionary, rect: Rect2,
		blocked: bool, dir: int, is_melee := true) -> void:
	var scale := 1.0
	if not blocked:
		scale = maxf(0.35, 1.0 - 0.09 * float(defender.combo_received))
	var hp_before := defender.health
	var result := defender.take_hit(info, blocked, dir, scale)
	var hp_lost := maxf(0.0, hp_before - defender.health)
	_register_hit(attacker_index, defender, rect.get_center(), info, result, hp_lost, dir, is_melee)


func _register_hit(attacker_index: int, defender: Fighter, contact: Vector2,
		info: Dictionary, result: Dictionary, hp_lost: float, dir := 0, is_melee := true) -> void:
	var attacker := _fighter(attacker_index)
	var blocked: bool = result["blocked"]
	var armored: bool = bool(result.get("armored", false))
	var heavy := float(result["damage"]) >= 80.0
	var hit_dir := dir if dir != 0 else attacker.facing
	_note_kick(attacker, defender)
	# Corner pushback transfer: grounded melee hits against a cornered defender
	# reflect horizontal pushback onto the attacker.
	if is_melee and not armored and not attacker.airborne and not defender.airborne:
		var pinned := (hit_dir < 0 and defender.pos.x <= defender.bounds.x + 14.0) \
				or (hit_dir > 0 and defender.pos.x >= defender.bounds.y - 14.0)
		if pinned:
			attacker.vel.x = -hit_dir * float(info.get("knockback", 0.0)) * (0.35 if blocked else 0.65)
	# Landing (or getting blocked) builds the attacker's meter.
	var gain := float(info.get("meter_gain", 8.0))
	attacker.meter = minf(CharacterDB.METER_MAX, attacker.meter + gain * (0.4 if blocked else 1.0))
	if blocked:
		_spawn_fx("block", contact, 1.6)
		Sfx.play("block", -7.0)
		shake = maxf(shake, 2.5)
		if bool(SaveData.settings.get("hitstop", true)):
			attacker.apply_hitstop(4)
			defender.apply_hitstop(4)
	elif armored:
		_spawn_fx("block", contact, 2.0)
		shake = maxf(shake, 4.0)
		if bool(SaveData.settings.get("hitstop", true)):
			attacker.apply_hitstop(5)
			defender.apply_hitstop(5)
	else:
		_spawn_fx("hit", contact, 2.2 if heavy else 1.6)
		Sfx.play(str(info.get("hit_sfx", "hit_light")), -4.0)
		shake = maxf(shake, 5.0 + minf(6.0, float(result["damage"]) * 0.045))
		if bool(SaveData.settings.get("hitstop", true)):
			var freeze := 9 if heavy else 7
			attacker.apply_hitstop(freeze)
			defender.apply_hitstop(freeze)
		combo[attacker_index] += 1
		combo_damage[attacker_index] += float(result["damage"])
		best_combo[attacker_index] = maxi(best_combo[attacker_index], combo[attacker_index])
	# Match damage is health actually removed, including nonlethal chip and
	# excluding overkill. Combo popups still use the hit's full damage.
	damage_done[attacker_index] += hp_lost
	if training and attacker_index == 0:
		var move_label := p1.move_name.to_upper() if (is_melee and p1.move_name != "") else "SPECIAL"
		var frame_src: Dictionary = info if is_melee else p1.data.get("moves", {}).get("special", info)
		var remaining_att := 0
		if not p1.move.is_empty():
			remaining_att = maxi(0, CharacterDB.move_total(p1.move) - p1.move_tick)
		var stun := int(info.get("blockstun", 10)) if blocked else int(info.get("hitstun", 12))
		last_frame_data = {
			"move": move_label,
			"startup": int(frame_src.get("startup", 0)),
			"active": int(frame_src.get("active", 0)),
			"recovery": int(frame_src.get("recovery", 0)),
			"advantage": stun - remaining_att,
			"outcome": "BLOCK" if blocked else "HIT",
		}


func _note_kick(attacker: Fighter, defender: Fighter) -> void:
	var aim := defender.pos - attacker.pos
	if aim.length_squared() < 1.0:
		aim = Vector2(attacker.facing, 0.0)
	_kick_dir = aim.normalized()
	_kick_time = 0.0


func _handle_spawns() -> void:
	for i in 2:
		var f: Fighter = p1 if i == 0 else p2
		if f.state != Fighter.State.ATTACK or f.move.is_empty():
			continue
		if not f.move.has("projectile") or f.move_projectile_spawned:
			continue
		if f.move_tick == int(f.move.get("startup", 1)):
			var proj := Projectile.new()
			proj.setup(f, f.move["projectile"])
			projectiles_root.add_child(proj)
			projectiles.append(proj)
			f.move_projectile_spawned = true


func _update_projectiles() -> void:
	# After TIME or K.O., projectiles advance for presentation and do not hit.
	_apply_contacts(_collect_projectile_contacts(phase == Phase.FIGHT))


func _collect_projectile_contacts(resolve: bool) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for proj in projectiles.duplicate():
		if not is_instance_valid(proj):
			projectiles.erase(proj)
			continue
		if proj.dead:
			_retire_projectile(proj)
			continue
		proj.tick()
		if resolve:
			var defender: Fighter = p2 if proj.owner_index == 0 else p1
			var rect: Rect2 = proj.hitbox()
			if defender.can_be_hit() and rect.intersects(defender.hurtbox()):
				proj.connected = true
				contacts.append({
					"attacker_index": proj.owner_index,
					"defender": defender,
					"info": proj.info,
					"rect": rect,
					"blocked": defender.is_guarding(str(proj.info.get("height", "mid"))),
					"dir": proj.facing,
					"projectile": proj,
				})
				continue
		if proj.dead:
			_retire_projectile(proj)
	return contacts


func _handle_throws() -> void:
	var tech_handled := false
	for i in 2:
		var f := _fighter(i)
		var foe := _fighter(1 - i)
		if f.teched_flag and not tech_handled:
			tech_handled = true
			var mid := Vector2((p1.pos.x + p2.pos.x) * 0.5, (p1.pos.y + p2.pos.y) * 0.5 - 160.0)
			_spawn_fx("block", mid, 1.8)
			shake = maxf(shake, 3.0)
			if phase != Phase.KO and not p1.knockout and not p2.knockout:
				_announce("TECH!", 34, "", UITheme.OK)
		if f.throw_completed_flag:
			damage_done[i] += f.throw_damage_dealt
			combo[i] += 1
			combo_damage[i] += f.throw_raw_damage
			best_combo[i] = maxi(best_combo[i], combo[i])
			_note_kick(f, foe)
			var at := Vector2((f.pos.x + foe.pos.x) * 0.5, CharacterDB.GROUND_Y - 160.0)
			_spawn_fx("hit", at, 2.0)
			shake = maxf(shake, 6.5)
			if training and i == 0:
				last_frame_data = {
					"move": "THROW",
					"startup": CharacterDB.THROW_STARTUP,
					"active": 2,
					"recovery": CharacterDB.THROW_RECOVERY,
					"advantage": CharacterDB.KNOCKDOWN_TICKS,
					"outcome": "THROW",
				}


func _dispatch_fighter_events() -> void:
	for f in [p1, p2]:
		if f == null:
			continue
		for ev in f.drain_events():
			if str(ev.get("type", "")) == "sfx":
				Sfx.play(
					str(ev.get("name", "")),
					float(ev.get("db", 0.0)),
					float(ev.get("pitch", 1.0)),
					float(ev.get("var", 0.06))
				)


func _update_combos() -> void:
	for i in 2:
		var defender: Fighter = p2 if i == 0 else p1
		if combo[i] > 0 and defender.state != Fighter.State.HITSTUN \
				and defender.state != Fighter.State.KO \
				and defender.state != Fighter.State.KNOCKDOWN \
				and defender.state != Fighter.State.GRABBED:
			combo[i] = 0
			combo_damage[i] = 0.0


func _handle_landings() -> void:
	for f in [p1, p2]:
		if f.landed_flag:
			_spawn_fx("dust", Vector2(f.pos.x, CharacterDB.GROUND_Y), 2.0)
			if shake < 1.2:
				_kick_dir = Vector2(0, 1)
				_kick_time = 0.0
			shake = maxf(shake, 1.2)


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------


func _update_timer() -> void:
	if training:
		round_time = ROUND_TIME
		return
	time_accum += TICK
	if time_accum >= 1.0:
		time_accum -= 1.0
		round_time = maxf(0.0, round_time - 1.0)
		if round_time <= 0.0:
			_time_over()


func _time_over() -> void:
	var max1 := float(p1.data["build"]["health"])
	var max2 := float(p2.data["build"]["health"])
	var r1 := p1.health / max1
	var r2 := p2.health / max2
	var winner := -1
	if not is_equal_approx(r1, r2):
		winner = 0 if r1 > r2 else 1
	_begin_round_end(winner, "TIME")


func _check_ko() -> void:
	if not p1.knockout and not p2.knockout:
		return
	if training:
		phase = Phase.KO
		phase_ticks = 110
		ko_winner = -1
		slowmo = 40
		_announce("K.O.", 100, "", UITheme.DANGER)
		return
	var winner := -1
	if p1.knockout and not p2.knockout:
		winner = 1
	elif p2.knockout and not p1.knockout:
		winner = 0
	_begin_round_end(winner, "K.O.")


func _begin_round_end(winner: int, label: String) -> void:
	if phase != Phase.FIGHT:
		return
	ko_winner = winner
	phase = Phase.KO
	phase_ticks = KO_TICKS if label == "K.O." else 120
	slowmo = 45 if label == "K.O." else 0
	shake = 8.0
	_kick_time = 0.0
	var sub := ""
	if winner == 0:
		sub = "%s WINS THE ROUND" % _name_of(p1)
	elif winner == 1:
		sub = "%s WINS THE ROUND" % _name_of(p2)
	elif label == "TIME":
		sub = "TIME OVER - DRAW"
	else:
		sub = "DOUBLE KO"
	_announce(label, 120, sub, UITheme.DANGER if label == "K.O." else UITheme.ACCENT)
	Sfx.play("bell", -3.0, 1.0, 0.0)


func _end_round(winner: int) -> void:
	round_finished.emit(winner)
	if winner == 0:
		round_wins[0] += 1
		p1.celebrate()
	elif winner == 1:
		round_wins[1] += 1
		p2.celebrate()
	else:
		round_wins[0] += 1
		round_wins[1] += 1

	var needed := round_wins_needed
	var over: bool = round_wins[0] >= needed or round_wins[1] >= needed
	if over:
		phase = Phase.MATCH_END
		phase_ticks = MATCH_END_TICKS
		var match_winner := -1
		if round_wins[0] > round_wins[1]:
			match_winner = 0
		elif round_wins[1] > round_wins[0]:
			match_winner = 1
		if match_winner >= 0:
			_announce("%s WINS" % _name_of(_fighter(match_winner)), 150, "", UITheme.ACCENT)
		else:
			_announce("DRAW", 150, "NOBODY WINS. PAPERWORK FOR EVERYONE.", UITheme.MUTED)
	else:
		phase = Phase.ROUND_END
		phase_ticks = ROUND_END_TICKS


func _training_reset() -> void:
	p1.reset_for_round(_start_positions[0], 1)
	p2.reset_for_round(_start_positions[1], -1)
	p1.health = float(p1.data["build"]["health"])
	p2.health = float(p2.data["build"]["health"])
	p1.meter = minf(CharacterDB.METER_MAX, p1.meter)
	p2.meter = minf(CharacterDB.METER_MAX, p2.meter)
	_meter_idle_ticks = 0
	_last_input_sig = ""
	last_frame_data = {}
	_enter_fight()
	clear_projectiles_now()
	_announce("RESET", 40)
	_sync_visual_endpoints()
	hud.snap_health()
	if ai != null:
		ai.reset()
	router.discard()


func _finish_match() -> void:
	if finished:
		return
	finished = true
	Sfx.stop_ambience()
	match_duration = total_ticks * TICK
	var winner := -1
	if round_wins[0] > round_wins[1]:
		winner = 0
	elif round_wins[1] > round_wins[0]:
		winner = 1
	var result := {
		"mode": str(cfg.get("mode", "versus")),
		"p1": str(cfg.get("p1", "dave")),
		"p2": str(cfg.get("p2", "karen")),
		"stage": str(cfg.get("stage", "breakroom")),
		"winner": winner,
		"wins": round_wins.duplicate(),
		"best_combo": best_combo.duplicate(),
		"damage": damage_done.duplicate(),
		"rounds": round_number,
		"duration": match_duration,
	}
	match_finished.emit(result)
	if auto_report:
		Game.on_match_end(result)


# ---------------------------------------------------------------------------
# Presentation helpers (also read by the HUD)
# ---------------------------------------------------------------------------


func _announce(text: String, ticks: int, sub := "", color := UITheme.ACCENT) -> void:
	announce_text = text
	announce_sub = sub
	announce_ticks = ticks
	announce_total = maxi(1, ticks)
	announce_color = color


func _spawn_fx(kind: String, at: Vector2, scale := 1.0) -> void:
	var anim := AnimatedSprite2D.new()
	match kind:
		"hit":
			anim.sprite_frames = _fx_frames("res://assets/sprites/fx/hit.png", 48, 48, 5, 24.0)
		"block":
			anim.sprite_frames = _fx_frames("res://assets/sprites/fx/block.png", 40, 40, 4, 22.0)
		"dust":
			anim.sprite_frames = _fx_frames("res://assets/sprites/fx/dust.png", 32, 24, 4, 14.0)
		_:
			anim.queue_free()
			return
	anim.position = at
	var target_scale := Vector2(scale, scale)
	anim.scale = target_scale * 0.8
	anim.z_index = 6
	fx_root.add_child(anim)
	anim.play("fx")
	anim.animation_finished.connect(anim.queue_free)
	var pop := anim.create_tween()
	pop.tween_property(anim, "scale", target_scale, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fx_frames(path: String, fw: int, fh: int, count: int, fps: float) -> SpriteFrames:
	if _fx_cache.has(path):
		return _fx_cache[path]
	var tex: Texture2D = load(path)
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation("fx")
	sf.set_animation_speed("fx", fps)
	sf.set_animation_loop("fx", false)
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("fx", at)
	_fx_cache[path] = sf
	return sf


func _fighter(index: int) -> Fighter:
	return p1 if index == 0 else p2


func _name_of(f: Fighter) -> String:
	return str(f.data.get("name", "FIGHTER"))


func fighter_name(index: int) -> String:
	return _name_of(_fighter(index))


func fighter_accent(index: int) -> Color:
	return _fighter(index).data.get("accent", UITheme.ACCENT)


func clear_projectiles_now() -> void:
	for proj in projectiles:
		if is_instance_valid(proj):
			proj.queue_free()
	projectiles.clear()


func _clear_projectiles() -> void:
	clear_projectiles_now()


func set_dummy_mode(mode_name: String) -> void:
	var behavior := "dummy"
	match mode_name:
		"crouch":
			dummy_mode = "crouch"
			behavior = "dummy_crouch"
		"block":
			dummy_mode = "block"
			behavior = "dummy_block"
		"jump":
			dummy_mode = "jump"
			behavior = "dummy_jump"
		_:
			dummy_mode = "stand"
			behavior = "dummy"
	if ai != null:
		ai.behavior = behavior
		ai.reset()


func _record_p1_input(inp: Dictionary) -> void:
	var dir := int(inp.get("dir", 0))
	var crouch := bool(inp.get("crouch", false))
	var jump := bool(inp.get("jump", false))
	var light := bool(inp.get("light", false))
	var heavy := bool(inp.get("heavy", false))
	var special := bool(inp.get("special", false))
	var block := bool(inp.get("block", false))
	var throw_btn := bool(inp.get("throw", false))
	var sig := "%d|%d%d%d%d%d%d%d" % [
		dir,
		1 if crouch else 0,
		1 if jump else 0,
		1 if light else 0,
		1 if heavy else 0,
		1 if special else 0,
		1 if block else 0,
		1 if throw_btn else 0,
	]
	if sig == _last_input_sig:
		return
	_last_input_sig = sig
	var neutral := dir == 0 and not crouch and not jump and not light \
			and not heavy and not special and not block and not throw_btn
	if neutral:
		return
	p1_input_history.append({
		"dir": dir,
		"crouch": crouch,
		"jump": jump,
		"light": light,
		"heavy": heavy,
		"special": special,
		"block": block,
		"throw": throw_btn,
	})
	while p1_input_history.size() > 10:
		p1_input_history.pop_front()


func _step_training_meter() -> void:
	if not auto_refill_meter:
		_meter_idle_ticks = 0
		return
	if p1.is_attacking() or p1.state == Fighter.State.THROW:
		_meter_idle_ticks = 0
		return
	if p1.meter < CharacterDB.METER_MAX:
		_meter_idle_ticks += 1
		if _meter_idle_ticks >= 45:
			p1.meter = minf(CharacterDB.METER_MAX, p1.meter + 3.0)
	else:
		_meter_idle_ticks = 0


func capture_snapshot() -> Dictionary:
	var proj_states: Array = []
	for proj in projectiles:
		if is_instance_valid(proj) and not proj.dead:
			proj_states.append(proj.to_state())
	return {
		"phase": phase,
		"phase_ticks": phase_ticks,
		"round_number": round_number,
		"round_wins": round_wins.duplicate(),
		"round_time": round_time,
		"time_accum": time_accum,
		"ko_winner": ko_winner,
		"slowmo": slowmo,
		"finished": finished,
		"combo": combo.duplicate(),
		"combo_damage": combo_damage.duplicate(),
		"best_combo": best_combo.duplicate(),
		"damage_done": damage_done.duplicate(),
		"shake": shake,
		"total_ticks": total_ticks,
		"p1": p1.to_state(),
		"p2": p2.to_state(),
		"projectiles": proj_states,
	}


func restore_snapshot(snap: Dictionary) -> void:
	phase = int(snap.get("phase", Phase.FIGHT))
	phase_ticks = int(snap.get("phase_ticks", 0))
	round_number = int(snap.get("round_number", 1))
	round_wins = (snap.get("round_wins", [0, 0]) as Array).duplicate()
	round_time = float(snap.get("round_time", ROUND_TIME))
	time_accum = float(snap.get("time_accum", 0.0))
	ko_winner = int(snap.get("ko_winner", -1))
	slowmo = int(snap.get("slowmo", 0))
	finished = bool(snap.get("finished", false))
	combo = (snap.get("combo", [0, 0]) as Array).duplicate()
	combo_damage = (snap.get("combo_damage", [0.0, 0.0]) as Array).duplicate()
	best_combo = (snap.get("best_combo", [0, 0]) as Array).duplicate()
	damage_done = (snap.get("damage_done", [0.0, 0.0]) as Array).duplicate()
	shake = float(snap.get("shake", 0.0))
	total_ticks = int(snap.get("total_ticks", 0))
	if snap.has("p1"):
		p1.from_state(snap["p1"])
	if snap.has("p2"):
		p2.from_state(snap["p2"])
	clear_projectiles_now()
	for ps in snap.get("projectiles", []):
		if ps is Dictionary:
			var proj := Projectile.new()
			projectiles_root.add_child(proj)
			proj.from_state(ps)
			projectiles.append(proj)
	_sync_visual_endpoints()


func set_hitboxes_visible(value: bool) -> void:
	hitboxes_visible = value
	p1.debug_boxes = value
	p2.debug_boxes = value
	p1.queue_redraw()
	p2.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hitboxes"):
		set_hitboxes_visible(not hitboxes_visible)
		if pause_menu != null and pause_menu._hitbox_button != null:
			pause_menu._hitbox_button.text = "HITBOXES: %s" % ("ON" if hitboxes_visible else "OFF")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reset_round"):
		# F5 is a training reset. It must not reopen a competitive round or a
		# match that has already been decided.
		if training and not finished:
			_training_reset()
		get_viewport().set_input_as_handled()


func _tick_fighters_presentation() -> void:
	var blank := InputRouter.blank()
	p1.tick(blank, false)
	p2.tick(blank, false)


func _retire_projectile(proj: Projectile) -> void:
	if phase == Phase.FIGHT and is_instance_valid(proj) and not proj.connected:
		var owner: Fighter = p1 if proj.owner_index == 0 else p2
		owner.meter = minf(CharacterDB.METER_MAX, owner.meter + 2.0)
	projectiles.erase(proj)
	if is_instance_valid(proj):
		proj.dead = true
		proj.queue_free()


func _sync_visual_endpoints() -> void:
	if p1 == null or p2 == null:
		return
	_vis_prev_p1 = p1.pos
	_vis_prev_p2 = p2.pos
	_vis_curr_p1 = p1.pos
	_vis_curr_p2 = p2.pos
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		proj.restore_sim_pos()
		proj.prev_pos = proj.sim_pos


func _capture_visual_previous() -> void:
	_vis_prev_p1 = p1.pos
	_vis_prev_p2 = p2.pos
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		proj.restore_sim_pos()
		proj.prev_pos = proj.sim_pos


func _capture_visual_current() -> void:
	_vis_curr_p1 = p1.pos
	_vis_curr_p2 = p2.pos
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		proj.restore_sim_pos()


func _present(alpha: float) -> void:
	if p1 == null or p2 == null:
		return
	var blend := clampf(alpha, 0.0, 1.0)
	p1.present_at(_quantize_px(_vis_prev_p1.lerp(_vis_curr_p1, blend)))
	p2.present_at(_quantize_px(_vis_prev_p2.lerp(_vis_curr_p2, blend)))
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		proj.present_at(_quantize_px(proj.prev_pos.lerp(proj.sim_pos, blend)))
	_apply_camera(_since_physics)


func _quantize_px(v: Vector2) -> Vector2:
	return Vector2(roundf(v.x), roundf(v.y))
