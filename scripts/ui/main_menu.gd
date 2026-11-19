extends Control

## Title screen. First thing the player sees; routes into every mode.

const MENU_BUTTON_SIZE := Vector2(360, 54)


func _ready() -> void:
	UI.backdrop(self, "res://assets/stages/parkinglot.png", Color(0.30, 0.33, 0.44), 0.52)

	# Fighters loitering at the edges of the title screen.
	UI.portrait(self, "dave", Rect2(84, 372, 192, 288), 0, 0)
	UI.portrait(self, "karen", Rect2(1004, 372, 192, 288), 0, 0)

	var glow := ColorRect.new()
	glow.color = Color(0.85, 0.7, 0.35, 0.05)
	glow.position = Vector2(0, 0)
	glow.size = Vector2(1280, 8)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	UI.banner(self, "AVERAGE", 52, 100, UITheme.INK, UITheme.heading_font)
	UI.banner(self, "COMBAT", 146, 100, UITheme.ACCENT, UITheme.heading_font)
	UI.banner(self, "AN EVERYDAY FIGHTING GAME", 268, 18, UITheme.MUTED)

	UI.rule(self, Vector2(500, 300), 280, UITheme.ACCENT, 3)

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
	var controls := UI.label(self, "P1: WASD + FGH      P2: ARROWS + NUMPAD 123",
			Vector2(0, 688), 12, Color(0.55, 0.58, 0.66))
	controls.size = Vector2(1280, 18)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	UI.focus_first(buttons)


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
			get_tree().quit()
