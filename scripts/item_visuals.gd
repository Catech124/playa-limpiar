class_name ItemVisuals
extends RefCounted
## Construye la geometría de los ítems. Sin assets: primitivas y color.


static func material(c: Color, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.metallic = metallic
	return m


static func build(item: CarryItem) -> Node3D:
	var root := Node3D.new()
	item.node = root
	rebuild(item)
	return root


static func rebuild(item: CarryItem) -> void:
	if item.node == null:
		return
	for c in item.node.get_children():
		item.node.remove_child(c)
		c.queue_free()
	if item.is_bag():
		_build_bag(item)
	else:
		_build_residue(item)


static func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, metallic := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color, metallic)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _build_residue(item: CarryItem) -> void:
	var base: Color = GameConfig.RESIDUES[item.type]["color"]
	if not item.classified:
		base = base.lerp(Color(0.55, 0.57, 0.60), 0.45)

	match item.type:
		"pet":
			var body := CylinderMesh.new()
			body.top_radius = 0.085
			body.bottom_radius = 0.095
			body.height = 0.34
			body.radial_segments = 12
			_mesh(item.node, body, base, Vector3(0, 0.17, 0))
			var cap := CylinderMesh.new()
			cap.top_radius = 0.045
			cap.bottom_radius = 0.045
			cap.height = 0.06
			_mesh(item.node, cap, base.darkened(0.35), Vector3(0, 0.36, 0))
		"lata":
			var can := CylinderMesh.new()
			can.top_radius = 0.10
			can.bottom_radius = 0.10
			can.height = 0.22
			can.radial_segments = 14
			_mesh(item.node, can, base, Vector3(0, 0.11, 0), 0.5)
			var top := CylinderMesh.new()
			top.top_radius = 0.085
			top.bottom_radius = 0.085
			top.height = 0.02
			_mesh(item.node, top, base.lightened(0.35), Vector3(0, 0.22, 0), 0.6)
		_:
			var shard := BoxMesh.new()
			shard.size = Vector3(0.17, 0.24, 0.09)
			var mi := _mesh(item.node, shard, base, Vector3(0, 0.14, 0))
			mi.rotation_degrees = Vector3(8, 22, 12)

	if item.classified:
		var dot := SphereMesh.new()
		dot.radius = 0.035
		dot.height = 0.07
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1)
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 0.35
		var mi := MeshInstance3D.new()
		mi.mesh = dot
		mi.material_override = mat
		mi.position = Vector3(0.1, 0.42, 0.06)
		item.node.add_child(mi)


static func _build_bag(item: CarryItem) -> void:
	var body_color := Color(0.87, 0.94, 1.0) if item.clean else Color(0.62, 0.55, 0.44)
	var body := BoxMesh.new()
	body.size = Vector3(0.44, 0.34, 0.28)
	_mesh(item.node, body, body_color, Vector3(0, 0.19, 0))

	var handle := TorusMesh.new()
	handle.inner_radius = 0.07
	handle.outer_radius = 0.115
	handle.rings = 12
	var h := _mesh(item.node, handle, body_color.darkened(0.25), Vector3(0, 0.39, 0))
	h.rotation_degrees = Vector3(90, 0, 0)

	if item.clean:
		var n := item.contents.size()
		for i in n:
			var dot := SphereMesh.new()
			dot.radius = 0.05
			dot.height = 0.1
			var col: Color = GameConfig.RESIDUES[item.contents[i]]["color"]
			var ox := -0.09 + (i % 2) * 0.18
			var oz := -0.05 + (i / 2) * 0.12
			_mesh(item.node, dot, col, Vector3(ox, 0.37, oz))
	else:
		# manchas de bolsa sucia
		for i in 3:
			var dot := SphereMesh.new()
			dot.radius = 0.035
			dot.height = 0.07
			_mesh(item.node, dot, Color(0.42, 0.36, 0.27), Vector3(-0.1 + i * 0.1, 0.36, 0.02))
