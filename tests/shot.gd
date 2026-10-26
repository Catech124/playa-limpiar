extends Node
## Captura un frame del juego para verificación visual (necesita un display):
##   xvfb-run -a godot --path . -- --shot=/tmp/x.png --demo

var main
var out_path := "/tmp/playa.png"


func _ready() -> void:
	await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			out_path = a.substr(7)

	if "--menu" in args:
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_path)
		print("shot -> ", out_path)
		get_tree().quit()
		return

	if "--results" in args:
		main.start_game(1)
		await get_tree().process_frame
		main.score = 340
		main.stats["served"] = 6
		main.stats["expired"] = 2
		main.stats["thrown"] = 3
		main.time_left = 0.05
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_path)
		print("shot -> ", out_path)
		get_tree().quit()
		return

	if "--closeup" in args:
		main.start_game(2)
		await get_tree().process_frame
		main.orders.spawn()
		main.players[0].teleport(11, 7, Vector2i(0, -1))
		main.players[1].teleport(13, 7, Vector2i(0, 1))
		main.camera.fov = 30.0
		main.camera.look_at_from_position(Vector3(12.0, 3.2, 11.4), Vector3(12.0, 0.7, 7.4), Vector3.UP)
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_path)
		print("shot -> ", out_path)
		get_tree().quit()
		return

	if "--facing" in args:
		# mira la cámara: sirve para verificar que el personaje NO camina de espaldas
		main.start_game(2)
		await get_tree().process_frame
		main.players[0].teleport(10, 9, Vector2i(0, 1))
		main.players[1].teleport(13, 9, Vector2i(1, 0))
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_path)
		print("shot -> ", out_path)
		get_tree().quit()
		return

	if "--demo" in args or "--demo2" in args:
		main.start_game(2 if "--demo2" in args else 1)
		await get_tree().process_frame
		main.orders.spawn()
		main.orders.spawn()
		main.orders.spawn()

		var world: GridWorld = main.world
		# bolsa a medio llenar en el mostrador
		var bag := CarryItem.bag(true, ["pet", "lata"])
		ItemVisuals.build(bag)
		main.move_item_to_tile(bag, world.tile_at(12, 5))
		# residuo clasificado esperando
		var res := CarryItem.residue("vidrio")
		res.classified = true
		ItemVisuals.build(res)
		main.move_item_to_tile(res, world.tile_at(13, 6))
		# residuo crudo tirado en la arena
		var raw := CarryItem.residue("pet")
		ItemVisuals.build(raw)
		main.move_item_to_tile(raw, world.tile_at(14, 8))
		# jugador clasificando (barra a medias)
		var p: Player = main.players[0]
		p.teleport(6, 3, Vector2i(0, 1))
		var held := CarryItem.residue("lata")
		held.progress = 0.62
		ItemVisuals.build(held)
		main.move_item_to_player(held, p)

		if main.players.size() > 1:
			var p2: Player = main.players[1]
			p2.teleport(10, 11, Vector2i(0, 1))
			var bag2 := CarryItem.bag(false)
			ItemVisuals.build(bag2)
			main.move_item_to_player(bag2, p2)

	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("shot -> ", out_path)
	get_tree().quit()
