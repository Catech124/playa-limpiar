class_name CharModel
extends RefCounted
## Personaje jugable y NPC, armado con primitivas (sin GLB).
##
## Ingeniería inversa de la referencia (chico de playa):
##   · sombrero de paja de ala ancha, copa redondeada
##   · pelo castaño rizado asomando bajo el ala
##   · ojos grandes con esclerótica, iris, pupila y brillo; cejas gruesas
##   · camiseta a rayas blancas y azules
##   · short azul marino, piernas cortas y sandalias azules con tiras blancas
##   · cuerpo = trapecio (ancho en la base, angosto en el cuello) y remate en
##     media luna del mismo ancho; brazos cortos con guante
##
## Las bisagras se llaman arm_l, arm_r, leg_l, leg_r, head, hat: la animación
## del jugador no cambia.

const SKIN := Color(0.95, 0.71, 0.56)
const SKIN_DARK := Color(0.88, 0.60, 0.46)
const WHITE := Color(0.97, 0.97, 0.95)
const STRIPE := Color(0.32, 0.48, 0.78)
const SHORTS := Color(0.16, 0.22, 0.42)
const STRAW := Color(0.83, 0.68, 0.44)
const STRAW_DARK := Color(0.72, 0.56, 0.34)
const HAIR := Color(0.40, 0.25, 0.15)
const DARK := Color(0.10, 0.09, 0.11)
const IRIS := Color(0.45, 0.30, 0.18)
const MOUTH := Color(0.45, 0.20, 0.18)
const BLUSH := Color(0.96, 0.60, 0.56)
const SANDAL := Color(0.30, 0.50, 0.80)

const HEAD_R := 0.170
const HEAD_Y := 0.590
const HINGE_Y := 0.470
const SHOULDER_X := 0.150
const SHOULDER_Y := 0.360
## Punto donde quedan las manos con la pose de cargar (lo usa el jugador).
const HAND_CARRY := Vector3(0.0, 0.245, 0.205)

const TORSO_BOTTOM := 0.200
const TORSO_TOP := 0.430
const TORSO_R_BOTTOM := 0.180
const TORSO_R_TOP := 0.108


static func build(shirt: Color, hat := "straw") -> Node3D:
	var root := Node3D.new()
	root.name = "CharModel"

	_build_torso(root)
	_build_legs(root)
	_build_arms(root)
	_build_head(root, hat)
	return root


# ------------------------------------------------------------------ torso
## Camiseta a rayas: el trapecio se arma con anillos alternados (blanco/azul).
static func _build_torso(root: Node3D) -> void:
	var bands := 5
	var height := TORSO_TOP - TORSO_BOTTOM
	for i in bands:
		var t0 := float(i) / float(bands)
		var t1 := float(i + 1) / float(bands)
		var seg := CylinderMesh.new()
		seg.top_radius = lerpf(TORSO_R_BOTTOM, TORSO_R_TOP, t1)
		seg.bottom_radius = lerpf(TORSO_R_BOTTOM, TORSO_R_TOP, t0)
		seg.height = height / float(bands)
		seg.radial_segments = 24
		var col := WHITE if i % 2 == 0 else STRIPE
		_mesh(root, seg, col, Vector3(0, TORSO_BOTTOM + height * (t0 + t1) * 0.5, 0))

	# cuello de la camiseta
	var collar := CylinderMesh.new()
	collar.top_radius = TORSO_R_TOP + 0.004
	collar.bottom_radius = TORSO_R_TOP + 0.010
	collar.height = 0.022
	collar.radial_segments = 24
	_mesh(root, collar, WHITE, Vector3(0, TORSO_TOP - 0.004, 0))

	# media luna del short: mismo ancho que la base, no sobresale
	var hips := SphereMesh.new()
	hips.radius = TORSO_R_BOTTOM
	hips.height = TORSO_R_BOTTOM * 2.0
	hips.radial_segments = 24
	hips.rings = 12
	var hm := _mesh(root, hips, SHORTS, Vector3(0, TORSO_BOTTOM, 0))
	hm.scale = Vector3(1.0, 0.62, 1.0)

	# cintura: banda del short
	var waist := CylinderMesh.new()
	waist.top_radius = TORSO_R_BOTTOM + 0.002
	waist.bottom_radius = TORSO_R_BOTTOM + 0.002
	waist.height = 0.045
	waist.radial_segments = 24
	_mesh(root, waist, SHORTS, Vector3(0, TORSO_BOTTOM + 0.012, 0))

	# cuello de piel
	var neck := CylinderMesh.new()
	neck.top_radius = 0.055
	neck.bottom_radius = 0.062
	neck.height = 0.05
	neck.radial_segments = 14
	_mesh(root, neck, SKIN, Vector3(0, TORSO_TOP + 0.010, 0))


# ------------------------------------------------------------------ piernas
static func _build_legs(root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "leg_" + tag
		pivot.position = Vector3(side * 0.062, 0.150, 0)
		root.add_child(pivot)

		var leg := CylinderMesh.new()
		leg.top_radius = 0.048
		leg.bottom_radius = 0.044
		leg.height = 0.10
		leg.radial_segments = 14
		_mesh(pivot, leg, SKIN, Vector3(0, -0.050, 0))

		# sandalia: suela ovalada azul + tira blanca
		var sole := SphereMesh.new()
		sole.radius = 0.062
		sole.height = 0.124
		sole.radial_segments = 16
		sole.rings = 9
		var sm := _mesh(pivot, sole, SANDAL, Vector3(0, -0.100, 0.030))
		sm.scale = Vector3(1.0, 0.42, 1.55)
		var strap := BoxMesh.new()
		strap.size = Vector3(0.085, 0.018, 0.045)
		_mesh(pivot, strap, WHITE, Vector3(0, -0.082, 0.030))


# ------------------------------------------------------------------ brazos
static func _build_arms(root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var pivot := Node3D.new()
		pivot.name = "arm_" + tag
		pivot.position = Vector3(side * SHOULDER_X, SHOULDER_Y, 0)
		root.add_child(pivot)

		# manga corta (blanca con puño azul), arranca dentro del torso
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.052
		sleeve.bottom_radius = 0.048
		sleeve.height = 0.07
		sleeve.radial_segments = 14
		var sl := _mesh(pivot, sleeve, STRIPE, Vector3(side * 0.012, -0.030, 0))
		sl.rotation_degrees = Vector3(0, 0, side * 10.0)

		var cuff := CylinderMesh.new()
		cuff.top_radius = 0.049
		cuff.bottom_radius = 0.047
		cuff.height = 0.02
		cuff.radial_segments = 14
		var cf := _mesh(pivot, cuff, WHITE, Vector3(side * 0.020, -0.070, 0))
		cf.rotation_degrees = Vector3(0, 0, side * 10.0)

		# antebrazo de piel
		var arm := CylinderMesh.new()
		arm.top_radius = 0.040
		arm.bottom_radius = 0.036
		arm.height = 0.075
		arm.radial_segments = 14
		var am := _mesh(pivot, arm, SKIN, Vector3(side * 0.026, -0.115, 0))
		am.rotation_degrees = Vector3(0, 0, side * 8.0)

		# guante blanco al final
		var glove := SphereMesh.new()
		glove.radius = 0.052
		glove.height = 0.110
		glove.radial_segments = 14
		glove.rings = 8
		var gm := _mesh(pivot, glove, WHITE, Vector3(side * 0.032, -0.170, 0))
		gm.scale = Vector3(1.0, 1.08, 1.0)


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
	skull.radial_segments = 24
	skull.rings = 14
	_mesh(pivot, skull, SKIN, Vector3(0, hy, 0))

	# orejas
	for side in [-1.0, 1.0]:
		var ear := SphereMesh.new()
		ear.radius = 0.045
		ear.height = 0.09
		var em := _mesh(pivot, ear, SKIN_DARK, Vector3(side * HEAD_R * 0.94, hy - 0.010, 0.010))
		em.scale = Vector3(0.5, 1.0, 0.8)

	_build_hair(pivot, hy)
	_build_face(pivot, hy)
	_build_hat(root, hy, hat)


## Pelo rizado: racimos de esferas alrededor de la cabeza, más juntos adelante.
static func _build_hair(pivot: Node3D, hy: float) -> void:
	var curls := [
		[-0.115, 0.085, 0.075], [0.115, 0.085, 0.075],
		[-0.075, 0.120, 0.105], [0.075, 0.120, 0.105],
		[0.0, 0.128, 0.115],
		[-0.135, 0.040, 0.020], [0.135, 0.040, 0.020],
		[-0.060, 0.100, -0.120], [0.060, 0.100, -0.120], [0.0, 0.105, -0.135],
		[-0.140, 0.075, -0.060], [0.140, 0.075, -0.060],
	]
	for c in curls:
		var curl := SphereMesh.new()
		curl.radius = 0.070
		curl.height = 0.140
		curl.radial_segments = 12
		curl.rings = 7
		var cm := _mesh(pivot, curl, HAIR, Vector3(float(c[0]), hy + float(c[1]), float(c[2])))
		cm.scale = Vector3(1.0, 0.92, 1.0)

	# flequillo: tres rizos al frente, sobre la frente
	for i in 3:
		var fringe := SphereMesh.new()
		fringe.radius = 0.062
		fringe.height = 0.124
		fringe.radial_segments = 12
		fringe.rings = 7
		var fx := -0.085 + 0.085 * float(i)
		var fm := _mesh(pivot, fringe, HAIR, Vector3(fx, hy + 0.105, 0.135))
		fm.scale = Vector3(1.05, 0.85, 0.85)


static func _build_face(pivot: Node3D, hy: float) -> void:
	for side in [-1.0, 1.0]:
		var ex: float = float(side) * 0.062
		var ey := 0.022
		var ez: float = sqrt(maxf(0.0, HEAD_R * HEAD_R - ex * ex - ey * ey)) + 0.002

		# esclerótica
		var sclera := SphereMesh.new()
		sclera.radius = 0.052
		sclera.height = 0.104
		sclera.radial_segments = 14
		sclera.rings = 8
		var sc := _mesh(pivot, sclera, WHITE, Vector3(ex, hy + ey, ez - 0.024))
		sc.scale = Vector3(1.0, 1.12, 0.34)

		# iris
		var iris := SphereMesh.new()
		iris.radius = 0.032
		iris.height = 0.064
		iris.radial_segments = 12
		iris.rings = 7
		var ir := _mesh(pivot, iris, IRIS, Vector3(ex, hy + ey - 0.002, ez - 0.002))
		ir.scale = Vector3(1.0, 1.05, 0.34)

		# pupila
		var pupil := SphereMesh.new()
		pupil.radius = 0.018
		pupil.height = 0.036
		pupil.radial_segments = 10
		pupil.rings = 5
		var pu := _mesh(pivot, pupil, DARK, Vector3(ex, hy + ey - 0.002, ez + 0.010))
		pu.scale = Vector3(1.0, 1.05, 0.30)

		# brillo
		var glint := SphereMesh.new()
		glint.radius = 0.009
		glint.height = 0.018
		var gm := _mesh(pivot, glint, WHITE, Vector3(ex - 0.010, hy + ey + 0.012, ez + 0.018))
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# ceja gruesa
		var brow := BoxMesh.new()
		brow.size = Vector3(0.078, 0.024, 0.024)
		var bm := _mesh(pivot, brow, HAIR, Vector3(ex, hy + ey + 0.088, ez - 0.006))
		bm.rotation_degrees = Vector3(0, 0, side * 9.0)

		# cachete
		var cheek := SphereMesh.new()
		cheek.radius = 0.042
		cheek.height = 0.084
		var cm := _mesh(pivot, cheek, BLUSH, Vector3(side * 0.115, hy - 0.045, ez - 0.045))
		cm.scale = Vector3(1.0, 0.72, 0.3)
		cm.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.material_override.albedo_color.a = 0.6
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# boca: sonrisa chica
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.052, 0.011, 0.011)
	var mm := MeshInstance3D.new()
	mm.mesh = mouth
	mm.material_override = ItemVisuals.material(MOUTH)
	mm.position = Vector3(0.0, hy - 0.076, sqrt(HEAD_R * HEAD_R - 0.0058) - 0.003)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mm)
	for side in [-1.0, 1.0]:
		var corner := BoxMesh.new()
		corner.size = Vector3(0.018, 0.011, 0.011)
		var km := MeshInstance3D.new()
		km.mesh = corner
		km.material_override = ItemVisuals.material(MOUTH)
		km.position = Vector3(side * 0.030, hy - 0.070, sqrt(HEAD_R * HEAD_R - 0.0009) - 0.003)
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
		var bm := _mesh(pivot, brim, Color(0.28, 0.45, 0.72), Vector3(0, hy + 0.070, 0.155))
		bm.rotation_degrees = Vector3(-8, 0, 0)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return

	# sombrero de paja: ala ancha y copa redondeada
	var brim := CylinderMesh.new()
	brim.top_radius = 0.285
	brim.bottom_radius = 0.300
	brim.height = 0.024
	brim.radial_segments = 28
	var brim_m := _mesh(pivot, brim, STRAW, Vector3(0, hy + HEAD_R - 0.018, 0))
	brim_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# borde trenzado: aro más oscuro bajo el ala
	var braid := TorusMesh.new()
	braid.inner_radius = 0.285
	braid.outer_radius = 0.312
	braid.rings = 26
	braid.ring_segments = 5
	var bm2 := _mesh(pivot, braid, STRAW_DARK, Vector3(0, hy + HEAD_R - 0.028, 0))
	bm2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# copa: cilindro con la tapa redondeada
	var crown := CylinderMesh.new()
	crown.top_radius = 0.145
	crown.bottom_radius = 0.158
	crown.height = 0.115
	crown.radial_segments = 24
	var cm2 := _mesh(pivot, crown, STRAW, Vector3(0, hy + HEAD_R + 0.040, 0))
	var cap_top := SphereMesh.new()
	cap_top.radius = 0.146
	cap_top.height = 0.292
	cap_top.radial_segments = 22
	cap_top.rings = 10
	var ct := _mesh(pivot, cap_top, STRAW, Vector3(0, hy + HEAD_R + 0.098, 0))
	ct.scale = Vector3(1.0, 0.42, 1.0)
	cm2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var band := CylinderMesh.new()
	band.top_radius = 0.152
	band.bottom_radius = 0.158
	band.height = 0.030
	band.radial_segments = 24
	var band_m := _mesh(pivot, band, STRAW_DARK, Vector3(0, hy + HEAD_R + 0.010, 0))
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
	outline.grow_amount = 0.009
	mat.next_pass = outline
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
