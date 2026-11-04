extends RefCounted
## Owns which region is loaded, and nothing else.
##
## One region exists at a time: loading unloads the previous region's nodes
## immediately, so the scene never holds two grounds, two woodlands or two
## landmarks. Everything else — hunter, deer, camera, audio, settings — belongs to
## main.gd and is therefore untouched by a transition, which is what "safe
## transition without losing player state" means here.
##
## The manager knows the region definitions and the builder, keeps the discovery
## set for the indicator, and hands the installed pieces back to the scene. It is
## deliberately usable in a headless test: give it a root node and a seed and it
## will load, unload and report counts without a renderer.

const RegionDefinition := preload("res://scripts/world/region_definition.gd")
const RegionBuilder := preload("res://scripts/world/region_builder.gd")

signal region_changed(previous: String, current: String)

const DEFAULT_REGION := "silver_forest"

var active_id := ""
var visited: Array[String] = []
var region_info := {}
var gate_position := Vector3.ZERO
var last_error := ""
var transitions := 0

var _root: Node3D
var _environment_info := {}
var _living_world: RefCounted
var _nodes: Array = []
var _seed := -1


## `scene_root` is where the region's nodes are parented (the main scene), and
## `seed_value` is the world seed: a seeded run reproduces every region exactly.
func setup(scene_root: Node3D, environment_info: Dictionary, seed_value := -1) -> void:
	_root = scene_root
	_environment_info = environment_info
	_seed = seed_value


## The living world is built after the first region, because it needs the
## environment the region tint writes into. Attaching it installs that tint.
func attach_living_world(world: RefCounted) -> void:
	_living_world = world
	if not region_info.is_empty():
		_living_world.set_region_tint(region_info["region"]["atmosphere"])
		_living_world.rebind_ground(region_info["ground_info"])


func can_enter(id: String) -> bool:
	return RegionDefinition.is_valid(id)


func is_loaded(id := "") -> bool:
	if id.is_empty():
		return active_id != "" and not _nodes.is_empty()
	return active_id == id and not _nodes.is_empty()


func is_discovered(id: String) -> bool:
	return id in visited


func discovered_count() -> int:
	return visited.size()


func region_count() -> int:
	return RegionDefinition.count()


func entry_point() -> Vector3:
	if region_info.is_empty():
		return Vector3.ZERO
	return region_info["region"]["entry"]


## Loads `id`, replacing whatever region was loaded. Returns a result dictionary
## with `ok`, and either the installed info or a reason. An unknown region is
## refused and the current one stays loaded: navigation never falls into a void.
func load_region(id: String, mark_visited := true) -> Dictionary:
	if not can_enter(id):
		last_error = "unknown_region:%s" % id
		return {"ok": false, "reason": last_error}
	if _root == null or not is_instance_valid(_root):
		last_error = "no_scene_root"
		return {"ok": false, "reason": last_error}
	if active_id == id and not _nodes.is_empty():
		return {"ok": true, "region": active_id, "reloaded": false, "info": region_info}

	var previous := active_id
	unload_region()

	var definition := RegionDefinition.get_region(id)
	var result: Dictionary = RegionBuilder.build(_root, definition, _rng_for(id))
	var info := {
		"region": definition,
		"ground_info": result["ground_info"],
		"forest_info": result["forest_info"],
		"gate_position": result["gate_position"],
		"landmark": result["landmark"],
		"node_count": result["node_count"],
		"mesh_instances": result["mesh_instances"],
		"material_count": result["material_count"],
	}
	_nodes = result["nodes"]
	region_info = info
	active_id = id
	gate_position = result["gate_position"]
	transitions += 1
	last_error = ""
	if mark_visited and not is_discovered(id):
		visited.append(id)

	_environment_info["foliage_material"] = result["forest_info"].get("material", null)
	if _living_world != null:
		_living_world.set_region_tint(definition["atmosphere"])
		_living_world.rebind_ground(result["ground_info"])

	region_changed.emit(previous, id)
	return {"ok": true, "region": id, "reloaded": false, "info": info}


## Frees the active region's nodes. Safe to call when nothing is loaded.
func unload_region() -> bool:
	if _nodes.is_empty():
		active_id = ""
		return false
	var freed := RegionBuilder.unload(_nodes)
	_nodes = []
	region_info = {}
	active_id = ""
	gate_position = Vector3.ZERO
	return freed > 0


## Deterministic per-region generator: the same world seed and region id always
## produce the same dunes, the same trees and the same landmark.
func _rng_for(id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if _seed >= 0:
		rng.seed = _seed + absi(id.hash())
	else:
		rng.randomize()
	return rng


## Fingerprint of the loaded geometry, used to prove a seeded region reproduces.
func region_signature() -> String:
	if region_info.is_empty():
		return ""
	var parts := PackedStringArray()
	var forest: Dictionary = region_info["forest_info"]
	for position in forest.get("positions", []):
		parts.append("%.3f,%.3f" % [position.x, position.z])
	for node in _nodes:
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			parts.append("%s:%.3f,%.3f,%.3f" % [node.name, node.position.x, node.position.y, node.position.z])
	return ",".join(parts).sha256_text()


## What the HUD and the region screen need to describe the current place.
func current_summary() -> Dictionary:
	if region_info.is_empty():
		return {}
	var definition: Dictionary = region_info["region"]
	return {
		"id": String(definition["id"]),
		"name_key": String(definition["name_key"]),
		"desc_key": String(definition["desc_key"]),
		"landmark": String(definition["landmark"]),
		"discovered": discovered_count(),
		"total": region_count(),
	}


## All regions with their discovery state, in display order.
func region_listing() -> Array:
	var out := []
	for region in RegionDefinition.all():
		out.append({
			"id": String(region["id"]),
			"name_key": String(region["name_key"]),
			"desc_key": String(region["desc_key"]),
			"landmark": String(region["landmark"]),
			"visited": is_discovered(String(region["id"])),
			"active": active_id == String(region["id"]),
			"atmosphere": region["atmosphere"],
			"habitat": region["habitat"],
		})
	return out
