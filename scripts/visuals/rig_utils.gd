extends RefCounted
## Shared helpers for the procedural character rigs.
##
## ATHAR ships no imported 3D models, so the hunter and the deer are assembled
## from Godot primitive meshes at runtime. These helpers keep that code short
## and keep the number of materials small: every part that shares a colour and
## roughness shares one StandardMaterial3D instance, which matters on mobile
## where each extra material is another draw-call state change.

## Returns a cached StandardMaterial3D for a colour/roughness/metallic triple.
static func material(cache: Dictionary, color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), roughness, metallic]
	if cache.has(key):
		return cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	cache[key] = m
	return m


## A faintly glowing accent material (used for the single cyan detail).
static func glow(cache: Dictionary, color: Color, energy := 1.4) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if cache.has(key):
		return cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	cache[key] = m
	return m


## Adds a mesh instance to `parent` and returns it.
static func part(parent: Node3D, mesh: Mesh, material: Material, position := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material
	n.position = position
	n.scale = scale
	parent.add_child(n)
	return n


## Adds an empty Node3D used as an animated joint and returns it.
static func pivot(parent: Node3D, name: String, position: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = position
	parent.add_child(n)
	return n


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func sphere(radius: float, segments := 12, rings := 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 10
	m.rings = 4
	return m


## A tapered cylinder: use equal radii for a limb, or top 0 for a cone.
static func tapered(top_radius: float, bottom_radius: float, height: float, segments := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func cone(radius: float, height: float, segments := 10) -> CylinderMesh:
	return tapered(0.0, radius, height, segments)


## A thin cylinder spanning two local points, used for antler beams, tines and
## the bow limbs. Returns the mesh instance, so callers can keep animating it.
static func strut(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var delta := to - from
	var length := delta.length()
	var mesh := tapered(radius, radius, maxf(length, 0.001), 6)
	var node := part(parent, mesh, material, (from + to) * 0.5)
	if length < 0.0001:
		return node
	# CylinderMesh runs along +Y; aim that axis along the segment.
	var dir := delta / length
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.0001:
		axis = Vector3.RIGHT
	var t := node.transform
	t.basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	node.transform = t
	return node
