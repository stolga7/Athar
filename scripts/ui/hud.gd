extends Control
## The in-game HUD: vitals panel, analogue movement pad, context buttons, pause,
## toast feedback and the off-screen deer cue.
##
## Layout is computed from the viewport size in `layout_for()` rather than from
## hardcoded offsets, so a 16:9 phone, a 20:9 phone and a tablet all get sensible
## margins and the same comfortable touch sizes. The panel, the pause button and
## the text mirror for right-to-left languages; the movement pad stays bottom-left
## and the action button bottom-right in both, which is the muscle memory every
## player already has.
##
## The HUD owns no gameplay state. It shows what `main.gd` hands it and emits
## signals when the player touches something.

signal action_pressed
signal interact_pressed
signal pause_pressed
signal move_changed(value: Vector2)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")
const Joystick := preload("res://scripts/ui/virtual_joystick.gd")
const VitalsBar := preload("res://scripts/ui/vitals_bar.gd")
const DeerMarker := preload("res://scripts/ui/deer_marker.gd")

const PANEL_MIN_WIDTH := 296.0
const PANEL_MAX_WIDTH := 560.0
const PAUSE_SIZE := 60.0
const JOYSTICK_MIN := 118.0
const JOYSTICK_MAX := 192.0
const ACTION_MIN := 92.0
const ACTION_MAX := 132.0
const INTERACT_HEIGHT := 58.0
const TOAST_SECONDS := 2.4

var joystick: Control
var action_button: Button
var interact_button: Button
var pause_button: Button
var panel: PanelContainer
var status_label: Label
var info_label: Label
var title_label: Label
var region_label: Label
var stamina_bar: Control
var condition_bar: Control
var alert_bar: Control
var toast_label: Label
var hint_label: Label
var marker: Control

## Screen edges taken by a notch or a rounded corner, in HUD pixels.
var safe_insets := Rect2()

var _built := false
var _view_size := Vector2(1280, 720)
var _toast_seconds := 0.0
var _relayout_guard := false
var _compact := false
var _status_key := "hud.initial_status"
var _info_parts := PackedStringArray()
var _action_key := "hud.action.hunt"
var _interact_key := ""
var _toast_key := ""
var _toast_arg := -1
var _region_key := ""
var _region_visited := 0
var _region_total := 0


func _ready() -> void:
	theme = UiKit.build_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _built:
		_build()


func setup(settings: RefCounted = null) -> void:
	if not _built:
		_build()
	set_sensitivity(float(settings.sensitivity) if settings != null else 1.0)
	retranslate()
	layout_for(size if size.length() > 0.0 else get_viewport().get_visible_rect().size)


func set_sensitivity(value: float) -> void:
	if joystick != null:
		joystick.set_sensitivity(value)


func _build() -> void:
	if _built:
		return
	_built = true

	# Behind everything: the off-screen deer cue, so it never covers a control.
	marker = DeerMarker.new()
	marker.name = "DeerMarker"
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker)

	panel = PanelContainer.new()
	panel.name = "TopPanel"
	panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	title_label = UiKit.label("app.title", "Headline")
	title_label.name = "Title"
	# The title is one short word: wrapping it never helps and would let a font
	# with tall metrics stretch the vitals panel.
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(title_label)

	# Which of the ten regions the hunter is standing in, and how many have been
	# seen. Rebuilt from keys like the info line, so it reads in both languages.
	region_label = UiKit.label("hud.region", "Caption")
	region_label.name = "Region"
	region_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(region_label)

	status_label = UiKit.label("hud.initial_status", "Subhead")
	status_label.name = "Status"
	status_label.custom_minimum_size = Vector2(0, 44)
	column.add_child(status_label)

	info_label = Label.new()
	info_label.name = "Info"
	info_label.theme_type_variation = "Caption"
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A key so the "no untagged text" rule holds; the live line is rebuilt from
	# its own keys every frame (see set_info).
	UiKit.tag(info_label, "hud.info")
	column.add_child(info_label)

	var vitals := VBoxContainer.new()
	vitals.name = "Vitals"
	vitals.add_theme_constant_override("separation", 4)
	column.add_child(vitals)

	stamina_bar = VitalsBar.new()
	stamina_bar.name = "Stamina"
	stamina_bar.setup("hud.vital.stamina", UiKit.GOLD)
	vitals.add_child(stamina_bar)

	condition_bar = VitalsBar.new()
	condition_bar.name = "Condition"
	condition_bar.setup("hud.vital.condition", UiKit.PURPLE)
	vitals.add_child(condition_bar)

	alert_bar = VitalsBar.new()
	alert_bar.name = "Alert"
	alert_bar.setup("hud.vital.alert", UiKit.CYAN)
	vitals.add_child(alert_bar)

	pause_button = UiKit.button("hud.pause")
	pause_button.name = "PauseButton"
	pause_button.custom_minimum_size = Vector2(PAUSE_SIZE, PAUSE_SIZE)
	pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	add_child(pause_button)

	joystick = Joystick.new()
	joystick.name = "MoveStick"
	add_child(joystick)
	joystick.moved.connect(func(value: Vector2) -> void: move_changed.emit(value))

	action_button = UiKit.button("hud.action.hunt")
	action_button.name = "ActionButton"
	action_button.add_theme_font_size_override("font_size", 21)
	action_button.add_theme_color_override("font_color", UiKit.GOLD)
	action_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	action_button.add_theme_stylebox_override("normal", UiKit.button_style(Color(0.20, 0.14, 0.30, 0.95), UiKit.GOLD_DEEP, 26))
	action_button.add_theme_stylebox_override("hover", UiKit.button_style(Color(0.26, 0.18, 0.38, 0.98), UiKit.GOLD, 26))
	action_button.add_theme_stylebox_override("pressed", UiKit.button_style(Color(0.40, 0.29, 0.16, 1.0), UiKit.GOLD, 26))
	action_button.pressed.connect(func() -> void: action_pressed.emit())
	add_child(action_button)

	interact_button = UiKit.button("hud.capture")
	interact_button.name = "InteractButton"
	interact_button.add_theme_stylebox_override("normal", UiKit.button_style(Color(0.08, 0.20, 0.21, 0.94), UiKit.CYAN, 18))
	interact_button.add_theme_stylebox_override("pressed", UiKit.button_style(Color(0.14, 0.34, 0.35, 1.0), UiKit.CYAN, 18))
	interact_button.visible = false
	interact_button.pressed.connect(func() -> void: interact_pressed.emit())
	add_child(interact_button)

	toast_label = UiKit.label("toast.saved", "Subhead", HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.name = "Toast"
	# Short messages on one line: wrapping here would make the toast's minimum
	# height depend on its width, which is exactly what the layout below avoids.
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast_label.visible = false
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.add_theme_color_override("font_color", UiKit.GOLD)
	toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	toast_label.add_theme_constant_override("shadow_offset_x", 0)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(toast_label)

	hint_label = UiKit.label("hud.hint", "Caption")
	hint_label.name = "Hint"
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)

	retranslate()


# ------------------------------------------------------------------ state ----
func set_status_key(key: String) -> void:
	_status_key = key
	if status_label == null:
		return
	# Re-tagging keeps the message in the new language after a language switch.
	if String(status_label.get_meta(UiKit.I18N_META, "")) != key:
		UiKit.tag(status_label, key)


## Restores whichever status message was last shown, used after a language change.
func current_status_key() -> String:
	return _status_key


## The region line: the loaded region's name plus the discovery count. `key` is
## the region's own name key, so a language switch only needs `retranslate()`.
func set_region(key: String, visited: int, total: int) -> void:
	_region_key = key
	_region_visited = visited
	_region_total = total
	_refresh_region()


func region_key() -> String:
	return _region_key


func region_text() -> String:
	return region_label.text if region_label != null else ""


func _refresh_region() -> void:
	if region_label == null:
		return
	region_label.visible = not _compact and not _region_key.is_empty()
	if _region_key.is_empty():
		return
	var progress := Localization.text("hud.region.progress") % [_region_visited, _region_total]
	region_label.text = "%s  •  %s" % [Localization.text(_region_key), progress]
	region_label.horizontal_alignment = Localization.text_alignment()


## The information line is built from translation keys (clock, day phase, weather,
## what the deer is doing) instead of an English sentence, so it reads correctly in
## both languages and still updates every frame.
func set_info(clock: String, phase_key: String, weather_key: String, deer_key: String) -> void:
	_info_parts = PackedStringArray([clock, phase_key, weather_key, deer_key])
	_refresh_info()


func _refresh_info() -> void:
	if info_label == null or _info_parts.is_empty():
		return
	var phase := Localization.text(_info_parts[1])
	var weather := Localization.text(_info_parts[2])
	var deer := Localization.text(_info_parts[3])
	info_label.text = "%s  •  %s  •  %s  •  %s" % [_info_parts[0], phase, weather, deer]
	info_label.horizontal_alignment = Localization.text_alignment()


func set_vitals(stamina: float, condition: float, alert: float) -> void:
	if stamina_bar != null:
		stamina_bar.set_value(stamina)
	if condition_bar != null:
		condition_bar.set_value(condition)
	if alert_bar != null:
		alert_bar.set_value(alert)


func set_action_key(key: String) -> void:
	if key == _action_key and action_button != null:
		return
	_action_key = key
	if action_button != null:
		action_button.text = Localization.text(key)


func action_key() -> String:
	return _action_key


## Shows the context button with `key`, or hides it when `key` is empty. Hiding
## it means "there is nothing to do here", which is why it never sits on screen
## doing nothing.
func set_interact_key(key: String) -> void:
	if key == _interact_key and interact_button != null:
		return
	_interact_key = key
	if interact_button == null:
		return
	interact_button.visible = not key.is_empty()
	if not key.is_empty():
		interact_button.text = Localization.text(key)


func interact_key() -> String:
	return _interact_key


## Transient confirmation or refusal, e.g. "Too far — 24 m".
func toast(key: String, arg := -1) -> void:
	_toast_key = key
	_toast_arg = arg
	if toast_label == null:
		return
	toast_label.text = _format(key, arg)
	toast_label.visible = true
	toast_label.modulate = Color(1, 1, 1, 1)
	_toast_seconds = TOAST_SECONDS


func _format(key: String, arg: int) -> String:
	var text := Localization.text(key)
	return text % arg if arg >= 0 else text


func toast_visible() -> bool:
	return toast_label != null and toast_label.visible


func _process(delta: float) -> void:
	if _toast_seconds <= 0.0:
		return
	_toast_seconds -= delta
	if _toast_seconds <= 0.0:
		toast_label.visible = false
	elif _toast_seconds < 0.5:
		toast_label.modulate = Color(1, 1, 1, _toast_seconds / 0.5)


func release_controls() -> void:
	if joystick != null:
		joystick.release()


# ----------------------------------------------------------------- layout ----
## Records the screen edges covered by hardware (notch, rounded corners). Values
## are in HUD pixels, so the caller converts from physical pixels.
func set_safe_insets(left: float, top: float, right: float, bottom: float) -> void:
	safe_insets = Rect2(left, top, right, bottom)
	layout_for(_view_size)


## Converts the platform safe-area rectangle into insets for the current size.
func apply_safe_area(safe_rect: Rect2i, window_size: Vector2i, viewport_size := Vector2.ZERO) -> void:
	var target := viewport_size if viewport_size.length() > 0.0 else _view_size
	var window_x := maxi(window_size.x, 1)
	var window_y := maxi(window_size.y, 1)
	var left := maxf(0.0, float(safe_rect.position.x)) * target.x / window_x
	var top := maxf(0.0, float(safe_rect.position.y)) * target.y / window_y
	var right := maxf(0.0, float(window_x - safe_rect.end.x)) * target.x / window_x
	var bottom := maxf(0.0, float(window_y - safe_rect.end.y)) * target.y / window_y
	set_safe_insets(left, top, right, bottom)


## Positions every element for `viewport_size`. Safe to call every frame; it only
## writes properties when a value actually changes, so a static screen costs one
## comparison per control and no redraws.
func layout_for(viewport_size: Vector2) -> void:
	if not _built:
		return
	_view_size = viewport_size
	var shortest := minf(viewport_size.x, viewport_size.y)
	var margin := clampf(shortest * 0.035, 14.0, 30.0)
	var left := margin + safe_insets.position.x
	var top := margin + safe_insets.position.y
	var right := margin + safe_insets.size.x
	var bottom := margin + safe_insets.size.y
	var rtl := Localization.is_rtl()
	# A short screen (a phone held sideways in a small window) keeps only what the
	# player needs: the message and the vitals, without the title and the clock.
	_compact = shortest < 420.0
	title_label.visible = not _compact
	region_label.visible = not _compact and not _region_key.is_empty()
	info_label.visible = not _compact
	status_label.custom_minimum_size = Vector2(0, 0 if _compact else 44)

	# Vitals panel: top corner on the reading side of the screen.
	var panel_width := clampf(viewport_size.x * 0.42, PANEL_MIN_WIDTH, minf(PANEL_MAX_WIDTH, viewport_size.x - left - right - PAUSE_SIZE - 20.0))
	# The wrapped labels get their width up front. Without this a label's minimum
	# height depends on its current width, and a panel that was once narrow keeps
	# a tall minimum size even after it is widened.
	var text_width := maxf(panel_width - 40.0, 96.0)
	status_label.custom_minimum_size.x = text_width
	title_label.custom_minimum_size.x = text_width
	region_label.custom_minimum_size.x = text_width
	info_label.custom_minimum_size.x = text_width
	panel.size = Vector2(maxf(panel_width, PANEL_MIN_WIDTH * 0.8), 0.0)
	panel.position = Vector2(viewport_size.x - panel_width - right, top) if rtl else Vector2(left, top)

	# Pause: the opposite top corner, always the same size.
	var pause_size := clampf(shortest * 0.085, PAUSE_SIZE, 72.0)
	pause_button.size = Vector2(pause_size, pause_size)
	pause_button.position = Vector2(left, top) if rtl else Vector2(viewport_size.x - pause_size - right, top)

	# Stick: bottom-left, sized by the short edge so a small phone still gets a
	# thumb-sized ring without it growing over the action button.
	var stick := clampf(shortest * 0.30, JOYSTICK_MIN, JOYSTICK_MAX)
	joystick.custom_minimum_size = Vector2(stick, stick)
	joystick.size = Vector2(stick, stick)
	joystick.position = Vector2(left, viewport_size.y - stick - bottom)

	var action := clampf(shortest * 0.185, ACTION_MIN, ACTION_MAX)
	action_button.custom_minimum_size = Vector2(action, action)
	action_button.size = Vector2(action, action)
	action_button.position = Vector2(viewport_size.x - action - right, viewport_size.y - action - bottom)

	var interact_width := clampf(action * 1.25, 132.0, 176.0)
	interact_button.custom_minimum_size = Vector2(interact_width, INTERACT_HEIGHT)
	interact_button.size = Vector2(interact_width, INTERACT_HEIGHT)
	interact_button.position = Vector2(viewport_size.x - interact_width - right, viewport_size.y - action - bottom - INTERACT_HEIGHT - 12.0)

	var toast_width := clampf(viewport_size.x * 0.56, 240.0, 560.0)
	toast_label.size = Vector2(toast_width, 40.0)
	toast_label.position = Vector2((viewport_size.x - toast_width) * 0.5, viewport_size.y - bottom - action - INTERACT_HEIGHT - 64.0)

	# The hint sits under the panel and disappears rather than overlapping the
	# controls on a short screen.
	# Width first, height second: an autowrapped label computes its minimum height
	# from the width it has at that moment, so setting both at once can leave it
	# with a height from the previous (narrower) width.
	var hint_width := minf(panel_width, viewport_size.x - left - right)
	# custom_minimum_size.x is what the label shapes against; assigning `size`
	# alone leaves the minimum height from a zero-width first pass.
	hint_label.custom_minimum_size = Vector2(hint_width, 0.0)
	hint_label.size = Vector2(hint_width, 24.0)
	hint_label.position = Vector2(panel.position.x, top + panel.size.y + 8.0)
	hint_label.visible = hint_label.position.y + hint_label.size.y < viewport_size.y * 0.5
	hint_label.horizontal_alignment = Localization.text_alignment()

	# A wrapped label's minimum height depends on the width it currently has, so
	# the first pass after a resize (or at startup) can over-estimate the panel.
	# One fix-up pass with the real widths settles it without looping.
	if not _relayout_guard:
		_relayout_guard = true
		layout_for(viewport_size)
		_relayout_guard = false

	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		layout_for(get_viewport().get_visible_rect().size)


# ----------------------------------------------------------- localization ----
## Re-fills every text from the CSV and mirrors the whole HUD. Called on start-up
## and whenever the player changes language in the settings.
func retranslate() -> void:
	if not _built:
		return
	UiKit.retranslate(self)
	layout_direction = Localization.layout_direction()
	_refresh_info()
	_refresh_region()
	set_status_key(_status_key)
	set_action_key(_action_key)
	set_interact_key(_interact_key)
	if not _toast_key.is_empty() and toast_visible():
		toast_label.text = _format(_toast_key, _toast_arg)
	layout_for(_view_size)
