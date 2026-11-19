class_name AIController
extends RefCounted

## A deliberately simple, readable opponent. It decides on a fixed beat so it
## can't react frame-perfectly, and it commits to actions instead of reading
## your inputs.

var level := 2
var behavior := "fight"  # "fight" | "dummy"

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


func decide(me: Fighter, foe: Fighter) -> Dictionary:
	var out := InputRouter.blank()
	if behavior == "dummy" or foe == null or me.knockout:
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
		if dist < 190.0 and _rng.randf() < 0.35:
			_pending["light"] = true
		return

	if dist > 175.0:
		_dir = toward
		if dist > 300.0 and dist < 520.0 and _rng.randf() < 0.12:
			_pending["jump"] = true
		return

	# In range: shimmy, then commit.
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

	var roll := _rng.randf()
	if roll < 0.24 and dist < 130.0:
		_crouch = true
		_pending["heavy"] = true  # sweep
	elif roll < 0.5 and dist < 150.0:
		_crouch = true
		_pending["light"] = true  # low poke
	elif roll < 0.78:
		_pending["light"] = true  # jab
	else:
		_pending["heavy"] = true  # heavy

	_attack_cd = [40, 30, 20][level - 1] + _rng.randi_range(0, 14)
