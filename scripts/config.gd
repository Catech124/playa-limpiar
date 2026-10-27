class_name GameConfig
extends RefCounted
## Todos los números del juego en un solo lugar.
## Regla del prototipo: si se puede "sentir" jugando, vive acá.

const TILE := 1.0

# --- jornada -------------------------------------------------------------
## El reloj de 24 h comprimido: el día va de las 06:00 a las 22:00.
const DAY_START_MINUTES := 6.0 * 60.0
const DAY_MINUTES := 16.0 * 60.0

# --- movimiento ----------------------------------------------------------
const PLAYER_SPEED := 4.6          # celdas/s
const PLAYER_RADIUS := 0.30
const PLAYER_HEIGHT := 1.0
const DASH_SPEED := 9.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 1.0

# --- bolsas --------------------------------------------------------------
## La bolsa entra en la boca del contenedor y allí se llena. Al entregarla
## en el camión se va con la basura (el dispensador da bolsas infinitas).
const BAG_CAPACITY := 4

# --- lanzamiento ---------------------------------------------------------
const THROW_RANGE := 3.4
const THROW_TIME := 0.42

# --- puntuación ----------------------------------------------------------
const POINTS_PER_BIN := 1          # basura metida en la bolsa del contenedor
const POINTS_PER_ITEM := 10        # basura entregada en el camión
const PENALTY := 2                 # castigo (contenedor equivocado, etc.)

# --- gaviotas ------------------------------------------------------------
## Depende de cuántos jugadores hay: con uno solo no alcanzan las manos para
## embolsar y cubrir la playa a la vez, así que la gaviota aparece mucho menos.
## Con dos, uno embolsa cerca del contenedor y el otro barre la arena.
const GULL_FIRST_DELAY := {1: 55.0, 2: 30.0}
const GULL_INTERVAL := {1: 50.0, 2: 34.0}
const GULL_SPEED := 3.2

# --- residuos ------------------------------------------------------------
## `order` fija el orden de las barras de cuota en el HUD.
const RESIDUE_ORDER := ["pet", "vidrio", "lata"]
const RESIDUES := {
	"pet": {
		"label": "PET",
		"name": "Botella PET",
		"color": Color(0.29, 0.72, 0.94),
		"accent": Color(0.96, 0.97, 0.98),      # etiqueta blanca
		"icon": "pet.png",
	},
	"vidrio": {
		"label": "VIDRIO",
		"name": "Botella de vidrio",
		"color": Color(0.31, 0.70, 0.44),
		"accent": Color(0.94, 0.91, 0.79),      # etiqueta crema
		"icon": "vidrio.png",
	},
	"lata": {
		"label": "LATAS",
		"name": "Lata",
		"color": Color(0.87, 0.88, 0.91),
		"accent": Color(0.82, 0.26, 0.22),      # banda de la bebida
		"icon": "lata.png",
	},
}

# --- estaciones ----------------------------------------------------------
const STATION_HEIGHT := {
	"bags": 0.80,
	"bin": 0.78,
	"delivery": 0.95,
}

const STATION_COLOR := {
	"bags": Color(0.24, 0.42, 0.70),
	"bin": Color(0.20, 0.52, 0.36),
	"delivery": Color(0.28, 0.31, 0.36),
}

const STATION_LABEL := {
	"bags": "BOLSAS",
	"bin": "CONTENEDOR",
	"delivery": "ENTREGA",
}

# contenedores de reciclaje: uno por tipo, como en la vida real
const BIN_LABEL := {
	"pet": "PET",
	"lata": "LATAS",
	"vidrio": "VIDRIO",
}
const BIN_COLOR := {
	"pet": Color(0.22, 0.58, 0.34),
	"lata": Color(0.62, 0.64, 0.68),
	"vidrio": Color(0.20, 0.46, 0.72),
}

# --- controles -----------------------------------------------------------
# physical_keycode de Godot (teclas físicas: funciona igual en cualquier layout)
const KEYMAPS := [
	{
		"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"action": KEY_SPACE, "dash": KEY_SHIFT, "throw": KEY_E,
	},
	{
		"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"action": KEY_ENTER, "dash": KEY_CTRL, "throw": KEY_PERIOD,
	},
]

const PLAYER_COLORS := [
	Color(0.95, 0.71, 0.27),
	Color(0.47, 0.78, 0.91),
]
