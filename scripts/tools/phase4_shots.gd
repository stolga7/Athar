extends Node
## Phase 4 screenshot tool: renders the real game with the imported models.
##
## Usage (needs a display):
##   DISPLAY=:99 godot --path . --rendering-driver opengl3 \
##       res://scenes/tools/phase4_shots.tscn
##
## Output goes to `artifacts/` (git-ignored). Every shot is a real frame of the
## real scene: the tool stages positions, plays a specific animation and then
## saves the viewport, so the owner can check the hunter and the deer from
## several angles, in combat and in the forest.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUT_DIR := "res://artifacts"
const WARMUP_FRAMES := 14

var _main: Node3D
var _shots: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	Engine.max_physics_steps_per_frame = 1
	await _settle(4)
	# Leave the title screen so the HUD is the real in-game one.
	_main.start_game()
	await _settle(2)
	_main.set_physics_process(false)
	_main.hunt_session.try_capture(999.0)

	await _shot("01_hunter_front", Vector3(0.6, 0.1, 7.6), 0.0, "Idle", 0.0, 165.0)
	await _shot("02_hunter_side", Vector3(0.6, 0.1, 7.6), 0.0, "Idle", 0.0, 95.0)
	await _shot("03_hunter_run", Vector3(0.6, 0.1, 7.6), 0.0, "Run", 4.6, 200.0)
	await _shot("04_hunter_attack", Vector3(0.6, 0.1, 7.6), 0.0, "Sword_Slash", 0.0, 210.0)
	await _shot("05_hunter_block", Vector3(0.6, 0.1, 7.6), 0.0, "Idle_Sword", 0.0, 190.0)
	await _deer_shots()
	await _combat_shot()
	await _hud_shot()
	await _forest_shot()

	print("CAPTURE_DONE ", ", ".join(_shots))
	get_tree().quit(0)


func _deer_shots() -> void:
	for entry in [
		{"name": "06_deer_grazing", "clip": "Eating", "yaw": 120.0},
		{"name": "07_deer_alert", "clip": "Idle_2", "yaw": 60.0},
		{"name": "08_deer_gallop", "clip": "Gallop", "yaw": 300.0},
	]:
		await _deer_shot(String(entry["name"]), String(entry["clip"]), float(entry["yaw"]))


func _deer_shot(name: String, clip: String, yaw: float) -> void:
	var deer_position := Vector3(1.4, 0.1, 3.2)
	_main.deer.visible = true
	_main.deer.global_position = deer_position
	_main.deer.rotation.y = 0.0
	_main.hunter.global_position = Vector3(-1.2, 0.1, 7.4)
	_main.hunter.rotation.y = 0.0
	if _main.deer_rig.player != null:
		_main.deer_rig.player.speed_scale = 0.35
	_main.deer_rig._play(clip)
	for i in range(14):
		_main.hunter_rig.animate(1.0 / 60.0, 0.0)
	_main.camera_rig.clear_lock()
	_main.camera_rig.snap_to(_main.hunter.global_position, _main.hunter.rotation.y)
	_main.camera_rig.yaw_offset = 0.0
	_main.camera_rig.set_zoom(0.62)
	var focus := deer_position + Vector3(0, 1.0, 0)
	var cam: Camera3D = _main.camera
	cam.global_position = focus + Vector3(sin(deg_to_rad(yaw)), 0.22, cos(deg_to_rad(yaw))).normalized() * 4.6
	cam.look_at(focus, Vector3.UP)
	await _settle(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	await _write(name)
	_main.camera_rig.set_zoom(1.0)


func _shot(name: String, hunter_position: Vector3, yaw: float, clip: String, speed: float, camera_yaw: float) -> void:
	_main.hunter.global_position = hunter_position
	_main.hunter.rotation.y = yaw
	_main.hunter.velocity = Vector3.ZERO
	_main.deer.visible = false
	if _main.hunter_rig.player != null:
		_main.hunter_rig.player.speed_scale = 1.0
	_main.hunter_rig._play(clip)
	for i in range(16):
		_main.hunter_rig.animate(1.0 / 60.0, speed)
	_main.camera_rig.clear_lock()
	_main.camera_rig.snap_to(_main.hunter.global_position, _main.hunter.rotation.y)
	_main.camera_rig.yaw_offset = 0.0
	var focus := hunter_position + Vector3(0, 1.05, 0)
	var cam: Camera3D = _main.camera
	cam.global_position = focus + Vector3(sin(deg_to_rad(camera_yaw)), 0.18, cos(deg_to_rad(camera_yaw))).normalized() * 3.4
	cam.look_at(focus, Vector3.UP)
	await _settle(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	await _write(name)


func _combat_shot() -> void:
	_main.deer.visible = false
	_main.dummy.reset()
	_main.dummy.global_position = Vector3(0.0, 0.1, 2.4)
	_main.hunter.global_position = Vector3(0, 0.1, 5.0)
	_main.hunter.rotation.y = 0.0
	_main.combat.stamina = 42.0
	_main.combat.request_heavy()
	_main.hunter_rig.play_action("heavy")
	for i in range(10):
		_main.combat.update(1.0 / 60.0)
		_main.hunter_rig.animate(1.0 / 60.0, 0.0)
	_main.hud.set_vitals(0.42, 0.7, 0.35)
	_main.hud.set_combat_state(42.0, false, false, true)
	# A side view of the swing, with the camera worked by the normal rig (lock-on
	# released) so the shot shows the same framing a player sees.
	_main.camera_rig.clear_lock()
	_main.camera_rig.snap_to(_main.hunter.global_position, _main.hunter.rotation.y)
	_main.camera_rig.yaw_offset = -0.95
	_main.camera_rig.set_zoom(0.72)
	for i in range(8):
		_main.camera_rig.update_camera(1.0 / 60.0, _main.hunter.global_position, _main.hunter.rotation.y)
	_main.hud.set_combat_state(42.0, false, false, false)
	await _settle(WARMUP_FRAMES)
	await RenderingServer.frame_post_draw
	await _write("09_combat_target")
	_main.camera_rig.yaw_offset = 0.0
	_main.camera_rig.set_zoom(1.0)


func _hud_shot() -> void:
	# The mobile control layout with phone-sized safe-area insets. The layout is
	# computed in the project's own 1280x720 viewport space; the window size only
	# scales it, so asking for a different size here would push the buttons off
	# the canvas (which is exactly how the first attempt failed).
	var view := _main.get_viewport().get_visible_rect().size
	_main.hud.set_safe_insets(26.0, 16.0, 26.0, 20.0)
	_main.hud.layout_for(view)
	_main.hud.set_combat_state(78.0, true, false, false)
	_main.camera_rig.clear_lock()
	_main.hunter.global_position = Vector3(0, 0.1, 7.0)
	_main.hunter.rotation.y = 0.0
	_main.camera_rig.snap_to(_main.hunter.global_position, 0.0)
	await _settle(WARMUP_FRAMES + 6)
	await RenderingServer.frame_post_draw
	await _write("10_mobile_controls")
	_main.hud.set_safe_insets(0.0, 0.0, 0.0, 0.0)
	_main.hud.layout_for(view)


func _forest_shot() -> void:
	_main.deer.visible = true
	_main.deer.global_position = Vector3(6.5, 0.1, -4.0)
	_main.deer.rotation.y = 2.2
	_main.deer_rig.set_state("GRAZING")
	_main.deer_rig.animate(1.0 / 60.0, 0.0)
	_main.hunter.global_position = Vector3(0, 0.1, 7.0)
	_main.hunter.rotation.y = 0.35
	_main.hunter_rig._play("Idle")
	_main.camera_rig.clear_lock()
	_main.camera_rig.snap_to(_main.hunter.global_position, _main.hunter.rotation.y)
	for i in range(4):
		_main.camera_rig.update_camera(1.0 / 60.0, _main.hunter.global_position, _main.hunter.rotation.y)
	await _settle(WARMUP_FRAMES + 10)
	await RenderingServer.frame_post_draw
	await _write("11_forest_gameplay")


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _write(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name]))
	_shots.append(name)
	print("SHOT %s" % name)
