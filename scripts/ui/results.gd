extends Control

## Post-match screen. Handles both versus/training and arcade (including the
## "ladder over" case), so there is no separate game-over scene.

var result: Dictionary = {}
var mode := "versus"
var winner := -1
var p1_won := false
var cleared := false
var _buttons: Array[Button] = []


func _ready() -> void:
	result = Game.results
	mode = str(result.get("mode", Game.mode))
	winner = int(result.get("winner", -1))
	p1_won = winner == 0
	cleared = bool(Game.arcade.get("cleared", false))

	var bg := StageDB.get_stage(str(result.get("stage", "breakroom")))
	UI.backdrop(self, str(bg["bg"]), Color(0.28, 0.30, 0.36), 0.72)

	_build_header()
	_build_winner()
	_build_stats()
	_build_buttons()

	UI.focus_first(_buttons)


func _build_header() -> void:
	UI.banner(self, "MATCH RESULT", 26, 22, UITheme.MUTED)
	UI.rule(self, Vector2(440, 68), 400, UITheme.ACCENT, 2)


func _build_winner() -> void:
	var title := ""
	var subtitle := ""
	var color := UITheme.ACCENT

	if mode == "arcade" and cleared:
		title = "ARCADE CLEARED"
		subtitle = "The whole ladder. Every last one of them."
		color = UITheme.OK
	elif winner < 0:
		title = "DRAW"
		subtitle = "Nobody wins. Everybody files paperwork."
		color = UITheme.MUTED
	elif mode == "arcade" and not p1_won:
		title = "GAME OVER"
		subtitle = "%s ended the run." % _name(str(result.get("p2", "karen")))
		color = UITheme.DANGER
	elif p1_won:
		title = "%s WINS" % _name(str(result.get("p1", "dave")))
		subtitle = "Somebody had to."
	else:
		title = "%s WINS" % _name(str(result.get("p2", "karen")))
		subtitle = "Better luck next quarter."

	UI.banner(self, title, 92, 76, color, UITheme.heading_font)
	UI.banner(self, subtitle, 186, 20, UITheme.MUTED)

	# Winner portrait framed in a sleek dark-bordered card. A draw is not a player 2 victory.
	var winner_id := str(result.get("p1", "dave")) if (p1_won or winner < 0) else str(result.get("p2", "karen"))
	if mode == "arcade" and not p1_won and winner >= 0:
		winner_id = str(result.get("p2", "karen"))

	var frame_rect := Rect2(552, 222, 176, 236)
	var frame := Panel.new()
	frame.position = frame_rect.position
	frame.size = frame_rect.size
	frame.add_theme_stylebox_override("panel",
			UI.panel_style(Color(0.065, 0.08, 0.11, 0.94), color, 2, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var portrait_rect := Rect2(frame_rect.position.x + 6, frame_rect.position.y + 6,
			frame_rect.size.x - 12, frame_rect.size.y - 12)
	var portrait := UI.portrait(self, winner_id, portrait_rect, 0, 0)
	portrait.clip_contents = true

	var fade := ColorRect.new()
	fade.position = Vector2(portrait_rect.position.x, portrait_rect.end.y - 32)
	fade.size = Vector2(portrait_rect.size.x, 32)
	fade.color = Color(0.04, 0.05, 0.08, 0.65)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	UI.rule(self, Vector2(portrait_rect.position.x, portrait_rect.end.y - 2),
			portrait_rect.size.x, Color(color.r, color.g, color.b, 0.8), 2.0)


func _build_stats() -> void:
	var wins: Array = result.get("wins", [0, 0])
	var combos: Array = result.get("best_combo", [0, 0])
	var damage: Array = result.get("damage", [0.0, 0.0])
	var seconds := float(result.get("duration", 0.0))

	var rows := [
		["SCORE", "%d  -  %d" % [int(wins[0]), int(wins[1])]],
		["BEST COMBO", "%d  -  %d" % [int(combos[0]), int(combos[1])]],
		["DAMAGE DEALT", "%d  -  %d" % [int(damage[0]), int(damage[1])]],
		["MATCH TIME", UI.fmt_seconds(seconds)],
	]
	UI.panel(self, Rect2(400, 470, 480, 142), UITheme.BORDER, 2)
	UI.rule(self, Vector2(402, 470), 476,
			Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.7), 2)
	var y := 492.0
	for row in rows:
		UI.label(self, str(row[0]), Vector2(432, y), 16, UITheme.MUTED)
		var value := UI.label(self, str(row[1]), Vector2(0, y), 18, UITheme.INK, UITheme.heading_font)
		value.size = Vector2(848, 24)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		y += 26.0

	if mode == "arcade" and not cleared:
		UI.banner(self, "LADDER  %s" % Game.arcade_progress_text(), 620, 18, UITheme.ACCENT)


func _build_buttons() -> void:
	var labels: Array = []
	var actions: Array = []

	if mode == "arcade" and cleared:
		labels = ["RUN IT BACK", "MAIN MENU"]
		actions = ["retry", "menu"]
	elif mode == "arcade" and not cleared and p1_won:
		labels = ["NEXT OPPONENT", "QUIT TO MENU"]
		actions = ["next", "menu"]
	elif mode == "arcade" and not cleared and winner < 0:
		labels = ["REMATCH", "QUIT TO MENU"]
		actions = ["rematch", "menu"]
	elif mode == "arcade":
		labels = ["TRY AGAIN", "QUIT TO MENU"]
		actions = ["retry", "menu"]
	else:
		labels = ["REMATCH", "CHANGE FIGHTERS", "MAIN MENU"]
		actions = ["rematch", "characters", "menu"]

	var total_width := labels.size() * 280.0 + (labels.size() - 1) * 20.0
	var start_x := 640.0 - total_width / 2.0
	for i in labels.size():
		var b := UI.button(self, labels[i], Vector2(start_x + i * 300.0, 650), Vector2(280, 48), 20)
		_buttons.append(b)
		var action: String = actions[i]
		b.pressed.connect(func(): _on_action(action))


func _on_action(action: String) -> void:
	match action:
		"next":
			Game.arcade_continue()
		"retry":
			Game.start_arcade()
		"rematch":
			Game.rematch()
		"characters":
			Game.back_to_characters()
		"menu":
			Game.go_main_menu()


func _name(id: String) -> String:
	var data := CharacterDB.get_character(id)
	return str(data.get("name", id.to_upper()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Sfx.play_ui("back")
		Game.go_main_menu()
		accept_event()
