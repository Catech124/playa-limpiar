class_name Levels
extends RefCounted
## Datos de los niveles: mapa en texto + ritmo de la jornada.
##
##   ~  mar (por ahora sólido; en la Fase 3 se entra a la orilla)
##   #  roca / muro del paseo
##   1  contenedor PET   2  LATAS   3  VIDRIO   (boca para colgar la bolsa)
##   B  dispensador de bolsas          D  camión (entrega de la cuota)
##   .  arena (caminable)   S  aparición de jugadores
##
## Circuito: RECOGER (arena) -> EMBOLSAR (contenedor) -> ENTREGAR (camión).
## La basura ya no sale de montones: aparece tirada por la playa.

const MAP := [
	"########################",
	"#..B...1.2.3.......DD..#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#..S......S............#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~",
]

## Jornadas. `spawn_rows` limita la franja de arena donde cae la basura:
## cuanto más abajo (lejos del paseo), más carrera para el jugador.
const LEVELS := [
	{
		"name": "Día 1 · La orilla",
		"seconds": 180.0,
		"quota": {"pet": 6, "vidrio": 4, "lata": 4},
		"spawn_initial": 3,
		"spawn_interval": 3.6,
		"spawn_max": 6,
		"spawn_rows": [3, 10],
		"spawn_water": 0.0,
		"npcs": 1,
	},
	{
		"name": "Día 2 · Marea alta",
		"seconds": 240.0,
		"quota": {"pet": 9, "vidrio": 6, "lata": 6},
		"spawn_initial": 3,
		"spawn_interval": 3.0,
		"spawn_max": 7,
		"spawn_rows": [4, 10],
		"spawn_water": 0.15,
		"npcs": 2,
	},
	{
		"name": "Día 3 · Último día",
		"seconds": 300.0,
		"quota": {"pet": 12, "vidrio": 8, "lata": 8},
		"spawn_initial": 4,
		"spawn_interval": 2.4,
		"spawn_max": 8,
		"spawn_rows": [5, 10],
		"spawn_water": 0.25,
		"npcs": 3,
	},
]

## Caja de arena: sin reloj, sin gaviotas y sin cuota (para probar mecánicas).
const SANDBOX := {
	"name": "Caja de arena",
	"seconds": 999.0,
	"quota": {},
	"spawn_initial": 5,
	"spawn_interval": 4.0,
	"spawn_max": 8,
	"spawn_rows": [2, 10],
	"spawn_water": 0.0,
	"npcs": 2,
}

## Props decorativos. Los grandes (palmera, torre, muelle) reservan la celda:
## la basura no aparece encima de ellos. Formato: [x, y, tipo]
const DECOR := [
	# palmeras en los rincones de la arena
	[2, 2, "palm"], [21, 2, "palm"], [2, 7, "palm"], [21, 9, "palm"],
	# sombrillas con reposera al lado (el toldo da sombra a la basura)
	[6, 4, "umbrella"], [16, 5, "umbrella"], [11, 8, "umbrella"],
	# reposeras en fila, paralelas a la orilla como en un balneario
	[7, 4, "lounger", 0.0], [15, 5, "lounger", 0.0], [12, 8, "lounger", 0.0],
	# torre del guardavidas, mirando al mar
	[3, 10, "tower"],
	# muelle de tablas que entra al agua
	[15, 12, "pier"],
	# detalles chicos: no reservan la celda
	[2, 9, "rock"], [21, 6, "rock"], [5, 8, "seaweed"], [17, 8, "shell"],
	[8, 10, "shell"], [14, 10, "starfish"], [3, 4, "starfish"], [20, 4, "seaweed"],
	[6, 5, "shell"], [12, 2, "shell"], [17, 2, "seaweed"],
]
