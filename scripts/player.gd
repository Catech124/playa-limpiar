class_name Player
extends CharacterBody3D
## Movimiento + interacción. Un solo botón contextual, como Overcooked:
##   mover · ACCIÓN (recoger / colgar bolsa / tirar basura / entregar) · IMPULSO · LANZAR
##
## No hay trabajos sostenidos: cada acción es instantánea (el ritmo lo pone el
## ir y volver por la basura).

# carga diferida: si el .glb no está importado, el preload rompe el parseo de
# todo el proyecto (nos pasó al borrar el import viejo para forzar la reimportación)
static var _chef_scene: PackedScene


func _chef() -> PackedScene:
	if _chef_scene == null:
		_chef_scene = load("res://assets/chef.glb") as PackedScene
	return _chef_scene


## El modelo de primitivas ya está a la escala final (no se reescala).
const CHAR_SCALE := 1.0
## Brazos caídos por diseño: la animación se suma desde cero.
const ARM_REST_L := 0.0
const ARM_REST_R := 0.0

var index := 0
var color := Color.WHITE
var keymap: Dictionary = {}
var world: GridWorld
var game                     # main.gd (sin tipo: evita dependencia circular)
var facing := Vector2i(0, -1)   # eje dominante: se usa para interactuar
var yaw := PI                   # hacia dónde mira el cuerpo (diagonal incluida)
var carrying: CarryItem = null
var active := false

var dash_left := 0.0
var dash_cd := 0.0
var walk_phase := 0.0

var carry_anchor: Node3D
var swimming := false
var water_time := 0.0       # segundos seguidos en el agua (lo usa el tiburón)
var shark_heat := 0.0      # 0..1: cuanto más tiempo en el agua, más rápido vuelve
var down_time := 0.0       # mordido: segundos que tarda en reaparecer
var respawn_tile := Vector2i(-1, -1)
var fin: Node3D = null      # aleta que avisa la mordida
var wake: MeshInstance3D = null   # espuma alrededor del nadador
var ripples: Array = []           # ondas que se abren al nadar
var _swim_blend := 0.0
var _splash_cd := 0.0
var _act_pressed := false
var _throw_pressed := false
var _dash_pressed := false
var _body_mesh: Node3D
# bisagras del GLB (el generador las crea como nodos vacíos): permiten animar
# brazos/piernas/cabeza sin esqueleto ni animaciones importadas
var _hinges := {}


func setup(idx: int, km: Dictionary, grid: GridWorld, g) -> void:
	index = idx
	keymap = km
	world = grid
	game = g
	color = GameConfig.PLAYER_COLORS[idx % GameConfig.PLAYER_COLORS.size()]
	_build_body()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = GameConfig.PLAYER_RADIUS
	capsule.height = GameConfig.PLAYER_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0, GameConfig.PLAYER_HEIGHT * 0.5, 0)
	add_child(shape)

	_body_mesh = Node3D.new()
	add_child(_body_mesh)

	# personaje de primitivas (sin GLB): cuerpo trapecio, brazos cilíndricos con
	# guantes blancos, cabeza circular y sombrero de paja
	var model := CharModel.build(color, "straw")
	_body_mesh.add_child(model)
	for hinge in ["arm_l", "arm_r", "leg_l", "leg_r", "head", "hat"]:
		var node := model.find_child(hinge, true, false)
		if node is Node3D:
			_hinges[hinge] = node

	_add_shadow_disc()

	carry_anchor = Node3D.new()
	# EN LAS MANOS: con la pose de cargar (brazos a -1.15 rad) los guantes
	# quedan en (±0.09, 0.41, 0.27) en el espacio del cuerpo.
	carry_anchor.position = CharModel.HAND_CARRY
	_body_mesh.add_child(carry_anchor)              # gira con el personaje


## Sombra de contacto: un disco oscuro bajo los pies.
func _add_shadow_disc() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.28
	disc.bottom_radius = 0.28
	disc.height = 0.006
	disc.radial_segments = 20
	var rm := MeshInstance3D.new()
	rm.mesh = disc
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.05, 0.06, 0.08, 0.22)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.material_override = rmat
	rm.position = Vector3(0, 0.012, 0)
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rm)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var code := k.physical_keycode
	if code == keymap["action"]:
		_act_pressed = true
	elif code == keymap["throw"]:
		_throw_pressed = true
	elif code == keymap["dash"]:
		_dash_pressed = true


func _physics_process(delta: float) -> void:
	# mordido: no se mueve ni interactúa hasta reaparecer (lo lleva main)
	if down_time > 0.0:
		velocity = Vector3.ZERO
		_act_pressed = false
		_throw_pressed = false
		_dash_pressed = false
		return
	_update_swim(delta)
	_animate(delta)
	if not active:
		return

	dash_left = maxf(0.0, dash_left - delta)
	dash_cd = maxf(0.0, dash_cd - delta)

	# ---- dirección --------------------------------------------------------
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(keymap["left"]):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(keymap["right"]):
		dir.x += 1.0
	if Input.is_physical_key_pressed(keymap["up"]):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(keymap["down"]):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		face_towards(dir, delta)
		walk_phase += delta * 12.0

	# ---- impulso ----------------------------------------------------------
	if _dash_pressed and dash_cd <= 0.0 and dir != Vector2.ZERO:
		dash_left = GameConfig.DASH_TIME
		dash_cd = GameConfig.DASH_COOLDOWN
		# polvo en la arena, salpicadura en el agua: el impulso tiene que verse
		if game != null:
			if swimming:
				game.spawn_puff(position + Vector3(0, GameConfig.WATER_LEVEL, 0), Color(0.85, 0.95, 1.0), 8, 1.1)
			else:
				game.spawn_puff(position, Color(0.88, 0.82, 0.66), 8, 1.0)
	_dash_pressed = false

	move_step(dir)

	# ---- lanzar -----------------------------------------------------------
	if _throw_pressed:
		_throw_pressed = false
		if carrying != null:
			game.throw_item(self)
			return

	# ---- acción puntual ---------------------------------------------------
	if _act_pressed:
		_act_pressed = false
		var front := front_tile()
		if front != null:
			game.player_use(self, front)


func move_step(dir: Vector2) -> void:
	var speed := GameConfig.PLAYER_SPEED
	if swimming:
		speed = GameConfig.SWIM_DASH_SPEED if dash_left > 0.0 else GameConfig.SWIM_SPEED
	elif dash_left > 0.0:
		speed = GameConfig.DASH_SPEED
	if dir == Vector2.ZERO:
		velocity = Vector3.ZERO
	else:
		velocity = Vector3(dir.x, 0.0, dir.y) * speed
	move_and_slide()
	# El suelo es plano y el personaje no salta: se lo deja siempre a nivel del
	# piso y dentro del mapa. Sin esto, al empujar contra el agua el motor lo
	# "trepaba" (quedaba en y=0.55 y se podía salir del mapa).
	position.y = 0.0
	if world != null:
		position.x = clampf(position.x, 1.05, float(world.w) - 1.05)
		position.z = clampf(position.z, 1.05, float(world.h) - 1.05)


## Gira el cuerpo hacia donde va, con un suavizado corto. Para interactuar se
## guarda el eje dominante (`facing`), pero la animación mira a la diagonal: si
## no, al caminar en diagonal el personaje se iba de costado.
func face_towards(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	var d := dir.normalized()
	if absf(d.x) >= absf(d.y):
		facing = Vector2i(signi(int(sign(d.x))), 0)
	else:
		facing = Vector2i(0, signi(int(sign(d.y))))
	yaw = lerp_angle(yaw, atan2(d.x, d.y), minf(1.0, delta * 22.0))
	_body_mesh.rotation.y = yaw


## Mirar si está en el agua se hace con la celda, no con la altura: el jugador
## camina siempre a y=0 y el agua es una lámina.
func _update_swim(delta: float) -> void:
	var t: CellData = world.tile_at(tile_x(), tile_y()) if world != null else null
	swimming = t != null and t.kind == "water"
	_swim_blend = move_toward(_swim_blend, 1.0 if swimming else 0.0, delta * 6.0)
	if _swim_blend > 0.05:
		_ensure_wake()
	if wake != null:
		wake.visible = _swim_blend > 0.4
		var k := 0.9 + 0.12 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)
		wake.scale = Vector3(k, 1.0, k)

	# ondas que se abren desde el nadador: es lo que más se lee desde arriba
	for rp in ripples:
		rp["ph"] = fmod(float(rp["ph"]) + delta * 0.75, 1.0)
		var n: MeshInstance3D = rp["node"]
		var ph: float = rp["ph"]
		var s2 := 0.7 + 1.2 * ph
		n.scale = Vector3(s2, 1.0, s2)
		(n.material_override as StandardMaterial3D).albedo_color.a = (1.0 - ph) * 0.55
		n.visible = _swim_blend > 0.4

	# salpicaduras al avanzar: el movimiento en el agua tiene que verse
	_splash_cd = maxf(0.0, _splash_cd - delta)
	if swimming and velocity.length() > 0.2 and _splash_cd <= 0.0:
		_splash_cd = 0.30
		if game != null:
			game.spawn_puff(position + Vector3(0, GameConfig.WATER_LEVEL - 0.02, 0), Color(0.94, 0.99, 1.0), 3, 0.55)


## Espuma: sin esto el personaje parece flotar sobre una plancha azul.
func _ensure_wake() -> void:
	if wake != null:
		return
	wake = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.34
	t.outer_radius = 0.46
	t.rings = 18
	t.ring_segments = 5
	wake.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.99, 1.0, 0.55)
	wake.material_override = m
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake.position = Vector3(0, GameConfig.WATER_LEVEL + 0.015, 0.16)
	wake.visible = false
	add_child(wake)

	# dos anillos de onda desfasados
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.50
		torus.rings = 20
		torus.ring_segments = 5
		ring.mesh = torus
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(0.96, 1.0, 1.0, 0.5)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0, GameConfig.WATER_LEVEL + 0.014, 0.16)
		ring.visible = false
		add_child(ring)
		ripples.append({"node": ring, "ph": 0.5 * float(i)})


## El tiburón lo mordió: desaparece del agua y vuelve a la arena en `seconds`.
func keep_down(seconds: float, tile: Vector2i) -> void:
	down_time = seconds
	respawn_tile = tile if tile.x >= 0 else Vector2i(tile_x(), tile_y())
	_body_mesh.visible = false
	velocity = Vector3.ZERO
	if wake != null:
		wake.visible = false


func revive() -> void:
	down_time = 0.0
	if respawn_tile.x >= 0:
		teleport(respawn_tile.x, respawn_tile.y, Vector2i(0, -1))
	respawn_tile = Vector2i(-1, -1)
	_body_mesh.visible = true


func front_tile() -> CellData:
	var fx := position.x + facing.x * 0.62
	var fz := position.z + facing.y * 0.62
	return world.tile_at(int(floor(fx)), int(floor(fz)))


func tile_x() -> int:
	return int(floor(position.x))


func tile_y() -> int:
	return int(floor(position.z))


func teleport(tx: int, ty: int, face := Vector2i(0, -1)) -> void:
	position = Vector3(tx + 0.5, 0.0, ty + 0.5)
	facing = face
	yaw = _facing_angle()
	_body_mesh.rotation.y = yaw


## Animación procedural sobre las bisagras del GLB.
##   idle   → respiración
##   mover  → ciclo de caminata
##   llevar → brazos adelante
##   pique  → cuerpo inclinado y brazos atrás
##   nadar  → acostado, brazada alternada y rolido
func _animate(delta: float) -> void:
	if _hinges.is_empty():
		return
	var moving := velocity.length() > 0.05
	var t := walk_phase
	var carry := carrying != null
	var swim := _swim_blend
	var dash := clampf(dash_left / maxf(0.01, GameConfig.DASH_TIME), 0.0, 1.0)
	var arm_l: Node3D = _hinges.get("arm_l")
	var arm_r: Node3D = _hinges.get("arm_r")
	var leg_l: Node3D = _hinges.get("leg_l")
	var leg_r: Node3D = _hinges.get("leg_r")
	var head: Node3D = _hinges.get("head")
	var breath := sin(Time.get_ticks_msec() / 1000.0 * 2.2)
	var now := Time.get_ticks_msec() / 1000.0

	if swim > 0.35:
		# Flotando parado: los brazos reman a los costados, a la altura del agua,
		# alternados. (Acostado "de nadador profesional" se hundía la cara.)
		var stroke := sin(now * 5.5)
		if arm_l: arm_l.rotation = Vector3(-0.45 + stroke * 0.55, 0.0, ARM_REST_L + 0.55 + stroke * 0.22)
		if arm_r: arm_r.rotation = Vector3(-0.45 - stroke * 0.55, 0.0, ARM_REST_R - 0.55 - stroke * 0.22)
	elif dash > 0.05 and not carry:
		# pique: brazos atrás y cuerpo estirado, como saliendo disparado
		if arm_l: arm_l.rotation = Vector3(1.15 * dash, 0.0, ARM_REST_L + 0.35)
		if arm_r: arm_r.rotation = Vector3(1.15 * dash, 0.0, ARM_REST_R - 0.35)
	elif carry:
		# brazos adelante y un poco abiertos, como sosteniendo la caja
		if arm_l: arm_l.rotation = Vector3(-1.15, 0.0, ARM_REST_L + 0.35)
		if arm_r: arm_r.rotation = Vector3(-1.15, 0.0, ARM_REST_R - 0.35)
	else:
		var swing := sin(t) * 0.55 if moving else 0.0
		if arm_l: arm_l.rotation = Vector3(swing, 0.0, ARM_REST_L - 0.06 + breath * 0.02)
		if arm_r: arm_r.rotation = Vector3(-swing, 0.0, ARM_REST_R + 0.06 - breath * 0.02)

	if swim > 0.35:
		var kick := sin(now * 9.0) * (0.45 if moving else 0.15)
		if leg_l: leg_l.rotation = Vector3(kick, 0.0, 0.0)
		if leg_r: leg_r.rotation = Vector3(-kick, 0.0, 0.0)
	elif moving:
		var stride := 0.62 + 0.40 * dash
		if leg_l: leg_l.rotation = Vector3(-sin(t) * stride, 0.0, 0.0)
		if leg_r: leg_r.rotation = Vector3(sin(t) * stride, 0.0, 0.0)
	else:
		if leg_l: leg_l.rotation = Vector3.ZERO
		if leg_r: leg_r.rotation = Vector3.ZERO

	if head:
		head.rotation = Vector3(
			-0.04 + (0.02 * sin(t * 2.0) if moving else breath * 0.015) - 0.12 * swim,
			0.0,
			(0.03 * sin(t) if moving else breath * 0.02))

	# postura del cuerpo: erguido en el agua (flotando parado), inclinado al picar
	_body_mesh.rotation.x = -0.10 * swim - 0.30 * dash * (1.0 - swim)
	_body_mesh.rotation.z = sin(now * 5.5) * 0.06 * swim
	_body_mesh.position.z = 0.0
	# se hunde apenas: el agua le llega al pecho y la cabeza queda afuera
	var target_y := -0.10 * swim
	if swim > 0.35:
		target_y += sin(now * 4.0) * 0.018       # flota como un corcho
	elif moving:
		target_y += absf(sin(t)) * 0.025
	_body_mesh.position.y = lerpf(_body_mesh.position.y, target_y, minf(1.0, delta * 12.0))


func _facing_angle() -> float:
	# el modelo mira a +Z (en Blender la cara está en -Y y glTF pasa -Y a +Z):
	# yaw 0 = +Z, +PI/2 = +X. Antes estaba invertido y se caminaba de espaldas.
	if facing.x > 0:
		return PI * 0.5
	if facing.x < 0:
		return -PI * 0.5
	if facing.y > 0:
		return 0.0
	return PI
