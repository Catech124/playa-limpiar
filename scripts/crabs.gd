class_name Crabs
extends RefCounted
## Cangrejos: cada tanto cruza uno por la arena y se vuelve al mar.
##
## Es decorativo (no roba ni resta puntos), pero SÍ es sólido: tiene collider
## propio, así que el jugador lo choca y la basura rebota en él. Camina de
## costado, y si se traba contra algo elige otro destino. Usa el modelo aparte
## `cangrejo_suave.glb`.

const MAX_CRABS := 2
## Tamaño del cangrejo y radio del collider (el modelo mide ~0.5 de ancho con
## las pinzas: el collider es más chico para no frenar al jugador de lejos).
const CRAB_HEIGHT := 0.22
const CRAB_RADIUS := 0.17

var game
var world: GridWorld
var list: Array = []
var timer := 14.0
var _scene: PackedScene


class Crab:
	var body: CharacterBody3D
	var model: Node3D
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var ttl := 0.0
	var phase := "walk"          # walk | flee
	var wobble := 0.0
	var stuck := 0.0             # segundos sin poder avanzar


func _init(g, w: GridWorld) -> void:
	game = g
	world = w


func tick(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = randf_range(24.0, 42.0)
		if game.is_playing() and list.size() < MAX_CRABS:
			spawn()

	for crab in list.duplicate():
		_advance(crab, delta)


func spawn() -> bool:
	if _scene == null:
		if not ResourceLoader.exists("res://assets/cangrejo_suave.glb"):
			return false
		_scene = load("res://assets/cangrejo_suave.glb") as PackedScene
		if _scene == null:
			return false

	var crab := Crab.new()

	# cuerpo con collider: así el jugador no lo atraviesa ni lo pisa
	var body := CharacterBody3D.new()
	body.name = "Cangrejo"
	body.collision_layer = 1
	body.collision_mask = 1
	# flotante: no le afectan escalones ni gravedad, camina en el plano
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = CRAB_RADIUS
	sh.height = CRAB_HEIGHT
	col.shape = sh
	col.position = Vector3(0.0, CRAB_HEIGHT * 0.5, 0.0)
	body.add_child(col)

	var model := _scene.instantiate() as Node3D
	_fit(model, CRAB_HEIGHT)
	body.add_child(model)

	world.add_child(body)
	crab.body = body
	crab.model = model

	# aparece en la orilla y camina hacia la arena
	crab.pos = Vector3(randf_range(2.0, float(world.w) - 2.0), 0.0, 10.9)
	crab.target = Vector3(clampf(crab.pos.x + randf_range(-5.0, 5.0), 1.5, float(world.w) - 1.5),
		0.0, randf_range(5.0, 9.0))
	crab.ttl = randf_range(9.0, 15.0)
	body.position = crab.pos
	list.append(crab)
	return true


func _advance(crab: Crab, delta: float) -> void:
	if crab.body == null or not is_instance_valid(crab.body):
		list.erase(crab)
		return

	crab.ttl -= delta
	if crab.ttl <= 0.0 and crab.phase == "walk":
		crab.phase = "flee"
		crab.target = Vector3(crab.pos.x, 0.0, 12.6)   # al agua

	var to := crab.target - crab.pos
	to.y = 0.0
	var dist := to.length()
	if dist < 0.2:
		if crab.phase == "flee":
			_despawn(crab)
			return
		crab.target = Vector3(clampf(crab.pos.x + randf_range(-4.0, 4.0), 1.5, float(world.w) - 1.5),
			0.0, randf_range(5.0, 9.0))
		return

	var dir := to / dist
	var speed := 1.5 if crab.phase == "flee" else 0.75
	crab.wobble += delta * 12.0

	# el collider hace el trabajo: si hay algo en el camino, se desliza o se
	# traba (y entonces busca otro lado, si no se queda empujando una sombrilla)
	var before := crab.body.position
	crab.body.velocity = dir * speed
	crab.body.move_and_slide()
	crab.pos = crab.body.position
	crab.pos.x = clampf(crab.pos.x, 1.2, float(world.w) - 1.2)
	crab.pos.z = clampf(crab.pos.z, 1.2, float(world.h) - 1.2)
	crab.body.position = crab.pos

	var avanzado := before.distance_to(crab.pos)
	if avanzado < speed * delta * 0.4:
		crab.stuck += delta
	else:
		crab.stuck = 0.0
	if crab.stuck > 0.6:
		crab.stuck = 0.0
		if crab.phase == "flee":
			# igual se va: busca otro hueco al agua
			crab.target = Vector3(clampf(crab.pos.x + randf_range(-3.0, 3.0), 1.5,
				float(world.w) - 1.5), 0.0, 12.6)
		else:
			crab.target = Vector3(clampf(crab.pos.x + randf_range(-4.0, 4.0), 1.5,
				float(world.w) - 1.5), 0.0, randf_range(5.0, 9.0))

	# los cangrejos caminan de costado: el cuerpo mira perpendicular al avance
	var side := Vector3(-dir.z, 0.0, dir.x)
	if crab.model != null and is_instance_valid(crab.model):
		crab.model.position.y = absf(sin(crab.wobble)) * 0.012
		crab.model.position.x = side.x * sin(crab.wobble) * 0.02
		crab.model.position.z = side.z * sin(crab.wobble) * 0.02
	crab.body.rotation.y = atan2(dir.x, dir.z) + PI * 0.5


func _despawn(crab: Crab) -> void:
	if crab.body != null and is_instance_valid(crab.body):
		crab.body.queue_free()
	list.erase(crab)


## Ajusta el GLB del cangrejo (viene en otra escala).
func _fit(node: Node3D, target: float) -> void:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.y < 0.001:
		return
	var k := target / box.size.y
	node.scale = Vector3(k, k, k)
	node.position.y = -box.position.y * k


func clear() -> void:
	for crab in list:
		if crab.body != null and is_instance_valid(crab.body):
			crab.body.queue_free()
	list.clear()
