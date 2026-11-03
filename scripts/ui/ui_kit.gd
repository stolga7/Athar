extends RefCounted
## The shared look of every ATHAR screen: one palette, one typography, one theme.
##
## The HUD, the menus and the settings are built in code (the project has no
## imported UI scenes beyond thin wrappers), so this file is the single source of
## truth for colour, spacing, sizes and fonts. Anything that paints a panel or a
## button asks this kit, which is what keeps the screens consistent.
##
## Every visible string is tagged with its translation key (see `Localization`)
## and then filled in by `retranslate()`, so switching language never rebuilds a
## screen and no text is hardcoded in a script.

const Localization := preload("res://scripts/ui/localization.gd")

## Dark fantasy palette: violet ink, aged gold, and one restrained cyan that is
## only used for information (never for a button the player must press).
const INK := Color(0.043, 0.031, 0.071)
const PANEL := Color(0.086, 0.067, 0.137, 0.88)
const PANEL_DEEP := Color(0.055, 0.043, 0.094, 0.95)
const PURPLE := Color(0.616, 0.482, 0.847, 0.72)
const PURPLE_DEEP := Color(0.298, 0.208, 0.435)
const GOLD := Color(0.886, 0.753, 0.478)
const GOLD_DEEP := Color(0.612, 0.478, 0.243)
const CYAN := Color(0.435, 0.816, 0.839)
const TEXT := Color(0.937, 0.914, 0.863)
const TEXT_DIM := Color(0.725, 0.694, 0.643)
const DANGER := Color(0.831, 0.396, 0.373)
const SCRIM := Color(0.012, 0.008, 0.024, 0.74)

const FONT_BODY := "res://assets/fonts/IBMPlexSansArabic-Regular.ttf"
const FONT_BOLD := "res://assets/fonts/IBMPlexSansArabic-SemiBold.ttf"
const FONT_DISPLAY := "res://assets/fonts/Amiri-Bold.ttf"

const SIZE_CAPTION := 15
const SIZE_BODY := 18
const SIZE_BUTTON := 19
const SIZE_SUBHEAD := 22
const SIZE_HEADLINE := 34
const SIZE_DISPLAY := 46

## Android's minimum comfortable touch target, in the HUD's own pixels. Every
## interactive control is at least this big on every supported screen.
const MIN_TOUCH := 56.0
const RADIUS_PANEL := 20
const RADIUS_BUTTON := 16

## Translation key stored on each control, so one call can re-fill a whole screen.
const I18N_META := "i18n"
const ALIGN_META := "i18n_align"

static var _theme: Theme
static var _fonts := {}


## Drops the static caches. Called when the game shuts down so the theme, the
## styles and the loaded fonts are released before the leak check runs.
static func release_cache() -> void:
	_theme = null
	_fonts.clear()


static func font(path: String) -> FontFile:
	if not _fonts.has(path):
		var loaded := load(path)
		if loaded is FontFile:
			# The CSV-free default rasteriser handles Arabic shaping through the
			# engine's advanced text server; the font only has to carry the glyphs.
			_fonts[path] = loaded
		else:
			_fonts[path] = null
	return _fonts[path]


static func body_font() -> Font:
	var loaded := font(FONT_BODY)
	return loaded if loaded != null else ThemeDB.fallback_font


static func bold_font() -> Font:
	var loaded := font(FONT_BOLD)
	return loaded if loaded != null else body_font()


static func display_font() -> Font:
	var loaded := font(FONT_DISPLAY)
	return loaded if loaded != null else bold_font()


static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = SIZE_BODY

	_style_label(theme, "Label", body_font(), SIZE_BODY, TEXT)
	_style_label(theme, "Headline", display_font(), SIZE_HEADLINE, GOLD)
	_style_label(theme, "Display", display_font(), SIZE_DISPLAY, GOLD)
	_style_label(theme, "Subhead", bold_font(), SIZE_SUBHEAD, TEXT)
	_style_label(theme, "Caption", body_font(), SIZE_CAPTION, TEXT_DIM)

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style())

	var normal := button_style(PANEL_DEEP, PURPLE)
	var hover := button_style(Color(0.129, 0.102, 0.196, 0.97), GOLD)
	var pressed := button_style(Color(0.239, 0.169, 0.353, 1.0), GOLD)
	var disabled := button_style(Color(0.070, 0.055, 0.098, 0.72), Color(0.35, 0.31, 0.38, 0.6))
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_font("font", "Button", bold_font())
	theme.set_font_size("font_size", "Button", SIZE_BUTTON)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)

	theme.set_stylebox("slider", "HSlider", slider_track())
	theme.set_stylebox("grabber_area", "HSlider", slider_fill(PURPLE))
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill(GOLD))
	theme.set_icon("grabber", "HSlider", _grabber_texture())
	theme.set_icon("grabber_highlight", "HSlider", _grabber_texture())

	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("h_separation", "HBoxContainer", 10)
	_theme = theme
	return theme


static func _style_label(theme: Theme, variation: String, label_font: Font, size: int, color: Color) -> void:
	# "Label" itself is the base type, not a variation of itself; the named ones
	# (Headline, Subhead, Caption, Display) are theme type variations.
	if variation != "Label":
		theme.set_type_variation(variation, "Label")
	theme.set_font("font", variation, label_font)
	theme.set_font_size("font_size", variation, size)
	theme.set_color("font_color", variation, color)


static func panel_style(deep := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_DEEP if deep else PANEL
	style.border_color = PURPLE
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_PANEL)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	return style


static func button_style(background: Color, border: Color, radius := RADIUS_BUTTON) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func slider_track() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.15, 0.24, 0.9)
	style.set_corner_radius_all(6)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func slider_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	return style


static func _grabber_texture() -> Texture2D:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(18):
		for x in range(18):
			var d := Vector2(x - 8.5, y - 8.5).length()
			if d <= 8.0:
				var edge := clampf(8.0 - d, 0.0, 1.5) / 1.5
				image.set_pixel(x, y, Color(GOLD.r, GOLD.g, GOLD.b, 1.0).lerp(Color(0, 0, 0, 0), 1.0 - edge))
	return ImageTexture.create_from_image(image)


# ------------------------------------------------------------------ widgets ---
static func tag(control: Control, key: String, align := -1) -> Control:
	control.set_meta(I18N_META, key)
	if align >= 0:
		control.set_meta(ALIGN_META, align)
	var translated := Localization.text(key)
	if control is Label:
		(control as Label).text = translated
	elif control is Button:
		(control as Button).text = translated
	return control


static func label(key: String, variation := "", align := -1) -> Label:
	var node := Label.new()
	if not variation.is_empty():
		node.theme_type_variation = variation
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag(node, key, align)
	return node


static func button(key: String) -> Button:
	var node := Button.new()
	node.custom_minimum_size = Vector2(0, MIN_TOUCH)
	tag(node, key, HORIZONTAL_ALIGNMENT_CENTER)
	return node


## Dim scrim plus a centred panel, shared by every menu so they match. Returns
## the vertical content box to fill and the panel that holds it.
static func modal(root: Control, title_key: String) -> Dictionary:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(margin)

	var panel := PanelContainer.new()
	panel.name = "ModalPanel"
	panel.custom_minimum_size = Vector2(320, 0)
	panel.add_theme_stylebox_override("panel", panel_style(true))
	margin.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := label(title_key, "Headline")
	title.name = "ModalTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_meta(ALIGN_META, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(title)

	return {"panel": panel, "content": column, "scrim": scrim}


## Paints every tagged control in `root` with the current language and mirrors
## its alignment when the language is right to left. Returns the number of
## controls that were updated, which is what the tests count.
static func retranslate(root: Node) -> int:
	var updated := 0
	if root is Control and root.has_meta(I18N_META):
		var control := root as Control
		var key := String(control.get_meta(I18N_META))
		var translated := Localization.text(key)
		if control is Label:
			(control as Label).text = translated
		elif control is Button:
			(control as Button).text = translated
		if control.has_meta(ALIGN_META):
			var align := int(control.get_meta(ALIGN_META))
			if control is Label:
				(control as Label).horizontal_alignment = align
			elif control is Button:
				(control as Button).alignment = align
		elif control is Label:
			(control as Label).horizontal_alignment = Localization.text_alignment()
		elif control is Button:
			(control as Button).alignment = HORIZONTAL_ALIGNMENT_CENTER
		control.layout_direction = Localization.layout_direction()
		updated += 1
	for child in root.get_children():
		updated += retranslate(child)
	return updated


## Every control in `root` that shows text but was never given a translation key.
## Must be empty: this is how "no hardcoded visible strings" is enforced.
static func untranslated(root: Node) -> Array[String]:
	var found: Array[String] = []
	var shown := ""
	if root is Label:
		shown = (root as Label).text
	elif root is Button:
		shown = (root as Button).text
	if not shown.strip_edges().is_empty() and not root.has_meta(I18N_META):
		found.append(String(root.get_path()))
	for child in root.get_children():
		found.append_array(untranslated(child))
	return found
