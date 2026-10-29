class_name StationModels
extends RefCounted
## Dispensador de bolsas y camión de entrega (low-poly retro, generados con
## `~/botes/estaciones.py`).
##
## Los dos modelos vienen con el FRENTE hacia +Z (en Blender miraban a -Y) y
## apoyados en el piso, así que se usan sin rotación. El camión se escala para
## que ocupe exactamente el tramo de celdas que pide el mapa.

const BAGS_SCENE := "res://assets/dispensador.glb"
const TRUCK_SCENE := "res://assets/camion.glb"
## Alto final del dispensador en el juego (el modelo mide 0.885 en crudo).
const BAGS_HEIGHT := 0.95

static var _cache := {}


static func _inst(ruta: String) -> Node3D:
	if not _cache.has(ruta):
		_cache[ruta] = load(ruta) if ResourceLoader.exists(ruta) else null
	var packed: PackedScene = _cache[ruta]
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Dispensador de bolsas: centrado y apoyado en el piso.
static func build_bags() -> Node3D:
	var root := _inst(BAGS_SCENE)
	if root == null:
		return null
	var box := _bounds(root)
	if box.size.y < 0.001:
		return null
	var k := BAGS_HEIGHT / box.size.y
	var holder := Node3D.new()
	holder.add_child(root)
	# centrado en X y en Z por el cuerpo (el estante delantero sobresale, así
	# que se centra con la caja del cuerpo y no con la de todo el modelo)
	holder.position = Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y,
		-(box.position.z + box.size.z * 0.5))
	var wrapper := Node3D.new()
	wrapper.name = "Dispensador"
	wrapper.add_child(holder)
	wrapper.scale = Vector3(k, k, k)
	return wrapper


## Camión: se estira en largo hasta ocupar `largo` celdas y arranca en x = 0.
static func build_truck(largo: float) -> Node3D:
	var root := _inst(TRUCK_SCENE)
	if root == null:
		return null
	var box := _bounds(root)
	if box.size.x < 0.001:
		return null
	var k := largo / box.size.x
	var holder := Node3D.new()
	holder.add_child(root)
	holder.position = Vector3(-box.position.x, -box.position.y,
		-(box.position.z + box.size.z * 0.5))
	var wrapper := Node3D.new()
	wrapper.name = "Camion"
	wrapper.add_child(holder)
	wrapper.scale = Vector3(k, k, k)
	return wrapper


## AABB de todo lo que cuelga de `node`, en el espacio de `space`.
static func _bounds(node: Node3D, space: Node3D = null) -> AABB:
	if space == null:
		space = node
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
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
