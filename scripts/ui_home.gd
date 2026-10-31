class_name UiHome
extends Control
## Pantalla de inicio y tienda, dibujadas pixel a pixel (sin texturas de UI).
##
## La lógica de teclas vive en `main.gd`; acá solo hay estado de selección,
## dibujo y avisos. La tienda gasta conchas del save (SaveGame).

const ANCHO_BASE := 1280.0
const ALTO_BASE := 800.0

var modo := "menu"            # menu | tienda
var sel := 0                  # 0 = jugador 1, 1 = jugador 2
var cursor := 0               # fila de la tienda
var aviso := ""
var aviso_t := 0.0
var t := 0.0

var _tex := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for n in ["retrato-j1", "retrato-j2"]:
		var p := "res://assets/ui/%s.png" % n
		if ResourceLoader.exists(p):
			_tex[n] = load(p)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	if aviso_t > 0.0:
		aviso_t = maxf(0.0, aviso_t - delta)
	queue_redraw()


func abrir_menu() -> void:
	modo = "menu"
	visible = true


func abrir_tienda() -> void:
	modo = "tienda"
	cursor = 0
	visible = true


func cerrar_tienda() -> void:
	modo = "menu"


func avisar(txt: String) -> void:
	aviso = txt
	aviso_t = 2.4


func mover(dir: int) -> void:
	if modo == "menu":
		sel = clampi(sel + dir, 0, 1)
	else:
		cursor = clampi(cursor + dir, 0, ShopCatalog.ITEMS.size() - 1)


# ------------------------------------------------------------------ dibujo
func _draw() -> void:
	var size := get_viewport_rect().size
	var k := minf(size.x / ANCHO_BASE, size.y / ALTO_BASE)
	_fondo(size, k)
	if modo == "menu":
		_menu(size, k)
	else:
		_tienda(size, k)
	_aviso(size, k)


func _u(x: float, y: float, k: float) -> Vector2:
	return Vector2(x * k, y * k)


func _esc(v: float, k: float) -> int:
	return maxi(1, int(round(v * k)))


## Cielo en bandas, sol de bloques, mar con olas y arena con granitos.
func _fondo(size: Vector2, k: float) -> void:
	var cielo := [Pixel.PALETA["cielo_1"], Pixel.PALETA["cielo_1"].lightened(0.10),
		Pixel.PALETA["cielo_2"], Pixel.PALETA["cielo_2"].lightened(0.10),
		Pixel.PALETA["cielo_3"]]
	var banda := size.y * 0.47 / float(cielo.size())
	for i in cielo.size():
		draw_rect(Rect2(0, banda * i, size.x, banda + 1.0), cielo[i])

	# sol: cuadros de 1/14 del ancho formando un círculo duro
	var cx := size.x * 0.79
	var cy := size.y * 0.15
	var cubo := maxf(4.0, size.y / 110.0)
	for gy in range(-6, 7):
		for gx in range(-6, 7):
			var d := Vector2(gx, gy).length()
			if d <= 6.2:
				var c: Color = Pixel.PALETA["sol"]
				if d > 4.6:
					c = c.darkened(0.10)
				draw_rect(Rect2(cx + gx * cubo, cy + gy * cubo, cubo, cubo), c)

	# ciudad lejana: bloques oscuros sobre la línea del horizonte
	var base_y := size.y * 0.47
	var semilla := 7
	for i in 26:
		semilla = (semilla * 1103515245 + 12345) % 2147483648
		var alto := (8 + (semilla >> 8) % 42) * k
		var ancho := (18 + (semilla >> 16) % 26) * k
		var x := (i * 52.0) * k
		draw_rect(Rect2(x, base_y - alto, ancho, alto), Color("1b3f5e"))

	# mar
	draw_rect(Rect2(0, base_y, size.x, size.y * 0.16), Pixel.PALETA["mar_1"])
	draw_rect(Rect2(0, base_y, size.x, size.y * 0.035), Pixel.PALETA["mar_2"])
	var ola_y := base_y + size.y * 0.045
	var paso := 26.0 * k
	var corrimiento := fmod(t * 22.0 * k, paso)
	for i in int(size.x / paso) + 2:
		draw_rect(Rect2(i * paso - corrimiento, ola_y, paso * 0.55, 4.0 * k),
			Color(1, 1, 1, 0.35))
		draw_rect(Rect2(i * paso - corrimiento + paso * 0.7, ola_y + 10.0 * k,
			paso * 0.30, 4.0 * k), Color(1, 1, 1, 0.22))

	# arena
	var arena_y := size.y * 0.63
	draw_rect(Rect2(0, arena_y, size.x, size.y - arena_y), Pixel.PALETA["arena_1"])
	draw_rect(Rect2(0, arena_y, size.x, 5.0 * k), Pixel.PALETA["arena_2"])
	var alto_arena := size.y - arena_y
	for i in 110:
		var fx := fmod(float(i) * 149.0, size.x)
		var fy := arena_y + fmod(float(i) * 83.0 + 17.0, maxf(alto_arena - 8.0 * k, 1.0))
		draw_rect(Rect2(fx, fy, 3.0 * k, 3.0 * k), Pixel.PALETA["arena_2"].darkened(0.05))

	# dunas: dos manchas de arena un poco más oscura en las esquinas
	var duna := Pixel.PALETA["arena_2"]
	draw_rect(Rect2(0, size.y - 74.0 * k, 250.0 * k, 74.0 * k), duna)
	draw_rect(Rect2(0, size.y - 96.0 * k, 170.0 * k, 22.0 * k), duna)
	draw_rect(Rect2(size.x - 300.0 * k, size.y - 58.0 * k, 300.0 * k, 58.0 * k), duna)
	draw_rect(Rect2(size.x - 210.0 * k, size.y - 78.0 * k, 210.0 * k, 20.0 * k), duna)


func _contador_conchas(size: Vector2, k: float) -> void:
	SaveGame.cargar()
	var txt := str(SaveGame.conchas)
	var esc := _esc(3.4, k)
	var w := 190.0 * k
	var rect := Rect2(size.x - w - 24.0 * k, 20.0 * k, w, 46.0 * k)
	Pixel.panel(self, rect, Pixel.PALETA["papel"], Pixel.PALETA["tinta"], _esc(1.2, k))
	Pixel.icono(self, Vector2(rect.position.x + 12.0 * k, rect.position.y + 11.0 * k),
		"concha", _esc(2.6, k), Pixel.PALETA["ambar"])
	Pixel.dibujar(self, Vector2(rect.position.x + 78.0 * k, rect.position.y + 12.0 * k),
		txt, esc, Pixel.PALETA["tinta"])


func _menu(size: Vector2, k: float) -> void:
	var cx := size.x * 0.5
	Pixel.centrado_sombra(self, cx, 44.0 * k, "PLAYA LIMPIA", _esc(8.4, k), Pixel.PALETA["papel"])
	Pixel.centrado_sombra(self, cx, 118.0 * k, "UNA PLAYA, DOS MANOS, UNA CUOTA",
		_esc(2.2, k), Pixel.PALETA["crema"])

	_contador_conchas(size, k)

	var ancho := 340.0 * k
	var alto := 396.0 * k
	var hueco := 52.0 * k
	var x0 := cx - ancho - hueco * 0.5
	var y0 := 168.0 * k
	_carta(Vector2(x0, y0), Vector2(ancho, alto), k, 0, "JUGADOR 1", "retrato-j1",
		SaveGame.tiene("mujer") or true, "LISTO")
	_carta(Vector2(x0 + ancho + hueco, y0), Vector2(ancho, alto), k, 1, "JUGADORA 2",
		"retrato-j2", SaveGame.tiene("mujer"), "LISTA")

	var yf := 612.0 * k
	Pixel.centrado_sombra(self, cx, yf, "[ IZQ / DER ]  ELEGIR", _esc(2.3, k), Pixel.PALETA["crema"])
	Pixel.centrado_sombra(self, cx, yf + 34.0 * k, "[ ENTER ]  JUGAR", _esc(3.2, k), Pixel.PALETA["papel"])
	Pixel.centrado_sombra(self, cx, yf + 78.0 * k,
		"[ T ]  TIENDA DE MEJORAS        [ D ]  ARENA DE PRUEBAS",
		_esc(2.0, k), Pixel.PALETA["crema"])


func _carta(pos: Vector2, tam: Vector2, k: float, idx: int, titulo: String,
		textura: String, desbloqueada: bool, estado_ok: String) -> void:
	var elegida := sel == idx
	var borde: Color = Pixel.PALETA["ambar"] if elegida else Pixel.PALETA["tinta"]
	var grosor := _esc(1.6 if elegida else 1.0, k)
	Pixel.panel(self, Rect2(pos, tam), Pixel.PALETA["crema"], borde, grosor)

	# retrato
	var lado := 196.0 * k
	var prect := Rect2(pos.x + (tam.x - lado) * 0.5, pos.y + 26.0 * k, lado, lado)
	draw_rect(prect.grow(4.0 * k), Pixel.PALETA["tinta"])
	draw_rect(prect, Pixel.PALETA["cielo_2"])
	var tex: Texture2D = _tex.get(textura, null)
	if tex != null:
		var tinte := Color(1, 1, 1, 1) if desbloqueada else Color(0.09, 0.10, 0.12, 1)
		draw_texture_rect(tex, prect, false, tinte)
	if not desbloqueada:
		# el icono mide 8x8: `lado_icono / 8` es el tamaño de cada pixel
		var lado_icono := 74.0 * k
		var px := lado_icono / 8.0
		Pixel.icono(self, Vector2(prect.get_center().x - lado_icono * 0.5,
			prect.get_center().y - lado_icono * 0.5), "candado", int(maxf(1.0, px)),
			Pixel.PALETA["ambar"])

	Pixel.centrado(self, pos.x + tam.x * 0.5, pos.y + 250.0 * k, titulo, _esc(3.0, k),
		Pixel.PALETA["tinta"])

	if desbloqueada:
		Pixel.centrado(self, pos.x + tam.x * 0.5, pos.y + 292.0 * k, estado_ok,
			_esc(2.4, k), Pixel.PALETA["verde"])
		Pixel.centrado(self, pos.x + tam.x * 0.5, pos.y + 330.0 * k,
			"JUGAR SOLO" if idx == 0 else "COOPERATIVO", _esc(1.8, k),
			Pixel.PALETA["gris"])
	else:
		Pixel.centrado(self, pos.x + tam.x * 0.5, pos.y + 292.0 * k, "BLOQUEADA",
			_esc(2.4, k), Pixel.PALETA["rojo"])
		var et := 15
		var precio := ShopCatalog.item("mujer")
		if not precio.is_empty():
			et = int(precio["precio"])
		var txt := "%d CONCHAS" % et
		var esc := _esc(2.0, k)
		var w := Pixel.ancho(txt, esc)
		var x := pos.x + tam.x * 0.5 - (w + 26.0 * k) * 0.5
		Pixel.icono(self, Vector2(x, pos.y + 328.0 * k), "concha", _esc(1.9, k),
			Pixel.PALETA["ambar"])
		Pixel.dibujar(self, Vector2(x + 22.0 * k, pos.y + 330.0 * k), txt, esc,
			Pixel.PALETA["tinta"])

	if elegida:
		var fle := _esc(2.6, k)
		var lado_f := fle * 8.0
		Pixel.icono(self, Vector2(pos.x - lado_f - 10.0 * k, pos.y + tam.y * 0.5 - lado_f * 0.5),
			"flecha_i", fle, Pixel.PALETA["ambar"])
		Pixel.icono(self, Vector2(pos.x + tam.x + 10.0 * k, pos.y + tam.y * 0.5 - lado_f * 0.5),
			"flecha_d", fle, Pixel.PALETA["ambar"])


func _tienda(size: Vector2, k: float) -> void:
	var cx := size.x * 0.5
	Pixel.centrado_sombra(self, cx, 40.0 * k, "TIENDA DE MEJORAS", _esc(5.6, k),
		Pixel.PALETA["papel"])
	Pixel.centrado_sombra(self, cx, 104.0 * k, "LO QUE COMPRES QUEDA PARA SIEMPRE",
		_esc(2.0, k), Pixel.PALETA["crema"])
	_contador_conchas(size, k)

	var ancho := 920.0 * k
	var alto := 82.0 * k
	var x0 := cx - ancho * 0.5
	var y0 := 150.0 * k
	SaveGame.cargar()
	for i in ShopCatalog.ITEMS.size():
		var it: Dictionary = ShopCatalog.ITEMS[i]
		var pos := Vector2(x0, y0 + float(i) * (alto + 14.0 * k))
		var elegida := cursor == i
		var comprado := SaveGame.tiene(String(it["id"]))
		var precio := int(it["precio"])
		var alcanza := SaveGame.conchas >= precio
		var borde: Color = Pixel.PALETA["ambar"] if elegida else Pixel.PALETA["tinta"]
		Pixel.panel(self, Rect2(pos, Vector2(ancho, alto)),
			Pixel.PALETA["crema"] if not comprado else Pixel.PALETA["crema_2"], borde,
			_esc(1.6 if elegida else 1.0, k))

		var esc_n := _esc(2.8, k)
		Pixel.dibujar(self, Vector2(pos.x + 24.0 * k, pos.y + 16.0 * k),
			String(it["nombre"]), esc_n, Pixel.PALETA["tinta"])
		Pixel.dibujar(self, Vector2(pos.x + 24.0 * k, pos.y + 52.0 * k),
			String(it["desc"]), _esc(1.8, k), Pixel.PALETA["gris"])

		var icono_nombre := String(it.get("icono", ""))
		if icono_nombre != "" and _tex.has(icono_nombre):
			var lado := 54.0 * k
			draw_texture_rect(_tex[icono_nombre],
				Rect2(pos.x + ancho - lado - 250.0 * k, pos.y + 14.0 * k, lado, lado),
				false, Color(1, 1, 1, 1) if comprado or alcanza else Color(0.65, 0.65, 0.65, 1))

		if comprado:
			Pixel.icono(self, Vector2(pos.x + ancho - 168.0 * k, pos.y + 22.0 * k),
				"check", _esc(3.0, k), Pixel.PALETA["verde"])
			Pixel.dibujar(self, Vector2(pos.x + ancho - 136.0 * k, pos.y + 26.0 * k),
				"COMPRADO", _esc(2.2, k), Pixel.PALETA["verde"])
		else:
			var txt := str(precio)
			var esc_p := _esc(3.0, k)
			var w := Pixel.ancho(txt, esc_p)
			var x := pos.x + ancho - 34.0 * k - w
			Pixel.icono(self, Vector2(x - 30.0 * k, pos.y + 26.0 * k), "concha",
				_esc(2.4, k), Pixel.PALETA["ambar"] if alcanza else Pixel.PALETA["gris"])
			Pixel.dibujar(self, Vector2(x, pos.y + 24.0 * k), txt, esc_p,
				Pixel.PALETA["tinta"] if alcanza else Pixel.PALETA["rojo"])

	Pixel.centrado_sombra(self, cx, y0 + 5.0 * (alto + 14.0 * k) + 16.0 * k,
		"[ ARRIBA / ABAJO ]  ELEGIR      [ ENTER ]  COMPRAR      [ ESC ]  VOLVER",
		_esc(2.0, k), Pixel.PALETA["crema"])


func _aviso(size: Vector2, k: float) -> void:
	if aviso_t <= 0.0 or aviso == "":
		return
	var alpha := clampf(aviso_t / 0.4, 0.0, 1.0)
	var esc := _esc(2.6, k)
	var w := Pixel.ancho(aviso, esc) + 44.0 * k
	var rect := Rect2(size.x * 0.5 - w * 0.5, size.y - 96.0 * k, w, 46.0 * k)
	Pixel.panel(self, rect, Color(Pixel.PALETA["tinta"], 0.92 * alpha),
		Pixel.PALETA["ambar"], _esc(1.2, k))
	Pixel.centrado(self, size.x * 0.5, rect.position.y + 14.0 * k, aviso, esc,
		Color(Pixel.PALETA["papel"], alpha))
