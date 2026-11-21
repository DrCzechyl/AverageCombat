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
var sim_pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var _visual_displaced := false


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
	var offset: Vector2 = info.get("spawn_offset", Vector2(66, -196))
	position = owner.pos + Vector2(facing * offset.x, offset.y)
	sim_pos = position
	prev_pos = position
	_visual_displaced = false
	z_index = 3
	connected = false


func present_at(at: Vector2) -> void:
	if not _visual_displaced:
		sim_pos = position
	_visual_displaced = true
	position = at


func restore_sim_pos() -> void:
	if _visual_displaced:
		position = sim_pos
		_visual_displaced = false


func tick() -> void:
	restore_sim_pos()
	prev_pos = position
	position.x += facing * speed * TICK
	sim_pos = position
	_spin += facing * 2.0 * TICK
	queue_redraw()
	life -= TICK
	if life <= 0.0 or position.x < 60.0 or position.x > 1220.0:
		dead = true


func to_state() -> Dictionary:
	restore_sim_pos()
	return {
		"owner_index": owner_index,
		"facing": facing,
		"info": info.duplicate(true),
		"speed": speed,
		"life": life,
		"dead": dead,
		"connected": connected,
		"spin": _spin,
		"pos": position,
		"prev_pos": prev_pos,
	}


func from_state(s: Dictionary) -> void:
	owner_index = int(s["owner_index"])
	facing = int(s["facing"])
	info = (s["info"] as Dictionary).duplicate(true)
	speed = float(s["speed"])
	life = float(s["life"])
	dead = bool(s["dead"])
	connected = bool(s["connected"])
	_spin = float(s["spin"])
	position = s["pos"]
	sim_pos = position
	prev_pos = s["prev_pos"]
	_visual_displaced = false
	z_index = 3
	queue_redraw()


func _local_board() -> Rect2:
	return info.get("rect", Rect2(-13, -26, 26, 34))


func hitbox() -> Rect2:
	var r := _local_board()
	return Rect2(r.position + position, r.size)


func _draw() -> void:
	var body := _local_board()
	var center := body.get_center()

	# Faint directional air-wake / motion streaks trailing behind the spinning clipboard
	var trail := -float(facing)
	draw_polygon(PackedVector2Array([
		Vector2(center.x + trail * 10.0, center.y - 11.0),
		Vector2(center.x + trail * 42.0, center.y - 7.0),
		Vector2(center.x + trail * 12.0, center.y - 4.0),
	]), PackedColorArray([Color(0.86, 0.82, 0.74, 0.24)]))
	draw_polygon(PackedVector2Array([
		Vector2(center.x + trail * 8.0, center.y + 3.0),
		Vector2(center.x + trail * 34.0, center.y + 5.0),
		Vector2(center.x + trail * 10.0, center.y + 9.0),
	]), PackedColorArray([Color(0.82, 0.78, 0.70, 0.18)]))

	draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)

	# Subtle offset shadow behind the spinning wood board
	var shadow_rect := Rect2(body.position + Vector2(2.0, 2.5), body.size)
	draw_rect(shadow_rect, Color(0.08, 0.06, 0.08, 0.28))

	# Illustrated masonite / walnut wood-grain clipboard body (exact _local_board() bounds)
	draw_rect(body, Color("7d5736"))
	# Subtle beveled light/shadow edges & vertical wood grain streaks
	draw_line(
		Vector2(body.position.x + 1.0, body.position.y + 1.0),
		Vector2(body.end.x - 1.0, body.position.y + 1.0),
		Color("a3764d"), 1.5
	)
	draw_line(
		Vector2(body.position.x + 1.0, body.position.y + 1.0),
		Vector2(body.position.x + 1.0, body.end.y - 1.0),
		Color("966b44"), 1.5
	)
	draw_line(
		Vector2(body.end.x - 1.0, body.position.y + 1.5),
		Vector2(body.end.x - 1.0, body.end.y - 1.0),
		Color("4d331e"), 1.5
	)
	draw_line(
		Vector2(body.position.x + 1.5, body.end.y - 1.0),
		Vector2(body.end.x - 1.0, body.end.y - 1.0),
		Color("462e1b"), 1.5
	)
	for gx in [body.position.x + 4.0, body.position.x + 10.0, body.end.x - 5.0]:
		draw_line(
			Vector2(gx, body.position.y + 2.0),
			Vector2(gx + 0.5, body.end.y - 2.0),
			Color(0.36, 0.24, 0.14, 0.42), 1.0
		)
	# Tinted dark umber-charcoal graphic-novel ink contour
	draw_rect(body, Color("1e1715"), false, 1.5)

	# Slightly crumpled, dog-eared cream legal sheet with soft contact shadow on wood
	var px0 := body.position.x + 3.0
	var py0 := body.position.y + 4.0
	var px1 := body.end.x - 3.0
	var py1 := body.end.y - 3.0
	var fold := 4.5
	var paper_shadow := PackedVector2Array([
		Vector2(px0 + 1.0, py0 + 1.5),
		Vector2(px1 + 1.0, py0 + 1.0),
		Vector2(px1 + 1.0, py1 - fold + 1.0),
		Vector2(px1 - fold + 1.0, py1 + 1.5),
		Vector2(px0 + 1.0, py1 + 1.5),
	])
	draw_colored_polygon(paper_shadow, Color(0.18, 0.11, 0.06, 0.35))

	var paper := PackedVector2Array([
		Vector2(px0, py0),
		Vector2(px1, py0 - 0.5),
		Vector2(px1, py1 - fold),
		Vector2(px1 - fold, py1),
		Vector2(px0, py1),
	])
	draw_colored_polygon(paper, Color("e1d8c2"))
	# Subtle paper crease shading across lower third
	draw_colored_polygon(PackedVector2Array([
		Vector2(px0, py1 - 9.0),
		Vector2(px1, py1 - 11.0),
		Vector2(px1, py1 - fold),
		Vector2(px1 - fold, py1),
		Vector2(px0, py1),
	]), Color(0.76, 0.71, 0.61, 0.38))
	# Folded dog-ear corner flap
	draw_colored_polygon(PackedVector2Array([
		Vector2(px1 - fold, py1),
		Vector2(px1, py1 - fold),
		Vector2(px1 - fold, py1 - fold),
	]), Color("c4baa2"))

	# Red HOA notice header stripe & crisp dark-slate legal ink lines
	draw_line(Vector2(px0 + 2.5, py0 + 3.5), Vector2(px1 - 4.0, py0 + 3.0), Color("96322e"), 1.8)
	var line_widths := [1.0, 0.88, 0.94, 0.64]
	for i in line_widths.size():
		var ly := py0 + 8.0 + i * 4.5
		var lx1 := lerpf(px0 + 2.5, px1 - 2.5, line_widths[i])
		draw_line(Vector2(px0 + 2.5, ly), Vector2(lx1, ly - 0.2), Color("4f4b45"), 1.2)

	# Beveled brushed steel/brass spring clip centered at top edge
	var cx := body.get_center().x
	var clip_shadow := Rect2(cx - 7.0, body.position.y - 1.5, 14.0, 6.5)
	draw_rect(clip_shadow, Color(0.12, 0.09, 0.07, 0.42))
	var clip := Rect2(cx - 6.5, body.position.y - 3.5, 13.0, 6.0)
	draw_rect(clip, Color("90969e"))
	# Metallic top highlight bevel & brass hinge bar
	draw_line(
		Vector2(clip.position.x + 1.0, clip.position.y + 1.0),
		Vector2(clip.end.x - 1.0, clip.position.y + 1.0),
		Color("d2d8df"), 1.2
	)
	draw_rect(Rect2(cx - 4.0, body.position.y - 4.8, 8.0, 2.2), Color("b89858"))
	draw_rect(clip, Color("242228"), false, 1.0)
	# Twin tiny clip rivets
	draw_circle(Vector2(cx - 4.0, clip.position.y + 3.2), 0.9, Color("484b52"))
	draw_circle(Vector2(cx + 4.0, clip.position.y + 3.2), 0.9, Color("484b52"))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
