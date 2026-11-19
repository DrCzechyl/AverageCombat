class_name FightHud
extends Control

## Fully custom-drawn HUD (health, meter, timer, rounds, combos, callouts).
## Reads the arena directly; the arena never has to push UI updates.

var arena: Arena = null

var _trail := [0.0, 0.0]
var _font: Font
var _heavy: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UITheme.get_ui_font()
	_heavy = UITheme.heading_font


func snap_health() -> void:
	if arena == null:
		return
	_trail[0] = arena.p1.health
	_trail[1] = arena.p2.health


func _process(delta: float) -> void:
	if arena == null:
		return
	var healths := [arena.p1.health, arena.p2.health]
	for i in 2:
		if healths[i] > _trail[i]:
			_trail[i] = healths[i]
		else:
			_trail[i] = move_toward(_trail[i], healths[i], delta * 340.0)
	queue_redraw()


func _draw() -> void:
	if arena == null:
		return
	_draw_player_side(0)
	_draw_player_side(1)
	_draw_center()
	_draw_callout()
	if arena.training:
		_draw_training_hints()
	if arena.hitboxes_visible:
		var notice_y := 674.0 if arena.training else 710.0
		_text("HITBOXES ON  -  F1 TO HIDE", Vector2(24, notice_y), 14, UITheme.MUTED)


func _draw_player_side(index: int) -> void:
	var f: Fighter = arena._fighter(index)
	var right := index == 1
	var bar := Rect2(36, 42, 500, 26) if not right else Rect2(744, 42, 500, 26)
	var accent: Color = arena.fighter_accent(index)
	var name := arena.fighter_name(index)
	var tag := "1P" if index == 0 else ("CPU" if arena.ai != null else "2P")

	# name + tag
	if right:
		_right_text("%s  %s" % [tag, name], Vector2(1244, 34), 20, accent)
	else:
		_text("%s  %s" % [tag, name], Vector2(36, 34), 20, accent)

	# frame + background
	draw_rect(bar.grow(4), Color(0, 0, 0, 0.6))
	draw_rect(bar, Color("1b2231"))

	var ratio: float = clampf(f.health / float(f.data["build"]["health"]), 0.0, 1.0)
	var trail_ratio: float = clampf(_trail[index] / float(f.data["build"]["health"]), 0.0, 1.0)
	var fill_color: Color = UITheme.P1 if index == 0 else UITheme.P2
	if f.health <= 0.0:
		fill_color = Color("6a5a5a")

	var fill_w := bar.size.x * ratio
	var trail_w := bar.size.x * trail_ratio
	if right:
		var tx := bar.position.x + bar.size.x - trail_w
		draw_rect(Rect2(tx, bar.position.y, trail_w, bar.size.y), Color(1.0, 0.86, 0.5, 0.55))
		var fx := bar.position.x + bar.size.x - fill_w
		draw_rect(Rect2(fx, bar.position.y, fill_w, bar.size.y), fill_color)
		draw_rect(Rect2(fx, bar.position.y, fill_w, bar.size.y / 3.0), Color(1, 1, 1, 0.16))
	else:
		draw_rect(Rect2(bar.position.x, bar.position.y, trail_w, bar.size.y),
				Color(1.0, 0.86, 0.5, 0.55))
		draw_rect(Rect2(bar.position.x, bar.position.y, fill_w, bar.size.y), fill_color)
		draw_rect(Rect2(bar.position.x, bar.position.y, fill_w, bar.size.y / 3.0),
				Color(1, 1, 1, 0.16))

	draw_rect(bar, Color("0d1119"), false, 2.0)
	# notches every 25%
	for i in range(1, 4):
		var x := bar.position.x + bar.size.x * 0.25 * i
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.position.y + bar.size.y),
				Color(0, 0, 0, 0.25), 1.0)

	# meter
	var meter_rect := Rect2(36, 78, 236, 9) if not right else Rect2(1008, 78, 236, 9)
	draw_rect(meter_rect, Color("161c29"))
	var meter_ratio: float = clampf(f.meter / CharacterDB.METER_MAX, 0.0, 1.0)
	var meter_color := UITheme.ACCENT
	if f.meter >= CharacterDB.METER_COST:
		var pulse := 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) / 120.0)
		meter_color = UITheme.ACCENT.lightened(0.35 * pulse)
	var mw := meter_rect.size.x * meter_ratio
	if right:
		draw_rect(Rect2(meter_rect.position.x + meter_rect.size.x - mw, meter_rect.position.y,
				mw, meter_rect.size.y), meter_color)
	else:
		draw_rect(Rect2(meter_rect.position.x, meter_rect.position.y, mw,
				meter_rect.size.y), meter_color)
	# the 50% special threshold
	var threshold_x := meter_rect.position.x + meter_rect.size.x * 0.5
	draw_line(Vector2(threshold_x, meter_rect.position.y - 2),
			Vector2(threshold_x, meter_rect.position.y + meter_rect.size.y + 2),
			Color(0, 0, 0, 0.55), 2.0)
	draw_rect(meter_rect, Color("0d1119"), false, 1.0)

	var ready := f.meter >= CharacterDB.METER_COST
	var label_pos := Vector2(36, 104) if not right else Vector2(1244, 104)
	var label := "SPECIAL READY" if ready else "METER"
	if right:
		_right_text(label, label_pos, 12, UITheme.ACCENT if ready else UITheme.MUTED)
	else:
		_text(label, label_pos, 12, UITheme.ACCENT if ready else UITheme.MUTED)

	# combos (attacker's counter, shown on that player's side)
	var hits: int = arena.combo[index]
	if hits >= 2:
		var cd: float = arena.combo_damage[index]
		var text := "%d HIT COMBO" % hits
		if right:
			_right_text(text, Vector2(1244, 160), 26, UITheme.ACCENT)
			_right_text("%d DAMAGE" % int(cd), Vector2(1244, 184), 14, UITheme.INK)
		else:
			_text(text, Vector2(36, 160), 26, UITheme.ACCENT)
			_text("%d DAMAGE" % int(cd), Vector2(36, 184), 14, UITheme.INK)


func _draw_center() -> void:
	# timer panel
	var panel := Rect2(594, 24, 92, 66)
	draw_rect(panel.grow(3), Color(0, 0, 0, 0.6))
	draw_rect(panel, Color("161c29"))
	draw_rect(panel, UITheme.BORDER, false, 2.0)

	if arena.training:
		_text_center("TRAIN", Vector2(640, 72), 26, UITheme.ACCENT, _heavy)
	else:
		var secs := int(ceil(arena.round_time))
		var color := UITheme.DANGER if secs <= 10 else UITheme.INK
		_text_center(str(secs), Vector2(640, 74), 42, color, _heavy)

	_text_center("ROUND %d" % arena.round_number, Vector2(640, 112), 14, UITheme.MUTED)

	# round win pips
	var needed := maxi(1, arena.round_wins_needed)
	for i in needed:
		var x1 := 556.0 - i * 18.0
		var x2 := 724.0 + i * 18.0
		var y := 58.0
		var p1_won: bool = arena.round_wins[0] > i
		var p2_won: bool = arena.round_wins[1] > i
		_pip(Vector2(x1, y), p1_won)
		_pip(Vector2(x2, y), p2_won)


func _pip(at: Vector2, filled: bool) -> void:
	if filled:
		draw_circle(at, 6.0, UITheme.ACCENT)
		draw_circle(at, 6.0, Color(0, 0, 0, 0.5), false, 2.0)
	else:
		draw_circle(at, 6.0, Color(0, 0, 0, 0.35))
		draw_circle(at, 6.0, UITheme.BORDER, false, 2.0)


func _draw_callout() -> void:
	if arena.announce_ticks <= 0 or arena.announce_text == "":
		return
	var t := 1.0 - float(arena.announce_ticks) / float(arena.announce_total)
	var alpha := clampf(minf(t * 6.0, (1.0 - t) * 5.0), 0.0, 1.0)
	var grow := 1.0 + 0.10 * (1.0 - clampf(t * 4.0, 0.0, 1.0))
	var color: Color = arena.announce_color
	color.a = alpha
	var size := 64 if arena.announce_text.length() <= 8 else 48
	var text_size := _heavy.get_string_size(arena.announce_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var plate_w := clampf(text_size.x + 96.0, 320.0, 1040.0)
	var plate_h := 104.0 if arena.announce_sub == "" else 148.0
	var plate := Rect2(640.0 - plate_w / 2.0, 156.0, plate_w, plate_h)
	draw_rect(plate, Color(0.03, 0.04, 0.07, 0.62 * alpha))
	draw_rect(plate, Color(0.31, 0.37, 0.5, 0.9 * alpha), false, 2.0)

	draw_set_transform(Vector2(640, 228), 0.0, Vector2(grow, grow))
	_text_center(arena.announce_text, Vector2(0, 0), size, color, _heavy)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if arena.announce_sub != "":
		var sc: Color = UITheme.INK
		sc.a = alpha
		_text_center(arena.announce_sub, Vector2(640, 268), 20, sc, _font)


func _draw_training_hints() -> void:
	draw_rect(Rect2(0, 690, 1280, 30), Color(0, 0, 0, 0.45))
	_text_center("P1  A/D MOVE   W JUMP   S CROUCH   F LIGHT   G HEAVY   H SPECIAL   V BLOCK",
			Vector2(640, 710), 14, UITheme.MUTED)


# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------


func _text(text: String, pos: Vector2, size: int, color: Color = UITheme.INK,
		font: Font = null) -> void:
	draw_string(font if font != null else _font, pos, text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, size, color)


func _right_text(text: String, pos: Vector2, size: int, color: Color = UITheme.INK,
		font: Font = null) -> void:
	var f := font if font != null else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, Vector2(pos.x - w, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_center(text: String, pos: Vector2, size: int, color: Color = UITheme.INK,
		font: Font = null) -> void:
	var f := font if font != null else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, Vector2(pos.x - w / 2.0, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, size, color)
