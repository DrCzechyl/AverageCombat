class_name UI
extends RefCounted

## Small helpers for building the 1280x720 menus from code. The project uses a
## fixed "canvas_items" stretch mode, so absolute positions are stable across
## resolutions.

const W := 1280.0
const H := 720.0


static func backdrop(root: Control, image_path := "", tint := Color(0.22, 0.25, 0.35, 1.0),
		dim := 0.35) -> void:
	var rect: Control
	if image_path != "" and ResourceLoader.exists(image_path):
		var tex := TextureRect.new()
		tex.texture = load(image_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.modulate = tint
		tex.size = Vector2(W, H)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect = tex
	else:
		var color := ColorRect.new()
		color.color = UITheme.BG
		color.size = Vector2(W, H)
		color.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect = color
	root.add_child(rect)

	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0.04, 0.05, 0.08, dim)
		shade.size = Vector2(W, H)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shade)


static func label(root: Control, text: String, pos: Vector2, size := 22,
		color := UITheme.INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


static func title(root: Control, text: String, pos: Vector2, size := 88,
		color := UITheme.INK) -> Label:
	var l := label(root, text, pos, size, color, UITheme.heading_font)
	return l


static func banner(root: Control, text: String, y: float, size := 88,
		color := UITheme.INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(W, size * 1.35)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


static func button(root: Control, text: String, pos: Vector2, size := Vector2(320, 56),
		font_size := 26) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.position = pos
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_constant_override("outline_size", 0)
	root.add_child(b)
	_attach_sounds(b)
	return b


static func _attach_sounds(b: Button) -> void:
	b.focus_entered.connect(func(): Sfx.play_ui("move"))
	b.mouse_entered.connect(func():
		if not b.has_focus():
			b.grab_focus()
	)
	b.pressed.connect(func(): Sfx.play_ui("confirm"))


static func rule(root: Control, pos: Vector2, width := 400.0, color := UITheme.BORDER,
		height := 2.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = Vector2(width, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


static func panel(root: Control, rect: Rect2, accent := Color(0, 0, 0, 0), border := 3) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", panel_style(UITheme.PANEL, accent, border))
	root.add_child(p)
	return p


static func panel_style(bg := UITheme.PANEL, border_color := UITheme.BORDER, border := 3,
		radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	return sb


static func set_panel_style(p: Control, bg: Color, border_color: Color, border := 3) -> void:
	p.add_theme_stylebox_override("panel", panel_style(bg, border_color, border))


static func portrait(root: Control, char_id: String, rect: Rect2, frame_row := 0,
		frame_col := 0) -> TextureRect:
	var data := CharacterDB.get_character(char_id)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(data["sheet"])
	atlas.region = Rect2(frame_col * 64, frame_row * 96, 64, 96)
	var tex := TextureRect.new()
	tex.texture = atlas
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.position = rect.position
	tex.size = rect.size
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tex)
	return tex


static func stat_bar(root: Control, pos: Vector2, value: int, color: Color,
		segments := 5, seg_w := 22.0, seg_h := 8.0, gap := 3.0) -> void:
	for i in segments:
		var c := ColorRect.new()
		c.position = pos + Vector2(i * (seg_w + gap), 0)
		c.size = Vector2(seg_w, seg_h)
		c.color = color if i < value else Color(color.r, color.g, color.b, 0.16)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)


static func vbox(root: Control, pos: Vector2, size: Vector2, separation := 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = pos
	box.size = size
	box.add_theme_constant_override("separation", separation)
	root.add_child(box)
	return box


static func hbox(root: Control, pos: Vector2, size: Vector2, separation := 12) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.position = pos
	box.size = size
	box.add_theme_constant_override("separation", separation)
	root.add_child(box)
	return box


static func center_buttons(root: Control, labels: Array, x := 470.0, y := 330.0,
		width := 340.0, height := 58.0, gap := 12.0) -> Array[Button]:
	var buttons: Array[Button] = []
	for i in labels.size():
		var b := button(root, labels[i], Vector2(x, y + i * (height + gap)), Vector2(width, height))
		buttons.append(b)
	return buttons


static func focus_first(buttons: Array) -> void:
	for b in buttons:
		if b != null and b.is_inside_tree() and not b.disabled:
			b.grab_focus()
			return


static func fmt_seconds(seconds: float) -> String:
	var s := int(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]
