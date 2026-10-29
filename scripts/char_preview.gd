extends Node3D
## Vista previa del personaje, sin cargar el juego: sirve para iterar el modelo
## en un render de ~3 s.
##
##   xvfb-run -a godot --path . scenes/CharPreview.tscn -- --out=/tmp/char.png [--npc] [--side]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "/tmp/char-preview.png"
	for a in args:
		if a.begins_with("--out="):
			out_path = a.substr(6)

	var shirt := Color(0.95, 0.82, 0.31)
	var hat := "cap" if "--npc" in args else "straw"
	var model := CharModel.build(shirt, hat)
	add_child(model)

	# luz y cielo parecidos a los del juego
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.17, 0.40, 0.68)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.88)
	sky_mat.ground_bottom_color = Color(0.10, 0.28, 0.40)
	sky_mat.ground_horizon_color = Color(0.72, 0.82, 0.88)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.70, 0.80)
	e.ambient_light_energy = 0.40
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -42, 0)
	sun.light_energy = 0.75
	add_child(sun)

	# piso de arena para ver la sombra de contacto
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 1.4
	floor_mesh.bottom_radius = 1.4
	floor_mesh.height = 0.02
	floor_mesh.radial_segments = 32
	var fm := MeshInstance3D.new()
	fm.mesh = floor_mesh
	fm.material_override = ItemVisuals.material(Color(0.87, 0.74, 0.50))
	fm.position = Vector3(0, -0.01, 0)
	add_child(fm)

	var cam := Camera3D.new()
	cam.fov = 26.0
	add_child(cam)
	var side := "--side" in args
	var eye := Vector3(1.9, 0.62, 2.3) if side else Vector3(0.0, 0.55, 2.4)
	if side:
		cam.look_at_from_position(eye, Vector3(0.0, 0.42, 0.0), Vector3.UP)
	else:
		cam.look_at_from_position(eye, Vector3(0.0, 0.40, 0.0), Vector3.UP)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("preview -> ", out_path)
	get_tree().quit()
