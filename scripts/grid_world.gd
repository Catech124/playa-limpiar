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


# ------------------------------------------------------------------ consultas
func tile_at(x: int, y: int) -> CellData:
	if x < 0 or y < 0 or x >= w or y >= h:
		return null
	return tiles[y][x]


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
	return Vector3(tile.x + 0.5, tile.top_y() + 0.02, tile.y + 0.5)


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
		"P":
			_set_station(t, "pile", ["pet"])
		"L":
			_set_station(t, "pile", ["lata"])
		"Q":
			_set_station(t, "pile", ["vidrio"])
		"T":
			_set_station(t, "sort")
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
		"W":
			_set_station(t, "wash")
		"D":
			_set_station(t, "delivery")
		"R":
			_set_station(t, "return")
		"=":
			_set_station(t, "counter")
		_:
			push_warning("Carácter de mapa desconocido: %s (%d,%d)" % [ch, x, y])
			t.kind = "floor"
	return t


func _set_station(t: CellData, station: String, pool: Array = []) -> void:
	t.kind = "station"
	t.station = station
	t.pool = pool


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
	_build_decor()

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
		var pos := Vector3(d[0] + 0.5, 0.02, d[1] + 0.5)
		match kind:
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


func _build_visual(t: CellData) -> void:
	match t.kind:
		"water":
			var wbox := BoxMesh.new()
			wbox.size = Vector3(1.0, 0.06, 1.0)
			var wm := MeshInstance3D.new()
			wm.mesh = wbox
			wm.material_override = ItemVisuals.material(COLORS["ocean"])
			wm.position = Vector3(t.x + 0.5, 0.03, t.y + 0.5)
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wm)
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

	# tapa clara: se lee de un vistazo qué es cada estación
	var top := BoxMesh.new()
	top.size = Vector3(0.86, 0.06, 0.86)
	var tm := MeshInstance3D.new()
	tm.mesh = top
	tm.material_override = ItemVisuals.material(color.lightened(0.22))
	tm.position = Vector3(t.x + 0.5, height + 0.02, t.y + 0.5)
	add_child(tm)

	if t.station == "pile":
		# residuos de muestra encima del montón
		for i in t.pool.size():
			var dot := SphereMesh.new()
			dot.radius = 0.09
			dot.height = 0.18
			var dm := MeshInstance3D.new()
			dm.mesh = dot
			dm.material_override = ItemVisuals.material(GameConfig.RESIDUES[t.pool[i]]["color"])
			dm.position = Vector3(t.x + 0.5, height + 0.1, t.y + 0.5)
			add_child(dm)

	# una sola etiqueta por tramo continuo (si no, "ENTREGAENTREGA").
	# Se mira el mapa de texto: `tiles` todavía se está construyendo.
	if t.x > 0 and String(map[t.y])[t.x - 1] == t.ch:
		return

	var label_text: String = GameConfig.STATION_LABEL.get(t.station, "")
	if t.station == "bin":
		label_text = GameConfig.BIN_LABEL.get(t.bin, "CONTENEDOR")
	if t.station == "pile" and not t.pool.is_empty():
		label_text = String(GameConfig.RESIDUES[t.pool[0]]["label"])
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
	label.position = Vector3(t.x + 0.5, height + 0.46, t.y + 0.5)
	add_child(label)


func _build_collider(t: CellData) -> void:
	# Todos los sólidos llevan una pared ALTA: con la altura real (0.55 a 0.95)
	# la cápsula del jugador se trepaba al borde y quedaba "encima de todo".
	# La altura visual la da el mesh; el collider es una pared invisible.
	var height := 2.0

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, height, 1.0)
	shape.shape = box
	shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(shape)
	body.position = Vector3(t.x + 0.5, 0, t.y + 0.5)
	colliders.add_child(body)
