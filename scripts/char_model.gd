class_name CharModel
extends RefCounted
## Personaje jugable y NPC, armado con primitivas (sin GLB).
##
## Forma buscada (estilo Overcooked):
##   · torso = trapecio invertido con bordes redondeados (ancho arriba, angosto
##     abajo) y casquete de hombros.
##   · brazos = cilindros que nacen DENTRO del torso (la axila queda recortada
##     por el propio cuerpo) y terminan en un guante blanco.
##   · cabeza = esfera perfecta y más chica; sombrero encima.
##
## Las bisagras se llaman igual que antes (arm_l, arm_r, leg_l, leg_r, head,
## hat): la animación del jugador no cambia.

const SKIN := Color(0.90, 0.63, 0.50)
const PANTS := Color(0.22, 0.25, 0.38)
const WHITE := Color(0.96, 0.96, 0.94)
const STRAW := Color(0.85, 0.72, 0.48)
const BAND := Color(0.72, 0.31, 0.32)
const HAIR := Color(0.32, 0.20, 0.14)
const DARK := Color(0.13, 0.12, 0.14)

const HEAD_R := 0.150
const HEAD_Y := 0.505        # centro de la cabeza
const HINGE_Y := 0.385       # bisagra de la cabeza (cuello)
const SHOULDER_X := 0.150
const SHOULDER_Y := 0.285
## Punto donde quedan las manos con la pose de cargar (lo usa el jugador).
const HAND_CARRY := Vector3(0.0, 0.245, 0.205)


static func build(shirt: Color, hat := "straw") -> Node3D:
	var root := Node3D.new()
	root.name = "CharModel"

	_build_torso(root, shirt)
	_build_legs(root)
	_build_arms(root, shirt)
	_build_head(root, hat)
	return root


# ------------------------------------------------------------------ cuerpo
static func _build_torso(root: Node3D, shirt: Color) -> void:
	# trapecio invertido: más ancho en los hombros que en la cintura
	var torso := CylinderMesh.new()
	torso.top_radius = 0.090      # cuello/hombros
	torso.bottom_radius = 0.162   # se mete dentro de la panza
	torso.height = 0.24
	torso.radial_segments = 24
	_mesh(root, torso, shirt, Vector3(0, 0.285, 0))

	# hombros: casquete angosto arriba
	var shoulders := SphereMesh.new()
	shoulders.radius = 0.090
	shoulders.height = 0.18
	shoulders.radial_segments = 22
	shoulders.rings = 10
	var sm := _mesh(root, shoulders, shirt, Vector3(0, 0.330, 0))
	sm.scale = Vector3(1.0, 0.55, 1.0)

	# panza: esfera completa, la base del cuerpo es CIRCULAR y abultada
	var belly := SphereMesh.new()
	belly.radius = 0.178
	belly.height = 0.356
	belly.radial_segments = 24
	belly.rings = 14
	var bm := _mesh(root, belly, shirt, Vector3(0, 0.190, 0))
	bm.scale = Vector3(1.0, 0.72, 1.0)

	# cuello
	var neck := CylinderMesh.new()
	neck.top_radius = 0.052
	neck.bottom_radius = 0.060
	neck.height = 0.06
	neck.radial_segments = 14
	_mesh(root, neck, SKIN, Vector3(0, 0.350, 0))


static func _build_legs(root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "leg_" + tag
		pivot.position = Vector3(side * 0.062, 0.072, 0)
		root.add_child(pivot)

		var leg := CylinderMesh.new()
		leg.top_radius = 0.044
		leg.bottom_radius = 0.040
		leg.height = 0.06
		leg.radial_segments = 14
		_mesh(pivot, leg, PANTS, Vector3(0, -0.030, 0))

		# zapatilla blanca
		# pie: esfera deformada (óvalo alargado y aplastado), no un cubo
		var foot := SphereMesh.new()
		foot.radius = 0.058
		foot.height = 0.116
		foot.radial_segments = 16
		foot.rings = 9
		var fm := _mesh(pivot, foot, WHITE, Vector3(0, -0.042, 0.050))
		fm.scale = Vector3(1.0, 0.62, 1.55)
		fm.rotation_degrees = Vector3(0, side * 4.0, 0)


# ------------------------------------------------------------------ brazos
static func _build_arms(root: Node3D, shirt: Color) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "arm_" + tag
		pivot.position = Vector3(side * SHOULDER_X, SHOULDER_Y, 0)
		root.add_child(pivot)

		# El cilindro ARRANCA DENTRO del torso: la axila la recorta el cuerpo.
		var arm := CylinderMesh.new()
		arm.top_radius = 0.042
		arm.bottom_radius = 0.036
		arm.height = 0.13
		arm.radial_segments = 14
		var am := _mesh(pivot, arm, shirt, Vector3(side * 0.020, -0.058, 0))
		am.rotation_degrees = Vector3(0, 0, side * 16.0)

		# hombro: esfera que tapa la costura con el torso
		var shoulder := SphereMesh.new()
		shoulder.radius = 0.042
		shoulder.height = 0.084
		shoulder.radial_segments = 14
		shoulder.rings = 7
		_mesh(pivot, shoulder, shirt, Vector3(side * 0.010, -0.010, 0))

		# guante blanco al final del brazo
		var glove := SphereMesh.new()
		glove.radius = 0.046
		glove.height = 0.098
		glove.radial_segments = 14
		glove.rings = 8
		var gm := _mesh(pivot, glove, WHITE, Vector3(side * 0.046, -0.132, 0))
		gm.scale = Vector3(1.0, 1.05, 1.0)


# ------------------------------------------------------------------ cabeza
static func _build_head(root: Node3D, hat: String) -> void:
	var pivot := Node3D.new()
	pivot.name = "head"
	pivot.position = Vector3(0, HINGE_Y, 0)
	root.add_child(pivot)

	var local_head_y := HEAD_Y - HINGE_Y

	# esfera PERFECTA y más chica
	var skull := SphereMesh.new()
	skull.radius = HEAD_R
	skull.height = HEAD_R * 2.0
	skull.radial_segments = 22
	skull.rings = 12
	_mesh(pivot, skull, SKIN, Vector3(0, local_head_y, 0))

	_build_face(pivot, local_head_y)
	_build_hat(root, pivot, local_head_y, hat)


static func _build_face(pivot: Node3D, hy: float) -> void:
	# Dos círculos negros grandes, APOYADOS en la esfera: nada de esferas que
	# sobresalen (antes parecían ojos saltones pegados).
	var eye_r := 0.040
	for side in [-1.0, 1.0]:
		var ex: float = float(side) * 0.056
		var ey := 0.020
		var ez: float = sqrt(maxf(0.0, HEAD_R * HEAD_R - ex * ex - ey * ey)) + 0.004
		var eye := CylinderMesh.new()
		eye.top_radius = eye_r
		eye.bottom_radius = eye_r
		eye.height = 0.012
		eye.radial_segments = 20
		var em := MeshInstance3D.new()
		em.mesh = eye
		em.material_override = ItemVisuals.material(DARK)
		em.position = Vector3(ex, hy + ey, ez)
		em.rotation_degrees = Vector3(90, 0, 0)   # el disco mira a +Z
		em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(em)

	# sonrisa fina
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.076, 0.012, 0.012)
	var mm := MeshInstance3D.new()
	mm.mesh = mouth
	mm.material_override = ItemVisuals.material(Color(0.42, 0.18, 0.17))
	mm.position = Vector3(0.0, hy - 0.078, sqrt(HEAD_R * HEAD_R - 0.0061) + 0.002)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mm)


static func _build_hat(root: Node3D, head: Node3D, hy: float, kind: String) -> void:
	if kind == "none":
		return
	var pivot := Node3D.new()
	pivot.name = "hat"
	pivot.position = Vector3(0, HINGE_Y, 0)
	root.add_child(pivot)

	var top := hy + HEAD_R
	if kind == "cap":
		# gorrita: casquete pegado al cráneo + visera
		var cap := SphereMesh.new()
		cap.radius = HEAD_R * 1.02
		cap.height = HEAD_R * 2.0
		cap.radial_segments = 18
		cap.rings = 10
		var cm := _mesh(pivot, cap, Color(0.35, 0.55, 0.85), Vector3(0, hy + 0.010, 0))
		cm.scale = Vector3(1.0, 0.62, 1.0)
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var brim := BoxMesh.new()
		brim.size = Vector3(0.22, 0.020, 0.13)
		var bm := _mesh(pivot, brim, Color(0.28, 0.45, 0.72), Vector3(0, hy + 0.060, 0.150))
		bm.rotation_degrees = Vector3(-8, 0, 0)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return

	# sombrero de paja: ala + copa + banda
	var brim := CylinderMesh.new()
	brim.top_radius = 0.185
	brim.bottom_radius = 0.195
	brim.height = 0.026
	brim.radial_segments = 24
	var brim_m := _mesh(pivot, brim, STRAW, Vector3(0, top - 0.026, 0))
	brim_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var crown := CylinderMesh.new()
	crown.top_radius = 0.098
	crown.bottom_radius = 0.112
	crown.height = 0.105
	crown.radial_segments = 24
	var crown_m := _mesh(pivot, crown, STRAW.lightened(0.04), Vector3(0, top + 0.024, 0))
	crown_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var band := CylinderMesh.new()
	band.top_radius = 0.113
	band.bottom_radius = 0.117
	band.height = 0.028
	band.radial_segments = 24
	var band_m := _mesh(pivot, band, BAND, Vector3(0, top - 0.016, 0))
	band_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ util
## Contorno por casco invertido: la firma del look low-poly.
static func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3,
		metallic := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ItemVisuals.material(color, metallic)
	var outline := StandardMaterial3D.new()
	outline.albedo_color = Color(0.05, 0.05, 0.06)
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.010
	mat.next_pass = outline
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
