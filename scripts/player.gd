class_name Player
extends CharacterBody3D
## Movimiento + interacción. Un solo botón contextual, como Overcooked:
##   mover · ACCIÓN (recoger / soltar / trabajar) · IMPULSO · LANZAR
##
## El trabajo (clasificar / lavar) es MANTENER la acción mirando la estación:
## soltar la tecla no pierde el avance (queda en el ítem).

const CHEF_SCENE := preload("res://assets/chef.glb")

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
	var model := CHEF_SCENE.instantiate()
	_body_mesh.add_child(model)
	_tint_shirt(model)

	# anillo en el piso (legibilidad)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.27
	ring.outer_radius = 0.34
	ring.rings = 20
	var rm := MeshInstance3D.new()
	rm.mesh = ring
	var rmat := ItemVisuals.material(color.darkened(0.1))
	rmat.emission_enabled = true
	rmat.emission = color
	rmat.emission_energy_multiplier = 0.18
	rm.material_override = rmat
	rm.rotation_degrees = Vector3(90, 0, 0)
	rm.position = Vector3(0, 0.03, 0)
	_body_mesh.add_child(rm)

	carry_anchor = Node3D.new()
	carry_anchor.position = Vector3(0, 1.44, 0)
	add_child(carry_anchor)


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

	# ---- trabajo sostenido ------------------------------------------------
	var front := front_tile()
	var holding := Input.is_physical_key_pressed(keymap["action"])
	if holding and front != null and game.player_channel(self, front, delta):
		pass

	# ---- acción puntual ---------------------------------------------------
	if _act_pressed:
		_act_pressed = false
		if front != null:
			game.player_use(self, front)


func move_step(dir: Vector2) -> void:
	var speed := GameConfig.DASH_SPEED if dash_left > 0.0 else GameConfig.PLAYER_SPEED
	if dir == Vector2.ZERO:
		velocity = Vector3.ZERO
	else:
		velocity = Vector3(dir.x, 0.0, dir.y) * speed
	move_and_slide()


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


func _facing_angle() -> float:
	if facing.x > 0:
		return -PI * 0.5
	if facing.x < 0:
		return PI * 0.5
	if facing.y > 0:
		return PI
	return 0.0
