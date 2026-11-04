extends RefCounted
## Ground surface and ground clutter for the ATHAR wilderness.
##
## The prototype ground was one flat olive-coloured plane, which read as a test
## map: no scale cue, no variation, and nothing to separate near ground from far.
##
## This builder keeps the same single collision slab (so movement and the
## checksum-relevant world stay put) but gives it:
##
##   * a seamless procedural albedo texture blending moss, soil and dry grass,
##   * a matching detail normal map so the light breaks across the surface,
##   * tuned roughness so the ground is matte rather than plastic,
##   * stones and grass tufts as two MultiMesh batches, which is two draw calls
##     for hundreds of props instead of one node each.
##
## Textures come from FastNoiseLite with a fixed seed: no downloaded assets, and
## no effect on the world's deterministic seeding.

## Collision slab and detailed surface: the playable world.
const WORLD_SIZE := 90.0
## A wider backdrop sits just under the detailed surface so the horizon never
## shows sky beneath the ground when the camera looks to the edge.
const BACKDROP_SIZE := 320.0
const NOISE_SEED := 1337

const ALBEDO_TILE := 26.0
const NORMAL_TILE := 58.0

const GROUND_DARK := Color(0.062, 0.082, 0.054)
const GROUND_MOSS := Color(0.086, 0.112, 0.070)
const GROUND_GRASS := Color(0.108, 0.138, 0.082)
const GROUND_DRY := Color(0.140, 0.142, 0.094)

const STONE_COUNT := 70
const TUFT_COUNT := 620

const WIND_SHADER := preload("res://shaders/vegetation_wind.gdshader")
## Grass sways much more than a trunk, and from the ground up.
const TUFT_WIND_STRENGTH := 0.075
const TUFT_WIND_SPEED := 1.5

const TUFT_BASE := Color(0.088, 0.132, 0.068)
const TUFT_TIP := Color(0.158, 0.216, 0.108)


## Merges a region palette over the silver-forest defaults, so a caller that
## passes nothing gets exactly the Phase 3.1 ground and a region only overrides
## what gives it its identity.
static func palette_colors(palette: Dictionary) -> Dictionary:
	return {
		"dark": palette.get("dark", GROUND_DARK),
		"moss": palette.get("moss", GROUND_MOSS),
		"grass": palette.get("grass", GROUND_GRASS),
		"dry": palette.get("dry", GROUND_DRY),
		"backdrop": palette.get("backdrop", GROUND_MOSS.darkened(0.15)),
		"roughness": float(palette.get("roughness", 0.96)),
		"stone": palette.get("stone", Color(0.22, 0.25, 0.21)),
		"tuft_base": palette.get("tuft_base", TUFT_BASE),
		"tuft_tip": palette.get("tuft_tip", TUFT_TIP),
		"tuft_count": int(palette.get("tuft_count", TUFT_COUNT)),
		"stone_count": int(palette.get("stone_count", STONE_COUNT)),
		"noise_seed": int(palette.get("noise_seed", NOISE_SEED)),
	}


## Adds the ground body, its surface and the clutter, and returns a summary.
static func build(parent: Node3D, rng: RandomNumberGenerator, palette := {}) -> Dictionary:
	var colors := palette_colors(palette)
	var ground_body := StaticBody3D.new()
	ground_body.name = "ForestGround"
	parent.add_child(ground_body)

	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)

	var ground := MeshInstance3D.new()
	ground.name = "GroundSurface"
	ground.mesh = plane
	ground.material_override = _ground_material(colors)
	ground.scale = Vector3.ONE
	ground_body.add_child(ground)

	var box := BoxShape3D.new()
	box.size = Vector3(WORLD_SIZE, 1.0, WORLD_SIZE)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.y = -0.55
	ground_body.add_child(collider)

	# The backdrop: one untextured plane far wider than the playable area.
	var backdrop := MeshInstance3D.new()
	backdrop.name = "GroundBackdrop"
	var backdrop_plane := PlaneMesh.new()
	backdrop_plane.size = Vector2(BACKDROP_SIZE, BACKDROP_SIZE)
	backdrop.mesh = backdrop_plane
	var backdrop_mat := StandardMaterial3D.new()
	backdrop_mat.albedo_color = (colors["backdrop"] as Color)
	backdrop_mat.roughness = 1.0
	backdrop.material_override = backdrop_mat
	backdrop.position.y = -0.05
	parent.add_child(backdrop)

	var stones := _stone_batch(parent, rng, colors)
	var tufts := _tuft_batch(parent, rng, colors)

	return {
		"ground_body": ground_body,
		"ground_surface": ground,
		"material": ground.material_override,
		"stone_count": stones,
		"tuft_count": int(tufts["count"]),
		"tuft_material": tufts["material"],
		"node_count": 3,
	}


static func _ground_material(colors: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = _albedo_texture(colors)
	mat.normal_enabled = true
	mat.normal_texture = _normal_texture()
	mat.normal_scale = 0.65
	mat.roughness = float(colors["roughness"])
	mat.metallic_specular = 0.18
	mat.uv1_scale = Vector3(ALBEDO_TILE, ALBEDO_TILE, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


static func _albedo_texture(colors: Dictionary) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = int(colors["noise_seed"])
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6
	noise.fractal_gain = 0.6

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.34, 0.62, 0.85, 1.0])
	var dark: Color = colors["dark"]
	var moss: Color = colors["moss"]
	var grass: Color = colors["grass"]
	var dry: Color = colors["dry"]
	ramp.colors = PackedColorArray([
		dark,
		moss,
		grass,
		dry,
		grass.lerp(dry, 0.65),
	])

	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


static func _normal_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED + 7
	noise.frequency = 0.05
	noise.fractal_octaves = 3

	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 2.4
	tex.noise = noise
	return tex


## Scattered low-poly stones: one batch, no collision, sat just above the ground.
static func _stone_batch(parent: Node3D, rng: RandomNumberGenerator, colors: Dictionary) -> int:
	var mesh := _mossy_mesh(0.34, 8, 5, colors["stone"])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var transforms: Array[Transform3D] = []
	var attempts := 0
	var wanted := int(colors["stone_count"])
	while transforms.size() < wanted and attempts < wanted * 20:
		attempts += 1
		var x := rng.randf_range(-42.0, 42.0)
		var z := rng.randf_range(-42.0, 42.0)
		if Vector2(x, z).length() < 6.0:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3(rng.randf_range(0.6, 1.5), rng.randf_range(0.35, 0.6), rng.randf_range(0.7, 1.4)))
		transforms.append(Transform3D(basis, Vector3(x, 0.05, z)))
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stones"
	mmi.multimesh = mm
	parent.add_child(mmi)
	return transforms.size()


## Grass clumps: three crossed tapered blades per tuft, one MultiMesh batch, no
## shadows and no collision. They are ground detail at knee height; the wind
## shader gives them the strongest sway in the scene because they are lightest.
static func _tuft_batch(parent: Node3D, rng: RandomNumberGenerator, colors: Dictionary) -> Dictionary:
	var mesh := _tuft_mesh(colors["tuft_base"], colors["tuft_tip"])
	var material := ShaderMaterial.new()
	mesh.surface_set_material(0, material)
	material.shader = WIND_SHADER
	material.set_shader_parameter("wind_strength", TUFT_WIND_STRENGTH)
	material.set_shader_parameter("wind_speed", TUFT_WIND_SPEED)
	material.set_shader_parameter("sway_start", 0.02)
	material.set_shader_parameter("sway_span", 0.55)
	material.set_shader_parameter("base_roughness", 0.96)
	material.set_shader_parameter("specular_amount", 0.05)
	material.set_shader_parameter("use_vertex_color", true)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var transforms: Array[Transform3D] = []
	var wanted := int(colors["tuft_count"])
	while transforms.size() < wanted:
		var x := rng.randf_range(-44.0, 44.0)
		var z := rng.randf_range(-44.0, 44.0)
		# Keep the hunter's spawn pocket and the ruin courtyard tidy.
		if Vector2(x, z - 7.0).length() < 3.0:
			continue
		if Vector2(x + 10.0, z + 15.0).length() < 3.5:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var s := rng.randf_range(0.75, 1.45)
		basis = basis.scaled(Vector3(s, rng.randf_range(0.8, 1.3), s))
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassTufts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return {"count": transforms.size(), "material": material}


## One tuft: three tapered quads crossed at 60 degrees, dark at the root and
## greener at the tip so the clump reads as grass rather than a spike.
static func _tuft_mesh(bottom: Color, top: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(3):
		var angle := float(blade) * PI / 3.0 + 0.35
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.048
		var lean := dir * 0.05
		var base := -side
		var base_r := side
		var tip_l := -side * 0.35 + lean + Vector3(0, 0.235, 0)
		var tip_r := side * 0.35 + lean + Vector3(0, 0.235, 0)
		_quad(st, base, base_r, tip_r, tip_l, bottom, top)
	st.generate_normals()
	return st.commit()


## `a`/`b` are the root corners, `c`/`d` the tip corners.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, bottom: Color, top: Color) -> void:
	st.set_color(bottom)
	st.add_vertex(a)
	st.set_color(bottom)
	st.add_vertex(b)
	st.set_color(top)
	st.add_vertex(c)
	st.set_color(bottom)
	st.add_vertex(a)
	st.set_color(top)
	st.add_vertex(c)
	st.set_color(top)
	st.add_vertex(d)


static func _mossy_mesh(radius: float, segments: int, rings: int, color: Color) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.4
	mesh.radial_segments = segments
	mesh.rings = rings
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.94
	mesh.material = mat
	return mesh
