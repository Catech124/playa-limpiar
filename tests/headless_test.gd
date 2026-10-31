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
		# una parte de la basura cae al agua y se hunde: no cuenta para la cuota
		# salvo que se rescate, así que el ritmo tiene que cubrir esa pérdida
		var lost := float(lvl.get("spawn_water", 0.0))
		var t_spawn := float(maxi(0, need - burst)) / maxf(0.2, 1.0 - lost) * float(lvl["spawn_interval"])
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
	# el bote es angosto (0.47 de planta): el tope está en su cara de adelante
	check("el contenedor bloquea (no atraviesa)", p.position.z > 2.05, "z=%.2f" % p.position.z)

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
	check("y no castiga: solo bloquea", int(main.stats["penalties"]) == penalties_before,
		"penalizaciones %d" % int(main.stats["penalties"]))
	take_away()

	# --- llenar la bolsa --------------------------------------------------
	for i in 3:
		var r := CarryItem.residue("pet")
		give(r)
		await tp(7, 2, Vector2i(0, -1))
		var ft: CellData = p.front_tile()
		use()
		# si algo no cerró, este aviso dice exactamente dónde quedó el jugador,
		# qué celda tenía adelante y cuánto entró en la bolsa (para cazar el
		# fallo raro que aparece 1 de cada ~15 corridas)
		if p.carrying != null or bag.contents.size() != i + 2:
			print("AVISO paso %d: bolsa=%d/4 (esperado %d) lleva=%s frente=%s,%s bin=%s pos=%s" % [
				i, bag.contents.size(), i + 2,
				(p.carrying.label() if p.carrying != null else "nada"),
				ft.x if ft != null else -1, ft.y if ft != null else -1,
				(ft.bin if ft != null else "-"), p.position])
		if p.carrying != null:
			# solo aparece cuando el test falla: dice dónde quedó el jugador y qué
			# tenía en la mano (es la pista que faltaba para cazar el fallo raro)
			print("AVISO paso %d no entró: lleva=%s pos=%s frente=%s,%s bolsa=%d" % [
				i, p.carrying.type, p.position,
				p.front_tile().x if p.front_tile() else -1,
				p.front_tile().y if p.front_tile() else -1, bag.contents.size()])
	check("la bolsa se llena con 4 residuos", bag.contents.size() == 4 and bag.is_full(),
		"%d/4" % bag.contents.size())

	var extra := CarryItem.residue("pet")
	give(extra)
	await tp(7, 2, Vector2i(0, -1))
	use()
	check("la bolsa llena no acepta más", p.carrying == extra,
		"lleva=%s esperado=%s bolsa=%d/4" % [
			(p.carrying.type if p.carrying != null else "nada"), extra.type,
			bag.contents.size()])
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

	# el agua se nada (Fase 3): se entra y se va más lento que caminando
	p.teleport(5, 10, Vector2i(0, 1))
	await frames(2)
	for i in 40:
		p.velocity = Vector3(0.0, 0.0, 4.0)
		p.move_and_slide()
		await get_tree().physics_frame
	check("se puede entrar al mar", p.position.z > 11.2, "z=%.2f" % p.position.z)
	check("en el agua el jugador nada", p.swimming)
	check("nadar es más lento que caminar",
		GameConfig.SWIM_SPEED < GameConfig.PLAYER_SPEED
		and GameConfig.SWIM_DASH_SPEED < GameConfig.DASH_SPEED,
		"nadar %.1f · correr %.1f" % [GameConfig.SWIM_SPEED, GameConfig.PLAYER_SPEED])

	# tiburón: aleta a los 3 s; después se acerca y muerde cuando llega
	var carried: CarryItem = CarryItem.bag(["pet"])
	ItemVisuals.build(carried)
	main.move_item_to_player(carried, p)
	p.water_time = 0.0
	main._tick_water(1.0)
	check("al segundo en el agua todavía no hay aleta", p.fin == null)
	p.water_time = GameConfig.SHARK_FIN_TIME
	main._tick_water(0.05)
	check("a los 3 s aparece la aleta", p.fin != null)
	var score_antes: int = main.score
	for i in 80:
		main._tick_water(0.1)      # se queda en el agua hasta la mordida
		if p.down_time > 0.0:
			break
	check("el tiburón llega y muerde", p.down_time > 0.0, "%.1f" % p.down_time)
	check("la mordida no descuenta puntos", main.score == score_antes,
		"%d -> %d" % [score_antes, main.score])
	check("mientras está mordido no se mueve ni se ve", not p._body_mesh.visible)
	check("la mordida hace soltar lo que llevaba", p.carrying == null)
	check("la aleta desaparece después de la mordida", p.fin == null)

	# reaparece en la arena recién a los 5 s
	for i in 3:
		main._tick_water(1.0)
	check("a los 3 s todavía no reapareció", p.down_time > 0.0)
	for i in 3:
		main._tick_water(1.0)
	check("a los 5 s reaparece en la arena", p.down_time == 0.0 and p.tile_y() <= 10,
		"y=%d" % p.tile_y())
	check("reaparece visible", p._body_mesh.visible)

	# --- la aleta sale del agua y NO de la arena --------------------------
	# Este era el bug: parado en la orilla, la aleta aparecía sobre la playa.
	main._clear_fin(p)
	p.down_time = 0.0
	p.water_time = 0.0
	p.teleport(6, 10, Vector2i(0, 1))
	p.swimming = false
	check("la orilla cuenta como cerca del agua", main._near_water(p),
		"celda %d,%d" % [p.tile_x(), p.tile_y()])
	var en_agua := true
	var ejemplo: Vector3 = Vector3.ZERO
	for i in 12:
		var q: Vector3 = main._fin_spawn(p)
		if ejemplo == Vector3.ZERO:
			ejemplo = q
		if not main._is_water_at(q):
			en_agua = false
	check("la aleta sale del mar aunque estés en la orilla", en_agua, "ej. %s" % [ejemplo])
	check("la aleta sale lejos del jugador",
		Vector2(ejemplo.x - p.position.x, ejemplo.z - p.position.z).length() > 1.6,
		"%.1f" % Vector2(ejemplo.x - p.position.x, ejemplo.z - p.position.z).length())

	# y no puede reptar por la arena: persigue a un jugador que está en la playa
	p.water_time = GameConfig.SHARK_FIN_TIME + 0.1
	main._tick_water(0.02)
	check("aparece la aleta", p.fin != null)
	var fuera_del_agua := false
	for i in 160:
		main._tick_water(0.05)
		if p.fin != null and not main._is_water_at(p.fin.position):
			fuera_del_agua = true
			break
	check("la aleta no se sube a la arena", not fuera_del_agua,
		"%s" % [p.fin.position if p.fin != null else Vector3.ZERO])
	main._clear_fin(p)
	p.water_time = 0.0

	# --- cangrejo: sólido ------------------------------------------------
	main.crabs.clear()
	main.crabs.timer = 999.0
	check("aparece un cangrejo", main.crabs.spawn() and main.crabs.list.size() == 1)
	var crab = main.crabs.list[0]
	var col: CollisionShape3D = null
	for c in crab.body.get_children():
		if c is CollisionShape3D:
			col = c
	check("el cangrejo tiene collider", col != null and col.shape != null)
	check("el collider está a la altura del cuerpo", col != null and col.position.y > 0.0,
		"%.2f" % (col.position.y if col != null else -1.0))
	check("el cangrejo choca con el jugador",
		crab.body.collision_layer == 1 and crab.body.collision_mask == 1,
		"capa %d · máscara %d" % [crab.body.collision_layer, crab.body.collision_mask])

	# y de verdad lo frena: el jugador camina derecho hacia él
	main.crabs.list.clear()               # congelado para la prueba
	crab.body.position = Vector3(6.5, 0.0, 7.5)
	crab.pos = crab.body.position
	p.teleport(4, 7, Vector2i(1, 0))
	p.down_time = 0.0
	for i in 60:
		p.velocity = Vector3(4.0, 0.0, 0.0)
		p.move_and_slide()
		await get_tree().physics_frame
	check("el jugador no atraviesa el cangrejo", p.position.x < 6.25 and p.position.x > 5.2,
		"x=%.2f (cangrejo en 6.50)" % p.position.x)
	main.crabs.list.append(crab)
	main.crabs.clear()

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

	# la gaviota avisa cuál va a robar con un aro rojo
	# (playa vacía: la víctima tiene que ser la única candidata)
	for row in main.world.tiles:
		for t in row:
			if t.item != null:
				main.destroy_item(t.item)
				t.item = null
	var mark_victim: CarryItem = main.spawner.spawn_one("pet")
	main.gulls.list.clear()
	main.gulls.spawn()
	var gull = main.gulls.list[0]
	check("la gaviota marca lo que va a robar", gull.mark != null)
	for i in 240:
		main.gulls.tick(0.05)
	check("al robar, el aro desaparece", gull.mark == null or not is_instance_valid(gull.mark))
	check("el aro apuntaba a la basura robada", mark_victim.node == null)



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

	# --- NPCs y reparto de tipos -----------------------------------------
	main.start_game(1, false, 2)          # Día 3: tres NPCs
	await frames(2)
	check("hay NPCs caminando por la playa", main.npcs.list.size() == 3,
		"%d" % main.npcs.list.size())

	# el NPC tira basura: cae en una celda libre con la misma parábola
	for row in main.world.tiles:
		for t in row:
			if t.item != null:
				main.destroy_item(t.item)
				t.item = null
	var npc_tile: CellData = main.spawner.pick_tile()
	main.npc_throw(Vector3(4.0, 1.2, 3.0), npc_tile)
	check("el NPC tira basura", main.flying.size() == 1)
	for i in 40:
		main._update_flying(0.03)
	check("la basura del NPC cae en la arena",
		npc_tile.item != null and npc_tile.item.is_residue())

	# los NPCs tiran al MAR: la basura flota y se hunde a los 10 s
	var water_tile: CellData = main.world.tile_at(8, 12)
	if water_tile != null and water_tile.item != null:
		main.destroy_item(water_tile.item)
		water_tile.item = null
	main.npc_throw(Vector3(8.0, 1.2, 9.0), water_tile, true)
	for i in 40:
		main._update_flying(0.03)
	check("el NPC tira basura al mar",
		water_tile.item != null and water_tile.item.origin == "water")
	var sunk_before: int = int(main.stats["penalties"])
	main._tick_decay(GameConfig.SEA_SINK_TIME + 0.1)
	check("lo que tiró al mar se hunde si nadie lo saca",
		water_tile.item == null and int(main.stats["penalties"]) > sunk_before)

	# el vidrio pesa más: es el que se acababa siempre
	var w_glass: float = main.spawner.type_weight("vidrio")
	var w_pet: float = main.spawner.type_weight("pet")
	check("el vidrio pesa más que el PET en el reparto", w_glass > w_pet,
		"vidrio %.1f · pet %.1f" % [w_glass, w_pet])
	var counts := {"pet": 0, "vidrio": 0, "lata": 0}
	for i in 400:
		counts[main.spawner.pick_type()] += 1
	var glass_share := float(counts["vidrio"]) / 400.0
	check("el vidrio sale al menos una de cada cuatro veces", glass_share > 0.25,
		"%.0f%%" % (glass_share * 100.0))

	# --- el agua tira basura ---------------------------------------------
	main.start_game(1, false, 1)          # Día 2: marea alta
	await frames(2)
	check("el Día 2 tira basura al agua", main.spawner.water_chance > 0.0,
		"%.2f" % main.spawner.water_chance)
	var wt: CellData = main.spawner.pick_water_tile()
	check("la basura flotante cae en el agua",
		wt != null and wt.kind == "water" and wt.y >= 11,
		"fila %d" % (wt.y if wt != null else -1))

	# --- giro diagonal y agarre por cercanía -----------------------------
	main.start_game(1)
	await frames(2)
	for row in main.world.tiles:
		for t in row:
			if t.item != null:
				main.destroy_item(t.item)
				t.item = null
	p = main.players[0]
	p.teleport(10, 6, Vector2i(0, -1))
	p.face_towards(Vector2(1.0, -1.0), 1.0)
	check("en diagonal el cuerpo mira en diagonal",
		absf(angle_difference(p.yaw, PI * 0.75)) < 0.12, "yaw=%.2f" % p.yaw)
	check("para interactuar queda el eje dominante", p.facing == Vector2i(1, 0),
		str(p.facing))

	p.teleport(10, 6, Vector2i(0, -1))        # mirando al norte
	var side: CarryItem = CarryItem.residue("pet")
	ItemVisuals.build(side)
	main.move_item_to_tile(side, main.world.tile_at(11, 6))   # a la derecha
	main.player_use(p, p.front_tile())                        # el frente está vacío
	check("se recoge lo que está al costado sin mirarlo", p.carrying == side)
	main.destroy_item(side)
	p.carrying = null

	var behind: CarryItem = CarryItem.residue("lata")
	ItemVisuals.build(behind)
	main.move_item_to_tile(behind, main.world.tile_at(10, 7))  # atrás
	main.player_use(p, p.front_tile())
	check("también se recoge lo que quedó atrás", p.carrying == behind)
	main.destroy_item(behind)
	p.carrying = null

	var far: CarryItem = CarryItem.residue("vidrio")
	ItemVisuals.build(far)
	main.move_item_to_tile(far, main.world.tile_at(10, 3))     # tres celdas
	main.player_use(p, p.front_tile())
	check("no se recoge lo que está lejos", p.carrying == null)
	main.destroy_item(far)

	var palm: CellData = main.world.tile_at(2, 7)
	check("los props grandes reservan su celda", palm != null and palm.decor == "palm",
		"decor=%s" % (palm.decor if palm != null else "?"))

	# --- presión: la basura que se pierde --------------------------------
	main.start_game(1)
	await frames(2)
	# playa limpia: si queda vidrio de la aparición inicial, se rompe también y
	# el conteo de castigos deja de ser determinista
	for row in main.world.tiles:
		for t in row:
			if t.item != null:
				main.destroy_item(t.item)
				t.item = null
	var glass: CarryItem = main.spawner.spawn_one("vidrio")
	main._tick_decay(1.0)
	check("el vidrio avisa con un aro de cuenta atrás", glass.ring != null)
	var pen_before: int = int(main.stats["penalties"])
	main._tick_decay(GameConfig.GLASS_BREAK_TIME)
	check("el vidrio de la arena se rompe solo", glass.node == null)
	check("el vidrio roto descuenta", int(main.stats["penalties"]) == pen_before + 1,
		"%d -> %d" % [pen_before, int(main.stats["penalties"])])

	# basura flotante: se alcanza desde la orilla y se hunde si nadie la agarra
	var wtile: CellData = main.world.tile_at(5, 11)
	if wtile != null and wtile.item != null:
		main.destroy_item(wtile.item)
		wtile.item = null
	var floating: CarryItem = CarryItem.residue("lata", "water")
	ItemVisuals.build(floating)
	main.move_item_to_tile(floating, wtile)
	p = main.players[0]
	p.teleport(5, 10, Vector2i(0, 1))
	check("la basura del agua se alcanza desde la orilla",
		"recoger" in main.interaction_hint(p).to_lower(), main.interaction_hint(p))
	pen_before = int(main.stats["penalties"])
	main._tick_decay(GameConfig.SEA_SINK_TIME + 0.1)
	check("la basura del agua se hunde", floating.node == null)
	check("lo que se hundió descuenta", int(main.stats["penalties"]) == pen_before + 1)

	# la basura del mar suma doble a la cuota
	main.start_game(1)
	await frames(2)
	var sea_bag: CarryItem = CarryItem.bag(["pet"])
	sea_bag.water = ["pet"]
	ItemVisuals.build(sea_bag)
	main.move_item_to_player(sea_bag, main.players[0])
	main.deliver(main.players[0], sea_bag)
	check("la basura del mar suma doble a la cuota",
		int(main.delivered["pet"]) == 2, "%d" % int(main.delivered["pet"]))

	# tope: como mucho 3 castigos por minuto descuentan
	main.start_game(1)
	await frames(2)
	main.score = 100
	var score0: int = main.score
	for i in 6:
		main.penalty("prueba", Vector3.ZERO)
	check("el tope deja descontar solo 3 castigos por minuto",
		score0 - main.score == GameConfig.PENALTY * GameConfig.PENALTY_CAP,
		"descontó %d de %d" % [score0 - main.score, GameConfig.PENALTY * 6])
	check("los castigos igual quedan contados", int(main.stats["penalties"]) == 6)

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
	# Un GLB externo (p. ej. el "pescador low poly") puede no traer bisagras:
	# en ese caso el personaje se mueve igual pero sin animación de miembros.
	if hinges.is_empty():
		check("un modelo sin bisagras no rompe la animación", true,
			"modelo estático (sin rig)")
	else:
		check("el modelo trae las 6 bisagras", hinges.size() == 6,
			"hay %d: %s" % [hinges.size(), hinges.keys()])

	if hinges.is_empty():
		await frames(2)
		return

	p2.walk_phase = PI * 0.5
	p2.velocity = Vector3(0, 0, 1) * 2.0
	p2._animate(0.016)
	var l1: float = hinges["leg_l"].rotation.x
	var r1: float = hinges["leg_r"].rotation.x
	# el ala del sombrero es de una sola cara en el GLB: se veía hueca de abajo
	var ala: MeshInstance3D = null
	for mi in p2.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with("ala_"):
			ala = mi
			break
	var doble_cara := false
	if ala != null and ala.material_override is BaseMaterial3D:
		doble_cara = (ala.material_override as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED
	check("el ala del sombrero se ve sólida desde abajo", doble_cara,
		"ala=%s" % (ala != null))
	check("la copa del sombrero está tapada (no se ve hueca)",
		p2.find_child("tapa_sombrero", true, false) != null)
	check("el pelo tapa la calva entre el flequillo y el sombrero",
		p2.find_child("pelo_calva", true, false) != null)

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


	# --- arrancar desde el menú (el bug era que el menú quedaba encima) ----
	main.state = main.State.MENU
	main.home.abrir_menu()
	main.home.fila = 0
	main.home.sel = 0
	main.menu_confirmar()
	await frames(2)
	check("jugar desde el menú arranca y ESCONDE la pantalla de inicio",
		main.state == main.State.PLAYING and not main.home.visible,
		"estado=%d visible=%s" % [main.state, main.home.visible])
	check("una partida normal habilita la tienda de la run", main.en_run)

	main.state = main.State.MENU
	main.home.abrir_menu()
	main.home.fila = 3          # ARENA
	main.menu_confirmar()
	await frames(2)
	check("arena arranca en modo de pruebas",
		main.state == main.State.PLAYING and main.sandbox and not main.home.visible,
		"sandbox=%s" % main.sandbox)

	# --- save, desbloqueos por logros y colección ------------------------
	var ruta_real := SaveGame.ruta
	SaveGame.ruta = "user://test_save.cfg"
	SaveGame.reiniciar()
	check("arranca sin desbloqueos", not SaveGame.tiene("mujer") and SaveGame.dias_jugados == 0)

	check("completar el día 1 no abre a la jugadora 2",
		SaveGame.registrar_dia(true, 0, 100) == "" and not SaveGame.tiene("mujer"))
	var logro := SaveGame.registrar_dia(true, 1, 200)
	check("completar el día 2 abre a la jugadora 2",
		logro == "mujer" and SaveGame.tiene("mujer"), logro)
	check("el mismo logro no se repite", SaveGame.registrar_dia(true, 1, 200) == "")

	SaveGame.cargar(true)
	check("el progreso se guarda en disco",
		SaveGame.tiene("mujer") and SaveGame.dias_jugados == 3,
		"%d días jugados" % SaveGame.dias_jugados)

	# el menú respeta el bloqueo
	main.start_game(1)
	await frames(2)
	main.state = main.State.MENU
	main.home.abrir_menu()
	SaveGame.reiniciar()
	main.home.sel = 1
	main.home.fila = 0
	main.menu_confirmar()
	check("con la jugadora 2 bloqueada el menú no arranca",
		main.state == main.State.MENU and main.home.aviso != "", main.home.aviso)

	SaveGame.desbloquear("mujer")
	main.home.abrir_menu()
	main.home.sel = 1
	main.home.fila = 0
	main.menu_confirmar()
	await frames(2)
	check("desbloqueada, el menú arranca en cooperativo",
		main.state == main.State.PLAYING and main.player_count == 2,
		"jugadores %d" % main.player_count)

	# la tienda es SOLO de la run (afuera no se compra nada)
	main.home.cursor = 0
	main.home.compradas.clear()
	main.home.monedas = 20
	main.en_run = false
	main._comprar_carta()
	check("fuera de la run la tienda no compra", main.home.compradas.is_empty(),
		"%d compradas" % main.home.compradas.size())

	main.en_run = true
	main.home.monedas = 20
	main._comprar_carta()
	var precio0 := int(ShopCatalog.CARTAS[0]["precio"])
	check("dentro de la run compra y descuenta la plata",
		main.home.compradas.size() == 1 and main.home.monedas == 20 - precio0,
		"%d cartas · %d plata" % [main.home.compradas.size(), main.home.monedas])
	main._comprar_carta()
	check("la misma carta no se compra dos veces", main.home.compradas.size() == 1)
	main.en_run = false

	# limpieza: restaurar el save REAL (sin tocarlo) y borrar el de test
	SaveGame.ruta = ruta_real
	SaveGame.cargar(true)
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_save.cfg"):
		dir.remove("test_save.cfg")
