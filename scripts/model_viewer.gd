extends Node3D
## Visor del personaje: tres copias girando (sin pintar, J1 y J2) para revisar
## el asset sin abrir el juego. Se abre con:
##   godot --path . scenes/ModelViewer.tscn

const CHEF := preload("res://assets/chef.glb")

var spinners: Array = []
var angle := 0.0
var model_ref: Node3D = null


func _ready() -> void:
	_build_environment()
	_build_floor()

	for i in 3:
		var holder := Node3D.new()
		holder.position = Vector3((i - 1) * 1.25, 0, 0)
		add_child(holder)
		spinners.append(holder)

		var model := CHEF.instantiate()
		holder.add_child(model)
		if i == 0:
			model_ref = model   # el contador mide UNA copia, no las tres
		if i > 0:
			_tint(model, GameConfig.PLAYER_COLORS[i - 1])

		var tag := Label3D.new()
		tag.text = ["ORIGINAL", "J1", "J2"][i]
		tag.font_size = 48
		tag.pixel_size = 0.004
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.outline_size = 16
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		tag.modulate = Color(1, 1, 1) if i == 0 else GameConfig.PLAYER_COLORS[i - 1]
		tag.position = Vector3((i - 1) * 1.25, 1.52, 0)
		add_child(tag)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_capture(arg.substr(7))

	var title := Label3D.new()
	title.text = "assets/chef.glb  ·  %d tris  ·  %d materiales" % [_count_tris(), _count_materials()]
	title.position.y = 1.95
	title.font_size = 40
	title.pixel_size = 0.0035
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.no_depth_test = true
	title.outline_size = 12
	title.outline_modulate = Color(0, 0, 0, 0.8)
	title.position = Vector3(0, 1.95, 0)
	add_child(title)


func _capture(path: String) -> void:
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot -> ", path)
	get_tree().quit()


func _count_tris() -> int:
	if model_ref == null:
		return 0
	var n := 0
	for node in model_ref.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			n += mesh.get_faces().size() / 3
	return int(n)


func _count_materials() -> int:
	if model_ref == null:
		return 0
	var names := {}
	for node in model_ref.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m:
					names[String(m.resource_name)] = true
	return names.size()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	key.shadow_bias = 0.06
	key.shadow_normal_bias = 1.5
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.look_at_from_position(Vector3(3.2, 2.15, 5.0), Vector3(0, 0.62, 0), Vector3.UP)


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.15, 0.18)
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)

	# discos de apoyo bajo cada copia
	for i in 3:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.42
		disc.bottom_radius = 0.42
		disc.height = 0.02
		var d := MeshInstance3D.new()
		d.mesh = disc
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.22, 0.26, 0.32)
		d.material_override = dm
		d.position = Vector3((i - 1) * 1.25, 0.011, 0)
		add_child(d)


func _tint(root: Node, color: Color) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var mat_name := String(mat.resource_name)
			if mat_name != "shirt" and mat_name != "band":
				continue
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_color = color if mat_name == "shirt" else color.darkened(0.12)
			mi.set_surface_override_material(i, dup)


func _process(delta: float) -> void:
	angle += delta * 0.35
	for holder in spinners:
		holder.rotation.y = angle - 0.35   # arranca casi de frente


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			get_tree().quit()
