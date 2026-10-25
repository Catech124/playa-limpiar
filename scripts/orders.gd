class_name OrderBook
extends RefCounted
## Pedidos: el motor de presión. Dicen QUÉ entregar, corren un reloj que
## convierte "hacerlo bien" en "hacerlo rápido", y la cola castiga no priorizar.

class Order:
	var id := 0
	var need: Dictionary = {}       # type -> count
	var items := 0
	var patience := 0.0
	var patience_max := 0.0
	var signature := ""

var list: Array = []
var next_id := 1
var timer := 0.0
var pool: Array = ["pet", "lata", "vidrio"]


func _init() -> void:
	timer = GameConfig.ORDER_FIRST_DELAY


func spawn() -> Order:
	var type_count := 1 + randi() % GameConfig.ORDER_MAX_TYPES
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	var types: Array = shuffled.slice(0, mini(type_count, pool.size()))
	var total := GameConfig.ORDER_MIN_ITEMS + randi() % (GameConfig.ORDER_MAX_ITEMS - GameConfig.ORDER_MIN_ITEMS + 1)

	var need := {}
	for t in types:
		need[t] = 1
	var extra := total - types.size()
	for i in maxi(extra, 0):
		var t: String = types[randi() % types.size()]
		need[t] = int(need[t]) + 1

	var o := Order.new()
	o.id = next_id
	next_id += 1
	o.need = need
	o.patience_max = GameConfig.ORDER_PATIENCE
	o.patience = GameConfig.ORDER_PATIENCE
	o.items = total

	var parts: Array = []
	for t in need.keys():
		for i in int(need[t]):
			parts.append(t)
	parts.sort()
	o.signature = "+".join(parts)

	list.append(o)
	return o


## Devuelve los pedidos que expiraron en este tick.
func tick(delta: float) -> Array:
	timer -= delta
	if timer <= 0.0:
		if list.size() < GameConfig.ORDER_MAX_ACTIVE:
			spawn()
			timer = GameConfig.ORDER_INTERVAL
		else:
			timer = 2.0

	var expired: Array = []
	for i in range(list.size() - 1, -1, -1):
		var o: Order = list[i]
		o.patience -= delta
		if o.patience <= 0.0:
			expired.append(o)
			list.remove_at(i)
	return expired


func match_contents(contents: Array) -> Order:
	var c := contents.duplicate()
	c.sort()
	var sig := "+".join(c)
	for o in list:
		if o.signature == sig:
			return o
	return null


func consume(order: Order) -> void:
	var idx := list.find(order)
	if idx >= 0:
		list.remove_at(idx)
