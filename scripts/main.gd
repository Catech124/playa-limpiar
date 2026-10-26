extends Node3D
## Orquestador: escena, estado, reglas y bucle.
##
## Piezas del bucle (todas con nombre para poder discutirlas):
##   fuente   -> montones de basura y dispensador de bolsas
##   canal    -> mesa de clasificar / lavadero (trabajo sostenido)
##   buffer   -> mostradores (donde se acumula y se fusiona la bolsa)
##   sumidero -> camión de entrega (valida el pedido)
##   retorno  -> bolsas sucias (el "plato sucio" de Overcooked)

enum State { MENU, PLAYING, PAUSED, RESULTS }

var state: State = State.MENU
var world: GridWorld
var players: Array = []
var orders: OrderBook
var gulls: Gulls
var hud: Hud
var camera: Camera3D
var _cam_target := Vector3(12, 0, 8)
var _cam_dist := 14.0

var time_left := 0.0
var level_seconds := GameConfig.ROUND_SECONDS
var score := 0
var stats := {"served": 0, "expired": 0, "thrown": 0, "washed": 0}
var player_count := 1
var sandbox := false
var mismatch := 0.0

var toasts: Array = []
var flying: Array = []


func _ready() -> void:
	_build_environment()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	hud.camera = camera
	layer.add_child(hud)

	_reset_world(1)

	if "--test" in OS.get_cmdline_user_args():
		var t: Node = load("res://tests/headless_test.gd").new()
		t.main = self
		add_child(t)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot=") or arg == "--demo":
			var s: Node = load("res://tests/shot.gd").new()
			s.main = self
			add_child(s)
			break


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.17, 0.40, 0.68)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.88)
	sky_mat.ground_bottom_color = Color(0.10, 0.28, 0.40)
	sky_mat.ground_horizon_color = Color(0.72, 0.82, 0.88)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.80)
	env.ambient_light_energy = 0.40
	env.background_energy_multiplier = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -42, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 2.5
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 38.0
	_cam_setup()
	add_child(camera)
	camera.look_at_from_position(Vector3(12, 15.5, 26.0), Vector3(12, 0, 7.5), Vector3.UP)


# ------------------------------------------------------------------ estados
func is_menu() -> bool:
	return state == State.MENU


func is_playing() -> bool:
	return state == State.PLAYING


func is_paused() -> bool:
	return state == State.PAUSED


func is_results() -> bool:
	return state == State.RESULTS


func _reset_world(count: int) -> void:
	if world != null:
		world.queue_free()
		world = null
	for p in players:
		p.queue_free()
	players.clear()

	world = GridWorld.new()
	world.name = "World"
	add_child(world)
	world.build(Levels.MAP)

	player_count = count
	for i in count:
		var p := Player.new()
		p.name = "Player%d" % (i + 1)
		add_child(p)
		p.setup(i, GameConfig.KEYMAPS[i], world, self)
		var sp: Vector2i = world.spawns[i % world.spawns.size()]
		p.position = Vector3(sp.x + 0.5, 0.0, sp.y + 0.5)
		p.active = false
		players.append(p)


func start_game(count: int, is_sandbox := false) -> void:
	sandbox = is_sandbox
	_reset_world(count)
	for p in players:
		p.active = true

	orders = OrderBook.new()
	gulls = Gulls.new(self, world)
	toasts.clear()
	flying.clear()
	score = 0
	mismatch = 0.0
	stats = {"served": 0, "expired": 0, "thrown": 0, "washed": 0}
	level_seconds = Levels.SANDBOX_SECONDS if sandbox else GameConfig.ROUND_SECONDS
	time_left = level_seconds
	state = State.PLAYING


func _toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		for p in players:
			p.active = false
	elif state == State.PAUSED:
		state = State.PLAYING
		for p in players:
			p.active = true


func _finish() -> void:
	state = State.RESULTS
	for p in players:
		p.active = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := k.physical_keycode

	match state:
		State.MENU:
			if code == KEY_ENTER or code == KEY_SPACE or code == KEY_KP_ENTER:
				start_game(1)
			elif code == KEY_2:
				start_game(2)
			elif code == KEY_D:
				start_game(1, true)
		State.PLAYING:
			if code == KEY_P or code == KEY_ESCAPE:
				_toggle_pause()
			elif code == KEY_R:
				start_game(player_count, sandbox)
		State.PAUSED:
			if code == KEY_P or code == KEY_ESCAPE:
				_toggle_pause()
			elif code == KEY_R:
				start_game(player_count, sandbox)
		State.RESULTS:
			if code == KEY_R or code == KEY_ENTER:
				start_game(player_count, sandbox)
			elif code == KEY_ESCAPE:
				state = State.MENU
				_reset_world(1)


# ------------------------------------------------------------------ bucle
## Cámara de cooperativo: mira el punto medio entre jugadores con una
## inclinación de ~42° (se ve la cara, como en Overcooked) y se aleja lo justo
## para que ninguno quede fuera de cuadro.
func _cam_setup() -> void:
	_cam_target = Vector3(world.w * 0.5, 0.0, world.h * 0.5)
	camera.look_at_from_position(_cam_pos_for(_cam_target, _cam_dist), _cam_target + Vector3(0, 0.6, 0), Vector3.UP)


func _cam_pos_for(target: Vector3, dist: float) -> Vector3:
	var el := deg_to_rad(42.0)
	return target + Vector3(0.0, sin(el) * dist, cos(el) * dist)


func _cam_dist_for(spread: float) -> float:
	# 14 unidades alcanzan para una pantalla de ~10 celdas de alto; si se
	# separan, se abre hasta 30
	return clampf(12.5 + spread * 1.9, 12.5, 30.0)


func _update_camera(delta: float) -> void:
	if players.is_empty():
		return
	var mid := Vector3.ZERO
	for p in players:
		mid += p.position
	mid /= float(players.size())
	var spread := 0.0
	for p in players:
		spread = maxf(spread, mid.distance_to(p.position))
	var target := Vector3(mid.x, 0.0, mid.z)
	target.x = clampf(target.x, 5.0, maxf(5.0, world.w - 5.0))
	target.z = clampf(target.z, 4.0, maxf(4.0, world.h - 4.0))
	_cam_target = _cam_target.lerp(target, minf(1.0, delta * 3.0))
	_cam_dist = lerpf(_cam_dist, _cam_dist_for(spread), minf(1.0, delta * 2.0))
	camera.look_at_from_position(_cam_pos_for(_cam_target, _cam_dist),
		_cam_target + Vector3(0, 0.6, 0), Vector3.UP)


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return

	_update_camera(delta)

	time_left = maxf(0.0, time_left - delta)

	for o in orders.tick(delta):
		stats["expired"] += 1
		score = maxi(0, score - GameConfig.SCORE_EXPIRED_PENALTY)
		toast(Vector3(world.w * 0.5, 1.8, 3.0), "¡Pedido perdido!", "bad")

	gulls.tick(delta)
	_update_flying(delta)
	_update_toasts(delta)
	mismatch = maxf(0.0, mismatch - delta)

	if time_left <= 0.0:
		_finish()


func _update_toasts(delta: float) -> void:
	for i in range(toasts.size() - 1, -1, -1):
		var t: Dictionary = toasts[i]
		t["ttl"] -= delta
		t["rise"] += delta * 34.0
		if t["ttl"] <= 0.0:
			toasts.remove_at(i)


func _update_flying(delta: float) -> void:
	for f in flying.duplicate():
		f["t"] += delta / GameConfig.THROW_TIME
		var t: float = minf(f["t"], 1.0)
		var from: Vector3 = f["from"]
		var to: Vector3 = f["to"]
		var pos := from.lerp(to, t) + Vector3(0.0, sin(t * PI) * 1.1, 0.0)
		if f["item"].node != null:
			f["item"].node.position = pos
			f["item"].node.rotation.y += delta * 6.0
		if f["t"] >= 1.0:
			flying.erase(f)
			_land(f)


# ------------------------------------------------------------------ reglas
func player_use(p: Player, tile: CellData) -> void:
	var st: String = tile.station
	var held: CarryItem = p.carrying

	# 1. entrega en el camión
	if st == "delivery":
		if held != null and held.is_bag() and held.clean:
			deliver(p, held)
		elif held != null:
			toast(p.position + Vector3(0, 1.7, 0), "Solo bolsas limpias", "bad")
		else:
			toast(p.position + Vector3(0, 1.7, 0), "Trae una bolsa", "bad")
		return

	# 2. manos vacías: fuentes y recogida
	if held == null:
		if st == "pile":
			var item := CarryItem.residue(tile.pool[randi() % tile.pool.size()])
			ItemVisuals.build(item)
			move_item_to_player(item, p)
			return
		if st == "bags":
			if count_bags() >= GameConfig.BAG_STOCK:
				toast(p.position + Vector3(0, 1.7, 0), "No quedan bolsas: hay que lavar", "bad")
				return
			var bag := CarryItem.bag()
			ItemVisuals.build(bag)
			move_item_to_player(bag, p)
			return
		if tile.item != null:
			var it: CarryItem = tile.item
			tile.item = null
			move_item_to_player(it, p)
			return
		return

	# 3. con algo en la mano: colocar / fusionar
	if try_place(tile, held):
		p.carrying = null


func player_channel(p: Player, tile: CellData, delta: float) -> bool:
	var item: CarryItem = p.carrying
	if item == null:
		return false

	if tile.station == "sort" and item.is_residue() and not item.classified:
		item.progress += delta / GameConfig.CLASSIFY_TIME
		if item.progress >= 1.0:
			item.progress = 0.0
			item.classified = true
			ItemVisuals.rebuild(item)
			toast(p.position + Vector3(0, 2.1, 0), "Clasificado", "good")
		return true

	if tile.station == "wash" and item.is_bag() and not item.clean:
		item.progress += delta / GameConfig.WASH_TIME
		if item.progress >= 1.0:
			item.progress = 0.0
			item.clean = true
			item.contents.clear()
			ItemVisuals.rebuild(item)
			stats["washed"] += 1
			toast(p.position + Vector3(0, 2.1, 0), "Bolsa limpia", "good")
		return true

	return false


func try_place(tile: CellData, item: CarryItem) -> bool:
	if item == null or not tile.can_hold():
		return false

	var on_tile: CarryItem = tile.item
	if on_tile == null:
		move_item_to_tile(item, tile)
		return true

	# bolsa sobre la mesa + residuo en la mano
	if on_tile.is_bag() and item.is_residue():
		if fill_bag(on_tile, item):
			destroy_item(item)
			return true
		return false

	# residuo sobre la mesa + bolsa en la mano
	if item.is_bag() and on_tile.is_residue():
		if fill_bag(item, on_tile):
			destroy_item(on_tile)
			tile.item = null
			move_item_to_tile(item, tile)
			return true
		return false

	return false


func fill_bag(bag: CarryItem, residue: CarryItem) -> bool:
	if not bag.clean:
		toast(Vector3(residue.node.position.x if residue.node else 0, 1.8, residue.node.position.z if residue.node else 0), "La bolsa está sucia", "bad")
		return false
	if not residue.classified:
		toast(Vector3(residue.node.position.x if residue.node else 0, 1.8, residue.node.position.z if residue.node else 0), "Clasifícalo primero", "bad")
		return false
	if not bag.has_room():
		toast(Vector3(residue.node.position.x if residue.node else 0, 1.8, residue.node.position.z if residue.node else 0), "Bolsa llena", "bad")
		return false
	bag.contents.append(residue.type)
	ItemVisuals.rebuild(bag)
	return true


func deliver(p: Player, bag: CarryItem) -> void:
	if bag.contents.is_empty():
		toast(p.position + Vector3(0, 1.7, 0), "La bolsa está vacía", "bad")
		return

	var order := orders.match_contents(bag.contents)
	if order == null:
		mismatch = 0.5
		toast(p.position + Vector3(0, 1.7, 0), "No cuadra con el pedido", "bad")
		return

	var ratio := clampf(order.patience / order.patience_max, 0.0, 1.0)
	var pts := GameConfig.SCORE_BASE + int(round(GameConfig.SCORE_SPEED_BONUS * ratio))
	score += pts
	stats["served"] += 1
	orders.consume(order)
	p.carrying = null
	destroy_item(bag)
	toast(p.position + Vector3(0, 1.9, 0), "+%d" % pts, "good")
	spawn_dirty_bag()


func spawn_dirty_bag() -> void:
	var returns := world.tiles_of("return")
	if returns.is_empty():
		return
	var ret: CellData = returns[0]
	var bag := CarryItem.bag(false)
	ItemVisuals.build(bag)
	if ret.item == null:
		move_item_to_tile(bag, ret)
	else:
		var floors := world.free_floors_near(ret.x, ret.y, 5)
		if not floors.is_empty():
			move_item_to_tile(bag, floors[0])
		else:
			destroy_item(bag)


func count_bags() -> int:
	var n := 0
	for row in world.tiles:
		for t in row:
			if t.item != null and t.item.is_bag():
				n += 1
	for p in players:
		if p.carrying != null and p.carrying.is_bag():
			n += 1
	return n


func throw_item(p: Player) -> void:
	var item: CarryItem = p.carrying
	if item == null:
		return

	var f := p.facing
	var last_free: CellData = world.tile_at(p.tile_x(), p.tile_y())
	var landing: CellData = null

	for step in range(1, int(GameConfig.THROW_RANGE) + 1):
		var tx := int(floor(p.position.x + f.x * step))
		var ty := int(floor(p.position.z + f.y * step))
		var t := world.tile_at(tx, ty)
		if t == null:
			break
		if t.is_solid():
			if t.can_hold():
				landing = t
			break
		if t.item == null:
			last_free = t
		landing = t

	if landing == null:
		landing = last_free
	if landing == null or item.node == null:
		return

	p.carrying = null
	stats["thrown"] += 1
	parent_item(item.node, world.items_root)

	var from := p.position + Vector3(0, 1.3, 0)
	var to := world.item_position(landing)
	flying.append({"item": item, "from": from, "to": to, "tile": landing, "t": 0.0, "player": p})


func _land(f: Dictionary) -> void:
	var item: CarryItem = f["item"]
	var tile: CellData = f["tile"]

	if tile != null and try_place(tile, item):
		return

	var floors: Array = []
	if tile != null:
		floors = world.free_floors_near(tile.x, tile.y, 4)
	if not floors.is_empty():
		move_item_to_tile(item, floors[0])
	elif f["player"].carrying == null:
		move_item_to_player(item, f["player"])
	else:
		destroy_item(item)


# ------------------------------------------------------------------ ítems
## Reparentar es delicado: si el nodo recién se creó todavía no tiene padre.
func parent_item(node: Node3D, new_parent: Node) -> void:
	if node == null:
		return
	if node.get_parent() == null:
		new_parent.add_child(node)
	elif node.get_parent() != new_parent:
		node.reparent(new_parent, false)


## Un ítem en el piso ocupa la celda: sin esto el jugador lo atraviesa (en
## Overcooked no se puede caminar por encima de una bolsa).
func item_blocker(item: CarryItem, on: bool) -> void:
	if item.node == null:
		return
	var node := item.node.get_node_or_null("Blocker")
	if on and node == null:
		var body := StaticBody3D.new()
		body.name = "Blocker"
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.30
		cyl.height = 0.9
		cs.shape = cyl
		cs.position = Vector3(0, 0.45, 0)
		body.add_child(cs)
		item.node.add_child(body)
	elif not on and node != null:
		item.node.remove_child(node)   # queue_free solo lo saca al fin del frame
		node.queue_free()


func move_item_to_tile(item: CarryItem, tile: CellData) -> void:
	tile.item = item
	if item.node == null:
		return
	item_blocker(item, true)
	parent_item(item.node, world.items_root)
	item.node.position = world.item_position(tile)
	item.node.rotation = Vector3.ZERO
	item.node.scale = Vector3.ONE


func move_item_to_player(item: CarryItem, p: Player) -> void:
	p.carrying = item
	if item.node == null:
		return
	item_blocker(item, false)
	parent_item(item.node, p.carry_anchor)
	item.node.position = Vector3.ZERO
	item.node.rotation = Vector3.ZERO
	item.node.scale = Vector3.ONE


func destroy_item(item: CarryItem) -> void:
	if item == null:
		return
	if item.node != null:
		item.node.queue_free()
		item.node = null


# ------------------------------------------------------------------ feedback
func toast(pos: Vector3, text: String, kind := "info") -> void:
	toasts.append({"pos": pos, "text": text, "kind": kind, "ttl": 1.5, "rise": 0.0})


func stars_earned() -> int:
	var n := 0
	for threshold in GameConfig.STARS:
		if score >= int(threshold):
			n += 1
	return n


# ------------------------------------------------------------------ ayudas UI
func interaction_hint(p: Player) -> String:
	var tile := p.front_tile()
	if tile == null:
		return ""

	var st: String = tile.station
	var held: CarryItem = p.carrying
	var key := "ESPACIO"
	if players.size() > 1 and p.index == 1:
		key = "ENTER"

	match st:
		"delivery":
			if held != null and held.is_bag() and held.clean:
				return "[%s] Entregar bolsa" % key
			if held != null and held.is_bag() and not held.clean:
				return "Esa bolsa está sucia: hay que lavarla"
			if held != null:
				return "Solo bolsas con residuos clasificados"
			return "Camión de reciclaje"
		"pile":
			if held == null:
				return "[%s] Recoger residuo" % key
			return "Montón de basura"
		"bags":
			if held != null:
				return "Bolsas limpias"
			if count_bags() >= GameConfig.BAG_STOCK:
				return "Sin bolsas: hay que lavar"
			return "[%s] Tomar bolsa (%d/%d)" % [key, count_bags(), GameConfig.BAG_STOCK]
		"sort":
			if held != null and held.is_residue() and not held.classified:
				return "[MANTÉN] Clasificar"
			if held != null and held.is_residue():
				return "Ya está clasificado"
			return "Mesa de clasificación"
		"wash":
			if held != null and held.is_bag() and not held.clean:
				return "[MANTÉN] Lavar bolsa"
			return "Lavadero"
		"return":
			if held == null and tile.item != null:
				return "[%s] Coger bolsa sucia" % key
			return "Bolsas sucias"
		"counter":
			if held == null and tile.item != null:
				return "[%s] Coger" % key
			if held != null and tile.item == null:
				return "[%s] Soltar" % key
			if held != null and held.is_residue() and tile.item != null and tile.item.is_bag():
				return "[%s] Meter en la bolsa" % key
			if held != null and held.is_bag() and tile.item != null and tile.item.is_residue():
				return "[%s] Meter en la bolsa" % key
			return ""

	if held == null and tile.item != null:
		return "[%s] Coger" % key
	if held != null and tile.item == null and not tile.is_solid():
		return "[%s] Soltar" % key
	return ""
