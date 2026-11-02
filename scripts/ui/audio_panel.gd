extends Control
## Compact audio settings panel: three volume sliders and a mute toggle.
##
## Kept deliberately small and tucked into the top-right corner so it never
## covers the movement pad, the hunt button or the deer cue. It is a normal
## Control, so it can be built and inspected headlessly.

signal closed

const PANEL_SIZE := Vector2(286, 232)
const BUTTON_SIZE := Vector2(104, 46)
const MARGIN := 22.0

var settings: RefCounted
var panel: PanelContainer
var master_slider: HSlider
var music_slider: HSlider
var effects_slider: HSlider
var mute_button: Button
var open_button: Button

var _rows := {}


func setup(audio_settings: RefCounted) -> void:
	settings = audio_settings
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	open_button = Button.new()
	open_button.name = "AudioOpen"
	open_button.text = "AUDIO"
	open_button.size = BUTTON_SIZE
	open_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	open_button.position = Vector2(-BUTTON_SIZE.x - MARGIN, MARGIN)
	open_button.add_theme_font_size_override("font_size", 16)
	open_button.add_theme_color_override("font_color", Color(0.98, 0.88, 0.63))
	open_button.add_theme_stylebox_override("normal", _style(Color(0.12, 0.19, 0.16, 0.86)))
	open_button.add_theme_stylebox_override("pressed", _style(Color(0.35, 0.34, 0.20, 0.96)))
	open_button.pressed.connect(toggle)
	add_child(open_button)

	panel = PanelContainer.new()
	panel.name = "AudioPanel"
	panel.size = PANEL_SIZE
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-PANEL_SIZE.x - MARGIN, MARGIN + BUTTON_SIZE.y + 10.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.visible = false
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "AUDIO"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.91, 0.78, 0.48))
	column.add_child(title)

	master_slider = _add_row(column, "Master", "master")
	music_slider = _add_row(column, "Music", "music")
	effects_slider = _add_row(column, "Effects", "effects")

	mute_button = Button.new()
	mute_button.name = "AudioMute"
	mute_button.text = "MUTE"
	mute_button.custom_minimum_size = Vector2(0, 38)
	mute_button.add_theme_font_size_override("font_size", 15)
	mute_button.add_theme_color_override("font_color", Color(0.96, 0.91, 0.75))
	mute_button.add_theme_stylebox_override("normal", _style(Color(0.14, 0.20, 0.17, 0.9)))
	mute_button.add_theme_stylebox_override("pressed", _style(Color(0.42, 0.30, 0.13, 0.96)))
	mute_button.pressed.connect(_on_mute)
	column.add_child(mute_button)

	_sync_from_settings()


func _add_row(parent: Control, label_text: String, key: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(66, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.90, 0.91, 0.84))
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(170, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: _on_slider(key, value))
	row.add_child(slider)
	parent.add_child(row)
	_rows[key] = slider
	return slider


func toggle() -> void:
	panel.visible = not panel.visible
	open_button.visible = not panel.visible
	if panel.visible:
		_sync_from_settings()


func _on_slider(key: String, value: float) -> void:
	if settings == null:
		return
	match key:
		"master":
			settings.set_master(value)
		"music":
			settings.set_music(value)
		"effects":
			settings.set_effects(value)
	settings.save()


func _on_mute() -> void:
	if settings == null:
		return
	settings.toggle_mute()
	settings.save()
	_sync_from_settings()


func _sync_from_settings() -> void:
	if settings == null:
		return
	_rows["master"].set_value_no_signal(settings.master)
	_rows["music"].set_value_no_signal(settings.music)
	_rows["effects"].set_value_no_signal(settings.effects)
	mute_button.text = "UNMUTE" if settings.muted else "MUTE"


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.68, 0.59, 0.35, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.09, 0.94)
	style.border_color = Color(0.55, 0.48, 0.30, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
