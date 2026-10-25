class_name Hud
extends Control
## HUD dibujado a mano. La documentación del juego es el aviso contextual que
## aparece sobre el jugador: no hay tutorial.

var game
var camera: Camera3D
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var size := get_viewport_rect().size
	if game.is_menu():
		_draw_menu(size)
		return

	_draw_bar(size)
	_draw_score(size)
	_draw_orders(size)
	_draw_players(size)
	_draw_prompts(size)
	_draw_toasts()

	if game.is_paused():
		_draw_pause(size)
	if game.is_results():
		_draw_results(size)


# ------------------------------------------------------------------ helpers
func _panel(rect: Rect2, color: Color, radius := 10) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.12)
	draw_style_box(sb, rect)


func _text(pos: Vector2, txt: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if font == null:
		return
	draw_string(font, pos, txt, align, width, size, color)


func _text_width(txt: String, size: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _text_centered(center: Vector2, txt: String, size: int, color: Color) -> void:
	var w := _text_width(txt, size)
	_text(Vector2(center.x - w * 0.5, center.y), txt, size, color)


# ------------------------------------------------------------------ HUD
func _draw_bar(size: Vector2) -> void:
	var pct: float = clampf(game.time_left / game.level_seconds, 0.0, 1.0)
	draw_rect(Rect2(0, 0, size.x, 7), Color(0, 0, 0, 0.25))
	var col := Color(0.88, 0.35, 0.24) if pct < 0.2 else Color(0.24, 0.56, 0.89)
	draw_rect(Rect2(0, 0, size.x * pct, 7), col)


func _draw_score(size: Vector2) -> void:
	_panel(Rect2(16, 20, 250, 78), Color(0.05, 0.09, 0.13, 0.78), 12)
	_text(Vector2(32, 44), "PUNTOS", 13, Color(1, 1, 1, 0.6))
	_text(Vector2(32, 80), str(game.score), 34, Color.WHITE)

	var left: float = maxf(game.time_left, 0.0)
	var mm := int(left) / 60
	var ss := int(left) % 60
	_text(Vector2(178, 44), "TIEMPO", 13, Color(1, 1, 1, 0.6))
	var urgent := left < 20.0
	_text(Vector2(178, 80), "%d:%02d" % [mm, ss], 34, Color(1.0, 0.68, 0.6) if urgent else Color.WHITE)


func _draw_orders(size: Vector2) -> void:
	var card_w := 196.0
	var card_h := 92.0
	var gap := 10.0
	var list: Array = game.orders.list
	var start_x := size.x - 16.0 - list.size() * (card_w + gap) + gap

	for i in list.size():
		var o = list[i]
		var x := start_x + i * (card_w + gap)
		var rect := Rect2(x, 20, card_w, card_h)
		var ratio: float = clampf(o.patience / o.patience_max, 0.0, 1.0)
		var urgent := ratio < 0.3
		_panel(rect, Color(0.42, 0.11, 0.09, 0.9) if urgent else Color(0.05, 0.09, 0.13, 0.82), 12)

		var ix := x + 26.0
		for type in o.need.keys():
			var color: Color = GameConfig.RESIDUES[type]["color"]
			draw_circle(Vector2(ix, 62), 13, color)
			draw_arc(Vector2(ix, 62), 13, 0, TAU, 20, Color(0, 0, 0, 0.35), 2.0)
			_text(Vector2(ix + 19, 68), "x%d" % int(o.need[type]), 20, Color.WHITE)
			ix += 82.0

		var bar := Rect2(x + 14, 20 + card_h - 22, card_w - 28, 9)
		draw_rect(bar, Color(0, 0, 0, 0.35))
		var bar_color := Color(1.0, 0.42, 0.29) if urgent else (Color(0.95, 0.76, 0.31) if ratio < 0.6 else Color(0.37, 0.83, 0.54))
		draw_rect(Rect2(bar.position, Vector2(maxf(bar.size.x * ratio, 3.0), bar.size.y)), bar_color)


func _draw_players(size: Vector2) -> void:
	var x := 22.0
	var y := size.y - 34.0
	for p in game.players:
		draw_circle(Vector2(x + 8, y), 9, p.color)
		draw_arc(Vector2(x + 8, y), 9, 0, TAU, 16, Color(0, 0, 0, 0.4), 2.0)
		_text(Vector2(x + 22, y + 6), "J%d" % (p.index + 1), 16, Color(1, 1, 1, 0.85))
		x += 58.0


func _draw_prompts(_size: Vector2) -> void:
	for p in game.players:
		if p.carrying != null and p.carrying.progress > 0.0:
			_draw_progress(p)

	# aviso contextual del jugador 1 (y del 2 si hay co-op)
	for p in game.players:
		var hint: String = game.interaction_hint(p)
		if hint == "":
			continue
		var screen: Vector2 = camera.unproject_position(p.position + Vector3(0, 0.1, 0.75))
		var w := _text_width(hint, 15) + 24.0
		_panel(Rect2(screen.x - w * 0.5, screen.y + 10, w, 26), Color(0.03, 0.07, 0.10, 0.85), 13)
		_text_centered(Vector2(screen.x, screen.y + 28), hint, 15, Color.WHITE)


func _draw_progress(p) -> void:
	var item: CarryItem = p.carrying
	var center: Vector2 = camera.unproject_position(p.position + Vector3(0, 2.25, 0))
	draw_circle(center, 17, Color(0, 0, 0, 0.35))
	draw_arc(center, 17, -PI * 0.5, -PI * 0.5 + TAU * item.progress, 28, Color.WHITE, 5.0)


func _draw_toasts() -> void:
	for t in game.toasts:
		if camera.is_position_behind(t["pos"]):
			continue
		var screen: Vector2 = camera.unproject_position(t["pos"])
		var alpha: float = clampf(t["ttl"] * 2.0, 0.0, 1.0)
		var col: Color = Color(0.71, 0.95, 0.69) if t["kind"] == "good" else (Color(1.0, 0.70, 0.70) if t["kind"] == "bad" else Color.WHITE)
		col.a = alpha
		_text_centered(Vector2(screen.x, screen.y - t["rise"]), t["text"], 17, col)


# ------------------------------------------------------------------ pantallas
func _draw_menu(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.09, 0.13, 0.86))
	_text_centered(Vector2(size.x * 0.5, size.y * 0.30), "PLAYA LIMPIA", 76, Color.WHITE)
	_text_centered(Vector2(size.x * 0.5, size.y * 0.35), "PROTOTIPO 3D — MECÁNICAS", 15, Color(1, 1, 1, 0.55))
	_text_centered(Vector2(size.x * 0.5, size.y * 0.42), "Recogé, clasificá y entregá antes de que se llene la playa.", 20, Color(1, 1, 1, 0.85))

	var rows := [
		["WASD / flechas", "moverte"],
		["ESPACIO", "acción · mantener para clasificar o lavar"],
		["SHIFT", "impulso"],
		["E", "lanzar lo que llevás"],
		["P / ESC", "pausa"],
	]
	var y := size.y * 0.52
	for r in rows:
		var label: String = r[0]
		_text(Vector2(size.x * 0.5 - 260, y), label, 17, Color(1.0, 0.83, 0.47), HORIZONTAL_ALIGNMENT_RIGHT, 220)
		_text(Vector2(size.x * 0.5 + 10, y), r[1], 17, Color(1, 1, 1, 0.82))
		y += 30.0

	_text_centered(Vector2(size.x * 0.5, size.y * 0.86), "ENTER — jugar solo        2 — dos jugadores", 22, Color.WHITE)
	_text_centered(Vector2(size.x * 0.5, size.y * 0.90), "D — caja de arena (debug: sin reloj ni gaviotas)", 14, Color(1, 1, 1, 0.45))


func _draw_pause(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.10, 0.62))
	_text_centered(Vector2(size.x * 0.5, size.y * 0.46), "PAUSA", 64, Color.WHITE)
	_text_centered(Vector2(size.x * 0.5, size.y * 0.54), "P o ESC para seguir · R para reiniciar", 18, Color(1, 1, 1, 0.75))


func _draw_results(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.10, 0.55))
	var rect := Rect2(size.x * 0.5 - 260, size.y * 0.5 - 210, 520, 420)
	_panel(rect, Color(0.03, 0.07, 0.10, 0.94), 18)

	_text_centered(Vector2(size.x * 0.5, rect.position.y + 52), "FIN DE LA JORNADA", 16, Color(1, 1, 1, 0.6))
	_text_centered(Vector2(size.x * 0.5, rect.position.y + 118), "%d pts" % game.score, 60, Color.WHITE)

	var earned: int = game.stars_earned()
	for i in 3:
		var c := Vector2(size.x * 0.5 - 60 + i * 60, rect.position.y + 176)
		_star(c, 22.0, Color(1.0, 0.81, 0.30) if i < earned else Color(1, 1, 1, 0.16))

	var lines := [
		"Entregados: %d" % game.stats["served"],
		"Pedidos perdidos: %d" % game.stats["expired"],
		"Lanzamientos: %d" % game.stats["thrown"],
	]
	var y := rect.position.y + 236
	for l in lines:
		_text_centered(Vector2(size.x * 0.5, y), l, 19, Color(1, 1, 1, 0.85))
		y += 30.0

	_text_centered(Vector2(size.x * 0.5, rect.position.y + 350), "R — repetir        ESC — menú", 20, Color.WHITE)


func _star(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + i * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.45
		points.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(points, color)
