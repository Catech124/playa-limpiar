extends Node3D
## Orquestador: escena, estado, reglas y bucle.
##
## El bucle de la v2 (Fase 1):
##   fuente   -> basura tirada en la playa (TrashSpawner)
##   buffer   -> la bolsa que cuelga en la boca del contenedor
##   sumidero -> camión: entregar la bolsa suma a la CUOTA DEL DÍA
##
## No hay pedidos ni lavado: el objetivo es cumplir la cuota por tipo antes de
## que termine la jornada (reloj de 24 h comprimido).

enum State { MENU, PLAYING, PAUSED, RESULTS }

var state: State = State.MENU
var world: GridWorld
var players: Array = []
var gulls: Gulls
var spawner: TrashSpawner
var hud: Hud
var camera: Camera3D
var sun: DirectionalLight3D
var _cam_target := Vector3(12, 0, 8)
var _cam_dist := 14.0

var level_index := 0
var level: Dictionary = {}
var time_left := 0.0
var level_seconds := 180.0
var quota := {}                  # objetivo por tipo
var delivered := {}              # entregado por tipo
var score := 0
var won := false
var stats := {"delivered": 0, "spawned": 0, "binned": 0, "stolen": 0, "penalties": 0, "thrown": 0}
var player_count := 1
var sandbox := false

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

	sun = DirectionalLight3D.new()
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
	if gulls != null:
		for g in gulls.list:
			if g.node != null and is_instance_valid(g.node):
				g.node.queue_free()
		gulls.list.clear()
		gulls = null
	spawner = null
	flying.clear()

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


func start_game(count: int, is_sandbox := false, idx := 0) -> void:
	sandbox = is_sandbox
	level_index = clampi(idx, 0, Levels.LEVELS.size() - 1)
	level = Levels.SANDBOX.duplicate(true) if sandbox else Levels.LEVELS[level_index].duplicate(true)

	_reset_world(count)
	for p in players:
		p.active = true

	gulls = Gulls.new(self, world)
	spawner = TrashSpawner.new(self, world)
	spawner.setup(level)

	toasts.clear()
	flying.clear()
	score = 0
	won = false
	stats = {"delivered": 0, "spawned": 0, "binned": 0, "stolen": 0, "penalties": 0, "thrown": 0}
	level_seconds = float(level.get("seconds", 180.0))
	time_left = level_seconds
	quota = (level.get("quota", {}) as Dictionary).duplicate()
	delivered = {}
	for t in GameConfig.RESIDUE_ORDER:
		delivered[t] = 0
	state = State.PLAYING
	_cam_setup()
	_update_light()


func _toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		for p in players:
			p.active = false
	elif state == State.PAUSED:
		state = State.PLAYING
		for p in players:
			p.active = true


func _finish(win: bool) -> void:
	won = win
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
				start_game(1, false, 0)
			elif code == KEY_2:
				start_game(2, false, 0)
			elif code == KEY_D:
				start_game(1, true, 0)
		State.PLAYING:
			if code == KEY_P or code == KEY_ESCAPE:
				_toggle_pause()
			elif code == KEY_R:
				start_game(player_count, sandbox, level_index)
		State.PAUSED:
			if code == KEY_P or code == KEY_ESCAPE:
				_toggle_pause()
			elif code == KEY_R:
				start_game(player_count, sandbox, level_index)
		State.RESULTS:
			if code == KEY_R:
				start_game(player_count, sandbox, level_index)
			elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
				if sandbox:
					state = State.MENU
					_reset_world(1)
				elif won and level_index + 1 < Levels.LEVELS.size():
					start_game(player_count, false, level_index + 1)
				else:
					start_game(player_count, false, 0)
			elif code == KEY_ESCAPE:
				state = State.MENU
				_reset_world(1)


# ------------------------------------------------------------------ bucle
## Cámara de cooperativo: mira el punto medio entre jugadores con una
## inclinación de ~42° (se ve la cara, como en Overcooked) y se aleja lo justo
## para que ninguno quede fuera de cuadro.
func _cam_setup() -> void:
	# ojo: en _ready() todavía no hay mundo (la cámara se crea antes que el nivel)
	var center := Vector3(12, 0, 8)
	if world != null:
		center = Vector3(world.w * 0.5, 0.0, world.h * 0.5)
	_cam_target = center
	_cam_dist = 20.0
	camera.look_at_from_position(_cam_pos_for(_cam_target, _cam_dist), _cam_target + Vector3(0, 0.6, 0), Vector3.UP)


func _cam_pos_for(target: Vector3, dist: float) -> Vector3:
	var el := deg_to_rad(42.0)
	return target + Vector3(0.0, sin(el) * dist, cos(el) * dist)


func _cam_dist_for(spread: float) -> float:
	# El encuadre no se abre sin freno: a 24 unidades de distancia los
	# personajes quedan del tamaño de una uña. Si se separan mucho, uno
	# puede quedar al borde de la pantalla (como en Overcooked) en vez de
	# alejar la cámara hasta perder el juego de vista.
	return clampf(11.0 + spread * 1.15, 11.0, 15.5)


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

	spawner.tick(delta)
	if not sandbox:
		gulls.tick(delta)

	_update_flying(delta)
	_update_toasts(delta)
	_update_light()

	if not sandbox:
		if quota_met():
			_finish(true)
		elif time_left <= 0.0:
			_finish(false)


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


## La luz sigue al reloj: amanecer cálido, sol alto al mediodía, atardecer
## naranja. Es gratis y hace que la jornada se sienta avanzar.
func _update_light() -> void:
	if sun == null:
		return
	var p := day_progress()
	var arc := sin(PI * p)
	sun.rotation_degrees = Vector3(-18.0 - 70.0 * arc, lerpf(-78.0, -12.0, p), 0.0)
	sun.light_energy = lerpf(0.55, 0.92, arc)
	var golden := 1.0 - arc
	sun.light_color = Color(1, 1, 1).lerp(Color(1.0, 0.68, 0.43), golden * 0.85)


# ------------------------------------------------------------------ reloj
func day_progress() -> float:
	if level_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - time_left / level_seconds, 0.0, 1.0)


func clock_minutes() -> float:
	return fmod(GameConfig.DAY_START_MINUTES + GameConfig.DAY_MINUTES * day_progress(), 1440.0)


func clock_text() -> String:
	var m := int(clock_minutes())
	return "%02d:%02d" % [int(m / 60), m % 60]


func level_name() -> String:
	return String(level.get("name", ""))


func days_total() -> int:
	return Levels.LEVELS.size()


# ------------------------------------------------------------------ cuota
func quota_met() -> bool:
	if quota.is_empty():
		return false
	for t in quota.keys():
		if int(delivered.get(t, 0)) < int(quota[t]):
			return false
	return true


func total_delivered() -> int:
	var n := 0
	for t in delivered.keys():
		n += int(delivered[t])
	return n


func total_quota() -> int:
	var n := 0
	for t in quota.keys():
		n += int(quota[t])
	return n


func quota_rows() -> Array:
	var rows: Array = []
	for t in GameConfig.RESIDUE_ORDER:
		var need := int(quota.get(t, 0))
		var have := int(delivered.get(t, 0))
		rows.append({
			"type": t,
			"label": String(GameConfig.RESIDUES[t]["label"]),
			"color": GameConfig.RESIDUES[t]["color"],
			"icon": String(GameConfig.RESIDUES[t]["icon"]),
			"done": have,
			"need": need,
			"ratio": 1.0 if need <= 0 else clampf(float(have) / float(need), 0.0, 1.0),
		})
	return rows


func stars_earned() -> int:
	if not won or level_seconds <= 0.0:
		return 0
	var ratio := time_left / level_seconds
	if ratio >= 0.40:
		return 3
	if ratio >= 0.18:
		return 2
	return 1


func penalty(reason: String, pos: Vector3) -> void:
	stats["penalties"] = int(stats.get("penalties", 0)) + 1
	score = maxi(0, score - GameConfig.PENALTY)
	toast(pos, "%s −%d" % [reason, GameConfig.PENALTY], "bad")


# ------------------------------------------------------------------ reglas
func player_use(p: Player, tile: CellData) -> void:
	if tile == null:
		return
	var st: String = tile.station
	var held: CarryItem = p.carrying

	# 1. entrega: bolsa con basura -> suma a la cuota del día
	if st == "delivery":
		if held != null and held.is_bag():
			deliver(p, held)
		elif held != null:
			toast(p.position + Vector3(0, 1.7, 0), "La basura va al contenedor", "bad")
		else:
			toast(p.position + Vector3(0, 1.7, 0), "Traé una bolsa llena", "bad")
		return

	# 2. contenedor: la bolsa se cuelga en la boca y allí se llena
	if st == "bin":
		_use_bin(p, tile, held)
		return

	# 3. dispensador de bolsas
	if st == "bags":
		if held != null:
			toast(p.position + Vector3(0, 1.7, 0), "Manos ocupadas", "bad")
			return
		var bag := CarryItem.bag()
		ItemVisuals.build(bag)
		move_item_to_player(bag, p)
		return

	# 4. manos vacías: recoger del piso
	if held == null:
		if tile.item != null:
			var it: CarryItem = tile.item
			tile.item = null
			move_item_to_player(it, p)
		return

	# 5. con algo en la mano: soltar / meter en una bolsa del piso
	if try_place(tile, held):
		p.carrying = null


## Contenedor con boca de bolsa (decisión "bolsa primero"):
##   - con un residuo: entra en la bolsa si el tipo coincide
##   - con una bolsa: la cuelga (si no hay otra)
##   - con las manos vacías: retira la bolsa (llena o a medias)
func _use_bin(p: Player, tile: CellData, held: CarryItem) -> void:
	var bin_name := String(GameConfig.BIN_LABEL.get(tile.bin, "CONTENEDOR"))
	var at := tile.center() + Vector3(0, 0.9, 0)

	if held != null and held.is_residue():
		# El tipo se comprueba ANTES que la bolsa: tirar vidrio en el de latas es
		# un error del jugador y tiene que castigarse aunque no haya bolsa.
		if held.type != tile.bin:
			penalty("Ese no va en %s" % bin_name, at)
			return
		if tile.bag == null:
			toast(at, "Falta la bolsa en %s" % bin_name, "bad")
			return
		if not tile.bag.has_room():
			toast(at, "La bolsa está llena: llevala al camión", "bad")
			return
		tile.bag.contents.append(held.type)
		p.carrying = null
		destroy_item(held)
		ItemVisuals.rebuild(tile.bag)
		_update_bin_visual(tile)
		score += GameConfig.POINTS_PER_BIN
		stats["binned"] = int(stats.get("binned", 0)) + 1
		if tile.bag.is_full():
			toast(at, "¡%s llena! Al camión" % bin_name, "good")
		else:
			toast(at, "+1 en %s (%d/%d)" % [bin_name, tile.bag.contents.size(), GameConfig.BAG_CAPACITY], "good")
		return

	if held != null and held.is_bag():
		if tile.bag != null:
			toast(at, "Ya hay una bolsa en %s" % bin_name, "bad")
			return
		p.carrying = null
		tile.bag = held
		_update_bin_visual(tile)
		toast(at, "Bolsa colgada en %s" % bin_name, "good")
		return

	if held != null:
		toast(at, "Acá va basura", "bad")
		return

	# manos vacías
	if tile.bag != null:
		var bag := tile.bag
		tile.bag = null
		move_item_to_player(bag, p)
		if bag.is_full():
			toast(at, "¡Bolsa llena! Llevala al camión", "good")
		else:
			toast(at, "Bolsa fuera (%d/%d)" % [bag.contents.size(), GameConfig.BAG_CAPACITY], "info")
	else:
		toast(at, "Sin bolsa: tomá una en el dispensador", "bad")


## Entregar en el camión: cada residuo suma a su barra de cuota.
func deliver(p: Player, bag: CarryItem) -> void:
	if bag.contents.is_empty():
		toast(p.position + Vector3(0, 1.7, 0), "La bolsa está vacía", "bad")
		return

	var n := bag.contents.size()
	for t in bag.contents:
		delivered[t] = int(delivered.get(t, 0)) + 1
	stats["delivered"] = int(stats["delivered"]) + n
	score += n * GameConfig.POINTS_PER_ITEM

	p.carrying = null
	destroy_item(bag)
	toast(p.position + Vector3(0, 1.9, 0), "+%d entregados" % n, "good")

	if quota_met():
		_finish(true)


func try_place(tile: CellData, item: CarryItem) -> bool:
	if item == null or not tile.can_hold():
		return false

	var on_tile: CarryItem = tile.item
	if on_tile == null:
		move_item_to_tile(item, tile)
		return true

	# bolsa en el piso + residuo en la mano
	if on_tile.is_bag() and item.is_residue():
		if fill_bag(on_tile, item):
			destroy_item(item)
			return true
		return false

	# residuo en el piso + bolsa en la mano
	if item.is_bag() and on_tile.is_residue():
		if fill_bag(item, on_tile):
			destroy_item(on_tile)
			tile.item = null
			move_item_to_tile(item, tile)
			return true
		return false

	return false


func fill_bag(bag: CarryItem, residue: CarryItem) -> bool:
	if not bag.has_room():
		toast(Vector3(residue.node.position.x if residue.node else 0, 1.8, residue.node.position.z if residue.node else 0), "Bolsa llena", "bad")
		return false
	bag.contents.append(residue.type)
	ItemVisuals.rebuild(bag)
	return true


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
	stats["thrown"] = int(stats["thrown"]) + 1
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


## Solo las BOLSAS estorban el paso: una botella tirada en la arena se pisa.
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
		cyl.height = 1.8
		cs.shape = cyl
		cs.position = Vector3(0, 0.9, 0)
		body.add_child(cs)
		item.node.add_child(body)
	elif not on and node != null:
		item.node.remove_child(node)   # queue_free solo lo saca al fin del frame
		node.queue_free()


func move_item_to_tile(item: CarryItem, tile: CellData) -> void:
	tile.item = item
	_unhang(item)
	if item.node == null:
		return
	item_blocker(item, item.is_bag())
	parent_item(item.node, world.items_root)
	item.node.position = world.item_position(tile)
	item.node.rotation = Vector3.ZERO
	item.node.scale = Vector3.ONE


## Nodo visual del ítem (se crea si todavía no existe).
func _item_node(item: CarryItem) -> Node3D:
	if item.node == null:
		ItemVisuals.build(item)
	return item.node


## Acomoda la bolsa que cuelga de la boca del contenedor. No se escala: la bolsa
## colgada se dibuja EXPANDIDA como forro (ver `ItemVisuals._build_bin_liner`),
## así que al colgarla hay que volver a construirla.
func _update_bin_visual(tile: CellData) -> void:
	if tile.bag == null:
		return
	var bag := tile.bag
	if not bag.hung:
		bag.hung = true
		ItemVisuals.rebuild(bag)      # si todavía no existe el nodo, no hace nada
	var node := _item_node(bag)       # y acá se construye ya como forro
	item_blocker(bag, false)
	parent_item(node, world.items_root)
	# origen en el piso de la celda: la geometría del forro se arma en alturas
	# absolutas sobre la cara del contenedor
	node.position = Vector3(tile.x + 0.5, 0.0, tile.y + 0.5)
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE


## Al sacarla vuelve a ser la bolsa de mano (cono atado).
func _unhang(item: CarryItem) -> void:
	if item.is_bag() and item.hung:
		item.hung = false
		ItemVisuals.rebuild(item)


func move_item_to_player(item: CarryItem, p: Player) -> void:
	p.carrying = item
	_unhang(item)
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
			if held != null and held.is_bag() and held.contents.is_empty():
				return "La bolsa está vacía"
			if held != null and held.is_bag():
				return "[%s] Entregar (%d)" % [key, held.contents.size()]
			if held != null:
				return "La basura va al contenedor"
			return "Camión: entregá una bolsa llena"
		"bags":
			if held != null:
				return "Manos ocupadas"
			return "[%s] Tomar bolsa" % key
		"bin":
			var nombre: String = String(GameConfig.BIN_LABEL.get(tile.bin, "CONTENEDOR"))
			if held == null:
				if tile.bag != null:
					return "[%s] Sacar bolsa (%d/%d)" % [key, tile.bag.contents.size(), GameConfig.BAG_CAPACITY]
				return "Contenedor de %s · falta bolsa" % nombre
			if held.is_bag():
				return "Ya hay una bolsa" if tile.bag != null else "[%s] Colgar la bolsa" % key
			if not held.is_residue():
				return "Acá va basura"
			if held.type != tile.bin:
				return "Ese no va en %s" % nombre
			if tile.bag == null:
				return "Primero colgá una bolsa"
			if tile.bag.is_full():
				return "Bolsa llena: al camión"
			return "[%s] Tirar en %s" % [key, nombre]

	if held == null and tile.item != null:
		return "[%s] Recoger %s" % [key, tile.item.label()]
	if held != null and tile.item == null and tile.can_hold():
		return "[%s] Soltar" % key
	return ""
