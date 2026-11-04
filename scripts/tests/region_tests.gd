extends Node
## Headless tests for Phase 3.6: the ten regions, loading one at a time, travel
## between them, the player state that must survive a transition, seed
## determinism, and what happens when a region is missing or malformed.
##
## Run with:
##   godot --headless --path . res://scenes/tests/region_tests.tscn
##
## Most of this drives `region_definition`, `region_builder` and `region_manager`
## directly: they are data and plain nodes, so no renderer is needed. The last
## groups load the real scene and travel with it, which is the only way to prove
## the hunter, the hunt session and the HUD actually survive.

const RegionDefinition := preload("res://scripts/world/region_definition.gd")
const RegionBuilder := preload("res://scripts/world/region_builder.gd")
const RegionManager := preload("res://scripts/world/region_manager.gd")
const LivingWorld := preload("res://scripts/world/living_world.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const REGION_MENU_SCENE := preload("res://scenes/ui/region_menu.tscn")
const Localization := preload("res://scripts/ui/localization.gd")

const CSV_PATH := "res://localization/ui_strings.csv"
const WATCHDOG_SECONDS := 150.0
## A region must stay cheap enough for a phone: one ground, one woodland, one
## landmark. These ceilings are the shape of that promise, not a guess.
const MAX_NODES := 60
const MAX_MESH_INSTANCES := 40
const MAX_MATERIALS := 12
const SEED := 20261104

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR world region tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	_test_definitions()
	_test_translation_coverage()
	_test_identity()
	await _test_loading()
	await _test_determinism()
	_test_missing_resources()
	await _test_scene()
	await _test_region_menu()
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
	printerr("RESULT: %d checks, %d failed (watchdog expired after %.0f s)" % [_checks, _failures + 1, WATCHDOG_SECONDS])
	get_tree().quit(1)


func _check(condition: bool, label: String, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


# ---------------------------------------------------------------- definitions ---
func _test_definitions() -> void:
	print("-- region data")
	var all := RegionDefinition.all()
	_check(all.size() == 10, "ten regions are defined", "%d" % all.size())
	_check(RegionDefinition.count() == all.size(), "the count agrees with the table")
	var ids := RegionDefinition.ids()
	for expected in ["desert", "silver_forest", "frozen_highlands", "ember_lands", "ancient_ruins",
			"mirage_oasis", "crystal_caves", "reflection_swamp", "sky_cliffs", "void_realm"]:
		_check(expected in ids, "the brief's region %s exists" % expected)
	_check(RegionDefinition.is_valid(RegionManager.DEFAULT_REGION), "the default region is a real region")
	_check(RegionDefinition.DEFAULT_REGION == "silver_forest", "the shipped world is still the default")
	_check(RegionDefinition.is_valid("") == false, "an empty id is not a region")
	_check(RegionDefinition.get_region("nowhere").is_empty(), "an unknown id returns no definition")

	var problems := RegionDefinition.validate_all()
	_check(problems.is_empty(), "every definition validates", "; ".join(problems))
	for region in all:
		var id := String(region["id"])
		_check(RegionDefinition.validate(region).is_empty(), "%s passes its own validation" % id)
		_check(String(region["name_key"]) == "region.%s.name" % id, "%s names its translation key" % id)
		_check(String(region["desc_key"]) == "region.%s.desc" % id, "%s has a description key" % id)
		var future: Dictionary = region["future"]
		_check(future.has("creatures") and future.has("bosses") and future.has("quests") and future.has("events"),
			"%s reserves hooks for creatures, bosses, quests and events" % id)
		_check(String(region["landmark"]) != "", "%s has a landmark style" % id)
		var exit_ids: Array = region["exits"]
		_check(exit_ids.size() > 0, "%s can be left through at least one exit" % id)
		var gate: Vector3 = region["gate"]
		var entry: Vector3 = region["entry"]
		_check(gate.distance_to(entry) > 6.0, "%s keeps its gate away from the entry point" % id,
			"%.1f m" % gate.distance_to(entry))
		_check((region["habitat"] as Dictionary).has("spawn_min"), "%s declares a wildlife habitat" % id)


func _test_translation_coverage() -> void:
	print("-- region text")
	var table := _read_csv()
	for key in RegionDefinition.translation_keys():
		var row: Dictionary = table.get(key, {})
		_check(not row.is_empty(), "the CSV carries %s" % key)
		if row.is_empty():
			continue
		_check(String(row["ar"]).strip_edges() != "", "%s is translated to Arabic" % key)
		_check(String(row["en"]).strip_edges() != "", "%s is translated to English" % key)
	for key in ["hud.region", "hud.region.progress", "regions.title", "status.region_entered",
			"toast.region", "toast.region_missing", "menu.regions", "menu.travel"]:
		_check(table.has(key), "the HUD and menus have %s" % key)


## The palette is what the player sees first, so two regions may not look alike.
func _test_identity() -> void:
	print("-- region identity")
	var silver := RegionDefinition.get_region("silver_forest")
	var silver_ground: Dictionary = silver["ground"]
	var silver_atmosphere: Dictionary = silver["atmosphere"]
	_check(_is_neutral(silver_atmosphere), "the silver forest's atmosphere is neutral, so the old world is unchanged")
	var palettes := {}
	var landmarks := {}
	var tints := 0
	for region in RegionDefinition.all():
		var id := String(region["id"])
		var ground: Dictionary = region["ground"]
		landmarks[String(region["landmark"])] = true
		palettes["%s|%s" % [str(ground["dark"]), str(ground["backdrop"])]] = id
		var atmosphere: Dictionary = region["atmosphere"]
		if id != "silver_forest":
			_check(not _is_neutral(atmosphere), "%s changes the light and air" % id)
			_check(ground["dark"] != silver_ground["dark"], "%s does not reuse the silver forest's ground" % id)
			tints += 1
	_check(palettes.size() == 10, "all ten ground palettes are distinct", "%d unique" % palettes.size())
	_check(tints == 9, "nine regions apply their own atmosphere", "%d" % tints)
	_check(landmarks.size() == 10, "each region has its own kind of landmark", "%d styles" % landmarks.size())
	var all_ground_distinct := true
	for region in RegionDefinition.all():
		var ground: Dictionary = region["ground"]
		_check(ground.has("tuft_count") and int(ground["tuft_count"]) >= 0, "%s controls its own grass density" % region["id"])
		if int(ground["tuft_count"]) <= 0:
			all_ground_distinct = false
	_check(all_ground_distinct, "every region plants some ground cover")


func _is_neutral(atmosphere: Dictionary) -> bool:
	return atmosphere["sun_color"] == Color(1, 1, 1) and atmosphere["fog_color"] == Color(1, 1, 1) \
		and is_equal_approx(float(atmosphere["fog_density"]), 1.0) and is_equal_approx(float(atmosphere["exposure"]), 1.0)


# -------------------------------------------------------------- load / unload ---
func _test_loading() -> void:
	print("-- loading and unloading")
	var root := Node3D.new()
	root.name = "RegionTestRoot"
	add_child(root)
	var environment_info := {}
	var manager = RegionManager.new()
	manager.setup(root, environment_info, SEED)

	var baseline := root.get_child_count()
	var result: Dictionary = manager.load_region("silver_forest")
	_check(result.get("ok", false), "the manager loads the default region")
	_check(manager.active_id == "silver_forest", "the manager reports the loaded region")
	_check(root.get_child_count() > baseline, "the region put nodes in the scene",
		"%d nodes" % root.get_child_count())
	var info: Dictionary = result["info"]
	_check(info["node_count"] == manager.region_info["node_count"], "the result describes what it installed")
	_check(info["forest_info"].get("variant_count", 0) == 8, "the silver forest keeps its eight tree variants")
	_check(info["forest_info"].get("material") is ShaderMaterial, "its trees still use the wind shader")
	_check(environment_info.get("foliage_material") is ShaderMaterial,
		"the environment points at the new foliage material")
	_check(info["gate_position"] == RegionDefinition.get_region("silver_forest")["gate"],
		"the gate sits where the definition says")
	_check(manager.is_discovered("silver_forest"), "loading a region discovers it")
	_check(manager.discovered_count() == 1, "the discovery counter starts at one", "%d" % manager.discovered_count())
	_check(_count_named(root, RegionBuilder.GROUND_NAME) == 1, "there is exactly one ground")
	_check(_count_named(root, "TreeCollision") == 1, "there is exactly one collision body")

	var loaded_nodes: Array = manager._nodes
	var first_count := root.get_child_count()
	var second: Dictionary = manager.load_region("desert")
	_check(second.get("ok", false), "the manager loads another region")
	_check(manager.active_id == "desert", "the active region changed")
	_check(_count_named(root, RegionBuilder.GROUND_NAME) == 1, "the old ground was unloaded, not stacked")
	_check(_count_named(root, RegionBuilder.GRASS_NAME) == 1, "there is exactly one grass batch")
	_check(root.get_child_count() < first_count + MAX_NODES, "two regions are never in the scene at once",
		"%d children" % root.get_child_count())
	await get_tree().process_frame
	var still_alive := 0
	for node in loaded_nodes:
		if is_instance_valid(node):
			still_alive += 1
	_check(still_alive == 0, "the unloaded region's nodes are freed", "%d alive" % still_alive)
	_check(manager.discovered_count() == 2, "travel discoveries add up", "%d" % manager.discovered_count())

	var emptied := manager.unload_region()
	_check(emptied, "the manager can unload what it loaded")
	_check(manager.active_id == "", "nothing is active after unloading")
	_check(manager.region_info.is_empty(), "no region info survives unloading")
	_check(root.get_child_count() == baseline, "unloading returns the scene to its baseline",
		"%d children" % root.get_child_count())
	await get_tree().process_frame

	# Every region must install, fit the budget, and unload again.
	var worst_nodes := 0
	var worst_meshes := 0
	for region in RegionDefinition.all():
		var id := String(region["id"])
		var loaded: Dictionary = manager.load_region(id)
		_check(loaded.get("ok", false), "%s loads" % id)
		if not loaded.get("ok", false):
			continue
		var metrics: Dictionary = loaded["info"]
		worst_nodes = maxi(worst_nodes, int(metrics["node_count"]))
		worst_meshes = maxi(worst_meshes, int(metrics["mesh_instances"]))
		_check(int(metrics["node_count"]) <= MAX_NODES, "%s stays inside the node budget" % id,
			"%d nodes" % int(metrics["node_count"]))
		_check(int(metrics["mesh_instances"]) <= MAX_MESH_INSTANCES, "%s stays inside the mesh budget" % id,
			"%d meshes" % int(metrics["mesh_instances"]))
		_check(int(metrics["material_count"]) <= MAX_MATERIALS, "%s reuses its materials" % id,
			"%d materials" % int(metrics["material_count"]))
		_check(not manager.region_signature().is_empty(), "%s produces a geometry fingerprint" % id)
	print("  ..  worst region: %d nodes, %d meshes" % [worst_nodes, worst_meshes])

	manager.unload_region()
	_check(root.get_child_count() == baseline, "the scene is clean after touring every region",
		"%d children" % root.get_child_count())
	root.queue_free()
	await get_tree().process_frame


func _count_prefixed(root: Node, prefix: String) -> int:
	var count := 0
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
	return count


func _count_named(root: Node, node_name: String) -> int:
	var count := 0
	for child in root.get_children():
		if String(child.name) == node_name:
			count += 1
	return count


# --------------------------------------------------------------- determinism ---
func _test_determinism() -> void:
	print("-- seed determinism")
	var roots := []
	for index in range(4):
		var root := Node3D.new()
		root.name = "SeedRoot%d" % index
		add_child(root)
		roots.append(root)

	var a = RegionManager.new()
	a.setup(roots[0], {}, SEED)
	var b = RegionManager.new()
	b.setup(roots[1], {}, SEED)
	var other = RegionManager.new()
	other.setup(roots[2], {}, SEED + 1)
	var unseeded_a = RegionManager.new()
	unseeded_a.setup(roots[3], {}, -1)
	var unseeded_b = RegionManager.new()
	unseeded_b.setup(roots[3], {}, -1)

	for id in ["silver_forest", "desert", "void_realm"]:
		a.load_region(id)
		b.load_region(id)
		_check(a.region_signature() == b.region_signature(), "the same seed reproduces %s" % id)
		other.load_region(id)
		_check(a.region_signature() != other.region_signature(), "a different seed changes %s" % id)
		unseeded_a.load_region(id)
		unseeded_b.load_region(id)
		_check(unseeded_a.region_signature() != unseeded_b.region_signature(),
			"an unseeded world varies %s between runs" % id)

	a.unload_region()
	b.unload_region()
	other.unload_region()
	unseeded_a.unload_region()
	unseeded_b.unload_region()
	await get_tree().process_frame
	for root in roots:
		root.queue_free()
	await get_tree().process_frame


# --------------------------------------------------------- missing resources ---
func _test_missing_resources() -> void:
	print("-- missing and malformed regions")
	var root := Node3D.new()
	root.name = "MissingRoot"
	add_child(root)
	var manager = RegionManager.new()
	manager.setup(root, {}, SEED)
	manager.load_region("silver_forest")

	var refused: Dictionary = manager.load_region("atlantis")
	_check(not refused.get("ok", true), "an unknown region is refused")
	_check(String(refused.get("reason", "")).begins_with("unknown_region"), "the refusal says why",
		String(refused.get("reason", "")))
	_check(manager.active_id == "silver_forest", "the refusal leaves the current region loaded")
	_check(manager._nodes.size() > 0, "the refused transition did not unload anything")

	var broken := RegionDefinition.get_region("desert").duplicate(true)
	broken.erase("gate")
	var problems := RegionDefinition.validate(broken)
	_check(problems.size() > 0 and "missing gate" in problems, "a definition without a gate is rejected")
	var inverted := RegionDefinition.get_region("desert").duplicate(true)
	inverted["vegetation"]["inner_radius"] = 60.0
	_check("vegetation ring is inverted" in RegionDefinition.validate(inverted),
		"a woodland ring that cannot exist is rejected")
	var bad_exit := RegionDefinition.get_region("desert").duplicate(true)
	bad_exit["exits"] = ["desert"]
	_check("region exits to itself" in RegionDefinition.validate(bad_exit),
		"a region that exits to itself is rejected")

	# An unknown landmark style must still mark the gate rather than crash.
	var unknown_style := RegionDefinition.get_region("desert").duplicate(true)
	unknown_style["landmark"] = "future_style"
	var built: Dictionary = RegionBuilder.build(root, unknown_style, _rng(7))
	_check(built["node_count"] > 0, "an unknown landmark style still builds something")
	_check(_count_prefixed(root, "GateStone") == 6, "it falls back to a stone circle at the gate",
		"%d stones" % _count_prefixed(root, "GateStone"))
	RegionBuilder.unload(built["nodes"])
	await get_tree().process_frame

	# A region with no trees keeps the contract of the collision body.
	var bare := RegionDefinition.get_region("desert").duplicate(true)
	bare["vegetation"]["tree_count"] = 0
	bare["vegetation"]["far_tree_count"] = 0
	var bare_built: Dictionary = RegionBuilder.build(root, bare, _rng(9))
	_check(int(bare_built["forest_info"].get("count", -1)) == 0, "a treeless region builds no trunks")
	_check(bare_built["forest_info"].get("collision_body") != null, "but still provides a collision body")
	RegionBuilder.unload(bare_built["nodes"])
	await get_tree().process_frame
	manager.unload_region()
	root.queue_free()
	await get_tree().process_frame


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ------------------------------------------------------------------ the scene ---
func _test_scene() -> void:
	print("-- travel in the real scene")
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_main.set_physics_process(false)

	_check(_main.regions != null, "the scene owns a region manager")
	_check(_main.regions.active_id == "silver_forest", "the scene boots in the silver forest",
		_main.regions.active_id)
	_check(_main.current_region_id() == "silver_forest", "the scene reports its region")
	_check(_main.hud.region_key() == "region.silver_forest.name", "the HUD names the region",
		_main.hud.region_key())
	_check("1/" in _main.hud.region_text(), "the HUD shows the discovery count", _main.hud.region_text())
	_check(_main.regions.discovered_count() == 1, "only the starting region is discovered")
	_check(_main.living_world.atmosphere()["fog_density"] == 1.0, "the starting tint is neutral")

	var ground_before: Dictionary = _main.ground_info
	var start_position: Vector3 = _main.hunter.global_position
	_main.stamina = 61.5
	var travelled: bool = _main.travel_to("desert")
	_check(travelled, "the player can travel to the desert")
	_check(_main.regions.active_id == "desert", "the desert is the active region")
	_check(_main.current_region_id() == "desert", "the scene knows it moved")
	_check(_main.ground_info != ground_before, "the ground was replaced")
	_check(absf(_main.stamina - 61.5) < 0.001, "breath survives the transition", "%.1f" % _main.stamina)
	_check(_main.hunter.global_position.distance_to(_main.regions.entry_point()) < 0.05,
		"the hunter stands at the region's entry point",
		"%.2f m away" % _main.hunter.global_position.distance_to(_main.regions.entry_point()))
	_check(_main.hunter.velocity.length() < 0.01, "the hunter arrives standing still",
		"%.2f m/s" % _main.hunter.velocity.length())
	_check(_main.hud.region_key() == "region.desert.name", "the HUD switched to the desert",
		_main.hud.region_key())
	_check(_main.regions.discovered_count() == 2, "the desert is now discovered")
	_check(_main.living_world.atmosphere()["fog_density"] != 1.0,
		"the desert applies its own atmosphere", "x%.2f" % float(_main.living_world.atmosphere()["fog_density"]))
	_check(_main.deer.visible, "the quarry is placed in the new habitat")
	var habitat: Dictionary = _main.current_region()["habitat"]
	var deer_distance: float = _main.hunter.global_position.distance_to(_main.deer.global_position)
	_check(deer_distance >= float(habitat["spawn_min"]) - 0.5,
		"the quarry respects the habitat's minimum distance", "%.1f m" % deer_distance)
	_check(deer_distance <= float(habitat["spawn_max"]) + 0.5,
		"the quarry respects the habitat's maximum distance", "%.1f m" % deer_distance)
	_check(_main.deer_ai.profile.archetype == String(habitat["archetype"]),
		"the quarry has the habitat's temperament", _main.deer_ai.profile.archetype)
	_check(_count_named(_main, RegionBuilder.GRASS_NAME) == 1, "still only one grass batch after travel")

	_main.stamina = 40.0
	_check(_main.travel_to("silver_forest"), "the player can travel back")
	_check(_main.regions.active_id == "silver_forest", "the starting region is active again")
	_check(absf(_main.stamina - 40.0) < 0.001, "breath survives the way back")
	_check(_main.regions.discovered_count() == 2, "travelling back does not invent discoveries")
	_check(not _main.travel_to("silver_forest"), "travelling to the region you are in is a no-op")
	_check(not _main.travel_to("nowhere"), "travelling nowhere is refused")
	_check(_main.regions.active_id == "silver_forest", "the refused travel changed nothing")

	# The gate prompt is the in-world way into the region screen.
	_main.hunter.global_position = _main.regions.gate_position
	_main._update_context()
	_check(_main._near_gate(), "standing on the gate is detected")
	_check(_main.interact_mode == "travel", "the context button becomes travel", _main.interact_mode)
	_check(_main.hud.interact_key() == "regions.travel", "the button says travel", _main.hud.interact_key())
	_main.hunter.global_position = _main.regions.entry_point() + Vector3(14.0, 0.0, 6.0)
	_main._update_context()
	_check(_main.interact_mode != "travel", "walking away hides the travel prompt", _main.interact_mode)

	for id in RegionDefinition.ids():
		var ok: bool = _main.travel_to(String(id))
		_check(ok, "the player can reach %s" % id)
		_check(_main.regions.active_id == String(id), "%s is active" % id)
	_check(_main.regions.discovered_count() == 10, "the discovery indicator reaches ten",
		"%d" % _main.regions.discovered_count())
	_check(_main.hud.region_text().begins_with(_tr("region.void_realm.name")),
		"the HUD shows the last region by name", _main.hud.region_text())

	# A capture is player state too: it must survive a transition.
	_check(_main.travel_to("silver_forest"), "the player returns for the capture test")
	_main.hunt_session.try_capture(1.0)
	_check(_main.hunt_session.capture_count == 1, "the deer is captured once")
	_check(_main.captured, "the scene agrees the quarry is secured")
	_check(_main.travel_to("frozen_highlands"), "the player travels while holding a capture")
	_check(_main.hunt_session.capture_count == 1, "the capture count survives travel")
	_check(_main.captured, "the secured quarry stays secured")
	_check(not _main.deer.visible, "no new quarry is spawned over a secured one")


func _tr(key: String) -> String:
	return Localization.text(key)


# ----------------------------------------------------------------- the screen ---
func _test_region_menu() -> void:
	print("-- the region screen")
	var menu = REGION_MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var listing: Array = _main.regions.region_listing()
	menu.open(listing)
	await get_tree().process_frame

	_check(menu.visible, "the region screen opens")
	_check(menu.region_buttons.size() == 10, "it lists every region", "%d buttons" % menu.region_buttons.size())
	var current: String = _main.regions.active_id
	_check(menu.selected_id() == current, "it starts on the region you are in", menu.selected_id())
	_check(menu.travel_button.disabled, "travel is disabled for the region you are already in")
	_check(menu.description_label.text != "", "it describes the selected region")
	menu.select("desert")
	_check(menu.selected_id() == "desert", "selecting another region works")
	_check(not menu.travel_button.disabled, "travel is offered for a different region")
	_check(menu.description_label.text == _tr("region.desert.desc"), "the description follows the selection",
		menu.description_label.text)
	var requested := []
	menu.travel_requested.connect(func(id: String) -> void: requested.append(id))
	menu._on_travel()
	_check(requested == ["desert"], "the travel button asks for the selected region", str(requested))
	var closed := []
	menu.closed.connect(func() -> void: closed.append(true))
	menu.close()
	_check(not menu.visible, "the screen closes")
	_check(closed.size() == 1, "closing is announced once")
	menu.queue_free()
	await get_tree().process_frame


# ----------------------------------------------------------------------- CSV ---
func _read_csv() -> Dictionary:
	var table := {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		return table
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and not String(row[0]).strip_edges().is_empty():
			table[String(row[0])] = {"ar": row[1], "en": row[2]}
	file.close()
	return table
