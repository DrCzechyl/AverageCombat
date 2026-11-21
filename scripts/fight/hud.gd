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
		if arena.show_frame_data:
			_draw_frame_data()
			_draw_input_history()
		_draw_training_hints()
	if arena.hitboxes_visible:
		var notice_y := 674.0 if arena.training else 710.0
		_text("HITBOXES ON  -  F1 TO HIDE", Vector2(24, notice_y), 14, UITheme.MUTED)


func _draw_player_side(index: int) -> void:
	var f: Fighter = arena._fighter(index)
	var right := index == 1
	var colorblind := UITheme.is_colorblind()
	var bar := Rect2(36, 42, 500, 26) if not right else Rect2(744, 42, 500, 26)
	var accent: Color = arena.fighter_accent(index)
	var name := arena.fighter_name(index)
	var tag := "1P" if index == 0 else ("CPU" if arena.ai != null else "2P")

	# Fighter nameplate with crisp drop shadow and subtle accent pip
	if right:
		draw_rect(Rect2(1240, 21, 4, 14), accent)
		_right_text("%s  %s" % [tag, name], Vector2(1232, 34), 19, UITheme.INK, _heavy)
	else:
		draw_rect(Rect2(36, 21, 4, 14), accent)
		_text("%s  %s" % [tag, name], Vector2(48, 34), 19, UITheme.INK, _heavy)

	# Beveled gunmetal health bar casing
	var casing := bar.grow(4)
	draw_rect(Rect2(casing.position + Vector2(0, 2), casing.size), Color(0, 0, 0, 0.52))
	draw_rect(casing, Color(0.055, 0.068, 0.092, 0.92))
	draw_rect(casing, Color("2e3542"), false, 1.5)
	draw_line(Vector2(casing.position.x + 1.0, casing.position.y + 1.0),
			Vector2(casing.end.x - 1.0, casing.position.y + 1.0),
			Color(0.82, 0.86, 0.94, 0.16), 1.0)

	# Smoked dark backing + recessed inner top shadow
	draw_rect(bar, Color("0f131a"))
	draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, 4.0), Color(0, 0, 0, 0.42))

	var ratio: float = clampf(f.health / float(f.data["build"]["health"]), 0.0, 1.0)
	var trail_ratio: float = clampf(_trail[index] / float(f.data["build"]["health"]), 0.0, 1.0)
	var fill_color: Color = UITheme.p1_color() if index == 0 else UITheme.p2_color()
	if f.health <= 0.0:
		fill_color = Color("4a3d3d")

	var fill_w := bar.size.x * ratio
	var trail_w := bar.size.x * trail_ratio
	var fill_rect: Rect2
	if right:
		var tx := bar.position.x + bar.size.x - trail_w
		draw_rect(Rect2(tx, bar.position.y, trail_w, bar.size.y), Color(0.84, 0.66, 0.34, 0.62))
		var fx := bar.position.x + bar.size.x - fill_w
		fill_rect = Rect2(fx, bar.position.y, fill_w, bar.size.y)
		draw_rect(fill_rect, fill_color)
		if fill_w > 0.5:
			draw_rect(Rect2(fx, bar.position.y, fill_w, 5.0), Color(1.0, 1.0, 1.0, 0.18))
			draw_rect(Rect2(fx, bar.position.y + 5.0, fill_w, 1.0), Color(1.0, 1.0, 1.0, 0.08))
			draw_rect(Rect2(fx, bar.end.y - 4.0, fill_w, 4.0), Color(0.0, 0.0, 0.0, 0.24))
	else:
		draw_rect(Rect2(bar.position.x, bar.position.y, trail_w, bar.size.y),
				Color(0.84, 0.66, 0.34, 0.62))
		fill_rect = Rect2(bar.position.x, bar.position.y, fill_w, bar.size.y)
		draw_rect(fill_rect, fill_color)
		if fill_w > 0.5:
			draw_rect(Rect2(bar.position.x, bar.position.y, fill_w, 5.0), Color(1.0, 1.0, 1.0, 0.18))
			draw_rect(Rect2(bar.position.x, bar.position.y + 5.0, fill_w, 1.0), Color(1.0, 1.0, 1.0, 0.08))
			draw_rect(Rect2(bar.position.x, bar.end.y - 4.0, fill_w, 4.0), Color(0.0, 0.0, 0.0, 0.24))

	if colorblind:
		var marker_y := bar.position.y + bar.size.y * 0.5
		if right:
			# P2: diamond marker + subtle diagonal hatching on bar fill
			var cx := bar.end.x + 15.0
			var pts := PackedVector2Array([
				Vector2(cx, marker_y - 7.0),
				Vector2(cx + 7.0, marker_y),
				Vector2(cx, marker_y + 7.0),
				Vector2(cx - 7.0, marker_y),
			])
			draw_colored_polygon(pts, fill_color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
					Color("090b10"), 1.5)
			var hx := fill_rect.position.x + 10.0
			while hx < fill_rect.end.x - 4.0:
				draw_line(Vector2(hx - 6.0, fill_rect.end.y - 2.0),
						Vector2(hx, fill_rect.position.y + 2.0),
						Color(0.04, 0.06, 0.09, 0.26), 1.5)
				hx += 16.0
		else:
			# P1: circle marker
			var cx := bar.position.x - 15.0
			draw_circle(Vector2(cx, marker_y), 6.5, fill_color)
			draw_circle(Vector2(cx, marker_y), 6.5, Color("090b10"), false, 1.5)

	# Inner dark frame + recessed 25% tick marks
	draw_rect(bar, Color("090b10"), false, 2.0)
	for i in range(1, 4):
		var x := bar.position.x + bar.size.x * 0.25 * i
		draw_line(Vector2(x, bar.position.y + 1.0), Vector2(x, bar.end.y - 1.0),
				Color(0, 0, 0, 0.36), 1.5)
		draw_line(Vector2(x + 1.0, bar.position.y + 2.0), Vector2(x + 1.0, bar.position.y + 7.0),
				Color(1, 1, 1, 0.12), 1.0)

	# Meter housing + trough
	var meter_rect := Rect2(36, 78, 236, 9) if not right else Rect2(1008, 78, 236, 9)
	var meter_casing := meter_rect.grow(2)
	draw_rect(meter_casing, Color(0.045, 0.055, 0.075, 0.88))
	draw_rect(meter_casing, Color("29303c"), false, 1.0)
	draw_rect(meter_rect, Color("0e1219"))

	var meter_ratio: float = clampf(f.meter / CharacterDB.METER_MAX, 0.0, 1.0)
	var base_meter := UITheme.meter_color()
	var meter_color := base_meter
	var ready := f.meter >= CharacterDB.METER_COST
	if ready:
		var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) / 120.0)
		meter_color = base_meter.lightened(0.28 * pulse)
	var mw := meter_rect.size.x * meter_ratio
	var meter_fill := Rect2(meter_rect.position.x + meter_rect.size.x - mw, meter_rect.position.y,
			mw, meter_rect.size.y) if right else Rect2(meter_rect.position.x, meter_rect.position.y,
			mw, meter_rect.size.y)
	draw_rect(meter_fill, meter_color)
	if mw > 1.0:
		draw_rect(Rect2(meter_fill.position.x, meter_fill.position.y, mw, 2.5),
				Color(1, 1, 1, 0.2))
	if colorblind and mw >= 6.0:
		var step := 10.0 if ready else 14.0
		var tick_col := Color(0.05, 0.07, 0.11, 0.65)
		var mx := meter_fill.position.x + 4.0
		var y_top := meter_fill.position.y + 1.0
		var y_mid := meter_fill.position.y + meter_fill.size.y * 0.5
		var y_bot := meter_fill.end.y - 1.0
		while mx < meter_fill.end.x - 3.0:
			if ready:
				var tip_x := clampf(mx + (-3.0 if right else 3.0), meter_fill.position.x + 1.0,
						meter_fill.end.x - 1.0)
				draw_line(Vector2(mx, y_top), Vector2(tip_x, y_mid), tick_col, 1.5)
				draw_line(Vector2(tip_x, y_mid), Vector2(mx, y_bot), tick_col, 1.5)
			else:
				draw_line(Vector2(mx, y_bot),
						Vector2(minf(mx + 4.0, meter_fill.end.x - 1.0), y_top), tick_col, 1.2)
			mx += step
	# The 50% special threshold notch
	var threshold_x := meter_rect.position.x + meter_rect.size.x * 0.5
	draw_line(Vector2(threshold_x, meter_rect.position.y - 2),
			Vector2(threshold_x, meter_rect.position.y + meter_rect.size.y + 2),
			Color(0, 0, 0, 0.72), 2.0)
	draw_line(Vector2(threshold_x, meter_rect.position.y - 1),
			Vector2(threshold_x, meter_rect.position.y + 1),
			Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.6), 1.0)
	draw_rect(meter_rect, Color("090b10"), false, 1.0)

	var label_pos := Vector2(36, 104) if not right else Vector2(1244, 104)
	var label := "SPECIAL READY" if ready else "METER"
	var label_color := base_meter if ready else UITheme.MUTED
	if right:
		_right_text(label, label_pos, 12, label_color, _heavy if ready else _font)
	else:
		_text(label, label_pos, 12, label_color, _heavy if ready else _font)

	# Combos (attacker's counter, shown on that player's side)
	var hits: int = arena.combo[index]
	if hits >= 2:
		var cd: float = arena.combo_damage[index]
		var text := "%d HIT COMBO" % hits
		if right:
			_right_text(text, Vector2(1244, 158), 26, UITheme.ACCENT, _heavy)
			draw_rect(Rect2(1076, 165, 168, 2), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.65))
			_right_text("%d DAMAGE" % int(cd), Vector2(1244, 184), 14, UITheme.INK, _heavy)
		else:
			_text(text, Vector2(36, 158), 26, UITheme.ACCENT, _heavy)
			draw_rect(Rect2(36, 165, 168, 2), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.65))
			_text("%d DAMAGE" % int(cd), Vector2(36, 184), 14, UITheme.INK, _heavy)


func _draw_center() -> void:
	# Refined brass/steel timer housing
	var panel := Rect2(594, 24, 92, 66)
	draw_rect(Rect2(panel.position + Vector2(0, 3), panel.size).grow(3), Color(0, 0, 0, 0.56))
	draw_rect(panel.grow(2), Color(0.04, 0.05, 0.07, 0.94))
	draw_rect(panel, Color(0.075, 0.09, 0.12, 0.96))
	draw_rect(Rect2(panel.position.x, panel.position.y, panel.size.x, 3.0),
			Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.85))
	draw_rect(panel, UITheme.BORDER, false, 1.5)

	# Clean brass corner ticks
	var tick_col := Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.78)
	var tlen := 8.0
	var x0 := panel.position.x - 1.0
	var y0 := panel.position.y - 1.0
	var x1 := panel.end.x + 1.0
	var y1 := panel.end.y + 1.0
	draw_line(Vector2(x0, y0), Vector2(x0 + tlen, y0), tick_col, 2.0)
	draw_line(Vector2(x0, y0), Vector2(x0, y0 + tlen), tick_col, 2.0)
	draw_line(Vector2(x1, y0), Vector2(x1 - tlen, y0), tick_col, 2.0)
	draw_line(Vector2(x1, y0), Vector2(x1, y0 + tlen), tick_col, 2.0)
	draw_line(Vector2(x0, y1), Vector2(x0 + tlen, y1), tick_col, 2.0)
	draw_line(Vector2(x0, y1), Vector2(x0, y1 - tlen), tick_col, 2.0)
	draw_line(Vector2(x1, y1), Vector2(x1 - tlen, y1), tick_col, 2.0)
	draw_line(Vector2(x1, y1), Vector2(x1, y1 - tlen), tick_col, 2.0)

	if arena.training:
		_text_center("TRAIN", Vector2(640, 70), 24, UITheme.ACCENT, _heavy)
	else:
		var secs := int(ceil(arena.round_time))
		var color := UITheme.DANGER if secs <= 10 else UITheme.INK
		_text_center(str(secs), Vector2(640, 74), 42, color, _heavy)

	_text_center("ROUND %d" % arena.round_number, Vector2(640, 112), 13, UITheme.MUTED, _heavy)

	# Round win pips
	var needed := maxi(1, arena.round_wins_needed)
	for i in needed:
		var x1p := 556.0 - i * 18.0
		var x2p := 724.0 + i * 18.0
		var y := 58.0
		var p1_won: bool = arena.round_wins[0] > i
		var p2_won: bool = arena.round_wins[1] > i
		_pip(Vector2(x1p, y), p1_won)
		_pip(Vector2(x2p, y), p2_won)


func _pip(at: Vector2, filled: bool) -> void:
	draw_circle(at + Vector2(0, 1.0), 6.5, Color(0, 0, 0, 0.55))
	if filled:
		draw_circle(at, 6.0, UITheme.ACCENT)
		draw_circle(at + Vector2(-1.5, -1.5), 2.0, Color(1, 1, 1, 0.35))
		draw_circle(at, 6.0, Color("090b10"), false, 1.5)
	else:
		draw_circle(at, 6.0, Color(0.06, 0.075, 0.1, 0.85))
		draw_circle(at, 6.0, UITheme.BORDER, false, 1.5)


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
	var plate_w := clampf(text_size.x + 112.0, 340.0, 1040.0)
	var plate_h := 104.0 if arena.announce_sub == "" else 148.0
	var plate := Rect2(640.0 - plate_w / 2.0, 156.0, plate_w, plate_h)

	# Smoked-glass callout plate with top & bottom brass hairline rules
	draw_rect(Rect2(plate.position + Vector2(0, 4), plate.size), Color(0, 0, 0, 0.42 * alpha))
	draw_rect(plate, Color(0.04, 0.05, 0.075, 0.80 * alpha))
	draw_rect(plate, Color(0.24, 0.28, 0.36, 0.65 * alpha), false, 1.0)
	var rule_col := Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.88 * alpha)
	draw_rect(Rect2(plate.position.x + 16.0, plate.position.y, plate.size.x - 32.0, 2.0), rule_col)
	draw_rect(Rect2(plate.position.x + 16.0, plate.end.y - 2.0, plate.size.x - 32.0, 2.0), rule_col)

	draw_set_transform(Vector2(640, 228), 0.0, Vector2(grow, grow))
	_text_center(arena.announce_text, Vector2(0, 0), size, color, _heavy)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if arena.announce_sub != "":
		var sc: Color = UITheme.INK
		sc.a = alpha
		_text_center(arena.announce_sub, Vector2(640, 268), 20, sc, _font)


func _draw_frame_data() -> void:
	var box := Rect2(970, 560, 286, 118)
	draw_rect(box, Color(0.055, 0.068, 0.095, 0.88))
	draw_rect(Rect2(box.position.x, box.position.y, box.size.x, 2.0),
			Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.72))
	draw_rect(box, UITheme.BORDER, false, 1.5)
	_text("FRAME DATA", Vector2(box.position.x + 12.0, box.position.y + 20.0), 12, UITheme.MUTED)

	var fd: Dictionary = arena.last_frame_data
	if fd.is_empty():
		_text("ATTACK TO INSPECT", Vector2(box.position.x + 12.0, box.position.y + 66.0),
				14, UITheme.MUTED)
		return

	var move_name := str(fd.get("move", ""))
	var startup := int(fd.get("startup", 0))
	var active := int(fd.get("active", 0))
	var recovery := int(fd.get("recovery", 0))
	var adv := int(fd.get("advantage", 0))
	var outcome := str(fd.get("outcome", "WHIFF"))

	var outcome_color := UITheme.MUTED
	if outcome == "HIT" or outcome == "THROW":
		outcome_color = UITheme.OK
	elif outcome == "BLOCK":
		outcome_color = UITheme.meter_color()

	_text(move_name, Vector2(box.position.x + 12.0, box.position.y + 46.0), 18, UITheme.INK, _heavy)
	_right_text(outcome, Vector2(box.end.x - 12.0, box.position.y + 46.0), 13, outcome_color, _heavy)

	_text("ST %d   AC %d   RC %d" % [startup, active, recovery],
			Vector2(box.position.x + 12.0, box.position.y + 72.0), 14, UITheme.MUTED)

	_text("ADVANTAGE", Vector2(box.position.x + 12.0, box.position.y + 102.0), 13, UITheme.MUTED)
	if outcome == "WHIFF":
		_right_text("--", Vector2(box.end.x - 12.0, box.position.y + 104.0), 20, UITheme.MUTED, _heavy)
	else:
		var adv_text := "+%dF" % adv if adv > 0 else ("%dF" % adv if adv < 0 else "0F")
		var adv_color := UITheme.OK if adv > 0 else (UITheme.DANGER if adv < 0 else UITheme.INK)
		_right_text(adv_text, Vector2(box.end.x - 12.0, box.position.y + 104.0), 22, adv_color, _heavy)


func _draw_input_history() -> void:
	var panel := Rect2(18, 220, 158, 340)
	draw_rect(panel, Color(0.055, 0.068, 0.095, 0.84))
	draw_rect(Rect2(panel.position.x, panel.position.y, panel.size.x, 2.0),
			Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.65))
	draw_rect(panel, UITheme.BORDER, false, 1.5)
	_text("INPUTS", Vector2(panel.position.x + 10.0, panel.position.y + 18.0), 12, UITheme.MUTED)

	var history: Array[Dictionary] = arena.p1_input_history
	var count := mini(history.size(), 10)
	var start_idx := history.size() - count
	for row in count:
		var entry: Dictionary = history[start_idx + row]
		var ry := panel.position.y + 28.0 + float(row) * 30.0
		if row == count - 1:
			draw_rect(Rect2(panel.position.x + 4.0, ry - 2.0, panel.size.x - 8.0, 26.0),
					Color(1.0, 1.0, 1.0, 0.07))

		var dir_sym := "o"
		var dir := int(entry.get("dir", 0))
		if bool(entry.get("jump", false)):
			dir_sym = "^"
		elif bool(entry.get("crouch", false)):
			dir_sym = "v"
		elif dir < 0:
			dir_sym = "<"
		elif dir > 0:
			dir_sym = ">"

		var dir_rect := Rect2(panel.position.x + 8.0, ry, 22.0, 22.0)
		draw_rect(dir_rect, Color("141922"))
		draw_rect(dir_rect, UITheme.BORDER, false, 1.0)
		_text_center(dir_sym, Vector2(dir_rect.position.x + 11.0, dir_rect.position.y + 16.0),
				13, UITheme.INK, _heavy)

		var chips: Array = []
		if bool(entry.get("light", false)):
			chips.append(["L", UITheme.p1_color()])
		if bool(entry.get("heavy", false)):
			chips.append(["H", UITheme.DANGER])
		if bool(entry.get("special", false)):
			chips.append(["S", UITheme.meter_color()])
		if bool(entry.get("block", false)):
			chips.append(["B", UITheme.OK])
		if bool(entry.get("throw", false)):
			chips.append(["T", Color("b07ac0")])

		var cx := panel.position.x + 36.0
		for chip in chips:
			var chip_rect := Rect2(cx, ry, 20.0, 22.0)
			draw_rect(chip_rect, chip[1])
			draw_rect(chip_rect, Color("090b10"), false, 1.0)
			_text_center(str(chip[0]), Vector2(chip_rect.position.x + 10.0, chip_rect.position.y + 16.0),
					12, Color("090b10"), _heavy, false)
			cx += 23.0


func _draw_training_hints() -> void:
	draw_rect(Rect2(0, 690, 1280, 30), Color(0.03, 0.04, 0.06, 0.68))
	draw_rect(Rect2(0, 690, 1280, 1), Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.6))
	_text_center("P1  A/D MOVE  W JUMP  S CROUCH  F LIGHT  G HEAVY  H SPECIAL  V BLOCK  E THROW  F5 RESET",
			Vector2(640, 710), 14, UITheme.MUTED)


# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------


func _text(text: String, pos: Vector2, size: int, color: Color = UITheme.INK,
		font: Font = null, shadow := true) -> void:
	var f := font if font != null else _font
	if shadow:
		draw_string(f, pos + Vector2(1.5, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, size, Color(0, 0, 0, 0.72 * color.a))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _right_text(text: String, pos: Vector2, size: int, color: Color = UITheme.INK,
		font: Font = null, shadow := true) -> void:
	var f := font if font != null else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(pos.x - w, pos.y)
	if shadow:
		draw_string(f, origin + Vector2(1.5, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, size, Color(0, 0, 0, 0.72 * color.a))
	draw_string(f, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_center(text: String, pos: Vector2, size: int, color: Color = UITheme.INK,
		font: Font = null, shadow := true) -> void:
	var f := font if font != null else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(pos.x - w / 2.0, pos.y)
	if shadow:
		var offset := Vector2(2.0, 3.0) if size >= 36 else Vector2(1.5, 2.0)
		draw_string(f, origin + offset, text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, size, Color(0, 0, 0, 0.78 * color.a))
	draw_string(f, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
