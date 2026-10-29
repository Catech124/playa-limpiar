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

const HEAD_R := 0.165
const HEAD_Y := 0.760        # centro de la cabeza
const HINGE_Y := 0.620       # bisagra de la cabeza (cuello)
const SHOULDER_X := 0.196
const SHOULDER_Y := 0.530


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
	torso.top_radius = 0.200
	torso.bottom_radius = 0.145
	torso.height = 0.36
	torso.radial_segments = 24
	_mesh(root, torso, shirt, Vector3(0, 0.38, 0))

	# casquete de hombros (redondea el borde de arriba)
	var shoulders := SphereMesh.new()
	shoulders.radius = 0.200
	shoulders.height = 0.40
	shoulders.radial_segments = 24
	shoulders.rings = 12
	var sm := _mesh(root, shoulders, shirt, Vector3(0, 0.560, 0))
	sm.scale = Vector3(1.0, 0.42, 1.0)

	# ruedo redondeado abajo
	var hem := SphereMesh.new()
	hem.radius = 0.145
	hem.height = 0.29
	hem.radial_segments = 20
	hem.rings = 10
	var hm := _mesh(root, hem, shirt.darkened(0.05), Vector3(0, 0.200, 0))
	hm.scale = Vector3(1.0, 0.36, 1.0)

	# cuello
	var neck := CylinderMesh.new()
	neck.top_radius = 0.072
	neck.bottom_radius = 0.082
	neck.height = 0.10
	neck.radial_segments = 14
	_mesh(root, neck, SKIN, Vector3(0, 0.610, 0))


static func _build_legs(root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "leg_" + tag
		pivot.position = Vector3(side * 0.070, 0.190, 0)
		root.add_child(pivot)

		var leg := CylinderMesh.new()
		leg.top_radius = 0.062
		leg.bottom_radius = 0.056
		leg.height = 0.17
		leg.radial_segments = 14
		_mesh(pivot, leg, PANTS, Vector3(0, -0.085, 0))

		# zapatilla blanca
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.125, 0.075, 0.200)
		var sm := _mesh(pivot, shoe, WHITE, Vector3(0, -0.185, 0.028))
		sm.rotation_degrees = Vector3(0, side * 4.0, 0)
		# suela
		var sole := BoxMesh.new()
		sole.size = Vector3(0.130, 0.030, 0.205)
		_mesh(pivot, sole, WHITE.darkened(0.12), Vector3(0, -0.214, 0.028))


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
		arm.top_radius = 0.058
		arm.bottom_radius = 0.050
		arm.height = 0.30
		arm.radial_segments = 14
		var am := _mesh(pivot, arm, shirt, Vector3(side * 0.030, -0.130, 0))
		am.rotation_degrees = Vector3(0, 0, side * 7.0)

		# hombro: esfera que tapa la costura con el torso
		var shoulder := SphereMesh.new()
		shoulder.radius = 0.070
		shoulder.height = 0.14
		shoulder.radial_segments = 14
		shoulder.rings = 7
		_mesh(pivot, shoulder, shirt, Vector3(side * 0.012, -0.012, 0))

		# guante blanco al final del brazo
		var glove := SphereMesh.new()
		glove.radius = 0.072
		glove.height = 0.150
		glove.radial_segments = 14
		glove.rings = 8
		var gm := _mesh(pivot, glove, WHITE, Vector3(side * 0.050, -0.312, 0))
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
	var z_eye := 0.150
	for side in [-1.0, 1.0]:
		# ojo: esclerótica blanca + pupila + brillo
		var eye := SphereMesh.new()
		eye.radius = 0.042
		eye.height = 0.084
		eye.radial_segments = 12
		eye.rings = 6
		var em := _mesh(pivot, eye, WHITE, Vector3(side * 0.068, hy + 0.022, z_eye))
		em.scale = Vector3(1.0, 1.10, 0.55)

		var pupil := SphereMesh.new()
		pupil.radius = 0.023
		pupil.height = 0.046
		pupil.radial_segments = 10
		pupil.rings = 5
		var pm := _mesh(pivot, pupil, DARK, Vector3(side * 0.068, hy + 0.020, z_eye + 0.026))
		pm.scale = Vector3(1.0, 1.15, 0.5)

		var glint := SphereMesh.new()
		glint.radius = 0.008
		glint.height = 0.016
		var gm := _mesh(pivot, glint, WHITE, Vector3(side * 0.062, hy + 0.034, z_eye + 0.040))
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# ceja
		var brow := BoxMesh.new()
		brow.size = Vector3(0.072, 0.020, 0.020)
		var bm := _mesh(pivot, brow, HAIR, Vector3(side * 0.070, hy + 0.088, z_eye + 0.010))
		bm.rotation_degrees = Vector3(0, 0, side * 8.0)

		# cachete
		var cheek := SphereMesh.new()
		cheek.radius = 0.042
		cheek.height = 0.084
		var cm := _mesh(pivot, cheek, Color(0.95, 0.56, 0.54), Vector3(side * 0.120, hy - 0.040, z_eye - 0.020))
		cm.scale = Vector3(1.0, 0.7, 0.25)
		cm.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.material_override.albedo_color.a = 0.55
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# comisura de la sonrisa
		var corner := BoxMesh.new()
		corner.size = Vector3(0.030, 0.018, 0.018)
		var km := _mesh(pivot, corner, Color(0.42, 0.18, 0.17), Vector3(side * 0.040, hy - 0.080, z_eye + 0.005))
		km.rotation_degrees = Vector3(0, 0, side * 28.0)

	# boca
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.066, 0.018, 0.018)
	_mesh(pivot, mouth, Color(0.42, 0.18, 0.17), Vector3(0, hy - 0.090, z_eye + 0.010))

	# nariz
	var nose := SphereMesh.new()
	nose.radius = 0.030
	nose.height = 0.060
	var nm := _mesh(pivot, nose, SKIN.darkened(0.06), Vector3(0, hy - 0.030, z_eye + 0.045))
	nm.scale = Vector3(1.0, 0.8, 0.8)


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
	brim.top_radius = 0.255
	brim.bottom_radius = 0.265
	brim.height = 0.026
	brim.radial_segments = 24
	var brim_m := _mesh(pivot, brim, STRAW, Vector3(0, top + 0.015, 0))
	brim_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var crown := CylinderMesh.new()
	crown.top_radius = 0.140
	crown.bottom_radius = 0.158
	crown.height = 0.135
	crown.radial_segments = 24
	var crown_m := _mesh(pivot, crown, STRAW.lightened(0.04), Vector3(0, top + 0.088, 0))
	crown_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var band := CylinderMesh.new()
	band.top_radius = 0.159
	band.bottom_radius = 0.164
	band.height = 0.036
	band.radial_segments = 24
	var band_m := _mesh(pivot, band, BAND, Vector3(0, top + 0.035, 0))
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
