extends Node
## Renders the real scene at different hours and in different weather.
##
## The point is to see the living world: daylight, sunset, night, rain and fog,
## with the hunter and the deer in frame so readability can be judged. It loads
## the actual main scene, sets the clock and the weather on the real systems, and
## writes what the camera sees. Development tool only.
##
## Usage (needs a display; see TESTING.md, section 7):
##   DISPLAY=:99 godot --path . --rendering-driver vulkan res://scenes/tools/world_shots.tscn
##
## Output goes to `artifacts/` in the project folder, which is git-ignored.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DayCycle := preload("res://scripts/world/day_cycle.gd")
const Weather := preload("res://scripts/world/weather.gd")
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

	await _shot(0.50, Weather.CLEAR, "world_01_day")
	await _shot(0.755, Weather.CLEAR, "world_02_sunset")
	await _shot(0.02, Weather.CLEAR, "world_03_night")
	await _shot(0.52, Weather.RAIN, "world_04_rain")
	await _shot(0.34, Weather.FOG, "world_05_fog")

	print("WORLD_CAPTURE_DONE ", ", ".join(_shots))
	get_tree().quit(0)


## Sets the clock and the weather, places the actors, renders one frame.
func _shot(time_of_day: float, condition: String, name: String) -> void:
	var hunter_position := Vector3(2.0, 0.1, 8.0)
	_main.hunter.global_position = hunter_position
	_main.hunter.rotation.y = 0.0
	_main.hunter.velocity = Vector3.ZERO
	_main.deer.global_position = Vector3(3.4, 0.1, 1.2)
	_main.deer.rotation.y = PI * 0.8
	_main.deer.velocity = Vector3.ZERO
	_main.deer_ai.state = "GRAZING"
	_main.deer_rig.set_state("GRAZING")

	var world = _main.living_world
	world.day.set_time(time_of_day)
	world.weather.force_state(condition)
	world.update(0.0, hunter_position)
	world.apply()
	_main._apply_wildlife_environment()

	for i in range(20):
		_main.hunter_rig.animate(DT, 0.0)
		_main.deer_rig.animate(DT, 0.0)
	_main.camera_rig.snap_to(hunter_position, 0.0)
	_main.camera_rig.update_camera(DT, hunter_position, 0.0)
	_main.camera_rig.update_camera(DT, hunter_position, 0.0)
	_main.deer_marker.update_marker(_main.camera, _main.deer.global_position, true)
	_main.info_label.text = "STAMINA 100%%   •   %s   •   DEER GRAZING" % world.hud_text()
	_main.status_label.text = _caption(time_of_day, condition)
	await _settle(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	await _write(name, time_of_day, condition)


func _caption(time_of_day: float, condition: String) -> String:
	var hour := "day"
	if time_of_day < 0.2:
		hour = "night"
	elif time_of_day < 0.3:
		hour = "dawn"
	elif time_of_day >= 0.73 and time_of_day < 0.82:
		hour = "sunset"
	match condition:
		Weather.RAIN:
			return "Rain: the forest darkens, the ground shines and the deer hears less."
		Weather.FOG:
			return "Fog: distance dissolves, but the deer is still visible inside 20 m."
		Weather.CLOUDY:
			return "Overcast: flat light and a heavier sky."
	if hour == "night":
		return "Night: moonlight, raised exposure and a cool ambient keep the hunt readable."
	if hour == "sunset":
		return "Sunset: warm low light, long shadows and a violet sky."
	if hour == "dawn":
		return "Dawn: cold mist and a low sun coming up behind the treeline."
	return "Midday: the approved daylight look, unchanged."


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _write(name: String, time_of_day: float, condition: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var err: int = image.save_png(path)
	if err == OK:
		_shots.append(name)
		print("SHOT_SAVED %s %dx%d time=%.3f weather=%s" % [name, image.get_width(), image.get_height(), time_of_day, condition])
	else:
		print("SHOT_FAILED %s err=%d" % [name, err])
