extends SceneTree
func _init():
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main.start_game(2)
	await physics_frame
	await physics_frame
	var a = main.players[0]
	var b = main.players[1]
	a.teleport(5, 10, Vector2i(1, 0))
	b.teleport(6, 10, Vector2i(1, 0))
	await physics_frame
	print("posiciones: ", a.position, " / ", b.position)
	var d0: float = a.position.distance_to(b.position)
	for i in 30:
		a.velocity = Vector3(4, 0, 0)
		a.move_and_slide()
		await physics_frame
	print("jugador vs jugador: %.2f -> %.2f" % [d0, a.position.distance_to(b.position)])
	quit()
