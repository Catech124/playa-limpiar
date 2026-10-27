class_name TrashSpawner
extends RefCounted
## Tira basura en la playa. Es la fuente visible del bucle: la basura aparece
## tirada en la arena (y más adelante también en el agua), no de un montón.
##
## Elige el TIPO pesando por lo que falta de la cuota: así el nivel nunca se
## vuelve imposible por azar (si faltan PET, salen más PET).

var game
var world: GridWorld
var timer := 0.0
var interval := 3.6
var max_on_ground := 6
var rows := Vector2i(3, 10)
var water_chance := 0.0        # basura flotante en la primera fila de agua
var enabled := true


func _init(g, w: GridWorld) -> void:
	game = g
	world = w


func setup(cfg: Dictionary) -> void:
	interval = float(cfg.get("spawn_interval", 3.6))
	max_on_ground = int(cfg.get("spawn_max", 6))
	var band: Array = cfg.get("spawn_rows", [3, 10])
	rows = Vector2i(int(band[0]), int(band[1]))
	water_chance = float(cfg.get("spawn_water", 0.0))
	timer = interval
	for i in int(cfg.get("spawn_initial", 0)):
		spawn_one()


func tick(delta: float) -> void:
	if not enabled or not game.is_playing():
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = interval
	if count_on_ground() < max_on_ground:
		spawn_one()


## Basura que está tirada en la arena (no la que llevan los jugadores ni las bolsas).
func count_on_ground() -> int:
	var n := 0
	for row in world.tiles:
		for t in row:
			if t.item != null and t.item.is_residue():
				n += 1
	return n


func spawn_one(force_type := "") -> CarryItem:
	# una parte de la basura cae al agua: se ve la orilla trabajar y hay una
	# razón para correr (se hunde a los segundos)
	var from_water := force_type == "" and water_chance > 0.0 and randf() < water_chance
	var tile: CellData = pick_water_tile() if from_water else null
	if tile == null:
		from_water = false
		tile = pick_tile()
	if tile == null:
		return null

	var t := force_type
	if t == "":
		t = pick_type()

	var item := CarryItem.residue(t, "water" if from_water else "beach")
	ItemVisuals.build(item)
	game.move_item_to_tile(item, tile)
	# cae desde un poco más arriba y se acuesta sola: la basura no aparece
	# plantada como una vela
	game.drop_from_above(item)
	game.stats["spawned"] = int(game.stats.get("spawned", 0)) + 1
	return item


## Arena libre y sin jugador encima. `rows` acota la franja (lejos del paseo =
## más carrera). El agua queda para la Fase 3.
func pick_tile() -> CellData:
	var candidates: Array = []
	for y in range(rows.x, rows.y + 1):
		for x in range(1, world.w - 1):
			var t := world.tile_at(x, y)
			if t == null or not t.can_hold() or t.item != null:
				continue
			if _player_on(t):
				continue
			candidates.append(t)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


## Basura flotante: solo la PRIMERA fila de agua, que se alcanza desde la orilla
## (el agua todavía no se camina; eso es la Fase 3).
func pick_water_tile() -> CellData:
	var row_y := -1
	for y in world.h:
		for x in world.w:
			var t := world.tile_at(x, y)
			if t != null and t.kind == "water":
				row_y = y
				break
		if row_y >= 0:
			break
	if row_y < 0:
		return null

	var options: Array = []
	for x in range(1, world.w - 1):
		var t := world.tile_at(x, row_y)
		if t != null and t.kind == "water" and t.item == null and not _player_on(t):
			options.append(t)
	if options.is_empty():
		return null
	return options[randi() % options.size()]


func _player_on(t: CellData) -> bool:
	for p in game.players:
		if p.tile_x() == t.x and p.tile_y() == t.y:
			return true
	return false


## Peso por tipo = lo que falta para la cuota (mínimo 1). Sin cuota (caja de
## arena) el reparto es uniforme.
func pick_type() -> String:
	var types: Array = GameConfig.RESIDUE_ORDER
	var total := 0.0
	var weights := {}
	for t in types:
		var need := 1
		if game.quota.has(t):
			need = maxi(1, int(game.quota[t]) - int(game.delivered.get(t, 0)))
		weights[t] = need
		total += float(need)

	var r := randf() * total
	for t in types:
		r -= float(weights[t])
		if r <= 0.0:
			return t
	return types[0]
