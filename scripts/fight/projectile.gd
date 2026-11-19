class_name Projectile
extends Node2D

## Karen's clipboard, and anything else that travels. Collision is resolved by
## the arena so both projectiles and melee hits share the same hit pipeline.

const TICK := 1.0 / 60.0

var owner_index := 0
var facing := 1
var info: Dictionary = {}
var speed := 800.0
var life := 0.9
var dead := false
var connected := false
var _spin := 0.0


func setup(owner: Fighter, data: Dictionary) -> void:
	owner_index = owner.player_index
	facing = owner.facing
	info = data.duplicate(true)
	var move := owner.move
	if not info.has("chip"):
		info["chip"] = move.get("chip", 0.12)
	if not info.has("hit_sfx"):
		info["hit_sfx"] = move.get("hit_sfx", "hit_light")
	# 0 is a real value (Karen's special). Leaving the key off would fall
	# through to the arena's meter default of 8.
	if not info.has("meter_gain"):
		info["meter_gain"] = float(move.get("meter_gain", 0.0))
	if not info.has("height"):
		info["height"] = move.get("height", "mid")
	speed = float(info.get("speed", 800.0))
	life = float(info.get("life", 0.9))
	var board := _local_board()
	# Standing mids bottom out at the heavy hitbox (-150). That is eight pixels
	# into CROUCH_HURTBOX (top -158). The same reach makes a grounded clipboard
	# a mid: it clips a crouch and still crosses a standing torso. Spawn Y is
	# derived from the board rect so the drawn clipboard and the hitbox move
	# together.
	var heavy: Rect2 = CharacterDB.BASE_MOVES["heavy"]["hitbox"]
	var mid_bottom := heavy.position.y + heavy.size.y
	var spawn_y := mid_bottom - (board.position.y + board.size.y)
	position = owner.pos + Vector2(facing * 66.0, spawn_y)
	z_index = 3
	connected = false


func tick() -> void:
	position.x += facing * speed * TICK
	_spin += facing * 9.0 * TICK
	life -= TICK
	if life <= 0.0 or position.x < 60.0 or position.x > 1220.0:
		dead = true


func _local_board() -> Rect2:
	return info.get("rect", Rect2(-13, -26, 26, 34))


func hitbox() -> Rect2:
	var r := _local_board()
	return Rect2(r.position + position, r.size)


func _draw() -> void:
	var body := _local_board()
	draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)
	# Clipboard art uses the collision rect so the sprite cannot drift off the hit.
	draw_rect(body, Color("ded6c0"))
	draw_rect(body, Color("2b2630"), false, 2.0)
	var clip := Rect2(body.get_center().x - 6.0, body.position.y - 3.0, 12.0, 5.0)
	draw_rect(clip, Color("8a8a94"))
	draw_rect(clip, Color("2b2630"), false, 1.0)
	var left := body.position.x + 5.0
	var right := body.end.x - 5.0
	var line_y := body.position.y + 8.0
	for i in 3:
		draw_line(Vector2(left, line_y + i * 8.0), Vector2(right, line_y + i * 8.0), Color("b6b0a4"), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
