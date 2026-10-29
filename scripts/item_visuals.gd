class_name ItemVisuals
extends RefCounted
## Geometría de los ítems. Sin assets: primitivas y color.
##
## Se mira todo desde la cámara alta (~12 unidades), así que la basura tiene que
## reconocerse por SILUETA y MATERIAL:
##   PET    → plástico azul con etiqueta blanca y tapa oscura
##   vidrio → botellón verde translúcido, cuello largo y etiqueta crema
##   lata   → metal brillante con banda de color y anilla
##
## La bolsa tiene DOS formas: en la mano es un cono atado; colgada en un
## contenedor va EXPANDIDA como forro, con el borde doblado sobre la boca y lo
## que lleva adentro a la vista, como una bolsa de basura de verdad.

## Alturas reales de cada pieza (el origen del dibujo es la base).
const RESIDUE_HEIGHT := {"pet": 0.356, "vidrio": 0.417, "lata": 0.236}
const RESIDUE_RADIUS := {"pet": 0.100, "vidrio": 0.095, "lata": 0.082}


static func residue_height(type: String) -> float:
	return float(RESIDUE_HEIGHT.get(type, 0.35))


static func residue_radius(type: String) -> float:
	return float(RESIDUE_RADIUS.get(type, 0.10))


## Cuánto bajar el ítem para que quede centrado en las manos (el origen del
## nodo es la base, así que si no se compensa la botella sube hasta la cara).
static func hold_offset(item: CarryItem) -> float:
	if item.is_bag():
		return 0.17
	return residue_height(item.type) * 0.45


## En la mano el residuo se achica: el chico mide 0.92 y una botella de tamaño
## real le tapa media cara y no deja ver que la agarra con las dos manos.
const CARRY_SCALE := 0.74
## La bolsa es la más grande de todas: en la mano va comprimida o tapa al chico
## entero (y no se ve que la lleva con las dos manos).
const CARRY_SCALE_BAG := 0.60


static func carry_scale(item: CarryItem) -> float:
	return CARRY_SCALE_BAG if item.is_bag() else CARRY_SCALE


# ------------------------------------------------------------------ materiales
static func material(c: Color, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	# el metal con la rugosidad del plástico se lee como plástico plateado
	m.roughness = lerpf(0.8, 0.18, metallic)
	if metallic > 0.3:
		m.metallic_specular = 1.0
	return m


## Vidrio: se ve el fondo a través y el borde brilla. En el renderer de
## compatibilidad no hay refracción, así que el efecto se arma con alfa, borde
## iluminado (rim) y rugosidad casi cero.
static func glass_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r * 0.9, c.g * 0.95, c.b * 0.9, 0.60)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.95
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.5
	# que no proyecte una sombra sólida de botella opaca
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Metal: con metallic 1 el color sale casi todo del reflejo del cielo y la lata
## queda azul oscura; por eso va satinada (0.7) con la rugosidad baja, que es
## como se lee una lata de aluminio con brillo.
static func metal_material(c: Color, polished := 1.0, metallic := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.lightened(0.12)
	m.metallic = metallic
	m.metallic_specular = 1.0
	m.roughness = 0.24 + (1.0 - polished) * 0.26
	return m


# ------------------------------------------------------------------ construcción
static func build(item: CarryItem) -> Node3D:
	var root: Node3D
	if item.is_residue():
		root = _make_residue_body(item)
	else:
		root = Node3D.new()
	item.node = root
	rebuild(item)
	return root


## La basura es un cuerpo rígido: se puede patear, rueda y se acuesta sola.
## El origen queda en la BASE del dibujo y la cápsula en el medio, así el cuerpo
## gira sobre su centro de masa (como una botella de verdad).
static func _make_residue_body(item: CarryItem) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Residue"
	body.mass = GameConfig.ITEM_MASS
	body.collision_layer = GameConfig.ITEM_LAYER
	body.collision_mask = 1 | GameConfig.ITEM_LAYER | GameConfig.WATER_LAYER
	body.continuous_cd = true
	body.linear_damp = 0.25
	body.angular_damp = 0.9

	var h := residue_height(item.type)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = residue_radius(item.type)
	cap.height = maxf(h, cap.radius * 2.0 + 0.01)
	shape.shape = cap
	shape.position = Vector3(0, h * 0.5, 0)
	body.add_child(shape)
	return body


static func rebuild(item: CarryItem) -> void:
	if item.node == null:
		return
	for c in item.node.get_children():
		if c is CollisionShape3D:
			continue          # la física no se toca: solo se redibuja la geometría
		item.node.remove_child(c)
		c.queue_free()
	if item.is_bag():
		if item.hung:
			_build_bin_liner(item)
		else:
			_build_bag(item)
	else:
		_build_residue(item)


static func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, metallic := 0.0) -> MeshInstance3D:
	return _mesh_mat(parent, mesh, material(color, metallic), pos)


static func _mesh_mat(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Cilindro rápido: es el 90% de las formas de este juego.
static func _cyl(parent: Node3D, top_r: float, bottom_r: float, height: float, color: Color,
		pos: Vector3, metallic := 0.0, segments := 14) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	return _mesh(parent, m, color, pos, metallic)


static func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, color, pos)


# ------------------------------------------------------------------ residuos
## Botella PET: cuerpo recto y ancho, etiqueta blanca, tapa oscura.
static func pet_bottle() -> Node3D:
	var root := Node3D.new()
	var c: Color = GameConfig.RESIDUES["pet"]["color"]
	var lab: Color = GameConfig.RESIDUES["pet"]["accent"]
	_cyl(root, 0.092, 0.100, 0.19, c, Vector3(0, 0.095, 0))                  # cuerpo
	_cyl(root, 0.048, 0.096, 0.075, c, Vector3(0, 0.2275, 0))                # hombro
	_cyl(root, 0.044, 0.044, 0.055, c, Vector3(0, 0.2925, 0))                # cuello
	_cyl(root, 0.050, 0.050, 0.036, c.darkened(0.38), Vector3(0, 0.338, 0))  # tapa
	_cyl(root, 0.101, 0.101, 0.085, lab, Vector3(0, 0.105, 0))               # etiqueta
	return root


## Botella de vidrio: verde translúcido, cuello largo, etiqueta crema.
static func glass_bottle() -> Node3D:
	var root := Node3D.new()
	var c: Color = GameConfig.RESIDUES["vidrio"]["color"]
	var lab: Color = GameConfig.RESIDUES["vidrio"]["accent"]
	var glass := glass_material(c)
	var dark := glass_material(c.darkened(0.35))

	var body := CylinderMesh.new()
	body.top_radius = 0.086
	body.bottom_radius = 0.094
	body.height = 0.20
	body.radial_segments = 16
	_mesh_mat(root, body, glass, Vector3(0, 0.10, 0))                        # cuerpo
	var shoulder := CylinderMesh.new()
	shoulder.top_radius = 0.033
	shoulder.bottom_radius = 0.086
	shoulder.height = 0.11
	shoulder.radial_segments = 16
	_mesh_mat(root, shoulder, glass, Vector3(0, 0.255, 0))                   # hombro
	var neck := CylinderMesh.new()
	neck.top_radius = 0.031
	neck.bottom_radius = 0.031
	neck.height = 0.085
	neck.radial_segments = 14
	_mesh_mat(root, neck, glass, Vector3(0, 0.3525, 0))                      # cuello
	var lip := CylinderMesh.new()
	lip.top_radius = 0.040
	lip.bottom_radius = 0.040
	lip.height = 0.022
	lip.radial_segments = 14
	_mesh_mat(root, lip, dark, Vector3(0, 0.406, 0))                         # boca
	_cyl(root, 0.095, 0.095, 0.075, lab, Vector3(0, 0.095, 0))               # etiqueta
	return root


## Lata: metal brillante, banda de color y anilla.
static func metal_can() -> Node3D:
	var root := Node3D.new()
	var c: Color = GameConfig.RESIDUES["lata"]["color"]
	var lab: Color = GameConfig.RESIDUES["lata"]["accent"]
	var steel := metal_material(c, 0.75)
	var shine := metal_material(c.lightened(0.25), 1.0)

	var body := CylinderMesh.new()
	body.top_radius = 0.080
	body.bottom_radius = 0.080
	body.height = 0.21
	body.radial_segments = 16
	_mesh_mat(root, body, steel, Vector3(0, 0.105, 0))                       # cuerpo
	_cyl(root, 0.082, 0.082, 0.105, lab, Vector3(0, 0.115, 0))               # banda
	var lid := CylinderMesh.new()
	lid.top_radius = 0.073
	lid.bottom_radius = 0.073
	lid.height = 0.020
	lid.radial_segments = 16
	_mesh_mat(root, lid, shine, Vector3(0, 0.220, 0))                        # tapa
	var base := CylinderMesh.new()
	base.top_radius = 0.070
	base.bottom_radius = 0.070
	base.height = 0.012
	base.radial_segments = 16
	_mesh_mat(root, base, steel, Vector3(0, 0.006, 0))                       # fondo
	var tab := BoxMesh.new()
	tab.size = Vector3(0.055, 0.008, 0.024)
	_mesh(root, tab, c.darkened(0.28), Vector3(0.012, 0.232, 0), 0.7)        # anilla
	return root


static func residue_piece(type: String) -> Node3D:
	match type:
		"pet":
			return pet_bottle()
		"lata":
			return metal_can()
		_:
			return glass_bottle()


static func _build_residue(item: CarryItem) -> void:
	var piece := residue_piece(item.type)
	# giro propio: diez botellas alineadas iguales parecen un patrón, no basura
	piece.rotation.y = randf() * TAU
	# "flota" apenas sobre la arena: se ve mejor y no se entierra en el piso
	piece.name = "Piece"
	piece.position.y = 0.02
	item.node.add_child(piece)


# ------------------------------------------------------------------ bolsas
static func _bag_color(item: CarryItem) -> Color:
	# blanca cuando está vacía, crema cuando ya no entra nada más
	return Color(0.95, 0.90, 0.62) if item.is_full() else Color(0.85, 0.91, 0.96)


## Bolsa de mano: cono atado con lo que lleva asomando por la boca.
static func _build_bag(item: CarryItem) -> void:
	var n := item.contents.size()
	var body_color := _bag_color(item)
	# más chica que la bolsa del contenedor: en la mano va comprimida
	var h_body := 0.28 + 0.02 * n
	var top := 0.14 + h_body * 0.5

	var body := CylinderMesh.new()
	body.top_radius = 0.115 + 0.006 * n
	body.bottom_radius = 0.155 + 0.010 * n
	body.height = h_body
	body.radial_segments = 14
	_mesh(item.node, body, body_color, Vector3(0, 0.14, 0))

	# nudo y asas arriba: es lo que hace que se lea "bolsa" y no "caja"
	var knot := SphereMesh.new()
	knot.radius = 0.042
	knot.height = 0.075
	_mesh(item.node, knot, body_color.darkened(0.16), Vector3(0, top + 0.02, 0))

	var handle := TorusMesh.new()
	handle.inner_radius = 0.05
	handle.outer_radius = 0.085
	handle.rings = 12
	var h := _mesh(item.node, handle, body_color.darkened(0.25), Vector3(0, top + 0.075, 0))
	h.rotation_degrees = Vector3(90, 0, 0)

	# lo que lleva adentro asoma por la boca: botellas de verdad, no bolitas
	for i in n:
		var mini := residue_piece(String(item.contents[i]))
		mini.scale = Vector3(0.38, 0.38, 0.38)
		mini.position = Vector3(-0.05 + (i % 2) * 0.10, top - 0.10, -0.04 + (i >> 1) * 0.08)
		mini.rotation_degrees = Vector3(-14.0 + (i % 3) * 10.0, i * 53.0, 8.0)
		item.node.add_child(mini)


## Bolsa colgada en un contenedor: va EXPANDIDA como forro. El bote es cuadrado,
## así que la bolsa también: cuatro paredes, el borde doblado sobre el marco, la
## falda arrugada por fuera y un nudo atado en una esquina. Un cilindro en el
## medio no se leía como bolsa.
static func _build_bin_liner(item: CarryItem) -> void:
	# El bote del GLB es ESTRECHO (0.47 x 0.57 de planta, boca a 0.84): el forro
	# entra justo y solo se dobla un poco sobre el labio. Con las medidas del
	# contenedor viejo (caja de 0.94) quedaba una bandeja blanca gigante encima.
	var mouth_y := 0.85
	var bottom_y := 0.46
	var wx := 0.40
	var wz := 0.48
	var plastic := _bag_color(item)
	var n := item.contents.size()
	var h := mouth_y - bottom_y

	# fondo y paredes del forro (finas: casi no se ven, es una bolsa)
	_box(item.node, Vector3(wx, 0.015, wz), plastic.lightened(0.04), Vector3(0, bottom_y, 0))
	for sx in [-1.0, 1.0]:
		var wall_x := _box(item.node, Vector3(0.015, h, wz), plastic,
			Vector3(sx * wx * 0.5, bottom_y + h * 0.5, 0))
		_wall_light(wall_x, plastic)
	for sz in [-1.0, 1.0]:
		var wall_z := _box(item.node, Vector3(wx, h, 0.015), plastic,
			Vector3(0, bottom_y + h * 0.5, sz * wz * 0.5))
		_wall_light(wall_z, plastic)

	# borde doblado sobre el labio: cuatro tiras finas, apenas más anchas que la
	# boca (no un marco ancho, que se leía como una mesa)
	for sz in [-1.0, 1.0]:
		var strip_z := _box(item.node, Vector3(wx + 0.08, 0.014, 0.07), plastic,
			Vector3(0, mouth_y, sz * (wz * 0.5 - 0.005)))
		strip_z.rotation_degrees = Vector3(0, 1.5 * sz, 0)
	for sx in [-1.0, 1.0]:
		var strip_x := _box(item.node, Vector3(0.07, 0.014, wz + 0.08), plastic,
			Vector3(sx * (wx * 0.5 - 0.005), mouth_y + 0.002, 0))
		strip_x.rotation_degrees = Vector3(0, -1.5 * sx, 0)

	# nudo atado en una esquina
	var knot := SphereMesh.new()
	knot.radius = 0.038
	knot.height = 0.075
	_mesh(item.node, knot, plastic.darkened(0.12), Vector3(0.13, mouth_y + 0.03, 0.17))

	# la basura que ya tiene adentro: asoma apenas por la boca
	var slots := [Vector3(-0.08, 0, -0.11), Vector3(0.08, 0, -0.11),
		Vector3(-0.08, 0, 0.11), Vector3(0.08, 0, 0.11)]
	if n == 1:
		slots = [Vector3.ZERO]
	elif n == 2:
		slots = [Vector3(-0.07, 0, -0.09), Vector3(0.07, 0, 0.09)]
	var pile := 0.58 + 0.035 * float(n)
	for i in n:
		var mini := residue_piece(String(item.contents[i]))
		mini.scale = Vector3(0.52, 0.52, 0.52)
		mini.position = Vector3(0, pile, 0) + slots[i % slots.size()]
		mini.rotation_degrees = Vector3(-7.0 + (i % 3) * 7.0, i * 61.0, 6.0 - (i % 2) * 12.0)
		item.node.add_child(mini)


## Las caras internas del forro reciben la luz por la espalda y quedan negras:
## un poco de emisión las deja del color del plástico (como una bolsa real).
static func _wall_light(mi: MeshInstance3D, plastic: Color) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		return
	m.emission_enabled = true
	m.emission = plastic
	m.emission_energy_multiplier = 0.42
