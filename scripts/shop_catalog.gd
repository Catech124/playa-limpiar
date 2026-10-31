class_name ShopCatalog
extends RefCounted
## Dos catálogos distintos, como en Balatro:
##
##   DESBLOQUEOS → se abren jugando (logros). Se MIRAN en la Colección, no se
##                 compran: fuera de la run no hay tienda.
##   CARTAS      → se compran con la plata que juntás DENTRO de la run, entre
##                 día y día. Son las mejoras que se apilan hasta el final.

const DESBLOQUEOS := [
	{
		"id": "mujer",
		"nombre": "JUGADORA 2",
		"desc": "SEGUNDO PERSONAJE JUGABLE",
		"condicion": "COMPLETA EL DIA 2",
		"icono": "retrato-j2",
	},
	{
		"id": "carta_extra",
		"nombre": "CUARTA CARTA",
		"desc": "UNA MEJORA MAS EN LA TIENDA",
		"condicion": "COMPLETA EL DIA 3",
	},
	{
		"id": "carta_inicial",
		"nombre": "MEJORA INICIAL",
		"desc": "EMPIEZAS LA RUN CON UNA CARTA",
		"condicion": "GANÁ UNA RUN DE 7 DIAS",
	},
	{
		"id": "pool_raro",
		"nombre": "POOL RARO",
		"desc": "APARECEN CARTAS RARAS",
		"condicion": "TERMINA 3 RUNS",
	},
	{
		"id": "dificultad",
		"nombre": "DIFICULTAD +",
		"desc": "MAS CUOTA Y MEJORES CARTAS",
		"condicion": "COMPLETA 10 DIAS",
	},
]

## Cartas de la run. `precio` se paga con la plata del día (no con conchas).
const CARTAS := [
	{
		"id": "sandalias",
		"nombre": "SANDALIAS DE GOMA",
		"desc": "+12% DE VELOCIDAD",
		"precio": 4,
		"rareza": "comun",
	},
	{
		"id": "guantes",
		"nombre": "GUANTES DE TRABAJO",
		"desc": "LA BOLSA ENTRA UNO MAS",
		"precio": 5,
		"rareza": "comun",
	},
	{
		"id": "carrito",
		"nombre": "CARRITO",
		"desc": "LLEVAS DOS RESIDUOS A LA VEZ",
		"precio": 7,
		"rareza": "rara",
	},
	{
		"id": "repelente",
		"nombre": "REPELENTE",
		"desc": "EL TIBURON TARDA 40% MAS",
		"precio": 4,
		"rareza": "comun",
	},
	{
		"id": "comederos",
		"nombre": "COMEDEROS",
		"desc": "LAS GAVIOTAS SE VAN SOLAS",
		"precio": 6,
		"rareza": "rara",
	},
	{
		"id": "reciclador",
		"nombre": "RECICLADOR EXPERTO",
		"desc": "+50% DE PUNTOS",
		"precio": 6,
		"rareza": "rara",
	},
	{
		"id": "reloj",
		"nombre": "RELOJ DE ARENA",
		"desc": "+15 SEGUNDOS POR DIA",
		"precio": 5,
		"rareza": "comun",
	},
	{
		"id": "sombra",
		"nombre": "SOMBRA EXTRA",
		"desc": "LA BASURA DEL SOL AGUANTA MAS",
		"precio": 3,
		"rareza": "comun",
	},
	{
		"id": "marea_negra",
		"nombre": "MAREA NEGRA",
		"desc": "CUOTA -15% PERO UNA GAVIOTA MAS",
		"precio": 2,
		"rareza": "maldita",
	},
]


static func desbloqueo(id: String) -> Dictionary:
	for it in DESBLOQUEOS:
		if String(it["id"]) == id:
			return it
	return {}


static func carta(id: String) -> Dictionary:
	for it in CARTAS:
		if String(it["id"]) == id:
			return it
	return {}
