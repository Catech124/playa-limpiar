class_name CellData
extends RefCounted
## Una celda del mapa y lo que contiene.

var x := 0
var y := 0
var ch := "."
var kind := "floor"      # floor | water | rock | station
var station := ""        # "" | counter | pile | sort | bags | wash | delivery | return
var pool: Array = []     # tipos que entrega un montón
var item: CarryItem = null


func is_solid() -> bool:
	return kind != "floor"


func can_hold() -> bool:
	# mostradores y arena: sí. Estaciones con oficio (montón, mesa, camión...): no.
	return station == "counter" or kind == "floor"


func top_y() -> float:
	if station != "":
		return float(GameConfig.STATION_HEIGHT.get(station, 0.7))
	return 0.06


func center() -> Vector3:
	return Vector3(x + 0.5, top_y(), y + 0.5)
