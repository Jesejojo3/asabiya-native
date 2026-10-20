extends SceneTree
## Focused technical regressions. Does not load the app scene or run Go.
const Terrain := preload("res://scripts/map/terrain_renderer.gd")
const Vegetation := preload("res://scripts/map/vegetation_layer.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	_test_grid()
	_test_sampling()
	await _test_vegetation()
	print("Performance regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_grid() -> void:
	var terrain := Terrain.new()
	for n in [1, 2, 10, 20, 40, 80, 160]:
		var mesh: ArrayMesh = terrain._grid_mesh(n)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(vertices.size() == (n + 1) * (n + 1) + n * 4, "grid vertex and skirt count")
		check(indices == _original_indices(n), "grid winding and topology match the original at LOD %d" % n)
	terrain.free()


func _original_indices(n: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			idx.append_array([a, b, d, a, d, c] if (i + j) % 2 == 0 else [a, b, c, b, d, c])
	var ring: Array[int] = []
	for i in n + 1: ring.append(i)
	for j in range(1, n + 1): ring.append(j * (n + 1) + n)
	for i in range(n - 1, -1, -1): ring.append(n * (n + 1) + i)
	for j in range(n - 1, 0, -1): ring.append(j * (n + 1))
	var base := (n + 1) * (n + 1)
	for k in ring.size():
		var a: int = ring[k]
		var b: int = ring[(k + 1) % ring.size()]
		var c := base + k
		var d := base + (k + 1) % ring.size()
		idx.append_array([a, c, b, b, c, d])
		idx.append_array([a, b, c, b, d, c])
	return idx


func _test_sampling() -> void:
	var w := WorldData.new()
	w.width = 24
	w.height = 16
	w.detail = 4
	w.fine_width = 96
	w.fine_height = 64
	w.elevation_fine.resize(w.fine_width * w.fine_height)
	for i in w.elevation_fine.size():
		w.elevation_fine[i] = sin(float(i) * 0.13) * 3000.0
	var math := MapMath.new()
	math.setup(w)
	for point in [Vector2(-0.1, -0.3), Vector2(95.9, 64.2), Vector2(0.5, 0.5), Vector2(33.7, 40.2)]:
		var ix := floori(point.x - 0.5)
		var iz := floori(point.y - 0.5)
		var fx := point.x - 0.5 - ix
		var fz := point.y - 0.5 - iz
		var rows: Array[float] = []
		for j in range(-1, 3):
			rows.append(MapMath._cr(math._texel(ix - 1, iz + j), math._texel(ix, iz + j), math._texel(ix + 1, iz + j), math._texel(ix + 2, iz + j), fx))
		var expected := MapMath._cr(rows[0], rows[1], rows[2], rows[3], fz)
		check(math.elev_bicubic(point.x, point.y) == expected, "bicubic preserves sample order, seam and pole clamping")


func _test_vegetation() -> void:
	var w := WorldData.new()
	w.width = 400
	w.height = 200
	w.detail = 4
	w.fine_width = 1600
	w.fine_height = 800
	w.land.resize(w.cell_count())
	w.land.fill(0) # Empty geography keeps this a scheduling/resource test.
	var math := MapMath.new()
	math.setup(w)
	var veg := Vegetation.new()
	root.add_child(veg)
	veg.setup_veg(w, math)
	for key in [0, 10, 19]:
		veg.set_band(key, {})
	veg._prune(Vector2(40, 40))
	check(veg.has_band(0) and veg.has_band(19) and not veg.has_band(10), "pruning releases distant tiles and preserves longitude neighbours")
	veg.set_clearings([[Vector2(40, 40), 1.0]])
	check(not veg.has_band(0) and veg.has_band(19), "clearing invalidates only intersecting tiles")
	veg.clear()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(40, 20, 40)
	veg.update_view(cam)
	var task: int = veg._task
	check(task >= 0, "vegetation schedules one worker")
	veg.set_clearings([[Vector2(40, 40), 2.0]])
	check(veg._task == task, "clearing invalidation does not join the worker on the annual publication path")
	veg.enabled = false
	while task >= 0 and not WorkerThreadPool.is_task_completed(task):
		await process_frame
	veg.update_view(cam)
	check(veg._task == -1 and veg._bands.is_empty() and veg._task_result.is_empty(), "invalidated completion is discarded and its transforms released")
	veg.free()
	cam.free()
	await process_frame
