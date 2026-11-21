extends Control

## Title screen. First thing the player sees; routes into every mode.

const MENU_BUTTON_SIZE := Vector2(360, 54)


func _ready() -> void:
	UI.backdrop(self, "res://assets/stages/parkinglot.png", Color(0.36, 0.38, 0.46), 0.50)

	# Fighters framed in moody steel-and-brass vignette cards flanking the menu.
	_build_flank_portrait("dave", Rect2(84, 360, 200, 280), UITheme.P1)
	_build_flank_portrait("karen", Rect2(996, 360, 200, 280), UITheme.P2)

	var top_trim := ColorRect.new()
	top_trim.color = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.45)
	top_trim.position = Vector2(0, 0)
	top_trim.size = Vector2(1280, 3)
	top_trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_trim)

	UI.banner(self, "AVERAGE", 48, 100, UITheme.INK, UITheme.heading_font)
	UI.banner(self, "COMBAT", 142, 100, UITheme.ACCENT, UITheme.heading_font)
	UI.banner(self, "AN EVERYDAY FIGHTING GAME", 264, 18, UITheme.MUTED)

	UI.rule(self, Vector2(500, 298), 280, UITheme.ACCENT, 2)

	var x := 460.0
	var buttons: Array[Button] = []
	var labels := ["LOCAL VERSUS", "ARCADE", "TRAINING", "OPTIONS", "QUIT"]
	var actions := ["versus", "arcade", "training", "options", "quit"]
	for i in labels.size():
		var b := UI.button(self, labels[i], Vector2(x, 326 + i * 66), MENU_BUTTON_SIZE)
		buttons.append(b)
		var action: String = actions[i]
		b.pressed.connect(func(): _on_menu(action))

	# Stats footer
	var matches := int(SaveData.stats.get("matches", 0))
	var wins := int(SaveData.stats.get("wins", 0))
	var clears := int(SaveData.stats.get("arcade_clears", 0))
	UI.label(self, "MATCHES %d    WINS %d    ARCADE CLEARS %d" % [matches, wins, clears],
			Vector2(36, 662), 14, UITheme.MUTED)
	UI.label(self, "v%s" % Game.VERSION, Vector2(1180, 662), 14, UITheme.MUTED)
	var controls := UI.label(self,
			"P1: WASD + F/G/H  V BLOCK  E THROW      P2: ARROWS + NUMPAD 1/2/3  NUMPAD 0 BLOCK  NUMPAD 4 THROW",
			Vector2(0, 688), 12, Color(0.55, 0.58, 0.66))
	controls.size = Vector2(1280, 18)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	UI.focus_first(buttons)


func _build_flank_portrait(char_id: String, rect: Rect2, trim_color: Color) -> void:
	var frame := Panel.new()
	frame.position = rect.position
	frame.size = rect.size
	frame.add_theme_stylebox_override("panel",
			UI.panel_style(Color(0.06, 0.072, 0.098, 0.90), UITheme.BORDER, 2, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var inset := Rect2(rect.position.x + 6.0, rect.position.y + 6.0,
			rect.size.x - 12.0, rect.size.y - 12.0)
	UI.portrait(self, char_id, inset, 0, 0)

	# Subtle dark bottom vignette and steel/brass trim bars
	var vignette := ColorRect.new()
	vignette.position = Vector2(inset.position.x, inset.end.y - 44.0)
	vignette.size = Vector2(inset.size.x, 44.0)
	vignette.color = Color(0.04, 0.05, 0.075, 0.62)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	UI.rule(self, Vector2(rect.position.x + 2.0, rect.position.y),
			rect.size.x - 4.0, Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.72), 2.0)
	UI.rule(self, Vector2(rect.position.x + 2.0, rect.end.y - 2.0),
			rect.size.x - 4.0, Color(trim_color.r, trim_color.g, trim_color.b, 0.8), 2.0)


func _on_menu(action: String) -> void:
	match action:
		"versus":
			Game.start_versus()
		"arcade":
			Game.start_arcade()
		"training":
			Game.start_training()
		"options":
			Game.goto("res://scenes/ui/options.tscn")
		"quit":
			Game.quit()
