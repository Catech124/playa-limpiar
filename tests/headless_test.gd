extends Node
## Autotest de mecánicas. Se lanza con:
##   godot --headless --path . -- --test
## Ejercita las MISMAS funciones que usa el input real (player_use, throw_item),
## teleportando al jugador entre estaciones.
##
## Cubre el bucle de la v2: basura tirada -> bolsa en la boca del contenedor ->
## camión -> cuota del día. Se lanza con `godot --headless -- --test`.

var main
var results: Array = []


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	var failed := 0
	for r in results:
		if not r["ok"]:
			failed += 1
	print("")
	print("%d/%d PASS" % [results.size() - failed, results.size()])
	get_tree().quit(0 if failed == 0 else 1)


# ------------------------------------------------------------------ helpers
func check(name: String, ok: bool, detail := "") -> void:
	results.append({"name": name, "ok": ok})
	var line := ("PASS  " if ok else "FAIL  ") + name
	if detail != "":
		line += "  — " + detail
	print(line)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func tp(tx: int, ty: int, facing := Vector2i(0, -1)) -> void:
	main.players[0].teleport(tx, ty, facing)
	await get_tree().physics_frame


func use() -> void:
	var p = main.players[0]
	main.player_use(p, p.front_tile())


## Se para en una celda caminable vecina y mira la celda indicada.
func face_tile(t: CellData) -> void:
	var p = main.players[0]
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: CellData = main.world.tile_at(t.x + d.x, t.y + d.y)
		if n != null and not n.is_solid():
			p.teleport(n.x, n.y, Vector2i(-d.x, -d.y))
			await get_tree().physics_frame
			return


func free_tile(y := 8) -> CellData:
	for x in range(2, main.world.w - 2):
		var t: CellData = main.world.tile_at(x, y)
		if t != null and t.can_hold() and t.item == null:
			return t
	return main.world.tile_at(2, 8)


func give(item: CarryItem) -> void:
	ItemVisuals.build(item)
	main.move_item_to_player(item, main.players[0])


func take_away() -> void:
	var p = main.players[0]
	if p.carrying != null:
		main.destroy_item(p.carrying)
		p.carrying = null


# ------------------------------------------------------------------ tests
func _run() -> void:
	main.start_game(1)
	await frames(2)
	var p = main.players[0]

	check("arranca en juego", main.is_playing(), "estado=%d" % main.state)
	check("aparece en el spawn (3,6)", p.tile_x() == 3 and p.tile_y() == 6, "%d,%d" % [p.tile_x(), p.tile_y()])

	# --- nivel y reloj ----------------------------------------------------
	check("el día 1 arranca a las 06:00", main.clock_text() == "06:00", main.clock_text())
	check("la cuota del día 1 es 6/4/4",
		int(main.quota["pet"]) == 6 and int(main.quota["vidrio"]) == 4 and int(main.quota["lata"]) == 4,
		str(main.quota))
	check("el HUD tiene 3 barras de cuota", main.quota_rows().size() == 3)
	# --- los niveles se pueden ganar --------------------------------------
	# La basura sale de a una cada `spawn_interval`: si el tiempo no alcanza
	# para que aparezca la cuota completa, el nivel es imposible por diseño
	# (y no por jugar mal), que es el peor bug de balance que existe.
	for lvl in Levels.LEVELS:
		var need := 0
		for t in lvl["quota"].keys():
			need += int(lvl["quota"][t])
		var burst := int(lvl["spawn_initial"])
		var t_spawn := float(maxi(0, need - burst)) * float(lvl["spawn_interval"])
		check("el nivel «%s» puede llenar su cuota a tiempo" % String(lvl["name"]),
			t_spawn < float(lvl["seconds"]) * 0.6,
			"%.0f s de aparición para %.0f s de jornada" % [t_spawn, float(lvl["seconds"])])

	check("la playa amanece con basura", main.spawner.count_on_ground() == 3,
		"%d tiradas" % main.spawner.count_on_ground())

	main.time_left = main.level_seconds * 0.5
	check("a mitad de jornada el reloj va por la tarde", main.clock_text() == "14:00", main.clock_text())
	main.time_left = main.level_seconds
	check("el avance del día se mide de 0 a 1", absf(main.day_progress()) < 0.001)

	# --- movimiento -------------------------------------------------------
	var start_x: float = p.position.x
	for i in 30:
		p.move_step(Vector2(1, 0))
		await get_tree().physics_frame
	check("se mueve a la derecha", p.position.x > start_x + 0.8, "x %.2f -> %.2f" % [start_x, p.position.x])

	await tp(7, 2, Vector2i(0, -1))
	for i in 30:
		p.move_step(Vector2(0, -1))
		await get_tree().physics_frame
	check("el contenedor bloquea (no atraviesa)", p.position.z > 2.25, "z=%.2f" % p.position.z)

	# --- spawner ----------------------------------------------------------
	var trash: CarryItem = main.spawner.spawn_one("pet")
	var tt: CellData = null
	if trash != null and trash.node != null:
		tt = main.world.tile_at(int(floor(trash.node.position.x)), int(floor(trash.node.position.z)))
	check("el spawner tira basura nueva", trash != null and main.spawner.count_on_ground() == 4,
		"%d tiradas" % main.spawner.count_on_ground())
	check("la basura cae en una celda de arena", tt != null and tt.kind == "floor")
	check("el tipo pedido es el que sale", trash != null and trash.type == "pet")
	check("el spawner elige tipos válidos",
		main.spawner.pick_type() in ["pet", "vidrio", "lata"])

	# --- recoger del piso -------------------------------------------------
	await face_tile(tt)
	use()
	check("recoge la basura del piso", p.carrying == trash,
		p.carrying.label() if p.carrying else "nada")

	# --- contenedor sin bolsa --------------------------------------------
	await tp(7, 2, Vector2i(0, -1))
	use()
	var bin_pet: CellData = main.world.tile_at(7, 1)
	check("sin bolsa el contenedor no acepta basura", p.carrying == trash)

	# --- dispensador de bolsas -------------------------------------------
	var drop_tile := free_tile(8)
	main.move_item_to_tile(trash, drop_tile)
	p.carrying = null
	await tp(3, 2, Vector2i(0, -1))
	use()
	check("toma una bolsa del dispensador", p.carrying != null and p.carrying.is_bag())
	var bag: CarryItem = p.carrying

	# --- colgar la bolsa en el contenedor --------------------------------
	await tp(7, 2, Vector2i(0, -1))
	use()
	check("la bolsa queda colgada en el contenedor",
		p.carrying == null and bin_pet.bag == bag)
	check("la bolsa colgada tiene nodo en escena",
		bag.node != null and bag.node.get_parent() == main.world.items_root)
	check("la bolsa arranca vacía", bag.contents.is_empty())

	# --- tirar basura en la bolsa ----------------------------------------
	await face_tile(drop_tile)
	use()
	check("vuelve a levantar la basura", p.carrying == trash)
	await tp(7, 2, Vector2i(0, -1))
	use()
	check("tirar en el contenedor correcto llena la bolsa",
		p.carrying == null and bag.contents.size() == 1,
		"%d en la bolsa" % bag.contents.size())
	check("la basura desaparece de la mano", p.carrying == null)

	# --- tipo equivocado --------------------------------------------------
	var wrong := CarryItem.residue("vidrio")
	give(wrong)
	var penalties_before: int = int(main.stats["penalties"])
	await tp(9, 2, Vector2i(0, -1))   # contenedor de LATAS
	use()
	check("el contenedor equivocado no lo acepta", p.carrying == wrong)
	check("y penaliza", int(main.stats["penalties"]) == penalties_before + 1,
		"penalizaciones %d" % int(main.stats["penalties"]))
	take_away()

	# --- llenar la bolsa --------------------------------------------------
	for i in 3:
		var r := CarryItem.residue("pet")
		give(r)
		await tp(7, 2, Vector2i(0, -1))
		use()
	check("la bolsa se llena con 4 residuos", bag.contents.size() == 4 and bag.is_full(),
		"%d/4" % bag.contents.size())

	var extra := CarryItem.residue("pet")
	give(extra)
	await tp(7, 2, Vector2i(0, -1))
	use()
	check("la bolsa llena no acepta más", p.carrying == extra)
	take_away()

	# --- retirar la bolsa llena ------------------------------------------
	await tp(7, 2, Vector2i(0, -1))
	use()
	check("retira la bolsa llena del contenedor", p.carrying == bag and bin_pet.bag == null)
	check("al sacarla se achica al tamaño de la mano", bag.node != null and bag.node.get_parent() == p.carry_anchor)

	# --- entrega en el camión --------------------------------------------
	var delivered_before: int = int(main.delivered["pet"])
	var score_before: int = main.score
	await tp(19, 2, Vector2i(0, -1))
	use()
	check("entregar suma a la cuota", int(main.delivered["pet"]) == delivered_before + 4,
		"%d -> %d" % [delivered_before, int(main.delivered["pet"])])
	check("la bolsa se va con el camión", p.carrying == null and bag.node == null)
	check("entregar suma puntos", main.score > score_before, "%d -> %d" % [score_before, main.score])

	# bolsa vacía
	var empty := CarryItem.bag()
	give(empty)
	var total_before: int = main.total_delivered()
	await tp(19, 2, Vector2i(0, -1))
	use()
	check("la bolsa vacía no suma", main.total_delivered() == total_before and p.carrying == empty)
	take_away()

	# basura suelta en el camión
	var loose := CarryItem.residue("lata")
	give(loose)
	await tp(19, 2, Vector2i(0, -1))
	use()
	check("la basura suelta no se entrega", p.carrying == loose)
	take_away()

	# --- cumplir la cuota gana -------------------------------------------
	main.delivered = {"pet": 6, "vidrio": 4, "lata": 3}
	var last := CarryItem.bag(["lata"])
	give(last)
	await tp(19, 2, Vector2i(0, -1))
	use()
	check("cumplir la cuota termina el día", main.is_results() and main.won,
		"estado=%d won=%s" % [main.state, main.won])
	check("ganando se gana al menos una estrella", main.stars_earned() >= 1,
		"%d estrellas" % main.stars_earned())

	# --- reinicio ---------------------------------------------------------
	main.start_game(1)
	await frames(2)
	check("R reinicia la partida", main.is_playing() and main.score == 0)
	check("al reiniciar la cuota vuelve a cero", main.total_delivered() == 0)

	# --- fin de jornada sin cuota ----------------------------------------
	main.time_left = 0.05
	await frames(12)
	check("si se acaba el día sin cuota, se pierde", main.is_results() and not main.won)

	# --- colisiones -------------------------------------------------------
	main.start_game(1)
	await frames(2)
	p = main.players[0]

	var bag_tile: CellData = main.world.tile_at(8, 8)
	if bag_tile.item != null:
		main.destroy_item(bag_tile.item)
		bag_tile.item = null
	var floor_bag := CarryItem.bag()
	ItemVisuals.build(floor_bag)
	main.move_item_to_tile(floor_bag, bag_tile)
	p.teleport(7, 8, Vector2i(1, 0))
	await frames(2)
	check("la bolsa del piso tiene collider", floor_bag.node.get_node_or_null("Blocker") != null)
	for i in 40:
		p.velocity = Vector3(4.0, 0.0, 0.0)
		p.move_and_slide()
		await get_tree().physics_frame
	check("no atraviesa la bolsa del piso", p.position.x < 8.10, "x=%.2f" % p.position.x)
	main.move_item_to_player(floor_bag, p)
	check("al levantarla se libera el paso", floor_bag.node.get_node_or_null("Blocker") == null)
	take_away()

	# una botella tirada NO estorba (solo las bolsas son obstáculo)
	var can_tile: CellData = main.world.tile_at(10, 8)
	if can_tile.item != null:
		main.destroy_item(can_tile.item)
		can_tile.item = null
	var floor_can := CarryItem.residue("lata")
	ItemVisuals.build(floor_can)
	main.move_item_to_tile(floor_can, can_tile)
	check("la basura del piso no tiene collider", floor_can.node.get_node_or_null("Blocker") == null)
	p.teleport(9, 8, Vector2i(1, 0))
	await frames(2)
	for i in 40:
		p.velocity = Vector3(4.0, 0.0, 0.0)
		p.move_and_slide()
		await get_tree().physics_frame
	check("se puede caminar por encima de una botella", p.position.x > 10.4, "x=%.2f" % p.position.x)

	# el agua sigue siendo sólida
	p.teleport(5, 10, Vector2i(0, 1))
	await frames(2)
	for i in 40:
		p.velocity = Vector3(0.0, 0.0, 4.0)
		p.move_and_slide()
		await get_tree().physics_frame
	check("no se entra al mar", p.position.z < 10.85, "z=%.2f" % p.position.z)

	# --- gaviotas ---------------------------------------------------------
	main.start_game(1)
	await frames(2)
	main.gulls.list.clear()
	main.gulls.timer = 999.0
	# playa vacía a propósito: la gaviota elige al azar entre lo que hay
	# tirado, así que la "víctima" tiene que ser la única candidata
	for row in main.world.tiles:
		for t in row:
			if t.item != null:
				main.destroy_item(t.item)
				t.item = null
	var stolen_before: int = int(main.stats["stolen"])
	var victim: CarryItem = main.spawner.spawn_one("lata")
	main.gulls.spawn()
	check("aparece una gaviota si hay basura tirada", main.gulls.list.size() == 1,
		"%d gaviotas" % main.gulls.list.size())
	for i in 40:
		main.gulls.tick(0.5)
	check("la gaviota se lleva la basura", int(main.stats["stolen"]) == stolen_before + 1,
		"robos %d" % int(main.stats["stolen"]))
	check("la basura robada desaparece de la playa", victim.node == null)

	main.gulls.list.clear()
	for row in main.world.tiles:
		for t in row:
			if t.item != null and t.item.is_residue():
				main.destroy_item(t.item)
				t.item = null
	check("sin basura tirada no viene ninguna gaviota", not main.gulls.spawn())

	# La gaviota llega según cuántos jugadores hay: sola, la playa queda sin
	# cubrir mientras se embolsa (era imposible ganarle).
	var solo_wait: float = main.gulls.first_delay()
	var solo_gap: float = main.gulls.interval()
	main.start_game(2)
	await frames(2)
	var duo_wait: float = main.gulls.first_delay()
	check("la gaviota tarda más con un solo jugador",
		solo_wait > duo_wait and solo_wait >= 45.0,
		"solo %.0f s · dos %.0f s" % [solo_wait, duo_wait])
	check("entre gaviota y gaviota pasa más de medio minuto con un jugador",
		solo_gap >= 40.0, "cada %.0f s" % solo_gap)

	# --- física de la basura ---------------------------------------------
	main.start_game(1)
	await frames(2)
	for row in main.world.tiles:
		for t in row:
			if t.item != null:
				main.destroy_item(t.item)
				t.item = null

	var dropped: CarryItem = main.spawner.spawn_one("pet")
	var drop_body := dropped.node as RigidBody3D
	check("la basura es un cuerpo rígido (se puede patear)", drop_body != null)
	var y0 := drop_body.global_position.y
	check("aparece desde un poco arriba", y0 > 0.20, "y=%.2f" % y0)
	for i in 100:
		await get_tree().physics_frame
	check("no se hunde en la arena",
		drop_body.global_position.y < 0.35, "y=%.2f" % drop_body.global_position.y)
	var up := drop_body.global_transform.basis.y.y
	check("al caer queda acostada (no plantada)", absf(up) < 0.75, "up.y=%.2f" % up)

	# patear: el jugador camina sobre la basura y la corre
	var kick_me: CarryItem = main.spawner.spawn_one("lata")
	for i in 80:
		await get_tree().physics_frame
	p = main.players[0]
	p.teleport(10, 6, Vector2i(0, -1))
	main.move_item_to_tile(kick_me, main.world.tile_at(10, 5))
	main.drop_from_above(kick_me)
	for i in 60:
		await get_tree().physics_frame
	var kicked_from := (kick_me.node as Node3D).global_position
	for i in 30:
		p.velocity = Vector3(0.0, 0.0, -GameConfig.PLAYER_SPEED)
		p.move_and_slide()
		await get_tree().physics_frame
	var kicked_to := (kick_me.node as Node3D).global_position
	check("la basura se puede patear",
		kicked_to.distance_to(kicked_from) > 0.20,
		"se movió %.2f" % kicked_to.distance_to(kicked_from))

	main.move_item_to_player(kick_me, p)
	check("en la mano el residuo queda sin física",
		(kick_me.node as RigidBody3D).freeze and (kick_me.node as RigidBody3D).collision_layer == 0)

	# --- avisos contextuales ---------------------------------------------
	main.start_game(1)
	await frames(2)
	p = main.players[0]
	await tp(7, 2, Vector2i(0, -1))
	check("el aviso del contenedor pide la bolsa",
		"bolsa" in main.interaction_hint(p).to_lower(), main.interaction_hint(p))
	await tp(3, 2, Vector2i(0, -1))
	check("el aviso del dispensador ofrece una bolsa",
		"bolsa" in main.interaction_hint(p).to_lower(), main.interaction_hint(p))
	await tp(19, 2, Vector2i(0, -1))
	check("el aviso del camión explica la entrega",
		"bolsa" in main.interaction_hint(p).to_lower(), main.interaction_hint(p))

	# --- rig y animación ---------------------------------------------------
	var p2 = main.players[0]
	var hinges: Dictionary = p2._hinges
	check("el modelo trae las 6 bisagras", hinges.size() == 6,
		"hay %d: %s" % [hinges.size(), hinges.keys()])

	p2.walk_phase = PI * 0.5
	p2.velocity = Vector3(0, 0, 1) * 2.0
	p2._animate(0.016)
	var l1: float = hinges["leg_l"].rotation.x
	var r1: float = hinges["leg_r"].rotation.x
	check("caminar mueve las piernas en oposición",
		absf(l1) > 0.2 and absf(r1) > 0.2 and signf(l1) != signf(r1),
		"leg_l=%.2f leg_r=%.2f" % [l1, r1])

	p2.velocity = Vector3.ZERO
	p2._animate(0.016)
	check("quieto deja las piernas rectas",
		absf(hinges["leg_l"].rotation.x) < 0.001 and absf(hinges["leg_r"].rotation.x) < 0.001,
		"leg_l=%.3f" % hinges["leg_l"].rotation.x)
	check("quieto igual mueve la cabeza", absf(hinges["head"].rotation.z) > 0.0001,
		"head.z=%.4f" % hinges["head"].rotation.z)

	var before: float = hinges["arm_l"].rotation.x
	p2.carrying = CarryItem.bag()
	p2._animate(0.016)
	check("llevando algo los brazos van adelante",
		hinges["arm_l"].rotation.x < before - 0.5,
		"brazo %.2f -> %.2f" % [before, hinges["arm_l"].rotation.x])
	p2.carrying = null
