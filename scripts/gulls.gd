class_name Gulls
extends RefCounted
## Gaviotas: la presión de dejar basura tirada.
## Bajan, agarran un residuo de la arena y se lo llevan volando. No lo tiran:
## la basura que se llevan está perdida (la Fase 2 le suma el castigo de −2).

var game
var world: GridWorld
var list: Array = []
var timer := 0.0


class Gull:
	var node: Node3D
	var pos := Vector3.ZERO
	var phase := "target"
	var target: CellData = null
	var carry: CarryItem = null
	var wobble := 0.0
	var wing_l: Node3D
	var wing_r: Node3D


func _init(g, w: GridWorld) -> void:
	game = g
	world = w
	timer = first_delay()


## La paciencia de la gaviota depende de cuántos jugadores hay: sola, la playa
## queda sin cubrir mientras se embolsa.
func first_delay() -> float:
	return float(GameConfig.GULL_FIRST_DELAY.get(int(game.player_count), 50.0))


func interval() -> float:
	return float(GameConfig.GULL_INTERVAL.get(int(game.player_count), 50.0))


func tick(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = interval()
		if game.is_playing():
			spawn()

	for g in list.duplicate():
		_advance(g, delta)


func spawn() -> bool:
	var targets: Array = []
	for row in world.tiles:
		for t in row:
			if t.item != null and t.item.is_residue():
				targets.append(t)
	if targets.is_empty():
		return false

	var g := Gull.new()
	g.target = targets[randi() % targets.size()]
	g.pos = Vector3(randf_range(2.0, world.w - 2.0), 2.4, -0.6)
	g.node = _build_gull(g)
	g.node.position = g.pos
	game.add_child(g.node)
	list.append(g)
	return true


## Las alas se guardan en el objeto Gull: sin esa referencia el aleteo no tiene
## a quién mover (era el bug que dejaba la gaviota clavada en "target").
func _build_gull(g: Gull) -> Node3D:
	var root := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.16, 0.14, 0.42)
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = ItemVisuals.material(Color(0.97, 0.97, 0.96))
	root.add_child(bm)

	var beak := BoxMesh.new()
	beak.size = Vector3(0.07, 0.05, 0.12)
	var bkm := MeshInstance3D.new()
	bkm.mesh = beak
	bkm.material_override = ItemVisuals.material(Color(0.91, 0.71, 0.23))
	bkm.position = Vector3(0, 0, -0.26)
	root.add_child(bkm)

	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.42, 0.04, 0.18)

	var wl := Node3D.new()
	var wlm := MeshInstance3D.new()
	wlm.mesh = wing_mesh
	wlm.material_override = ItemVisuals.material(Color(0.93, 0.93, 0.92))
	wlm.position = Vector3(-0.26, 0.02, 0)
	wl.add_child(wlm)
	root.add_child(wl)

	var wr := Node3D.new()
	var wrm := MeshInstance3D.new()
	wrm.mesh = wing_mesh
	wrm.material_override = ItemVisuals.material(Color(0.93, 0.93, 0.92))
	wrm.position = Vector3(0.26, 0.02, 0)
	wr.add_child(wrm)
	root.add_child(wr)

	g.wing_l = wl
	g.wing_r = wr
	return root


func _advance(g: Gull, delta: float) -> void:
	g.wobble += delta * 9.0
	if g.wing_l != null:
		g.wing_l.rotation.z = sin(g.wobble) * 0.5
	if g.wing_r != null:
		g.wing_r.rotation.z = -sin(g.wobble) * 0.5

	match g.phase:
		"target":
			if g.target == null or g.target.item == null:
				g.phase = "exit"
				return
			var to_target := Vector3(g.target.x + 0.5, 1.3, g.target.y + 0.5)
			_move(g, to_target, delta * GameConfig.GULL_SPEED)
			if g.pos.distance_to(to_target) < 0.15:
				# se lleva el residuo: no lo deja caer en otro lado
				g.carry = g.target.item
				g.target.item = null
				game._hold(g.carry)      # congelado en el pico: si no, se cae
				game.parent_item(g.carry.node, g.node)
				g.carry.node.position = Vector3(0, -0.2, 0)
				g.carry.node.scale = Vector3(0.7, 0.7, 0.7)
				game.stats["stolen"] = int(game.stats.get("stolen", 0)) + 1
				game.toast(Vector3(g.target.x + 0.5, 1.6, g.target.y + 0.5), "¡Gaviota!", "bad")
				g.phase = "exit"
		_:
			var edge := Vector3(g.pos.x, 3.4, -2.0)
			_move(g, edge, delta * GameConfig.GULL_SPEED * 1.4)
			if g.pos.z < -1.2:
				if g.carry != null:
					game.destroy_item(g.carry)
					g.carry = null
				g.node.queue_free()
				list.erase(g)


func _move(g: Gull, dest: Vector3, step: float) -> void:
	var dir := dest - g.pos
	var dist := dir.length()
	if dist > 0.0001:
		g.pos += dir / dist * minf(step, dist)
	g.node.position = g.pos
	g.node.rotation.y = atan2(dir.x, dir.z) + PI
