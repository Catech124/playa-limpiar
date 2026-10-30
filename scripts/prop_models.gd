class_name PropModels
extends RefCounted
## Palmera, sombrilla y reposera (low-poly retro, generadas con
## `~/botes/playa.py`).
##
## La sombrilla y la reposera vienen con la tela en blanco para poder teñirlas
## desde el juego: `toldo_a` toma el color de la sombrilla y `tela` el de la
## reposera (el otro grupo de paneles queda crema, como las sombrillas de playa).

const PALM := "res://assets/palmera.glb"
const UMBRELLA := "res://assets/sombrilla.glb"
const LOUNGER := "res://assets/reposera.glb"

static var _cache := {}


static func _inst(ruta: String) -> Node3D:
	if not _cache.has(ruta):
		_cache[ruta] = load(ruta) if ResourceLoader.exists(ruta) else null
	var packed: PackedScene = _cache[ruta]
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Palmera: el modelo ya viene con la base del tronco en el origen.
static func build_palm() -> Node3D:
	return _inst(PALM)


## Sombrilla con el toldo teñido (los paneles `toldo_a`).
static func build_umbrella(color: Color) -> Node3D:
	var root := _inst(UMBRELLA)
	if root == null:
		return null
	_tint(root, "toldo_a", color)
	return root


## Reposera con las fajas de tela teñidas.
static func build_lounger(color: Color) -> Node3D:
	var root := _inst(LOUNGER)
	if root == null:
		return null
	_tint(root, "tela", color)
	return root


static func _tint(root: Node3D, prefijo: String, color: Color) -> void:
	var mat := ItemVisuals.material(color)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(prefijo):
			(mi as MeshInstance3D).material_override = mat
