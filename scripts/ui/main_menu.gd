extends Control
## Title screen. Shown once at launch, and again if the player leaves a hunt from
## the pause menu.
##
## Deliberately quiet: the live world stays visible behind the scrim, so the menu
## is the forest at dusk rather than a separate screen with its own art.

signal begin_pressed
signal settings_pressed
signal regions_pressed
signal quit_pressed

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")

var panel: PanelContainer
var content: VBoxContainer
var begin_button: Button
var settings_button: Button
var regions_button: Button
var quit_button: Button

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
	var frame := UiKit.modal(self, "app.title")
	panel = frame["panel"]
	content = frame["content"]
	panel.custom_minimum_size = Vector2(360, 0)

	# The modal helper already put the game title at the top; make it big.
	var title := panel.find_child("ModalTitle", true, false) as Label
	if title != null:
		title.theme_type_variation = "Display"
		title.add_theme_font_size_override("font_size", UiKit.SIZE_DISPLAY)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.set_meta(UiKit.ALIGN_META, HORIZONTAL_ALIGNMENT_CENTER)

	var tagline := UiKit.label("app.tagline", "Caption", HORIZONTAL_ALIGNMENT_CENTER)
	tagline.name = "Tagline"
	content.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	content.add_child(spacer)

	begin_button = UiKit.button("menu.begin")
	begin_button.name = "BeginButton"
	begin_button.pressed.connect(func() -> void: begin_pressed.emit())
	content.add_child(begin_button)

	regions_button = UiKit.button("menu.regions")
	regions_button.name = "RegionsButton"
	regions_button.pressed.connect(func() -> void: regions_pressed.emit())
	content.add_child(regions_button)

	settings_button = UiKit.button("menu.settings")
	settings_button.name = "MenuSettingsButton"
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	content.add_child(settings_button)

	quit_button = UiKit.button("menu.quit")
	quit_button.name = "QuitButton"
	quit_button.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	content.add_child(quit_button)

	var version := UiKit.label("menu.version", "Caption", HORIZONTAL_ALIGNMENT_CENTER)
	version.name = "Version"
	content.add_child(version)

	retranslate()


func open() -> void:
	visible = true


func close() -> void:
	visible = false


## Re-fills every text and mirrors the screen. Also used by the settings screen's
## language switch, which must not require leaving the menu.
func retranslate() -> void:
	if not _built:
		return
	UiKit.retranslate(self)
	layout_direction = Localization.layout_direction()
