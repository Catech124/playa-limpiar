class_name Crabs
extends RefCounted
## Cangrejos: cada tanto cruza uno por la arena y se vuelve al mar.
##
## Es puramente decorativo (no roba ni estorba): aparece en la orilla, camina
## de costado un rato y se va nadando. Usa el modelo aparte `cangrejo_suave.glb`.

const MAX_CRABS := 2

var game
var world: GridWorld
var list: Array = []
var timer := 14.0
var _scene: PackedScene


class Crab:
	var node: Node3D
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var ttl := 0.0
	var phase := "walk"          # walk | flee
	var wobble := 0.0


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
	crab.node = _scene.instantiate()
	_fit(crab.node, 0.22)
	world.add_child(crab.node)

	# aparece en la orilla y camina hacia la arena
	crab.pos = Vector3(randf_range(2.0, float(world.w) - 2.0), 0.0, 10.9)
	crab.target = Vector3(clampf(crab.pos.x + randf_range(-5.0, 5.0), 1.5, float(world.w) - 1.5),
		0.0, randf_range(5.0, 9.0))
	crab.ttl = randf_range(9.0, 15.0)
	crab.node.position = crab.pos
	list.append(crab)
	return true


func _advance(crab: Crab, delta: float) -> void:
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
	crab.pos += dir * minf(speed * delta, dist)
	crab.wobble += delta * 12.0

	# los cangrejos caminan de costado: el cuerpo mira perpendicular al avance
	var side := Vector3(-dir.z, 0.0, dir.x)
	crab.node.position = crab.pos + Vector3(0, absf(sin(crab.wobble)) * 0.012, 0) + side * sin(crab.wobble) * 0.02
	crab.node.rotation.y = atan2(dir.x, dir.z) + PI * 0.5


func _despawn(crab: Crab) -> void:
	if crab.node != null and is_instance_valid(crab.node):
		crab.node.queue_free()
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
		if crab.node != null and is_instance_valid(crab.node):
			crab.node.queue_free()
	list.clear()
