extends Node
## Captura un frame del juego para verificación visual (necesita un display):
##   xvfb-run -a godot --path . -- --shot=/tmp/x.png --demo
##
## Modos: --demo, --demo2 (co-op), --menu, --results (derrota), --win,
##        --facing, --carry, --closeup.

var main
var out_path := "/tmp/playa.png"


func _ready() -> void:
	await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			out_path = a.substr(7)

	if "--menu" in args:
		await _shoot(0.8)
		return

	if "--results" in args or "--win" in args:
		main.start_game(1)
		await get_tree().process_frame
		main.delivered = {"pet": 3, "vidrio": 2, "lata": 1}
		main.stats["delivered"] = 6
		if "--win" in args:
			main.delivered = {"pet": 6, "vidrio": 4, "lata": 4}
			main.stats["delivered"] = 14
			main.time_left = main.level_seconds * 0.42
		else:
			main.time_left = 0.05
		await _shoot(1.2)
		return

	if "--closeup" in args:
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.5
		_set_bin(7, ["pet", "pet", "pet"])
		_set_bin(9, ["lata"])
		_set_bin(11, ["vidrio"])
		main.players[0].teleport(7, 3, Vector2i(0, -1))
		main.players[1].teleport(9, 3, Vector2i(0, -1))
		var held := CarryItem.residue("pet")
		ItemVisuals.build(held)
		main.move_item_to_player(held, main.players[0])
		main.camera.fov = 30.0
		main.camera.look_at_from_position(Vector3(9.0, 3.0, 6.4), Vector3(9.0, 0.8, 2.4), Vector3.UP)
		await _shoot(1.2)
		return

	if "--diagonal" in args:
		# los dos jugadores caminando en diagonal: el cuerpo mira a la diagonal
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var p1: Player = main.players[0]
		var p2: Player = main.players[1]
		p1.teleport(8, 8)
		p2.teleport(13, 6)
		p1.face_towards(Vector2(1.0, -1.0), 1.0)
		p2.face_towards(Vector2(-1.0, -1.0), 1.0)
		var one := CarryItem.residue("vidrio")
		ItemVisuals.build(one)
		main.move_item_to_player(one, p1)
		var other := CarryItem.bag(["pet", "pet"])
		ItemVisuals.build(other)
		main.move_item_to_player(other, p2)
		main.camera.fov = 30.0
		main.camera.look_at_from_position(Vector3(10.5, 3.4, 15.0), Vector3(10.5, 0.5, 8.4), Vector3.UP)
		await _shoot(0.8)
		return

	if "--map" in args:
		# el mapa entero desde el mar: sirve para revisar props y proporciones
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.7
		var w := float(main.world.w)
		var h := float(main.world.h)
		main.camera.fov = 52.0
		main.camera.look_at_from_position(Vector3(w * 0.5, 15.0, h + 12.0),
			Vector3(w * 0.5, 0.0, h * 0.42), Vector3.UP)
		await _shoot(1.2)
		return

	if "--pressure" in args:
		# Fase 2: aro de cuenta atrás en el vidrio y basura flotante en la orilla
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.55
		for row in main.world.tiles:
			for t in row:
				if t.item != null:
					main.destroy_item(t.item)
					t.item = null
		var spots := [[9, 8, "vidrio", 6.5], [12, 7, "vidrio", 2.0], [7, 9, "pet", 0.0]]
		for spot in spots:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))
			main.drop_from_above(r)
			r.life = float(spot[3])
		for wx in [10, 13, 16]:
			var w := CarryItem.residue("lata", "water")
			ItemVisuals.build(w)
			main.move_item_to_tile(w, main.world.tile_at(wx, 11))
			main.drop_from_above(w)
			w.life = 2.0 + float(wx % 3)
		main.players[0].teleport(11, 9, Vector2i(0, 1))
		for i in 80:
			await get_tree().physics_frame
		main._tick_decay(0.0)
		main.camera.fov = 34.0
		main.camera.look_at_from_position(Vector3(12.0, 6.4, 16.0), Vector3(12.0, 0.3, 10.6), Vector3.UP)
		await _shoot(0.8)
		return

	if "--kick" in args:
		# basura pateada: los residuos ruedan y quedan acostados
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.7
		var p: Player = main.players[0]
		p.teleport(9, 8, Vector2i(0, -1))
		for spot in [[9, 6, "pet"], [10, 6, "vidrio"], [11, 6, "lata"]]:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))
			main.drop_from_above(r)
		for i in 90:
			await get_tree().physics_frame
		# camina por encima: los patea y salen despedidos
		for i in 40:
			p.velocity = Vector3(0.0, 0.0, -GameConfig.PLAYER_SPEED)
			p.move_and_slide()
			await get_tree().physics_frame
		for i in 70:
			await get_tree().physics_frame
		main.camera.fov = 30.0
		main.camera.look_at_from_position(Vector3(10.0, 3.0, 9.2), Vector3(10.0, 0.2, 6.2), Vector3.UP)
		await _shoot(0.8)
		return

	if "--items" in args:
		# los tres residuos de cerca: se tienen que reconocer de un vistazo
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.7
		main.players[0].teleport(9, 8, Vector2i(0, 1))
		var spots := [[9, 6, "pet"], [10, 6, "vidrio"], [11, 6, "lata"]]
		for spot in spots:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))
		main.camera.fov = 26.0
		main.camera.look_at_from_position(Vector3(10.0, 2.2, 8.6), Vector3(10.0, 0.25, 6.0), Vector3.UP)
		await _shoot(1.2)
		return

	if "--shore" in args:
		# jugador en la orilla: se ve el agua y la espuma de cerca
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.62
		main.players[0].teleport(12, 9, Vector2i(0, 1))
		for spot in [[10, 9, "pet"], [14, 10, "lata"], [8, 8, "vidrio"]]:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))
		await _shoot(1.2)
		return

	if "--carry" in args:
		# con una bolsa en la mano: el ítem va a las manos (no a la cabeza)
		main.start_game(2)
		await get_tree().process_frame
		var bag := CarryItem.bag(["pet", "lata", "vidrio"])
		ItemVisuals.build(bag)
		main.move_item_to_player(bag, main.players[0])
		main.players[0].teleport(11, 7, Vector2i(0, 1))
		main.players[1].teleport(13, 7, Vector2i(0, 1))
		await _shoot(1.4)
		return

	if "--facing" in args:
		# mira la cámara: sirve para verificar que el personaje NO camina de espaldas
		main.start_game(2)
		await get_tree().process_frame
		main.players[0].teleport(10, 9, Vector2i(0, 1))
		main.players[1].teleport(13, 9, Vector2i(1, 0))
		var one := CarryItem.residue("pet")
		ItemVisuals.build(one)
		main.move_item_to_player(one, main.players[0])
		var other := CarryItem.bag(["lata", "lata"])
		ItemVisuals.build(other)
		main.move_item_to_player(other, main.players[1])
		await _shoot(1.6)
		return

	if "--demo" in args or "--demo2" in args or not args.is_empty():
		main.start_game(2 if "--demo2" in args else 1)
		await get_tree().process_frame
		_set_bin(7, ["pet", "pet"])
		_set_bin(9, ["lata", "lata", "lata"])
		_set_bin(11, ["vidrio"])
		for spot in [[6, 5, "pet"], [10, 7, "lata"], [14, 6, "vidrio"], [17, 8, "pet"], [12, 9, "lata"]]:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))

		var p: Player = main.players[0]
		# mirando a cámara: se ve lo que llevan en las manos
		p.teleport(7, 3, Vector2i(0, 1))
		var held := CarryItem.residue("pet")
		ItemVisuals.build(held)
		main.move_item_to_player(held, p)

		if main.players.size() > 1:
			var p2: Player = main.players[1]
			p2.teleport(18, 3, Vector2i(0, 1))
			var full := CarryItem.bag(["pet", "pet", "pet", "pet"])
			ItemVisuals.build(full)
			main.move_item_to_player(full, p2)

	main.time_left = main.level_seconds * 0.38
	await _shoot(1.5)


func _set_bin(x: int, contents: Array) -> void:
	var tile: CellData = main.world.tile_at(x, 1)
	var bag := CarryItem.bag(contents)
	ItemVisuals.build(bag)
	tile.bag = bag
	main._update_bin_visual(tile)


func _shoot(wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("shot -> ", out_path)
	get_tree().quit()
