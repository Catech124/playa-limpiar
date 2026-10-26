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

	# --- clasificar (mantener) --------------------------------------------
	await tp(6, 3, Vector2i(0, 1))    # mesa de clasificar debajo
	await hold(0.6)
	check("clasificar está a medias a los 0.6 s", p.carrying != null and not p.carrying.classified,
		"progreso=%.2f" % (p.carrying.progress if p.carrying else -1.0))
	await hold(0.8)
	check("se clasifica al mantener ~1.2 s", p.carrying != null and p.carrying.classified)

	# --- mostrador: soltar, bolsa, fusionar -------------------------------
	await tp(12, 4, Vector2i(0, 1))
	use()
	check("suelta el residuo clasificado en el mostrador", main.world.tile_at(12, 5).item != null and p.carrying == null)

	await tp(9, 3, Vector2i(0, -1))   # dispensador de bolsas
	use()
	check("toma una bolsa limpia", p.carrying != null and p.carrying.is_bag() and p.carrying.clean)

	await tp(13, 4, Vector2i(0, 1))
	use()
	var bag_tile: CellData = main.world.tile_at(13, 5)
	check("deja la bolsa en el mostrador", bag_tile.item != null and bag_tile.item.is_bag() and p.carrying == null)

	await tp(12, 4, Vector2i(0, 1))
	use()   # coger el vidrio clasificado
	await tp(13, 4, Vector2i(0, 1))
	use()   # meterlo en la bolsa
	check("fusiona el residuo en la bolsa", bag_tile.item != null and bag_tile.item.contents.size() == 1,
		str(bag_tile.item.contents if bag_tile.item else []))

	# segundo vidrio, ciclo completo
	await tp(7, 3, Vector2i(0, -1))
	use()
	await tp(6, 3, Vector2i(0, 1))
	await hold(1.4)
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

	await tp(14, 3, Vector2i(0, -1))
	await hold(0.8)
	check("lavar está a medias al segundo", p.carrying != null and not p.carrying.clean)
	await hold(0.9)
	check("la bolsa queda limpia tras ~1.5 s", p.carrying != null and p.carrying.clean)

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
