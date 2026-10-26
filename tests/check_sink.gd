extends SceneTree
func _init():
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main.start_game(1)
	await physics_frame
	var p = main.players[0]
	var t = main.world.tile_at(14, 2)
	print("estación en (14,2): ", t.station)
	var dirty = CarryItem.bag(false)
	ItemVisuals.build(dirty)
	main.move_item_to_player(dirty, p)
	p.teleport(14, 3, Vector2i(0, -1))
	await physics_frame
	print("frente: ", p.front_tile().station)
	main.player_use(p, p.front_tile())
	print("tras dejar: cargando=", p.carrying, " items=", t.items.size())
	for i in 120:
		await physics_frame
		if t.items.size() > 0 and t.items[0].clean: break
	var states := []
	for it in t.items:
		states.append(it.clean)
	print("tras lavar: items=", t.items.size(), " clean=", states)
	main.player_use(p, p.front_tile())
	print("tras retirar: cargando=", p.carrying, " es bolsa=", p.carrying.is_bag() if p.carrying else false, " limpia=", p.carrying.clean if p.carrying else false)
	quit()
