# ════════════════════════════════════════════════════════════════════
#  PLAYA LIMPIA · CharModel · parche de proporciones "chibi / juguete"
#  Pegar dentro de scripts/char_model.gd (reemplaza las funciones
#  _build_legs, _build_torso, _build_arms, _build_head, _build_hair,
#  _build_face y _build_hat, y el valor de HAND_CARRY).
#  Asume: _mesh(parent, mesh, color, pos) -> MeshInstance3D (con contorno).
# ════════════════════════════════════════════════════════════════════
 
# ── Paleta ──────────────────────────────────────────────────────────
const C_SKIN     := Color("#F5BF99")
const C_SKIN_D   := Color("#E7A47F")   # nariz
const C_CHEEK    := Color("#F0968A")
const C_WHITE    := Color("#F4F4EF")   # remera / esclerótica / tiras
const C_NAVY     := Color("#243366")
const C_STRAW    := Color("#CCA87B")
const C_STRAW_L  := Color("#DBBC8B")   # copa, un poco más clara que el ala
const C_STRAW_D  := Color("#A8824F")   # borde del ala
const C_HAIR     := Color("#613B21")
const C_HAIR_L   := Color("#764B2A")   # rizos alternos
const C_BROW     := Color("#45270F")
const C_IRIS     := Color("#6B4529")
const C_GLOVE    := Color("#8C613D")
const C_SANDAL   := Color("#5285D1")
const C_MOUTH    := Color("#6E2F26")
 
# ── Layout (unidades de mundo; pies en y = 0) ──────────────────────
const SIDE_L := -1.0                   # lado X de arm_l / leg_l (si lo tenías al revés: 1.0)
const LEG_X := 0.075
const LEG_PIVOT_Y := 0.200
const TORSO_Y0 := 0.272
const TORSO_Y1 := 0.508
const TORSO_R0 := 0.182
const TORSO_R1 := 0.152
const ARM_X := 0.165
const ARM_Y := 0.452
const ARM_SPLAY_DEG := 16.0            # los brazos cuelgan abiertos hacia afuera
const HEAD_HINGE_Y := 0.520
const HEAD_C := Vector3(0.0, 0.180, 0.0)       # centro cabeza, relativo a la bisagra
const HEAD_RAD := Vector3(0.207, 0.185, 0.195) # elipsoide: más ancho que alto
const HAT_Y := 0.150                   # altura del ala sobre el centro de la cabeza
const HAT_TILT_DEG := 14.0             # inclinación hacia atrás: levanta el ala delantera
const BRIM_R := 0.300
const HAT_Z := -0.025                  # sombrero corrido hacia atrás: deja ver la frente
const BRIM_Z_SQUASH := 0.84            # ala elíptica: menos saliente al frente/atrás
 
# Mano al cargar: hinge (0.452) + brazo 0.165 a ~-60° + el mismo offset objeto↔mano que tenías.
const HAND_CARRY := Vector3(0.0, 0.330, 0.195)
 
# ── Helpers de geometría ───────────────────────────────────────────
static func _sph(r: float, seg := 18, rings := 10) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m
 
static func _cyl(r_top: float, r_bot: float, h: float, seg := 18) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m
 
static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 3
	return m
 
static func _tor(inner: float, outer: float, ring_seg := 24, tube_seg := 8) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = ring_seg
	m.ring_segments = tube_seg
	return m
 
# Detalle sin contorno (pupila, brillo, mejillas, boca): el contorno los ensucia.
static func _flat(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
 
# Punto sobre la superficie de la cabeza (elipsoide) en yaw/pitch, + lift hacia afuera.
static func _dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
 
static func _head_pt(yaw_deg: float, pitch_deg: float, lift := 0.0) -> Vector3:
	var d := _dir(yaw_deg, pitch_deg)
	return HEAD_C + Vector3(d.x * HEAD_RAD.x, d.y * HEAD_RAD.y, d.z * HEAD_RAD.z) + d * lift
 
# Base cuyo +Z apunta hacia afuera de la cabeza en esa dirección.
static func _face_basis(yaw_deg: float, pitch_deg: float) -> Basis:
	return Basis.looking_at(-_dir(yaw_deg, pitch_deg), Vector3.UP)
 
# ════════════════════════════════════════════════════════════════════
#  PIERNAS  (leg_l / leg_r, bisagra en la cadera, rotan en X)
# ════════════════════════════════════════════════════════════════════
static func _build_legs(root: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "leg_l" if s == SIDE_L else "leg_r"
		leg.position = Vector3(s * LEG_X, LEG_PIVOT_Y, 0.0)
		root.add_child(leg)
		# pierna (la parte alta queda tapada por el short)
		_mesh(leg, _cyl(0.056, 0.060, 0.170, 14), C_SKIN, Vector3(0, -0.085, 0))
		# empeine de piel
		var foot := _mesh(leg, _sph(0.058, 14, 8), C_SKIN, Vector3(0, -0.158, 0.030))
		foot.scale = Vector3(1.0, 0.58, 1.45)
		# suela azul, óvalo plano más ancho que la pierna
		var sole := _mesh(leg, _cyl(0.072, 0.072, 0.026, 16), C_SANDAL, Vector3(0, -0.187, 0.028))
		sole.scale = Vector3(1.0, 1.0, 1.42)
		# tira blanca en Y: aro sobre el empeine + poste hacia los dedos
		var strap := _mesh(leg, _tor(0.050, 0.070, 18, 8), C_WHITE)
		strap.transform = Transform3D(
			Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 0.55)),
			Vector3(0, -0.158, 0.040))
		_mesh(leg, BoxMesh.new(), C_WHITE, Vector3(0, -0.141, 0.086)).scale = Vector3(0.024, 0.022, 0.050)
 
# ════════════════════════════════════════════════════════════════════
#  TORSO + SHORT  (remera con 4 bandas blancas y 3 azules)
# ════════════════════════════════════════════════════════════════════
static func _build_torso(root: Node3D, shirt: Color) -> void:
	# short: bloque corto, apenas acampanado
	var sh := _mesh(root, _cyl(0.168, 0.188, 0.130, 20), C_NAVY, Vector3(0, 0.225, 0))
	sh.scale = Vector3(1.0, 1.0, 0.88)
	# bandas: 4 blancas (0.040) + 3 de color (el resto), de abajo hacia arriba
	var total := TORSO_Y1 - TORSO_Y0
	var h_white := 0.040
	var h_col := (total - 4.0 * h_white) / 3.0
	var y := TORSO_Y0
	for i in 7:
		var is_col := i % 2 == 1
		var h := h_col if is_col else h_white
		var r0 := lerpf(TORSO_R0, TORSO_R1, (y - TORSO_Y0) / total)
		var r1 := lerpf(TORSO_R0, TORSO_R1, (y + h - TORSO_Y0) / total)
		var band := _mesh(root, _cyl(r1, r0, h, 20), shirt if is_col else C_WHITE, Vector3(0, y + h * 0.5, 0))
		band.scale = Vector3(1.0, 1.0, 0.88)
		y += h
	# hombros redondeados (tapa el disco plano de arriba)
	var dome := _mesh(root, _sph(TORSO_R1, 20, 8), C_WHITE, Vector3(0, TORSO_Y1, 0))
	dome.scale = Vector3(1.0, 0.34, 0.88)
 
# ════════════════════════════════════════════════════════════════════
#  BRAZOS  (arm_l / arm_r, bisagra en el hombro, rotan en X)
# ════════════════════════════════════════════════════════════════════
static func _build_arms(root: Node3D, shirt: Color) -> void:
	for s: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "arm_l" if s == SIDE_L else "arm_r"
		arm.position = Vector3(s * ARM_X, ARM_Y, 0.0)
		root.add_child(arm)
		# "splay" va DENTRO de la bisagra: la animación sigue rotando solo arm_* en X
		var splay := Node3D.new()
		splay.name = "splay"
		splay.rotation.z = s * deg_to_rad(ARM_SPLAY_DEG)
		arm.add_child(splay)
		_mesh(splay, _sph(0.066, 14, 8), C_WHITE)                                          # hombro
		_mesh(splay, _cyl(0.061, 0.064, 0.060, 14), C_WHITE, Vector3(0, -0.040, 0))        # manga
		_mesh(splay, _cyl(0.058, 0.061, 0.026, 14), shirt, Vector3(0, -0.075, 0))          # puño con color
		_mesh(splay, _cyl(0.040, 0.042, 0.050, 12), C_SKIN, Vector3(0, -0.105, 0))         # antebrazo
		var glove := _mesh(splay, _sph(0.058, 14, 8), C_GLOVE, Vector3(0, -0.165, 0.004))  # guante
		glove.scale = Vector3(1.0, 0.95, 1.05)
		_mesh(splay, _sph(0.025, 10, 6), C_GLOVE, Vector3(0, -0.150, 0.050))               # pulgar
 
# ════════════════════════════════════════════════════════════════════
#  CABEZA  (devuelve el nodo "head", bisagra en y = 0.52)
# ════════════════════════════════════════════════════════════════════
static func _build_head(root: Node3D) -> Node3D:
	var head := Node3D.new()
	head.name = "head"
	head.position = Vector3(0, HEAD_HINGE_Y, 0)
	root.add_child(head)
	var skull := _mesh(head, _sph(0.195, 28, 16), C_SKIN, HEAD_C)
	skull.scale = HEAD_RAD / 0.195
	# orejas: discos chatos a los costados (asoman bajo el pelo)
	for s: float in [-1.0, 1.0]:
		var ear := _mesh(head, _sph(0.042, 10, 6), C_SKIN)
		ear.transform = Transform3D(
			_face_basis(90.0 * s, -4.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.5)),
			_head_pt(90.0 * s, -4.0, 0.0))
	return head
 
# ════════════════════════════════════════════════════════════════════
#  PELO  (masa desplazada hacia atrás + rizos en el borde)
# ════════════════════════════════════════════════════════════════════
# [yaw, pitch, radio, lift, tono]   (se espejan en X salvo yaw 0 / 180)
const CURLS_BANGS_CENTER := [0.0, 31.0, 0.056, 0.020, 1]
const CURLS_BANGS := [[19.0, 35.0, 0.053, 0.018, 0], [38.0, 30.0, 0.050, 0.016, 1]]
const CURLS_SIDE := [
	[64.0, 16.0, 0.056, 0.014, 0], [84.0, -12.0, 0.058, 0.010, 1],
	[112.0, 4.0, 0.062, 0.018, 1], [142.0, 0.0, 0.064, 0.020, 0],
	[124.0, -26.0, 0.056, 0.012, 0], [160.0, -24.0, 0.058, 0.014, 1],
]
const CURLS_BACK_CENTER := [180.0, 2.0, 0.066, 0.020, 1]
 
static func _curl(head: Node3D, c: Array) -> void:
	var m := _mesh(head, _sph(c[2], 12, 7), C_HAIR_L if c[4] == 1 else C_HAIR, _head_pt(c[0], c[1], c[3]))
	m.scale = Vector3(1.0, 0.94, 1.0)
 
static func _build_hair(head: Node3D, hat := "straw") -> void:
	# masa base: elipsoide más grande y corrido hacia atrás/arriba -> da la línea de nacimiento
	var mass := _mesh(head, _sph(0.195, 26, 14), C_HAIR, HEAD_C + Vector3(0.0, 0.016, -0.030))
	mass.scale = Vector3(1.125, 1.04, 1.06)
	if hat != "cap":                      # con gorra el flequillo atraviesa la copa
		_curl(head, CURLS_BANGS_CENTER)
		for c: Array in CURLS_BANGS:
			_curl(head, c)
			_curl(head, [-c[0], c[1], c[2], c[3], c[4]])
	for c: Array in CURLS_SIDE:
		_curl(head, c)
		_curl(head, [-c[0], c[1], c[2], c[3], c[4]])
	_curl(head, CURLS_BACK_CENTER)
 
# ════════════════════════════════════════════════════════════════════
#  CARA
# ════════════════════════════════════════════════════════════════════
static func _build_face(head: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		_build_eye(head, s)
		# ceja gruesa, el extremo externo más bajo
		var by := 17.0
		var brow := _mesh(head, _cap(0.0135, 0.092), C_BROW)
		var phi := deg_to_rad(-s * 12.0)
		brow.transform = Transform3D(
			_face_basis(27.0 * s * 0.8, by) * Basis(Vector3.BACK, phi - PI * 0.5),
			_head_pt(27.0 * s, by, 0.004))
		# cachete rosado, opaco (sin transparencia -> sin problemas de orden)
		var ch := _flat(head, _sph(0.040, 12, 6), C_CHEEK)
		ch.transform = Transform3D(
			_face_basis(42.0 * s, -17.0) * Basis.from_scale(Vector3(1.0, 0.85, 0.40)),
			_head_pt(42.0 * s, -17.0, -0.004))
	# nariz de botón
	_mesh(head, _sph(0.022, 12, 8), C_SKIN_D, _head_pt(0.0, -13.0, 0.008))
	# sonrisa: 3 cápsulas (centro + 2 comisuras levantadas)
	var mb := _face_basis(0.0, -33.0)
	var mp := _head_pt(0.0, -33.0, 0.002)
	var mid := _flat(head, _cap(0.0085, 0.050), C_MOUTH)
	mid.transform = Transform3D(mb * Basis(Vector3.BACK, -PI * 0.5), mp)
	for s: float in [-1.0, 1.0]:
		var corner := _flat(head, _cap(0.0085, 0.040), C_MOUTH)
		corner.transform = Transform3D(
			mb * Basis(Vector3.BACK, deg_to_rad(s * 35.0) - PI * 0.5),
			mp + mb * Vector3(s * 0.037, 0.007, 0.0))
 
static func _build_eye(head: Node3D, s: float) -> void:
	var yaw := 27.0 * s
	var pitch := -5.0
	var b := _face_basis(yaw * 0.6, pitch)       # el ojo mira más al frente que la normal
	var c := _head_pt(yaw, pitch, -0.002)
	var inward := -s * 0.006                      # iris corrido hacia la nariz: mirada al frente
	var sclera := _mesh(head, _sph(0.048, 18, 10), Color(0.98, 0.98, 0.96))
	sclera.transform = Transform3D(b * Basis.from_scale(Vector3(0.95, 1.08, 0.50)), c)
	var iris := _mesh(head, _sph(0.035, 14, 8), C_IRIS)
	iris.transform = Transform3D(b * Basis.from_scale(Vector3(1.0, 1.0, 0.5)), c + b * Vector3(inward, 0.0, 0.017))
	var pupil := _flat(head, _sph(0.021, 10, 6), Color(0.04, 0.03, 0.03))
	pupil.transform = Transform3D(b * Basis.from_scale(Vector3(1.0, 1.0, 0.4)), c + b * Vector3(inward, 0.0, 0.029))
	var glint := _flat(head, _sph(0.0115, 8, 5), Color.WHITE)
	glint.transform = Transform3D(b * Basis.from_scale(Vector3(1.0, 1.0, 0.5)), c + b * Vector3(inward + 0.011, 0.013, 0.034))
 
# ════════════════════════════════════════════════════════════════════
#  SOMBRERO  (nodo "hat" hijo de head; la inclinación va en un hijo)
# ════════════════════════════════════════════════════════════════════
static func _build_hat(head: Node3D, kind: String, shirt := C_NAVY) -> void:
	var hat := Node3D.new()
	hat.name = "hat"
	hat.position = HEAD_C
	head.add_child(hat)
	var tilt := Node3D.new()
	tilt.name = "tilt"
	var is_cap := kind == "cap"
	tilt.position = Vector3(0, HAT_Y, 0.0 if is_cap else HAT_Z)
	tilt.rotation.x = -deg_to_rad(4.0 if is_cap else HAT_TILT_DEG)
	hat.add_child(tilt)
	if kind == "cap":
		_build_cap(tilt, shirt)
	else:
		_build_straw(tilt)
	for n in tilt.get_children():          # sin sombra: si no, tapa la cara
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 
static func _build_straw(t: Node3D) -> void:
	# ala: tronco de cono que baja hacia el borde (caída natural), elíptica
	var brim := _mesh(t, _cyl(0.190, BRIM_R, 0.035, 30), C_STRAW)
	brim.scale = Vector3(1.0, 1.0, BRIM_Z_SQUASH)
	# borde enrollado, más oscuro: da grosor a la silueta del ala
	var rim := _mesh(t, _tor(BRIM_R - 0.011, BRIM_R + 0.011, 30, 8), C_STRAW_D, Vector3(0, -0.0115, 0))
	rim.scale = Vector3(1.0, 1.0, BRIM_Z_SQUASH)
	# copa baja y redondeada: cilindro corto + domo
	_mesh(t, _cyl(0.186, 0.200, 0.045, 24), C_STRAW_L, Vector3(0, 0.040, 0))
	var dome := _mesh(t, _sph(0.186, 24, 12), C_STRAW_L, Vector3(0, 0.0625, 0))
	dome.scale = Vector3(1.0, 0.60, 1.0)
 
static func _build_cap(t: Node3D, col: Color) -> void:
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.238
	dome_mesh.height = 0.238
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 24
	dome_mesh.rings = 10
	var dome := _mesh(t, dome_mesh, col, Vector3(0, -0.095, 0))
	dome.scale = Vector3(1.0, 0.85, 1.0)
	var visor := _mesh(t, _cyl(0.118, 0.118, 0.020, 20), col.darkened(0.15))
	visor.transform = Transform3D(Basis(Vector3.RIGHT, 0.30), Vector3(0, -0.088, 0.225))
	_mesh(t, _sph(0.022, 10, 6), col.darkened(0.15), Vector3(0, 0.102, 0))
 
Contenido