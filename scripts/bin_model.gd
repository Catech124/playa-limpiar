class_name BinModel
extends RefCounted
## Botes recicladores low-poly retro (assets/botes_reciclaje.glb).
##
## El GLB trae los TRES botes en fila (VIDRIO, PET, METAL) con las tapas como
## objetos aparte y el origen en la bisagra. Acá se instancia, se deja UNO solo
## según el tipo de contenedor, se centra, se escala al alto del juego y se
## orienta con la placa PUSH mirando a la cámara (+Z).

const SCENE := "res://assets/botes_reciclaje.glb"
## Alto final del bote: un poco menos que el chico (0.92), como un contenedor
## de verdad al lado de una persona.
const HEIGHT := 0.95
## Distancia entre botes en el GLB (los tres están a -0.655, 0 y +0.655).
const SPACING := 0.655

static var _scene: PackedScene
static var _kinds := {}       # "vidrio" -> x del bote en el GLB


static func _load() -> PackedScene:
	if _scene == null and ResourceLoader.exists(SCENE):
		_scene = load(SCENE) as PackedScene
	return _scene


## Devuelve el bote armado (origen en el piso, centrado, mirando a +Z) o null.
static func build(kind: String) -> Node3D:
	var packed := _load()
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null

	var clusters := _scan(root)
	if clusters.is_empty():
		root.queue_free()
		return null
	var cx := float(clusters.get(kind, clusters.values()[0]))

	# dejar SOLO el bote que corresponde (los otros dos se tiran)
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var n3 := child as Node3D
		if absf(n3.position.x - cx) > SPACING * 0.5:
			root.remove_child(n3)
			n3.queue_free()

	# la bolsa negra y las latas de adentro son del modelo: el juego dibuja su
	# propio forro cuando cuelgan una bolsa (si no, se verían dos bolsas)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.begins_with("bolsa") or nm.begins_with("m_lata"):
			mi.visible = false

	var lid := _find_lid(root)
	if lid != null:
		lid.name = "Lid"

	# centrar en X y apoyar en el piso (se mide, no se supone)
	var box := _bounds(root, root)
	var holder := Node3D.new()
	holder.name = "Bote"
	holder.add_child(root)
	root.position = Vector3(-cx, 0.0, 0.0)

	var k := HEIGHT / maxf(0.001, box.size.y)
	holder.position = Vector3(0.0, -box.position.y, 0.0)

	var wrapper := Node3D.new()
	wrapper.name = "BoteReciclador"
	wrapper.add_child(holder)
	wrapper.scale = Vector3(k, k, k)
	wrapper.rotation.y = PI            # la placa PUSH mira a +Z (a la cámara)
	return wrapper


## Tipo de cada bote del GLB, leyendo el material del cuerpo.
static func _scan(root: Node3D) -> Dictionary:
	var out := {}
	for child in root.get_children():
		if not String(child.name).begins_with("cuerpo"):
			continue
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var kind := _kind_of(mi)
		if kind != "":
			out[kind] = child.position.x
	return out


static func _kind_of(mi: MeshInstance3D) -> String:
	var mat := mi.get_active_material(0)
	if mat != null:
		var nm := String(mat.resource_name).to_upper()
		if nm.contains("VIDRIO"):
			return "vidrio"
		if nm.contains("PET"):
			return "pet"
		if nm.contains("METAL") or nm.contains("LATA"):
			return "lata"
		# sin nombre útil: se clasifica por color (verde / amarillo / gris)
		var c := (mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else Color.GRAY
		if c.g > c.r * 1.4 and c.g > c.b * 1.4:
			return "vidrio"
		if c.r > c.b * 1.6 and c.g > c.b * 1.3:
			return "pet"
		return "lata"
	return ""


## La tapa del bote que quedó (su origen está en la bisagra).
static func _find_lid(root: Node3D) -> Node3D:
	# ojo: Godot sanea los nombres del GLB ("tapa.001" -> "tapa_001") y
	# "tapa_panel"/"tapa_placa" también empiezan con "tapa": solo vale el nodo
	# cuyo sufijo es vacío o un número
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var nm := String(child.name)
		if not nm.begins_with("tapa"):
			continue
		var resto := nm.substr(4)
		if resto == "" or resto.is_valid_int() or (resto.begins_with("_") and resto.substr(1).is_valid_int()):
			return child as Node3D
	return null


## AABB de todo lo que cuelga de `node`, en el espacio de `space`.
static func _bounds(node: Node3D, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if not (mi as Node3D).is_visible_in_tree():
			continue
		var tr := _accum(mi as Node3D, space)
		var b: AABB = tr * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _accum(node: Node3D, space: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != space:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t
