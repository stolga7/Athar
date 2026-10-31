extends RefCounted
## ATHAR procedural forest.
##
## Why this exists: the prototype drew every tree as a brown cylinder with three
## identical green spheres stacked on it, which read as a field of lollipops and
## cost one draw call per part (roughly 380 for the forest alone).
##
## This builder does three things differently:
##
##   1. Silhouette. Each tree is a tapered trunk with a root flare, a few
##      branches, and a crown built from overlapping lobes. Broadleaf crowns are
##      irregular clusters; conifers are stacked, slightly rotated cones. Crowns
##      start well above head height, so the camera is never inside foliage.
##   2. Variety. Eight variants with different proportions and palettes are
##      instanced with a per-tree yaw, height, width and a couple of degrees of
##      lean, so no two trees on screen are identical.
##   3. Cost. Each variant is merged into a single vertex-coloured mesh and drawn
##      with one MultiMeshInstance3D, so the whole forest is about eight draw
##      calls instead of hundreds.
##
## Trunks get a collision cylinder on layer 2 only. The hunter and deer collide
## on layer 1, so movement and gameplay are untouched; the camera probes mask
## 1|2 and can therefore be blocked by a trunk.
##
## Everything is driven by the caller's RandomNumberGenerator, so a seeded world
## reproduces the same forest exactly.

const U := preload("res://scripts/visuals/rig_utils.gd")

## Trees to place, and the ring they are placed in. The inner radius keeps a
## playable clearing; the outer one stays inside the world bounds.
const TREE_COUNT := 84
## A second, unplayable ring far outside the world bounds. It exists only to give
## the horizon a treeline instead of ending in fog, and casts no shadows.
const FAR_TREE_COUNT := 54
const FAR_INNER_RADIUS := 54.0
const FAR_OUTER_RADIUS := 82.0
const INNER_RADIUS := 14.0
const OUTER_RADIUS := 43.0
## Minimum distance between two trunks. Wider spacing than the prototype, which
## is what keeps the mid-ground readable instead of a wall of leaves.
const MIN_SPACING := 3.5
## Cleared areas: the ruin courtyard and the hunter's starting pocket.
const RUIN_CENTER := Vector3(-10.0, 0.0, -15.0)
const RUIN_CLEAR_RADIUS := 6.0
const START_CENTER := Vector3(0.0, 0.0, 7.0)
const START_CLEAR_RADIUS := 4.5
## Trunk collision lives on its own layer, so it blocks the camera and nothing else.
const COLLISION_LAYER := 2
## Nothing may hang foliage below this height: the camera tops out at about 2.9 m.
const CANOPY_BOTTOM := 3.6

const BARK_COLORS: Array[Color] = [
	Color(0.169, 0.132, 0.097),
	Color(0.209, 0.162, 0.115),
	Color(0.142, 0.119, 0.095),
]
const LEAF_PALETTES: Array = [
	[Color(0.061, 0.135, 0.084), Color(0.081, 0.169, 0.097), Color(0.105, 0.203, 0.115)],
	[Color(0.095, 0.176, 0.095), Color(0.121, 0.213, 0.111), Color(0.146, 0.243, 0.124)],
	[Color(0.047, 0.124, 0.095), Color(0.068, 0.155, 0.119), Color(0.092, 0.186, 0.132)],
	[Color(0.078, 0.132, 0.076), Color(0.101, 0.162, 0.089), Color(0.124, 0.189, 0.105)],
	[Color(0.051, 0.111, 0.076), Color(0.070, 0.135, 0.089), Color(0.092, 0.162, 0.105)],
	[Color(0.111, 0.196, 0.121), Color(0.135, 0.223, 0.135), Color(0.162, 0.250, 0.146)],
]


## Builds the forest under `parent` and returns a summary used by the tests.
static func build(parent: Node3D, rng: RandomNumberGenerator) -> Dictionary:
	var variants := _variants()
	var meshes: Array[ArrayMesh] = []
	for i in range(variants.size()):
		meshes.append(_variant_mesh(variants[i], i))

	var spots: Array[Dictionary] = []
	var attempts := 0
	var max_attempts := TREE_COUNT * 80
	while spots.size() < TREE_COUNT and attempts < max_attempts:
		attempts += 1
		# sqrt keeps the trees evenly spread over the ring instead of clumping
		# against the inner edge.
		var radius := sqrt(rng.randf_range(INNER_RADIUS * INNER_RADIUS, OUTER_RADIUS * OUTER_RADIUS))
		var angle := rng.randf() * TAU
		var p := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if p.distance_to(START_CENTER) < START_CLEAR_RADIUS:
			continue
		if p.distance_to(RUIN_CENTER) < RUIN_CLEAR_RADIUS:
			continue
		var too_close := false
		for spot in spots:
			if p.distance_to(spot["position"]) < MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		spots.append({
			"position": p,
			"variant": rng.randi_range(0, variants.size() - 1),
			"yaw": rng.randf() * TAU,
			"height_scale": rng.randf_range(0.9, 1.18),
			"width_scale": rng.randf_range(0.92, 1.1),
			"tilt": Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0)),
		})

	# One MultiMeshInstance3D per variant, each holding every tree of that shape.
	var far_spots: Array[Dictionary] = []
	var far_attempts := 0
	while far_spots.size() < FAR_TREE_COUNT and far_attempts < FAR_TREE_COUNT * 30:
		far_attempts += 1
		var far_angle := rng.randf() * TAU
		var far_radius := rng.randf_range(FAR_INNER_RADIUS, FAR_OUTER_RADIUS)
		far_spots.append({
			"position": Vector3(cos(far_angle) * far_radius, 0.0, sin(far_angle) * far_radius),
			"variant": rng.randi_range(0, variants.size() - 1),
			"yaw": rng.randf() * TAU,
			"height_scale": rng.randf_range(1.05, 1.35),
			"width_scale": rng.randf_range(1.0, 1.2),
			"tilt": Vector2.ZERO,
		})

	var nodes := 0
	nodes += _instance_group(parent, "TreeVariant", spots, variants.size(), meshes, true)
	nodes += _instance_group(parent, "FarTree", far_spots, variants.size(), meshes, false)

	var body := StaticBody3D.new()
	body.name = "TreeCollision"
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	var positions: Array[Vector3] = []
	var heights: Array[float] = []
	for spot in spots:
		var spec: Dictionary = variants[spot["variant"]]
		var height: float = spec["trunk_height"] + spec["crown_height"]
		heights.append(height * spot["height_scale"])
		positions.append(spot["position"])
		var shape := CylinderShape3D.new()
		shape.radius = spec["trunk_bottom"] * spot["width_scale"] * 1.2
		shape.height = 4.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = spot["position"] + Vector3(0, 2.0, 0)
		body.add_child(cs)

	return {
		"count": positions.size(),
		"far_count": far_spots.size(),
		"variant_count": variants.size(),
		"node_count": nodes + 1,
		"positions": positions,
		"heights": heights,
		"collision_body": body,
		"collision_shapes": body.get_child_count(),
		"canopy_bottom": CANOPY_BOTTOM,
	}


## Groups spots by variant and emits one MultiMeshInstance3D per variant.
static func _instance_group(parent: Node3D, prefix: String, spots: Array[Dictionary], variant_count: int, meshes: Array[ArrayMesh], shadows: bool) -> int:
	var per_variant: Array[Array] = []
	for i in range(variant_count):
		per_variant.append([])
	for spot in spots:
		per_variant[spot["variant"]].append(spot)

	var nodes := 0
	for i in range(variant_count):
		if per_variant[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = per_variant[i].size()
		for j in range(per_variant[i].size()):
			mm.set_instance_transform(j, _instance_transform(per_variant[i][j]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%d" % [prefix, i]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		nodes += 1
	return nodes


## The eight tree shapes. Broadleaf trees have a short trunk under a rounded,
## broken crown; conifers are narrower with foliage starting higher and stacked
## cones going up. Sizes are metres.
static func _variants() -> Array:
	return [
		{"species": 0, "trunk_height": 4.7, "trunk_bottom": 0.36, "trunk_top": 0.19, "crown_height": 3.4, "crown_width": 2.5, "palette": 0, "bark": 0},
		{"species": 0, "trunk_height": 5.4, "trunk_bottom": 0.31, "trunk_top": 0.17, "crown_height": 3.0, "crown_width": 2.2, "palette": 1, "bark": 1},
		{"species": 0, "trunk_height": 4.2, "trunk_bottom": 0.42, "trunk_top": 0.22, "crown_height": 3.8, "crown_width": 2.9, "palette": 2, "bark": 0},
		{"species": 0, "trunk_height": 5.9, "trunk_bottom": 0.29, "trunk_top": 0.15, "crown_height": 2.7, "crown_width": 2.0, "palette": 3, "bark": 2},
		{"species": 0, "trunk_height": 4.5, "trunk_bottom": 0.33, "trunk_top": 0.18, "crown_height": 3.1, "crown_width": 2.4, "palette": 5, "bark": 1},
		{"species": 1, "trunk_height": 6.4, "trunk_bottom": 0.30, "trunk_top": 0.14, "crown_height": 4.6, "crown_width": 2.0, "palette": 4, "bark": 2},
		{"species": 1, "trunk_height": 7.2, "trunk_bottom": 0.26, "trunk_top": 0.12, "crown_height": 4.2, "crown_width": 1.8, "palette": 2, "bark": 0},
		{"species": 1, "trunk_height": 6.0, "trunk_bottom": 0.33, "trunk_top": 0.15, "crown_height": 5.0, "crown_width": 2.2, "palette": 0, "bark": 1},
	]


static func _instance_transform(spot: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, spot["yaw"])
	basis = basis * Basis(Vector3.RIGHT, deg_to_rad(spot["tilt"].x))
	basis = basis * Basis(Vector3.FORWARD, deg_to_rad(spot["tilt"].y))
	basis = basis.scaled(Vector3(spot["width_scale"], spot["height_scale"], spot["width_scale"]))
	return Transform3D(basis, spot["position"])


## One shared material for every tree: the colour lives in the vertex data, so
## all eight variants and all their instances are a single material state.
static func _foliage_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# The baked colours are authored in sRGB, so tell the renderer to read them
	# that way instead of treating them as linear.
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.92
	mat.metallic_specular = 0.15
	return mat


## Builds one tree variant as a single vertex-coloured mesh.
static func _variant_mesh(spec: Dictionary, index: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each variant jitters its crown from its own fixed seed, so the shape is
	# stable no matter which world seed placed it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (index + 1)
	var bark: Color = BARK_COLORS[spec["bark"]]
	var palette: Array = LEAF_PALETTES[spec["palette"]]
	var trunk_h: float = spec["trunk_height"]
	var bottom: float = spec["trunk_bottom"]
	var top: float = spec["trunk_top"]

	# Root flare, so the trunk meets the ground instead of floating on it.
	_cone(st, Vector3.ZERO, 0.34, bottom * 1.25, 0.0, 7, bark.darkened(0.35))
	# Trunk, slightly tapered.
	_segment(st, Vector3(0, 0.35, 0), Vector3(0, trunk_h, 0), bottom, top, 7, bark)

	# Two or three bare branches reaching into the crown.
	var branch_count := 2 + rng.randi_range(0, 1)
	for b in range(branch_count):
		var angle := TAU * float(b) / float(branch_count) + rng.randf() * 0.9
		var start := Vector3(0, trunk_h * rng.randf_range(0.62, 0.8), 0)
		var reach: float = spec["crown_width"] * rng.randf_range(0.34, 0.5)
		var end := start + Vector3(cos(angle) * reach, rng.randf_range(0.7, 1.4), sin(angle) * reach)
		_segment(st, start, end, top * 0.7, top * 0.35, 5, bark)

	if spec["species"] == 1:
		_conifer_crown(st, spec, palette, trunk_h, rng)
	else:
		_broadleaf_crown(st, spec, palette, trunk_h, rng)

	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _foliage_material())
	return mesh


static func _broadleaf_crown(st: SurfaceTool, spec: Dictionary, palette: Array, trunk_h: float, rng: RandomNumberGenerator) -> void:
	var width: float = spec["crown_width"]
	var height: float = spec["crown_height"]
	var lobes := 4
	for i in range(lobes):
		var t := float(i) / float(lobes - 1)
		# Lobes fan out and rise, each a flattened, slightly rotated sphere.
		var angle := TAU * t + rng.randf_range(-0.4, 0.4)
		var spread := 0.0 if i == 0 else width * rng.randf_range(0.18, 0.34)
		var centre := Vector3(
			cos(angle) * spread,
			trunk_h + 0.55 + t * height * 0.45 + rng.randf_range(-0.15, 0.15),
			sin(angle) * spread
		)
		var radius: float = width * (0.62 if i == 0 else rng.randf_range(0.38, 0.5))
		var squash := rng.randf_range(0.72, 0.92)
		var mesh := U.sphere(radius, 9, 6)
		var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), centre)
		xform.basis = xform.basis.scaled(Vector3(1.0, squash, 1.0))
		_merge(st, mesh, xform, palette[i % palette.size()])
	# A couple of smaller satellite lobes break up the outline.
	for i in range(2):
		var angle := rng.randf() * TAU
		var centre := Vector3(
			cos(angle) * width * 0.42,
			trunk_h + height * rng.randf_range(0.35, 0.75),
			sin(angle) * width * 0.42
		)
		var radius: float = width * rng.randf_range(0.22, 0.32)
		_merge(st, U.sphere(radius, 8, 5), Transform3D(Basis(), centre), palette[(i + 1) % palette.size()])


static func _conifer_crown(st: SurfaceTool, spec: Dictionary, palette: Array, trunk_h: float, rng: RandomNumberGenerator) -> void:
	var width: float = spec["crown_width"]
	var height: float = spec["crown_height"]
	var tiers := 5
	for i in range(tiers):
		var t := float(i) / float(tiers - 1)
		# Tiers shrink as they climb and overlap each other, giving the stepped
		# conifer outline instead of a single cone.
		var radius: float = width * lerpf(0.95, 0.22, t)
		var tier_h: float = height * lerpf(0.42, 0.3, t)
		var base_y: float = CANOPY_BOTTOM + t * (height - tier_h * 0.55)
		var centre := Vector3(0, base_y + tier_h * 0.5, 0)
		var mesh := U.cone(radius, tier_h, 8)
		var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), centre)
		_merge(st, mesh, xform, palette[i % palette.size()])
	# A short leader spike closes the silhouette.
	var top_y: float = CANOPY_BOTTOM + height
	_merge(st, U.cone(width * 0.18, height * 0.22, 6), Transform3D(Basis(), Vector3(0, top_y, 0)), palette[0])


## Merges one primitive mesh into the SurfaceTool with a baked vertex colour.
static func _merge(st: SurfaceTool, mesh: Mesh, xform: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := xform.basis.inverse().transposed()
	if indices.size() > 0:
		for i in indices:
			st.set_color(color)
			st.set_normal((normal_basis * normals[i]).normalized())
			st.add_vertex(xform * verts[i])
	else:
		for i in range(verts.size()):
			st.set_color(color)
			st.set_normal((normal_basis * normals[i]).normalized())
			st.add_vertex(xform * verts[i])


## A tapered cylinder from `from` to `to`.
static func _segment(st: SurfaceTool, from: Vector3, to: Vector3, radius_from: float, radius_to: float, segments: int, color: Color) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.0001:
		return
	var mesh := U.tapered(radius_to, radius_from, length, segments)
	var dir := delta / length
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.0001:
		axis = Vector3.RIGHT
	var basis := Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	_merge(st, mesh, Transform3D(basis, (from + to) * 0.5), color)


## A short trunk-flare cone sitting on the ground.
static func _cone(st: SurfaceTool, base: Vector3, height: float, radius: float, _unused: float, segments: int, color: Color) -> void:
	var mesh := U.cone(radius, height, segments)
	_merge(st, mesh, Transform3D(Basis(), base + Vector3(0, height * 0.5, 0)), color)
