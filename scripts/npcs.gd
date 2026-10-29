class_name Npcs
extends RefCounted
## NPCs de la Fase 4: **veraneantes**. No pasean sin rumbo: cada uno está
## haciendo algo distinto en la arena (tomando sol, sentado, charlando), se
## levanta cada tanto, camina hasta la orilla y **tira basura al mar**.
##
## Son la razón visual de que la playa se ensucie y atan la ciudad del fondo con
## la arena. La basura que tiran cae al agua y flota: hay que rescatarla antes de
## que se hunda.

var game
var world: GridWorld
var list: Array = []


class Npc:
	var node: Node3D
	var body: Node3D
	var home := Vector3.ZERO
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var activity := "lie"        # lie | sit | chat
	var phase := "idle"          # idle | stand | walk_out | throw | walk_home
	var timer := 0.0
	var bob := 0.0
	var color := Color.WHITE
	var hinges := {}
	var pose_blend := 1.0        # 1 = en su actividad, 0 = parado
	var throw_blend := 0.0


func _init(g, w: GridWorld) -> void:
	game = g
	world = w


func spawn_all(count: int) -> void:
	if count <= 0:
		return
	var palette := [Color(0.88, 0.45, 0.42), Color(0.40, 0.64, 0.86),
		Color(0.90, 0.74, 0.35), Color(0.55, 0.80, 0.55)]
	# Dos charlando frente a frente y uno tomando sol: se lee de un vistazo.
	var spots := [Vector3(4.2, 0.0, 6.2), Vector3(13.6, 0.0, 5.8),
		Vector3(15.4, 0.0, 6.1), Vector3(19.0, 0.0, 8.0)]
	var acts := ["lie", "chat", "chat", "lie"]
	for i in count:
		var npc := Npc.new()
		npc.color = palette[i % palette.size()]
		npc.activity = acts[i % acts.size()]
		npc.home = spots[i % spots.size()]
		npc.pos = npc.home
		npc.timer = randf_range(10.0, 22.0)
		npc.node = _build(npc)
		npc.node.position = npc.pos
		game.add_child(npc.node)
		if npc.activity == "lie":
			_add_towel(npc)
		list.append(npc)


func _build(npc: Npc) -> Node3D:
	var root := Node3D.new()
	# mismo modelo que el jugador; a los NPCs se les cambia el sombrero por gorrita
	var model: Node3D = null
	if ResourceLoader.exists("res://assets/kid.glb"):
		var packed := load("res://assets/kid.glb") as PackedScene
		if packed != null:
			model = packed.instantiate()
	if model == null:
		model = CharModel.build(npc.color, "cap")
	root.add_child(model)
	for h in ["arm_l", "arm_r", "leg_l", "leg_r", "head", "hat"]:
		var node := model.find_child(h, true, false)
		if node is Node3D:
			npc.hinges[h] = node

	# gorrita: se oculta el sombrero de paja y se agrega una gorra al cráneo
	var hat: Node3D = npc.hinges.get("hat")
	if hat != null:
		hat.visible = false
	var head: Node3D = npc.hinges.get("head")
	if head != null:
		var cap := SphereMesh.new()
		cap.radius = 0.205
		cap.height = 0.41
		cap.radial_segments = 20
		cap.rings = 10
		var cm := MeshInstance3D.new()
		cm.mesh = cap
		cm.material_override = ItemVisuals.material(npc.color.darkened(0.10))
		cm.position = Vector3(0, 0.20, 0)
		cm.scale = Vector3(1.0, 0.62, 1.0)
		head.add_child(cm)
		var visor := BoxMesh.new()
		visor.size = Vector3(0.26, 0.022, 0.16)
		var vm := MeshInstance3D.new()
		vm.mesh = visor
		vm.material_override = ItemVisuals.material(npc.color.darkened(0.25))
		vm.position = Vector3(0, 0.245, 0.185)
		vm.rotation_degrees = Vector3(-8, 0, 0)
		head.add_child(vm)

	npc.body = model
	return root


## Toalla bajo el que toma sol.
func _add_towel(npc: Npc) -> void:
	var towel := BoxMesh.new()
	towel.size = Vector3(0.75, 0.02, 1.5)
	var mi := MeshInstance3D.new()
	mi.mesh = towel
	mi.material_override = ItemVisuals.material(npc.color.lightened(0.45))
	mi.position = npc.home + Vector3(0.0, 0.008, -0.45)
	mi.rotation_degrees = Vector3(0, 8, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(mi)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.16, 0.021, 1.5)
	var sm := MeshInstance3D.new()
	sm.mesh = stripe
	sm.material_override = ItemVisuals.material(Color(0.97, 0.97, 0.95))
	sm.position = npc.home + Vector3(0.18, 0.010, -0.45)
	sm.rotation_degrees = Vector3(0, 8, 0)
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(sm)



func tick(delta: float) -> void:
	if not game.is_playing():
		return
	for npc in list:
		_advance(npc, delta)


func _advance(npc: Npc, delta: float) -> void:
	var arm_l: Node3D = npc.hinges.get("arm_l")
	var arm_r: Node3D = npc.hinges.get("arm_r")
	var leg_l: Node3D = npc.hinges.get("leg_l")
	var leg_r: Node3D = npc.hinges.get("leg_r")
	var head: Node3D = npc.hinges.get("head")

	match npc.phase:
		"idle":
			npc.timer -= delta
			npc.pose_blend = move_toward(npc.pose_blend, 1.0, delta * 3.0)
			_pose_activity(npc, delta, arm_l, arm_r, leg_l, leg_r, head)
			if npc.timer <= 0.0:
				npc.phase = "stand"
				npc.timer = 0.55
		"stand":
			# se levanta y se sacude la arena
			npc.pose_blend = move_toward(npc.pose_blend, 0.0, delta * 4.0)
			npc.timer -= delta
			_pose_activity(npc, delta, arm_l, arm_r, leg_l, leg_r, head)
			if npc.timer <= 0.0:
				npc.phase = "walk_out"
				npc.target = _shore_point(npc.home)
		"walk_out", "walk_home":
			npc.pose_blend = move_toward(npc.pose_blend, 0.0, delta * 4.0)
			var to := npc.target - npc.pos
			to.y = 0.0
			var dist := to.length()
			if dist < 0.18:
				if npc.phase == "walk_out":
					npc.phase = "throw"
					npc.timer = 1.0
				else:
					npc.phase = "idle"
					npc.timer = randf_range(16.0, 26.0)
				return
			var dir := to / dist
			npc.pos += dir * minf(1.15 * delta, dist)
			npc.bob += delta * 8.0
			npc.node.position = npc.pos + Vector3(0, absf(sin(npc.bob)) * 0.025, 0)
			npc.node.rotation.y = atan2(dir.x, dir.z)
			var swing := sin(npc.bob) * 0.45
			if arm_l: arm_l.rotation = Vector3(swing, 0.0, Player.ARM_REST_L - 0.06)
			if arm_r: arm_r.rotation = Vector3(-swing, 0.0, Player.ARM_REST_R + 0.06)
			if leg_l: leg_l.rotation = Vector3(-sin(npc.bob) * 0.5, 0.0, 0.0)
			if leg_r: leg_r.rotation = Vector3(sin(npc.bob) * 0.5, 0.0, 0.0)
		"throw":
			npc.timer -= delta
			var k: float = 1.0 - clampf(npc.timer / 1.0, 0.0, 1.0)
			npc.node.rotation.y = PI          # mira al mar
			# se arma atrás y suelta el latigazo
			if arm_r: arm_r.rotation = Vector3(1.5 - k * 3.2, 0.0, Player.ARM_REST_R + 0.25)
			if arm_l: arm_l.rotation = Vector3(0.5 - k * 0.4, 0.0, Player.ARM_REST_L - 0.05)
			npc.body.rotation.x = 0.18 - k * 0.45
			if npc.timer <= 0.5 and not npc.has_meta("thrown"):
				npc.set_meta("thrown", true)
				_throw(npc)
			if npc.timer <= 0.0:
				npc.remove_meta("thrown")
				npc.body.rotation.x = 0.0
				npc.phase = "walk_home"
				npc.target = npc.home


## Posturas de "veraneante": cada NPC hace algo distinto y se lo ve cómodo.
func _pose_activity(npc: Npc, delta: float, arm_l: Node3D, arm_r: Node3D,
		leg_l: Node3D, leg_r: Node3D, head: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var b := npc.pose_blend
	var breath := sin(now * 1.8 + float(npc.color.r) * 10.0)

	match npc.activity:
		"lie":
			npc.node.rotation.y = 0.0
			# panza arriba, manos detrás de la nuca, una pierna cruzada
			npc.body.rotation.x = -1.45 * b
			npc.body.position.y = 0.10 * b
			npc.body.position.z = -0.45 * b
			if arm_l:
				arm_l.rotation = Vector3(0.0, 0.0, Player.ARM_REST_L + 2.35 * b)
			if arm_r:
				arm_r.rotation = Vector3(0.0, 0.0, Player.ARM_REST_R - 2.35 * b)
			if leg_l: leg_l.rotation = Vector3(-0.10 * b, 0.0, 0.16 * b)
			if leg_r: leg_r.rotation = Vector3(-0.22 * b, 0.0, -0.10 * b)
			if head: head.rotation = Vector3(0.12 * b + breath * 0.02, 0.0, 0.0)
		"sit":
			# sentado de costado (así se le ven las piernas desde la cámara)
			npc.node.rotation.y = 2.35
			npc.body.rotation.x = -0.30 * b
			npc.body.position.y = -0.18 * b
			npc.body.position.z = 0.14 * b
			# brazos descansando sobre las rodillas
			if arm_l:
				arm_l.rotation = Vector3(-0.85 * b + breath * 0.03, 0.0, Player.ARM_REST_L + 0.20 * b)
			if arm_r:
				arm_r.rotation = Vector3(-0.85 * b - breath * 0.03, 0.0, Player.ARM_REST_R - 0.20 * b)
			if leg_l: leg_l.rotation = Vector3(-1.55 * b, 0.0, 0.14 * b)
			if leg_r: leg_r.rotation = Vector3(-1.45 * b, 0.0, -0.12 * b)
			if head: head.rotation = Vector3(-0.06 * b, 0.0, 0.02)
		_:
			# charlando: de pie frente a otro veraneante, gesticulando
			var other := _nearest_npc(npc)
			if other != null:
				var d: Vector3 = other.pos - npc.pos
				npc.node.rotation.y = atan2(d.x, d.z)
			else:
				npc.node.rotation.y = PI
			npc.body.rotation.x = 0.0
			npc.body.position.y = 0.0
			npc.body.position.z = 0.0
			var gesture := sin(now * 2.6 + float(npc.color.g) * 12.0)
			if arm_l:
				arm_l.rotation = Vector3(-0.55 - gesture * 0.30, 0.0, Player.ARM_REST_L - 0.42)
			if arm_r:
				arm_r.rotation = Vector3(-0.35 + gesture * 0.42, 0.0, Player.ARM_REST_R + 0.38)
			if leg_l: leg_l.rotation = Vector3.ZERO
			if leg_r: leg_r.rotation = Vector3.ZERO
			if head:
				head.rotation = Vector3(-0.04 + gesture * 0.06, gesture * 0.18, 0.0)


## Tira la basura AL MAR: la elige el spawner y vuela con la misma parábola que
## el lanzamiento del jugador, pero a una celda de agua (flota y se hunde).
func _throw(npc: Npc) -> void:
	var tile: CellData = game.spawner.pick_water_tile()
	if tile == null:
		tile = game.spawner.pick_tile()
	if tile == null:
		return
	game.npc_throw(npc.pos + Vector3(0, 1.1, 0.35), tile, tile.kind == "water")


func _nearest_npc(npc: Npc) -> Npc:
	var best: Npc = null
	var best_d := 99.0
	for other in list:
		if other == npc:
			continue
		var d: float = other.pos.distance_to(npc.pos)
		if d < best_d:
			best_d = d
			best = other
	return best


## Punto de la orilla al que camina para tirar (frente al agua, cerca de casa).
func _shore_point(home: Vector3) -> Vector3:
	var ty := 9.7
	for row in range(9, 12):
		var t := world.tile_at(int(home.x), row)
		if t != null and t.kind == "floor":
			ty = float(row) + 0.3
	return Vector3(home.x, 0.0, ty)
