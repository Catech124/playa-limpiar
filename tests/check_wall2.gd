extends SceneTree
func _init():
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main.start_game(1)
	await physics_frame
	var p = main.players[0]
	# ¿qué hay en (5,1)? agua. Ver su collider
	var t = main.world.tile_at(5, 1)
	print("tile (5,1): ", t.kind, " sólido=", t.is_solid())
	for c in main.world.colliders.get_children():
		if abs(c.position.x - 5.5) < 0.1 and abs(c.position.z - 1.5) < 0.1:
			var sh = c.get_child(0).shape
			print("  collider agua en ", c.position, " tamaño ", sh.size)
	p.teleport(5, 2, Vector2i(0, -1))
	await physics_frame
	for i in 40:
		p.velocity = Vector3(0, 0, -4.0)
		p.move_and_slide()
		await physics_frame
		if i % 8 == 0:
			print("  frame %d: y=%.2f z=%.2f" % [i, p.position.y, p.position.z])
	print("final: ", p.position)
	quit()
