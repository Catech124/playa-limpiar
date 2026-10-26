extends SceneTree
func _init():
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main.start_game(1)
	await physics_frame
	var p = main.players[0]
	print("tiles: (0,2)=", main.world.tile_at(0,2).kind, " sólido=", main.world.tile_at(0,2).is_solid())
	p.teleport(1, 2, Vector2i(-1, 0))
	await physics_frame
	print("inicio: ", p.position, " y=", p.position.y)
	for i in 60:
		p.velocity = Vector3(-4.0, 0.0, 0.0)
		p.move_and_slide()
		await physics_frame
	print("tras empujar: ", p.position, "  on_floor=", p.is_on_floor(), " on_wall=", p.is_on_wall())
	# ¿cuántos colliders hay y de qué tamaño?
	var n = 0
	for c in main.world.colliders.get_children():
		n += 1
		if n <= 3:
			var cs = c.get_child(0)
			print("  collider en ", c.position, " shape ", cs.shape.size if cs.shape is BoxShape3D else "?")
	print("colliders totales: ", n)
	quit()
