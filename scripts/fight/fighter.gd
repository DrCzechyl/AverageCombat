class_name Fighter
extends Node2D

## One fighter. Deliberately self-contained: it never reads the keyboard, it only
## consumes an input dictionary, so an AI (or a future network peer) can drive it
## with the exact same code path.
##
## input = {
##   "dir": -1 | 0 | 1, "jump": bool, "crouch": bool,
##   "light": bool, "heavy": bool, "special": bool, "block": bool
## }

enum State { INTRO, IDLE, WALK, CROUCH, AIR, ATTACK, HITSTUN, BLOCKSTUN, KO, WIN }

const TICK := 1.0 / 60.0
const GRAVITY := 2600.0
const GROUND_FRICTION := 2400.0
const ATTACK_FRICTION := 3000.0
const AIR_CONTROL := 950.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

var char_id := "dave"
var data: Dictionary = {}
var player_index := 0
var opponent: Fighter

var bounds := Vector2(CharacterDB.ARENA_LEFT, CharacterDB.ARENA_RIGHT)
var facing := 1
var health := 1000.0
var meter := 0.0
var pos := Vector2.ZERO
var vel := Vector2.ZERO

var state: int = State.IDLE
var state_tick := 0
var airborne := false
var crouching := false
var blocking := false
var walking := false
var hitstop := 0
var stun_ticks := 0
var invuln := 0
var flash_ticks := 0
var debug_boxes := false

var move: Dictionary = {}
var move_name := ""
var move_tick := 0
var move_has_hit := false
var move_armor_used := false
var move_lunged := false
var move_projectile_spawned := false

var knockout := false
var landed_flag := false
var jumped_flag := false
var combo_received := 0

var _anim_name := ""
var _rng := RandomNumberGenerator.new()


func setup(id: String, index: int) -> void:
	char_id = id
	data = CharacterDB.get_character(id)
	player_index = index
	health = float(data["build"]["health"])
	meter = 0.0
	_rng.randomize()
	_build_frames()
	reset_visuals()
	shadow.texture = load("res://assets/sprites/fx/shadow.png")


func _build_frames() -> void:
	var tex: Texture2D = load(data["sheet"])
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for anim_name in CharacterDB.ANIMS:
		var info: Dictionary = CharacterDB.ANIMS[anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, float(info["fps"]))
		sf.set_animation_loop(anim_name, bool(info["loop"]))
		for i in int(info["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CharacterDB.CELL_W, int(info["row"]) * CharacterDB.CELL_H,
					CharacterDB.CELL_W, CharacterDB.CELL_H)
			sf.add_frame(anim_name, at)
	sprite.sprite_frames = sf
	sprite.play("idle")


func _ready() -> void:
	if sprite.sprite_frames == null:
		# setup() normally runs right after add_child(); this is a safety net for
		# the editor preview / tests that put a Fighter in the scene directly.
		data = CharacterDB.get_character(char_id)
		_build_frames()
	position = pos


# ---------------------------------------------------------------------------
# Round lifecycle
# ---------------------------------------------------------------------------


func reset_for_round(at: Vector2, face_dir: int) -> void:
	pos = at
	position = pos
	health = float(data["build"]["health"])
	vel = Vector2.ZERO
	facing = face_dir
	airborne = false
	crouching = false
	blocking = false
	walking = false
	hitstop = 0
	stun_ticks = 0
	invuln = 0
	flash_ticks = 0
	move = {}
	move_name = ""
	move_tick = 0
	move_has_hit = false
	move_armor_used = false
	move_lunged = false
	move_projectile_spawned = false
	knockout = false
	landed_flag = false
	jumped_flag = false
	combo_received = 0
	state = State.INTRO
	state_tick = 0
	_anim_name = ""
	sprite.modulate = Color.WHITE
	sprite.position = Vector2.ZERO
	sprite.visible = true
	reset_visuals()
	_play_anim("idle", true)


func reset_for_match() -> void:
	health = float(data["build"]["health"])
	meter = 0.0


func heal_full() -> void:
	health = float(data["build"]["health"])
	knockout = false


func celebrate() -> void:
	if state == State.KO:
		return
	state = State.WIN
	state_tick = 0
	_move_clear()


func _move_clear() -> void:
	move = {}
	move_name = ""
	move_tick = 0
	move_has_hit = false
	move_lunged = false
	move_projectile_spawned = false


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------


func tick(inp: Dictionary, grant_whiff_meter := true) -> void:
	landed_flag = false
	jumped_flag = false

	if hitstop > 0:
		hitstop -= 1
		_update_visuals(true)
		return
	if flash_ticks > 0:
		flash_ticks -= 1
	if invuln > 0:
		invuln -= 1
	state_tick += 1

	match state:
		State.KO:
			_tick_ko()
		State.WIN:
			_tick_win()
		State.ATTACK:
			_tick_attack(grant_whiff_meter)
		State.HITSTUN, State.BLOCKSTUN:
			_tick_stun(inp)
		State.INTRO:
			_tick_intro()
		_:
			_tick_free(inp)

	_integrate()
	_update_visuals()


func _tick_intro() -> void:
	vel.x = move_toward(vel.x, 0, GROUND_FRICTION * TICK)
	if opponent != null and not airborne:
		facing = 1 if opponent.pos.x >= pos.x else -1
	blocking = false
	crouching = false
	if state_tick > 2:
		state = State.IDLE
		state_tick = 0


func _tick_free(inp: Dictionary) -> void:
	var dir := int(inp.get("dir", 0))
	if opponent != null and not airborne:
		facing = 1 if opponent.pos.x >= pos.x else -1

	var want_crouch := bool(inp.get("crouch", false)) and not airborne
	crouching = want_crouch

	var holding_back := dir != 0 and dir == -facing
	blocking = (bool(inp.get("block", false)) or holding_back) and not airborne

	# Attacks take priority over movement.
	if _try_attack(inp):
		return

	if bool(inp.get("jump", false)) and not airborne:
		vel.y = float(data["build"]["jump_velocity"])
		airborne = true
		crouching = false
		blocking = false
		state = State.AIR
		state_tick = 0
		jumped_flag = true
		return

	if airborne:
		state = State.AIR
		if dir != 0:
			vel.x = move_toward(vel.x, dir * float(data["build"]["walk_speed"]) * 0.85,
					AIR_CONTROL * TICK)
		return

	if want_crouch:
		state = State.CROUCH
		vel.x = move_toward(vel.x, 0, GROUND_FRICTION * TICK)
		walking = false
		return

	if dir != 0:
		state = State.WALK
		walking = true
		var speed: float = float(data["build"]["walk_speed"])
		if dir != facing:
			speed = float(data["build"]["back_speed"])
		if blocking:
			speed *= 0.6
		vel.x = dir * speed
	else:
		state = State.IDLE
		walking = false
		vel.x = move_toward(vel.x, 0, GROUND_FRICTION * TICK)


func _try_attack(inp: Dictionary) -> bool:
	if bool(inp.get("special", false)) and meter >= CharacterDB.METER_COST:
		start_move("special")
		return true
	if airborne:
		if bool(inp.get("heavy", false)) or bool(inp.get("light", false)):
			start_move("air")
			return true
		return false
	if bool(inp.get("heavy", false)):
		start_move("sweep" if crouching else "heavy")
		return true
	if bool(inp.get("light", false)):
		start_move("low" if crouching else "jab")
		return true
	return false


func start_move(id: String) -> void:
	if not data.get("moves", {}).has(id):
		return
	move_name = id
	move = data["moves"][id]
	move_tick = 0
	move_has_hit = false
	move_armor_used = false
	move_lunged = false
	move_projectile_spawned = false
	state = State.ATTACK
	state_tick = 0
	blocking = false
	walking = false
	if not airborne and opponent != null:
		facing = 1 if opponent.pos.x >= pos.x else -1
	var cost := float(move.get("meter_cost", 0.0))
	if cost > 0.0:
		meter = maxf(0.0, meter - cost)
	Sfx.play(str(move.get("sfx", "swing")), -7.0)


func _tick_attack(grant_whiff_meter: bool) -> void:
	move_tick += 1
	var total := CharacterDB.move_total(move)
	var startup := int(move.get("startup", 1))
	var active := int(move.get("active", 1))

	# A projectile is still in flight when these active frames end, so the
	# whiff bonus waits until the arena sees it miss.
	if grant_whiff_meter and move_tick == startup + active and not move_has_hit \
			and not move.has("projectile"):
		meter = minf(CharacterDB.METER_MAX, meter + 2.0)

	if not move_lunged and move_tick >= startup and float(move.get("lunge", 0.0)) > 0.0:
		move_lunged = true
		var dist := float(move["lunge"])
		vel.x = facing * sqrt(2.0 * ATTACK_FRICTION * dist)

	vel.x = move_toward(vel.x, 0, ATTACK_FRICTION * TICK)
	if airborne:
		# Air attacks keep their drift; gravity still applies.
		pass

	if move_tick >= total:
		_move_clear()
		if airborne:
			state = State.AIR
		else:
			state = State.IDLE
		state_tick = 0


func _tick_stun(inp: Dictionary) -> void:
	if stun_ticks > 0:
		stun_ticks -= 1
	vel.x = move_toward(vel.x, 0, GROUND_FRICTION * TICK)
	if stun_ticks <= 0 and not airborne:
		var was_hit := state == State.HITSTUN
		state = State.CROUCH if crouching else State.IDLE
		state_tick = 0
		blocking = false
		if was_hit:
			combo_received = 0


func _tick_ko() -> void:
	vel.x = move_toward(vel.x, 0, GROUND_FRICTION * 0.35 * TICK)


func _tick_win() -> void:
	vel.x = move_toward(vel.x, 0, GROUND_FRICTION * TICK)
	if opponent != null:
		facing = 1 if opponent.pos.x >= pos.x else -1


func _integrate() -> void:
	vel.y += GRAVITY * TICK
	pos += vel * TICK
	if pos.y >= CharacterDB.GROUND_Y:
		pos.y = CharacterDB.GROUND_Y
		if airborne and vel.y > 0.0:
			airborne = false
			landed_flag = true
			_on_land(vel.y)
		vel.y = 0.0
	pos.x = clampf(pos.x, bounds.x, bounds.y)
	position = pos


func _on_land(fall_speed: float) -> void:
	if fall_speed > 420.0:
		Sfx.play("land", -12.0, 0.85, 0.1)
	match state:
		State.AIR:
			state = State.IDLE
			state_tick = 0
		State.ATTACK:
			if move_name == "air":
				_move_clear()
				state = State.IDLE
				state_tick = 0
		State.HITSTUN:
			stun_ticks = maxi(stun_ticks, 16)
		State.KO:
			pass


# ---------------------------------------------------------------------------
# Hit resolution API (the arena drives this)
# ---------------------------------------------------------------------------


func active_hit() -> Dictionary:
	if state != State.ATTACK or move.is_empty() or move_has_hit:
		return {}
	# Projectile moves (Karen's clipboard) deal damage only through the projectile.
	if move.has("projectile"):
		return {}
	var startup := int(move.get("startup", 1))
	var active := int(move.get("active", 1))
	if move_tick < startup or move_tick >= startup + active:
		return {}
	var box: Rect2 = move["hitbox"]
	if facing < 0:
		box = Rect2(-(box.position.x + box.size.x), box.position.y, box.size.x, box.size.y)
	return {
		"rect": Rect2(box.position + pos, box.size),
		"move": move,
		"name": move_name,
		"height": str(move.get("height", "mid")),
		"damage": float(move.get("damage", 0.0)) * float(data["build"]["damage_scale"]),
		"startup": startup,
		"owner": self,
	}


func hurtbox() -> Rect2:
	if state == State.KO:
		return Rect2(pos.x - 48.0, pos.y - 52.0, 96.0, 52.0)
	var r: Rect2
	if airborne:
		r = CharacterDB.AIR_HURTBOX
	elif crouching:
		r = CharacterDB.CROUCH_HURTBOX
	else:
		r = CharacterDB.BASE_HURTBOX
	return Rect2(r.position + pos, r.size)


func is_guarding(height: String) -> bool:
	if not blocking or airborne:
		return false
	match height:
		"low":
			return crouching
		"high":
			return not crouching
		_:
			return true


func can_be_hit() -> bool:
	return state != State.KO and invuln <= 0 and not knockout


func is_attacking() -> bool:
	return state == State.ATTACK and not move.is_empty()


func attack_frame() -> int:
	return move_tick


func take_hit(info: Dictionary, blocked: bool, dir: int, combo_scale := 1.0) -> Dictionary:
	var raw_damage := float(info.get("damage", 0.0))
	var damage := raw_damage * combo_scale
	var result := {"damage": 0.0, "blocked": blocked, "ko": false, "armored": false}

	if blocked:
		var chip := damage * float(info.get("chip", 0.12))
		if health - chip <= 0.0:
			# A killing chip is a KO, not a successful block.
			result["blocked"] = false
			return _apply_hit_damage(info, dir, chip, result)
		health -= chip
		meter = minf(CharacterDB.METER_MAX, meter + damage * 0.06)
		state = State.BLOCKSTUN
		stun_ticks = int(info.get("blockstun", 10))
		state_tick = 0
		flash_ticks = 4
		vel.x = dir * float(info.get("knockback", 0.0)) * 0.3
		result["damage"] = chip
		return result

	# Super armor (Tony's special) eats a non-lethal hit and keeps the move going.
	# A hit that would empty the bar still KOs.
	var armored := state == State.ATTACK and bool(move.get("armor", false)) and not move_armor_used
	if armored and health - damage > 0.0:
		move_armor_used = true
		health -= damage
		meter = minf(CharacterDB.METER_MAX, meter + damage * 0.1)
		flash_ticks = 6
		result["damage"] = damage
		result["armored"] = true
		return result

	return _apply_hit_damage(info, dir, damage, result)


func _apply_hit_damage(info: Dictionary, dir: int, damage: float, result: Dictionary) -> Dictionary:
	health -= damage
	combo_received += 1
	meter = minf(CharacterDB.METER_MAX, meter + damage * 0.1)
	state = State.HITSTUN
	stun_ticks = int(info.get("hitstun", 12))
	state_tick = 0
	flash_ticks = 6
	crouching = false
	blocking = false
	var weight := maxf(0.6, float(data["build"]["weight"]))
	vel.x = dir * float(info.get("knockback", 0.0)) / weight
	var launch := float(info.get("launch", 0.0))
	if launch > 0.0:
		vel.y = -launch
		airborne = true
	result["damage"] = damage
	if health <= 0.0:
		health = 0.0
		knockout = true
		state = State.KO
		state_tick = 0
		stun_ticks = 0
		_move_clear()
		airborne = true
		vel.y = -430.0
		vel.x = dir * 320.0 / weight
		Sfx.play("ko", -2.0)
		result["ko"] = true
	return result


func apply_hitstop(ticks: int) -> void:
	hitstop = maxi(hitstop, ticks)


func _threatened() -> bool:
	if opponent == null:
		return false
	if opponent.is_attacking():
		var startup := int(opponent.move.get("startup", 0))
		return opponent.attack_frame() >= startup - 8 and absf(opponent.pos.x - pos.x) < 340.0
	return false


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------


func reset_visuals() -> void:
	sprite.flip_h = facing < 0
	sprite.position = Vector2.ZERO
	shadow.position = Vector2(0, CharacterDB.GROUND_Y - pos.y)
	shadow.modulate = Color(1, 1, 1, 0.55)
	shadow.scale = Vector2(2.2, 1.0)


func _update_visuals(frozen := false) -> void:
	sprite.flip_h = facing < 0

	var air_height := CharacterDB.GROUND_Y - pos.y
	shadow.position = Vector2(0, air_height)
	shadow.scale = Vector2(2.2 * clampf(1.0 - air_height / 1400.0, 0.55, 1.0), 1.0)
	shadow.modulate = Color(1, 1, 1, clampf(0.6 - air_height / 900.0, 0.18, 0.6))

	if flash_ticks > 0:
		sprite.modulate = Color(1.9, 1.9, 1.9)
	else:
		sprite.modulate = Color.WHITE

	if hitstop > 0 and not frozen:
		sprite.position = Vector2.ZERO
	elif hitstop > 0:
		sprite.position = Vector2(_rng.randf_range(-3.0, 3.0), 0)
	else:
		sprite.position = Vector2.ZERO

	_update_anim()
	if debug_boxes:
		queue_redraw()


func _draw() -> void:
	if not debug_boxes:
		return
	var hb := hurtbox()
	draw_rect(Rect2(hb.position - pos, hb.size), Color(0.35, 0.8, 1.0, 0.45), false, 2.0)
	var hit := active_hit()
	if not hit.is_empty():
		var r: Rect2 = hit["rect"]
		draw_rect(Rect2(r.position - pos, r.size), Color(1.0, 0.25, 0.25, 0.65), false, 2.0)


func _update_anim() -> void:
	var anim := "idle"
	var manual := false

	match state:
		State.KO:
			anim = "ko"
		State.ATTACK:
			if not move.is_empty():
				anim = str(move.get("anim", "light"))
				manual = true
			else:
				anim = "idle"
		State.HITSTUN:
			anim = "hurt"
		State.BLOCKSTUN:
			anim = "block"
		State.WIN:
			anim = "win"
		State.AIR:
			anim = "jump"
			manual = true
		State.CROUCH:
			anim = "crouch"
		State.WALK:
			anim = "block" if blocking and _threatened() else "walk"
		_:
			anim = "block" if blocking and _threatened() else "idle"

	if manual:
		var frame := 0
		if anim == "jump":
			frame = 0 if vel.y < 0.0 else 1
		elif not move.is_empty():
			var total := CharacterDB.move_total(move)
			var count := int(CharacterDB.ANIMS[anim]["frames"])
			frame = CharacterDB.move_frame_index(move_tick, total, count)
		if _anim_name != anim or sprite.animation != anim:
			sprite.play(anim)
		sprite.set_frame_and_progress(frame, 0.0)
		_anim_name = anim
	else:
		var restart := _anim_name != anim
		_play_anim(anim, restart)
		_anim_name = anim


func _play_anim(anim: String, restart := false) -> void:
	if sprite.animation != anim or restart:
		sprite.play(anim)
		if restart:
			sprite.frame = 0
