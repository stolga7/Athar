extends VBoxContainer
## Collapsible sound section: three volume sliders and a mute toggle.
##
## Phase 3.4 shipped this as a floating panel with its own corner button; Phase
## 3.5 moved it into the settings screen, so it is now a section that folds out
## under a header. The API the audio tests rely on is unchanged: `settings`,
## `panel` (the fold-out box), the three sliders, `mute_button` and `toggle()`.
##
## Sliders change the bus immediately as the thumb moves, but the file is only
## written when the drag ends — a ConfigFile write on every frame of a drag is
## exactly the kind of thing that stutters a modest phone.

signal changed
signal saved

const UiKit := preload("res://scripts/ui/ui_kit.gd")

var settings: RefCounted
var panel: VBoxContainer
var open_button: Button
var master_slider: HSlider
var music_slider: HSlider
var effects_slider: HSlider
var mute_button: Button

var _rows := {}
var _built := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	if not _built:
		_build()


func setup(audio_settings: RefCounted) -> void:
	settings = audio_settings
	if not _built:
		_build()
	_sync_from_settings()


func _build() -> void:
	if _built:
		return
	_built = true

	open_button = UiKit.button("settings.audio")
	open_button.name = "AudioOpen"
	open_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_button.pressed.connect(toggle)
	add_child(open_button)

	panel = VBoxContainer.new()
	panel.name = "AudioPanel"
	panel.add_theme_constant_override("separation", 8)
	panel.visible = false
	add_child(panel)

	master_slider = _add_row("settings.master", "master")
	music_slider = _add_row("settings.music", "music")
	effects_slider = _add_row("settings.effects", "effects")

	mute_button = UiKit.button("settings.mute")
	mute_button.name = "AudioMute"
	mute_button.custom_minimum_size = Vector2(0, 48)
	mute_button.pressed.connect(_on_mute)
	panel.add_child(mute_button)


func _add_row(label_key: String, key: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := UiKit.label(label_key, "Caption")
	label.custom_minimum_size = Vector2(120, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(140, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: _on_slider(key, value))
	slider.drag_ended.connect(func(_changed: bool) -> void: _persist())
	row.add_child(slider)
	panel.add_child(row)
	_rows[key] = slider
	return slider


func toggle() -> void:
	if panel == null:
		return
	panel.visible = not panel.visible
	if panel.visible:
		_sync_from_settings()


func is_open() -> bool:
	return panel != null and panel.visible


func _on_slider(key: String, value: float) -> void:
	changed.emit()
	if settings == null:
		return
	match key:
		"master":
			settings.set_master(value)
		"music":
			settings.set_music(value)
		"effects":
			settings.set_effects(value)


func _on_mute() -> void:
	if settings == null:
		return
	settings.toggle_mute()
	_sync_from_settings()
	changed.emit()
	_persist()


func _persist() -> void:
	if settings == null:
		return
	settings.save()
	saved.emit()


func _sync_from_settings() -> void:
	if settings == null or _rows.is_empty():
		return
	_rows["master"].set_value_no_signal(settings.master)
	_rows["music"].set_value_no_signal(settings.music)
	_rows["effects"].set_value_no_signal(settings.effects)
	# Re-tagging keeps the label correct after a language change, when one walk
	# over the tree re-fills every text from its key.
	UiKit.tag(mute_button, "settings.unmute" if settings.muted else "settings.mute", HORIZONTAL_ALIGNMENT_CENTER)
