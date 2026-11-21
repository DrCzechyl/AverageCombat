class_name AIController
extends RefCounted

## A deliberately simple, readable opponent. It decides on a fixed beat so it
## can't react frame-perfectly, and it commits to actions instead of reading
## your inputs.
##
## Ground normals are chosen only when the posed hitbox overlaps the opponent's
## hurtbox. A flat stop at 175px sits past standing reach (jab about 148px,
## heavy about 162px), so the CPU used to whiff until a special landed.

const GROUND_NORMALS := ["sweep", "low", "jab", "heavy"]
const NORMAL_WEIGHTS := {
	"sweep": 24,
	"low": 26,
	"jab": 28,
	"heavy": 22,
}

var level := 2
var behavior := "fight"  # "fight" | "dummy" | "dummy_crouch" | "dummy_block" | "dummy_jump"

var _rng := RandomNumberGenerator.new()
var _tick := 0
var _interval := 12
var _dir := 0
var _crouch := false
var _block_ticks := 0
var _crouch_block := false
var _attack_cd := 0
var _retreat_ticks := 0
var _pending: Dictionary = {}


func _init(ai_level := 2, ai_behavior := "fight") -> void:
	level = clampi(ai_level, 1, 3)
	behavior = ai_behavior
	_rng.randomize()
	match level:
		1: _interval = 19
		2: _interval = 12
		3: _interval = 7


func reset() -> void:
	_tick = 0
	_dir = 0
	_crouch = false
	_block_ticks = 0
	_crouch_block = false
	_attack_cd = 0
	_retreat_ticks = 0
	_pending.clear()


func decide(me: Fighter, foe: Fighter) -> Dictionary:
	var out := InputRouter.blank()
	if foe == null or me.knockout:
		return out
	match behavior:
		"dummy":
			return out
		"dummy_crouch":
			out["crouch"] = true
			return out
		"dummy_block":
			if foe.is_attacking():
				out["block"] = true
				if str(foe.move.get("height", "mid")) == "low":
					out["crouch"] = true
			return out
		"dummy_jump":
			_tick += 1
			if _tick % 50 == 1 and not me.airborne:
				out["jump"] = true
			return out

	_tick += 1
	_attack_cd = maxi(0, _attack_cd - 1)
	if _block_ticks > 0:
		_block_ticks -= 1

	var dx := foe.pos.x - me.pos.x
	var dist := absf(dx)
	var toward := 1 if dx >= 0.0 else -1

	if _block_ticks <= 0 and _tick % _interval == 0:
		_think(me, foe, dist, toward)

	if _retreat_ticks > 0:
		_retreat_ticks -= 1
		_dir = -toward
		_crouch = false

	if _block_ticks > 0:
		out["block"] = true
		out["crouch"] = _crouch_block
		out["dir"] = _dir
		return out

	out["dir"] = _dir
	out["crouch"] = _crouch
	if not _pending.is_empty():
		for key in _pending:
			out[key] = true
		_pending.clear()
	return out


func _think(me: Fighter, foe: Fighter, dist: float, toward: int) -> void:
	_crouch = false

	# Block incoming attacks, sometimes in the correct stance.
	if foe.is_attacking() and dist < 300.0:
		var chance: float = [0.16, 0.36, 0.58][level - 1]
		if _rng.randf() < chance:
			_block_ticks = _rng.randi_range(14, 28)
			_crouch_block = str(foe.move.get("height", "mid")) == "low" or _rng.randf() < 0.3
			_dir = 0
			return

	# Keep distance when hurt badly.
	if me.health < float(me.data["build"]["health"]) * 0.25 and _rng.randf() < 0.25:
		_retreat_ticks = _rng.randi_range(16, 34)
		_block_ticks = _rng.randi_range(6, 14)
		_crouch_block = false
		return

	if me.airborne:
		if move_reaches(me, foe, "air") and _rng.randf() < 0.35:
			_pending["light"] = true
		return

	var throw_range := float(me.data.get("build", {}).get("throw_range", CharacterDB.THROW_RANGE))
	if dist <= throw_range and not foe.airborne and foe.blocking \
			and _attack_cd <= 0 and _rng.randf() < 0.25:
		_pending["throw"] = true
		_dir = 0
		_attack_cd = [42, 34, 24][level - 1]
		return

	var reachable := _reachable_normals(me, foe)
	if reachable.is_empty():
		if _attack_cd <= 0 and me.meter >= CharacterDB.METER_COST:
			var special: Dictionary = me.data.get("moves", {}).get("special", {})
			if special.has("projectile"):
				if dist >= 160.0 and dist <= 720.0 and _rng.randf() < 0.28:
					_dir = 0
					_pending["special"] = true
					_attack_cd = [46, 38, 30][level - 1] + _rng.randi_range(0, 12)
					return
			elif float(special.get("lunge", 0.0)) > 0.0:
				var lunge := float(special.get("lunge", 0.0))
				if dist >= 110.0 and dist <= 165.0 + lunge and _rng.randf() < 0.22:
					_dir = 0
					_pending["special"] = true
					_attack_cd = [46, 38, 30][level - 1] + _rng.randi_range(0, 12)
					return
		_dir = toward
		if dist > 300.0 and dist < 520.0 and _rng.randf() < 0.12:
			_pending["jump"] = true
		return

	# In range: shimmy, then commit to a normal that actually overlaps.
	if dist < 92.0 and _rng.randf() < 0.3:
		_dir = -toward
	else:
		_dir = 0

	if _attack_cd > 0:
		return

	if me.meter >= CharacterDB.METER_COST and _rng.randf() < 0.3:
		_pending["special"] = true
		_attack_cd = [46, 38, 30][level - 1] + _rng.randi_range(0, 12)
		return

	_commit_normal(_choose_normal(reachable))


## True when the move's posed hitbox would overlap the opponent this frame.
## Ground attacks face the opponent the way start_move does. Lunge is ignored
## so a normal is never started from a spacing that would whiff.
func move_reaches(me: Fighter, foe: Fighter, move_name: String) -> bool:
	if me == null or foe == null:
		return false
	var moves: Dictionary = me.data.get("moves", {})
	if not moves.has(move_name):
		return false
	var move: Dictionary = moves[move_name]
	if not move.has("hitbox"):
		return false
	var facing := me.facing
	if not me.airborne:
		facing = 1 if foe.pos.x >= me.pos.x else -1
	return me.move_hitbox(move, facing).intersects(foe.hurtbox())


func _reachable_normals(me: Fighter, foe: Fighter) -> Array:
	var found: Array = []
	for move_name in GROUND_NORMALS:
		if move_reaches(me, foe, move_name):
			found.append(move_name)
	return found


func _choose_normal(names: Array) -> String:
	var total := 0
	for move_name in names:
		total += int(NORMAL_WEIGHTS[move_name])
	var roll := _rng.randi_range(1, total)
	var cursor := 0
	for move_name in names:
		cursor += int(NORMAL_WEIGHTS[move_name])
		if roll <= cursor:
			return str(move_name)
	return str(names[0])


func _commit_normal(move_name: String) -> void:
	if move_name == "sweep" or move_name == "low":
		_crouch = true
	if move_name == "heavy" or move_name == "sweep":
		_pending["heavy"] = true
	else:
		_pending["light"] = true
	_attack_cd = [40, 30, 20][level - 1] + _rng.randi_range(0, 14)
