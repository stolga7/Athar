extends Control
## Off-screen deer cue.
##
## With the camera pulled in close enough to read the hunter, a fleeing deer can
## leave the frame entirely, and the player then has no idea which way to run.
## This overlay draws a small gold chevron at the screen edge pointing at the
## deer, with the distance in metres, and disappears the moment the deer is on
## screen again.
##
## It is presentation only: it reads the camera and the deer's position, never
## changes gameplay, and draws nothing when the deer is visible.

## Distance from the screen edge to the chevron centre, in pixels.
const EDGE_MARGIN := 76.0
const CHEVRON_LENGTH := 15.0
const CHEVRON_WIDTH := 11.0
const COLOR := Color(0.94, 0.83, 0.52, 0.92)
const SHADOW_COLOR := Color(0.05, 0.06, 0.05, 0.55)
## Beyond this distance an on-screen deer is only a few pixels of coat, so it
## gets a small diamond and a range readout to make it findable between trunks.
## Closer than this the model speaks for itself and the overlay stays out of the
## way.
const ON_SCREEN_DISTANCE := 15.0
## Keep the cue inside the part of the screen the HUD leaves free. The HUD pushes
## its real control sizes in through `set_safe_margins()` on every layout, so a
## tablet and a small phone both keep the chevron clear of the thumbs.
const SAFE_LEFT := 150.0
const SAFE_RIGHT := 250.0
const SAFE_TOP := 135.0
const SAFE_BOTTOM := 215.0

var safe_left := SAFE_LEFT
var safe_right := SAFE_RIGHT
var safe_top := SAFE_TOP
var safe_bottom := SAFE_BOTTOM

var _visible_target := false
var _on_screen := false
var _edge_position := Vector2.ZERO
var _direction := Vector2.UP
var _distance := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Called every frame by main.gd with the live camera and deer position.
func update_marker(camera: Camera3D, target: Vector3, show: bool) -> void:
	if camera == null or not show or not is_visible_in_tree():
		_hide()
		return
	var viewport_rect := get_viewport_rect()
	var screen := camera.unproject_position(target)
	var behind := camera.is_position_behind(target)
	_distance = camera.global_position.distance_to(target)
	if not behind and viewport_rect.has_point(screen):
		if _distance <= ON_SCREEN_DISTANCE:
			# Close enough to read: no overlay needed.
			_hide()
			return
		_on_screen = true
		_edge_position = screen
		_visible_target = true
		queue_redraw()
		return
	_on_screen = false
	var centre := viewport_rect.size * 0.5
	var to_target := screen - centre
	if behind:
		# unproject_position mirrors points behind the camera, so flip the cue.
		to_target = -to_target
	if to_target.length() < 1.0:
		to_target = Vector2(0, 1)
	_direction = to_target.normalized()
	var limit := viewport_rect.size * 0.5 - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var scaled := Vector2(
		_direction.x * limit.x / maxf(absf(_direction.x), 0.001),
		_direction.y * limit.y / maxf(absf(_direction.y), 0.001)
	)
	_edge_position = centre + scaled
	# A very small window can leave no room between the margins; fall back to the
	# centre line rather than inverting the clamp.
	var left_limit := minf(safe_left, viewport_rect.size.x * 0.5)
	var right_limit := maxf(viewport_rect.size.x - safe_right, viewport_rect.size.x * 0.5)
	var top_limit := minf(safe_top, viewport_rect.size.y * 0.5)
	var bottom_limit := maxf(viewport_rect.size.y - safe_bottom, viewport_rect.size.y * 0.5)
	_edge_position.x = clampf(_edge_position.x, left_limit, right_limit)
	_edge_position.y = clampf(_edge_position.y, top_limit, bottom_limit)
	_visible_target = true
	queue_redraw()


## Insets, in pixels, that the cue must stay inside: the HUD's own controls.
func set_safe_margins(left: float, right: float, top: float, bottom: float) -> void:
	safe_left = maxf(left, 0.0)
	safe_right = maxf(right, 0.0)
	safe_top = maxf(top, 0.0)
	safe_bottom = maxf(bottom, 0.0)


func _hide() -> void:
	if not _visible_target:
		return
	_visible_target = false
	queue_redraw()


func _draw() -> void:
	if not _visible_target:
		return
	var font := ThemeDB.fallback_font
	if _on_screen:
		# A diamond over the deer plus a range readout, deliberately small.
		var size := 7.0
		var diamond := PackedVector2Array([
			_edge_position + Vector2(0, -size),
			_edge_position + Vector2(size, 0),
			_edge_position + Vector2(0, size),
			_edge_position + Vector2(-size, 0),
		])
		draw_circle(_edge_position, size * 1.5, SHADOW_COLOR)
		draw_colored_polygon(diamond, COLOR)
		draw_string(font, _edge_position + Vector2(-14, size + 20), "%d m" % int(round(_distance)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR)
		return
	var tip := _edge_position + _direction * CHEVRON_LENGTH
	var side := Vector2(-_direction.y, _direction.x)
	var back := _edge_position - _direction * CHEVRON_LENGTH * 0.45
	var points := PackedVector2Array([
		tip,
		back + side * CHEVRON_WIDTH,
		back - side * CHEVRON_WIDTH,
	])
	# A soft dark halo keeps the chevron readable against bright canopy.
	draw_circle(_edge_position, CHEVRON_LENGTH * 1.15, SHADOW_COLOR)
	draw_colored_polygon(points, COLOR)
	var text := "%d m" % int(round(_distance))
	draw_string(font, _edge_position + Vector2(-14, CHEVRON_LENGTH + 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR)
