extends SceneTree
func _init():
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main.start_game(1)
	await physics_frame
	var p = main.players[0]
	var casos = [
		["agua norte", 5, 2, Vector3(0, 0, -1)],
		["agua sur", 5, 11, Vector3(0, 0, 1)],
		["roca oeste", 1, 5, Vector3(-1, 0, 0)],
		["roca este", 22, 5, Vector3(1, 0, 0)],
	]
	for c in casos:
		p.teleport(c[1], c[2], Vector2i(0, 0))
		await physics_frame
		for i in 60:
			p.velocity = c[3] * 4.0
			p.move_and_slide()
			await physics_frame
		print("%-12s desde (%d,%d) -> pos (%.2f, %.2f, %.2f)  y=%.2f" % [c[0], c[1], c[2], p.position.x, p.position.y, p.position.z, p.position.y])
	quit()
