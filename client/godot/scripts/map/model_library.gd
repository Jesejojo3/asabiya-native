class_name ModelLibrary
extends RefCounted
## Procedural low-poly models (own work, vertex-coloured, no external assets).
## Sizes are in world units: one logical cell is `detail` (4) units wide; models
## are exaggerated like any strategy map so they read at provincial zoom.

static var _cache := {}
static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.85
		_material.vertex_color_is_srgb = true
	return _material


static func get_mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"hut":
			_cylinder(st, Vector3.ZERO, 0.045, 0.05, 7, Color8(150, 120, 86))
			_cone(st, Vector3(0, 0.05, 0), 0.06, 0.06, 7, Color8(176, 150, 92))
		"house":
			_box(st, Vector3(0, 0.03, 0), Vector3(0.09, 0.06, 0.065), Color8(214, 200, 176))
			_gable(st, Vector3(0, 0.06, 0), Vector3(0.1, 0.045, 0.075), Color8(160, 72, 52))
		"longhouse":
			_box(st, Vector3(0, 0.03, 0), Vector3(0.16, 0.06, 0.07), Color8(170, 140, 104))
			_gable(st, Vector3(0, 0.06, 0), Vector3(0.17, 0.05, 0.08), Color8(122, 104, 66))
		"townhouse":
			_box(st, Vector3(0, 0.05, 0), Vector3(0.08, 0.1, 0.08), Color8(226, 214, 190))
			_gable(st, Vector3(0, 0.1, 0), Vector3(0.09, 0.045, 0.09), Color8(140, 64, 48))
		"tower":
			_cylinder(st, Vector3.ZERO, 0.05, 0.22, 8, Color8(178, 170, 156))
			_cone(st, Vector3(0, 0.22, 0), 0.065, 0.09, 8, Color8(96, 70, 60))
		"keep":
			_box(st, Vector3(0, 0.12, 0), Vector3(0.2, 0.24, 0.2), Color8(170, 164, 150))
			for cx in [-1, 1]:
				for cz in [-1, 1]:
					_box(st, Vector3(cx * 0.085, 0.26, cz * 0.085), Vector3(0.05, 0.05, 0.05), Color8(160, 154, 142))
			_box(st, Vector3(0, 0.3, 0), Vector3(0.09, 0.12, 0.09), Color8(176, 170, 156))
			_cone(st, Vector3(0, 0.36, 0), 0.07, 0.08, 8, Color8(70, 76, 110))
		"wall":
			# unit segment along +X, scaled per instance
			_box(st, Vector3(0.5, 0.05, 0), Vector3(1.0, 0.1, 0.035), Color8(165, 158, 144))
		"temple":
			_box(st, Vector3(0, 0.02, 0), Vector3(0.24, 0.04, 0.17), Color8(196, 188, 170))
			_box(st, Vector3(0, 0.08, 0), Vector3(0.2, 0.08, 0.13), Color8(228, 222, 206))
			_gable(st, Vector3(0, 0.12, 0), Vector3(0.22, 0.06, 0.15), Color8(170, 110, 60))
		"ziggurat":
			for k in 4:
				var s := 0.26 - k * 0.055
				_box(st, Vector3(0, 0.025 + k * 0.05, 0), Vector3(s, 0.05, s), Color8(196 - k * 6, 170 - k * 6, 120))
		"market":
			_box(st, Vector3(0, 0.005, 0), Vector3(0.22, 0.01, 0.22), Color8(180, 160, 120))
			for k in 4:
				var a := k * TAU / 4.0 + 0.4
				var c: Color = [Color8(176, 60, 50), Color8(60, 100, 160), Color8(200, 160, 60), Color8(70, 130, 80)][k]
				_gable(st, Vector3(cos(a) * 0.06, 0.035, sin(a) * 0.06), Vector3(0.06, 0.035, 0.05), c)
		"dock":
			_box(st, Vector3(0, 0.01, 0.12), Vector3(0.05, 0.02, 0.24), Color8(120, 90, 60))
			_box(st, Vector3(0, 0.01, 0.24), Vector3(0.16, 0.02, 0.04), Color8(120, 90, 60))
		"ship":
			_box(st, Vector3(0, 0.015, 0), Vector3(0.05, 0.03, 0.14), Color8(110, 80, 52))
			_box(st, Vector3(0, 0.08, 0), Vector3(0.006, 0.12, 0.006), Color8(90, 70, 50))
			_box(st, Vector3(0, 0.09, 0), Vector3(0.002, 0.07, 0.09), Color8(230, 224, 206))
		"field":
			# flat strip field; a few centimetres thick so slopes don't swallow it
			_box(st, Vector3(0, 0.004, 0), Vector3(0.2, 0.012, 0.12), Color8(176, 160, 84))
			for k in 3:
				_box(st, Vector3(0, 0.011, -0.04 + k * 0.04), Vector3(0.2, 0.004, 0.012), Color8(132, 140, 70))
		"conifer":
			_cylinder(st, Vector3.ZERO, 0.008, 0.03, 5, Color8(92, 70, 50))
			_cone(st, Vector3(0, 0.02, 0), 0.04, 0.12, 6, Color8(46, 82, 58))
		"broadleaf":
			_cylinder(st, Vector3.ZERO, 0.009, 0.04, 5, Color8(96, 74, 52))
			_blob(st, Vector3(0, 0.07, 0), 0.045, Color8(76, 116, 60))
		"palm":
			_cylinder(st, Vector3.ZERO, 0.007, 0.1, 5, Color8(130, 104, 70))
			_cone(st, Vector3(0, 0.08, 0), 0.06, 0.035, 6, Color8(70, 124, 62))
		"shrub":
			_blob(st, Vector3(0, 0.02, 0), 0.025, Color8(120, 120, 72))
		"rock":
			_blob(st, Vector3(0, 0.01, 0), 0.03, Color8(128, 122, 114))
		"banner":
			_box(st, Vector3(0, 0.15, 0), Vector3(0.01, 0.3, 0.01), Color8(80, 60, 40))
			_box(st, Vector3(0.045, 0.25, 0), Vector3(0.08, 0.08, 0.004), Color8(255, 255, 255))
		_:
			_box(st, Vector3(0, 0.05, 0), Vector3(0.1, 0.1, 0.1), Color8(255, 0, 255))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_cache[kind] = mesh
	return mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# Godot treats clockwise triangles (as seen from outside) as front faces
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	var top := col
	var side := col.darkened(0.12)
	_quad(st, p[4], p[5], p[6], p[7], top)
	_quad(st, p[0], p[3], p[2], p[1], side.darkened(0.3))
	_quad(st, p[0], p[1], p[5], p[4], side)
	_quad(st, p[2], p[3], p[7], p[6], side)
	_quad(st, p[1], p[2], p[6], p[5], side.darkened(0.05))
	_quad(st, p[3], p[0], p[4], p[7], side.darkened(0.05))


static func _gable(st: SurfaceTool, base: Vector3, s: Vector3, col: Color) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var a := base + Vector3(-hx, 0, -hz)
	var b := base + Vector3(hx, 0, -hz)
	var c := base + Vector3(hx, 0, hz)
	var d := base + Vector3(-hx, 0, hz)
	var r1 := base + Vector3(-hx, s.y, 0)
	var r2 := base + Vector3(hx, s.y, 0)
	_quad(st, a, b, r2, r1, col)
	_quad(st, c, d, r1, r2, col.darkened(0.1))
	_tri(st, d, a, r1, col.darkened(0.25))
	_tri(st, b, c, r2, col.darkened(0.25))


static func _cylinder(st: SurfaceTool, base: Vector3, r: float, h: float, seg: int, col: Color) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		_quad(st, p1, p0, p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), col.darkened(0.08))
		_tri(st, base + Vector3(0, h, 0), p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), col)


static func _cone(st: SurfaceTool, base: Vector3, r: float, h: float, seg: int, col: Color) -> void:
	var tip := base + Vector3(0, h, 0)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		_tri(st, p1, p0, tip, col if k % 2 == 0 else col.darkened(0.06))
		_tri(st, p0, p1, base, col.darkened(0.3))


static func _blob(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	# squashed octahedron-ish blob, cheap and readable from above
	var top := c + Vector3(0, r, 0)
	var bot := c + Vector3(0, -r * 0.6, 0)
	var ring := []
	for k in 6:
		var a := TAU * k / 6.0
		ring.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
	for k in 6:
		var p0: Vector3 = ring[k]
		var p1: Vector3 = ring[(k + 1) % 6]
		_tri(st, p1, p0, top, col)
		_tri(st, p0, p1, bot, col.darkened(0.25))
