extends Node
## Renders the real game scene to PNG files for visual review.
##
## The look of a 3D game cannot be checked from a headless run, so this tool
## loads the actual main scene, poses it into a handful of representative
## situations, and writes what the camera sees. It is a development tool, not
## part of the game: nothing here runs unless this scene is launched explicitly.
##
## Usage (needs a display; see TESTING.md):
##   DISPLAY=:99 godot --path . --rendering-driver vulkan res://scenes/tools/capture_shots.tscn
##
## Output goes to `artifacts/` in the project folder, which is git-ignored.
##
## Gameplay is frozen before each shot (the scene's physics processing is turned
## off) and the actors are placed by hand, so a slow software renderer cannot let
## the deer wander out of frame while the screenshot is being taken.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUT_DIR := "res://artifacts"
const WARMUP_FRAMES := 12

var _main: Node3D
var _shots: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	# One physics step per frame keeps simulation time tied to frames, so the
	# staged poses below cannot drift between two runs.
	Engine.max_physics_steps_per_frame = 1
	await _settle(4)
	_main.set_physics_process(false)

	await _shot_spawn()
	_render_stats()
	await _shot_deer_close()
	await _shot_chase()
	await _shot_obstructed()
	await _shot_horizon()

	print("CAPTURE_DONE ", ", ".join(_shots))
	get_tree().quit(0)


## Places the hunter and the deer, then renders once.
func _stage(hunter_position: Vector3, hunter_yaw: float, deer_position: Vector3, deer_yaw: float, state: String, name: String) -> void:
	_main.hunter.global_position = hunter_position
	_main.hunter.rotation.y = hunter_yaw
	_main.hunter.velocity = Vector3.ZERO
	_main.deer.global_position = deer_position
	_main.deer.rotation.y = deer_yaw
	_main.deer.velocity = Vector3.ZERO
	_main.deer_ai.state = state
	_main.deer_rig.set_state(state)
	# A few animation steps so idle poses settle rather than showing frame zero.
	for i in range(20):
		_main.hunter_rig.animate(1.0 / 60.0, 0.0)
		_main.deer_rig.animate(1.0 / 60.0, 0.0)
	_main.camera_rig.snap_to(_main.hunter.global_position, _main.hunter.rotation.y)
	# Two camera updates settle the obstruction probe on the new position.
	_main.camera_rig.update_camera(1.0 / 60.0, _main.hunter.global_position, _main.hunter.rotation.y)
	_main.camera_rig.update_camera(1.0 / 60.0, _main.hunter.global_position, _main.hunter.rotation.y)
	# The HUD normally refreshes from main's physics step, which is paused here,
	# so bring the cue and the readouts in line with the staged state.
	_main.deer_marker.update_marker(_main.camera, _main.deer.global_position, _main.deer.visible)
	_main.info_label.text = "STAMINA 100%%   •   FOREST REGION   •   DEER %s" % state
	await _settle(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	await _write(name)


func _shot_spawn() -> void:
	await _stage(_main.hunter.global_position, 0.0, Vector3(4.5, 0.1, -5.0), 0.6, "GRAZING", "01_spawn")
	print("SHOT spawn: camera_distance=%.2f obstructed=%s" % [_main.camera_rig.distance, str(_main.camera_rig.obstructed)])


func _shot_deer_close() -> void:
	# The deer a few metres ahead and to the left, in its alert pose.
	await _stage(Vector3(0, 0.1, 4.0), 0.0, Vector3(1.8, 0.1, -1.4), PI + 0.5, "ALERTED", "02_deer_close")


func _shot_chase() -> void:
	# Deer running away and to the side, the way a real chase looks: with the
	# camera on the right shoulder the deer stays visible instead of hiding
	# behind the hunter's cloak.
	await _stage(Vector3(-2, 0.1, 6.0), -0.25, Vector3(2.6, 0.1, -2.4), PI + 0.3, "FLEEING", "03_chase")


## Puts a tree directly between the camera and the hunter, which is the bug the
## owner reported: the camera must pull in instead of filling the screen.
func _shot_obstructed() -> void:
	var trees: Array = _main.forest_info.get("positions", [])
	var best := Vector3.ZERO
	var best_distance := 1e9
	for candidate in trees:
		var d: float = Vector2(candidate.x, candidate.z).length()
		if d < best_distance:
			best_distance = d
			best = candidate
	var to_tree := (best - Vector3(0, 0, 7.0))
	to_tree.y = 0
	var away := to_tree.normalized()
	# Hunter stands 2.6 m beyond the trunk with his back to open ground, so the
	# trunk sits exactly between the camera and the hunter.
	var hunter_position := Vector3(best.x, 0.1, best.z) + away * 2.6
	var hunter_yaw := atan2(-away.x, -away.z)
	await _stage(hunter_position, hunter_yaw, Vector3(-14, 0.1, -6), 0.0, "GRAZING", "04_obstructed")
	print("SHOT obstructed: tree=%s camera_distance=%.2f clear=%.2f obstructed=%s" % [str(best), _main.camera_rig.distance, _main.camera_rig.clear_distance, str(_main.camera_rig.obstructed)])


func _shot_horizon() -> void:
	# Looking along the clearing edge: checks the treeline, fog and horizon.
	await _stage(Vector3(12, 0.1, 16), PI * 0.75, Vector3(-6, 0.1, -2), 0.0, "GRAZING", "05_horizon")


## Prints what the frame cost, which is the only performance evidence a software
## rasteriser can give: draw calls and triangles for the whole scene.
func _render_stats() -> void:
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objects: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("RENDER_STATS draw_calls=%d objects=%d primitives=%d" % [draws, objects, prims])
	print("SCENE_STATS nodes=%d trees=%d far_trees=%d tree_nodes=%d" % [
		_count_nodes(_main), int(_main.forest_info.get("count", 0)),
		int(_main.forest_info.get("far_count", 0)), int(_main.forest_info.get("node_count", 0))])


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _write(name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var err: int = image.save_png(path)
	if err == OK:
		_shots.append(name)
		print("SHOT_SAVED %s %dx%d" % [name, image.get_width(), image.get_height()])
	else:
		print("SHOT_FAILED %s err=%d" % [name, err])
