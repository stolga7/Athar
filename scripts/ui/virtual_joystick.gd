extends Control
## Analogue movement pad for touch, with a mouse path for desktop play.
##
## Behaviour that matters on a phone:
##   * one finger owns the stick — a second finger on the same pad is ignored, so
##     a stray touch cannot yank the hunter sideways;
##   * the knob is clamped to the ring, and a small deadzone keeps the hunter
##     still when a thumb rests on the centre;
##   * the output is a normalised vector, scaled by the player's sensitivity
##     setting, so the rest of the game never sees pixels;
##   * releasing anywhere (even off the pad) settles the stick back to zero, which
##     is what stops a slide-off from leaving the hunter walking forever.

signal moved(value: Vector2)

const UiKit := preload("res://scripts/ui/ui_kit.gd")

const DEADZONE := 0.12
## A pointer smaller than this fraction of the ring is treated as a tap, not a
## direction, so a resting thumb cannot creep forward.
const KNOB_RADIUS_FRACTION := 0.30

var value := Vector2.ZERO
var sensitivity := 1.0
var active := false

var _owner_index := -1
var _using_mouse := false
var _centre := Vector2.ZERO
var _knob := Vector2.ZERO
var _radius := 1.0


func setup(diameter: float) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_refresh_geometry()


func set_sensitivity(next: float) -> void:
	sensitivity = maxf(next, 0.05)


## Percentage of travel the thumb is currently asking for, 0..1.
func intensity() -> float:
	return minf(value.length() * sensitivity, 1.0)


func release() -> void:
	if not active:
		return
	active = false
	_owner_index = -1
	_using_mouse = false
	value = Vector2.ZERO
	_knob = _centre
	queue_redraw()
	moved.emit(value)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_geometry()


func _refresh_geometry() -> void:
	_centre = size * 0.5
	_radius = maxf(minf(size.x, size.y) * 0.5 - 6.0, 1.0)
	_knob = _centre
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _owner_index == -1 and Rect2(Vector2.ZERO, size).has_point(touch.position):
				_owner_index = touch.index
				_begin(touch.position)
				accept_event()
		elif touch.index == _owner_index:
			release()
			accept_event()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _owner_index:
			_aim(drag.position)
			accept_event()
		return
	# Mouse: same behaviour, so the pad is usable in the editor and on desktop.
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			if click.pressed:
				_using_mouse = true
				_owner_index = 0
				_begin(click.position)
			else:
				release()
			accept_event()
		return
	if event is InputEventMouseMotion and _using_mouse and active:
		_aim((event as InputEventMouseMotion).position)
		accept_event()


func _begin(at: Vector2) -> void:
	active = true
	_aim(at)


func _aim(at: Vector2) -> void:
	var offset := at - _centre
	var distance := offset.length()
	if distance > _radius:
		offset = offset / distance * _radius
	_knob = _centre + offset
	var raw := offset / _radius
	var magnitude := raw.length()
	var next := Vector2.ZERO
	if magnitude > DEADZONE:
		# Rescale past the deadzone so the first millimetre of travel is gentle
		# rather than a jump from zero to 12%.
		var scaled := (magnitude - DEADZONE) / (1.0 - DEADZONE)
		next = raw / magnitude * scaled * sensitivity
		if next.length() > 1.0:
			next = next.normalized()
	value = next
	queue_redraw()
	moved.emit(value)


func _draw() -> void:
	var ring := UiKit.PURPLE
	draw_circle(_centre, _radius + 6.0, Color(0.043, 0.031, 0.071, 0.42))
	draw_circle(_centre, _radius, Color(0.086, 0.067, 0.137, 0.58))
	draw_arc(_centre, _radius, 0.0, TAU, 48, Color(ring.r, ring.g, ring.b, 0.55), 2.0, true)
	# Four faint ticks give the ring a direction without adding an icon.
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		var inner := _centre + Vector2(cos(angle), sin(angle)) * (_radius - 12.0)
		var outer := _centre + Vector2(cos(angle), sin(angle)) * (_radius - 4.0)
		draw_line(inner, outer, Color(0.55, 0.47, 0.69, 0.42), 1.5, true)
	var knob_radius := _radius * KNOB_RADIUS_FRACTION
	var knob_colour := UiKit.GOLD if active else Color(0.80, 0.72, 0.56, 0.85)
	draw_circle(_knob, knob_radius + 3.0, Color(0.02, 0.01, 0.05, 0.55))
	draw_circle(_knob, knob_radius, Color(knob_colour.r, knob_colour.g, knob_colour.b, 0.92))
	draw_arc(_knob, knob_radius, 0.0, TAU, 32, Color(0.20, 0.14, 0.26, 0.7), 1.5, true)
