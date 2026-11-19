extends Node

## One project-wide theme, applied to the root window so every scene inherits it.
## Menus are built from code (scripts/ui/ui_kit.gd) to keep styling consistent.

const BG := Color("10141c")
const PANEL := Color("1a2130")
const PANEL_LIGHT := Color("232c40")
const BORDER := Color("2f3a50")
const INK := Color("ece7db")
const MUTED := Color("98a2b4")
const ACCENT := Color("d9b45b")
const P1 := Color("5aa9e6")
const P2 := Color("e6645a")
const DANGER := Color("e0645a")
const OK := Color("79c08b")

var theme: Theme
var heading_font: Font
var body_font: Font


func _ready() -> void:
	body_font = ThemeDB.fallback_font
	var heavy := FontVariation.new()
	heavy.base_font = ThemeDB.fallback_font
	heavy.variation_embolden = 0.9
	heading_font = heavy

	theme = Theme.new()
	theme.default_font = body_font
	theme.default_font_size = 22

	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)

	_build_button()
	_build_panel()
	_build_variations(heavy)

	get_tree().root.theme = theme


func _build_button() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL
		sb.border_color = BORDER
		sb.set_border_width_all(3)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		match state:
			"hover":
				sb.bg_color = PANEL_LIGHT
				sb.border_color = ACCENT
			"pressed":
				sb.bg_color = Color("323d56")
				sb.border_color = ACCENT
			"focus":
				sb.bg_color = PANEL_LIGHT
				sb.border_color = ACCENT
				sb.set_border_width_all(4)
			"disabled":
				sb.bg_color = Color("171c27")
				sb.border_color = Color("252c3a")
		theme.set_stylebox(state, "Button", sb)

	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color("5b6476"))
	theme.set_font_size("font_size", "Button", 26)
	theme.set_constant("outline_size", "Button", 0)


func _build_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = BORDER
	sb.set_border_width_all(3)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	theme.set_stylebox("panel", "PanelContainer", sb)
	theme.set_stylebox("panel", "Panel", sb)
	theme.set_color("separator", "HSeparator", BORDER)


func _build_variations(heavy: Font) -> void:
	# Big headings
	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", heavy)
	theme.set_font_size("font_size", "Title", 88)
	theme.set_color("font_color", "Title", INK)
	theme.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.85))
	theme.set_constant("shadow_offset_x", "Title", 5)
	theme.set_constant("shadow_offset_y", "Title", 5)

	theme.set_type_variation("Subtitle", "Label")
	theme.set_font_size("font_size", "Subtitle", 24)
	theme.set_color("font_color", "Subtitle", MUTED)

	theme.set_type_variation("SectionTitle", "Label")
	theme.set_font("font", "SectionTitle", heavy)
	theme.set_font_size("font_size", "SectionTitle", 32)
	theme.set_color("font_color", "SectionTitle", ACCENT)

	theme.set_type_variation("Small", "Label")
	theme.set_font_size("font_size", "Small", 16)
	theme.set_color("font_color", "Small", MUTED)

	theme.set_type_variation("Tiny", "Label")
	theme.set_font_size("font_size", "Tiny", 13)
	theme.set_color("font_color", "Tiny", MUTED)

	theme.set_type_variation("Hint", "Label")
	theme.set_font_size("font_size", "Hint", 18)
	theme.set_color("font_color", "Hint", Color("8a94a8"))


func get_ui_font() -> Font:
	return body_font if body_font != null else ThemeDB.fallback_font
