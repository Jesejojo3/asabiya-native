class_name HistoryOverlay
extends Node3D
## Historical annotations from engine frames: territory names lying on the
## terrain, war markers, recent events and trade routes. Rebuilt only when the
## frame changes; positions follow the longitude wrap every frame.

var world: WorldData
var mm: MapMath
var _labels: Array[Label3D] = []
var _markers: Array[Node3D] = []
var _routes: Array[MeshInstance3D] = []
var show_labels := true
var show_events := true
var show_routes := true
var label_mode := "states"   # states | peoples | religions
var _label_signature: Variant = null
var _marker_signature: Variant = null
var _route_signature: Variant = null


func setup(w: WorldData, math: MapMath) -> void:
	world = w
	mm = math


func clear() -> void:
	for n in _labels:
		n.queue_free()
	for n in _markers:
		n.queue_free()
	for n in _routes:
		n.queue_free()
	_labels.clear()
	_markers.clear()
	_routes.clear()
	_label_signature = null
	_marker_signature = null
	_route_signature = null


func rebuild(frame: HistoryFrame, mode: String) -> void:
	label_mode = mode
	if frame == null:
		clear()
		return
	var ids := frame.owner
	var records := frame.states
	if mode == "peoples":
		ids = frame.people
		records = frame.peoples
	elif mode == "religions":
		ids = frame.religion
		records = frame.religions
	var names := {}
	for id: int in records: names[id] = records[id].get("name", "")
	var labels := {"enabled":show_labels,"mode":mode,"ids":ids,"names":names}
	if labels != _label_signature:
		for node in _labels: node.queue_free()
		_labels.clear()
		_build_labels(frame)
		_label_signature = labels
	var recent := []
	for event: Dictionary in frame.events:
		if frame.year - int(event.get("year", frame.year)) <= 50 and int(event.get("cell", -1)) >= 0:
			recent.append([event.get("id"), event.get("cell"), event.get("kind")])
	var fronts := []
	for war: Dictionary in frame.wars:
		var front: PackedInt32Array = war.get("front", PackedInt32Array())
		if not front.is_empty(): fronts.append(front)
	var markers := {"enabled":show_events,"events":recent,"fronts":fronts,"relief":mm.land_scale}
	if markers != _marker_signature:
		for node in _markers: node.queue_free()
		_markers.clear()
		_build_markers(frame)
		_marker_signature = markers
	var routes := {"enabled":show_routes,"routes":frame.routes,"relief":mm.land_scale}
	if routes != _route_signature:
		for node in _routes: node.queue_free()
		_routes.clear()
		_build_routes(frame)
		_route_signature = routes


## Wrap-aware centroid and extent of groups of cells.
func _group_shapes(ids: PackedInt32Array) -> Dictionary:
	var acc := {}
	var W := mm.map_w
	for i in world.land_cells:
		var g := ids[i]
		if g < 0:
			continue
		var c := world.cell_center(i)
		var a := c.x / W * TAU
		if not acc.has(g):
			acc[g] = [0.0, 0.0, 0.0, 0, INF, -INF]  # sin, cos, z, n, minz, maxz
		var v: Array = acc[g]
		v[0] += sin(a)
		v[1] += cos(a)
		v[2] += c.y
		v[3] += 1
		v[4] = minf(v[4], c.y)
		v[5] = maxf(v[5], c.y)
	var out := {}
	for g in acc:
		var v: Array = acc[g]
		var ang: float = atan2(v[0], v[1])
		var spread: float = sqrt(v[0] * v[0] + v[1] * v[1]) / v[3]   # 1 = compact in x
		out[g] = {"x": fposmod(ang / TAU * W, W), "z": v[2] / v[3], "n": v[3], "spread": spread, "dz": v[5] - v[4]}
	return out


func _build_labels(frame: HistoryFrame) -> void:
	if not show_labels:
		return
	var ids := PackedInt32Array()
	var names := {}
	match label_mode:
		"peoples":
			ids = frame.people
			for k in frame.peoples:
				names[k] = frame.peoples[k].get("name", "")
		"religions":
			ids = frame.religion
			for k in frame.religions:
				names[k] = frame.religions[k].get("name", "")
		_:
			ids = frame.owner
			for k in frame.states:
				names[k] = frame.states[k].get("name", "")
	if ids.is_empty():
		return
	var shapes := _group_shapes(ids)
	for g in shapes:
		var sh: Dictionary = shapes[g]
		if int(sh["n"]) < 6 or str(names.get(g, "")) == "":
			continue
		var l := Label3D.new()
		l.text = str(names[g]).to_upper()
		var size := sqrt(float(sh["n"]))
		l.font_size = 96
		# CK-style: the name spans a good part of the territory it labels
		var chars := maxf(4.0, float(l.text.length()))
		l.pixel_size = clampf(size * 3.2 / (chars * 0.62 * 96.0) * 1.0, 0.012, 0.25)
		l.outline_size = 14
		l.modulate = Color(0.98, 0.94, 0.84, 0.95)
		l.outline_modulate = Color(0.06, 0.05, 0.04, 0.75)
		l.rotation_degrees = Vector3(-90, 0, 0)  # lies on the map, CK-style
		l.double_sided = true
		l.no_depth_test = true
		l.render_priority = 2
		l.modulate.a = 0.95
		l.visibility_range_begin = size * 1.6
		l.visibility_range_begin_margin = size * 1.0
		l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		l.set_meta("anchor", Vector3(sh["x"], 12.0, sh["z"]))
		add_child(l)
		_labels.append(l)


func _build_markers(frame: HistoryFrame) -> void:
	if not show_events:
		return
	for wv in frame.wars:
		var front: PackedInt32Array = wv.get("front", PackedInt32Array())
		if front.is_empty():
			continue
		_add_marker(front[front.size() / 2], Color8(210, 40, 30), "⚔")
	for ev in frame.events:
		var y := int(ev.get("year", frame.year))
		if frame.year - y > 50 or int(ev.get("cell", -1)) < 0:
			continue
		var col := Color8(220, 190, 90)
		match str(ev.get("kind", "")):
			"war", "battle": col = Color8(210, 40, 30)
			"collapse", "fall": col = Color8(90, 90, 90)
			"founding", "foundation": col = Color8(60, 150, 220)
			"plague", "catastrophe", "famine": col = Color8(140, 60, 160)
		_add_marker(int(ev["cell"]), col, "")


func _add_marker(cell: int, col: Color, glyph: String) -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = ModelLibrary.get_mesh("banner")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.scale = Vector3.ONE * 2.2
	root.add_child(mi)
	if glyph != "":
		var l := Label3D.new()
		l.text = glyph
		l.font_size = 64
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, 0.9, 0)
		l.modulate = col.lightened(0.3)
		root.add_child(l)
	mi.visibility_range_end = 400.0
	var c := world.cell_center(cell)
	root.set_meta("anchor", Vector3(c.x, maxf(mm.height_at(c.x, c.y), 0.0), c.y))
	add_child(root)
	_markers.append(root)


func _build_routes(frame: HistoryFrame) -> void:
	if not show_routes or frame.routes.is_empty():
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.78, 0.35, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = false
	for r in frame.routes:
		var cells: PackedInt32Array = r.get("cells", PackedInt32Array())
		if cells.size() < 2:
			continue
		var width := 0.12 + clampf(float(r.get("volume", 0.5)), 0.0, 1.0) * 0.3
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, mat)
		var prev := world.cell_center(cells[0])
		var pts: Array[Vector3] = []
		for c in cells:
			var p := world.cell_center(c)
			p.x = mm.wrap_x_near(p.x, prev.x)
			prev = p
			pts.append(Vector3(p.x, maxf(mm.height_at(p.x, p.y), 0.0) + 0.12, p.y))
		for k in pts.size():
			var a: Vector3 = pts[maxi(k - 1, 0)]
			var b: Vector3 = pts[mini(k + 1, pts.size() - 1)]
			var dir := (b - a)
			dir.y = 0
			var side := Vector3(-dir.z, 0, dir.x).normalized() * width * 0.5
			im.surface_add_vertex(pts[k] - side)
			im.surface_add_vertex(pts[k] + side)
		im.surface_end()
	for k in [-1, 0, 1]:
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.x = k * mm.map_w
		add_child(mi)
		_routes.append(mi)


func update_view(cam: Camera3D, zoom: float) -> void:
	var cx := cam.global_position.x
	for l in _labels:
		var a: Vector3 = l.get_meta("anchor")
		l.position = Vector3(mm.wrap_x_near(a.x, cx), a.y, a.z)
		# names belong to the world/regional views
		var fade := smoothstep(0.40, 0.56, zoom)
		l.visible = fade > 0.01
		l.modulate.a = fade * 0.95
	for m in _markers:
		var a2: Vector3 = m.get_meta("anchor")
		m.position = Vector3(mm.wrap_x_near(a2.x, cx), a2.y, a2.z)
	for k in _routes.size():
		_routes[k].position.x = (roundf(cx / mm.map_w) + (k - 1)) * mm.map_w
