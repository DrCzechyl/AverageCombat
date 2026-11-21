class_name PauseMenu
extends Control

## Overlay pause menu. Lives in a CanvasLayer set to PROCESS_MODE_ALWAYS so it
## keeps responding while the arena itself is paused.

const DUMMY_MODES := ["stand", "crouch", "block", "jump"]
const DUMMY_LABELS := {
	"stand": "STAND",
	"crouch": "CROUCH",
	"block": "AUTO-BLOCK",
	"jump": "JUMP",
}

var arena: Arena = null

var _panel: Panel
var _title: Label
var _rule: ColorRect
var _buttons: Array[Button] = []
var _resume_button: Button
var _restart_button: Button
var _hitbox_button: Button
var _dummy_button: Button
var _meter_button: Button
var _frame_data_button: Button
var _quit_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.055, 0.80)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.position = Vector2(420, 168)
	_panel.size = Vector2(440, 408)
	_panel.add_theme_stylebox_override("panel",
			UI.panel_style(Color(0.075, 0.09, 0.12, 0.96), UITheme.ACCENT, 2, 2))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	_title = Label.new()
	_title.text = "PAUSED"
	_title.position = Vector2(420, 196)
	_title.size = Vector2(440, 60)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UITheme.heading_font)
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	add_child(_title)

	_rule = UI.rule(self, Vector2(470, 264), 340,
			Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.6), 2)

	_resume_button = UI.button(self, "RESUME", Vector2(470, 288), Vector2(340, 54))
	_resume_button.pressed.connect(close)
	_restart_button = UI.button(self, "RESTART MATCH", Vector2(470, 354), Vector2(340, 54))
	_restart_button.pressed.connect(_restart)
	_hitbox_button = UI.button(self, "HITBOXES: OFF", Vector2(470, 420), Vector2(340, 54))
	_hitbox_button.pressed.connect(_toggle_hitboxes)

	_dummy_button = UI.button(self, "DUMMY: STAND", Vector2(470, 360), Vector2(340, 50), 22)
	_dummy_button.pressed.connect(_cycle_dummy)
	_dummy_button.visible = false
	_meter_button = UI.button(self, "METER: AUTO-REFILL", Vector2(470, 418), Vector2(340, 50), 22)
	_meter_button.pressed.connect(_toggle_meter_refill)
	_meter_button.visible = false
	_frame_data_button = UI.button(self, "FRAME DATA: ON", Vector2(470, 476), Vector2(340, 50), 22)
	_frame_data_button.pressed.connect(_toggle_frame_data)
	_frame_data_button.visible = false

	_quit_button = UI.button(self, "QUIT TO MENU", Vector2(470, 486), Vector2(340, 54))
	_quit_button.pressed.connect(_quit)
	_sync_training_rows()


func _sync_training_rows() -> void:
	var is_training := arena != null and arena.training
	_dummy_button.visible = is_training
	_meter_button.visible = is_training
	_frame_data_button.visible = is_training

	if is_training:
		_panel.position = Vector2(420, 102)
		_panel.size = Vector2(440, 516)
		_title.position = Vector2(420, 118)
		_title.size = Vector2(440, 52)
		_rule.position = Vector2(470, 174)
		_buttons = [
			_resume_button,
			_restart_button,
			_hitbox_button,
			_dummy_button,
			_meter_button,
			_frame_data_button,
			_quit_button,
		]
		for i in _buttons.size():
			var b: Button = _buttons[i]
			b.position = Vector2(470, 186 + i * 58)
			b.custom_minimum_size = Vector2(340, 50)
			b.size = Vector2(340, 50)
			b.add_theme_font_size_override("font_size", 22)
		_refresh_training_labels()
	else:
		_panel.position = Vector2(420, 168)
		_panel.size = Vector2(440, 408)
		_title.position = Vector2(420, 196)
		_title.size = Vector2(440, 60)
		_rule.position = Vector2(470, 264)
		_buttons = [_resume_button, _restart_button, _hitbox_button, _quit_button]
		for i in _buttons.size():
			var b: Button = _buttons[i]
			b.position = Vector2(470, 288 + i * 66)
			b.custom_minimum_size = Vector2(340, 54)
			b.size = Vector2(340, 54)
			b.add_theme_font_size_override("font_size", 24)

	for i in _buttons.size():
		var above: Button = _buttons[(i + _buttons.size() - 1) % _buttons.size()]
		var below: Button = _buttons[(i + 1) % _buttons.size()]
		_buttons[i].focus_neighbor_top = _buttons[i].get_path_to(above)
		_buttons[i].focus_neighbor_bottom = _buttons[i].get_path_to(below)


func _refresh_training_labels() -> void:
	if arena == null:
		return
	_dummy_button.text = "DUMMY: %s" % str(DUMMY_LABELS.get(arena.dummy_mode, "STAND"))
	_meter_button.text = "METER: %s" % ("AUTO-REFILL" if arena.auto_refill_meter else "NORMAL")
	_frame_data_button.text = "FRAME DATA: %s" % ("ON" if arena.show_frame_data else "OFF")


func _unhandled_input(event: InputEvent) -> void:
	# Escape is both "pause" and ui_cancel. Accept pause before ui_cancel so
	# one press toggles instead of opening and closing on the same event.
	if event.is_action_pressed("pause"):
		if visible:
			close()
		else:
			open()
		accept_event()
		return
	if visible and event.is_action_pressed("ui_cancel"):
		if arena != null:
			arena.router.consume_menu_press(event)
		close()
		accept_event()


func _exit_tree() -> void:
	if visible and get_tree() != null:
		get_tree().paused = false


func open() -> void:
	if visible or (arena != null and arena.finished):
		return
	visible = true
	get_tree().paused = true
	_sync_training_rows()
	if arena != null:
		_hitbox_button.text = "HITBOXES: %s" % ("ON" if arena.hitboxes_visible else "OFF")
	_resume_button.grab_focus()


func close() -> void:
	if not visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	if arena != null:
		arena.router.consume_pressed_edges()
	visible = false
	get_tree().paused = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _toggle_hitboxes() -> void:
	if arena == null:
		return
	arena.set_hitboxes_visible(not arena.hitboxes_visible)
	_hitbox_button.text = "HITBOXES: %s" % ("ON" if arena.hitboxes_visible else "OFF")


func _cycle_dummy() -> void:
	if arena == null:
		return
	var idx := DUMMY_MODES.find(arena.dummy_mode)
	var next_mode: String = DUMMY_MODES[(idx + 1) % DUMMY_MODES.size()]
	arena.set_dummy_mode(next_mode)
	_refresh_training_labels()


func _toggle_meter_refill() -> void:
	if arena == null:
		return
	arena.auto_refill_meter = not arena.auto_refill_meter
	_refresh_training_labels()


func _toggle_frame_data() -> void:
	if arena == null:
		return
	arena.show_frame_data = not arena.show_frame_data
	_refresh_training_labels()


func _quit() -> void:
	get_tree().paused = false
	Game.go_main_menu()
