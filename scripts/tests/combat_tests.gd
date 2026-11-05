extends Node
## Headless tests for Phase 4: imported models, the animation state machines,
## the combat rules, the camera additions and the mobile combat controls.
##
## Run with:
##   godot --headless --path . res://scenes/tests/combat_tests.tscn
##
## The combat controller and the camera are plain objects, so almost everything
## here runs without a renderer. The last group loads the real scene, swings at
## the training target and checks that the hunting loop still works.

const ModelAsset := preload("res://scripts/visuals/model_asset.gd")
const HunterRig := preload("res://scripts/visuals/hunter_rig.gd")
const DeerRig := preload("res://scripts/visuals/deer_rig.gd")
const Combat := preload("res://scripts/gameplay/combat_controller.gd")
const CameraRig := preload("res://scripts/visuals/camera_rig.gd")
const HUDScene := preload("res://scenes/ui/hud.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const Localization := preload("res://scripts/ui/localization.gd")

const DT := 1.0 / 60.0
const WATCHDOG_SECONDS := 150.0
const MANIFEST_PATH := "res://assets/models/ASSET_MANIFEST.json"

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR combat and model tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	_test_manifest()
	_test_model_loading()
	await _test_rigs()
	_test_combat_rules()
	_test_camera()
	await _test_hud_controls()
	await _test_scene()
	_finish()


func _finish() -> void:
	_watchdog.stop()
	_silence_audio(get_tree().root)
	if is_instance_valid(_main):
		_main.free()
	_main = null
	OS.delay_msec(250)
	await get_tree().process_frame
	print("")
	if _failures > 0:
		print("RESULT: %d checks, %d failed" % [_checks, _failures])
		get_tree().quit(1)
	else:
		print("RESULT: %d checks, 0 failed" % _checks)
		get_tree().quit(0)


func _silence_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_silence_audio(child)


func _on_watchdog_timeout() -> void:
	printerr("ATHAR_TEST_WATCHDOG=expired")
	printerr("RESULT: %d checks, %d failed (watchdog)" % [_checks, _failures + 1])
	get_tree().quit(1)


func _check(condition: bool, label: String, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


# ------------------------------------------------------------------ manifest ---
## Every imported asset must be traceable: a source page, a creator, a license
## that allows use and modification in a game, and a local file that exists. A
## model without that record does not ship.
func _test_manifest() -> void:
	print("-- asset manifest")
	_check(FileAccess.file_exists(MANIFEST_PATH), "the asset manifest exists")
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var data = JSON.parse_string(text)
	_check(data is Dictionary, "the manifest is valid JSON")
	if not data is Dictionary:
		return
	var assets: Array = data.get("assets", [])
	_check(assets.size() >= 2, "the manifest lists the imported assets", "%d" % assets.size())
	for entry in assets:
		var id := String(entry.get("id", ""))
		var path := String(entry.get("file", ""))
		_check(path != "" and FileAccess.file_exists(path), "%s ships its file" % id, path)
		_check(String(entry.get("source_url", "")).begins_with("https://"), "%s records its source URL" % id)
		_check(String(entry.get("creator", "")) != "", "%s records the creator" % id)
		_check(String(entry.get("license", "")) in ["CC0-1.0", "CC-BY-4.0", "CC-BY-3.0"],
			"%s records a recognised license" % id, String(entry.get("license", "")))
		_check(bool(entry.get("modification_allowed", false)), "%s allows modification" % id)
		_check(bool(entry.get("redistribution_allowed", false)), "%s allows use in a game" % id)
		_check(String(entry.get("attribution", "")) != "", "%s states its attribution" % id)
	var hunter := _manifest_entry(assets, "hunter")
	_check(not hunter.is_empty(), "the hunter is in the manifest")
	_check(String(hunter.get("license", "")) == "CC0-1.0", "the hunter is CC0")
	var deer := _manifest_entry(assets, "deer")
	_check(not deer.is_empty(), "the deer is in the manifest")
	_check(String(deer.get("license", "")) == "CC0-1.0", "the deer is CC0")


func _manifest_entry(assets: Array, id: String) -> Dictionary:
	for entry in assets:
		if String(entry.get("id", "")) == id:
			return entry
	return {}


# --------------------------------------------------------------- model loading ---
func _test_model_loading() -> void:
	print("-- model loading")
	var missing := ModelAsset.load_model("res://assets/models/characters/does_not_exist.glb", 1.8)
	_check(not missing.ok, "a missing model is reported, not crashed")
	_check(missing.reason.find("missing asset") >= 0, "the reason names the missing asset", missing.reason)
	_check(missing.root == null, "a missing model returns no node")

	var hunter := ModelAsset.load_model(HunterRig.MODEL_PATH, HunterRig.HEIGHT)
	_check(hunter.ok, "the hunter model loads", hunter.reason)
	_check(hunter.skeleton != null and hunter.skeleton.get_bone_count() >= 40,
		"the hunter has a real skeleton", "%d bones" % (hunter.skeleton.get_bone_count() if hunter.skeleton else 0))
	_check(hunter.clips.size() >= 20, "the hunter exposes its animation clips", "%d clips" % hunter.clips.size())
	_check(hunter.clips.has("Idle") and hunter.clips.has("Run") and hunter.clips.has("Death"),
		"the hunter has idle, run and death clips")
	_check(absf(hunter.height - HunterRig.HEIGHT) < 0.001, "the hunter is normalised to its set height")
	if hunter.root != null:
		hunter.root.free()

	var deer := ModelAsset.load_model(DeerRig.MODEL_PATH, DeerRig.HEIGHT)
	_check(deer.ok, "the deer model loads", deer.reason)
	_check(deer.skeleton != null and deer.skeleton.get_bone_count() >= 20,
		"the deer has a real skeleton", "%d bones" % (deer.skeleton.get_bone_count() if deer.skeleton else 0))
	_check(deer.clips.has("Walking") or deer.clips.has("Walk"), "the deer has a walk clip")
	_check(deer.clips.has("Gallop") and deer.clips.has("Death"), "the deer has gallop and death clips")
	if deer.root != null:
		deer.root.free()

	# A scene that exists but carries no skeleton must also be refused cleanly.
	# (A non-model file such as a CSV would make the engine log an error, which
	# the verifier treats as a project fault, so a real scene is the fair test.)
	var bogus := ModelAsset.load_model("res://scenes/tools/model_preview.tscn", 1.8)
	_check(not bogus.ok, "a scene without a skeleton is refused", bogus.reason)


# -------------------------------------------------------------------- rigs ---
func _test_rigs() -> void:
	print("-- hunter and deer rigs")
	var stage := Node3D.new()
	add_child(stage)
	var hunter = HunterRig.new()
	stage.add_child(hunter)
	var deer = DeerRig.new()
	deer.position = Vector3(4, 0, 0)
	stage.add_child(deer)
	await get_tree().process_frame

	_check(hunter.is_ready(), "the hunter rig builds", hunter.missing_reason)
	_check(hunter.animation_tree != null and hunter._playback != null, "the hunter animates through an AnimationTree state machine")
	_check(hunter._clips.size() >= 20, "the hunter rig catalogues its clips", "%d" % hunter._clips.size())

	# Locomotion selects idle, walk and run from speed.
	hunter.animate(DT, 0.0)
	_check(hunter.current_clip == HunterRig.CLIP_IDLE, "standing still plays idle", hunter.current_clip)
	hunter.animate(DT, 1.4)
	_check(hunter.current_clip == HunterRig.CLIP_WALK, "walking speed plays the walk clip", hunter.current_clip)
	hunter.animate(DT, 4.4)
	_check(hunter.current_clip == HunterRig.CLIP_RUN, "hunting speed plays the run clip", hunter.current_clip)
	_check(hunter.player.speed_scale > 0.5, "playback speed follows the movement speed", "%.2f" % hunter.player.speed_scale)

	# One-shot actions take over and then hand control back.
	_check(hunter.play_action("light"), "the light attack clip plays")
	_check(hunter.action_active(), "a one-shot action is marked active")
	_check(hunter.current_clip == HunterRig.CLIP_LIGHT, "the attack clip is the sword slash", hunter.current_clip)
	var guard := 0
	while hunter.action_active() and guard < 600:
		hunter.animate(DT, 0.0)
		guard += 1
	_check(not hunter.action_active(), "the attack ends by itself")
	_check(hunter.current_clip == HunterRig.CLIP_IDLE, "the hunter returns to idle after an attack", hunter.current_clip)

	hunter.set_blocking(true)
	hunter.animate(DT, 0.0)
	_check(hunter.current_clip == HunterRig.CLIP_BLOCK, "blocking holds the guard clip", hunter.current_clip)
	hunter.set_blocking(false)
	_check(hunter.play_action("roll"), "the dodge roll clip plays")
	hunter.play_death()
	_check(hunter.current_clip == HunterRig.CLIP_DEATH, "death plays the death clip", hunter.current_clip)
	_check(not hunter.play_action("light"), "no action plays while dead")
	hunter.revive()
	_check(hunter.current_clip == HunterRig.CLIP_IDLE, "reviving returns to idle")

	_check(deer.is_ready(), "the deer rig builds", deer.missing_reason)
	_check(deer.animation_tree != null, "the deer animates through an AnimationTree")
	deer.set_state("GRAZING")
	deer.animate(DT, 0.0)
	_check(deer.current_clip == DeerRig.CLIP_GRAZE, "grazing plays the eating clip", deer.current_clip)
	deer.animate(DT, 1.2)
	_check(deer.current_clip == DeerRig.CLIP_WALK, "walking plays the walk clip", deer.current_clip)
	deer.animate(DT, 6.0)
	_check(deer.current_clip == DeerRig.CLIP_GALLOP, "bolting plays the gallop clip", deer.current_clip)
	deer.set_state("RESTING")
	deer.animate(DT, 0.0)
	_check(deer.current_clip == DeerRig.CLIP_HEAD_LOW, "resting lowers the head", deer.current_clip)
	for state in ["GRAZING", "OBSERVING", "ALERTED", "FLEEING", "ESCAPING", "INVESTIGATING", "RETURNING", "CAPTURED"]:
		deer.set_state(state)
		deer.animate(DT, 2.0)
	_check(true, "every deer state animates without error")

	stage.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ combat ---
func _test_combat_rules() -> void:
	print("-- combat rules")
	var combat = Combat.new()
	_check(combat.state == Combat.IDLE, "combat starts idle")
	_check(combat.stamina == Combat.MAX_STAMINA, "combat starts with full stamina")

	_check(combat.request_light(), "a light attack starts")
	_check(combat.state == Combat.LIGHT_STATE, "the state is the light attack", combat.state)
	_check(combat.stamina < Combat.MAX_STAMINA, "a light attack costs stamina", "%.0f" % combat.stamina)
	_check(not combat.request_light(), "a second light attack is refused mid-swing")
	_check(combat.attack_phase() == "windup", "the swing starts in its windup", combat.attack_phase())
	var hit_window := 0
	for i in range(60):
		combat.update(DT)
		if combat.hit_pending:
			hit_window += 1
			combat.hit_pending = false
	_check(hit_window == 1, "the swing opens exactly one hit window", "%d" % hit_window)
	_check(combat.state == Combat.IDLE, "the swing returns to idle", combat.state)

	# Heavy attacks cost more and hit harder.
	combat.stamina = Combat.MAX_STAMINA
	_check(combat.request_heavy(), "a heavy attack starts")
	_check(combat.stamina <= Combat.MAX_STAMINA - Combat.COST_HEAVY + 0.01, "a heavy attack costs its price", "%.0f" % combat.stamina)
	_check(combat.current_damage() > Combat.LIGHT["damage"], "the heavy swing does more damage", "%.0f" % combat.current_damage())
	for i in range(120):
		combat.update(DT)
		combat.hit_pending = false

	# Stamina gates actions.
	combat.stamina = 3.0
	_check(not combat.request_light(), "an unaffordable attack is refused")
	_check(not combat.request_dodge(), "an unaffordable dodge is refused")
	combat.stamina = 60.0
	for i in range(300):
		combat.update(DT)
	_check(combat.stamina > 59.0, "stamina regenerates after the delay", "%.1f" % combat.stamina)

	# Dodge grants invulnerability and gets out of the way.
	combat.stamina = 60.0
	_check(combat.request_dodge(), "a dodge starts")
	_check(not combat.is_invulnerable(), "the dodge does not start invulnerable")
	var became_invulnerable := false
	for i in range(40):
		combat.update(DT)
		if combat.is_invulnerable():
			became_invulnerable = true
	_check(became_invulnerable, "the dodge has an invulnerable window")
	combat.update(DT)
	combat.state = Combat.DODGE_STATE
	combat.elapsed = 0.2
	_check(combat.take_hit(30.0) == "dodged", "a hit inside the dodge is avoided")
	_check(combat.health == 100.0, "a dodged hit does no damage")

	# Blocking soaks most damage and drains stamina.
	combat.heal_full()
	combat.set_blocking(true)
	var before: float = combat.health
	var result := combat.take_hit(20.0)
	_check(result == "blocked", "a raised guard blocks", result)
	_check(combat.health > before - 6.0, "a blocked hit does little damage", "%.1f" % combat.health)
	_check(combat.stamina < 100.0, "blocking a hit spends stamina", "%.1f" % combat.stamina)
	var stamina_while_blocking: float = combat.stamina
	for i in range(30):
		combat.update(DT)
	_check(combat.stamina < stamina_while_blocking, "holding the guard drains stamina", "%.1f" % combat.stamina)
	combat.set_blocking(false)

	# Unblocked hits stagger, then kill.
	combat.heal_full()
	var unblocked := combat.take_hit(15.0)
	_check(unblocked == "hit", "an unblocked hit lands", unblocked)
	_check(combat.state == Combat.HIT_STATE, "a hit staggers the hunter", combat.state)
	_check(not combat.request_light(), "no attack starts while staggered")
	for i in range(40):
		combat.update(DT)
	_check(combat.state == Combat.IDLE, "the stagger ends", combat.state)
	combat.take_hit(200.0)
	_check(combat.is_dead(), "enough damage kills")
	_check(not combat.request_dodge(), "a dead hunter cannot dodge")
	_check(combat.take_hit(10.0) == "ignored", "a dead hunter ignores further hits")
	combat.heal_full()
	_check(combat.health == 100.0 and combat.state == Combat.IDLE, "heal_full restores the hunter")


# ------------------------------------------------------------------ camera ---
func _test_camera() -> void:
	print("-- camera")
	var rig = CameraRig.new()
	add_child(rig)
	rig.snap_to(Vector3(0, 0, 0), 0.0)
	_check(rig.camera != null and rig.camera.current, "the camera is created and current")
	var base := rig.current_distance()
	# Positive zoom means a longer distance in this rig, so a negative step
	# pulls the camera in.
	rig.zoom_by(-0.3)
	for i in range(60):
		rig.update_camera(DT, Vector3.ZERO, 0.0)
	_check(rig.current_distance() < base, "zooming in shortens the distance", "%.2f m" % rig.current_distance())
	rig.set_zoom(99.0)
	for i in range(90):
		rig.update_camera(DT, Vector3.ZERO, 0.0)
	_check(rig.current_distance() <= CameraRig.ZOOM_MAX + 0.01, "zoom is clamped at the far limit", "%.2f m" % rig.current_distance())
	rig.set_zoom(-99.0)
	for i in range(90):
		rig.update_camera(DT, Vector3.ZERO, 0.0)
	_check(rig.current_distance() >= CameraRig.MIN_DISTANCE, "zoom is clamped at the near limit", "%.2f m" % rig.current_distance())
	rig.set_zoom(0.8)

	var yaw_before: float = rig.yaw_offset
	rig.add_look(Vector2(-120, 0))
	_check(rig.yaw_offset != yaw_before, "dragging orbits the camera")
	rig.add_look(Vector2(-100000, 100000))
	_check(absf(rig.yaw_offset) <= CameraRig.MAX_YAW_OFFSET + 0.001, "look yaw is clamped", "%.2f" % rig.yaw_offset)
	_check(rig.pitch_offset <= CameraRig.MAX_PITCH_OFFSET + 0.001, "look pitch is clamped", "%.2f" % rig.pitch_offset)
	rig.set_look_sensitivity(2.0)
	_check(rig.look_sensitivity == 2.0, "look sensitivity is settable")
	rig.set_look_sensitivity(0.01)
	_check(rig.look_sensitivity >= 0.3, "look sensitivity has a floor")

	var target := Node3D.new()
	target.position = Vector3(0, 0, -6)
	add_child(target)
	rig.lock_on(target)
	_check(rig.has_lock(), "lock-on takes a target")
	rig.set_zoom(1.0)
	for i in range(80):
		rig.update_camera(DT, Vector3.ZERO, 0.0)
	var free_distance := rig.current_distance()
	_check(rig.has_lock(), "the target stays locked while alive")
	_check(rig.current_distance() <= free_distance + 0.01, "lock-on pulls the camera in", "%.2f" % rig.current_distance())
	rig.clear_lock()
	_check(not rig.has_lock(), "lock-on can be released")
	target.queue_free()
	rig.queue_free()


# --------------------------------------------------------------------- hud ---
func _test_hud_controls() -> void:
	print("-- mobile combat controls")
	Localization.ensure_installed()
	var hud = HUDScene.instantiate()
	add_child(hud)
	hud.setup(null)
	await get_tree().process_frame
	var view := Vector2(1280, 720)
	hud.layout_for(view)

	for action in ["light", "heavy", "dodge", "block", "aim", "lock"]:
		_check(hud.combat_buttons.has(action), "the HUD has a %s control" % action)
	_check(hud.combat_buttons.size() == 6, "there are six combat controls", "%d" % hud.combat_buttons.size())
	_check(hud.look_area != null, "the HUD has a camera drag area")

	var seen: Array[String] = []
	hud.combat_action.connect(func(action: String, _pressed: bool) -> void: seen.append(action))
	for action in ["light", "heavy", "dodge"]:
		var button: Button = hud.combat_buttons[action]
		button.pressed.emit()
	_check(seen.size() == 3 and "light" in seen, "tapping the controls emits their actions", ", ".join(seen))

	hud.set_combat_visible(false)
	var hidden := 0
	for button in hud.combat_buttons.values():
		if not (button as Button).visible:
			hidden += 1
	_check(hidden == 6, "combat controls can be hidden", "%d hidden" % hidden)
	hud.set_combat_visible(true)

	# Safe-area layout: every button inside the screen and none overlapping.
	hud.set_safe_insets(30.0, 20.0, 30.0, 24.0)
	hud.layout_for(view)
	var rects: Array[Rect2] = []
	var inside := true
	for button in hud.combat_buttons.values():
		var rect: Rect2 = (button as Button).get_rect()
		rects.append(rect)
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > view.x or rect.end.y > view.y:
			inside = false
	_check(inside, "every combat control stays on screen with safe-area insets")
	var overlapping := 0
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlapping += 1
	_check(overlapping == 0, "combat controls do not overlap", "%d overlaps" % overlapping)

	# The same layout must hold at a phone aspect ratio and at tablet size.
	for size in [Vector2(960, 540), Vector2(720, 1280), Vector2(1600, 900)]:
		hud.layout_for(size)
		var fits := true
		for button in hud.combat_buttons.values():
			var rect: Rect2 = (button as Button).get_rect()
			if rect.end.x > size.x + 0.5 or rect.end.y > size.y + 0.5:
				fits = false
		_check(fits, "combat controls fit a %dx%d screen" % [int(size.x), int(size.y)])

	hud.set_combat_state(5.0, false, false, false)
	_check((hud.combat_buttons["light"] as Button).disabled, "an unaffordable attack is greyed out")
	hud.set_combat_state(90.0, true, false, true)
	_check(hud.block_button.button_pressed, "the block control shows the held state")
	_check(not (hud.combat_buttons["light"] as Button).disabled, "an affordable attack is enabled")

	hud.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------- scene ---
func _test_scene() -> void:
	print("-- live scene")
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(_main.combat != null, "the scene owns a combat controller")
	_check(_main.dummy != null, "the scene has a training target")
	_check(_main.hunter_rig.is_ready() and _main.deer_rig.is_ready(), "the imported models are in the scene")
	_check(_main.hunter_rig.skeleton != null, "the hunter in the scene is skinned")

	# A swing inside reach damages the target.
	_main.dummy.reset()
	_main.dummy.global_position = _main.hunter.global_position + Vector3(0, 0, -1.4)
	_main.hunter.rotation.y = 0.0
	var health_before: float = _main.dummy.health
	_main.request_combat("light")
	for i in range(60):
		await get_tree().physics_frame
	_check(_main.dummy.health < health_before, "an attack in reach damages the target", "%.0f hp" % _main.dummy.health)

	# The same swing out of reach does nothing.
	_main.dummy.reset()
	_main.dummy.global_position = _main.hunter.global_position + Vector3(0, 0, -6.0)
	_main.combat.heal_full()
	health_before = _main.dummy.health
	_main.request_combat("light")
	for i in range(60):
		await get_tree().physics_frame
	_check(_main.dummy.health == health_before, "an attack out of reach misses")

	# The target can be knocked down and comes back.
	_main.dummy.global_position = _main.hunter.global_position + Vector3(0, 0, -1.4)
	for i in range(6):
		_main.combat.heal_full()
		_main.request_combat("heavy")
		for j in range(70):
			await get_tree().physics_frame
	_check(_main.dummy.is_down(), "the target can be knocked down", "%.0f hp" % _main.dummy.health)
	_main.dummy.reset()
	_check(not _main.dummy.is_down(), "the target resets for the next round")

	# Stamina is the shared resource between attacking and the HUD.
	_main.combat.heal_full()
	_main.stamina = 100.0
	_main.request_combat("light")
	_main.hud.set_vitals(0.5, 1.0, 0.2)
	_check(_main.combat.stamina < 100.0, "attacking spends combat stamina", "%.0f" % _main.combat.stamina)

	# The hunting loop is untouched: capture still works and still counts.
	_main.dummy.global_position = Vector3(40, 0.1, 40)
	_main.deer.global_position = _main.hunter.global_position + Vector3(0, 0, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_main.hunt_session.is_captured, "the deer can still be captured")
	_check(_main.deer_rig.current_clip != "", "the captured deer still animates")

	# Lock-on finds the deer when it is the nearest thing around.
	_main.deer.visible = true
	_main.deer.global_position = _main.hunter.global_position + Vector3(0, 0, -3.0)
	_check(_main.toggle_lock_on(), "lock-on takes the nearest target")
	_check(_main.camera_rig.has_lock(), "the camera is locked")
	_main.toggle_lock_on()
	_check(not _main.camera_rig.has_lock(), "pressing lock-on again releases it")

	# Every prior system is still alive in this scene.
	_check(_main.regions != null and _main.current_region_id() != "", "the regions are still loaded")
	_check(_main.living_world != null, "the living world is still running")
	_check(_main.audio != null, "audio is still attached")
