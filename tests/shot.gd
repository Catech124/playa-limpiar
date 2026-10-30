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
		main.cam_free = true
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
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(10.5, 3.4, 15.0), Vector3(10.5, 0.5, 8.4), Vector3.UP)
		await _shoot(0.8)
		return

	if "--crab" in args:
		# cangrejo cruzando la arena + objeto en las manos + basura flotando
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		main.crabs.spawn()
		if not main.crabs.list.is_empty():
			var c = main.crabs.list[0]
			c.pos = Vector3(11.7, 0.0, 9.3)
			c.target = Vector3(11.7, 0.0, 8.1)   # un paso al frente, no re-targetea
			c.body.position = c.pos
			c.body.rotation.y = 0.6
			main.crabs.tick(0.02)
		var p: Player = main.players[0]
		p.teleport(10, 8, Vector2i(0, 1))
		var it := CarryItem.residue("pet")
		ItemVisuals.build(it)
		main.move_item_to_player(it, p)
		for spot in [[7, 8, "lata"], [13, 9, "vidrio"]]:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))
		main.players[1].teleport(16, 6, Vector2i(0, 1))
		main.camera.fov = 40.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(10.9, 2.9, 14.2),
			Vector3(10.9, 0.32, 8.6), Vector3.UP)
		await _shoot(0.4)
		return

	if "--char" in args:
		# retrato del personaje: sin HUD y de cerca, para revisar el modelo
		main.start_game(1)
		await get_tree().process_frame
		var cp: Player = main.players[0]
		cp.teleport(10, 7, Vector2i(0, 1))
		var held: CarryItem = CarryItem.bag(["pet", "lata"]) if "--bag" in args \
			else CarryItem.residue("pet")
		ItemVisuals.build(held)
		main.move_item_to_player(held, cp)
		await get_tree().process_frame
		main.hud.visible = false
		main.camera.fov = 26.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(10.5, 1.30, 11.6),
			Vector3(10.5, 0.45, 7.50), Vector3.UP)
		await _shoot(0.5)
		return

	if "--npc" in args:
		# veraneantes: uno toma sol, otro sentado y otro charlando
		main.start_game(2, false, 2)      # Día 3: tres NPCs
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		main.players[0].teleport(2, 2)
		main.players[1].teleport(21, 2)
		for i in 30:
			main.npcs.tick(1.0 / 60.0)
		main.camera.fov = 40.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(10.0, 5.6, 15.0),
			Vector3(10.0, 0.5, 6.2), Vector3.UP)
		await _shoot(0.05)
		return

	if "--npcthrow" in args:
		# uno se levanta, camina a la orilla y tira basura al mar
		main.start_game(2, false, 2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var actor = main.npcs.list[0]
		actor.phase = "walk_out"
		actor.target = main.npcs._shore_point(actor.home)
		for i in 260:
			main.npcs.tick(1.0 / 60.0)
		main.camera.fov = 36.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(4.5, 4.4, 15.0),
			Vector3(4.5, 0.6, 9.6), Vector3.UP)
		await _shoot(0.05)
		return

	if "--bite" in args:
		# mordida: el tiburón sale del agua y la cuenta atrás de reaparición
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var bp: Player = main.players[0]
		bp.teleport(10, 12, Vector2i(0, -1))
		for i in 3:
			await get_tree().physics_frame
		main._show_shark(bp)
		main._update_sharks(0.34)
		bp.down_time = 3.6
		bp._body_mesh.visible = false
		main.camera.fov = 34.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(10.0, 4.4, 17.2),
			Vector3(10.0, 0.4, 11.6), Vector3.UP)
		await _shoot(0.10)
		return

	if "--swim" in args:
		# nadando con la aleta cerca: el agua es más lenta y da miedo
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var s1: Player = main.players[0]
		var s2: Player = main.players[1]
		s1.teleport(9, 12, Vector2i(1, 0))
		s2.teleport(12, 11, Vector2i(-1, 1))
		for i in 3:
			await get_tree().physics_frame
		s1.face_towards(Vector2(1.0, 0.0), 1.0)
		s2.face_towards(Vector2(-1.0, 1.0), 1.0)
		s1.water_time = 4.2
		main._tick_water(0.02)
		# la aleta viene de mar adentro: se la deja a mitad de camino
		if s1.fin != null:
			for i in 22:
				main._tick_water(0.06)
		var floating := CarryItem.residue("pet", "water")
		ItemVisuals.build(floating)
		main.move_item_to_tile(floating, main.world.tile_at(13, 12))
		main.camera.fov = 34.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(11.0, 5.0, 17.0), Vector3(11.0, 0.2, 11.4), Vector3.UP)
		await _shoot(1.0)
		return

	if "--palmera" in args:
		# palmera + reposera + sombrilla de cerca, con un jugador al lado
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		main.players[0].teleport(3, 3, Vector2i(0, 1))
		await get_tree().physics_frame
		main.hud.visible = false
		main.camera.fov = 40.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(4.2, 3.4, 10.6),
			Vector3(4.4, 1.0, 4.4), Vector3.UP)
		await _shoot(0.5)
		return

	if "--dispensador" in args:
		# el dispensador de bolsas de cerca, con un jugador al lado
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var tp_bags: CellData = null
		for row in main.world.tiles:
			for t in row:
				if t.station == "bags":
					tp_bags = t
		if tp_bags != null:
			main.players[0].teleport(tp_bags.x + 1, tp_bags.y + 1, Vector2i(0, -1))
		await get_tree().physics_frame
		var bx := float(tp_bags.x) + 0.5 if tp_bags != null else 3.5
		var bz := float(tp_bags.y) + 0.5 if tp_bags != null else 1.5
		main.hud.visible = false
		main.camera.fov = 36.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(bx + 0.3, 1.75, bz + 3.4),
			Vector3(bx, 0.55, bz), Vector3.UP)
		await _shoot(0.5)
		return

	if "--bins" in args:
		# los tres botes de cerca: uno con bolsa colgada (tapa abierta)
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var bins: Array = []
		for row in main.world.tiles:
			for t in row:
				if t.station == "bin":
					bins.append(t)
		bins.sort_custom(func(a, b): return a.x < b.x)
		var con_bolsa: CellData = null
		for t in bins:
			if t.bin == "vidrio":
				con_bolsa = t
		if con_bolsa != null:
			con_bolsa.bag = CarryItem.bag(["vidrio", "pet"])
			ItemVisuals.build(con_bolsa.bag)
			main._update_bin_visual(con_bolsa)
			for i in 60:
				main._tick_bin_lids(0.03)
		# un jugador al lado del bote verde, para comparar tamaños
		if con_bolsa != null:
			main.players[0].teleport(con_bolsa.x, con_bolsa.y + 1, Vector2i(0, -1))
			await get_tree().physics_frame
		var cx := 0.0
		for t in bins:
			cx += float(t.x) + 0.5
		cx /= float(maxi(bins.size(), 1))
		var cz := 0.0
		for t in bins:
			cz += float(t.y) + 0.5
		cz /= float(maxi(bins.size(), 1))
		main.hud.visible = false
		main.camera.fov = 40.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(cx, 1.9, cz + 5.2),
			Vector3(cx, 0.5, cz), Vector3.UP)
		await _shoot(0.5)
		return

	if "--shore" in args:
		# jugador en la orilla: la aleta tiene que quedarse en el agua
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		var sh: Player = main.players[0]
		sh.teleport(6, 10, Vector2i(0, 1))
		await get_tree().physics_frame
		sh.water_time = GameConfig.SHARK_FIN_TIME + 0.1
		main._tick_water(0.02)
		for i in 90:
			main._tick_water(0.05)
		print("fin en ", sh.fin.position if sh.fin != null else Vector3.ZERO,
			" agua=", main._is_water_at(sh.fin.position) if sh.fin != null else false)
		main.camera.fov = 36.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(6.5, 3.4, 15.6),
			Vector3(6.5, 0.3, 10.4), Vector3.UP)
		await _shoot(0.4)
		return

	if "--gull" in args:
		# gaviota con el aro rojo sobre la basura que eligió
		main.start_game(1)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.6
		for row in main.world.tiles:
			for t in row:
				if t.item != null:
					main.destroy_item(t.item)
					t.item = null
		for spot in [[9, 7, "vidrio"], [12, 6, "pet"], [7, 6, "lata"]]:
			var r := CarryItem.residue(spot[2])
			ItemVisuals.build(r)
			main.move_item_to_tile(r, main.world.tile_at(spot[0], spot[1]))
		var gull: bool = main.gulls.spawn()
		if not gull:
			main.cam_free = true
			main.camera.look_at_from_position(Vector3(10.0, 4.0, 14.0), Vector3(10.0, 0.3, 7.0), Vector3.UP)
			await _shoot(0.6)
			return
		for i in 72:
			main.gulls.tick(1.0 / 60.0)
		var g2 = main.gulls.list[0]
		var tp := Vector3(g2.target.x + 0.5, 0.0, g2.target.y + 0.5)
		print("gull en ", g2.pos, " target ", tp, " aro ", g2.mark)
		var w := float(main.world.w)
		var h := float(main.world.h)
		main.camera.fov = 44.0
		main.cam_free = true
		main.camera.look_at_from_position(tp + Vector3(0.0, 11.0, 13.0),
			tp + Vector3(-1.5, 0.0, 1.0), Vector3.UP)
		await _shoot(0.6)
		return

	if "--dash" in args:
		# el polvo del impulso, recién salido
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.7
		var d1: Player = main.players[0]
		var d2: Player = main.players[1]
		d1.teleport(9, 7)
		d2.teleport(12, 7)
		d1.face_towards(Vector2(1.0, 0.0), 1.0)
		d2.face_towards(Vector2(0.0, -1.0), 1.0)
		await get_tree().physics_frame
		main.spawn_puff(d1.position, Color(0.88, 0.82, 0.66), 9, 1.1)
		main.spawn_puff(d2.position, Color(0.88, 0.82, 0.66), 9, 1.1)
		main.camera.fov = 30.0
		main.cam_free = true
		main.camera.look_at_from_position(Vector3(10.5, 3.2, 14.0), Vector3(10.5, 0.4, 7.4), Vector3.UP)
		await _shoot(0.10)
		return

	if "--map" in args:
		# el mapa entero desde el mar: sirve para revisar props y proporciones
		main.start_game(2)
		await get_tree().process_frame
		main.time_left = main.level_seconds * 0.7
		var w := float(main.world.w)
		var h := float(main.world.h)
		main.camera.fov = 52.0
		main.cam_free = true
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
		main.cam_free = true
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
		main.cam_free = true
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
		main.cam_free = true
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
