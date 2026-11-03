extends Control
## One labelled gauge: a small caption above a slim bar.
##
## Three of these sit in the HUD panel (breath, quarry condition, alertness). They
## are plain [Control]s that draw two rectangles, so a phone redraws three quads
## per gauge and nothing else. RTL mirrors the fill direction, so an Arabic HUD
## fills from the right edge.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")

const BAR_HEIGHT := 9.0
const TRACK_COLOR := Color(0.153, 0.125, 0.208, 0.92)

var value := 1.0
var fill_color := UiKit.GOLD
var title: Label

var _track_style: StyleBoxFlat
var _fill_style: StyleBoxFlat


func setup(title_key: String, color: Color) -> void:
	fill_color = color
	custom_minimum_size = Vector2(0, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = UiKit.label(title_key, "Caption")
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	_track_style = StyleBoxFlat.new()
	_track_style.bg_color = TRACK_COLOR
	_track_style.set_corner_radius_all(4)
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = color
	_fill_style.set_corner_radius_all(4)
	queue_redraw()


func set_value(next: float) -> void:
	var clamped := clampf(next, 0.0, 1.0)
	if is_equal_approx(clamped, value):
		return
	value = clamped
	queue_redraw()


func set_fill_color(color: Color) -> void:
	fill_color = color
	if _fill_style != null:
		_fill_style.bg_color = color
	queue_redraw()


func _draw() -> void:
	var top := size.y - BAR_HEIGHT
	var track := Rect2(0, top, size.x, BAR_HEIGHT)
	draw_style_box(_track_style, track)
	var width := roundf(size.x * value)
	if width < 2.0:
		return
	var filled := Rect2(0, top, width, BAR_HEIGHT)
	if Localization.is_rtl():
		filled.position.x = size.x - width
	draw_style_box(_fill_style, filled)
