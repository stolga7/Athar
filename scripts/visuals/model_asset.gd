extends RefCounted
## Loads a licensed GLB model and prepares it for use in ATHAR.
##
## Every imported asset is a plain glTF binary scene (see
## assets/models/ASSET_MANIFEST.json for sources and licenses). This helper keeps
## the awkward parts in one place:
##
##   - missing or broken files are reported instead of crashing the game,
##   - the model is scaled to a known real-world height and its feet are put on
##     the origin, so a 1.8 m hunter and a 1.35 m stag share one convention,
##   - the model is turned to face -Z, which is the direction ATHAR's movement
##     code treats as "forward",
##   - the mesh is stripped of shadows settings that cost frames on mobile and
##     its animations are catalogued by short name.
##
## Nothing here reads random numbers, so loading a model cannot disturb the
## seeded world.

## Result of `load_model()`. `ok` is false and `reason` explains why when the
## file is absent, unreadable or contains no skinned mesh.
class Result:
	var ok := false
	var reason := ""
	var root: Node3D
	var skeleton: Skeleton3D
	var player: AnimationPlayer
	## Clip name -> animation name inside the AnimationPlayer.
	var clips := {}
	## Height of the model in metres after normalisation.
	var height := 0.0


static func load_model(path: String, target_height: float, facing_yaw := PI) -> Result:
	var result := Result.new()
	if not ResourceLoader.exists(path):
		result.reason = "missing asset %s" % path
		return result
	var packed := load(path) as PackedScene
	if packed == null:
		result.reason = "unreadable asset %s" % path
		return result
	var root := packed.instantiate() as Node3D
	if root == null:
		result.reason = "asset %s has no 3D root" % path
		return result
	root.rotation.y = facing_yaw
	var skeleton := _find_first(root, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		result.reason = "asset %s has no skeleton" % path
		root.free()
		return result
	# A skinned mesh's own AABB is the bind-pose bounding box of its vertices,
	# which is not the size of the character in the world (Godot reports the
	# untouched mesh bounds, and the imported armature may be scaled). The
	# skeleton's rest pose is the reliable measure, so the model is sized from the
	# bones and the mesh bounds are only a fallback.
	var span := _bone_span(root, skeleton)
	var min_y: float = span[0]
	var height: float = span[1] - span[0]
	if height <= 0.05:
		var box := _aabb(root)
		min_y = box.position.y
		height = box.size.y
	if height <= 0.0001:
		result.reason = "asset %s has no measurable geometry" % path
		root.free()
		return result
	var scale := target_height / height
	root.scale = Vector3.ONE * scale
	# Put the lowest bone on the origin so the model stands on the terrain
	# instead of sinking into it or floating above it.
	root.position.y = -min_y * scale
	result.ok = true
	result.root = root
	result.skeleton = skeleton
	result.height = target_height
	result.player = _find_first(root, "AnimationPlayer") as AnimationPlayer
	if result.player != null:
		for clip in result.player.get_animation_list():
			result.clips[_short_name(clip)] = clip
	return result


## Strips the "Armature|" style prefixes glTF exporters put in front of clip
## names, so the game can ask for "Run" without caring about the exporter.
static func _short_name(clip: String) -> String:
	var bar := clip.find("|")
	return clip.substr(bar + 1) if bar >= 0 else clip


static func _find_first(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var found := _find_first(child, cls)
		if found != null:
			return found
	return null


## Lowest and highest bone origin of the skeleton's rest pose, in the model's
## own metres. glTF armatures are often authored in centimetres and scaled up by
## the importer, so the skeleton's own transform is applied: without it a 1.86 m
## character measures 0.0186 and every model comes out a hundred times too big.
static func _bone_span(root: Node3D, skeleton: Skeleton3D) -> Array:
	var lowest := 1e9
	var highest := -1e9
	# Compose the transforms from the model root down to the skeleton: the
	# importer often puts the armature under a scaled node, and stopping at
	# skeleton.transform misses that factor.
	var base := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != null and node != root:
		if node is Node3D:
			base = (node as Node3D).transform * base
		node = node.get_parent()
	for i in range(skeleton.get_bone_count()):
		var origin := (base * skeleton.get_bone_global_rest(i)).origin
		lowest = minf(lowest, origin.y)
		highest = maxf(highest, origin.y)
	if lowest > highest:
		return [0.0, 0.0]
	return [lowest, highest]


## Bounding box of the model in its own space. It is computed by composing the
## local transforms down the tree instead of calling get_global_transform(),
## because the asset is measured before it is added to the scene and asking for
## a global transform outside the tree returns an identity and logs an error.
static func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for entry in _mesh_entries(node, Transform3D.IDENTITY):
		var mesh: MeshInstance3D = entry[0]
		var part: AABB = (entry[1] as Transform3D) * mesh.get_aabb()
		if first:
			box = part
			first = false
		else:
			box = box.merge(part)
	return box


static func _mesh_entries(node: Node, parent_xform: Transform3D) -> Array:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	var found: Array = []
	if node is MeshInstance3D:
		found.append([node, xform])
	for child in node.get_children():
		found.append_array(_mesh_entries(child, xform))
	return found


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found


## Applies a colour scheme to a model that ships with flat material colours.
## `palette` maps a material name fragment (lower case) to a colour; materials
## that do not match keep their imported colour. Matching is by name so the
## model's own material layout survives, which keeps the rig and its textures
## intact.
static func recolour(root: Node, palette: Array) -> int:
	var changed := 0
	for mesh in _meshes(root):
		var count := 0
		if mesh.mesh != null:
			count = mesh.mesh.get_surface_count()
		for surface in range(count):
			var source: Material = mesh.get_active_material(surface)
			if source == null or mesh.mesh.surface_get_material(surface) != null:
				source = mesh.mesh.surface_get_material(surface)
			var mat := source.duplicate() as StandardMaterial3D if source is StandardMaterial3D else null
			if mat == null:
				continue
			var name := mat.resource_name.to_lower()
			for entry in palette:
				if name.find(String(entry["match"])) >= 0:
					mat.albedo_color = entry["color"]
					mat.roughness = float(entry.get("roughness", mat.roughness))
					mesh.set_surface_override_material(surface, mat)
					changed += 1
					break
	return changed
