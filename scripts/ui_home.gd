class_name UiHome
extends Control
## Pantalla de inicio, colección y tienda (pixel art + modelo 3D en vivo).
##
## Layout: opciones a la IZQUIERDA y el personaje elegido en 3D a la DERECHA,
## girando sobre un pedestal (SubViewport con fondo transparente).
##
## La TIENDA solo existe DENTRO de la run (entre día y día): desde el menú no se
## compra nada, solo se mira la COLECCIÓN de desbloqueos, como en Balatro.

const ANCHO_BASE := 1280.0
const ALTO_BASE := 800.0
const FILAS := ["JUGAR", "PERSONAJE", "COLECCION", "ARENA"]

var modo := "menu"            # menu | coleccion | tienda
var fila := 0                 # opción del menú
var sel := 0                  # 0 = jugador 1, 1 = jugadora 2
var cursor := 0               # colección / tienda
var monedas := 0              # plata de la RUN (la pone main al abrir la tienda)
var compradas: Array = []     # cartas compradas en esta run
var aviso := ""
var aviso_t := 0.0
var t := 0.0

var _tex := {}
var _vp: SubViewport
var _ancla: Node3D
var _modelo: Node3D
var _modelo_idx := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	SaveGame.cargar()
	for it in ShopCatalog.DESBLOQUEOS:
		var n := String(it.get("icono", ""))
		if n == "":
			continue
		var p := "res://assets/ui/%s.png" % n
		if ResourceLoader.exists(p):
			_tex[n] = load(p)
	_montar_escenario()
	visible = false


# ------------------------------------------------------------------ 3D
func _montar_escenario() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(560, 720)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var escena := Node3D.new()
	_vp.add_child(escena)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.86, 0.95)
	e.ambient_light_energy = 0.95
	env.environment = e
	escena.add_child(env)

	var clave := DirectionalLight3D.new()
	clave.rotation_degrees = Vector3(-42, 34, 0)
	clave.light_energy = 1.15
	escena.add_child(clave)
	var relleno := DirectionalLight3D.new()
	relleno.rotation_degrees = Vector3(-16, -125, 0)
	relleno.light_energy = 0.5
	relleno.light_color = Color(0.86, 0.93, 1.0)
	escena.add_child(relleno)

	_ancla = Node3D.new()
	escena.add_child(_ancla)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.24
	cam.position = Vector3(0.0, 0.47, 3.0)
	escena.add_child(cam)
	cam.current = true

	_set_modelo(sel)


func _set_modelo(idx: int) -> void:
	if _modelo != null and is_instance_valid(_modelo):
		_modelo.queue_free()
		_modelo = null
	var ruta := "res://assets/kid.glb" if idx == 0 else "res://assets/mujer.glb"
	if not ResourceLoader.exists(ruta):
		return
	var packed := load(ruta) as PackedScene
	if packed == null:
		return
	_modelo_idx = idx
	_modelo = packed.instantiate() as Node3D
	_ancla.add_child(_modelo)
	CharModel.fit_model(_modelo)
	# el pescador trae un cangrejo pegado: en el menú no va
	for mi in _modelo.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		for pre in ["brazoC", "pataC", "pinza", "ojoC", "pupC", "reborde",
				"pedunculo", "dedo-1x", "concha", "vientre"]:
			if nm.begins_with(pre):
				(mi as MeshInstance3D).visible = false
				break
	_silueta(_modelo, not desbloqueado(idx))


func _silueta(model: Node3D, negro: bool) -> void:
	var mat: Material = null
	if negro:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.07, 0.08, 0.10)
		sm.roughness = 1.0
		mat = sm
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).visible:
			(mi as MeshInstance3D).material_override = mat


func desbloqueado(idx: int) -> bool:
	if idx == 0:
		return true
	return SaveGame.tiene("mujer")


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	if aviso_t > 0.0:
		aviso_t = maxf(0.0, aviso_t - delta)
	# si cambió la selección (por teclado o por código) se cambia el modelo
	if modo == "menu" and _modelo_idx != sel:
		_set_modelo(sel)
	if _modelo != null and is_instance_valid(_modelo) and modo == "menu":
		_modelo.rotation.y += delta * 0.55
	queue_redraw()


# ------------------------------------------------------------------ API
func abrir_menu() -> void:
	modo = "menu"
	visible = true
	_set_modelo(sel)


func abrir_coleccion() -> void:
	modo = "coleccion"
	cursor = 0
	visible = true


## Solo desde la run: la plata es la que se junta jugando.
func abrir_tienda(plata: int) -> void:
	modo = "tienda"
	cursor = 0
	monedas = plata
	visible = true


func cerrar() -> void:
	modo = "menu"
	visible = true


func avisar(txt: String) -> void:
	aviso = txt
	aviso_t = 2.6


func mover(dir: int) -> void:
	if modo == "menu":
		fila = clampi(fila + dir, 0, FILAS.size() - 1)
	elif modo == "coleccion":
		var n := ShopCatalog.DESBLOQUEOS.size()
		cursor = (cursor + dir + n) % n
	else:
		var n := ShopCatalog.CARTAS.size()
		cursor = (cursor + dir + n) % n


func cambiar_personaje(dir: int) -> void:
	sel = clampi(sel + dir, 0, 1)
	_set_modelo(sel)


## Devuelve la acción del menú para que main la ejecute.
func accion_menu() -> String:
	match fila:
		0:
			return "jugar"
		1:
			return "personaje"
		2:
			return "coleccion"
		_:
			return "arena"


# ------------------------------------------------------------------ dibujo
func _draw() -> void:
	var size := get_viewport_rect().size
	var k := minf(size.x / ANCHO_BASE, size.y / ALTO_BASE)
	_fondo(size, k)
	match modo:
		"menu":
			_escenario(size, k)
			_menu(size, k)
		"coleccion":
			_coleccion(size, k)
		_:
			_tienda(size, k)
	_aviso(size, k)


func _esc(v: float, k: float) -> int:
	return maxi(1, int(round(v * k)))


## Cielo en bandas, sol de bloques, ciudad lejana, mar con olas y arena.
func _fondo(size: Vector2, k: float) -> void:
	var cielo := [Pixel.PALETA["cielo_1"], Pixel.PALETA["cielo_1"].lightened(0.10),
		Pixel.PALETA["cielo_2"], Pixel.PALETA["cielo_2"].lightened(0.10),
		Pixel.PALETA["cielo_3"]]
	var banda := size.y * 0.47 / float(cielo.size())
	for i in cielo.size():
		draw_rect(Rect2(0, banda * i, size.x, banda + 1.0), cielo[i])

	var cx := size.x * 0.455
	var cy := size.y * 0.255
	var cubo := maxf(4.0, size.y / 120.0)
	for gy in range(-6, 7):
		for gx in range(-6, 7):
			var d := Vector2(gx, gy).length()
			if d <= 6.2:
				draw_rect(Rect2(cx + gx * cubo, cy + gy * cubo, cubo, cubo),
					Pixel.PALETA["sol"] if d <= 4.6 else Pixel.PALETA["sol"].darkened(0.10))

	var base_y := size.y * 0.47
	var semilla := 11
	for i in 26:
		semilla = (semilla * 1103515245 + 12345) % 2147483648
		var alto := (8 + (semilla >> 8) % 40) * k
		var ancho := (18 + (semilla >> 16) % 26) * k
		draw_rect(Rect2((i * 52.0) * k, base_y - alto, ancho, alto), Color("1b3f5e"))

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

	var arena_y := size.y * 0.63
	draw_rect(Rect2(0, arena_y, size.x, size.y - arena_y), Pixel.PALETA["arena_1"])
	draw_rect(Rect2(0, arena_y, size.x, 5.0 * k), Pixel.PALETA["arena_2"])
	var alto_arena := size.y - arena_y
	for i in 110:
		var fx := fmod(float(i) * 149.0, size.x)
		var fy := arena_y + fmod(float(i) * 83.0 + 17.0, maxf(alto_arena - 8.0 * k, 1.0))
		draw_rect(Rect2(fx, fy, 3.0 * k, 3.0 * k), Pixel.PALETA["arena_2"].darkened(0.05))


## Elipse dibujada con cuadraditos (para que tenga el mismo filo que el resto).
func _elipse_pixel(centro: Vector2, rx: float, ry: float, color: Color, paso: float) -> void:
	var y := -ry
	while y <= ry:
		var k2 := 1.0 - (y * y) / maxf(ry * ry, 0.001)
		if k2 > 0.0:
			var ancho := rx * sqrt(k2)
			draw_rect(Rect2(centro.x - ancho, centro.y + y, ancho * 2.0, paso), color)
		y += paso


## Panel donde vive el modelo 3D (a la derecha).
func _escenario(size: Vector2, k: float) -> void:
	var rect := Rect2(size.x * 0.515, size.y * 0.05, size.x * 0.45, size.y * 0.90)
	draw_rect(rect.grow(6.0 * k), Color("141a20"))
	var bandas := [Color("2a5f8f"), Color("3674a6"), Color("4287b6")]
	var alto_b := rect.size.y / float(bandas.size())
	for i in bandas.size():
		draw_rect(Rect2(rect.position.x, rect.position.y + alto_b * i,
			rect.size.x, alto_b + 1.0), bandas[i])
	# sombra del personaje: elipse de bloques justo donde apoyan los pies
	var pies_y := rect.position.y + rect.size.y * 0.882
	_elipse_pixel(Vector2(rect.get_center().x, pies_y), rect.size.x * 0.20,
		rect.size.x * 0.055, Color(0, 0, 0, 0.20), maxf(3.0, 5.0 * k))
	if _vp != null:
		var tex := _vp.get_texture()
		if tex != null:
			draw_texture_rect(tex, rect, false)


func _menu(size: Vector2, k: float) -> void:
	Pixel.dibujar_sombra(self, Vector2(64.0 * k, 54.0 * k), "PLAYA", _esc(7.0, k),
		Pixel.PALETA["papel"])
	Pixel.dibujar_sombra(self, Vector2(64.0 * k, 116.0 * k), "LIMPIA", _esc(7.0, k),
		Pixel.PALETA["ambar"])
	Pixel.dibujar(self, Vector2(66.0 * k, 186.0 * k), "UNA PLAYA, DOS MANOS, UNA CUOTA",
		_esc(1.9, k), Color(Pixel.PALETA["crema"], 0.9))

	var y := 250.0 * k
	for i in FILAS.size():
		var elegida := fila == i
		var color: Color = Pixel.PALETA["ambar"] if elegida else Pixel.PALETA["papel"]
		if elegida:
			Pixel.icono(self, Vector2(40.0 * k, y + 10.0 * k), "flecha_d", _esc(2.2, k),
				Pixel.PALETA["ambar"])
		var txt: String = FILAS[i]
		if i == 1:
			txt = "PERSONAJE"
		Pixel.dibujar_sombra(self, Vector2(78.0 * k, y), txt, _esc(3.4, k), color)
		if i == 0:
			var modo_txt := "SOLO" if sel == 0 else "COOPERATIVO"
			Pixel.dibujar(self, Vector2(300.0 * k, y + 10.0 * k), modo_txt, _esc(1.9, k),
				Color(Pixel.PALETA["crema"], 0.75))
		if i == 1:
			var nom := "JUGADOR 1" if sel == 0 else "JUGADORA 2"
			var lock_txt := nom if desbloqueado(sel) else nom + "  [BLOQUEADA]"
			Pixel.dibujar(self, Vector2(300.0 * k, y + 10.0 * k), lock_txt, _esc(1.9, k),
				Pixel.PALETA["crema"] if desbloqueado(sel) else Pixel.PALETA["rojo"])
		y += 62.0 * k

	# estado del personaje elegido, abajo a la izquierda
	var estado_y := 560.0 * k
	if desbloqueado(sel):
		Pixel.dibujar(self, Vector2(64.0 * k, estado_y), "ELEGIDO", _esc(1.9, k),
			Color(Pixel.PALETA["crema"], 0.7))
		Pixel.dibujar_sombra(self, Vector2(64.0 * k, estado_y + 26.0 * k),
			"JUGADOR 1" if sel == 0 else "JUGADORA 2", _esc(2.8, k), Pixel.PALETA["papel"])
		Pixel.dibujar(self, Vector2(64.0 * k, estado_y + 66.0 * k),
			"+ MANOS" if sel == 1 else "SOLO VOS", _esc(1.7, k), Pixel.PALETA["verde"])
	else:
		Pixel.dibujar_sombra(self, Vector2(64.0 * k, estado_y + 26.0 * k),
			"BLOQUEADA", _esc(2.8, k), Pixel.PALETA["rojo"])
		Pixel.dibujar(self, Vector2(64.0 * k, estado_y + 66.0 * k),
			"COMPLETA EL DIA 2 PARA ABRIRLA", _esc(1.6, k), Pixel.PALETA["crema"])

	Pixel.dibujar(self, Vector2(64.0 * k, 726.0 * k),
		"[ ARRIBA / ABAJO ]  ELEGIR     [ IZQ / DER ]  PERSONAJE",
		_esc(1.7, k), Color(Pixel.PALETA["crema"], 0.85))
	Pixel.dibujar(self, Vector2(64.0 * k, 752.0 * k),
		"[ ENTER ]  JUGAR     [ C ]  COLECCION",
		_esc(1.7, k), Color(Pixel.PALETA["crema"], 0.85))


func _coleccion(size: Vector2, k: float) -> void:
	var cx := size.x * 0.5
	Pixel.centrado_sombra(self, cx, 34.0 * k, "COLECCION", _esc(5.0, k), Pixel.PALETA["papel"])
	Pixel.centrado_sombra(self, cx, 92.0 * k, "SE DESBLOQUEA JUGANDO (NO SE COMPRA)",
		_esc(1.8, k), Pixel.PALETA["crema"])

	var cols := 2
	var ancho := 470.0 * k
	var alto := 150.0 * k
	var hueco := 18.0 * k
	var total := ShopCatalog.DESBLOQUEOS.size()
	var x0 := cx - (ancho * cols + hueco * (cols - 1)) * 0.5
	var y0 := 132.0 * k
	for i in total:
		var it: Dictionary = ShopCatalog.DESBLOQUEOS[i]
		var col := i % cols
		var fil := i / cols
		var pos := Vector2(x0 + float(col) * (ancho + hueco), y0 + float(fil) * (alto + hueco))
		var abierto := SaveGame.tiene(String(it["id"]))
		var elegida := cursor == i
		Pixel.panel(self, Rect2(pos, Vector2(ancho, alto)),
			Pixel.PALETA["crema"] if abierto else Pixel.PALETA["crema_2"],
			Pixel.PALETA["ambar"] if elegida else Pixel.PALETA["tinta"],
			_esc(1.4 if elegida else 0.8, k))
		Pixel.dibujar(self, Vector2(pos.x + 20.0 * k, pos.y + 18.0 * k),
			String(it["nombre"]), _esc(2.4, k),
			Pixel.PALETA["tinta"] if abierto else Pixel.PALETA["gris"])
		Pixel.dibujar(self, Vector2(pos.x + 20.0 * k, pos.y + 54.0 * k),
			String(it["desc"]), _esc(1.5, k), Pixel.PALETA["gris"])
		if abierto:
			Pixel.icono(self, Vector2(pos.x + 20.0 * k, pos.y + 96.0 * k), "check",
				_esc(2.2, k), Pixel.PALETA["verde"])
			Pixel.dibujar(self, Vector2(pos.x + 48.0 * k, pos.y + 100.0 * k),
				"DESBLOQUEADO", _esc(1.9, k), Pixel.PALETA["verde"])
		else:
			Pixel.icono(self, Vector2(pos.x + 20.0 * k, pos.y + 94.0 * k), "candado",
				_esc(2.0, k), Pixel.PALETA["ambar"])
			Pixel.dibujar(self, Vector2(pos.x + 48.0 * k, pos.y + 100.0 * k),
				String(it["condicion"]), _esc(1.6, k), Pixel.PALETA["ambar"])

	Pixel.centrado_sombra(self, cx, 720.0 * k, "[ FLECHAS ]  MOVER        [ ESC / C ]  VOLVER",
		_esc(1.8, k), Pixel.PALETA["crema"])


func _tienda(size: Vector2, k: float) -> void:
	var cx := size.x * 0.5
	Pixel.centrado_sombra(self, cx, 30.0 * k, "TIENDA", _esc(5.0, k), Pixel.PALETA["papel"])
	Pixel.dibujar(self, Vector2(60.0 * k, 116.0 * k), "PLATA", _esc(1.8, k),
		Color(Pixel.PALETA["crema"], 0.8))
	Pixel.icono(self, Vector2(130.0 * k, 110.0 * k), "concha", _esc(1.8, k),
		Pixel.PALETA["ambar"])
	Pixel.dibujar_sombra(self, Vector2(160.0 * k, 106.0 * k), str(monedas), _esc(2.8, k),
		Pixel.PALETA["papel"])

	var cols := 3
	var ancho := 360.0 * k
	var alto := 168.0 * k
	var hueco := 16.0 * k
	var total := ShopCatalog.CARTAS.size()
	var x0 := cx - (ancho * cols + hueco * (cols - 1)) * 0.5
	var y0 := 150.0 * k
	for i in total:
		var it: Dictionary = ShopCatalog.CARTAS[i]
		var col := i % cols
		var fil := i / cols
		var pos := Vector2(x0 + float(col) * (ancho + hueco), y0 + float(fil) * (alto + hueco))
		var comprada := compradas.has(String(it["id"]))
		var precio := int(it["precio"])
		var alcanza := monedas >= precio
		var elegida := cursor == i
		var color_rareza := Pixel.PALETA["crema"]
		match String(it["rareza"]):
			"rara":
				color_rareza = Color("e8dcc0")
			"maldita":
				color_rareza = Color("e9c7c0")
		Pixel.panel(self, Rect2(pos, Vector2(ancho, alto)), color_rareza,
			Pixel.PALETA["ambar"] if elegida else Pixel.PALETA["tinta"],
			_esc(1.4 if elegida else 0.8, k))
		Pixel.dibujar(self, Vector2(pos.x + 16.0 * k, pos.y + 16.0 * k),
			String(it["nombre"]), _esc(2.1, k), Pixel.PALETA["tinta"])
		Pixel.dibujar(self, Vector2(pos.x + 16.0 * k, pos.y + 52.0 * k),
			String(it["desc"]), _esc(1.4, k), Pixel.PALETA["gris"])
		Pixel.dibujar(self, Vector2(pos.x + 16.0 * k, pos.y + 128.0 * k),
			String(it["rareza"]).to_upper(), _esc(1.4, k), Pixel.PALETA["gris"])
		if comprada:
			Pixel.dibujar(self, Vector2(pos.x + ancho - 110.0 * k, pos.y + 128.0 * k),
				"COMPRADA", _esc(1.6, k), Pixel.PALETA["verde"])
		else:
			Pixel.icono(self, Vector2(pos.x + ancho - 74.0 * k, pos.y + 126.0 * k),
				"concha", _esc(1.6, k),
				Pixel.PALETA["ambar"] if alcanza else Pixel.PALETA["gris"])
			Pixel.dibujar(self, Vector2(pos.x + ancho - 50.0 * k, pos.y + 124.0 * k),
				str(precio), _esc(2.2, k),
				Pixel.PALETA["tinta"] if alcanza else Pixel.PALETA["rojo"])

	Pixel.centrado_sombra(self, cx, 742.0 * k,
		"[ FLECHAS ]  ELEGIR     [ ENTER ]  COMPRAR     [ ESC ]  SEGUIR",
		_esc(1.7, k), Pixel.PALETA["crema"])


func _aviso(size: Vector2, k: float) -> void:
	if aviso_t <= 0.0 or aviso == "":
		return
	var alpha := clampf(aviso_t / 0.4, 0.0, 1.0)
	var esc := _esc(2.4, k)
	var w := Pixel.ancho(aviso, esc) + 44.0 * k
	var rect := Rect2(size.x * 0.5 - w * 0.5, size.y - 92.0 * k, w, 44.0 * k)
	Pixel.panel(self, rect, Color(Pixel.PALETA["tinta"], 0.92 * alpha),
		Pixel.PALETA["ambar"], _esc(1.2, k))
	Pixel.centrado(self, size.x * 0.5, rect.position.y + 13.0 * k, aviso, esc,
		Color(Pixel.PALETA["papel"], alpha))
