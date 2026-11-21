extends Node

## One project-wide theme, applied to the root window so every scene inherits it.
## Menus are built from code (scripts/ui/ui_kit.gd) to keep styling consistent.

const BG := Color("0b0d11")
const PANEL := Color("14171e")
const PANEL_LIGHT := Color("1e232d")
const BORDER := Color("343b48")
const INK := Color("e6e1d6")
const MUTED := Color("8b929e")
const ACCENT := Color("c9a24b")
const P1 := Color("4f8ec4")
const P2 := Color("c7564b")
const CB_P1 := Color("3b8eea")
const CB_P2 := Color("f08c2e")
const CB_ACCENT := Color("f2d04e")
const DANGER := Color("c94a42")
const OK := Color("63a375")

const GLASS_PANEL := Color(0.08, 0.095, 0.125, 0.92)
const UI_FONT_NAMES := [
	"Helvetica Neue", "Avenir Next", "Inter", "Arial", "Liberation Sans", "DejaVu Sans",
]

var theme: Theme
var heading_font: Font
var body_font: Font


func _ready() -> void:
	body_font = _build_system_font(500)
	if body_font == null:
		body_font = ThemeDB.fallback_font

	var heavy_base := _build_system_font(700)
	if heavy_base == null:
		heavy_base = body_font
	var heavy := FontVariation.new()
	heavy.base_font = heavy_base
	heavy.spacing_glyph = -1
	heading_font = heavy if heavy != null else heavy_base

	theme = Theme.new()
	theme.default_font = body_font
	theme.default_font_size = 22

	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.72))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)

	_build_button()
	_build_panel()
	_build_variations(heading_font)

	get_tree().root.theme = theme


func _build_system_font(weight: int) -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(UI_FONT_NAMES)
	sf.font_weight = weight
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	sf.hinting = TextServer.HINTING_NORMAL
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return sf if sf != null else ThemeDB.fallback_font


func _build_button() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = GLASS_PANEL
		sb.border_color = BORDER
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.42)
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(0, 2)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		match state:
			"hover":
				sb.bg_color = PANEL_LIGHT
				sb.border_color = ACCENT
			"pressed":
				sb.bg_color = Color("262d3a")
				sb.border_color = ACCENT
				sb.shadow_size = 1
				sb.shadow_offset = Vector2(0, 1)
			"focus":
				sb.bg_color = PANEL_LIGHT
				sb.border_color = ACCENT
				sb.set_border_width_all(3)
			"disabled":
				sb.bg_color = Color(0.07, 0.08, 0.105, 0.78)
				sb.border_color = Color("232833")
				sb.shadow_size = 0
		theme.set_stylebox(state, "Button", sb)

	theme.set_font("font", "Button", heading_font)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color("586070"))
	theme.set_font_size("font_size", "Button", 24)
	theme.set_constant("outline_size", "Button", 0)


func _build_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS_PANEL
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
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
	theme.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.88))
	theme.set_constant("shadow_offset_x", "Title", 3)
	theme.set_constant("shadow_offset_y", "Title", 4)

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
	theme.set_color("font_color", "Hint", Color("7e8694"))


func get_ui_font() -> Font:
	return body_font if body_font != null else ThemeDB.fallback_font


func is_colorblind() -> bool:
	return bool(SaveData.settings.get("colorblind_hud", false))


func p1_color() -> Color:
	return CB_P1 if is_colorblind() else P1


func p2_color() -> Color:
	return CB_P2 if is_colorblind() else P2


func meter_color() -> Color:
	return CB_ACCENT if is_colorblind() else ACCENT
