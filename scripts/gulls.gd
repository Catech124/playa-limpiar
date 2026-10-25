class_name Gulls
extends RefCounted
## Gaviotas: el análogo de las ratas de Overcooked.
## No quitan puntos: rompen la comodidad de "clasifico todo y lo dejo en el
## mostrador". Roban un residuo YA clasificado, lo sueltan en la arena y se van.

var game
var world: GridWorld
var list: Array = []
var timer := GameConfig.GULL_FIRST_DELAY


class Gull:
	var node: Node3D
	var pos := Vector3.ZERO
	var phase := "target"
	var target: CellData = null
	var drop: CellData = null
	var carry: CarryItem = null
	var wobble := 0.0
	var wing_l: Node3D
	var wing_r: Node3D


func _init(g, w: GridWorld) -> void:
	game = g
	world = w


func tick(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = GameConfig.GULL_INTERVAL
		if game.is_playing():
			spawn()

	for g in list.duplicate():
		_advance(g, delta)


func spawn() -> void:
	var targets: Array = []
	for row in world.tiles:
		for t in row:
			if t.item != null and t.item.is_residue() and t.item.classified:
				targets.append(t)
	if targets.is_empty():
		return

	var g := Gull.new()
	g.target = targets[randi() % targets.size()]
	g.pos = Vector3(randf_range(2.0, world.w - 2.0), 2.4, -0.6)
	g.node = _build_gull()
	g.node.position = g.pos
	game.add_child(g.node)
	list.append(g)


func _build_gull() -> Node3D:
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

	return root


func _advance(g: Gull, delta: float) -> void:
	g.wobble += delta * 9.0
	g.wing_l.rotation.z = sin(g.wobble) * 0.5
	g.wing_r.rotation.z = -sin(g.wobble) * 0.5

	match g.phase:
		"target":
			if g.target == null:
				g.phase = "exit"
				return
			var to_target := Vector3(g.target.x + 0.5, 1.6, g.target.y + 0.5)
			_move(g, to_target, delta * GameConfig.GULL_SPEED)
			if g.pos.distance_to(to_target) < 0.15:
				if g.target.item != null and g.target.item.is_residue():
					g.carry = g.target.item
					g.target.item = null
					game.parent_item(g.carry.node, g.node)
					g.carry.node.position = Vector3(0, -0.2, 0)
					g.carry.node.scale = Vector3(0.7, 0.7, 0.7)
					var floors := world.free_floors_near(g.target.x, g.target.y, 6)
					g.drop = floors[randi() % floors.size()] if not floors.is_empty() else null
					game.toast(Vector3(g.target.x + 0.5, 1.6, g.target.y + 0.5), "¡Gaviota!", "bad")
					g.phase = "drop" if g.drop != null else "exit"
				else:
					g.phase = "exit"
		"drop":
			var to_drop := Vector3(g.drop.x + 0.5, 0.7, g.drop.y + 0.5)
			_move(g, to_drop, delta * GameConfig.GULL_SPEED)
			if g.pos.distance_to(to_drop) < 0.15:
				if g.carry != null:
					if g.drop.item == null:
						g.carry.node.scale = Vector3.ONE
						game.move_item_to_tile(g.carry, g.drop)
					else:
						game.destroy_item(g.carry)
					g.carry = null
				g.phase = "exit"
		_:
			var edge := Vector3(g.pos.x, 3.2, -1.5)
			_move(g, edge, delta * GameConfig.GULL_SPEED * 1.4)
			if g.pos.z < 0.2:
				g.node.queue_free()
				list.erase(g)


func _move(g: Gull, dest: Vector3, step: float) -> void:
	var dir := dest - g.pos
	var dist := dir.length()
	if dist > 0.0001:
		g.pos += dir / dist * minf(step, dist)
	g.node.position = g.pos
	g.node.rotation.y = atan2(dir.x, dir.z) + PI
