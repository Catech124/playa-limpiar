class_name ItemVisuals
extends RefCounted
## Geometría de los ítems. Sin assets: primitivas y color.
##
## Se mira todo desde la cámara alta (~12 unidades), así que la basura tiene que
## reconocerse por SILUETA y color: un cilindro pelado no dice "botella".
##   PET    → cuerpo ancho, etiqueta blanca, tapa oscura
##   vidrio → botellón verde, cuello largo, etiqueta crema
##   lata   → metal con banda de color y anilla
##
## La bolsa tiene DOS formas: en la mano es un cono atado; colgada en un
## contenedor va EXPANDIDA como forro, con el borde doblado sobre la boca y lo
## que lleva adentro a la vista, como una bolsa de basura de verdad.


static func material(c: Color, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	# el metal con la rugosidad del plástico se lee como plástico plateado
	m.roughness = lerpf(0.8, 0.30, metallic)
	return m


static func build(item: CarryItem) -> Node3D:
	var root := Node3D.new()
	item.node = root
	rebuild(item)
	return root


static func rebuild(item: CarryItem) -> void:
	if item.node == null:
		return
	for c in item.node.get_children():
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
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color, metallic)
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


## Botella de vidrio: más alta, cuello largo, etiqueta crema.
static func glass_bottle() -> Node3D:
	var root := Node3D.new()
	var c: Color = GameConfig.RESIDUES["vidrio"]["color"]
	var lab: Color = GameConfig.RESIDUES["vidrio"]["accent"]
	_cyl(root, 0.086, 0.094, 0.20, c, Vector3(0, 0.10, 0))                   # cuerpo
	_cyl(root, 0.033, 0.086, 0.11, c, Vector3(0, 0.255, 0))                  # hombro
	_cyl(root, 0.031, 0.031, 0.085, c, Vector3(0, 0.3525, 0))                # cuello
	_cyl(root, 0.040, 0.040, 0.022, c.darkened(0.35), Vector3(0, 0.406, 0))  # boca
	_cyl(root, 0.095, 0.095, 0.075, lab, Vector3(0, 0.095, 0))               # etiqueta
	return root


## Lata: metal, banda de color y anilla. Sin la banda parece un tarro.
static func metal_can() -> Node3D:
	var root := Node3D.new()
	var c: Color = GameConfig.RESIDUES["lata"]["color"]
	var lab: Color = GameConfig.RESIDUES["lata"]["accent"]
	_cyl(root, 0.080, 0.080, 0.21, c, Vector3(0, 0.105, 0), 0.55)            # cuerpo
	_cyl(root, 0.082, 0.082, 0.105, lab, Vector3(0, 0.115, 0))               # banda
	_cyl(root, 0.073, 0.073, 0.020, c.lightened(0.20), Vector3(0, 0.220, 0), 0.75)  # tapa
	_cyl(root, 0.070, 0.070, 0.012, c.darkened(0.12), Vector3(0, 0.006, 0), 0.55)   # fondo
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
	item.node.add_child(piece)


# ------------------------------------------------------------------ bolsas
static func _bag_color(item: CarryItem) -> Color:
	# blanca cuando está vacía, crema cuando ya no entra nada más
	return Color(0.95, 0.90, 0.62) if item.is_full() else Color(0.85, 0.91, 0.96)


## Bolsa de mano: cono atado con lo que lleva asomando por la boca.
static func _build_bag(item: CarryItem) -> void:
	var n := item.contents.size()
	var body_color := _bag_color(item)
	# más chica que la bolsa del contenedor: en la mano va comprimida y, si no,
	# tapaba al personaje entero (parecía una bata)
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


## Bolsa colgada en un contenedor: va EXPANDIDA como forro. El contenedor es una
## caja sólida (debajo de su cara superior no se ve nada), así que la bolsa se
## arma en tres piezas que es como se ve una bolsa real de arriba:
##   - el saco abierto (cilindro sin tapa y de doble cara: se ve el interior),
##   - el plástico tapando el marco de la boca,
##   - la falda que cuelga por FUERA del contenedor (lo que la delata como bolsa).
static func _build_bin_liner(item: CarryItem) -> void:
	var bin_top := float(GameConfig.STATION_HEIGHT.get("bin", 0.78))
	var plastic := _bag_color(item)
	var n := item.contents.size()
	var mouth_y := bin_top + 0.17        # sobresale un poco, como una bolsa real
	var bottom_y := bin_top - 0.30       # el fondo queda dentro del contenedor

	var sack := CylinderMesh.new()
	sack.top_radius = 0.335
	sack.bottom_radius = 0.30
	sack.height = mouth_y - bottom_y
	sack.radial_segments = 18
	sack.cap_top = false
	var sm := _mesh(item.node, sack, plastic, Vector3(0, (mouth_y + bottom_y) * 0.5, 0))
	sm.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	# el interior de un cilindro recibe la luz por la espalda: sin un poco de
	# emisión queda un pozo negro y no se ve la basura que hay adentro
	sm.material_override.emission_enabled = true
	sm.material_override.emission = plastic
	sm.material_override.emission_energy_multiplier = 0.45

	# fondo: es lo que se ve cuando la bolsa todavía está vacía
	var bottom := _cyl(item.node, 0.30, 0.30, 0.02, plastic.darkened(0.12),
		Vector3(0, bottom_y + 0.01, 0), 0.0, 18)
	bottom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# plástico sobre el marco (deja libre el círculo del saco)
	var cover_y := bin_top + 0.075
	for sz in [-1.0, 1.0]:
		_box(item.node, Vector3(1.00, 0.02, 0.16), plastic, Vector3(0, cover_y, sz * 0.42))
	for sx in [-1.0, 1.0]:
		_box(item.node, Vector3(0.16, 0.02, 0.68), plastic, Vector3(sx * 0.42, cover_y, 0))

	# falda que cuelga por fuera: alturas distintas para que no parezca una caja
	var skirt_top := bin_top + 0.06
	var skirts := [
		[Vector3(1.04, 0.17, 0.03), Vector3(0, skirt_top - 0.085, 0.48), Vector3(-4, 0, 0)],
		[Vector3(1.02, 0.13, 0.03), Vector3(0, skirt_top - 0.065, -0.48), Vector3(3, 0, 0)],
		[Vector3(0.03, 0.15, 1.00), Vector3(0.48, skirt_top - 0.075, 0), Vector3(0, 0, 4)],
		[Vector3(0.03, 0.19, 1.02), Vector3(-0.48, skirt_top - 0.095, 0.01), Vector3(0, 0, -3)],
	]
	for sk in skirts:
		var flap := _box(item.node, sk[0], plastic, sk[1])
		flap.rotation_degrees = sk[2]

	# borde enrollado: le da espesor al plástico de la boca
	var lip := TorusMesh.new()
	lip.inner_radius = 0.322
	lip.outer_radius = 0.350
	lip.rings = 20
	lip.ring_segments = 6
	_mesh(item.node, lip, plastic, Vector3(0, mouth_y, 0))


	# la basura que ya tiene adentro: se apila y asoma más cuanto más llena está
	var slots := [Vector3(-0.16, 0, -0.14), Vector3(0.16, 0, -0.14),
		Vector3(-0.16, 0, 0.14), Vector3(0.16, 0, 0.14)]
	if n == 1:
		slots = [Vector3.ZERO]
	elif n == 2:
		slots = [Vector3(-0.14, 0, -0.10), Vector3(0.14, 0, 0.10)]
	var pile := bottom_y + 0.19 + 0.05 * n
	for i in n:
		var mini := residue_piece(String(item.contents[i]))
		mini.scale = Vector3(0.85, 0.85, 0.85)
		mini.position = Vector3(0, pile, 0) + slots[i % slots.size()]
		mini.rotation_degrees = Vector3(-7.0 + (i % 3) * 7.0, i * 61.0, 6.0 - (i % 2) * 12.0)
		item.node.add_child(mini)
