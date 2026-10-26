class_name Levels
extends RefCounted
## Mapas como texto: se itera el layout en segundos, sin editor.
##
##   ~  agua (sólida, decorativa)      P  montón PET     (fuente)
##   #  roca (sólida)                  L  montón LATAS   (fuente)
##   1  contenedor PET   2  LATAS   3  VIDRIO
##   .  arena (caminable)              Q  montón VIDRIO  (fuente)
##   S  aparición                      T  mesa de clasificar (canal)
##   =  mostrador (guarda cosas)       B  dispensador de bolsas
##                                     W  lavadero (canal)
##                                     D  camión de entrega
##                                     R  punto de bolsas sucias
##
## Circuito pensado para ~4-5 s por residuo:
##   montón (fila 2) -> clasificar (fila 4) -> mostrador (x12) -> camión


const MAP := [
	"~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~",
	"#..P.L.Q.B....W........#",
	"#......................#",
	"#.....1.2.3............#",
	"#...........==.........#",
	"#...........==.........#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#..S......S............#",
	"#......................#",
	"##########DD####R#######",
	"~~~~~~~~~~~~~~~~~~~~~~~~",
]

const SANDBOX_SECONDS := 999.0

## Props decorativos (sin colisión) pegados a los bordes, para que la arena
## no quede vacía. Formato: [x, y, tipo]
const DECOR := [
	[2, 5, "rock"], [21, 6, "seaweed"], [2, 8, "seaweed"], [21, 9, "shell"],
	[4, 11, "shell"], [19, 11, "rock"], [6, 7, "starfish"], [17, 7, "starfish"],
	[3, 6, "shell"], [20, 4, "rock"],
]
