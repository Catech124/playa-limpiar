extends Node
## Autotest de mecánicas. Se lanza con:
##   godot --headless --path . -- --test
## Ejercita las MISMAS funciones que usa el input real (player_use,
## player_channel, throw_item), teleportando al jugador entre estaciones.

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


func hold(seconds: float) -> void:
	var p = main.players[0]
	var tile: CellData = p.front_tile()
	var t := 0.0
	while t < seconds:
		var d: float = get_physics_process_delta_time()
		main.player_channel(p, tile, d)
		await get_tree().physics_frame
		t += d


func make_order(vidrio := 2, petals := 0) -> void:
	var o := OrderBook.Order.new()
	o.id = 999
	o.need = {}
	var parts: Array = []
	for i in vidrio:
		o.need["vidrio"] = int(o.need.get("vidrio", 0)) + 1
		parts.append("vidrio")
	for i in petals:
		o.need["pet"] = int(o.need.get("pet", 0)) + 1
		parts.append("pet")
	o.items = parts.size()
	o.patience = GameConfig.ORDER_PATIENCE
	o.patience_max = GameConfig.ORDER_PATIENCE
	parts.sort()
	o.signature = "+".join(parts)
	main.orders.list.clear()
	main.orders.list.append(o)
	main.orders.timer = 999.0


# ------------------------------------------------------------------ tests
func _run() -> void:
	main.start_game(1)
	await frames(2)
	var p = main.players[0]

	check("arranca en juego", main.is_playing(), "estado=%d" % main.state)
	check("aparece en el spawn (3,10)", p.tile_x() == 3 and p.tile_y() == 10, "%d,%d" % [p.tile_x(), p.tile_y()])

	# --- movimiento -------------------------------------------------------
	var start_x: float = p.position.x
	for i in 30:
		p.move_step(Vector2(1, 0))
		await get_tree().physics_frame
	check("se mueve a la derecha", p.position.x > start_x + 0.8, "x %.2f -> %.2f" % [start_x, p.position.x])

	await tp(3, 3, Vector2i(0, -1))
	for i in 30:
		p.move_step(Vector2(0, -1))
		await get_tree().physics_frame
	check("la estación bloquea (no atraviesa)", p.position.z > 2.9, "z=%.2f" % p.position.z)

	# --- recoger del montón ------------------------------------------------
	await tp(7, 3, Vector2i(0, -1))   # montón de vidrio
	use()
	check("recoge un residuo del montón", p.carrying != null and p.carrying.is_residue() and p.carrying.type == "vidrio",
		p.carrying.label() if p.carrying else "nada")

	# --- contenedores: el residuo se TIRA, no se etiqueta -----------------
	var score_bin: int = main.score
	await tp(10, 3, Vector2i(0, 1))    # contenedor VIDRIO
	use()
	check("tirar en el contenedor correcto suma", main.score > score_bin and p.carrying == null,
		"%d -> %d" % [score_bin, main.score])

	# residuo equivocado: no entra y penaliza
	await tp(3, 3, Vector2i(0, -1))    # montón PET
	use()
	await tp(10, 3, Vector2i(0, 1))    # contenedor VIDRIO
	var score_bad: int = main.score
	use()
	check("el contenedor equivocado no lo acepta", p.carrying != null,
		"sigue con %s" % (p.carrying.type if p.carrying else "nada"))
	check("y penaliza", main.score <= score_bad, "%d -> %d" % [score_bad, main.score])
	p.carrying = null

	# --- mostrador: soltar, bolsa, fusionar (sin clasificar) --------------
	await tp(7, 3, Vector2i(0, -1))    # otro vidrio
	use()
	await tp(12, 4, Vector2i(0, 1))
	use()
	check("deja el residuo en el mostrador", main.world.tile_at(12, 5).item != null and p.carrying == null)

	await tp(9, 3, Vector2i(0, -1))    # dispensador de bolsas
	use()
	check("toma una bolsa limpia", p.carrying != null and p.carrying.is_bag() and p.carrying.clean)

	await tp(13, 4, Vector2i(0, 1))
	use()
	var bag_tile: CellData = main.world.tile_at(13, 5)
	check("deja la bolsa en el mostrador", bag_tile.item != null and bag_tile.item.is_bag() and p.carrying == null)

	await tp(12, 4, Vector2i(0, 1))
	use()   # coger el vidrio
	await tp(13, 4, Vector2i(0, 1))
	use()   # meterlo en la bolsa
	check("fusiona el residuo en la bolsa", bag_tile.item != null and bag_tile.item.contents.size() == 1,
		str(bag_tile.item.contents if bag_tile.item else []))

	# segundo vidrio, ciclo completo
	await tp(7, 3, Vector2i(0, -1))
	use()
	await tp(13, 4, Vector2i(0, 1))
	use()
	check("la bolsa acumula 2 residuos", bag_tile.item != null and bag_tile.item.contents.size() == 2,
		str(bag_tile.item.contents if bag_tile.item else []))

	# --- entrega ----------------------------------------------------------
	make_order(2, 0)
	await tp(13, 4, Vector2i(0, 1))
	use()   # coger la bolsa llena
	check("recoge la bolsa llena", p.carrying != null and p.carrying.is_bag() and p.carrying.contents.size() == 2)

	var score_before: int = main.score
	await tp(10, 11, Vector2i(0, 1))
	use()
	check("entrega el pedido y suma puntos", main.score > score_before and main.stats["served"] == 1,
		"puntos %d -> %d" % [score_before, main.score])
	check("la entrega deja una bolsa sucia", main.world.tile_at(16, 12).item != null and not main.world.tile_at(16, 12).item.clean)

	# --- entrega que no cuadra --------------------------------------------
	make_order(0, 0)
	var o2 := OrderBook.Order.new()
	o2.need = {"pet": 3}
	o2.patience = 40.0
	o2.patience_max = 40.0
	o2.signature = "pet+pet+pet"
	main.orders.list.clear()
	main.orders.list.append(o2)

	var wrong := CarryItem.bag(true, ["lata"])
	ItemVisuals.build(wrong)
	main.move_item_to_player(wrong, p)
	var score2: int = main.score
	await tp(10, 11, Vector2i(0, 1))
	use()
	check("una bolsa que no cuadra no puntúa", main.score == score2, "puntos %d" % main.score)

	# --- lavar ------------------------------------------------------------
	p.carrying = null
	main.destroy_item(wrong)
	var dirty := CarryItem.bag(false)
	ItemVisuals.build(dirty)
	main.move_item_to_tile(dirty, main.world.tile_at(16, 12))

	await tp(16, 11, Vector2i(0, 1))
	use()
	check("recoge la bolsa sucia", p.carrying != null and p.carrying.is_bag() and not p.carrying.clean)

	# dejarla en el lavadero (no se lava en la mano)
	var wash_tile: CellData = main.world.tile_at(14, 2)
	await tp(14, 3, Vector2i(0, -1))
	use()
	check("la bolsa sucia queda en el lavadero", p.carrying == null and not wash_tile.items.is_empty(),
		"%d en la pila" % wash_tile.items.size())
	await frames(int(GameConfig.WASH_TIME / get_physics_process_delta_time()) + 12)
	var clean_ready := false
	for it in wash_tile.items:
		if it.is_bag() and it.clean:
			clean_ready = true
	check("al terminar el lavado hay una bolsa limpia en la repisa", clean_ready)
	use()
	check("y se retira de la repisa", p.carrying != null and p.carrying.is_bag() and p.carrying.clean)

	# --- lanzar -----------------------------------------------------------
	await tp(7, 3, Vector2i(0, -1))
	use()   # recoger un vidrio
	await tp(10, 8, Vector2i(0, -1))
	main.throw_item(p)
	check("lanzar saca el ítem de la mano", p.carrying == null and main.flying.size() == 1)
	await frames(40)
	check("el ítem aterriza en el suelo", main.flying.is_empty())

	# --- pedidos que expiran ----------------------------------------------
	var expired_before: int = main.stats["expired"]
	var o3 := OrderBook.Order.new()
	o3.need = {"pet": 1}
	o3.patience = 0.2
	o3.patience_max = 40.0
	o3.signature = "pet"
	main.orders.list.clear()
	main.orders.list.append(o3)
	main.orders.timer = 999.0
	await frames(40)
	check("el pedido expira y se contabiliza", main.stats["expired"] > expired_before,
		"%d -> %d" % [expired_before, main.stats["expired"]])

	# --- fin de ronda y reinicio ------------------------------------------
	main.time_left = 0.05
	await frames(10)
	check("al acabar el tiempo pasa a resultados", main.is_results(), "estado=%d" % main.state)

	main.start_game(1)
	await frames(2)
	check("R reinicia la partida", main.is_playing() and main.score == 0)

	# --- colisiones contra el mobiliario -----------------------------------
	var pc = main.players[0]
	# mesa de clasificar en (6,4): me paro al lado y empujo hacia ella
	pc.teleport(5, 4, Vector2i(1, 0))
	await frames(2)
	var x0: float = pc.position.x
	for i in 40:
		pc.velocity = Vector3(4.0, 0.0, 0.0)
		pc.move_and_slide()
		await get_tree().physics_frame
	check("no atraviesa una mesa", pc.position.x < 6.02,
		"x %.2f -> %.2f (la celda sólida empieza en 6.00)" % [x0, pc.position.x])
	check("se queda pegado a la mesa", pc.position.x > 5.55, "x=%.2f" % pc.position.x)

	# --- un ítem en el piso bloquea el paso -------------------------------
	var pitem = main.players[0]
	var floor_tile: CellData = main.world.tile_at(8, 12)
	pitem.teleport(7, 12, Vector2i(1, 0))
	await frames(2)
	var bolsa := CarryItem.bag(true)
	ItemVisuals.build(bolsa)          # el nodo visual es el que lleva el collider
	main.move_item_to_tile(bolsa, floor_tile)
	await frames(2)
	check("el ítem del piso tiene collider", bolsa.node != null and bolsa.node.get_node_or_null("Blocker") != null)
	for i in 40:
		pitem.velocity = Vector3(4.0, 0.0, 0.0)
		pitem.move_and_slide()
		await get_tree().physics_frame
	# tolerancia: el paso discreto del motor deja hasta ~0.07 de penetración
	check("no atraviesa la bolsa del piso", pitem.position.x < 8.10,
		"x=%.2f (la bolsa está en la celda 8, centro 8.5)" % pitem.position.x)
	main.move_item_to_player(bolsa, pitem)
	check("al levantarla se libera el paso", bolsa.node.get_node_or_null("Blocker") == null)
	pitem.carrying = null

	# --- gaviotas: roban una bolsa limpia de la repisa --------------------
	var sink: CellData = main.world.tile_at(14, 2)
	sink.items.clear()
	var clean_bag := CarryItem.bag(true)
	ItemVisuals.build(clean_bag)
	sink.items.append(clean_bag)
	main.gulls.list.clear()
	main.gulls.spawn()
	check("aparece una gaviota si hay bolsa limpia en la repisa", main.gulls.list.size() == 1,
		"%d gaviotas" % main.gulls.list.size())

	# --- rig y animación ---------------------------------------------------
	var p2 = main.players[0]
	var hinges: Dictionary = p2._hinges
	check("el modelo trae las 6 bisagras", hinges.size() == 6,
		"hay %d: %s" % [hinges.size(), hinges.keys()])

	# caminando: una pierna adelante y la otra atrás
	p2.walk_phase = PI * 0.5
	p2.velocity = Vector3(0, 0, 1) * 2.0
	p2._animate(0.016)
	var l1: float = hinges["leg_l"].rotation.x
	var r1: float = hinges["leg_r"].rotation.x
	check("caminar mueve las piernas en oposición",
		absf(l1) > 0.2 and absf(r1) > 0.2 and signf(l1) != signf(r1),
		"leg_l=%.2f leg_r=%.2f" % [l1, r1])

	# en reposo: piernas rectas, cabeza respirando
	p2.velocity = Vector3.ZERO
	p2._animate(0.016)
	check("quieto deja las piernas rectas",
		absf(hinges["leg_l"].rotation.x) < 0.001 and absf(hinges["leg_r"].rotation.x) < 0.001,
		"leg_l=%.3f" % hinges["leg_l"].rotation.x)
	check("quieto igual mueve la cabeza", absf(hinges["head"].rotation.z) > 0.0001,
		"head.z=%.4f" % hinges["head"].rotation.z)

	# llevando una caja: los brazos van adelante
	var before: float = hinges["arm_l"].rotation.x
	p2.carrying = CarryItem.bag(true)
	p2._animate(0.016)
	check("llevando algo los brazos van adelante",
		hinges["arm_l"].rotation.x < before - 0.5,
		"brazo %.2f -> %.2f" % [before, hinges["arm_l"].rotation.x])
	p2.carrying = null
