class_name GameConfig
extends RefCounted
## Todos los números del juego en un solo lugar.
## Regla del prototipo: si se puede "sentir" jugando, vive acá.


const TILE := 1.0

# --- ronda ---------------------------------------------------------------
const ROUND_SECONDS := 180.0

# --- movimiento ----------------------------------------------------------
const PLAYER_SPEED := 4.6          # celdas/s
const PLAYER_RADIUS := 0.30
const PLAYER_HEIGHT := 1.0
const DASH_SPEED := 9.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 1.0

# --- canales de trabajo --------------------------------------------------
const CLASSIFY_TIME := 1.2
const WASH_TIME := 1.5

# --- bolsas (el "plato" de Overcooked) -----------------------------------
const BAG_CAPACITY := 4
const BAG_STOCK := 5               # bolsas en circulación: recurso FINITO

# --- lanzamiento ---------------------------------------------------------
const THROW_RANGE := 3.4
const THROW_TIME := 0.42

# --- pedidos -------------------------------------------------------------
const ORDER_FIRST_DELAY := 2.0
const ORDER_INTERVAL := 15.0
const ORDER_MAX_ACTIVE := 3
const ORDER_PATIENCE := 40.0
const ORDER_MIN_ITEMS := 1
const ORDER_MAX_ITEMS := 3
const ORDER_MAX_TYPES := 2

# --- puntuación ----------------------------------------------------------
const SCORE_BASE := 30
const SCORE_SPEED_BONUS := 30
const SCORE_EXPIRED_PENALTY := 15

# --- gaviotas ------------------------------------------------------------
const GULL_FIRST_DELAY := 24.0
const GULL_INTERVAL := 22.0
const GULL_SPEED := 3.2

# --- estrellas por nivel -------------------------------------------------
const STARS := [160, 320, 480]

# --- residuos ------------------------------------------------------------
const RESIDUES := {
	"pet": {"label": "PET", "name": "Botella", "color": Color(0.29, 0.72, 0.94)},
	"lata": {"label": "LATA", "name": "Lata", "color": Color(0.87, 0.88, 0.91)},
	"vidrio": {"label": "VIDRIO", "name": "Vidrio", "color": Color(0.39, 0.79, 0.48)},
}

# --- estaciones ----------------------------------------------------------
const STATION_HEIGHT := {
	"counter": 0.80,
	"pile": 0.55,
	"sort": 0.75,
	"bags": 0.80,
	"wash": 0.70,
	"delivery": 0.95,
	"return": 0.60,
}

const STATION_COLOR := {
	"counter": Color(0.76, 0.56, 0.34),
	"pile": Color(0.45, 0.51, 0.33),
	"sort": Color(0.16, 0.55, 0.50),
	"bags": Color(0.24, 0.42, 0.70),
	"wash": Color(0.16, 0.60, 0.71),
	"delivery": Color(0.28, 0.31, 0.36),
	"return": Color(0.47, 0.35, 0.24),
}

const STATION_LABEL := {
	"counter": "",
	"pile": "BASURA",
	"sort": "CLASIF",
	"bags": "BOLSAS",
	"wash": "LAVAR",
	"delivery": "ENTREGA",
	"return": "SUCIAS",
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
