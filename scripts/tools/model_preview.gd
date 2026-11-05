extends Node3D
## Development tool: renders an imported GLB model from several angles and
## prints its bounding box, skeleton and animation clip list.
##
## Usage (a display is required; it renders, it does not run headless):
##   godot --path . res://scenes/tools/model_preview.tscn -- \
##       --model res://assets/models/animals/stag.glb --tag stag
## Every frame it renders one view and saves it to res://artifacts/.

const VIEWS := [
	{"name": "front", "yaw": 180.0},
	{"name": "three_quarter", "yaw": 225.0},
	{"name": "side", "yaw": 270.0},
	{"name": "back", "yaw": 0.0},
]

var _model_path := "res://assets/models/characters/adventurer.glb"
var _tag := "model"
var _animation := ""
var _frame := 0
var _wait := 0
var _camera: Camera3D
var _shots := 0
## Bounding box of the imported model only (the ground plane is excluded).
var _model_box := AABB()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			_model_path = arg.trim_prefix("--model=")
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--anim="):
			_animation = arg.trim_prefix("--anim=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	_build_stage()
	var instance := _spawn()
	if instance == null:
		get_tree().quit(1)
		return
	_model_box = _aabb(instance)
	_place_camera(instance)
	_print_report(instance)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -140, 0)
	fill.light_energy = 0.55
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.16)
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.current = true
	add_child(_camera)


func _spawn() -> Node3D:
	if not ResourceLoader.exists(_model_path):
		push_error("MODEL_MISSING %s" % _model_path)
		return null
	var packed := load(_model_path) as PackedScene
	if packed == null:
		push_error("MODEL_UNLOADABLE %s" % _model_path)
		return null
	var instance := packed.instantiate() as Node3D
	add_child(instance)
	return instance


func _place_camera(instance: Node3D) -> void:
	var aabb := _model_box
	var centre := aabb.get_center()
	var extent: float = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z))
	_camera.position = centre + Vector3(0, extent * 0.12, extent * 1.9)
	_camera.look_at(centre, Vector3.UP)
	print("MODEL_AABB pos=%s size=%s" % [aabb.position, aabb.size])


func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in _mesh_instances(node):
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found


func _print_report(instance: Node3D) -> void:
	print("MODEL_PATH %s" % _model_path)
	var skeletons := _find_all(instance, "Skeleton3D")
	for skeleton in skeletons:
		print("SKELETON %s bones=%d" % [skeleton.name, skeleton.get_bone_count()])
	var players := _find_all(instance, "AnimationPlayer")
	for player in players:
		var names: PackedStringArray = player.get_animation_list()
		print("ANIMATIONS %d %s" % [names.size(), ", ".join(names)])
		if _animation != "" and player.has_animation(_animation):
			player.play(_animation)
	var meshes := _mesh_instances(instance)
	print("MESH_INSTANCES %d" % meshes.size())


func _find_all(node: Node, cls: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(cls):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, cls))
	return found


func _process(_delta: float) -> void:
	_wait += 1
	if _wait < 8:
		return
	_wait = 0
	if _shots >= VIEWS.size():
		print("MODEL_CAPTURE_DONE %s" % _tag)
		get_tree().quit(0)
		return
	var view: Dictionary = VIEWS[_shots]
	_rotate_camera(float(view["yaw"]))
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://artifacts/model_%s_%s.png" % [_tag, view["name"]]
	image.save_png(ProjectSettings.globalize_path(path))
	print("MODEL_SHOT %s" % path)
	_shots += 1


func _rotate_camera(yaw_degrees: float) -> void:
	var aabb := _model_box
	var centre := aabb.get_center()
	centre.y = aabb.position.y + maxf(aabb.size.y * 0.5, 0.6)
	var distance := maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z)) * 1.85
	var dir := Vector3(sin(deg_to_rad(yaw_degrees)), 0.18, cos(deg_to_rad(yaw_degrees))).normalized()
	_camera.position = centre + dir * distance
	_camera.look_at(centre, Vector3.UP)
