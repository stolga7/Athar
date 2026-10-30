extends Node3D

# ATHAR vertical slice: procedural wilderness, touch controls, hunter and reactive deer.
const WORLD_SIZE := 90.0
var hunter: CharacterBody3D
var deer: CharacterBody3D
var camera: Camera3D
var status_label: Label
var info_label: Label
var move_vector := Vector2.ZERO
var captured := false
var deer_state := "Grazing"
var stamina := 100.0
var hunt_button: Button

func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_world()
	_build_hunter()
	_build_deer()
	_build_camera()
	_build_hud()
	_update_status("Find the deer. Move quietly through the forest.")

func _setup_input() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if not InputMap.has_action(action): InputMap.add_action(action)

func _mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _mesh_node(parent: Node, mesh: Mesh, material: Material, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material
	n.position = pos
	n.scale = scale
	parent.add_child(n)
	return n

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.19, 0.22)
	sky_mat.sky_horizon_color = Color(0.62, 0.58, 0.42)
	sky_mat.ground_bottom_color = Color(0.07, 0.10, 0.07)
	sky_mat.ground_horizon_color = Color(0.30, 0.34, 0.23)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.60)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.48, 0.53, 0.42)
	e.fog_density = 0.006
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color(1.0, 0.83, 0.62)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

func _build_world() -> void:
	var ground_body := StaticBody3D.new()
	ground_body.name = "ForestGround"
	add_child(ground_body)
	var ground := _mesh_node(ground_body, PlaneMesh.new(), _mat(Color(0.16, 0.22, 0.13)), Vector3.ZERO, Vector3(WORLD_SIZE, 1, WORLD_SIZE))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WORLD_SIZE, 1, WORLD_SIZE)
	cs.shape = box
	cs.position.y = -0.55
	ground_body.add_child(cs)
	# Fern-like ground patches and stones.
	for i in range(75):
		var x := randf_range(-42, 42)
		var z := randf_range(-42, 42)
		if Vector2(x, z).length() < 5.5: continue
		var stone_mesh := SphereMesh.new()
		stone_mesh.radius = randf_range(0.18, 0.48)
		stone_mesh.height = stone_mesh.radius * 1.1
		_mesh_node(self, stone_mesh, _mat(Color(0.25, 0.28, 0.23)), Vector3(x, 0.05, z), Vector3(1.4, 0.55, 1.0))
	# Procedural trees around a playable clearing.
	for i in range(95):
		var angle := randf() * TAU
		var radius := randf_range(13, 43)
		var p := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if abs(p.x) < 5 and abs(p.z) < 7: continue
		_create_tree(p, randf_range(0.8, 1.35))
	# A small ruined stone arch gives the clearing a landmark.
	_create_ruin(Vector3(-10, 0, -15))

func _create_tree(p: Vector3, s: float) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22 * s
	trunk.bottom_radius = 0.38 * s
	trunk.height = 3.4 * s
	_mesh_node(self, trunk, _mat(Color(0.20, 0.12, 0.075)), p + Vector3(0, 1.7 * s, 0))
	for j in range(3):
		var crown := SphereMesh.new()
		crown.radius = 1.65 * s * (1.0 - j * 0.13)
		crown.height = 2.5 * s
		var green: Color = [Color(0.10, 0.23, 0.15), Color(0.13, 0.29, 0.17), Color(0.18, 0.32, 0.19)][randi_range(0, 2)]
		_mesh_node(self, crown, _mat(green), p + Vector3(0, (3.1 + j * 0.65) * s, 0), Vector3(1, 0.82, 1))

func _create_ruin(p: Vector3) -> void:
	var stone := _mat(Color(0.34, 0.34, 0.28))
	for x in [-2.2, 2.2]:
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.8, 4.2, 0.9)
		_mesh_node(self, pillar, stone, p + Vector3(x, 2.1, 0))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(5.2, 0.8, 1.0)
	_mesh_node(self, lintel, stone, p + Vector3(0, 4.2, 0))

func _build_hunter() -> void:
	hunter = CharacterBody3D.new()
	hunter.name = "Hunter"
	hunter.position = Vector3(0, 0.1, 7)
	add_child(hunter)
	var body := CapsuleMesh.new()
	body.radius = 0.42
	body.height = 1.65
	_mesh_node(hunter, body, _mat(Color(0.12, 0.18, 0.17)), Vector3(0, 1.0, 0))
	var head := SphereMesh.new()
	head.radius = 0.31
	_mesh_node(hunter, head, _mat(Color(0.64, 0.48, 0.32)), Vector3(0, 2.0, 0))
	var hood := SphereMesh.new()
	hood.radius = 0.36
	_mesh_node(hunter, hood, _mat(Color(0.09, 0.12, 0.11)), Vector3(0, 2.12, -0.05), Vector3(1.0, 0.65, 1.0))
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 2.0
	collider.shape = shape
	collider.position.y = 1.0
	hunter.add_child(collider)

func _build_deer() -> void:
	deer = CharacterBody3D.new()
	deer.name = "WildDeer"
	deer.position = Vector3(4.5, 0.1, -5.0)
	add_child(deer)
	var brown := _mat(Color(0.48, 0.27, 0.13))
	var cream := _mat(Color(0.78, 0.66, 0.45))
	var body := SphereMesh.new()
	body.radius = 0.72
	_mesh_node(deer, body, brown, Vector3(0, 1.05, 0), Vector3(1.45, 0.78, 0.72))
	var neck := CapsuleMesh.new()
	neck.radius = 0.23
	neck.height = 0.95
	_mesh_node(deer, neck, brown, Vector3(0, 1.55, -0.48), Vector3(0.85, 1, 0.85))
	var head := SphereMesh.new()
	head.radius = 0.34
	_mesh_node(deer, head, brown, Vector3(0, 1.92, -0.82), Vector3(0.9, 0.85, 1.1))
	var muzzle := SphereMesh.new()
	muzzle.radius = 0.17
	_mesh_node(deer, muzzle, cream, Vector3(0, 1.82, -1.08), Vector3(1, 0.7, 1))
	for x in [-0.43, 0.43]:
		for z in [-0.42, 0.42]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.075
			leg.bottom_radius = 0.055
			leg.height = 0.85
			_mesh_node(deer, leg, _mat(Color(0.25,0.16,0.10)), Vector3(x, 0.43, z))
	var antler_mat := _mat(Color(0.72, 0.64, 0.43))
	for side in [-1, 1]:
		var antler := CylinderMesh.new()
		antler.top_radius = 0.025
		antler.bottom_radius = 0.055
		antler.height = 0.75
		var a := _mesh_node(deer, antler, antler_mat, Vector3(side * 0.22, 2.36, -0.75))
		a.rotation.z = deg_to_rad(side * -28)
	var c := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.55
	cs.height = 1.8
	c.shape = cs
	c.position.y = 0.95
	deer.add_child(c)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "GameCamera"
	camera.current = true
	camera.fov = 65
	add_child(camera)
	camera.global_position = hunter.global_position + Vector3(0, 6.5, 9.5)
	camera.look_at(hunter.global_position + Vector3(0, 1.0, 0), Vector3.UP)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var title := Label.new()
	title.text = "ATHAR  |  WILDLANDS"
	title.position = Vector2(26, 18)
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.91, 0.78, 0.48))
	root.add_child(title)
	status_label = Label.new()
	status_label.position = Vector2(28, 58)
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.84))
	root.add_child(status_label)
	info_label = Label.new()
	info_label.text = "STAMINA 100%   •   FOREST REGION"
	info_label.position = Vector2(28, 88)
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color(0.64, 0.82, 0.72))
	root.add_child(info_label)
	_add_hold_button(root, "▲", Vector2(112, -184), "move_forward")
	_add_hold_button(root, "▼", Vector2(112, -64), "move_back")
	_add_hold_button(root, "◀", Vector2(52, -124), "move_left")
	_add_hold_button(root, "▶", Vector2(172, -124), "move_right")
	hunt_button = Button.new()
	hunt_button.text = "HUNT / TRACK"
	hunt_button.position = Vector2(-210, -105)
	hunt_button.size = Vector2(180, 66)
	hunt_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hunt_button.add_theme_font_size_override("font_size", 19)
	hunt_button.add_theme_color_override("font_color", Color(0.98, 0.88, 0.63))
	hunt_button.add_theme_stylebox_override("normal", _button_style(Color(0.20, 0.27, 0.19, 0.94)))
	hunt_button.add_theme_stylebox_override("pressed", _button_style(Color(0.42, 0.30, 0.13, 0.98)))
	hunt_button.pressed.connect(_on_hunt_pressed)
	root.add_child(hunt_button)
	var hint := Label.new()
	hint.text = "Move with the left controls • Approach slowly • Track the deer"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -32)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.86, 0.86, 0.76))
	root.add_child(hint)

func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(0.68, 0.59, 0.35, 0.8)
	s.set_border_width_all(2)
	s.set_corner_radius_all(18)
	return s

func _add_hold_button(parent: Control, caption: String, offset: Vector2, action: String) -> void:
	var b := Button.new()
	b.text = caption
	b.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	b.position = offset
	b.size = Vector2(58, 58)
	b.add_theme_font_size_override("font_size", 25)
	b.add_theme_color_override("font_color", Color(0.96, 0.91, 0.75))
	b.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.19, 0.16, 0.88)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.35, 0.34, 0.20, 0.98)))
	b.button_down.connect(func(): Input.action_press(action))
	b.button_up.connect(func(): Input.action_release(action))
	parent.add_child(b)

func _physics_process(delta: float) -> void:
	if hunter == null or deer == null: return
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): dir.z -= 1
	if Input.is_action_pressed("move_back"): dir.z += 1
	if Input.is_action_pressed("move_left"): dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	if dir.length() > 0:
		dir = dir.normalized()
		hunter.velocity.x = dir.x * 4.0
		hunter.velocity.z = dir.z * 4.0
		hunter.rotation.y = lerp_angle(hunter.rotation.y, atan2(-dir.x, -dir.z), delta * 8.0)
		stamina = maxf(0, stamina - delta * 2.5)
	else:
		hunter.velocity.x = move_toward(hunter.velocity.x, 0, 18 * delta)
		hunter.velocity.z = move_toward(hunter.velocity.z, 0, 18 * delta)
		stamina = minf(100, stamina + delta * 5.0)
	hunter.velocity.y -= 20.0 * delta
	hunter.move_and_slide()
	hunter.global_position.x = clampf(hunter.global_position.x, -43, 43)
	hunter.global_position.z = clampf(hunter.global_position.z, -43, 43)
	_update_deer(delta)
	camera.global_position = camera.global_position.lerp(hunter.global_position + Vector3(0, 6.2, 9.0).rotated(Vector3.UP, hunter.rotation.y), delta * 3.5)
	camera.look_at(hunter.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	info_label.text = "STAMINA %d%%   •   %s" % [int(stamina), "FOREST REGION"]

func _update_deer(delta: float) -> void:
	if captured: return
	var to_hunter := hunter.global_position - deer.global_position
	var distance := to_hunter.length()
	if distance < 8.0 and deer_state != "Fleeing":
		deer_state = "Fleeing"
		_update_status("The deer sensed you and is fleeing!")
	if deer_state == "Fleeing":
		var flee := -to_hunter.normalized()
		deer.velocity.x = flee.x * 5.4
		deer.velocity.z = flee.z * 5.4
		deer.rotation.y = lerp_angle(deer.rotation.y, atan2(-flee.x, -flee.z), delta * 5)
		if distance > 19:
			deer_state = "Grazing"
	else:
		deer.velocity.x = move_toward(deer.velocity.x, 0, delta * 3)
		deer.velocity.z = move_toward(deer.velocity.z, 0, delta * 3)
	deer.velocity.y -= 20 * delta
	deer.move_and_slide()
	deer.global_position.x = clampf(deer.global_position.x, -42, 42)
	deer.global_position.z = clampf(deer.global_position.z, -42, 42)

func _on_hunt_pressed() -> void:
	if captured: return
	var distance := hunter.global_position.distance_to(deer.global_position)
	if distance <= 2.6:
		captured = true
		deer.visible = false
		_update_status("Successful capture! The deer is secured. First hunt complete.")
		hunt_button.text = "CAPTURED"
	else:
		_update_status("Too far away (%dm). Follow the deer tracks and approach quietly." % int(distance))

func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message
