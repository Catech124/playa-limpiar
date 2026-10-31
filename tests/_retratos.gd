extends SceneTree
## Renderiza los retratos de los personajes para el menú (fondo magenta para
## recortarlo después). Uso: godot --headless=false --script tests/_retratos.gd -- 1|2

func _init():
	var idx := 1
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			idx = int(a)
	var ruta := "res://assets/kid.glb" if idx == 1 else "res://assets/mujer.glb"
	var packed := load(ruta) as PackedScene
	var world := Node3D.new()
	get_root().add_child(world)

	var model := packed.instantiate() as Node3D
	world.add_child(model)
	CharModel.fit_model(model)
	model.rotation.y = deg_to_rad(18.0)
	# el pescador trae un cangrejo pegado al modelo: en el retrato no va
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		for pre in ["brazoC", "pataC", "pinza", "ojoC", "pupC", "reborde", "pedunculo",
				"dedo-1x", "concha", "vientre"]:
			if nm.begins_with(pre):
				(mi as MeshInstance3D).visible = false
				break

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(1, 0, 1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 0.75
	env.environment = e
	world.add_child(env)

	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-38, 34, 0)
	sol.light_energy = 1.25
	world.add_child(sol)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.10
	cam.position = Vector3(0.0, 0.47, 3.0)
	world.add_child(cam)
	cam.current = true

	for i in 6:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := "/tmp/retrato%d.png" % idx
	img.save_png(out)
	print("RETRATO", out, " ", img.get_width(), "x", img.get_height())
	quit()
