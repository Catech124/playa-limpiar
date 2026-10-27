class_name Hud
extends Control
## HUD dibujado a mano. La documentación del juego es el aviso contextual que
## aparece sobre el jugador: no hay tutorial.
##
## Muestra el objetivo (3 barras de cuota con sus íconos), el reloj de la
## jornada y el aviso del día. Los íconos son PNG generados con Qwen
## (assets/ui/, ver LICENCIAS.md).

var game
var camera: Camera3D
var font: Font
var _icons := {}

const ICON_NAMES := ["pet", "vidrio", "lata", "reloj", "gaviota", "bolsa", "tiburon"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	for n in ICON_NAMES:
		var path := "res://assets/ui/%s.png" % n
		if ResourceLoader.exists(path):
			_icons[n] = load(path)


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
	_draw_clock(size)
	_draw_quota(size)
	_draw_score(size)
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


func _text_right(right: float, y: float, txt: String, size: int, color: Color) -> void:
	var w := _text_width(txt, size)
	_text(Vector2(right - w, y), txt, size, color)


func _icon(name: String, rect: Rect2) -> void:
	var tex = _icons.get(name)
	if tex != null:
		draw_texture_rect(tex, rect, false)


# ------------------------------------------------------------------ HUD
## Filo superior: avance de la jornada (de amanecer a atardecer).
func _draw_bar(size: Vector2) -> void:
	if game.sandbox:
		return
	var pct: float = game.day_progress()
	draw_rect(Rect2(0, 0, size.x, 7), Color(0, 0, 0, 0.25))
	var col := Color(1.0, 0.60, 0.28) if pct > 0.75 else Color(0.24, 0.56, 0.89)
	draw_rect(Rect2(0, 0, size.x * pct, 7), col)


func _draw_clock(size: Vector2) -> void:
	var rect := Rect2(size.x * 0.5 - 118, 18, 236, 80)
	_panel(rect, Color(0.05, 0.09, 0.13, 0.80), 14)

	var subtitle := String(game.level_name())
	_text_centered(Vector2(rect.get_center().x, rect.position.y + 20), subtitle, 12, Color(1, 1, 1, 0.62))

	_icon("reloj", Rect2(rect.position.x + 16, rect.position.y + 30, 34, 34))

	var clock := "∞" if game.sandbox else String(game.clock_text())
	var big := 30
	var w := _text_width(clock, big)
	_text(Vector2(rect.position.x + 60 + (140 - w) * 0.5, rect.position.y + 60), clock, big, Color.WHITE)

	# barra del día
	if not game.sandbox:
		var bar := Rect2(rect.position.x + 14, rect.position.y + 69, rect.size.x - 28, 5)
		draw_rect(bar, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(bar.position, Vector2(maxf(bar.size.x * game.day_progress(), 2.0), bar.size.y)),
			Color(1.0, 0.76, 0.35))


func _draw_quota(size: Vector2) -> void:
	var rect := Rect2(16, 18, 316, 152)
	_panel(rect, Color(0.05, 0.09, 0.13, 0.80), 14)
	_text(Vector2(rect.position.x + 16, rect.position.y + 24), "CUOTA DEL DÍA", 12, Color(1, 1, 1, 0.6))

	if game.sandbox:
		_text(Vector2(rect.position.x + 16, rect.position.y + 60), "CAJA DE ARENA", 20, Color.WHITE)
		_text(Vector2(rect.position.x + 16, rect.position.y + 84), "sin cuota ni reloj", 14, Color(1, 1, 1, 0.55))
		return

	var rows: Array = game.quota_rows()
	var y := rect.position.y + 60.0
	for r in rows:
		var done: bool = int(r["done"]) >= int(r["need"])
		_icon(String(r["type"]), Rect2(rect.position.x + 16, y - 21, 26, 26))
		_text(Vector2(rect.position.x + 52, y - 2), String(r["label"]), 16, Color.WHITE if not done else Color(0.72, 0.95, 0.72))
		var counter := "%d/%d" % [int(r["done"]), int(r["need"])]
		_text_right(rect.position.x + rect.size.x - 16, y - 2, counter, 16,
			Color(0.72, 0.95, 0.72) if done else Color(1, 1, 1, 0.85))

		var bar := Rect2(rect.position.x + 52, y + 5, rect.size.x - 68, 8)
		draw_rect(bar, Color(0, 0, 0, 0.38))
		var fill: float = r["ratio"]
		var col: Color = r["color"]
		if done:
			col = Color(0.42, 0.83, 0.51)
		draw_rect(Rect2(bar.position, Vector2(maxf(bar.size.x * fill, 2.0), bar.size.y)), col)
		y += 30.0


func _draw_score(size: Vector2) -> void:
	var rect := Rect2(size.x - 266, 18, 250, 80)
	_panel(rect, Color(0.05, 0.09, 0.13, 0.80), 14)
	_text(Vector2(rect.position.x + 16, rect.position.y + 24), "PUNTOS", 12, Color(1, 1, 1, 0.6))
	_text(Vector2(rect.position.x + 16, rect.position.y + 62), str(game.score), 32, Color.WHITE)

	_text_right(rect.position.x + rect.size.x - 16, rect.position.y + 24, "BASURA", 12, Color(1, 1, 1, 0.6))
	if game.sandbox:
		_text_right(rect.position.x + rect.size.x - 16, rect.position.y + 62, "libre", 22, Color(1, 1, 1, 0.7))
	else:
		_text_right(rect.position.x + rect.size.x - 16, rect.position.y + 62,
			"%d/%d" % [game.total_delivered(), game.total_quota()], 22, Color(1, 1, 1, 0.9))


func _draw_players(size: Vector2) -> void:
	var x := 22.0
	var y := size.y - 34.0
	for p in game.players:
		draw_circle(Vector2(x + 8, y), 9, p.color)
		draw_arc(Vector2(x + 8, y), 9, 0, TAU, 16, Color(0, 0, 0, 0.4), 2.0)
		_text(Vector2(x + 22, y + 6), "J%d" % (p.index + 1), 16, Color(1, 1, 1, 0.85))
		x += 58.0


func _draw_prompts(_size: Vector2) -> void:
	# aviso contextual sobre cada jugador
	for p in game.players:
		var hint: String = game.interaction_hint(p)
		if hint == "":
			continue
		var screen: Vector2 = camera.unproject_position(p.position + Vector3(0, 0.1, 0.75))
		var w := _text_width(hint, 15) + 24.0
		_panel(Rect2(screen.x - w * 0.5, screen.y + 10, w, 26), Color(0.03, 0.07, 0.10, 0.85), 13)
		_text_centered(Vector2(screen.x, screen.y + 28), hint, 15, Color.WHITE)


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
	_text_centered(Vector2(size.x * 0.5, size.y * 0.26), "PLAYA LIMPIA", 76, Color.WHITE)
	_text_centered(Vector2(size.x * 0.5, size.y * 0.31), "PROTOTIPO 3D — CUOTA DIARIA", 15, Color(1, 1, 1, 0.55))
	_text_centered(Vector2(size.x * 0.5, size.y * 0.375),
		"La playa amanece cubierta de basura. Cumplí la cuota antes del atardecer.", 20, Color(1, 1, 1, 0.85))

	var rows := [
		["WASD / flechas", "moverte"],
		["ESPACIO", "recoger · colgar la bolsa · tirar basura · entregar"],
		["SHIFT", "impulso"],
		["E", "lanzar lo que llevás"],
		["P / ESC", "pausa"],
	]
	var y := size.y * 0.48
	for r in rows:
		_text(Vector2(size.x * 0.5 - 300, y), r[0], 17, Color(1.0, 0.83, 0.47), HORIZONTAL_ALIGNMENT_RIGHT, 250)
		_text(Vector2(size.x * 0.5 + 10, y), r[1], 17, Color(1, 1, 1, 0.82))
		y += 30.0

	var y2 := y + 14.0
	_text_centered(Vector2(size.x * 0.5, y2), "1 · tomá una bolsa y colgala en el contenedor", 16, Color(1, 1, 1, 0.7))
	_text_centered(Vector2(size.x * 0.5, y2 + 24), "2 · tirá la basura adentro hasta llenarla", 16, Color(1, 1, 1, 0.7))
	_text_centered(Vector2(size.x * 0.5, y2 + 48), "3 · llevá la bolsa llena al camión", 16, Color(1, 1, 1, 0.7))

	_text_centered(Vector2(size.x * 0.5, size.y * 0.88), "ENTER — jugar solo        2 — dos jugadores", 22, Color.WHITE)
	_text_centered(Vector2(size.x * 0.5, size.y * 0.92), "D — caja de arena (debug: sin reloj ni gaviotas)", 14, Color(1, 1, 1, 0.45))


func _draw_pause(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.10, 0.62))
	_text_centered(Vector2(size.x * 0.5, size.y * 0.46), "PAUSA", 64, Color.WHITE)
	_text_centered(Vector2(size.x * 0.5, size.y * 0.54), "P o ESC para seguir · R para reiniciar", 18, Color(1, 1, 1, 0.75))


func _draw_results(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.10, 0.55))
	var rect := Rect2(size.x * 0.5 - 290, size.y * 0.5 - 235, 580, 470)
	_panel(rect, Color(0.03, 0.07, 0.10, 0.95), 18)

	var won: bool = game.won
	var title := "¡DÍA COMPLETADO!" if won else "SE ACABÓ EL DÍA"
	var color := Color(0.55, 0.92, 0.60) if won else Color(1.0, 0.66, 0.55)
	_text_centered(Vector2(size.x * 0.5, rect.position.y + 56), title, 34, color)
	_text_centered(Vector2(size.x * 0.5, rect.position.y + 84), String(game.level_name()), 15, Color(1, 1, 1, 0.6))

	# estrellas por tiempo restante
	if won:
		var earned: int = game.stars_earned()
		for i in 3:
			var c := Vector2(size.x * 0.5 - 60 + i * 60, rect.position.y + 124)
			_star(c, 20.0, Color(1.0, 0.81, 0.30) if i < earned else Color(1, 1, 1, 0.16))

	# cuota
	var y := rect.position.y + 172.0
	for r in game.quota_rows():
		var ok: bool = int(r["done"]) >= int(r["need"])
		_icon(String(r["type"]), Rect2(rect.position.x + 150, y - 20, 26, 26))
		_text(Vector2(rect.position.x + 186, y), String(r["label"]), 17, Color(1, 1, 1, 0.85))
		_text(Vector2(rect.position.x + 300, y), "%d / %d" % [int(r["done"]), int(r["need"])], 17,
			Color(0.72, 0.95, 0.72) if ok else Color(1.0, 0.72, 0.68))
		_text(Vector2(rect.position.x + 390, y), "✓" if ok else "✗", 18,
			Color(0.55, 0.90, 0.60) if ok else Color(1.0, 0.55, 0.50))
		y += 32.0

	var lines := [
		"Basura entregada: %d" % int(game.stats["delivered"]),
		"Gaviotas: %d robos" % int(game.stats["stolen"]),
		"Penalizaciones: %d" % int(game.stats["penalties"]),
	]
	y += 8.0
	for l in lines:
		_text_centered(Vector2(size.x * 0.5, y), l, 17, Color(1, 1, 1, 0.82))
		y += 28.0

	var footer := "R — repetir        ESC — menú"
	if game.sandbox:
		footer = "R — repetir        ESC — menú"
	elif won and game.level_index + 1 < game.days_total():
		footer = "ENTER — siguiente día        R — repetir        ESC — menú"
	else:
		footer = "ENTER — jugar de nuevo        R — repetir        ESC — menú"
	_text_centered(Vector2(size.x * 0.5, rect.position.y + rect.size.y - 26), footer, 18, Color.WHITE)


func _star(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + i * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.45
		points.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(points, color)
