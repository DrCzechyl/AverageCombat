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
var _spin := 0.0


func setup(owner: Fighter, data: Dictionary) -> void:
	owner_index = owner.player_index
	facing = owner.facing
	info = data.duplicate(true)
	speed = float(info.get("speed", 800.0))
	life = float(info.get("life", 0.9))
	position = owner.pos + Vector2(facing * 66.0, -196.0)
	z_index = 3


func tick() -> void:
	position.x += facing * speed * TICK
	_spin += facing * 9.0 * TICK
	life -= TICK
	if life <= 0.0 or position.x < 60.0 or position.x > 1220.0:
		dead = true


func hitbox() -> Rect2:
	var r: Rect2 = info.get("rect", Rect2(-13, -26, 26, 34))
	return Rect2(r.position + position, r.size)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)
	# clipboard
	draw_rect(Rect2(-13, -18, 26, 34), Color("ded6c0"))
	draw_rect(Rect2(-13, -18, 26, 34), Color("2b2630"), false, 2.0)
	draw_rect(Rect2(-6, -21, 12, 5), Color("8a8a94"))
	draw_rect(Rect2(-6, -21, 12, 5), Color("2b2630"), false, 1.0)
	for i in 3:
		draw_line(Vector2(-8, -10 + i * 8), Vector2(8, -10 + i * 8), Color("b6b0a4"), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
