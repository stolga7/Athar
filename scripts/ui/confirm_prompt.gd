extends Control
## Small yes/no prompt for actions that throw away the current hunt.
##
## One instance is reused for both "restart" and "return to the main menu"; it is
## re-labelled each time it opens, so no screen is ever destroyed and rebuilt.

signal confirmed
signal cancelled

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")

var panel: PanelContainer
var content: VBoxContainer
var title_label: Label
var body_label: Label
var confirm_button: Button
var cancel_button: Button

var _title_key := "confirm.restart.title"
var _body_key := "confirm.restart.body"
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
	var frame := UiKit.modal(self, _title_key)
	panel = frame["panel"]
	content = frame["content"]
	panel.custom_minimum_size = Vector2(330, 0)
	title_label = panel.find_child("ModalTitle", true, false) as Label

	body_label = UiKit.label(_body_key, "Caption")
	body_label.name = "Body"
	content.add_child(body_label)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	confirm_button = UiKit.button("confirm.yes")
	confirm_button.name = "ConfirmButton"
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(_on_confirm)
	actions.add_child(confirm_button)
	cancel_button = UiKit.button("confirm.no")
	cancel_button.name = "CancelButton"
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(_on_cancel)
	actions.add_child(cancel_button)
	content.add_child(actions)

	retranslate()


## `title_key` explains what will be lost; the buttons are the same every time.
func ask(title_key: String, body_key: String) -> void:
	_title_key = title_key
	_body_key = body_key
	if title_label != null:
		title_label.set_meta(UiKit.I18N_META, title_key)
	if body_label != null:
		body_label.set_meta(UiKit.I18N_META, body_key)
	retranslate()
	visible = true


func dismiss() -> void:
	visible = false


func _on_confirm() -> void:
	visible = false
	confirmed.emit()


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func retranslate() -> void:
	if not _built:
		return
	UiKit.retranslate(self)
	layout_direction = Localization.layout_direction()
