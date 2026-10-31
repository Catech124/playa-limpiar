class_name SaveGame
extends RefCounted
## Progreso permanente en disco: desbloqueos y récords.
##
## No hay moneda permanente (como en Balatro): lo que se abre, se abre jugando
## y se mira en la Colección. La plata para comprar cartas es de la run.
##
## `ruta` es estática y configurable para que los tests usen un archivo temporal
## y no toquen la partida real.

const RUTA := "user://playa_save.cfg"

static var ruta := RUTA
static var desbloqueos: Array = []
static var mejor_dia := 0
static var mejor_puntaje := 0
static var dias_jugados := 0
static var runs := 0
static var _cargado := false


static func cargar(forzar := false) -> void:
	if _cargado and not forzar:
		return
	_cargado = true
	desbloqueos = []
	mejor_dia = 0
	mejor_puntaje = 0
	dias_jugados = 0
	runs = 0
	var cfg := ConfigFile.new()
	if cfg.load(ruta) == OK:
		var d = cfg.get_value("juego", "desbloqueos", [])
		desbloqueos = d if d is Array else []
		mejor_dia = int(cfg.get_value("juego", "mejor_dia", 0))
		mejor_puntaje = int(cfg.get_value("juego", "mejor_puntaje", 0))
		dias_jugados = int(cfg.get_value("juego", "dias_jugados", 0))
		runs = int(cfg.get_value("juego", "runs", 0))


static func guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("juego", "desbloqueos", desbloqueos)
	cfg.set_value("juego", "mejor_dia", mejor_dia)
	cfg.set_value("juego", "mejor_puntaje", mejor_puntaje)
	cfg.set_value("juego", "dias_jugados", dias_jugados)
	cfg.set_value("juego", "runs", runs)
	cfg.save(ruta)


static func tiene(id: String) -> bool:
	cargar()
	return desbloqueos.has(id)


## Abre un desbloqueo. Devuelve true solo si era nuevo (para avisarlo en
## pantalla sin repetir el cartel todos los días).
static func desbloquear(id: String) -> bool:
	cargar()
	if desbloqueos.has(id):
		return false
	desbloqueos.append(id)
	guardar()
	return true


## Anota el resultado de un día. Devuelve el id desbloqueado en ese momento o "".
static func registrar_dia(ganado: bool, nivel: int, puntaje: int) -> String:
	cargar()
	dias_jugados += 1
	if ganado:
		mejor_dia = maxi(mejor_dia, nivel + 1)
		mejor_puntaje = maxi(mejor_puntaje, puntaje)
	var nuevo := ""
	# logros: la jugadora 2 se abre completando el día 2 y la cuarta carta el 3
	if ganado and nivel >= 1 and desbloquear("mujer"):
		nuevo = "mujer"
	if ganado and nivel >= 2 and desbloquear("carta_extra") and nuevo == "":
		nuevo = "carta_extra"
	guardar()
	return nuevo


## Solo para tests y para el botón de "borrar progreso".
static func reiniciar() -> void:
	desbloqueos = []
	mejor_dia = 0
	mejor_puntaje = 0
	dias_jugados = 0
	runs = 0
	_cargado = true
	var d := DirAccess.open(ruta.get_base_dir())
	if d != null and d.file_exists(ruta.get_file()):
		d.remove(ruta.get_file())
	guardar()
