extends Control
## Pause screen: resume, settings, restart and a guarded way back to the title.
##
## It never destroys the hunt by itself. Restart and "main menu" both ask the
## confirmation prompt first, because a thumb on a phone slips and losing a chase
## to a mis-touch is the kind of thing players do not forgive.

signal resume_pressed
signal settings_pressed
signal regions_pressed
signal restart_pressed
signal menu_pressed

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")

var panel: PanelContainer
var content: VBoxContainer
var resume_button: Button
var settings_button: Button
var regions_button: Button
var restart_button: Button
var menu_button: Button

var _built := false


func _ready() -> void:
	theme = UiKit.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if not _built:
		_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var frame := UiKit.modal(self, "pause.title")
	panel = frame["panel"]
	content = frame["content"]
	panel.custom_minimum_size = Vector2(340, 0)

	resume_button = UiKit.button("menu.resume")
	resume_button.name = "ResumeButton"
	resume_button.pressed.connect(func() -> void: resume_pressed.emit())
	content.add_child(resume_button)

	settings_button = UiKit.button("menu.settings")
	settings_button.name = "PauseSettingsButton"
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	content.add_child(settings_button)

	regions_button = UiKit.button("menu.travel")
	regions_button.name = "RegionsButton"
	regions_button.pressed.connect(func() -> void: regions_pressed.emit())
	content.add_child(regions_button)

	restart_button = UiKit.button("menu.restart")
	restart_button.name = "RestartButton"
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	content.add_child(restart_button)

	menu_button = UiKit.button("menu.main_menu")
	menu_button.name = "MenuButton"
	menu_button.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	content.add_child(menu_button)

	retranslate()


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func retranslate() -> void:
	if not _built:
		return
	UiKit.retranslate(self)
	layout_direction = Localization.layout_direction()
