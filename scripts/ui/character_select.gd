extends Control

## Character select. P1 uses A/D, P2 uses arrows in local versus; in arcade and
## training the CPU opponent is shown but not selectable.

const CARD_W := 244.0
const CARD_H := 440.0
const GAP := 24.0
const START_X := 116.0
const CARD_Y := 176.0

var mode := "versus"
var index := [0, 1]
var locked := [false, false]
var cards: Array = []
var _starting := false
var _dirty := true
var _hint: Label
var _bio: Label


func _ready() -> void:
	mode = Game.mode
	UI.backdrop(self, "res://assets/stages/breakroom.png", Color(0.26, 0.28, 0.36), 0.58)

	index[0] = CharacterDB.ORDER.find(Game.p1_id)
	if index[0] < 0:
		index[0] = 0
	if mode == "versus":
		index[1] = CharacterDB.ORDER.find(Game.p2_id)
		if index[1] < 0:
			index[1] = 1
		if index[1] == index[0]:
			index[1] = (index[0] + 1) % CharacterDB.ORDER.size()
	else:
		var opponent := Game.p2_id
		if mode == "arcade":
			opponent = Game.next_arcade_opponent_id()
		index[1] = CharacterDB.ORDER.find(opponent)
		if index[1] < 0:
			index[1] = (index[0] + 1) % CharacterDB.ORDER.size()
		locked[1] = true

	UI.banner(self, "CHOOSE YOUR FIGHTER", 48, 46, UITheme.INK, UITheme.heading_font)

	# Character cards
	for i in CharacterDB.ORDER.size():
		_build_card(i)

	_hint = UI.label(self, "", Vector2(0, 646), 16, UITheme.MUTED)
	_hint.size = Vector2(1280, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_bio = UI.label(self, "", Vector2(140, 676), 14, Color(0.62, 0.66, 0.74))
	_bio.size = Vector2(1000, 34)
	_bio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_refresh()


func _build_card(i: int) -> void:
	var id: String = CharacterDB.ORDER[i]
	var data := CharacterDB.get_character(id)
	var x := START_X + i * (CARD_W + GAP)
	var panel := Panel.new()
	panel.position = Vector2(x, CARD_Y)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.add_theme_stylebox_override("panel", UI.panel_style(Color("121824"), UITheme.BORDER, 3))
	add_child(panel)

	var inner := Panel.new()
	inner.position = Vector2(x + 6, CARD_Y + 6)
	inner.size = Vector2(CARD_W - 12, CARD_H - 12)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner)

	var portrait := UI.portrait(self, id, Rect2(x + 12, CARD_Y + 12, CARD_W - 24, 286), 0, 0)

	var name_label := Label.new()
	name_label.text = str(data["name"])
	name_label.position = Vector2(x, CARD_Y + 296)
	name_label.size = Vector2(CARD_W, 36)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", UITheme.heading_font)
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", data["accent"])
	add_child(name_label)

	var title := Label.new()
	title.text = str(data["title"])
	title.position = Vector2(x + 10, CARD_Y + 334)
	title.size = Vector2(CARD_W - 20, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UITheme.MUTED)
	add_child(title)

	var stats: Dictionary = data["stats"]
	var rows := [["PWR", int(stats["power"])], ["SPD", int(stats["speed"])],
			["DEF", int(stats["defense"])]]
	for r in rows.size():
		var row: Array = rows[r]
		var label := UI.label(self, str(row[0]), Vector2(x + 26, CARD_Y + 370 + r * 22), 12,
				UITheme.MUTED)
		UI.stat_bar(self, Vector2(x + 74, CARD_Y + 368 + r * 22), int(row[1]),
				data["accent"], 5, 22.0, 8.0, 3.0)

	var p1_tag := UI.label(self, "1P", Vector2(x, CARD_Y - 28), 16, UITheme.P1)
	p1_tag.add_theme_font_override("font", UITheme.heading_font)
	var p2_tag := UI.label(self, "2P", Vector2(x + CARD_W - 44, CARD_Y - 28), 16, UITheme.P2)
	p2_tag.add_theme_font_override("font", UITheme.heading_font)

	cards.append({
		"id": id, "panel": panel, "inner": inner, "portrait": portrait,
		"p1_tag": p1_tag, "p2_tag": p2_tag, "name": name_label,
	})


func _process(_delta: float) -> void:
	if _starting:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		Sfx.play_ui("back")
		Game.go_main_menu()
		return

	var moved := false
	if not locked[0]:
		if Input.is_action_just_pressed("p1_left"):
			index[0] = (index[0] + CharacterDB.ORDER.size() - 1) % CharacterDB.ORDER.size()
			moved = true
		elif Input.is_action_just_pressed("p1_right"):
			index[0] = (index[0] + 1) % CharacterDB.ORDER.size()
			moved = true
		elif Input.is_action_just_pressed("p1_light") or Input.is_action_just_pressed("p1_confirm"):
			locked[0] = true
			_dirty = true
			Sfx.play_ui("confirm")

	if mode == "versus" and not locked[1]:
		if Input.is_action_just_pressed("p2_left"):
			index[1] = (index[1] + CharacterDB.ORDER.size() - 1) % CharacterDB.ORDER.size()
			moved = true
		elif Input.is_action_just_pressed("p2_right"):
			index[1] = (index[1] + 1) % CharacterDB.ORDER.size()
			moved = true
		elif Input.is_action_just_pressed("p2_light") or Input.is_action_just_pressed("p2_confirm"):
			locked[1] = true
			_dirty = true
			Sfx.play_ui("confirm")

	if moved:
		_dirty = true
		Sfx.play_ui("move")
	if mode != "versus":
		locked[1] = true

	if _dirty:
		_refresh()
		_dirty = false
	if locked[0] and locked[1]:
		_start()


func _refresh() -> void:
	var p1_data := CharacterDB.get_character(CharacterDB.ORDER[index[0]])
	_bio.text = str(p1_data["bio"])

	if mode == "versus":
		_hint.text = "P1: A/D + F      P2: ARROWS + NUMPAD 1/2/3      ESC: BACK"
	else:
		_hint.text = "P1: A/D + F      ESC: BACK"

	for i in cards.size():
		var card: Dictionary = cards[i]
		var selected_1: bool = index[0] == i
		var selected_2: bool = index[1] == i
		var bg := Color("121824")
		var border := UITheme.BORDER
		var width := 3
		if selected_1:
			border = UITheme.P1
			width = 4
			bg = Color("18202f")
		if selected_2:
			bg = Color("211a20") if not selected_1 else Color("241f2b")
			if not selected_1:
				border = UITheme.P2
				width = 4
		UI.set_panel_style(card["panel"], bg, border, width)
		UI.set_panel_style(card["inner"], Color(0, 0, 0, 0),
				UITheme.P2 if (selected_1 and selected_2) else Color(0, 0, 0, 0), 3)
		card["inner"].visible = selected_1 and selected_2

		var tag1: Label = card["p1_tag"]
		var tag2: Label = card["p2_tag"]
		tag1.visible = selected_1
		tag2.visible = selected_2
		tag1.text = "1P OK" if locked[0] else "1P"
		if mode == "versus":
			tag2.text = "2P OK" if locked[1] else "2P"
		else:
			tag2.text = "CPU"


func _start() -> void:
	_starting = true
	var p1_char: String = CharacterDB.ORDER[index[0]]
	var p2_char: String = CharacterDB.ORDER[index[1]]
	Game.characters_confirmed(p1_char, p2_char, mode == "versus")
