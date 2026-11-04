extends RefCounted
## Builds one region's visible content under the scene root.
##
## Only the active region is ever built, and `unload()` removes exactly the nodes
## this builder created, so two regions never share the scene and the peak cost is
## one region's ground, one woodland and one landmark. The silver forest reuses the
## Phase 3.1 builders untouched (empty palette), which is why the default world is
## identical to the one the earlier phases shipped.

const WildsGround := preload("res://scripts/visuals/wilds_ground.gd")
const Forest := preload("res://scripts/visuals/forest.gd")

## Ranges kept inside the playable bounds so nothing spawns in the fog.
const LANDMARK_DISTANCE := 13.0
const GATE_RADIUS := 3.2

## Region root nodes are named by kind, and the tests check these names.
const GROUND_NAME := "ForestGround"
const GRASS_NAME := "GrassTufts"
const STONE_NAME := "Stones"


## Builds the region's ground, woodland, landmark and gate. Returns everything the
## manager needs to install, unload and test it.
static func build(root: Node3D, region: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var created: Array[Node] = []
	var before := _child_set(root)

	var ground_info: Dictionary = WildsGround.build(root, rng, region["ground"])
	var vegetation: Dictionary = region["vegetation"]
	var forest_info := {}
	if int(vegetation.get("tree_count", 0)) > 0 or int(vegetation.get("far_tree_count", 0)) > 0:
		forest_info = Forest.build(root, rng, _forest_options(region, vegetation))
	else:
		# A treeless biome still gets a collision body so the region's contract is
		# the same everywhere and the camera probes have something consistent.
		var body := StaticBody3D.new()
		body.name = "TreeCollision"
		body.collision_layer = 2
		body.collision_mask = 0
		root.add_child(body)
		forest_info = {"count": 0, "far_count": 0, "variant_count": 0, "node_count": 1,
			"positions": [], "heights": [], "collision_body": body,
			"collision_shapes": 0, "canopy_bottom": 3.6, "material": null}

	var landmark := _landmark(root, String(region["landmark"]), region, rng)
	created = _new_children(root, before)

	var meshes := 0
	var materials := {}
	for node in created:
		_collect_cost(node, materials)
		if node is MeshInstance3D:
			meshes += 1
	return {
		"ground_info": ground_info,
		"forest_info": forest_info,
		"nodes": created,
		"node_count": created.size(),
		"mesh_instances": meshes,
		"material_count": materials.size(),
		"landmark": String(region["landmark"]),
		"gate_position": landmark["gate_position"],
		"landmark_nodes": landmark["nodes"],
	}


## Frees a region's nodes immediately. `queue_free` alone would leave the old
## region and the new one in the tree for a frame, which is both a visible pop and
## a moment with twice the memory.
static func unload(nodes: Array) -> int:
	var freed := 0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var parent: Node = node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.queue_free()
		freed += 1
	return freed


static func _forest_options(region: Dictionary, vegetation: Dictionary) -> Dictionary:
	# A region may name its own clearings to protect its landmark and its entry
	# point; otherwise the courtyard in front of the gate and the entry are cleared.
	var clearings: Array = vegetation.get("clearings", [
		{"center": region["entry"], "radius": 4.5},
		{"center": region["gate"], "radius": 6.0},
	])
	return {
		"tree_count": int(vegetation["tree_count"]),
		"far_tree_count": int(vegetation["far_tree_count"]),
		"inner_radius": float(vegetation["inner_radius"]),
		"outer_radius": float(vegetation["outer_radius"]),
		"min_spacing": float(vegetation["min_spacing"]),
		"leaf_palettes": vegetation.get("leaf_palettes", []),
		"bark_colors": vegetation.get("bark_colors", []),
		"clearings": clearings,
	}


## The landmark gives each region its silhouette: the thing you recognise from a
## distance. Positions are relative to the gate so the gate always sits inside it.
static func _landmark(root: Node3D, style: String, region: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var nodes: Array[Node] = []
	var gate: Vector3 = region["gate"]
	match style:
		"ruin":
			nodes.append_array(_ruin(root, gate))
		"dunes":
			nodes.append_array(_dunes(root, gate, rng))
		"ice_spires":
			nodes.append_array(_ice_spires(root, gate, rng))
		"lava_columns":
			nodes.append_array(_lava_columns(root, gate, rng))
		"colonnade":
			nodes.append_array(_colonnade(root, gate))
		"oasis_pool":
			nodes.append_array(_oasis_pool(root, gate, rng))
		"crystal_cluster":
			nodes.append_array(_crystal_cluster(root, gate, rng))
		"sunken_bridge":
			nodes.append_array(_sunken_bridge(root, gate))
		"cliff_platforms":
			nodes.append_array(_cliff_platforms(root, gate))
		"void_monolith":
			nodes.append_array(_void_monolith(root, gate, rng))
		_:
			# Unknown style: a plain stone circle still marks a gate, so a future
			# region cannot ship without a landmark and break navigation.
			nodes.append_array(_stone_circle(root, gate))
	return {"nodes": nodes, "gate_position": gate}


# ------------------------------------------------------------------ landmarks ---

## The Phase 3.1 arch, kept exactly where it has always been.
static func _ruin(root: Node3D, gate: Vector3) -> Array:
	var nodes: Array[Node] = []
	var stone := _material(Color(0.175, 0.185, 0.165), 0.94)
	for x in [-2.2, 2.2]:
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.8, 4.2, 0.9)
		nodes.append(_mesh(root, "RuinPillar", pillar, stone, gate + Vector3(x, 2.1, -2.0)))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(5.2, 0.8, 1.0)
	nodes.append(_mesh(root, "RuinLintel", lintel, stone, gate + Vector3(0, 4.2, -2.0)))
	var fallen := BoxMesh.new()
	fallen.size = Vector3(1.8, 0.55, 0.7)
	nodes.append(_mesh(root, "RuinBlock", fallen, stone, gate + Vector3(3.4, 0.3, 0.6), Vector3(0, 22, 6)))
	return nodes


static func _dunes(root: Node3D, gate: Vector3, rng: RandomNumberGenerator) -> Array:
	var nodes: Array[Node] = []
	var sand := _material(Color(0.478, 0.365, 0.196), 0.97)
	for i in range(6):
		var ridge := SphereMesh.new()
		ridge.radius = 1.0
		ridge.height = 1.0
		ridge.radial_segments = 14
		ridge.rings = 6
		var angle := TAU * float(i) / 6.0 + 0.4
		var distance := rng.randf_range(9.0, 18.0)
		var scale := Vector3(rng.randf_range(7.0, 12.0), rng.randf_range(1.6, 2.8), rng.randf_range(4.5, 7.5))
		nodes.append(_mesh(root, "DuneRidge", ridge, sand,
			gate + Vector3(cos(angle) * distance, -0.4, sin(angle) * distance),
			Vector3(0, rng.randf() * 180.0, 0), scale))
	var obelisk := BoxMesh.new()
	obelisk.size = Vector3(0.9, 5.4, 0.9)
	var dark := _material(Color(0.235, 0.196, 0.145), 0.86)
	for x in [-3.0, 3.0]:
		nodes.append(_mesh(root, "Obelisk", obelisk, dark, gate + Vector3(x, 2.7, 0)))
	return nodes


static func _ice_spires(root: Node3D, gate: Vector3, rng: RandomNumberGenerator) -> Array:
	var nodes: Array[Node] = []
	var ice := _material(Color(0.729, 0.831, 0.902), 0.32, 0.15)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 0.9
	spire.height = 6.0
	spire.radial_segments = 7
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var distance := rng.randf_range(7.0, 13.0)
		var height := rng.randf_range(0.7, 1.6)
		nodes.append(_mesh(root, "IceSpire", spire, ice,
			gate + Vector3(cos(angle) * distance, 3.0 * height, sin(angle) * distance),
			Vector3(rng.randf_range(-6.0, 6.0), rng.randf() * 360.0, rng.randf_range(-6.0, 6.0)),
			Vector3(1.0, height, 1.0)))
	var pond := CylinderMesh.new()
	pond.top_radius = 4.2
	pond.bottom_radius = 4.2
	pond.height = 0.06
	pond.radial_segments = 24
	nodes.append(_mesh(root, "FrozenPool", pond, _material(Color(0.518, 0.702, 0.780), 0.18, 0.25),
		gate + Vector3(0, 0.03, 4.6)))
	return nodes


static func _lava_columns(root: Node3D, gate: Vector3, rng: RandomNumberGenerator) -> Array:
	var nodes: Array[Node] = []
	var basalt := _material(Color(0.129, 0.114, 0.110), 0.9)
	var column := CylinderMesh.new()
	column.top_radius = 0.55
	column.bottom_radius = 0.7
	column.height = 4.0
	column.radial_segments = 6
	for i in range(7):
		var angle := TAU * float(i) / 7.0 + 0.3
		var distance := rng.randf_range(6.0, 12.0)
		var height := rng.randf_range(0.6, 1.5)
		nodes.append(_mesh(root, "BasaltColumn", column, basalt,
			gate + Vector3(cos(angle) * distance, 2.0 * height, sin(angle) * distance),
			Vector3(0, rng.randf() * 360.0, 0), Vector3(1, height, 1)))
	var crack := PlaneMesh.new()
	crack.size = Vector2(2.0, 9.0)
	nodes.append(_mesh(root, "LavaCrack", crack, _emissive(Color(1.0, 0.42, 0.12), 2.4),
		gate + Vector3(0, 0.04, 5.0)))
	var arch := BoxMesh.new()
	arch.size = Vector3(0.8, 4.6, 0.8)
	for x in [-2.6, 2.6]:
		nodes.append(_mesh(root, "ObsidianArch", arch, _material(Color(0.078, 0.067, 0.071), 0.45), gate + Vector3(x, 2.3, 0)))
	return nodes


static func _colonnade(root: Node3D, gate: Vector3) -> Array:
	var nodes: Array[Node] = []
	var stone := _material(Color(0.478, 0.451, 0.388), 0.93)
	var column := CylinderMesh.new()
	column.top_radius = 0.42
	column.bottom_radius = 0.52
	column.height = 4.6
	column.radial_segments = 10
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.4, 0.5, 0.7)
	for i in range(6):
		var row := -1.0 if i < 3 else 1.0
		var x := -6.0 + float(i % 3) * 6.0
		nodes.append(_mesh(root, "Column", column, stone, gate + Vector3(x, 2.3, row * 4.2)))
		if i % 2 == 0:
			nodes.append(_mesh(root, "Lintel", lintel, stone, gate + Vector3(x + 3.0, 4.85, row * 4.2), Vector3(0, 8, 0)))
	var slab := BoxMesh.new()
	slab.size = Vector3(3.6, 0.3, 2.2)
	nodes.append(_mesh(root, "FallenSlab", slab, stone, gate + Vector3(1.6, 0.15, 6.4), Vector3(0, 16, 3)))
	return nodes


static func _oasis_pool(root: Node3D, gate: Vector3, rng: RandomNumberGenerator) -> Array:
	var nodes: Array[Node] = []
	var water := _transparent(Color(0.161, 0.420, 0.451, 0.78), 0.06)
	var pool := CylinderMesh.new()
	pool.top_radius = 5.0
	pool.bottom_radius = 4.6
	pool.height = 0.08
	pool.radial_segments = 28
	nodes.append(_mesh(root, "OasisPool", pool, water, gate + Vector3(0, 0.04, 6.4)))
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = 5.2
	trunk_mesh.radial_segments = 6
	var frond := PrismMesh.new()
	frond.size = Vector3(2.6, 0.12, 0.7)
	var bark := _material(Color(0.290, 0.243, 0.180), 0.9)
	var leaf := _material(Color(0.157, 0.361, 0.243), 0.88)
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + 0.6
		var base := gate + Vector3(cos(angle) * 6.4, 0.0, sin(angle) * 6.4 + 6.4)
		nodes.append(_mesh(root, "PalmTrunk", trunk_mesh, bark, base + Vector3(0, 2.6, 0)))
		for f in range(4):
			var frond_angle := TAU * float(f) / 4.0
			nodes.append(_mesh(root, "PalmFrond", frond, leaf,
				base + Vector3(cos(frond_angle) * 1.1, 5.2, sin(frond_angle) * 1.1),
				Vector3(0, rad_to_deg(frond_angle), -18)))
	var rim := TorusMesh.new()
	rim.inner_radius = 1.0
	rim.outer_radius = 1.5
	nodes.append(_mesh(root, "WellRim", rim, _material(Color(0.396, 0.361, 0.290), 0.95), gate + Vector3(0, 0.3, 0)))
	return nodes


static func _crystal_cluster(root: Node3D, gate: Vector3, rng: RandomNumberGenerator) -> Array:
	var nodes: Array[Node] = []
	var crystal := PrismMesh.new()
	crystal.size = Vector3(1.1, 4.2, 1.1)
	var glow := _emissive(Color(0.435, 0.816, 0.839), 1.8)
	for i in range(9):
		var angle := TAU * float(i) / 9.0 + 0.2
		var distance := rng.randf_range(4.5, 11.0)
		var height := rng.randf_range(0.6, 1.7)
		nodes.append(_mesh(root, "Crystal", crystal, glow,
			gate + Vector3(cos(angle) * distance, 2.1 * height, sin(angle) * distance),
			Vector3(rng.randf_range(-12.0, 12.0), rng.randf() * 360.0, rng.randf_range(-12.0, 12.0)),
			Vector3(1.0, height, 1.0)))
	nodes.append_array(_stone_circle(root, gate))
	return nodes


static func _sunken_bridge(root: Node3D, gate: Vector3) -> Array:
	var nodes: Array[Node] = []
	var water := _transparent(Color(0.094, 0.161, 0.145, 0.86), 0.12)
	for i in range(3):
		var pool := CylinderMesh.new()
		pool.top_radius = 3.6 + float(i)
		pool.bottom_radius = 3.4 + float(i)
		pool.height = 0.05
		pool.radial_segments = 22
		nodes.append(_mesh(root, "SwampPool", pool, water,
			gate + Vector3(-7.0 + float(i) * 7.0, 0.02, 4.0 + float(i) * 3.0)))
	var plank := BoxMesh.new()
	plank.size = Vector3(1.1, 0.16, 2.2)
	var wood := _material(Color(0.157, 0.145, 0.125), 0.92)
	for i in range(5):
		nodes.append(_mesh(root, "BridgePlank", plank, wood,
			gate + Vector3(0, 0.5 - float(i) * 0.08, -3.0 + float(i) * 1.6), Vector3(float(i) * 3.0, 0, 0)))
	var post := BoxMesh.new()
	post.size = Vector3(0.28, 2.4, 0.28)
	for x in [-1.5, 1.5]:
		nodes.append(_mesh(root, "BridgePost", post, wood, gate + Vector3(x, 1.2, -3.6)))
	return nodes


static func _cliff_platforms(root: Node3D, gate: Vector3) -> Array:
	var nodes: Array[Node] = []
	var rock := _material(Color(0.290, 0.294, 0.310), 0.92)
	var terrace := BoxMesh.new()
	terrace.size = Vector3(9.0, 1.4, 7.0)
	nodes.append(_mesh(root, "CliffTerrace", terrace, rock, gate + Vector3(-9.0, 0.7, -2.0)))
	nodes.append(_mesh(root, "CliffTerrace", terrace, rock, gate + Vector3(9.0, 1.6, -4.0), Vector3(0, 12, 0), Vector3(0.8, 1.4, 0.9)))
	var step := BoxMesh.new()
	step.size = Vector3(2.2, 0.5, 1.2)
	for i in range(4):
		nodes.append(_mesh(root, "CliffStep", step, rock, gate + Vector3(0, 0.25 + float(i) * 0.5, -2.0 - float(i) * 1.1)))
	var plank := BoxMesh.new()
	plank.size = Vector3(1.0, 0.12, 5.0)
	var rope := _material(Color(0.353, 0.310, 0.243), 0.9)
	nodes.append(_mesh(root, "RopeBridge", plank, rope, gate + Vector3(0, 2.4, 4.0), Vector3(4, 0, 0)))
	return nodes


static func _void_monolith(root: Node3D, gate: Vector3, rng: RandomNumberGenerator) -> Array:
	var nodes: Array[Node] = []
	var shard := PrismMesh.new()
	shard.size = Vector3(1.2, 5.0, 1.2)
	var dark := _material(Color(0.086, 0.075, 0.129), 0.55)
	var glow := _emissive(Color(0.616, 0.482, 0.847), 1.4)
	for i in range(7):
		var angle := TAU * float(i) / 7.0
		var distance := rng.randf_range(6.0, 12.0)
		nodes.append(_mesh(root, "VoidShard", shard, dark,
			gate + Vector3(cos(angle) * distance, rng.randf_range(1.2, 3.4), sin(angle) * distance),
			Vector3(rng.randf_range(-25.0, 25.0), rng.randf() * 360.0, rng.randf_range(-25.0, 25.0))))
	var ring := TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 2.7
	nodes.append(_mesh(root, "VoidGate", ring, glow, gate + Vector3(0, 2.7, 0), Vector3(0, 0, 90)))
	return nodes


static func _stone_circle(root: Node3D, gate: Vector3) -> Array:
	var nodes: Array[Node] = []
	var stone := _material(Color(0.290, 0.278, 0.251), 0.94)
	var block := BoxMesh.new()
	block.size = Vector3(0.8, 2.2, 0.8)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		nodes.append(_mesh(root, "GateStone", block, stone,
			gate + Vector3(cos(angle) * 2.6, 1.1, sin(angle) * 2.6), Vector3(0, rad_to_deg(angle), 0)))
	return nodes


# ------------------------------------------------------------------- helpers ---

static func _mesh(root: Node3D, node_name: String, mesh: Mesh, material: Material, position: Vector3,
		rotation_degrees := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	# Sibling names must be unique: a repeated name would be renamed with the
	# node's instance id, which is not stable between runs or between regions.
	instance.name = _unique_name(root, node_name)
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.scale = scale
	root.add_child(instance)
	return instance


static func _unique_name(root: Node, base: String) -> String:
	if not root.has_node(NodePath(base)):
		return base
	var index := 2
	while root.has_node(NodePath("%s%d" % [base, index])):
		index += 1
	return "%s%d" % [base, index]


static func _material(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func _transparent(color: Color, roughness := 0.1) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.35
	return mat


static func _child_set(root: Node) -> Array:
	var out := []
	for child in root.get_children():
		out.append(child)
	return out


static func _new_children(root: Node, before: Array) -> Array:
	var out: Array[Node] = []
	for child in root.get_children():
		if not before.has(child):
			out.append(child)
	return out


static func _collect_cost(node: Node, materials: Dictionary) -> void:
	var mesh: Mesh = null
	if node is MultiMeshInstance3D:
		var multi := node as MultiMeshInstance3D
		if multi.multimesh != null:
			mesh = multi.multimesh.mesh
	elif node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.material_override != null:
			materials[instance.material_override.get_instance_id()] = true
		mesh = instance.mesh
	if mesh != null:
		for surface in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(surface)
			if mat != null:
				materials[mat.get_instance_id()] = true
	for child in node.get_children():
		_collect_cost(child, materials)
