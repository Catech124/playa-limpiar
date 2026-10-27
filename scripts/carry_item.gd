class_name CarryItem
extends RefCounted
## Dos familias y nada más:
##   residue — basura de la playa (pet | lata | vidrio).
##   bag     — una bolsa con `contents` de tipos de residuo.
##
## El jugador transporta UN ítem a la vez, como en Overcooked: la restricción
## de manos es lo que crea el reparto de tareas.
##
## `life` y `origin` los usa la Fase 2 (la basura del mar se hunde, el vidrio
## se rompe, la gaviota se la lleva): acá solo se acumulan.

var kind := "residue"        # residue | bag
var type := ""               # pet | lata | vidrio (solo residuos)
var contents: Array = []     # solo bolsas: Array[String]
var node: Node3D = null      # visual en la escena
var hung := false            # bolsa colgada en un contenedor: cambia de forma
var life := 0.0              # segundos que lleva tirado en el piso
var origin := "beach"        # beach | water (el agua vale más en la Fase 3)


static func residue(t: String, from := "beach") -> CarryItem:
	var it := CarryItem.new()
	it.kind = "residue"
	it.type = t
	it.origin = from
	return it


static func bag(with_contents: Array = []) -> CarryItem:
	var it := CarryItem.new()
	it.kind = "bag"
	it.contents = with_contents.duplicate()
	return it


func is_bag() -> bool:
	return kind == "bag"


func is_residue() -> bool:
	return kind == "residue"


func has_room() -> bool:
	return contents.size() < GameConfig.BAG_CAPACITY


func is_full() -> bool:
	return contents.size() >= GameConfig.BAG_CAPACITY


func label() -> String:
	if is_bag():
		return "bolsa llena" if is_full() else "bolsa"
	return String(GameConfig.RESIDUES.get(type, {}).get("label", type))
