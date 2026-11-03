extends Control
## Settings screen: sound, graphics, language and stick sensitivity.
##
## It is a plain Control that main.gd adds to a menu layer; opening and closing is
## just visibility, so a phone never rebuilds a screen or reloads a scene. Every
## change is written to the settings file immediately (except slider drags, which
## save when the finger lifts) so a killed app loses nothing.

signal closed
signal language_changed(code: String)
signal quality_changed(level: String)
signal sensitivity_changed(value: float)
signal reset_requested

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")
const GameSettings := preload("res://scripts/settings/game_settings.gd")
const GraphicsProfile := preload("res://scripts/settings/graphics_profile.gd")
const AudioPanel := preload("res://scripts/ui/audio_panel.gd")

var settings: RefCounted
var panel: PanelContainer
var content: VBoxContainer
var audio_section: Control
var sensitivity_slider: HSlider
var close_button: Button
var reset_button: Button
var language_buttons := {}
var quality_buttons := {}

var _built := false


func _ready() -> void:
	theme = UiKit.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if not _built:
		_build()


func setup(game_settings: RefCounted) -> void:
	settings = game_settings
	if not _built:
		_build()
	if audio_section != null:
		audio_section.setup(settings)
	_sync_from_settings()


func _build() -> void:
	if _built:
		return
	_built = true
	var frame := UiKit.modal(self, "settings.title")
	panel = frame["panel"]
	content = frame["content"]

	# Sound is the Phase 3.4 section, folded out under its own header.
	audio_section = AudioPanel.new()
	audio_section.name = "AudioSection"
	content.add_child(audio_section)

	content.add_child(_rule())
	content.add_child(UiKit.label("settings.graphics", "Subhead"))

	var quality_row := HBoxContainer.new()
	quality_row.name = "QualityRow"
	quality_row.add_theme_constant_override("separation", 8)
	var quality_label := UiKit.label("settings.quality", "Caption")
	quality_label.custom_minimum_size = Vector2(120, 0)
	quality_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quality_row.add_child(quality_label)
	for level in GraphicsProfile.PRESETS.keys():
		var button := UiKit.button(GraphicsProfile.label_key(String(level)))
		button.name = "Quality_%s" % level
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_quality.bind(String(level)))
		quality_row.add_child(button)
		quality_buttons[String(level)] = button
	content.add_child(quality_row)
	content.add_child(UiKit.label("settings.quality.note", "Caption"))

	content.add_child(_rule())
	content.add_child(UiKit.label("settings.language", "Subhead"))

	var language_row := HBoxContainer.new()
	language_row.name = "LanguageRow"
	language_row.add_theme_constant_override("separation", 8)
	for code in Localization.LANGUAGES:
		var button := UiKit.button("settings.language.%s" % code)
		button.name = "Language_%s" % code
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_language.bind(String(code)))
		language_row.add_child(button)
		language_buttons[String(code)] = button
	content.add_child(language_row)

	content.add_child(_rule())
	content.add_child(UiKit.label("settings.sensitivity", "Subhead"))

	var sensitivity_row := HBoxContainer.new()
	sensitivity_row.name = "SensitivityRow"
	sensitivity_row.add_theme_constant_override("separation", 10)
	sensitivity_row.add_child(UiKit.label("settings.sensitivity.slow", "Caption"))
	sensitivity_slider = HSlider.new()
	sensitivity_slider.name = "SensitivitySlider"
	sensitivity_slider.min_value = GameSettings.SENSITIVITY_MIN
	sensitivity_slider.max_value = GameSettings.SENSITIVITY_MAX
	sensitivity_slider.step = 0.1
	sensitivity_slider.custom_minimum_size = Vector2(150, 44)
	sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_slider.value_changed.connect(func(value: float) -> void: sensitivity_changed.emit(value))
	sensitivity_slider.drag_ended.connect(func(_changed: bool) -> void:
		if settings != null:
			settings.set_sensitivity(sensitivity_slider.value)
			settings.save()
	)
	sensitivity_row.add_child(sensitivity_slider)
	sensitivity_row.add_child(UiKit.label("settings.sensitivity.fast", "Caption"))
	content.add_child(sensitivity_row)

	content.add_child(_rule())
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button = UiKit.button("settings.reset")
	reset_button.name = "ResetButton"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.pressed.connect(_on_reset)
	actions.add_child(reset_button)
	close_button = UiKit.button("settings.close")
	close_button.name = "CloseButton"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(close)
	actions.add_child(close_button)
	content.add_child(actions)

	retranslate()


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(UiKit.PURPLE.r, UiKit.PURPLE.g, UiKit.PURPLE.b, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func open() -> void:
	visible = true
	_sync_from_settings()


func close() -> void:
	visible = false
	closed.emit()


func _sync_from_settings() -> void:
	if settings == null:
		return
	for code in language_buttons.keys():
		(language_buttons[code] as Button).button_pressed = code == settings.language
	for level in quality_buttons.keys():
		(quality_buttons[level] as Button).button_pressed = level == settings.quality
	if sensitivity_slider != null:
		sensitivity_slider.set_value_no_signal(clampf(settings.sensitivity, sensitivity_slider.min_value, sensitivity_slider.max_value))
	if audio_section != null:
		audio_section.setup(settings)


func _on_language(code: String) -> void:
	if settings == null:
		return
	settings.set_language(code)
	settings.save()
	_sync_from_settings()
	language_changed.emit(code)


func _on_quality(level: String) -> void:
	if settings == null:
		return
	settings.set_quality(level)
	settings.save()
	_sync_from_settings()
	quality_changed.emit(level)


func _on_reset() -> void:
	if settings == null:
		return
	settings.reset()
	settings.save()
	_sync_from_settings()
	reset_requested.emit()


## Re-fills every text and mirrors the panel for an Arabic or English screen.
func retranslate() -> void:
	if not _built:
		return
	UiKit.retranslate(self)
	layout_direction = Localization.layout_direction()
	if audio_section != null:
		audio_section.setup(settings)
