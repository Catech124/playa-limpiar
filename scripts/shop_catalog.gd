class_name ShopCatalog
extends RefCounted
## Catálogo de la tienda de conchas (mejoras permanentes entre runs).
##
## Las cartas de la run (fase 3) son otra cosa: esto se compra una vez y queda
## para siempre en el save.

const ITEMS := [
	{
		"id": "mujer",
		"nombre": "JUGADORA 2",
		"desc": "SEGUNDO PERSONAJE JUGABLE",
		"precio": 15,
		"icono": "retrato-j2",
	},
	{
		"id": "carta_extra",
		"nombre": "CUARTA CARTA",
		"desc": "UNA MEJORA MAS POR DIA",
		"precio": 10,
	},
	{
		"id": "carta_inicial",
		"nombre": "MEJORA INICIAL",
		"desc": "EMPEZAS LA RUN CON UNA CARTA",
		"precio": 25,
	},
	{
		"id": "pool_raro",
		"nombre": "POOL RARO",
		"desc": "APARECEN CARTAS RARAS",
		"precio": 40,
	},
	{
		"id": "dificultad",
		"nombre": "DIFICULTAD +",
		"desc": "MAS CUOTA Y MAS CONCHAS",
		"precio": 50,
	},
]


static func item(id: String) -> Dictionary:
	for it in ITEMS:
		if String(it["id"]) == id:
			return it
	return {}
