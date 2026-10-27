class_name GridWorld
extends Node3D
## Traduce el mapa de texto a geometría 3D + semántica de celdas:
##   sólido   -> no se puede caminar encima (agua, roca, estación)
##   superficie -> puede sostener un ítem (mostrador y arena)
##   station  -> qué interacción ofrece

const COLORS := {
	"sand": Color(0.87, 0.74, 0.50),
	"sand_line": Color(0.80, 0.67, 0.44),
	"ocean": Color(0.09, 0.40, 0.58),
	"rock": Color(0.50, 0.47, 0.42),
}

var w := 0
var h := 0
var map: Array = []
var tiles: Array = []          # Array[Array[CellData]]
var spawns: Array = []         # Array[Vector2i]
var items_root: Node3D
var colliders: Node3D


func build(map_rows: Array) -> void:
	map = map_rows
	h = map.size()
	w = String(map[0]).length()

	items_root = Node3D.new()
	items_root.name = "Items"
	add_child(items_root)

	colliders = Node3D.new()
	colliders.name = "Colliders"
	add_child(colliders)

	_build_ground()

	for y in h:
		var row: Array = []
		for x in w:
			var t := _make_tile(x, y, String(map[y])[x])
			row.append(t)
			_build_visual(t)
			if t.is_solid():
				_build_collider(t)
		tiles.append(row)

	# los props se arman al final: necesitan marcar su celda
	_build_decor()


# ------------------------------------------------------------------ consultas
func tile_at(x: int, y: int) -> CellData:
	# `tiles` se llena fila por fila mientras se construye el mundo: durante
	# el build puede pedirse una fila que todavía no existe (la de abajo).
	if x < 0 or y < 0 or x >= w or y >= h or y >= tiles.size():
		return null
	var row: Array = tiles[y]
	if x >= row.size():
		return null
	return row[x]


func is_solid(x: int, y: int) -> bool:
	var t := tile_at(x, y)
	return t == null or t.is_solid()


func tiles_of(station: String) -> Array:
	var out: Array = []
	for row in tiles:
		for t in row:
			if t.station == station:
				out.append(t)
	return out


func free_floors_near(cx: int, cy: int, radius := 4) -> Array:
	for r in range(0, radius + 1):
		var found: Array = []
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				var t := tile_at(x, y)
				if t != null and not t.is_solid() and t.item == null:
					found.append(t)
		if not found.is_empty():
			return found
	return []


func item_position(tile: CellData) -> Vector3:
	# la basura del agua flota sobre la lámina (el agua sigue siendo sólida)
	var y := 0.24 if tile.kind == "water" else tile.top_y() + 0.02
	return Vector3(tile.x + 0.5, y, tile.y + 0.5)


# ------------------------------------------------------------------ geometría
func _make_tile(x: int, y: int, ch: String) -> CellData:
	var t := CellData.new()
	t.x = x
	t.y = y
	t.ch = ch
	match ch:
		"~":
			t.kind = "water"
		"#":
			t.kind = "rock"
		".", "S":
			t.kind = "floor"
			if ch == "S":
				spawns.append(Vector2i(x, y))
		"1":
			_set_station(t, "bin")
			t.bin = "pet"
		"2":
			_set_station(t, "bin")
			t.bin = "lata"
		"3":
			_set_station(t, "bin")
			t.bin = "vidrio"
		"B":
			_set_station(t, "bags")
		"D":
			_set_station(t, "delivery")
		_:
			push_warning("Carácter de mapa desconocido: %s (%d,%d)" % [ch, x, y])
			t.kind = "floor"
	return t


func _set_station(t: CellData, station: String) -> void:
	t.kind = "station"
	t.station = station


func _build_ground() -> void:
	var ocean := PlaneMesh.new()
	ocean.size = Vector2(90, 90)
	var om := MeshInstance3D.new()
	om.mesh = ocean
	var omat := StandardMaterial3D.new()
	omat.albedo_color = COLORS["ocean"]
	omat.roughness = 0.35
	omat.metallic = 0.15
	om.material_override = omat
	om.position = Vector3(w * 0.5, -0.04, h * 0.5)
	add_child(om)

	# la arena cubre solo el recuadro de celdas no acuáticas
	var min_x := w
	var max_x := 0
	var min_y := h
	var max_y := 0
	for y in h:
		for x in w:
			if String(map[y])[x] != "~":
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)

	# losa de arena con espesor: sin borde fantasma contra el agua
	var sand_w := float(max_x - min_x + 1)
	var sand_h := float(max_y - min_y + 1)
	var sand := BoxMesh.new()
	sand.size = Vector3(sand_w, 0.4, sand_h)
	var sm := MeshInstance3D.new()
	sm.mesh = sand
	sm.material_override = ItemVisuals.material(COLORS["sand"], 0.0)
	sm.position = Vector3((min_x + max_x + 1) * 0.5, -0.2, (min_y + max_y + 1) * 0.5)
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sm)

	# piso físico: la basura es un cuerpo rígido y necesita dónde apoyarse
	# (el jugador sigue clavado a y=0 a mano, no salta ni cae)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(float(w) + 4.0, 1.0, float(h) + 4.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(w * 0.5, -0.5, h * 0.5)
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	# cuadrícula tenue: ayuda a leer distancias y da textura sin assets
	var line_mat := ItemVisuals.material(COLORS["sand_line"], 0.0)
	for x in range(min_x + 1, max_x + 1):
		var lx := BoxMesh.new()
		lx.size = Vector3(0.02, 0.02, sand_h)
		var lm := MeshInstance3D.new()
		lm.mesh = lx
		lm.material_override = line_mat
		lm.position = Vector3(x, 0.011, (min_y + max_y + 1) * 0.5)
		add_child(lm)

	for y in range(min_y + 1, max_y + 1):
		var lz := BoxMesh.new()
		lz.size = Vector3(sand_w, 0.02, 0.02)
		var lm2 := MeshInstance3D.new()
		lm2.mesh = lz
		lm2.material_override = line_mat
		lm2.position = Vector3((min_x + max_x + 1) * 0.5, 0.011, y)
		add_child(lm2)


func _build_decor() -> void:
	for d in Levels.DECOR:
		var kind: String = d[2]
		var tile := tile_at(int(d[0]), int(d[1]))
		var pos := Vector3(d[0] + 0.5, 0.02, d[1] + 0.5)
		match kind:
			"palm":
				if tile != null:
					tile.decor = kind
				_palm(Vector3(d[0] + 0.5, 0.0, d[1] + 0.5))
				_decor_collider(Vector3(d[0] + 0.5, 0.0, d[1] + 0.5), 0.16, 2.0)
			"umbrella":
				_umbrella(pos, _decor_color(d[0] * 7 + d[1] * 13))
			"tower":
				if tile != null:
					tile.decor = kind
				_tower(pos)
				_decor_collider(pos + Vector3(0, 0, 0), 0.55, 1.8)
			"pier":
				if tile != null:
					tile.decor = kind
				_pier(int(d[0]), 10, 13)
			"rock":
				var m := SphereMesh.new()
				m.radius = 0.24
				m.height = 0.3
				var mi := MeshInstance3D.new()
				mi.mesh = m
				mi.material_override = ItemVisuals.material(Color(0.55, 0.52, 0.46))
				mi.position = pos
				mi.scale = Vector3(1.2, 0.75, 1.0)
				add_child(mi)
			"seaweed":
				for i in 3:
					var c := CylinderMesh.new()
					c.top_radius = 0.015
					c.bottom_radius = 0.05
					c.height = 0.42
					var ci := MeshInstance3D.new()
					ci.mesh = c
					ci.material_override = ItemVisuals.material(Color(0.24, 0.47, 0.28))
					ci.position = pos + Vector3(-0.12 + i * 0.12, 0.2, (i % 2) * 0.1)
					ci.rotation_degrees = Vector3(6 - i * 5, 0, -10 + i * 9)
					add_child(ci)
			"shell":
				var sh := SphereMesh.new()
				sh.radius = 0.1
				sh.height = 0.08
				var shi := MeshInstance3D.new()
				shi.mesh = sh
				shi.material_override = ItemVisuals.material(Color(0.95, 0.88, 0.79))
				shi.position = pos
				shi.scale = Vector3(1.1, 1.0, 0.7)
				add_child(shi)
			"starfish":
				var st := SphereMesh.new()
				st.radius = 0.13
				st.height = 0.06
				var sti := MeshInstance3D.new()
				sti.mesh = st
				sti.material_override = ItemVisuals.material(Color(0.86, 0.45, 0.33))
				sti.position = pos
				sti.scale = Vector3(1.3, 1.0, 1.3)
				add_child(sti)


func _decor_color(seed: int) -> Color:
	var palette := [
		Color(0.90, 0.36, 0.32), Color(0.28, 0.60, 0.78),
		Color(0.95, 0.76, 0.30), Color(0.45, 0.72, 0.42),
	]
	return palette[seed % palette.size()]


## Pared invisible para los props grandes: el jugador los rodea en vez de
## atravesarlos (las palmeras y la torre se ven sólidos).
func _decor_collider(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(shape)
	body.position = pos
	colliders.add_child(body)


## Palmera: tronco en cuatro tramos inclinados, corona de seis hojas y cocos.
func _palm(pos: Vector3) -> void:
	var lean := Vector3(0.13, 0.0, 0.04)
	for i in 4:
		var seg := CylinderMesh.new()
		seg.top_radius = 0.075 - 0.008 * i
		seg.bottom_radius = 0.092 - 0.008 * i
		seg.height = 0.34
		seg.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = seg
		mi.material_override = ItemVisuals.material(
			Color(0.52, 0.38, 0.24).lightened(0.03 * float(i)))
		mi.position = pos + lean * float(i) + Vector3(0, 0.17 + 0.34 * i, 0)
		mi.rotation_degrees = Vector3(0, 0, -7.0 - 2.0 * i)
		add_child(mi)

	var top := pos + lean * 3.0 + Vector3(0, 1.38, 0)
	for i in 6:
		var leaf := BoxMesh.new()
		leaf.size = Vector3(0.64, 0.03, 0.19)
		var lm := MeshInstance3D.new()
		lm.mesh = leaf
		lm.material_override = ItemVisuals.material(
			Color(0.20, 0.52, 0.28).lightened(0.035 * float(i % 3)))
		var a := TAU * float(i) / 6.0
		lm.position = top + Vector3(cos(a) * 0.27, -0.03 * (i % 2), sin(a) * 0.27)
		lm.rotation = Vector3(0, -a, deg_to_rad(-16.0))
		add_child(lm)
	for i in 2:
		var coco := SphereMesh.new()
		coco.radius = 0.07
		coco.height = 0.14
		var cm := MeshInstance3D.new()
		cm.mesh = coco
		cm.material_override = ItemVisuals.material(Color(0.36, 0.28, 0.16))
		cm.position = top + Vector3(-0.06 + 0.12 * i, -0.09, 0.05)
		add_child(cm)


## Sombrilla con toalla. El toldo lleva varillas: un cono liso desde la cámara
## alta se lee como un hongo.
func _umbrella(pos: Vector3, color: Color) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.030
	pole.bottom_radius = 0.034
	pole.height = 1.05
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = ItemVisuals.material(Color(0.92, 0.92, 0.90))
	pm.position = pos + Vector3(0, 0.52, 0)
	add_child(pm)

	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.03
	canopy.bottom_radius = 0.46
	canopy.height = 0.22
	canopy.radial_segments = 12
	var cm := MeshInstance3D.new()
	cm.mesh = canopy
	cm.material_override = ItemVisuals.material(color)
	cm.position = pos + Vector3(0, 1.06, 0)
	cm.rotation_degrees = Vector3(5, 0, -6)
	add_child(cm)

	# varillas y punta: es lo que lo hace leer como sombrilla
	var rib_mat := ItemVisuals.material(color.darkened(0.22))
	for i in 8:
		var a := TAU * float(i) / 8.0
		var rib := BoxMesh.new()
		rib.size = Vector3(0.44, 0.018, 0.022)
		var rm := MeshInstance3D.new()
		rm.mesh = rib
		rm.material_override = rib_mat
		rm.position = pos + Vector3(cos(a) * 0.23, 1.05, sin(a) * 0.23)
		rm.rotation = Vector3(0, -a, deg_to_rad(-6.0))
		add_child(rm)

	var tip := SphereMesh.new()
	tip.radius = 0.045
	tip.height = 0.09
	var tm2 := MeshInstance3D.new()
	tm2.mesh = tip
	tm2.material_override = ItemVisuals.material(color.darkened(0.30))
	tm2.position = pos + Vector3(0, 1.19, 0)
	add_child(tm2)

	var towel := BoxMesh.new()
	towel.size = Vector3(0.56, 0.02, 1.05)
	var tm := MeshInstance3D.new()
	tm.mesh = towel
	tm.material_override = ItemVisuals.material(color.lightened(0.34))
	tm.position = pos + Vector3(0.48, 0.015, 0.10)
	tm.rotation_degrees = Vector3(0, 10, 0)
	add_child(tm)

	for i in 2:
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.10, 0.021, 1.05)
		var sm := MeshInstance3D.new()
		sm.mesh = stripe
		sm.material_override = ItemVisuals.material(Color(0.97, 0.97, 0.95))
		sm.position = pos + Vector3(0.38 + 0.20 * i, 0.018, 0.10)
		sm.rotation_degrees = Vector3(0, 10, 0)
		add_child(sm)


## Torre del guardavidas: patas, plataforma, caseta con ventana, techo a cuatro
## aguas (cono de 4 caras), escalera y bandera.
func _tower(pos: Vector3) -> void:
	var wood := Color(0.56, 0.40, 0.26)
	for dx in [-0.40, 0.40]:
		for dz in [-0.40, 0.40]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.045
			leg.bottom_radius = 0.055
			leg.height = 1.10
			var lm := MeshInstance3D.new()
			lm.mesh = leg
			lm.material_override = ItemVisuals.material(wood)
			lm.position = pos + Vector3(dx, 0.55, dz)
			add_child(lm)

	_box_mesh(Vector3(1.02, 0.08, 1.02), Color(0.62, 0.45, 0.28), pos + Vector3(0, 1.14, 0))
	# caseta: blanca con zócalo y ventana al mar
	_box_mesh(Vector3(0.74, 0.66, 0.74), Color(0.96, 0.96, 0.93), pos + Vector3(0, 1.51, 0))
	_box_mesh(Vector3(0.78, 0.10, 0.78), Color(0.86, 0.30, 0.24), pos + Vector3(0, 1.22, 0))
	_box_mesh(Vector3(0.52, 0.26, 0.02), Color(0.16, 0.26, 0.34), pos + Vector3(0, 1.58, -0.375))

	# techo a cuatro aguas: cono de 4 caras girado 45°
	var roof := CylinderMesh.new()
	roof.top_radius = 0.03
	roof.bottom_radius = 0.80
	roof.height = 0.30
	roof.radial_segments = 4
	var rm := MeshInstance3D.new()
	rm.mesh = roof
	rm.material_override = ItemVisuals.material(Color(0.86, 0.30, 0.24))
	rm.position = pos + Vector3(0, 1.99, 0)
	rm.rotation_degrees = Vector3(0, 45, 0)
	add_child(rm)

	# escalera
	for i in 4:
		_box_mesh(Vector3(0.30, 0.03, 0.03), wood, pos + Vector3(0.0, 0.24 + i * 0.26, 0.56))

	# mástil y bandera
	var mast := CylinderMesh.new()
	mast.top_radius = 0.014
	mast.bottom_radius = 0.014
	mast.height = 0.62
	var mm := MeshInstance3D.new()
	mm.mesh = mast
	mm.material_override = ItemVisuals.material(Color(0.88, 0.88, 0.86))
	mm.position = pos + Vector3(0.34, 2.36, 0)
	add_child(mm)
	_box_mesh(Vector3(0.30, 0.17, 0.02), Color(0.90, 0.24, 0.20), pos + Vector3(0.51, 2.54, 0))


## Muelle de tablas sobre el agua: da un punto de referencia en la orilla.
func _pier(cx: int, from_y: int, to_y: int) -> void:
	for y in range(from_y, to_y + 1):
		var z := float(y) + 0.5
		_box_mesh(Vector3(1.10, 0.06, 1.0), Color(0.62, 0.47, 0.30),
			Vector3(cx + 0.5, 0.34, z))
		_box_mesh(Vector3(1.10, 0.008, 0.03), Color(0.42, 0.31, 0.20),
			Vector3(cx + 0.5, 0.373, z + 0.44))
		for sx in [-0.50, 0.50]:
			var post := CylinderMesh.new()
			post.top_radius = 0.05
			post.bottom_radius = 0.055
			post.height = 0.80
			var pm := MeshInstance3D.new()
			pm.mesh = post
			pm.material_override = ItemVisuals.material(Color(0.42, 0.31, 0.20))
			pm.position = Vector3(cx + 0.5 + sx, 0.10, z)
			add_child(pm)


func _build_visual(t: CellData) -> void:
	match t.kind:
		"water":
			# se mira el MAPA, no `tiles`: durante el build la fila de abajo
			# todavía no existe
			var shallow := t.y == 0 or String(map[t.y - 1])[t.x] != "~"
			# la primera fila es turquesa (baja) y el resto azul profundo:
			# el degradé es lo que hace que se lea como mar y no como piso
			var wcol: Color = Color(0.19, 0.60, 0.73) if shallow else COLORS["ocean"]
			var wbox := BoxMesh.new()
			wbox.size = Vector3(1.0, 0.10, 1.0)
			var wm := MeshInstance3D.new()
			wm.mesh = wbox
			wm.material_override = ItemVisuals.material(wcol)
			wm.position = Vector3(t.x + 0.5, 0.05, t.y + 0.5)
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wm)
			if shallow:
				_foam(t.x, t.y)
			elif (t.x * 7 + t.y * 13) % 3 == 0:
				# crestas sueltas mar adentro (deterministas: no titilan al reiniciar)
				_wave_crest(t.x, t.y)
		"floor":
			# arena mojada donde la playa se mete al mar
			if t.y + 1 < h and String(map[t.y + 1])[t.x] == "~":
				_box_mesh(Vector3(1.0, 0.02, 0.34), Color(0.74, 0.62, 0.42),
					Vector3(t.x + 0.5, 0.013, t.y + 0.84 + 0.03 * sin(t.x * 1.3)))
		"rock":
			var box := BoxMesh.new()
			box.size = Vector3(0.96, 0.8, 0.96)
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.material_override = ItemVisuals.material(COLORS["rock"])
			mi.position = Vector3(t.x + 0.5, 0.4, t.y + 0.5)
			mi.rotation_degrees = Vector3(0, (t.x * 37 + t.y * 17) % 20 - 10, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		"station":
			_build_station(t)


## Espuma de la orilla: dos franjas (la rompiente y su estela) en la primera
## fila de agua. Sin esto el mar se lee como una plancha azul.
func _foam(x: int, y: int) -> void:
	# el serrucho de la rompiente: sin esto la orilla es una regla
	var wob := 0.035 * sin(x * 1.3) + 0.015 * sin(x * 2.9)
	_box_mesh(Vector3(1.0, 0.03, 0.16 + wob), Color(0.96, 0.99, 0.99),
		Vector3(x + 0.5, 0.115, y + 0.09 + wob * 0.5))
	_box_mesh(Vector3(1.0, 0.02, 0.06), Color(0.82, 0.94, 0.96),
		Vector3(x + 0.5, 0.105, y + 0.32 + wob))


## Cresta suelta mar adentro. La posición sale de (x,y): es decorativa pero
## estable, así el mar no "hierve" cada vez que se reconstruye el mundo.
func _wave_crest(x: int, y: int) -> void:
	var ox := float((x * 37 + y * 11) % 40) / 100.0 - 0.20
	var oz := float((x * 17 + y * 29) % 30) / 100.0 - 0.15
	_box_mesh(Vector3(0.42, 0.02, 0.06), Color(0.45, 0.79, 0.88),
		Vector3(x + 0.5 + ox, 0.105, y + 0.5 + oz))


func _build_station(t: CellData) -> void:
	var height := float(GameConfig.STATION_HEIGHT.get(t.station, 0.7))
	var color: Color = GameConfig.STATION_COLOR.get(t.station, Color(0.5, 0.5, 0.5))
	if t.station == "bin":
		color = GameConfig.BIN_COLOR.get(t.bin, color)

	var box := BoxMesh.new()
	box.size = Vector3(0.94, height, 0.94)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = ItemVisuals.material(color)
	mi.position = Vector3(t.x + 0.5, height * 0.5, t.y + 0.5)
	add_child(mi)

	if t.station == "bin":
		# boca abierta: hueco oscuro + borde claro (la bolsa se cuelga ahí)
		var hole := BoxMesh.new()
		hole.size = Vector3(0.70, 0.03, 0.70)
		var hm := MeshInstance3D.new()
		hm.mesh = hole
		hm.material_override = ItemVisuals.material(Color(0.10, 0.13, 0.12))
		hm.position = Vector3(t.x + 0.5, height + 0.005, t.y + 0.5)
		hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hm)
		var rim_mat := ItemVisuals.material(color.lightened(0.35))
		for off in [Vector3(0, 0, 0.40), Vector3(0, 0, -0.40), Vector3(0.40, 0, 0), Vector3(-0.40, 0, 0)]:
			var rim := BoxMesh.new()
			rim.size = Vector3(0.14 if off.x != 0 else 0.94, 0.07, 0.14 if off.z != 0 else 0.94)
			var rm := MeshInstance3D.new()
			rm.mesh = rim
			rm.material_override = rim_mat
			rm.position = Vector3(t.x + 0.5, height + 0.03, t.y + 0.5) + off
			rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rm)
	else:
		# tapa clara: se lee de un vistazo qué es cada estación
		var top := BoxMesh.new()
		top.size = Vector3(0.86, 0.06, 0.86)
		var tm := MeshInstance3D.new()
		tm.mesh = top
		tm.material_override = ItemVisuals.material(color.lightened(0.22))
		tm.position = Vector3(t.x + 0.5, height + 0.02, t.y + 0.5)
		add_child(tm)

	if t.station == "bags":
		# bolsas de muestra apiladas en el dispensador
		for i in 3:
			var b := BoxMesh.new()
			b.size = Vector3(0.22, 0.20, 0.16)
			var bm := MeshInstance3D.new()
			bm.mesh = b
			bm.material_override = ItemVisuals.material(Color(0.91, 0.96, 1.0))
			bm.position = Vector3(t.x + 0.5, height + 0.12 + i * 0.02, t.y + 0.5) + Vector3(-0.18 + i * 0.18, 0, (i % 2) * 0.12 - 0.06)
			bm.rotation_degrees = Vector3(0, i * 14.0, 0)
			add_child(bm)

	# el camión se dibuja UNA vez por tramo de `D` (si no, salen dos pegados)
	if t.station == "delivery" and (t.x == 0 or String(map[t.y])[t.x - 1] != t.ch):
		_build_truck(t)

	# una sola etiqueta por tramo continuo (si no, "ENTREGAENTREGA").
	# Se mira el mapa de texto: `tiles` todavía se está construyendo.
	if t.x > 0 and String(map[t.y])[t.x - 1] == t.ch:
		return

	var label_text: String = GameConfig.STATION_LABEL.get(t.station, "")
	if t.station == "bin":
		label_text = String(GameConfig.BIN_LABEL.get(t.bin, "CONTENEDOR"))
	if label_text == "":
		return

	var label := Label3D.new()
	label.text = label_text
	label.font_size = 42
	label.pixel_size = 0.0055
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 14
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.modulate = Color(1, 1, 1)
	label.position = Vector3(t.x + 0.5, height + 0.52, t.y + 0.5)
	add_child(label)


## Camión de la entrega: chasis, cabina adelante, caja atrás y cuatro ruedas.
## Se dibuja UNA vez por tramo de `D`: si no, aparecen dos camiones pegados.
func _build_truck(t: CellData) -> void:
	var run := 1
	while t.x + run < w and String(map[t.y])[t.x + run] == t.ch:
		run += 1
	var ox := float(t.x)
	var oz := float(t.y) + 0.5
	var length := float(run)
	var base := body_y(t)
	var bed := 0.16
	var body: Color = GameConfig.STATION_COLOR["delivery"]

	_box_mesh(Vector3(length - 0.06, bed, 0.98), body.darkened(0.25),
		Vector3(ox + length * 0.5, base + bed * 0.5, oz))
	_box_mesh(Vector3(length - 0.72, 0.58, 0.94), body.lightened(0.10),
		Vector3(ox + 0.72 + (length - 0.72) * 0.5, base + bed + 0.29, oz))
	_box_mesh(Vector3(0.66, 0.70, 0.90), Color(0.86, 0.42, 0.22),
		Vector3(ox + 0.36, base + bed + 0.35, oz))
	# parabrisas: desde el aire es lo que dice "esto es un camión"
	_box_mesh(Vector3(0.52, 0.05, 0.72), Color(0.16, 0.24, 0.32),
		Vector3(ox + 0.36, base + bed + 0.71, oz))

	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.17
	wheel.bottom_radius = 0.17
	wheel.height = 0.10
	wheel.radial_segments = 12
	for wx in [ox + 0.42, ox + length - 0.44]:
		for side in [-1.0, 1.0]:
			var wm := MeshInstance3D.new()
			wm.mesh = wheel
			wm.material_override = ItemVisuals.material(Color(0.10, 0.10, 0.11))
			wm.position = Vector3(wx, 0.17, oz + side * 0.48)
			wm.rotation_degrees = Vector3(90, 0, 0)
			add_child(wm)


## Altura de la base de una estación (el camión se apoya arriba).
func body_y(t: CellData) -> float:
	return float(GameConfig.STATION_HEIGHT.get(t.station, 0.7))


func _box_mesh(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = ItemVisuals.material(color)
	mi.position = pos
	add_child(mi)
	return mi


func _build_collider(t: CellData) -> void:
	# Todos los sólidos llevan una pared ALTA: con la altura real (0.55 a 0.95)
	# la cápsula del jugador se trepaba al borde y quedaba "encima de todo".
	# La altura visual la da el mesh; el collider es una pared invisible.
	# el agua es un escalón bajo: frena al jugador pero deja flotar la basura;
	# el resto de los sólidos son paredes altas (la cápsula se trepaba encima)
	var height := 0.20 if t.kind == "water" else 2.0

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, height, 1.0)
	shape.shape = box
	shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(shape)
	body.position = Vector3(t.x + 0.5, 0, t.y + 0.5)
	colliders.add_child(body)
