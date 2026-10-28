class_name CellData
extends RefCounted
## Una celda del mapa y lo que contiene.

var x := 0
var y := 0
var ch := "."
var kind := "floor"      # floor | water | rock | station
var station := ""        # "" | bags | bin | delivery
var item: CarryItem = null   # ítem apoyado en la celda (suelo)
var bin: String = ""     # tipo de residuo que acepta un contenedor (pet/lata/vidrio)
var bag: CarryItem = null    # bolsa colgada en la boca de un contenedor
var decor := ""              # prop decorativo grande (palmera, torre, muelle)
var bin_hole: Node3D = null  # boca oscura del contenedor (se oculta con bolsa)


func is_solid() -> bool:
	return kind != "floor"


func can_hold() -> bool:
	# solo la arena sostiene cosas: estaciones y agua tienen su propio oficio
	return kind == "floor"


func top_y() -> float:
	if station != "":
		return float(GameConfig.STATION_HEIGHT.get(station, 0.7))
	return 0.06


func center() -> Vector3:
	return Vector3(x + 0.5, top_y(), y + 0.5)
