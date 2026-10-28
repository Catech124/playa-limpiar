class_name Npcs
extends RefCounted
## NPCs de la Fase 4: caminan por la playa, se acercan a la orilla y **tiran
## basura**. Son la excusa visual de por qué la playa se ensucia (y atan la
## ciudad del fondo con la arena).

var game
var world: GridWorld
var list: Array = []
var _chef: PackedScene


class Npc:
	var node: Node3D
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var phase := "walk"          # walk | throw
	var timer := 0.0
	var speed := 1.15
	var bob := 0.0
	var color := Color.WHITE
	var hinges := {}


func _init(g, w: GridWorld) -> void:
	game = g
	world = w


func spawn_all(count: int) -> void:
	if count <= 0:
		return
	_chef = load("res://assets/chef.glb") as PackedScene
	var palette := [Color(0.88, 0.45, 0.42), Color(0.40, 0.64, 0.86),
		Color(0.90, 0.74, 0.35)]
	for i in count:
		var npc := Npc.new()
		npc.color = palette[i % palette.size()]
		npc.pos = Vector3(3.0 + float(i) * 3.4, 0.0, 2.6 + float(i % 2) * 1.4)
		npc.target = _pick_target(npc.pos)
		npc.node = _build(npc)
		npc.node.position = npc.pos
		game.add_child(npc.node)
		list.append(npc)


func _build(npc: Npc) -> Node3D:
	var root := Node3D.new()
	var model: Node3D = _chef.instantiate()
	model.scale = Vector3(0.76, 0.76, 0.76)
	root.add_child(model)
	_tint_shirt(model, npc.color)
	for h in ["arm_l", "arm_r", "leg_l", "leg_r", "head", "hat"]:
		var node := model.find_child(h, true, false)
		if node is Node3D:
			npc.hinges[h] = node
	# sin el sombrero del chef: gorrita de playa, así se distingue de un vistazo
	var hat: Node3D = npc.hinges.get("hat")
	if hat != null:
		hat.visible = false
	var head: Node3D = npc.hinges.get("head")
	if head != null:
		var cap := SphereMesh.new()
		cap.radius = 0.27
		cap.height = 0.54
		cap.radial_segments = 14
		cap.rings = 7
		var cm := MeshInstance3D.new()
		cm.mesh = cap
		cm.material_override = ItemVisuals.material(npc.color.darkened(0.15))
		cm.position = Vector3(0, 0.44, 0)
		cm.scale = Vector3(1.02, 0.55, 1.02)
		head.add_child(cm)

		var brim := BoxMesh.new()
		brim.size = Vector3(0.34, 0.03, 0.20)
		var bm := MeshInstance3D.new()
		bm.mesh = brim
		bm.material_override = ItemVisuals.material(npc.color.darkened(0.28))
		bm.position = Vector3(0, 0.44, 0.24)
		head.add_child(bm)
	return root


## Misma idea que en el jugador: la remera y la cinta del sombrero toman el
## color del NPC para distinguirlo de un vistazo.
func _tint_shirt(root: Node, color: Color) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if not (m is StandardMaterial3D):
				continue
			var res_name := String(m.resource_name)
			if res_name != "shirt" and res_name != "band":
				continue
			var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_color = color if res_name == "shirt" else color.darkened(0.12)
			mi.set_surface_override_material(i, dup)


func tick(delta: float) -> void:
	if not game.is_playing():
		return
	for npc in list:
		_advance(npc, delta)


func _advance(npc: Npc, delta: float) -> void:
	var arm_r: Node3D = npc.hinges.get("arm_r")
	var arm_l: Node3D = npc.hinges.get("arm_l")
	var leg_l: Node3D = npc.hinges.get("leg_l")
	var leg_r: Node3D = npc.hinges.get("leg_r")

	if npc.phase == "throw":
		npc.timer -= delta
		# brazo arriba y latigazo al soltar
		if arm_r:
			var k: float = clampf(1.0 - npc.timer / 0.55, 0.0, 1.0)
			arm_r.rotation = Vector3(-2.6 + k * 1.4, 0.0, -0.30)
		if npc.timer <= 0.0:
			_throw(npc)
			npc.phase = "walk"
			npc.target = _pick_target(npc.pos)
		return

	var to := npc.target - npc.pos
	to.y = 0.0
	var dist := to.length()
	if dist < 0.15:
		npc.phase = "throw"
		npc.timer = 0.55
		if arm_l: arm_l.rotation = Vector3.ZERO
		return

	var dir := to / dist
	npc.pos += dir * minf(npc.speed * delta, dist)
	npc.bob += delta * 8.0
	npc.node.position = npc.pos + Vector3(0, absf(sin(npc.bob)) * 0.025, 0)
	npc.node.rotation.y = atan2(dir.x, dir.z)

	var swing := sin(npc.bob) * 0.45
	if arm_l: arm_l.rotation = Vector3(swing, 0.0, -0.06)
	if arm_r: arm_r.rotation = Vector3(-swing, 0.0, 0.06)
	if leg_l: leg_l.rotation = Vector3(-sin(npc.bob) * 0.5, 0.0, 0.0)
	if leg_r: leg_r.rotation = Vector3(sin(npc.bob) * 0.5, 0.0, 0.0)


## Tira una basura al arenal: la elige el spawner (con el sesgo por cuota) y
## vuela con la misma parábola que el lanzamiento del jugador.
func _throw(npc: Npc) -> void:
	var tile: CellData = game.spawner.pick_tile()
	if tile == null:
		return
	game.npc_throw(npc.pos + Vector3(0, 1.15, 0), tile)
	game.toast(npc.pos + Vector3(0, 1.6, 0), "¡Tiró basura!", "info")


## Punto al azar del arenal, cerca de la orilla: así se los ve caminar y volver.
func _pick_target(from: Vector3) -> Vector3:
	for i in 12:
		var tx := randf_range(2.0, float(world.w) - 2.0)
		var ty := randf_range(3.0, 9.5)
		var d := Vector2(tx - from.x, ty - from.z).length()
		if d < 1.5:
			continue
		var t := world.tile_at(int(tx), int(ty))
		if t == null or not t.can_hold() or t.decor != "":
			continue
		return Vector3(tx, 0.0, ty)
	return from + Vector3(1.0, 0.0, 1.0)
