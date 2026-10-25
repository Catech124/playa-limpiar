class_name CarryItem
extends RefCounted
## Dos familias y nada más:
##   residue — un residuo (crudo -> clasificado). `progress` guarda el avance
##             de clasificación para que soltar la tecla no lo pierda.
##   bag     — una bolsa (limpia o sucia) con `contents` de tipos de residuo.
##
## El jugador transporta UN ítem a la vez, como en Overcooked: la restricción
## de manos es lo que crea el reparto de tareas.

var kind := "residue"        # residue | bag
var type := ""               # pet | lata | vidrio (solo residuos)
var classified := false
var clean := true            # solo bolsas
var contents: Array = []     # solo bolsas: Array[String]
var progress := 0.0
var node: Node3D = null      # visual en la escena


static func residue(t: String) -> CarryItem:
	var it := CarryItem.new()
	it.kind = "residue"
	it.type = t
	return it


static func bag(is_clean := true, with_contents: Array = []) -> CarryItem:
	var it := CarryItem.new()
	it.kind = "bag"
	it.clean = is_clean
	it.contents = with_contents.duplicate()
	return it


func is_bag() -> bool:
	return kind == "bag"


func is_residue() -> bool:
	return kind == "residue"


func has_room() -> bool:
	return contents.size() < GameConfig.BAG_CAPACITY


func signature() -> String:
	var c := contents.duplicate()
	c.sort()
	return "+".join(c)


func label() -> String:
	if is_bag():
		return "bolsa" if clean else "bolsa sucia"
	return String(GameConfig.RESIDUES.get(type, {}).get("label", type))
