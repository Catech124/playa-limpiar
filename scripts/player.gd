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


var index := 0
var color := Color.WHITE
var keymap: Dictionary = {}
var world: GridWorld
var game                     # main.gd (sin tipo: evita dependencia circular)
var facing := Vector2i(0, -1)
var carrying: CarryItem = null
var active := false

var dash_left := 0.0
var dash_cd := 0.0
var walk_phase := 0.0

var carry_anchor: Node3D
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

	# personaje low-poly (asset generado con tools/make_chef.py)
	var model := _chef().instantiate()
	_body_mesh.add_child(model)
	_tint_shirt(model)
	_add_outline(model)
	_unshadow_hat(model)
	for hinge in ["arm_l", "arm_r", "leg_l", "leg_r", "head", "hat"]:
		var node := model.find_child(hinge, true, false)
		if node is Node3D:
			_hinges[hinge] = node


## El ala del sombrero proyecta sombra sobre la cara y la deja ilegible a 45 px:
## el gorro no proyecta sombra. (La referencia tiene la cara iluminada.)
func _unshadow_hat(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat and String(mat.resource_name) == "hat":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break


## Contorno por casco invertido: es la firma del look low-poly de referencia.
## Se prueba si el renderer lo soporta; si no, no se nota y no rompe nada.
func _add_outline(root: Node) -> void:
	var outline := StandardMaterial3D.new()
	outline.albedo_color = Color(0.05, 0.05, 0.06)
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.012
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i)
			if mat == null:
				mat = mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.next_pass = outline
				mi.set_surface_override_material(i, dup)

	# Sombra de contacto: antes había un aro con emisión que, con la cámara
	# nueva, se leía como una argolla invertida debajo del personaje.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.30
	disc.bottom_radius = 0.30
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

	carry_anchor = Node3D.new()
	# EN LAS MANOS: con la pose de cargar (brazos a -1.15 rad) los guantes
	# quedan en (±0.09, 0.39, 0.28) en el espacio del cuerpo, así que el punto
	# medio es donde el personaje sostiene lo que lleva. Antes colgaba al
	# costado y los objetos aparecían flotando al lado de las manos.
	carry_anchor.position = Vector3(0.0, 0.40, 0.28)
	_body_mesh.add_child(carry_anchor)              # gira con el personaje


## Pinta la remera y la cinta del sombrero con el color del jugador.
## Es lo que hace legible al personaje desde la cámara alta.
func _tint_shirt(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if not (m is StandardMaterial3D):
				continue
			var name := String(m.resource_name)
			if name != "shirt" and name != "band":
				continue
			var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_color = color if name == "shirt" else color.darkened(0.12)
			mi.set_surface_override_material(i, dup)


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
		if absf(dir.x) >= absf(dir.y):
			facing = Vector2i(signi(int(sign(dir.x))), 0)
		else:
			facing = Vector2i(0, signi(int(sign(dir.y))))
		walk_phase += delta * 12.0
		_body_mesh.rotation.y = _facing_angle()
		_body_mesh.position.y = absf(sin(walk_phase)) * 0.025
	else:
		_body_mesh.position.y = 0.0

	# ---- impulso ----------------------------------------------------------
	if _dash_pressed and dash_cd <= 0.0 and dir != Vector2.ZERO:
		dash_left = GameConfig.DASH_TIME
		dash_cd = GameConfig.DASH_COOLDOWN
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
	var speed := GameConfig.DASH_SPEED if dash_left > 0.0 else GameConfig.PLAYER_SPEED
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
	_body_mesh.rotation.y = _facing_angle()


## Animación procedural sobre las bisagras del GLB.
##   idle  → respiración (cabeza y brazos meciéndose)
##   mover → ciclo de caminata: piernas y brazos alternados, cuerpo que sube
##   llevar→ los brazos van adelante sosteniendo la caja
func _animate(delta: float) -> void:
	if _hinges.is_empty():
		return
	var moving := velocity.length() > 0.05
	var t := walk_phase
	var carry := carrying != null
	var arm_l: Node3D = _hinges.get("arm_l")
	var arm_r: Node3D = _hinges.get("arm_r")
	var leg_l: Node3D = _hinges.get("leg_l")
	var leg_r: Node3D = _hinges.get("leg_r")
	var head: Node3D = _hinges.get("head")
	var breath := sin(Time.get_ticks_msec() / 1000.0 * 2.2)

	if carry:
		# brazos adelante y un poco abiertos, como sosteniendo la caja
		if arm_l: arm_l.rotation = Vector3(-1.15, 0.0, 0.35)
		if arm_r: arm_r.rotation = Vector3(-1.15, 0.0, -0.35)
	else:
		var swing := 0.0
		if moving:
			swing = sin(t) * 0.55
		if arm_l: arm_l.rotation = Vector3(swing, 0.0, -0.06 + breath * 0.02)
		if arm_r: arm_r.rotation = Vector3(-swing, 0.0, 0.06 - breath * 0.02)

	if moving:
		if leg_l: leg_l.rotation = Vector3(-sin(t) * 0.62, 0.0, 0.0)
		if leg_r: leg_r.rotation = Vector3(sin(t) * 0.62, 0.0, 0.0)
	else:
		if leg_l: leg_l.rotation = Vector3(0.0, 0.0, 0.0)
		if leg_r: leg_r.rotation = Vector3(0.0, 0.0, 0.0)

	if head:
		# cabeceo al caminar + respiración en reposo; mirando un poco adelante
		head.rotation = Vector3(
			-0.04 + (0.02 * sin(t * 2.0) if moving else breath * 0.015),
			0.0,
			(0.03 * sin(t) if moving else breath * 0.02))


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
