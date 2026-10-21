class_name HistoryOverlay
extends Node3D
## Historical annotations from engine frames: territory names lying on the
## terrain, war markers, recent events and trade routes. Rebuilt only when the
## frame changes; positions follow the longitude wrap every frame.

var profiler: PerformanceTrace
var _label_nodes := {}
var _label_values := {}
var _marker_nodes := {}
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
var _view_valid := false
var _view_x := INF
var _view_zoom := INF
var _marker_materials := {}
var _route_material: StandardMaterial3D
var _shape_ids := PackedInt32Array()
var _shapes := {}
var _longitude_sin := PackedFloat64Array()
var _longitude_cos := PackedFloat64Array()


func setup(w: WorldData, math: MapMath) -> void:
	world = w
	mm = math
	_shape_ids = PackedInt32Array()
	_shapes.clear()
	_longitude_sin.resize(world.width)
	_longitude_cos.resize(world.width)
	for x in world.width:
		var center := world.cell_center(x)
		var angle := center.x / mm.map_w * TAU
		_longitude_sin[x] = sin(angle)
		_longitude_cos[x] = cos(angle)


func clear() -> void:
	_view_valid = false
	_shape_ids = PackedInt32Array()
	_shapes.clear()
	for n in _labels:
		n.queue_free()
	for n in _markers:
		n.queue_free()
	for n in _routes:
		n.queue_free()
	_labels.clear()
	_label_nodes.clear()
	_label_values.clear()
	_marker_nodes.clear()
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
	if profiler != null: profiler.counter("annotationsPublications")
	if labels != _label_signature:
		_build_labels(frame)
		_view_valid = false
		_label_signature = labels
	elif profiler != null: profiler.counter("labelLayerCacheHits")
	var recent := []
	for event: Dictionary in frame.events:
		if frame.year - int(event.get("year", frame.year)) <= 50 and int(event.get("cell", -1)) >= 0:
			recent.append([event.get("id"), event.get("cell"), event.get("kind")])
	var fronts := []
	for war: Dictionary in frame.wars:
		var front: PackedInt32Array = war.get("front", PackedInt32Array())
		if not front.is_empty(): fronts.append(front)
	var markers := {"enabled":show_events,"events":recent,"fronts":fronts,"relief":Vector3(mm.land_scale, mm.ocean_scale, mm.relief_detail)}
	if markers != _marker_signature:
		_build_markers(frame)
		_view_valid = false
		_marker_signature = markers
	elif profiler != null: profiler.counter("markerLayerCacheHits")
	var paths := []
	for route: Dictionary in frame.routes:
		paths.append([route.get("cells", PackedInt32Array()), clampf(float(route.get("volume", 0.5)), 0.0, 1.0)])
	var routes := {"enabled":show_routes,"routes":paths,"relief":Vector3(mm.land_scale, mm.ocean_scale, mm.relief_detail)}
	if routes != _route_signature:
		for node in _routes: node.queue_free()
		_routes.clear()
		_build_routes(frame)
		_view_valid = false
		_route_signature = routes
	elif profiler != null: profiler.counter("routeLayerCacheHits")


## Wrap-aware centroid and extent of groups of cells.
func _group_shapes(ids: PackedInt32Array) -> Dictionary:
	var acc := {}
	var W := mm.map_w
	for i in world.land_cells:
		var g := ids[i]
		if g < 0:
			continue
		var c := world.cell_center(i)
		var longitude := i % world.width
		if not acc.has(g):
			acc[g] = [0.0, 0.0, 0.0, 0, INF, -INF]  # sin, cos, z, n, minz, maxz
		var v: Array = acc[g]
		v[0] += _longitude_sin[longitude]
		v[1] += _longitude_cos[longitude]
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
	var ids := frame.owner if label_mode == "states" else (frame.people if label_mode == "peoples" else frame.religion)
	var records := frame.states if label_mode == "states" else (frame.peoples if label_mode == "peoples" else frame.religions)
	var indexed: Dictionary = frame.visual_index.get("shapes", {})
	var shapes: Dictionary = {}
	if show_labels and not ids.is_empty():
		if indexed.has(label_mode):
			shapes = indexed[label_mode]
		else:
			# Legacy/manual frames retain the original exact computation.
			if ids != _shape_ids:
				_shapes = _group_shapes(ids)
				_shape_ids = ids
			shapes = _shapes
	var live := {}
	_labels.clear()
	for group: int in shapes:
		var shape: Dictionary = shapes[group]
		var text := str(records.get(group, {}).get("name", "")).to_upper()
		if int(shape["n"]) < 6 or text == "": continue
		live[group] = true
		var size := sqrt(float(shape["n"]))
		var pixel_size := clampf(size * 3.2 / (maxf(4.0, float(text.length())) * 0.62 * 96.0), 0.012, 0.25)
		var anchor := Vector3(shape["x"], 12.0, shape["z"])
		var values := [text, pixel_size, anchor, size]
		var label: Label3D = _label_nodes.get(group)
		if label == null:
			label = Label3D.new()
			label.font_size = 96
			label.outline_size = 14
			label.modulate = Color(0.98, 0.94, 0.84, 0.95)
			label.outline_modulate = Color(0.06, 0.05, 0.04, 0.75)
			label.rotation_degrees = Vector3(-90, 0, 0)
			label.double_sided = true
			label.no_depth_test = true
			label.render_priority = 2
			label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(label)
			_label_nodes[group] = label
			if profiler != null: profiler.counter("labelsCreated")
		var previous: Array = _label_values.get(group, [])
		if previous != values:
			if previous.is_empty() or previous[0] != text: label.text = text
			if previous.is_empty() or previous[1] != pixel_size: label.pixel_size = pixel_size
			if previous.is_empty() or previous[3] != size:
				label.visibility_range_begin = size * 1.6
				label.visibility_range_begin_margin = size
			if previous.is_empty() or previous[2] != anchor: label.set_meta("anchor", anchor)
			_label_values[group] = values
			if profiler != null: profiler.counter("labelsUpdated")
		elif profiler != null: profiler.counter("labelsReused")
		_labels.append(label)
	for group: int in _label_nodes.keys():
		if not live.has(group):
			(_label_nodes[group] as Label3D).queue_free()
			_label_nodes.erase(group)
			_label_values.erase(group)
			if profiler != null: profiler.counter("labelsRemoved")


func _build_markers(frame: HistoryFrame) -> void:
	var desired := {}
	if show_events:
		for index in frame.wars.size():
			var war: Dictionary = frame.wars[index]
			var front: PackedInt32Array = war.get("front", PackedInt32Array())
			if not front.is_empty(): desired["w:%s" % str(war.get("id", index))] = [front[front.size() / 2], Color8(210, 40, 30), "⚔"]
		for index in frame.events.size():
			var event: Dictionary = frame.events[index]
			if frame.year - int(event.get("year", frame.year)) > 50 or int(event.get("cell", -1)) < 0: continue
			var color := Color8(220, 190, 90)
			match str(event.get("kind", "")):
				"war", "battle": color = Color8(210, 40, 30)
				"collapse", "fall": color = Color8(90, 90, 90)
				"founding", "foundation": color = Color8(60, 150, 220)
				"plague", "catastrophe", "famine": color = Color8(140, 60, 160)
			desired["e:%s" % str(event.get("id", index))] = [int(event["cell"]), color, ""]
	_markers.clear()
	var relief := Vector3(mm.land_scale, mm.ocean_scale, mm.relief_detail)
	for key: String in desired:
		var item: Array = desired[key]
		var marker: Node3D = _marker_nodes.get(key)
		var style := [item[1], item[2]]
		if marker != null and marker.get_meta("style") != style:
			marker.queue_free()
			marker = null
		if marker == null:
			marker = _add_marker(item[0], item[1], item[2])
			marker.set_meta("style", style)
			marker.set_meta("surface", [item[0], relief])
			_marker_nodes[key] = marker
			if profiler != null: profiler.counter("markersCreated")
		elif profiler != null: profiler.counter("markersReused")
		var surface := [item[0], relief]
		if marker.get_meta("surface", []) != surface:
			var center := world.cell_center(item[0])
			marker.set_meta("anchor", Vector3(center.x, maxf(mm.height_at(center.x, center.y), 0.0), center.y))
			marker.set_meta("surface", surface)
		_markers.append(marker)
	for key: String in _marker_nodes.keys():
		if not desired.has(key):
			(_marker_nodes[key] as Node3D).queue_free()
			_marker_nodes.erase(key)
			if profiler != null: profiler.counter("markersRemoved")


func _add_marker(cell: int, col: Color, glyph: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = ModelLibrary.get_mesh("banner")
	var mat: StandardMaterial3D = _marker_materials.get(col)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.vertex_color_use_as_albedo = true
		_marker_materials[col] = mat
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
	return root


func _build_routes(frame: HistoryFrame) -> void:
	if not show_routes or frame.routes.is_empty():
		return
	var im := ImmediateMesh.new()
	if _route_material == null:
		_route_material = StandardMaterial3D.new()
		_route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_route_material.albedo_color = Color(0.95, 0.78, 0.35, 0.85)
		_route_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_route_material.vertex_color_use_as_albedo = false
	var mat := _route_material
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
	if _view_valid and cx == _view_x and zoom == _view_zoom: return
	_view_valid = true
	_view_x = cx
	_view_zoom = zoom
	var fade := smoothstep(0.40, 0.56, zoom)
	for l in _labels:
		var a: Vector3 = l.get_meta("anchor")
		var position_next := Vector3(mm.wrap_x_near(a.x, cx), a.y, a.z)
		if l.position != position_next: l.position = position_next
		# names belong to the world/regional views
		if l.visible != (fade > 0.01): l.visible = fade > 0.01
		if l.modulate.a != fade * 0.95: l.modulate.a = fade * 0.95
	for m in _markers:
		var a2: Vector3 = m.get_meta("anchor")
		var position_next := Vector3(mm.wrap_x_near(a2.x, cx), a2.y, a2.z)
		if m.position != position_next: m.position = position_next
	for k in _routes.size():
		var wrapped := (roundf(cx / mm.map_w) + (k - 1)) * mm.map_w
		if _routes[k].position.x != wrapped: _routes[k].position.x = wrapped
