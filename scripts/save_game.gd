class_name SaveGame
extends RefCounted
## Progreso permanente en disco: conchas, desbloqueos y récords.
##
## `ruta` es estática y configurable para que los tests usen un archivo temporal
## y no toquen la partida real.

const RUTA := "user://playa_save.cfg"
const CONCHAS_INICIALES := 6

static var ruta := RUTA
static var conchas := CONCHAS_INICIALES
static var desbloqueos: Array = []
static var mejor_dia := 0
static var mejor_puntaje := 0
static var runs := 0
static var _cargado := false


static func cargar(forzar := false) -> void:
	if _cargado and not forzar:
		return
	_cargado = true
	conchas = CONCHAS_INICIALES
	desbloqueos = []
	mejor_dia = 0
	mejor_puntaje = 0
	runs = 0
	var cfg := ConfigFile.new()
	if cfg.load(ruta) == OK:
		conchas = int(cfg.get_value("juego", "conchas", CONCHAS_INICIALES))
		desbloqueos = cfg.get_value("juego", "desbloqueos", [])
		if not (desbloqueos is Array):
			desbloqueos = []
		mejor_dia = int(cfg.get_value("juego", "mejor_dia", 0))
		mejor_puntaje = int(cfg.get_value("juego", "mejor_puntaje", 0))
		runs = int(cfg.get_value("juego", "runs", 0))


static func guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("juego", "conchas", conchas)
	cfg.set_value("juego", "desbloqueos", desbloqueos)
	cfg.set_value("juego", "mejor_dia", mejor_dia)
	cfg.set_value("juego", "mejor_puntaje", mejor_puntaje)
	cfg.set_value("juego", "runs", runs)
	cfg.save(ruta)


static func tiene(id: String) -> bool:
	cargar()
	return desbloqueos.has(id)


## Intenta comprar. Devuelve true solo si no lo tenía y alcanzaba la plata.
static func comprar(id: String, precio: int) -> bool:
	cargar()
	if desbloqueos.has(id) or conchas < precio:
		return false
	conchas -= precio
	desbloqueos.append(id)
	guardar()
	return true


static func sumar_conchas(n: int) -> void:
	cargar()
	conchas = maxi(0, conchas + n)
	guardar()


## Solo para tests y para el botón de "borrar progreso".
static func reiniciar() -> void:
	conchas = CONCHAS_INICIALES
	desbloqueos = []
	mejor_dia = 0
	mejor_puntaje = 0
	runs = 0
	_cargado = true
	var d := DirAccess.open(ruta.get_base_dir())
	if d != null and d.file_exists(ruta.get_file()):
		d.remove(ruta.get_file())
	guardar()
