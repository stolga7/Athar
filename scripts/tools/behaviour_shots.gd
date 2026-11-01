extends Node
## Renders one frame of the real deer in each behaviour state, for review.
##
## Companion to capture_shots.gd: that tool shows the world, this one shows what
## the animal looks like while grazing, watching, fleeing and settling. It loads
## the actual main scene, sets the state on the real brain and rig, and writes
## what the camera sees. Development tool only; nothing here runs unless this
## scene is launched explicitly.
##
## Usage (needs a display; see TESTING.md, section 7):
##   DISPLAY=:99 godot --path . --rendering-driver vulkan res://scenes/tools/behaviour_shots.tscn
##
## Output goes to `artifacts/` in the project folder, which is git-ignored.
##
## The composition is staged (positions and camera), but the states, poses and
## animation are the project's own: the deer is the Phase 3 rig driven by
## deer_ai.gd's state names, not a separate mock-up.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DeerAI := preload("res://scripts/animals/deer_ai.gd")
const OUT_DIR := "res://artifacts"
const DT := 1.0 / 60.0
const WARMUP_FRAMES := 12

var _main: Node3D
var _shots: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	Engine.max_physics_steps_per_frame = 1
	await _settle(4)
	_main.set_physics_process(false)

	await _shot("GRAZING", 0.0, 4.0, "behaviour_01_grazing")
	await _shot("OBSERVING", 0.0, 3.0, "behaviour_02_watching")
	await _shot("ALERTED", 0.0, 2.0, "behaviour_03_alerted")
	await _shot("FLEEING", DeerAI.SPRINT_SPEED, 0.42, "behaviour_04_fleeing")
	await _shot("RETURNING", 1.05, 1.8, "behaviour_05_returning")
	await _shot("RESTING", 0.0, 3.0, "behaviour_06_resting")

	print("BEHAVIOUR_CAPTURE_DONE ", ", ".join(_shots))
	get_tree().quit(0)


## Points the camera at the deer from a few metres, poses the state, renders.
func _shot(state: String, speed: float, seconds: float, name: String) -> void:
	var hunter_position := Vector3(0, 0.1, 6.0)
	var hunter_yaw := 0.0
	_main.hunter.global_position = hunter_position
	_main.hunter.rotation.y = hunter_yaw
	_main.hunter.velocity = Vector3.ZERO
	_main.deer.global_position = Vector3(1.5, 0.1, -0.6)
	_main.deer.rotation.y = PI * 0.78
	_main.deer.velocity = Vector3.ZERO
	_main.deer_ai.state = state
	_main.deer_ai.speed = speed
	_main.deer_rig.set_state(state)
	for i in range(int(seconds / DT)):
		_main.hunter_rig.animate(DT, 0.0)
		_main.deer_rig.animate(DT, speed)
	_main.camera_rig.snap_to(hunter_position, hunter_yaw)
	_main.camera_rig.update_camera(DT, hunter_position, hunter_yaw)
	_main.camera_rig.update_camera(DT, hunter_position, hunter_yaw)
	_main.deer_marker.update_marker(_main.camera, _main.deer.global_position, true)
	_main.info_label.text = "STAMINA 100%%   •   FOREST REGION   •   DEER %s" % state
	_main.status_label.text = _status_for(state)
	await _settle(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	await _write(name, state)


func _status_for(state: String) -> String:
	match state:
		"GRAZING":
			return "The deer is grazing, head down and relaxed."
		"OBSERVING":
			return "Head up and listening: the deer is watching its surroundings."
		"ALERTED":
			return "It has noticed you — ears pricked, tail up, ready to run."
		"FLEEING":
			return "It bolted! Galloping flat out away from the hunter."
		"RETURNING":
			return "The danger passed; the deer is drifting back to its patch."
		"RESTING":
			return "Settled and resting, but still keeping an ear on the forest."
	return ""


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _write(name: String, state: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var err: int = image.save_png(path)
	if err == OK:
		_shots.append(name)
		print("SHOT_SAVED %s %dx%d state=%s" % [name, image.get_width(), image.get_height(), state])
	else:
		print("SHOT_FAILED %s err=%d" % [name, err])
