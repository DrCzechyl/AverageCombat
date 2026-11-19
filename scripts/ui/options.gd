extends Control

## Options. Every row is a button that cycles its value, so the whole screen is
## usable with one key or one pad, and settings save immediately.

const ROW_W := 560.0
const ROW_H := 46.0

var _rows: Array[Button] = []
var _reset_button: Button
var _back_button: Button


func _ready() -> void:
	UI.backdrop(self, "res://assets/stages/backyard.png", Color(0.26, 0.30, 0.30), 0.66)
	UI.banner(self, "OPTIONS", 44, 52, UITheme.INK, UITheme.heading_font)
	UI.rule(self, Vector2(400, 116), 480, UITheme.ACCENT, 3)

	var x := 640.0 - ROW_W / 2.0
	var y := 156.0
	var gap := 10.0

	_rows.append(_row("MASTER VOLUME", x, y)); y += ROW_H + gap
	_rows.append(_row("DIFFICULTY", x, y)); y += ROW_H + gap
	_rows.append(_row("SCREEN SHAKE", x, y)); y += ROW_H + gap
	_rows.append(_row("HITSTOP", x, y)); y += ROW_H + gap
	_rows.append(_row("HITBOXES", x, y)); y += ROW_H + gap
	_rows.append(_row("FULLSCREEN", x, y)); y += ROW_H + gap

	_reset_button = UI.button(self, "RESET STATS", Vector2(390, y + 6), Vector2(240, 44), 18)
	_reset_button.pressed.connect(_reset_stats)
	_back_button = UI.button(self, "BACK", Vector2(650, y + 6), Vector2(240, 44), 18)
	_back_button.pressed.connect(_back)

	for footer in [
		["CHANGES SAVE AUTOMATICALLY", 620, 14],
		["P1  A/D MOVE  W JUMP  S CROUCH  F LIGHT  G HEAVY  H SPECIAL  V BLOCK", 644, 13],
		["P2  ARROWS  NUMPAD 1/2/3  NUMPAD 0 BLOCK      ESC PAUSE", 664, 13],
	]:
		var line := UI.label(self, str(footer[0]), Vector2(0, float(footer[1])),
				int(footer[2]), UITheme.MUTED)
		line.size = Vector2(1280, 20)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_refresh()
	_rows[0].grab_focus()


func _row(title: String, x: float, y: float) -> Button:
	var b := UI.button(self, title, Vector2(x, y), Vector2(ROW_W, ROW_H), 19)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("title", title)

	var value := Label.new()
	value.position = Vector2(ROW_W - 190, 9)
	value.size = Vector2(160, 30)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 19)
	value.add_theme_color_override("font_color", UITheme.ACCENT)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(value)
	b.set_meta("value_label", value)

	b.pressed.connect(func(): _cycle(title))
	return b


func _cycle(title: String) -> void:
	match title:
		"MASTER VOLUME":
			var steps := [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
			var current := int(round(float(SaveData.settings["volume"]) * 100.0))
			var next: int = steps[0]
			for step in steps:
				if step > current:
					next = step
					break
			SaveData.set_setting("volume", float(next) / 100.0)
		"DIFFICULTY":
			var d := int(SaveData.settings["difficulty"])
			SaveData.set_setting("difficulty", d % 3 + 1)
		"SCREEN SHAKE":
			SaveData.set_setting("screen_shake", not bool(SaveData.settings["screen_shake"]))
		"HITSTOP":
			SaveData.set_setting("hitstop", not bool(SaveData.settings["hitstop"]))
		"HITBOXES":
			SaveData.set_setting("show_hitboxes", not bool(SaveData.settings["show_hitboxes"]))
		"FULLSCREEN":
			SaveData.set_setting("fullscreen", not bool(SaveData.settings["fullscreen"]))
	_refresh()


func _refresh() -> void:
	for b in _rows:
		var title: String = b.get_meta("title")
		b.text = title
		var value: Label = b.get_meta("value_label")
		value.text = _value_text(title)


func _value_text(title: String) -> String:
	match title:
		"MASTER VOLUME":
			return "%d%%" % int(round(float(SaveData.settings["volume"]) * 100.0))
		"DIFFICULTY":
			return ["EASY", "NORMAL", "HARD"][int(SaveData.settings["difficulty"]) - 1]
		"SCREEN SHAKE":
			return "ON" if bool(SaveData.settings["screen_shake"]) else "OFF"
		"HITSTOP":
			return "ON" if bool(SaveData.settings["hitstop"]) else "OFF"
		"HITBOXES":
			return "ON" if bool(SaveData.settings["show_hitboxes"]) else "OFF"
		"FULLSCREEN":
			return "ON" if bool(SaveData.settings["fullscreen"]) else "OFF"
	return ""


func _reset_stats() -> void:
	SaveData.reset_stats()
	Sfx.play_ui("confirm")
	_flash("STATS RESET")


func _flash(message: String) -> void:
	var label := UI.label(self, message, Vector2(0, 574), 16, UITheme.OK)
	label.size = Vector2(1280, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tween := create_tween()
	tween.tween_interval(1.1)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _back() -> void:
	Sfx.play_ui("back")
	Game.go_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		accept_event()
