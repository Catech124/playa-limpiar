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
var npcs: Npcs
var crabs: Crabs
var spawner: TrashSpawner
var hud: Hud
var camera: Camera3D
var sun: DirectionalLight3D
var cam_free := false       # true = la cámara no sigue a los jugadores (capturas)
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
var puffs: Array = []            # polvo / salpicaduras
var sharks: Array = []           # tiburones de la mordida (animación)
var _sync_cd := 0.0
var _item_t := 0.0
var clock := 0.0                 # segundos de la jornada (para el tope de castigos)
var penalty_log: Array = []      # instantes de los castigos que descontaron
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
	if crabs != null:
		crabs.clear()
		crabs = null
	if npcs != null:
		for n in npcs.list:
			if n.node != null and is_instance_valid(n.node):
				n.node.queue_free()
		npcs.list.clear()
		npcs = null
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
	npcs = Npcs.new(self, world)
	npcs.spawn_all(int(level.get("npcs", 1)))
	crabs = Crabs.new(self, world)

	toasts.clear()
	flying.clear()
	for pf in puffs:
		if is_instance_valid(pf["node"]):
			pf["node"].queue_free()
	puffs.clear()
	for sh in sharks:
		if is_instance_valid(sh["node"]):
			sh["node"].queue_free()
	sharks.clear()
	clock = 0.0
	penalty_log.clear()
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
	if cam_free or players.is_empty():
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


## Los cangrejos tienen collider y usan move_and_slide: eso va en el frame de
## física, no en el de dibujo (en `_process` se traban y tiemblan).
func _physics_process(delta: float) -> void:
	if state != State.PLAYING or crabs == null:
		return
	crabs.tick(delta)


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return

	_update_camera(delta)

	clock += delta
	time_left = maxf(0.0, time_left - delta)
	_tick_decay(delta)
	_tick_water(delta)

	spawner.tick(delta)
	npcs.tick(delta)
	if not sandbox:
		gulls.tick(delta)

	_update_flying(delta)
	_update_toasts(delta)
	_update_puffs(delta)
	_animate_items(delta)
	_tick_bin_lids(delta)
	_update_sharks(delta)
	_update_light()

	# la basura rueda: la celda lógica tiene que seguir al cuerpo
	_sync_cd -= delta
	if _sync_cd <= 0.0:
		_sync_cd = 0.12
		_sync_item_tiles()

	if not sandbox:
		if quota_met():
			_finish(true)
		elif time_left <= 0.0:
			_finish(false)


## Tiburón (Fase 3): a los 3 s aparece la aleta y a los 6 s muerde. El reloj
## corre por jugador: nadie puede quedarse tranquilo en el agua.
func _tick_water(delta: float) -> void:
	for p in players:
		# mordido: cuenta atrás para reaparecer
		if p.down_time > 0.0:
			p.down_time = maxf(0.0, float(p.down_time) - delta)
			if p.down_time <= 0.0:
				_respawn(p)
			continue

		# el tiburón también acecha si estás en la orilla, no solo nadando
		if p.swimming or _near_water(p):
			p.water_time += delta
			# Cuanto más se queda en el agua, más se calienta el tiburón: la
			# aleta sale antes y la mordida también.
			p.shark_heat = minf(1.0, float(p.shark_heat) + delta * 0.035)
			var fin_t: float = GameConfig.SHARK_FIN_TIME * (1.0 - 0.5 * float(p.shark_heat))
			if p.fin == null and p.water_time >= fin_t:
				p.fin = _make_fin()
				world.items_root.add_child(p.fin)
				# Sale de mar ADENTRO (más allá de la orilla), no aparece al lado:
				# se lo ve venir desde afuera y acercarse derecho al jugador.
				p.fin.position = _fin_spawn(p)
				toast(p.position + Vector3(0, 1.4, 0), "¡Aleta!", "bad")
			if p.fin != null:
				# ya no orbita: viene desde afuera del mar y se acerca derecho
				var to: Vector3 = p.position - p.fin.position
				to.y = 0.0
				var d: float = to.length()
				var speed: float = 2.2 + 0.9 * float(p.shark_heat)
				if d > 0.001:
					var next: Vector3 = p.fin.position + (to / d) * minf(speed * delta, d)
					next.y = GameConfig.WATER_LEVEL - 0.02
					# no sale del agua: si el jugador se quedó en la arena, la
					# aleta espera en la orilla en vez de reptar por la playa
					if _is_water_at(next):
						p.fin.position = next
				p.fin.position.y = GameConfig.WATER_LEVEL - 0.02
				p.fin.rotation.y = atan2(to.x, to.z)
				# muerde SOLO si llega: no hay mordida por reloj (antes te comía
				# desde el otro lado del agua porque se cumplía el tiempo)
				if d < 0.55:
					_bite(p)
		else:
			p.water_time = 0.0
			p.shark_heat = maxf(0.0, float(p.shark_heat) - delta * 0.02)
			_clear_fin(p)


## ¿Hay agua en ese punto? La aleta solo puede estar en el mar: si aparece en
## la arena (cuando el jugador está en la orilla) es un bug visible.
func _is_water_at(pos: Vector3) -> bool:
	if world == null:
		return false
	var t: CellData = world.tile_at(int(floor(pos.x)), int(floor(pos.z)))
	return t != null and t.kind == "water"


## Desde dónde sale la aleta: en el AGUA, a ~6.5 unidades del jugador y
## prefiriendo mar adentro (así se la ve venir de afuera). Si el jugador está
## pegado a la orilla no hay agua a 6.5, así que se prueba cada vez más cerca
## y, como último recurso, se busca la celda de agua más cercana.
func _fin_spawn(p: Player) -> Vector3:
	var deepest := Vector3.INF
	var deepest_d := INF
	var r := 8
	var pz := int(floor(p.position.z))
	var px := int(floor(p.position.x))
	for ty in range(pz - r, pz + r + 1):
		for tx in range(px - r, px + r + 1):
			var t: CellData = world.tile_at(tx, ty)
			if t == null or t.kind != "water":
				continue
			var c := Vector3(tx + 0.5, GameConfig.WATER_LEVEL - 0.02, ty + 0.5)
			var d := Vector2(c.x - p.position.x, c.z - p.position.z).length()
			if d < 1.6:
				continue                     # no al lado: tiene que venir de lejos
			# 6.5 de distancia, y premio chico por salir de mar adentro
			var score := absf(d - 6.5) - 0.35 * maxf(0.0, c.z - p.position.z)
			if score < deepest_d:
				deepest_d = score
				deepest = c
	if deepest != Vector3.INF:
		return deepest
	# plan B: cualquier agua del mapa
	for row in world.tiles:
		for t in row:
			if t != null and t.kind == "water":
				return Vector3(t.x + 0.5, GameConfig.WATER_LEVEL - 0.02, t.y + 0.5)
	return Vector3(p.position.x, GameConfig.WATER_LEVEL - 0.02, p.position.z + 2.0)


func _make_fin() -> Node3D:
	var root := Node3D.new()
	# aleta plana triangular (prisma): se lee de costado a la cámara alta
	var m := PrismMesh.new()
	m.size = Vector3(0.42, 0.58, 0.08)
	m.left_to_right = 0.45
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = ItemVisuals.material(Color(0.26, 0.30, 0.34))
	mi.position = Vector3(0, 0.26, 0)
	mi.rotation_degrees = Vector3(0, 0, -6)
	root.add_child(mi)

	var foam := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.30
	t.outer_radius = 0.38
	t.rings = 16
	t.ring_segments = 5
	foam.mesh = t
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.94, 0.99, 1.0, 0.8)
	foam.material_override = mat
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam.position = Vector3(0, 0.02, 0)
	root.add_child(foam)
	return root


func _clear_fin(p: Player) -> void:
	if p.fin != null and is_instance_valid(p.fin):
		p.fin.queue_free()
	p.fin = null


## Mordida: −3, suelta lo que llevaba y vuelve a la arena. La basura que soltó
## queda en la orilla (no se pierde en el fondo: ya sería castigo doble).
## La mordida no quita puntos: te saca del agua y tardás 5 s en volver.
func _bite(p: Player) -> void:
	spawn_puff(p.position + Vector3(0, GameConfig.WATER_LEVEL, 0), Color(0.97, 1.0, 1.0), 14, 1.8)
	toast(p.position + Vector3(0, 1.5, 0), "¡Mordida! Volvés en %d s" % int(GameConfig.SHARK_RESPAWN_TIME), "bad")
	_show_shark(p)
	var dest := _nearest_sand(p)
	if p.carrying != null:
		var item := p.carrying
		p.carrying = null
		if dest != null:
			move_item_to_tile(item, dest)
		else:
			destroy_item(item)
	# reaparece en el spawn del nivel, no donde lo mordieron
	var sp: Vector2i = world.spawns[p.index % world.spawns.size()]
	p.keep_down(GameConfig.SHARK_RESPAWN_TIME, sp)
	p.water_time = 0.0
	p.shark_heat = minf(1.0, float(p.shark_heat) + 0.25)
	_clear_fin(p)


## Tiburón de la mordida: sale del agua, se abalanza y se vuelve a hundir.
## Es rápido y de primitivas, como el resto del juego.
func _show_shark(p: Player) -> void:
	var shark := _make_shark()
	world.add_child(shark)
	var base := p.position
	shark.position = base + Vector3(0.0, -1.1, 0.9)
	shark.rotation.y = PI        # mira al jugador (viene desde el sur)
	sharks.append({"node": shark, "base": base, "t": 0.0})


func _update_sharks(delta: float) -> void:
	for sh in sharks.duplicate():
		sh["t"] = float(sh["t"]) + delta
		var t: float = sh["t"]
		var node: Node3D = sh["node"]
		if not is_instance_valid(node):
			sharks.erase(sh)
			continue
		var base: Vector3 = sh["base"]
		if t < 0.22:
			# sube desde el fondo
			var k := t / 0.22
			node.position = base + Vector3(0, lerpf(-1.1, 0.34, k), 0.9)
			node.rotation.x = 0.35 * (1.0 - k)
		elif t < 0.44:
			# se abalanza con la boca abierta
			var k := (t - 0.22) / 0.22
			node.position = base + Vector3(0, 0.34 + sin(k * PI) * 0.10, lerpf(0.9, 0.18, k))
			node.rotation.x = -0.28 * sin(k * PI)
			node.scale = Vector3.ONE * (1.0 + 0.10 * sin(k * PI))
		else:
			# se hunde
			var k := (t - 0.44) / 0.70
			node.position = base + Vector3(0, lerpf(0.34, -1.4, k), lerpf(0.18, 0.5, k))
			node.rotation.x = 0.55 * k
			node.scale = Vector3.ONE
		if t > 1.2:
			node.queue_free()
			sharks.erase(sh)


func _make_shark() -> Node3D:
	var root := Node3D.new()
	var gray := Color(0.36, 0.42, 0.49)
	var belly := Color(0.90, 0.92, 0.92)

	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 14
	body.rings = 8
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = ItemVisuals.material(gray)
	bm.scale = Vector3(0.62, 0.44, 1.05)
	root.add_child(bm)

	var bely := SphereMesh.new()
	bely.radius = 0.5
	bely.height = 1.0
	bely.radial_segments = 12
	bely.rings = 6
	var blm := MeshInstance3D.new()
	blm.mesh = bely
	blm.material_override = ItemVisuals.material(belly)
	blm.scale = Vector3(0.52, 0.28, 0.95)
	blm.position = Vector3(0, -0.08, 0.03)
	root.add_child(blm)

	# hocico
	var snout := CylinderMesh.new()
	snout.top_radius = 0.03
	snout.bottom_radius = 0.30
	snout.height = 0.46
	snout.radial_segments = 12
	var sm := MeshInstance3D.new()
	sm.mesh = snout
	sm.material_override = ItemVisuals.material(gray)
	sm.position = Vector3(0, 0.0, 0.60)
	sm.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(sm)

	# aleta dorsal
	var dorsal := PrismMesh.new()
	dorsal.size = Vector3(0.30, 0.44, 0.07)
	var dm := MeshInstance3D.new()
	dm.mesh = dorsal
	dm.material_override = ItemVisuals.material(gray.darkened(0.12))
	dm.position = Vector3(0, 0.26, -0.04)
	root.add_child(dm)

	# cola
	var tail := PrismMesh.new()
	tail.size = Vector3(0.44, 0.54, 0.07)
	var tm := MeshInstance3D.new()
	tm.mesh = tail
	tm.material_override = ItemVisuals.material(gray.darkened(0.12))
	tm.position = Vector3(0, 0.12, -0.98)
	tm.rotation_degrees = Vector3(0, 0, 22)
	root.add_child(tm)

	# pectorales
	for side in [-1.0, 1.0]:
		var fin := PrismMesh.new()
		fin.size = Vector3(0.34, 0.22, 0.05)
		var fm := MeshInstance3D.new()
		fm.mesh = fin
		fm.material_override = ItemVisuals.material(gray.darkened(0.05))
		fm.position = Vector3(side * 0.30, -0.05, 0.20)
		fm.rotation_degrees = Vector3(0, side * 38.0, side * -58.0)
		root.add_child(fm)

	# ojos
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.038
		eye.height = 0.076
		var em := MeshInstance3D.new()
		em.mesh = eye
		em.material_override = ItemVisuals.material(Color(0.06, 0.06, 0.08))
		em.position = Vector3(side * 0.19, 0.10, 0.46)
		root.add_child(em)

	# boca y dientes
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.36, 0.06, 0.18)
	var mm := MeshInstance3D.new()
	mm.mesh = mouth
	mm.material_override = ItemVisuals.material(Color(0.42, 0.09, 0.11))
	mm.position = Vector3(0, -0.11, 0.56)
	root.add_child(mm)
	for i in 5:
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.045, 0.055, 0.03)
		var tmi := MeshInstance3D.new()
		tmi.mesh = tooth
		tmi.material_override = ItemVisuals.material(Color(0.99, 0.98, 0.95))
		tmi.position = Vector3(-0.12 + 0.06 * float(i), -0.066, 0.62)
		root.add_child(tmi)

	return root


func _respawn(p: Player) -> void:
	spawn_puff(p.position + Vector3(0, 0.1, 0), Color(0.85, 0.92, 1.0), 8, 1.2)
	p.revive()
	spawn_puff(p.position, Color(0.88, 0.82, 0.66), 8, 1.0)


## ¿Está a un paso del agua? En la orilla el tiburón ya empieza a contar.
func _near_water(p: Player) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := world.tile_at(p.tile_x() + d.x, p.tile_y() + d.y)
		if t != null and t.kind == "water":
			return true
	return false


func _nearest_sand(p: Player) -> CellData:
	var best: CellData = null
	var best_d := 999.0
	for row in world.tiles:
		for t in row:
			if t.kind != "floor" or t.decor != "":
				continue
			var d := Vector2(float(t.x - p.tile_x()), float(t.y - p.tile_y())).length()
			if d < best_d:
				best_d = d
				best = t
	return best


## Presión de la Fase 2: la basura del agua se hunde y el vidrio de la arena se
## rompe. El aro de cuenta atrás avisa cuánto queda (se cierra y se pone rojo).
func _tick_decay(delta: float) -> void:
	var expired: Array = []
	for row in world.tiles:
		for t in row:
			var it: CarryItem = t.item
			if it == null or not it.is_residue():
				continue
			var limit := 0.0
			if it.origin == "water":
				limit = GameConfig.SEA_SINK_TIME
			elif it.type == "vidrio":
				limit = GameConfig.GLASS_BREAK_TIME
			if limit <= 0.0:
				continue
			it.life += delta
			_update_ring(it, t, limit)
			if it.life >= limit:
				expired.append([t, it])
	for e in expired:
		var tile: CellData = e[0]
		var it: CarryItem = e[1]
		var at := tile.center() + Vector3(0, 0.5, 0)
		tile.item = null
		destroy_item(it)
		if it.origin == "water":
			penalty("Se hundió", at)
		else:
			penalty("Vidrio roto", at)


func _make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.20
	torus.outer_radius = 0.26
	torus.rings = 20
	torus.ring_segments = 6
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.72, 0.25, 0.85)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## El aro va en el piso (no cuelga del ítem): si la botella rueda, el aviso
## sigue legible desde la cámara alta.
func _update_ring(it: CarryItem, tile: CellData, limit: float) -> void:
	if it.ring == null or not is_instance_valid(it.ring):
		it.ring = _make_ring()
		world.items_root.add_child(it.ring)
	var left := clampf(1.0 - it.life / limit, 0.0, 1.0)
	# el aro sigue al cuerpo (la basura rueda), no a la celda donde cayó
	var at := Vector3(tile.x + 0.5, 0.035, tile.y + 0.5)
	if it.node != null:
		at.x = it.node.global_position.x
		at.z = it.node.global_position.z
	it.ring.position = at
	var k := 0.35 + 0.65 * left
	it.ring.scale = Vector3(k, 1.0, k)
	var mat := (it.ring as MeshInstance3D).material_override as StandardMaterial3D
	mat.albedo_color = Color(1.0, 0.72, 0.25, 0.85).lerp(Color(1.0, 0.22, 0.18, 0.95), 1.0 - left)


func _clear_ring(item: CarryItem) -> void:
	if item.ring != null and is_instance_valid(item.ring):
		item.ring.queue_free()
	item.ring = null


## La basura es física: si rueda dos celdas, la celda donde estaba quedaría
## apuntando a una botella que ya no está (y no se podría levantar del piso
## nuevo). Se reasigna la celda siguiendo la posición real del cuerpo.
func _sync_item_tiles() -> void:
	var moving: Array = []
	for row in world.tiles:
		for t in row:
			if t.item == null or not t.item.is_residue() or t.item.node == null:
				continue
			var gx := int(floor(t.item.node.global_position.x))
			var gy := int(floor(t.item.node.global_position.z))
			if gx != t.x or gy != t.y:
				moving.append([t, t.item, gx, gy])
	for m in moving:
		var from: CellData = m[0]
		var it: CarryItem = m[1]
		var dest := world.tile_at(int(m[2]), int(m[3]))
		if dest == null or (not dest.can_hold() and dest.kind != "water"):
			continue
		if dest.item != null:
			continue          # ocupada: se resuelve cuando el otro se mueva
		from.item = null
		dest.item = it


## Polvo del impulso (y salpicadura cuando es en el agua): unas bolitas que se
## abren y se apagan. Barato y da la sensación de velocidad.
func spawn_puff(pos: Vector3, color: Color, count := 7, spread := 0.9) -> void:
	for i in count:
		var a := TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var mi := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.10
		m.height = 0.10
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = pos + Vector3(randf_range(-0.1, 0.1), 0.07, randf_range(-0.1, 0.1))
		world.items_root.add_child(mi)
		puffs.append({
			"node": mi,
			"mat": mat,
			"vel": Vector3(cos(a), 0.0, sin(a)) * randf_range(0.4, 1.0) * spread,
			"life": 0.0,
			"ttl": randf_range(0.32, 0.50),
		})


## La tapa del bote se abre cuando le cuelgan una bolsa y se cierra al sacarla.
## Es un detalle chico pero es lo que hace que el bote se lea "de verdad".
func _tick_bin_lids(delta: float) -> void:
	if world == null:
		return
	for entry in world.bin_lids:
		var lid: Node3D = entry["lid"]
		if lid == null or not is_instance_valid(lid):
			continue
		var tile: CellData = entry["tile"]
		var target := deg_to_rad(104.0) if tile.bag != null else 0.0
		lid.rotation.x = move_toward(lid.rotation.x, target, delta * 3.0)


## La basura flota apenas sobre la arena: así se ve desde la cámara alta y no
## queda media enterrada. En la mano o volando no flota.
func _animate_items(delta: float) -> void:
	_item_t += delta
	for node in world.items_root.get_children():
		var piece := node.get_node_or_null("Piece")
		if piece == null:
			continue
		var body := node as RigidBody3D
		if body != null and not body.freeze:
			piece.position.y = 0.02 + sin(_item_t * 2.4 + float(node.get_instance_id() % 100) * 0.3) * 0.014
		else:
			piece.position.y = 0.0


func _update_puffs(delta: float) -> void:
	for pf in puffs.duplicate():
		pf["life"] += delta
		var node: MeshInstance3D = pf["node"]
		if not is_instance_valid(node):
			puffs.erase(pf)
			continue
		var vel: Vector3 = pf["vel"]
		node.position += vel * delta
		pf["vel"] = vel * 0.88
		var k: float = 1.0 - float(pf["life"]) / float(pf["ttl"])
		# el radio base es 0.09: la escala va de ~0.7 a 2.4 durante la vida
		var s: float = 0.9 + 1.9 * (1.0 - k)
		node.scale = Vector3(s, s, s)
		(pf["mat"] as StandardMaterial3D).albedo_color.a = 0.8 * k
		if float(pf["life"]) >= float(pf["ttl"]):
			node.queue_free()
			puffs.erase(pf)


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


## Castigo con motivo visible. Tope: los primeros 3 del último minuto
## descuentan; el resto solo avisan (si no, distraerse 20 s hunde la partida
## sin que se pueda remontar).
func penalty(reason: String, pos: Vector3, amount := GameConfig.PENALTY) -> void:
	stats["penalties"] = int(stats.get("penalties", 0)) + 1
	while not penalty_log.is_empty() and clock - float(penalty_log[0]) > GameConfig.PENALTY_WINDOW:
		penalty_log.pop_front()
	if penalty_log.size() >= GameConfig.PENALTY_CAP:
		toast(pos, "%s · tope, no descuenta" % reason, "info")
		return
	penalty_log.append(clock)
	score = maxi(0, score - amount)
	toast(pos, "%s −%d" % [reason, amount], "bad")


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

	# 4. manos vacías: recoger del piso (basta con tenerlo cerca)
	if held == null:
		var near := nearest_item_tile(p)
		if near != null:
			var it: CarryItem = near.item
			near.item = null
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
			# no es un castigo: el contenedor simplemente no lo acepta
			toast(at, "Ese no va en %s" % bin_name, "bad")
			return
		if tile.bag == null:
			toast(at, "Falta la bolsa en %s" % bin_name, "bad")
			return
		if not tile.bag.has_room():
			toast(at, "La bolsa está llena: llevala al camión", "bad")
			return
		tile.bag.contents.append(held.type)
		if held.origin == "water":
			tile.bag.water.append(held.type)     # del mar: suma doble a la cuota
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
		if tile.bin_hole != null:
			tile.bin_hole.visible = true
		move_item_to_player(bag, p)
		if bag.is_full():
			toast(at, "¡Bolsa llena! Llevala al camión", "good")
		else:
			toast(at, "Bolsa fuera (%d/%d)" % [bag.contents.size(), GameConfig.BAG_CAPACITY], "info")
	else:
		toast(at, "Sin bolsa: tomá una en el dispensador", "bad")


## Agarrar no exige mirar: alcanza con tener el objeto cerca (radio de algo más
## de una celda). Se prefiere lo que está adelante, pero también se levanta lo
## de los costados y lo de atrás, que es lo que uno espera al pasar por encima.
func nearest_item_tile(p: Player) -> CellData:
	var best: CellData = null
	var best_score := 99.0
	var forward := Vector3(float(p.facing.x), 0.0, float(p.facing.y))
	var me := Vector3(p.position.x, 0.0, p.position.z)
	for y in range(p.tile_y() - 1, p.tile_y() + 2):
		for x in range(p.tile_x() - 1, p.tile_x() + 2):
			var t := world.tile_at(x, y)
			if t == null or t.item == null:
				continue
			var to := Vector3(t.x + 0.5, 0.0, t.y + 0.5) - me
			var d := to.length()
			if d > 1.45:
				continue
			# adelante gana: a igual distancia se levanta lo que se está mirando
			var score := d - 0.30 * forward.dot(to.normalized())
			if score < best_score:
				best_score = score
				best = t
	return best


## Un NPC tira basura: vuela con la misma parábola que el lanzamiento del
## jugador y aterriza en una celda libre del arenal.
func npc_throw(from: Vector3, tile: CellData, in_water := false) -> void:
	if tile == null:
		return
	var item := CarryItem.residue(spawner.pick_type(), "water" if in_water else "beach")
	ItemVisuals.build(item)
	item.node.position = from
	world.items_root.add_child(item.node)
	_hold(item)
	flying.append({"item": item, "from": from, "to": world.item_position(tile),
		"tile": tile, "t": 0.0, "player": null})


## Entregar en el camión: cada residuo suma a su barra de cuota.
func deliver(p: Player, bag: CarryItem) -> void:
	if bag.contents.is_empty():
		toast(p.position + Vector3(0, 1.7, 0), "La bolsa está vacía", "bad")
		return

	var n := bag.contents.size()
	for t in bag.contents:
		delivered[t] = int(delivered.get(t, 0)) + 1
	# la basura que salió del mar suma doble a la cuota: es el premio por nadar
	for t in bag.water:
		delivered[t] = int(delivered.get(t, 0)) + 1
	stats["delivered"] = int(stats["delivered"]) + n
	score += n * GameConfig.POINTS_PER_ITEM + bag.water.size() * GameConfig.POINTS_PER_ITEM

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
	if residue.origin == "water":
		bag.water.append(residue.type)
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
	_hold(item)
	item.node.scale = Vector3.ONE      # vuelve a su tamaño de basura en el piso
	parent_item(item.node, world.items_root)

	var from := p.position + Vector3(0, 1.3, 0)
	var to := world.item_position(landing)
	flying.append({"item": item, "from": from, "to": to, "tile": landing, "t": 0.0, "player": p})


func _land(f: Dictionary) -> void:
	var item: CarryItem = f["item"]
	var tile: CellData = f["tile"]

	# al agua se cae directo: es lo que hacen los NPCs al tirar basura
	if tile != null and tile.kind == "water":
		move_item_to_tile(item, tile)
		return
	if tile != null and try_place(tile, item):
		return

	var floors: Array = []
	if tile != null:
		floors = world.free_floors_near(tile.x, tile.y, 4)
	if not floors.is_empty():
		move_item_to_tile(item, floors[0])
	elif f["player"] != null and f["player"].carrying == null:
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


## Un residuo en la mano (o en el pico de una gaviota) no tiene física: se
## congela y se saca de toda colisión. Si no, empuja al jugador y se cae solo.
func _hold(item: CarryItem) -> void:
	_clear_ring(item)          # si sale del piso, el aro ya no corresponde
	var body := item.node as RigidBody3D
	if body == null:
		return
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


## Vuelve a la playa: dinámico y con colisión (para poder patearlo).
func _drop(item: CarryItem) -> void:
	var body := item.node as RigidBody3D
	if body == null:
		return
	body.collision_layer = GameConfig.ITEM_LAYER
	body.collision_mask = 1 | GameConfig.ITEM_LAYER | GameConfig.WATER_LAYER
	body.freeze = false


func move_item_to_tile(item: CarryItem, tile: CellData) -> void:
	tile.item = item
	_unhang(item)
	if item.node == null:
		return
	item_blocker(item, item.is_bag())
	parent_item(item.node, world.items_root)
	var pos := world.item_position(tile)
	if item.node is RigidBody3D:
		var body := item.node as RigidBody3D
		body.freeze = true
		body.position = Vector3(pos.x, pos.y, pos.z)
		body.rotation = Vector3(0.0, randf() * TAU, 0.0)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.scale = Vector3.ONE
		_drop(item)
	else:
		item.node.position = pos
		item.node.rotation = Vector3.ZERO
		item.node.scale = Vector3.ONE


## La basura no aparece plantada: cae desde un poco más arriba, inclinada, y la
## física la acuesta. Es la animación de aparición del bucle.
func drop_from_above(item: CarryItem) -> void:
	var body := item.node as RigidBody3D
	if body == null:
		return
	body.freeze = true
	body.position += Vector3(0.0, GameConfig.ITEM_DROP_HEIGHT, 0.0)
	body.rotation = Vector3(randf_range(-1.1, 1.1), randf() * TAU, randf_range(-1.1, 1.1))
	body.linear_velocity = Vector3(0.0, -0.6, 0.0)
	body.angular_velocity = Vector3(randf_range(-5.0, 5.0), randf_range(-2.0, 2.0),
		randf_range(-5.0, 5.0))
	_drop(item)


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
	# la bolsa tapa la boca oscura del contenedor (si no, se ve un plato negro)
	if tile.bin_hole != null:
		tile.bin_hole.visible = false
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
	_clear_ring(item)
	if item.node == null:
		return
	_hold(item)
	item_blocker(item, false)
	parent_item(item.node, p.carry_anchor)
	# el ítem se centra en las manos (su origen es la base) y se achica: así las
	# dos manos quedan ADELANTE de la silueta y se ve que lo sujetan
	var k := ItemVisuals.carry_scale(item)
	item.node.position = Vector3(0.0, -ItemVisuals.hold_offset(item) * k, -0.03)
	item.node.rotation = Vector3.ZERO
	item.node.scale = Vector3(k, k, k)


func destroy_item(item: CarryItem) -> void:
	if item == null:
		return
	_clear_ring(item)
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

	if held == null:
		var near := nearest_item_tile(p)
		if near != null:
			return "[%s] Recoger %s" % [key, near.item.label()]
	if held != null and tile.item == null and tile.can_hold():
		return "[%s] Soltar" % key
	return ""
