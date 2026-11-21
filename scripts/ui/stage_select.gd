extends Control

## Stage picker. Shows a cropped still of each background before you commit.

const CARD_W := 360.0
const CARD_H := 300.0
const START_X := 70.0
const CARD_Y := 210.0

var index := 0
var cards: Array = []
var _starting := false


func _ready() -> void:
	UI.backdrop(self, "res://assets/stages/parkinglot.png", Color(0.28, 0.30, 0.38), 0.62)
	index = maxi(0, StageDB.ORDER.find(Game.stage_id))

	UI.banner(self, "CHOOSE A STAGE", 46, 46, UITheme.INK, UITheme.heading_font)

	var p1 := CharacterDB.get_character(Game.p1_id)
	var p2 := CharacterDB.get_character(Game.p2_id)
	var matchup := "%s   VS   %s" % [p1["name"], p2["name"]]
	UI.banner(self, matchup, 118, 26, UITheme.ACCENT, UITheme.heading_font)
	UI.rule(self, Vector2(480, 166), 320, Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.65), 2)

	for i in StageDB.ORDER.size():
		_build_card(i)

	var hint := UI.label(self, "P1: A/D + F      ESC: BACK", Vector2(0, 664), 16, UITheme.MUTED)
	hint.size = Vector2(1280, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh()


func _build_card(i: int) -> void:
	var id: String = StageDB.ORDER[i]
	var stage := StageDB.get_stage(id)
	var accent: Color = stage["accent"]
	var x := START_X + i * (CARD_W + 30.0)
	var panel := Panel.new()
	panel.position = Vector2(x, CARD_Y)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.add_theme_stylebox_override("panel",
			UI.panel_style(Color(0.075, 0.09, 0.12, 0.94), UITheme.BORDER, 2, 2))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_on_card_hover.bind(i))
	panel.gui_input.connect(_on_card_input.bind(i))
	add_child(panel)

	var thumb_frame := Panel.new()
	thumb_frame.position = Vector2(x + 12, CARD_Y + 12)
	thumb_frame.size = Vector2(CARD_W - 24, 198)
	thumb_frame.add_theme_stylebox_override("panel",
			UI.panel_style(Color("0b0e14"), Color("262d39"), 1, 2))
	thumb_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(thumb_frame)

	var thumb := TextureRect.new()
	thumb.texture = load(stage["bg"])
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	thumb.clip_contents = true
	thumb.position = Vector2(x + 14, CARD_Y + 14)
	thumb.size = Vector2(CARD_W - 28, 194)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(thumb)

	UI.rule(self, Vector2(x + 12, CARD_Y + 212), CARD_W - 24,
			Color(accent.r, accent.g, accent.b, 0.72), 2.0)

	var name_label := Label.new()
	name_label.text = str(stage["name"])
	name_label.position = Vector2(x, CARD_Y + 220)
	name_label.size = Vector2(CARD_W, 32)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", UITheme.heading_font)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)

	var sub := Label.new()
	sub.text = str(stage["subtitle"])
	sub.position = Vector2(x, CARD_Y + 254)
	sub.size = Vector2(CARD_W, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UITheme.MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)

	var tag := UI.label(self, "P1", Vector2(x, CARD_Y - 26), 16, UITheme.p1_color())
	tag.add_theme_font_override("font", UITheme.heading_font)

	cards.append({"panel": panel, "tag": tag, "accent": accent})


func _on_card_hover(i: int) -> void:
	if _starting or index == i:
		return
	index = i
	Sfx.play_ui("move")
	_refresh()


func _on_card_input(event: InputEvent, i: int) -> void:
	if _starting:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		index = i
		_starting = true
		Sfx.play_ui("confirm")
		Game.stage_confirmed(StageDB.ORDER[index])


func _process(_delta: float) -> void:
	if _starting:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		Sfx.play_ui("back")
		Game.back_to_characters()
		return
	var moved := false
	if Input.is_action_just_pressed("p1_left"):
		index = (index + StageDB.ORDER.size() - 1) % StageDB.ORDER.size()
		moved = true
	elif Input.is_action_just_pressed("p1_right"):
		index = (index + 1) % StageDB.ORDER.size()
		moved = true
	if moved:
		Sfx.play_ui("move")
		_refresh()
	if Input.is_action_just_pressed("p1_light") or Input.is_action_just_pressed("p1_confirm"):
		_starting = true
		Sfx.play_ui("confirm")
		Game.stage_confirmed(StageDB.ORDER[index])


func _refresh() -> void:
	for i in cards.size():
		var card: Dictionary = cards[i]
		var selected: bool = i == index
		UI.set_panel_style(card["panel"],
				Color(0.115, 0.145, 0.19, 0.96) if selected else Color(0.075, 0.09, 0.12, 0.94),
				card["accent"] if selected else UITheme.BORDER,
				3 if selected else 2)
		card["tag"].visible = selected
