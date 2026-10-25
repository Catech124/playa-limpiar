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
