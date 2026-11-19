class_name PauseMenu
extends Control

## Overlay pause menu. Lives in a CanvasLayer set to PROCESS_MODE_ALWAYS so it
## keeps responding while the arena itself is paused.

var arena: Arena = null

var _buttons: Array[Button] = []
var _hitbox_button: Button
var _resume_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.78)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(420, 168)
	panel.size = Vector2(440, 408)
	panel.add_theme_stylebox_override("panel", UI.panel_style(UITheme.PANEL, UITheme.ACCENT, 4))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var title := Label.new()
	title.text = "PAUSED"
	title.position = Vector2(420, 196)
	title.size = Vector2(440, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.heading_font)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	add_child(title)

	_resume_button = UI.button(self, "RESUME", Vector2(470, 288), Vector2(340, 54))
	_resume_button.pressed.connect(close)
	var restart := UI.button(self, "RESTART MATCH", Vector2(470, 354), Vector2(340, 54))
	restart.pressed.connect(_restart)
	_hitbox_button = UI.button(self, "HITBOXES: OFF", Vector2(470, 420), Vector2(340, 54))
	_hitbox_button.pressed.connect(_toggle_hitboxes)
	var quit := UI.button(self, "QUIT TO MENU", Vector2(470, 486), Vector2(340, 54))
	quit.pressed.connect(_quit)
	_buttons = [_resume_button, restart, _hitbox_button, quit]
	for i in _buttons.size():
		var above: Button = _buttons[(i + _buttons.size() - 1) % _buttons.size()]
		var below: Button = _buttons[(i + 1) % _buttons.size()]
		_buttons[i].focus_neighbor_top = _buttons[i].get_path_to(above)
		_buttons[i].focus_neighbor_bottom = _buttons[i].get_path_to(below)


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
		close()
		accept_event()


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	if arena != null:
		_hitbox_button.text = "HITBOXES: %s" % ("ON" if arena.hitboxes_visible else "OFF")
	_resume_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	# Pad A is both ui_accept and P1 light. Drop focus so a hidden pause
	# button does not eat the next attack.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _toggle_hitboxes() -> void:
	if arena == null:
		return
	arena.set_hitboxes_visible(not arena.hitboxes_visible)
	_hitbox_button.text = "HITBOXES: %s" % ("ON" if arena.hitboxes_visible else "OFF")
	Sfx.play_ui("confirm")


func _quit() -> void:
	get_tree().paused = false
	Game.go_main_menu()
