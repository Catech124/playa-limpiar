class_name CharModel
extends RefCounted
## Personaje jugable y NPC, armado con primitivas (sin GLB).
## Modelado a ojo sobre la referencia: chico de playa con sombrero de paja,
## pelo castaño rizado, ojos grandes, camiseta a rayas, short azul, sandalias y
## guantes de trabajo.
##
## Las bisagras se llaman arm_l, arm_r, leg_l, leg_r, head, hat: la animación
## del jugador no cambia.

const SKIN := Color(0.96, 0.75, 0.60)
const SKIN_DARK := Color(0.90, 0.65, 0.50)
const WHITE := Color(0.98, 0.98, 0.96)
const STRIPE := Color(0.35, 0.52, 0.80)
const SHORTS := Color(0.14, 0.20, 0.40)
const STRAW := Color(0.80, 0.66, 0.42)
const STRAW_LIGHT := Color(0.86, 0.73, 0.49)
const STRAW_DARK := Color(0.66, 0.51, 0.31)
const HAIR := Color(0.38, 0.23, 0.13)
const HAIR_DARK := Color(0.30, 0.18, 0.10)
const DARK := Color(0.10, 0.09, 0.11)
const IRIS := Color(0.42, 0.27, 0.16)
const MOUTH := Color(0.42, 0.18, 0.16)
const BLUSH := Color(0.97, 0.62, 0.58)
const SANDAL := Color(0.32, 0.52, 0.82)
const GLOVE := Color(0.55, 0.38, 0.24)

const HEAD_R := 0.195
const HEAD_Y := 0.700
const HINGE_Y := 0.520
const SHOULDER_X := 0.145
const SHOULDER_Y := 0.435
## Punto donde quedan las manos con la pose de cargar (lo usa el jugador).
const HAND_CARRY := Vector3(0.0, 0.300, 0.215)

const TORSO_BOTTOM := 0.285
const TORSO_TOP := 0.520
const TORSO_R_BOTTOM := 0.190
const TORSO_R_TOP := 0.125


static func build(_shirt: Color, hat := "straw") -> Node3D:
	var root := Node3D.new()
	root.name = "CharModel"

	_build_legs(root)
	_build_torso(root)
	_build_arms(root)
	_build_head(root, hat)
	return root


# ------------------------------------------------------------------ piernas
static func _build_legs(root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "leg_" + tag
		pivot.position = Vector3(side * 0.068, 0.205, 0)
		root.add_child(pivot)

		var leg := CylinderMesh.new()
		leg.top_radius = 0.056
		leg.bottom_radius = 0.050
		leg.height = 0.16
		leg.radial_segments = 16
		_mesh(pivot, leg, SKIN, Vector3(0, -0.080, 0))

		# sandalia: suela ovalada + tira en Y blanca
		var sole := SphereMesh.new()
		sole.radius = 0.072
		sole.height = 0.144
		sole.radial_segments = 18
		sole.rings = 10
		var sm := _mesh(pivot, sole, SANDAL, Vector3(0, -0.150, 0.035))
		sm.scale = Vector3(1.0, 0.40, 1.60)
		for i in 2:
			var strap := BoxMesh.new()
			strap.size = Vector3(0.022, 0.020, 0.085)
			var st := _mesh(pivot, strap, WHITE, Vector3(side * (0.028 - 0.056 * float(i)), -0.128, 0.060))
			st.rotation_degrees = Vector3(0, side * (26.0 - 52.0 * float(i)), 0)
		var strap2 := BoxMesh.new()
		strap2.size = Vector3(0.022, 0.020, 0.060)
		_mesh(pivot, strap2, WHITE, Vector3(0, -0.128, 0.010))


# ------------------------------------------------------------------ torso
static func _build_torso(root: Node3D) -> void:
	# short: volumen redondeado, más ancho que las piernas
	var shorts := CylinderMesh.new()
	shorts.top_radius = TORSO_R_BOTTOM + 0.004
	shorts.bottom_radius = 0.168
	shorts.height = 0.120
	shorts.radial_segments = 26
	_mesh(root, shorts, SHORTS, Vector3(0, 0.248, 0))
	# ruedo redondeado, apenas más ancho que el short
	var hem := TorusMesh.new()
	hem.inner_radius = 0.150
	hem.outer_radius = 0.172
	hem.rings = 26
	hem.ring_segments = 6
	_mesh(root, hem, SHORTS, Vector3(0, 0.190, 0))

	# camiseta a rayas finas (7 bandas)
	var bands := 7
	var height := TORSO_TOP - TORSO_BOTTOM
	for i in bands:
		var t0 := float(i) / float(bands)
		var t1 := float(i + 1) / float(bands)
		var seg := CylinderMesh.new()
		seg.top_radius = lerpf(TORSO_R_BOTTOM, TORSO_R_TOP, t1)
		seg.bottom_radius = lerpf(TORSO_R_BOTTOM, TORSO_R_TOP, t0)
		seg.height = height / float(bands)
		seg.radial_segments = 26
		var col := WHITE if i % 2 == 0 else STRIPE
		_mesh(root, seg, col, Vector3(0, TORSO_BOTTOM + height * (t0 + t1) * 0.5, 0))

	# cuello de la camiseta
	var collar := CylinderMesh.new()
	collar.top_radius = TORSO_R_TOP + 0.012
	collar.bottom_radius = TORSO_R_TOP + 0.004
	collar.height = 0.020
	collar.radial_segments = 24
	_mesh(root, collar, WHITE, Vector3(0, TORSO_TOP - 0.006, 0))

	# cuello de piel
	var neck := CylinderMesh.new()
	neck.top_radius = 0.068
	neck.bottom_radius = 0.078
	neck.height = 0.07
	neck.radial_segments = 16
	_mesh(root, neck, SKIN, Vector3(0, TORSO_TOP + 0.024, 0))


# ------------------------------------------------------------------ brazos
static func _build_arms(root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "arm_" + tag
		pivot.position = Vector3(side * 0.140, 0.440, 0)
		pivot.rotation_degrees = Vector3(0, 0, side * 7.0)
		root.add_child(pivot)

		# hombro redondeado que se funde con la camiseta
		var shoulder := SphereMesh.new()
		shoulder.radius = 0.062
		shoulder.height = 0.124
		shoulder.radial_segments = 16
		shoulder.rings = 8
		_mesh(pivot, shoulder, STRIPE, Vector3(side * 0.006, -0.006, 0))

		# manga corta a rayas
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.058
		sleeve.bottom_radius = 0.052
		sleeve.height = 0.070
		sleeve.radial_segments = 16
		_mesh(pivot, sleeve, STRIPE, Vector3(side * 0.010, -0.058, 0))

		# puño blanco
		var cuff := CylinderMesh.new()
		cuff.top_radius = 0.053
		cuff.bottom_radius = 0.051
		cuff.height = 0.016
		cuff.radial_segments = 16
		_mesh(pivot, cuff, WHITE, Vector3(side * 0.014, -0.100, 0))

		# antebrazo de piel
		var arm := CylinderMesh.new()
		arm.top_radius = 0.040
		arm.bottom_radius = 0.036
		arm.height = 0.080
		arm.radial_segments = 16
		_mesh(pivot, arm, SKIN, Vector3(side * 0.018, -0.146, 0))

		# guante de trabajo
		var glove := SphereMesh.new()
		glove.radius = 0.052
		glove.height = 0.108
		glove.radial_segments = 16
		glove.rings = 9
		var gm := _mesh(pivot, glove, GLOVE, Vector3(side * 0.022, -0.198, 0))
		gm.scale = Vector3(1.0, 1.08, 1.0)
		var thumb := SphereMesh.new()
		thumb.radius = 0.026
		thumb.height = 0.052
		_mesh(pivot, thumb, GLOVE, Vector3(side * 0.056, -0.204, 0.024))


# ------------------------------------------------------------------ cabeza
static func _build_head(root: Node3D, hat: String) -> void:
	var pivot := Node3D.new()
	pivot.name = "head"
	pivot.position = Vector3(0, HINGE_Y, 0)
	root.add_child(pivot)
	var hy := HEAD_Y - HINGE_Y

	var skull := SphereMesh.new()
	skull.radius = HEAD_R
	skull.height = HEAD_R * 2.0
	skull.radial_segments = 26
	skull.rings = 14
	_mesh(pivot, skull, SKIN, Vector3(0, hy, 0))

	# orejas
	for side in [-1.0, 1.0]:
		var ear := SphereMesh.new()
		ear.radius = 0.048
		ear.height = 0.096
		var em := _mesh(pivot, ear, SKIN_DARK, Vector3(side * HEAD_R * 0.93, hy - 0.015, 0.012))
		em.scale = Vector3(0.45, 1.0, 0.75)

	_build_hair(pivot, hy)
	_build_face(pivot, hy)
	_build_hat(root, hy, hat)


## Pelo: casquete de rizos alrededor de la cabeza y mechones laterales.
static func _build_hair(pivot: Node3D, hy: float) -> void:
	var locks := [
		# corona
		[0.000, 0.150, 0.020, 0.105], [-0.090, 0.140, 0.020, 0.095],
		[0.090, 0.140, 0.020, 0.095], [-0.150, 0.100, 0.010, 0.085],
		[0.150, 0.100, 0.010, 0.085], [-0.055, 0.155, 0.100, 0.085],
		[0.055, 0.155, 0.100, 0.085],
		# nuca
		[0.000, 0.120, -0.120, 0.100], [-0.100, 0.100, -0.110, 0.090],
		[0.100, 0.100, -0.110, 0.090], [-0.160, 0.060, -0.060, 0.080],
		[0.160, 0.060, -0.060, 0.080],
		# mechones que caen a los costados
		[-0.180, 0.055, 0.045, 0.060], [0.180, 0.055, 0.045, 0.060],
	]
	for l in locks:
		var lock := SphereMesh.new()
		lock.radius = 0.058
		lock.height = 0.116
		lock.radial_segments = 12
		lock.rings = 7
		var lm := _mesh(pivot, lock, HAIR, Vector3(float(l[0]), hy + float(l[1]), float(l[2])))
		lm.scale = Vector3(float(l[3]) / 0.058 * 0.85, float(l[3]) / 0.058 * 0.80, float(l[3]) / 0.058 * 0.85)

	# flequillo: rizos sobre la frente
	for i in 3:
		var fringe := SphereMesh.new()
		fringe.radius = 0.070
		fringe.height = 0.140
		fringe.radial_segments = 12
		fringe.rings = 7
		var fx := -0.085 + 0.085 * float(i)
		var fm := _mesh(pivot, fringe, HAIR, Vector3(fx, hy + 0.128, 0.140))
		fm.scale = Vector3(1.05, 0.80, 0.80)


static func _build_face(pivot: Node3D, hy: float) -> void:
	for side in [-1.0, 1.0]:
		var ex: float = float(side) * 0.078
		var ey := 0.020
		var ez: float = sqrt(maxf(0.0, HEAD_R * HEAD_R - ex * ex - ey * ey))

		# esclerótica grande y apenas hundida
		var sclera := SphereMesh.new()
		sclera.radius = 0.056
		sclera.height = 0.124
		sclera.radial_segments = 16
		sclera.rings = 9
		var sc := _mesh(pivot, sclera, WHITE, Vector3(ex, hy + ey, ez - 0.030))
		sc.scale = Vector3(1.0, 1.08, 0.26)

		var iris := SphereMesh.new()
		iris.radius = 0.036
		iris.height = 0.076
		iris.radial_segments = 14
		iris.rings = 8
		var ir := _mesh(pivot, iris, IRIS, Vector3(ex, hy + ey - 0.003, ez - 0.004))
		ir.scale = Vector3(1.0, 1.02, 0.30)

		var pupil := SphereMesh.new()
		pupil.radius = 0.020
		pupil.height = 0.042
		pupil.radial_segments = 12
		pupil.rings = 6
		var pu := _mesh(pivot, pupil, DARK, Vector3(ex, hy + ey - 0.003, ez + 0.008))
		pu.scale = Vector3(1.0, 1.02, 0.26)

		var glint := SphereMesh.new()
		glint.radius = 0.011
		glint.height = 0.022
		var gm := _mesh(pivot, glint, WHITE, Vector3(ex - 0.012, hy + ey + 0.016, ez + 0.016))
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# ceja gruesa, arqueada
		var brow := BoxMesh.new()
		brow.size = Vector3(0.080, 0.024, 0.024)
		var bm := _mesh(pivot, brow, HAIR_DARK, Vector3(ex, hy + ey + 0.098, ez - 0.014))
		bm.rotation_degrees = Vector3(0, 0, side * 10.0)

		# cachete
		var cheek := SphereMesh.new()
		cheek.radius = 0.048
		cheek.height = 0.096
		var cm := _mesh(pivot, cheek, BLUSH, Vector3(side * 0.130, hy - 0.052, ez - 0.060))
		cm.scale = Vector3(1.0, 0.70, 0.28)
		cm.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.material_override.albedo_color.a = 0.55
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# nariz de botón
	var nose := SphereMesh.new()
	nose.radius = 0.026
	nose.height = 0.052
	var nm := _mesh(pivot, nose, SKIN_DARK, Vector3(0.0, hy - 0.028, sqrt(HEAD_R * HEAD_R - 0.0008) + 0.012))
	nm.scale = Vector3(1.0, 0.85, 0.75)

	# sonrisa
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.048, 0.010, 0.010)
	var mm := MeshInstance3D.new()
	mm.mesh = mouth
	mm.material_override = ItemVisuals.material(MOUTH)
	mm.position = Vector3(0.0, hy - 0.082, sqrt(HEAD_R * HEAD_R - 0.0067) - 0.002)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mm)
	for side in [-1.0, 1.0]:
		var corner := BoxMesh.new()
		corner.size = Vector3(0.020, 0.012, 0.012)
		var km := MeshInstance3D.new()
		km.mesh = corner
		km.material_override = ItemVisuals.material(MOUTH)
		km.position = Vector3(side * 0.033, hy - 0.076, sqrt(HEAD_R * HEAD_R - 0.0011) - 0.002)
		km.rotation_degrees = Vector3(0, 0, side * 30.0)
		km.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(km)


static func _build_hat(root: Node3D, hy: float, kind: String) -> void:
	if kind == "none":
		return
	var pivot := Node3D.new()
	pivot.name = "hat"
	pivot.position = Vector3(0, HINGE_Y, 0)
	root.add_child(pivot)

	if kind == "cap":
		var cap := SphereMesh.new()
		cap.radius = HEAD_R * 1.04
		cap.height = HEAD_R * 2.08
		cap.radial_segments = 20
		cap.rings = 10
		var cm := _mesh(pivot, cap, Color(0.35, 0.55, 0.85), Vector3(0, hy + 0.020, 0))
		cm.scale = Vector3(1.0, 0.66, 1.0)
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var brim := BoxMesh.new()
		brim.size = Vector3(0.24, 0.022, 0.14)
		var bm := _mesh(pivot, brim, Color(0.28, 0.45, 0.72), Vector3(0, hy + 0.080, 0.160))
		bm.rotation_degrees = Vector3(-8, 0, 0)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return

	# ala: disco ancho con el borde ondulado (tramos que se solapan)
	var brim_y := hy + HEAD_R - 0.030
	var disc := CylinderMesh.new()
	disc.top_radius = 0.262
	disc.bottom_radius = 0.272
	disc.height = 0.020
	disc.radial_segments = 30
	var dm := _mesh(pivot, disc, STRAW, Vector3(0, brim_y, 0))
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# copa: cilindro bajo con tapa redondeada
	var crown := CylinderMesh.new()
	crown.top_radius = 0.146
	crown.bottom_radius = 0.160
	crown.height = 0.125
	crown.radial_segments = 26
	var cm2 := _mesh(pivot, crown, STRAW, Vector3(0, brim_y + 0.072, 0))
	cm2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var cap := SphereMesh.new()
	cap.radius = 0.150
	cap.height = 0.300
	cap.radial_segments = 24
	cap.rings = 10
	var cp := _mesh(pivot, cap, STRAW_LIGHT, Vector3(0, brim_y + 0.118, 0))
	cp.scale = Vector3(1.0, 0.72, 1.0)
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
	outline.grow_amount = 0.009
	mat.next_pass = outline
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
