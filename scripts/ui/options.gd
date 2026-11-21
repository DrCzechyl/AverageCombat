extends Control

## Options. Every row is a button that cycles its value, so the whole screen is
## usable with one key or one pad, and settings save immediately.

const ROW_W := 560.0
const ROW_H := 44.0
const ACTION_BTN_W := 196.0
const ACTION_BTN_H := 44.0
const ACTION_BTN_GAP := 16.0
const KEYBIND_COL_W := 400.0
const KEYBIND_ROW_H := 36.0
const KEYBIND_ROW_GAP := 6.0

var _rows: Array[Button] = []
var _controls_button: Button
var _reset_button: Button
var _back_button: Button

var _keybind_overlay: Control
var _keybind_p1_header: Label
var _keybind_p2_header: Label
var _keybind_buttons: Dictionary = {}
var _keybind_order: Array[Button] = []
var _keybind_reset_button: Button
var _keybind_done_button: Button
var _capturing_action := ""


func _ready() -> void:
	UI.backdrop(self, "res://assets/stages/backyard.png", Color(0.28, 0.30, 0.34), 0.66)
	UI.banner(self, "OPTIONS", 32, 44, UITheme.INK, UITheme.heading_font)
	UI.rule(self, Vector2(400, 98), 480, UITheme.ACCENT, 2)

	var x := 640.0 - ROW_W / 2.0
	var y := 122.0
	var gap := 8.0

	_rows.append(_row("MASTER VOLUME", x, y)); y += ROW_H + gap
	_rows.append(_row("DIFFICULTY", x, y)); y += ROW_H + gap
	_rows.append(_row("SCREEN SHAKE", x, y)); y += ROW_H + gap
	_rows.append(_row("HITSTOP", x, y)); y += ROW_H + gap
	_rows.append(_row("HITBOXES", x, y)); y += ROW_H + gap
	_rows.append(_row("FULLSCREEN", x, y)); y += ROW_H + gap
	_rows.append(_row("COLORBLIND HUD", x, y)); y += ROW_H + gap

	var total_w := ACTION_BTN_W * 3.0 + ACTION_BTN_GAP * 2.0
	var bx := 640.0 - total_w / 2.0
	var by := y + 12.0
	_controls_button = UI.button(self, "CONTROLS", Vector2(bx, by), Vector2(ACTION_BTN_W, ACTION_BTN_H), 17)
	_controls_button.pressed.connect(_open_keybinds)
	_reset_button = UI.button(self, "RESET STATS", Vector2(bx + ACTION_BTN_W + ACTION_BTN_GAP, by),
			Vector2(ACTION_BTN_W, ACTION_BTN_H), 17)
	_reset_button.pressed.connect(_reset_stats)
	_back_button = UI.button(self, "BACK", Vector2(bx + (ACTION_BTN_W + ACTION_BTN_GAP) * 2.0, by),
			Vector2(ACTION_BTN_W, ACTION_BTN_H), 17, false)
	_back_button.pressed.connect(_back)

	for footer in [
		["CHANGES SAVE AUTOMATICALLY", 620, 14],
		["P1  A/D MOVE  W JUMP  S CROUCH  F LIGHT  G HEAVY  H SPECIAL  V BLOCK  E THROW", 644, 13],
		["P2  ARROWS  NUMPAD 1/2/3  NUMPAD 0 BLOCK  NUMPAD 4 THROW      ESC PAUSE", 664, 13],
	]:
		var line := UI.label(self, str(footer[0]), Vector2(0, float(footer[1])),
				int(footer[2]), UITheme.MUTED)
		line.size = Vector2(1280, 20)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_build_keybind_overlay()
	_refresh()
	_rows[0].grab_focus()


func _row(title: String, x: float, y: float) -> Button:
	var b := UI.button(self, title, Vector2(x, y), Vector2(ROW_W, ROW_H), 18)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_button_padding(b, 20, 6, 2, 3)
	b.set_meta("title", title)

	var value := Label.new()
	value.position = Vector2(ROW_W - 190, 8)
	value.size = Vector2(160, 28)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_override("font", UITheme.heading_font)
	value.add_theme_font_size_override("font_size", 18)
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
			var scale := _shake_scale()
			var next_scale := 0.0
			if scale < 0.25:
				next_scale = 0.5
			elif scale < 0.75:
				next_scale = 1.0
			SaveData.set_setting("shake_scale", next_scale)
		"HITSTOP":
			SaveData.set_setting("hitstop", not bool(SaveData.settings["hitstop"]))
		"HITBOXES":
			SaveData.set_setting("show_hitboxes", not bool(SaveData.settings["show_hitboxes"]))
		"FULLSCREEN":
			SaveData.set_setting("fullscreen", not bool(SaveData.settings["fullscreen"]))
		"COLORBLIND HUD":
			SaveData.set_setting("colorblind_hud", not bool(SaveData.settings.get("colorblind_hud", false)))
	_refresh()


func _shake_scale() -> float:
	if SaveData.settings.has("shake_scale"):
		return clampf(float(SaveData.settings["shake_scale"]), 0.0, 1.0)
	return 1.0 if bool(SaveData.settings.get("screen_shake", true)) else 0.0


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
			var pct := int(round(_shake_scale() * 100.0))
			return "OFF" if pct <= 0 else "%d%%" % pct
		"HITSTOP":
			return "ON" if bool(SaveData.settings["hitstop"]) else "OFF"
		"HITBOXES":
			return "ON" if bool(SaveData.settings["show_hitboxes"]) else "OFF"
		"FULLSCREEN":
			return "ON" if bool(SaveData.settings["fullscreen"]) else "OFF"
		"COLORBLIND HUD":
			return "ON" if bool(SaveData.settings.get("colorblind_hud", false)) else "OFF"
	return ""


func _build_keybind_overlay() -> void:
	_keybind_overlay = Control.new()
	_keybind_overlay.position = Vector2.ZERO
	_keybind_overlay.size = Vector2(UI.W, UI.H)
	_keybind_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_keybind_overlay.visible = false
	add_child(_keybind_overlay)

	var dim := ColorRect.new()
	dim.position = Vector2.ZERO
	dim.size = Vector2(UI.W, UI.H)
	dim.color = Color(0.025, 0.035, 0.055, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_keybind_overlay.add_child(dim)

	var card := Panel.new()
	card.position = Vector2(170, 48)
	card.size = Vector2(940, 624)
	card.add_theme_stylebox_override("panel",
			UI.panel_style(Color(0.075, 0.09, 0.12, 0.96), UITheme.ACCENT, 2, 2))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_keybind_overlay.add_child(card)

	UI.banner(_keybind_overlay, "CONTROLS", 62, 34, UITheme.INK, UITheme.heading_font)
	var sub := UI.label(_keybind_overlay, "SELECT AN ACTION AND PRESS A KEY  |  ESC CANCELS",
			Vector2(0, 108), 13, UITheme.MUTED)
	sub.size = Vector2(UI.W, 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.rule(_keybind_overlay, Vector2(220, 132), 840, UITheme.BORDER, 2)

	_keybind_p1_header = UI.label(_keybind_overlay, "PLAYER 1", Vector2(220, 140), 18,
			UITheme.p1_color(), UITheme.heading_font)
	_keybind_p1_header.size = Vector2(KEYBIND_COL_W, 24)
	_keybind_p1_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_keybind_p2_header = UI.label(_keybind_overlay, "PLAYER 2", Vector2(660, 140), 18,
			UITheme.p2_color(), UITheme.heading_font)
	_keybind_p2_header.size = Vector2(KEYBIND_COL_W, 24)
	_keybind_p2_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var col_x := {"p1": 220.0, "p2": 660.0}
	var start_y := 172.0
	for p in ["p1", "p2"]:
		var px: float = col_x[p]
		for i in Controls.REBINDABLE_ACTIONS.size():
			var suffix: String = Controls.REBINDABLE_ACTIONS[i]
			var action_name := "%s_%s" % [p, suffix]
			var by := start_y + i * (KEYBIND_ROW_H + KEYBIND_ROW_GAP)
			var b := UI.button(_keybind_overlay, "", Vector2(px, by),
					Vector2(KEYBIND_COL_W, KEYBIND_ROW_H), 15)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_apply_button_padding(b, 16, 4, 2, 3)
			b.set_meta("action_name", action_name)
			b.set_meta("suffix", suffix)
			b.pressed.connect(_start_capture.bind(action_name))
			_keybind_buttons[action_name] = b
			_keybind_order.append(b)

	_keybind_reset_button = UI.button(_keybind_overlay, "RESET DEFAULTS", Vector2(380, 574),
			Vector2(240, 44), 17)
	_keybind_reset_button.pressed.connect(_reset_keybinds)

	_keybind_done_button = UI.button(_keybind_overlay, "DONE", Vector2(660, 574),
			Vector2(240, 44), 17)
	_keybind_done_button.pressed.connect(_close_keybinds.bind(false))


func _apply_button_padding(b: Button, pad_x: int, pad_y: int, border: int, focus_border: int) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.GLASS_PANEL
		sb.border_color = UITheme.BORDER
		sb.set_border_width_all(border)
		sb.set_corner_radius_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.36)
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(0, 2)
		sb.content_margin_left = pad_x
		sb.content_margin_right = pad_x
		sb.content_margin_top = pad_y
		sb.content_margin_bottom = pad_y
		match state:
			"hover":
				sb.bg_color = UITheme.PANEL_LIGHT
				sb.border_color = UITheme.ACCENT
			"pressed":
				sb.bg_color = Color("262d3a")
				sb.border_color = UITheme.ACCENT
				sb.shadow_size = 1
				sb.shadow_offset = Vector2(0, 1)
			"focus":
				sb.bg_color = UITheme.PANEL_LIGHT
				sb.border_color = UITheme.ACCENT
				sb.set_border_width_all(focus_border)
			"disabled":
				sb.bg_color = Color(0.07, 0.08, 0.105, 0.78)
				sb.border_color = Color("232833")
				sb.shadow_size = 0
		b.add_theme_stylebox_override(state, sb)


func _set_main_focus_enabled(enabled: bool) -> void:
	var mode := Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	for b in _rows:
		b.focus_mode = mode
	_controls_button.focus_mode = mode
	_reset_button.focus_mode = mode
	_back_button.focus_mode = mode


func _open_keybinds() -> void:
	_capturing_action = ""
	_set_main_focus_enabled(false)
	_keybind_overlay.visible = true
	_refresh_keybinds()
	if not _keybind_order.is_empty():
		_keybind_order[0].grab_focus()


func _close_keybinds(play_back_sfx := false) -> void:
	_capturing_action = ""
	_keybind_overlay.visible = false
	_set_main_focus_enabled(true)
	if play_back_sfx:
		Sfx.play_ui("back")
	_rows[0].grab_focus()


func _start_capture(action_name: String) -> void:
	_capturing_action = action_name
	_refresh_keybinds()


func _cancel_capture() -> void:
	_capturing_action = ""
	_refresh_keybinds()
	Sfx.play_ui("back")


func _reset_keybinds() -> void:
	_capturing_action = ""
	Controls.reset_keybinds()
	_refresh_keybinds()
	_flash("CONTROLS RESET", 632.0)


func _refresh_keybinds() -> void:
	_keybind_p1_header.add_theme_color_override("font_color", UITheme.p1_color())
	_keybind_p2_header.add_theme_color_override("font_color", UITheme.p2_color())
	for action_name in _keybind_buttons:
		var b: Button = _keybind_buttons[action_name]
		var suffix: String = b.get_meta("suffix")
		if _capturing_action == action_name:
			b.text = "PRESS A KEY..."
		else:
			b.text = "%s: %s" % [suffix.to_upper(), Controls.key_label(action_name)]


func _reset_stats() -> void:
	SaveData.reset_stats()
	_flash("STATS RESET")


func _flash(message: String, y := 568.0) -> void:
	var label := UI.label(self, message, Vector2(0, y), 16, UITheme.OK)
	label.size = Vector2(1280, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tween := create_tween()
	tween.tween_interval(1.1)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _back() -> void:
	Sfx.play_ui("back")
	Game.go_main_menu()


func _input(event: InputEvent) -> void:
	if _keybind_overlay == null or not _keybind_overlay.visible or _capturing_action.is_empty():
		return
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if not key_ev.pressed:
			return
		if key_ev.echo:
			get_viewport().set_input_as_handled()
			return
		var code: int = int(key_ev.physical_keycode) if key_ev.physical_keycode != KEY_NONE else int(key_ev.keycode)
		if code == KEY_ESCAPE or key_ev.keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		if code > 0:
			Controls.rebind_key(_capturing_action, code)
			_capturing_action = ""
			_refresh_keybinds()
			Sfx.play_ui("confirm")
			get_viewport().set_input_as_handled()
			return
	elif event.is_action_pressed("ui_cancel"):
		_cancel_capture()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _keybind_overlay != null and _keybind_overlay.visible:
			if not _capturing_action.is_empty():
				_cancel_capture()
			else:
				_close_keybinds(true)
			accept_event()
			return
		_back()
		accept_event()
