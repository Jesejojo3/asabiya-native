class_name VegetationLayer
extends InstanceBands
## DECORATIVE ONLY. Trees, shrubs and rocks scattered from the engine's
## geography (biome, initial forest cover forest0, elevation). They carry no
## causal meaning, are not selectable and never represent historical forest
## change; when the engine exposes current forest cover they can follow it.
## Built lazily per 80×80 tile near the camera, at most one tile per frame.

const BUILD_RADIUS := 150.0
# Keep one extra tile ring to avoid churn at the construction boundary.
const RETAIN_RADIUS := BUILD_RADIUS + 80.0

var world: WorldData
var enabled := true
var _task := -1
var _task_key := -1
var _task_result := {}
var _task_generation := 0
var _generation := 0
var _camera: Camera3D
var _focus_valid := false
var _last_focus := Vector2.ZERO
var _search_dirty := true
var _last_publish_frame := -1
var _clearings: Array = []   # [Vector2 centre, radius] around engine settlements


func setup_veg(w: WorldData, math: MapMath) -> void:
	world = w
	setup(math, 80.0, 95.0)
	cast_shadows = false
	visibility_margin = 20.0
	set_process(false)


func clear() -> void:
	# A relief change may invalidate work already running. Discard its result
	# after completion; never wait for a tile computation on an annual update.
	_generation += 1
	_focus_valid = false
	_search_dirty = true
	super.clear()
	if is_instance_valid(_camera): set_process(true)


func _process(_dt: float) -> void:
	if is_instance_valid(_camera): update_view(_camera)
	else: set_process(false)


func update_view(cam: Camera3D) -> void:
	_camera = cam
	var started := profiler.begin() if profiler != null else 0
	_update_tiles(cam)
	if profiler != null: profiler.end("vegetation", started)


func _update_tiles(cam: Camera3D) -> void:
	var t := cam.global_position
	var focus := Vector2(t.x, t.z)
	if cam is StrategyCamera:
		focus = Vector2((cam as StrategyCamera).target.x, (cam as StrategyCamera).target.z)
	if not _focus_valid or focus != _last_focus:
		_focus_valid = true
		_last_focus = focus
		_search_dirty = true
		_prune(focus)
	# Keep draining the worker independently of camera invalidation. Never
	# publish two tiles in one process frame, even if both callbacks run.
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task) and _last_publish_frame != Engine.get_process_frames():
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_last_publish_frame = Engine.get_process_frames()
		if profiler != null and _task_result.has("computeUsec"):
			profiler.worker_span("vegetation-compute", int(_task_result["computeUsec"]))
			profiler.worker_span("vegetation-pack", int(_task_result["packUsec"]))
		if enabled and _task_generation == _generation and _near_band(_task_key, focus, RETAIN_RADIUS):
			var published := profiler.begin() if profiler != null else 0
			set_band_buffers(_task_key, _task_result.get("bands", {}))
			if profiler != null: profiler.end("vegetation-publish", published)
		elif profiler != null: profiler.counter("vegetationTasksDiscarded")
		_task_result = {}
		_search_dirty = true
	super.update_view(cam)
	if _task >= 0:
		set_process(true)
		return
	if not enabled or t.y > BUILD_RADIUS or not _search_dirty:
		set_process(false)
		return
	var nx := maxi(1, ceili(mm.map_w / band_width))
	var nz := maxi(1, ceili(mm.map_h / band_width))
	var tx0 := floori((focus.x - BUILD_RADIUS) / band_width)
	var tx1 := floori((focus.x + BUILD_RADIUS) / band_width)
	var tz0 := maxi(0, floori((focus.y - BUILD_RADIUS) / band_width))
	var tz1 := mini(nz - 1, floori((focus.y + BUILD_RADIUS) / band_width))
	var best := -1
	var best_d := INF
	for tz in range(tz0, tz1 + 1):
		for tx in range(tx0, tx1 + 1):
			var key := tz * 1000 + posmod(tx, nx)
			if has_band(key): continue
			var c := band_origin(key) + Vector2.ONE * band_width * 0.5
			c.x = mm.wrap_x_near(c.x, focus.x)
			var d := c.distance_squared_to(focus)
			if d < best_d:
				best_d = d
				best = key
	_search_dirty = false
	if best < 0:
		set_process(false)
		return
	_task_key = best
	_task_generation = _generation
	var clearings: Array = _clearings.duplicate(true)
	var math := MapMath.new()
	math.setup(world)
	math.land_scale = mm.land_scale
	math.ocean_scale = mm.ocean_scale
	math.relief_detail = mm.relief_detail
	math.warp_amp = mm.warp_amp
	var profiling := profiler != null and profiler.enabled()
	_task = WorkerThreadPool.add_task(func(): _task_result = _prepare_tile(best, clearings, math, profiling), false, "vegetation")
	set_process(true)


func _prepare_tile(key: int, clearings: Array, math: MapMath, profiling := false) -> Dictionary:
	var started := Time.get_ticks_usec() if profiling else 0
	var transforms := _compute_tile(key, clearings, math)
	var computed := Time.get_ticks_usec() if profiling else 0
	var packed := {}
	var origin := band_origin(key)
	for kind: String in transforms:
		var instances: Array = transforms[kind]
		if not instances.is_empty():
			packed[kind] = {"count":instances.size(),"buffer":pack_instances(instances, origin, band_width, math)}
	var result := {"bands":packed}
	if profiling:
		result["computeUsec"] = computed - started
		result["packUsec"] = Time.get_ticks_usec() - computed
	return result


func _near_band(key: int, focus: Vector2, radius: float) -> bool:
	var o := band_origin(key)
	var cx := mm.wrap_x_near(o.x + band_width * 0.5, focus.x)
	var dx := maxf(0.0, absf(cx - focus.x) - band_width * 0.5)
	var dz := maxf(0.0, absf(o.y + band_width * 0.5 - focus.y) - band_width * 0.5)
	return dx * dx + dz * dz <= radius * radius


func _prune(focus: Vector2) -> void:
	for key: int in _bands.keys():
		if not _near_band(key, focus, RETAIN_RADIUS):
			clear_band(key)


## Keep unaffected tiles when settlement clearings change. The worker uses
## private snapshots of both clearings and relief parameters.
func set_clearings(list: Array) -> void:
	if list == _clearings:
		return
	var old := {}
	var next := {}
	for c in _clearings: old[c[0]] = c[1]
	for c in list: next[c[0]] = c[1]
	var changed := []
	for center: Vector2 in old:
		if not next.has(center) or next[center] != old[center]:
			changed.append([center, old[center]])
	for center: Vector2 in next:
		if not old.has(center) or old[center] != next[center]:
			changed.append([center, next[center]])
	_generation += 1
	_clearings = list.duplicate(true)
	_search_dirty = true
	if is_instance_valid(_camera): set_process(true)
	for key: int in _bands.keys():
		for c in changed:
			if _near_band(key, c[0], float(c[1])):
				clear_band(key)
				break


func _cleared_in(list: Array, px: float, pz: float) -> bool:
	for c in list:
		var d := Vector2(mm.wrap_x_near(px, c[0].x), pz).distance_to(c[0])
		if d < c[1]:
			return true
	return false


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	if on: _search_dirty = true
	set_process(is_instance_valid(_camera) and (on or _task >= 0))


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Pure computation (thread-safe: reads immutable world data only).
func compute_tile(key: int) -> Dictionary:
	return _compute_tile(key, _clearings, mm)


func _compute_tile(key: int, clearings: Array, math: MapMath) -> Dictionary:
	var o := band_origin(key)
	var kinds := {"conifer": [], "broadleaf": [], "palm": [], "shrub": [], "rock": []}
	var cs := world.detail
	var cx0 := int(o.x) / cs
	var cz0 := int(o.y) / cs
	var n := ceili(band_width / cs)
	var local_clear := []
	var tile_c := o + Vector2(band_width, band_width) * 0.5
	for c in clearings:
		var cc: Vector2 = c[0]
		var radius := float(c[1])
		if absf(math.wrap_x_near(cc.x, tile_c.x) - tile_c.x) <= band_width * 0.5 + radius and absf(cc.y - tile_c.y) <= band_width * 0.5 + radius:
			local_clear.append(c)
	for cz in range(cz0, mini(cz0 + n, world.height)):
		for cxi in range(cx0, mini(cx0 + n, world.width)):
			var cid := world.cell_id(cxi, cz)
			if cid < 0 or world.land[cid] != 1:
				continue
			var b := int(world.biome[cid])
			var forest := world.forest0[cid]
			var count := 0
			var kind := ""
			match b:
				3: # boreal
					kind = "conifer"
					count = int(forest * 26.0)
				4: # temperate forest
					kind = "broadleaf"
					count = int(forest * 24.0)
				9: # tropical forest
					kind = "broadleaf"
					count = int(forest * 30.0)
				8: # savanna
					kind = "palm"
					count = int(forest * 10.0) + 2
				5, 6: # grassland, steppe
					kind = "shrub"
					count = 3 + int(forest * 8.0)
				2: # tundra
					kind = "shrub"
					count = 1
				7: # desert
					kind = "rock"
					count = 2
			if count <= 0:
				continue
			# trees grow in groves: a few clump centres per cell
			count *= 2
			var groves := maxi(1, count / 9)
			for k in count:
				var g := k % groves
				var gx := 0.15 + 0.7 * MapMath.rnd(cid, 9000 + g * 2)
				var gz := 0.15 + 0.7 * MapMath.rnd(cid, 9001 + g * 2)
				var hx := clampf(gx + (MapMath.rnd(cid, k * 3 + 1) - 0.5) * 0.45, 0.0, 0.999)
				var hz := clampf(gz + (MapMath.rnd(cid, k * 3 + 2) - 0.5) * 0.45, 0.0, 0.999)
				var hs := MapMath.rnd(cid, k * 3 + 3)
				var px := (cxi + hx) * cs
				var pz := (cz + hz) * cs
				if not math.is_land_at(px, pz) or (not local_clear.is_empty() and _cleared_in(local_clear, px, pz)):
					continue
				var e := math.elev_bilinear(px, pz)
				var kk := kind
				if e > 2600.0:
					kk = "rock" if hs < 0.5 else "conifer"
				if e > 4200.0:
					continue
				var y := math.height_at(px, pz)
				var s := (0.75 + hs * 0.6) * 2.2
				var basis := Basis(Vector3.UP, hs * TAU).scaled(Vector3(s, s, s))
				(kinds[kk] as Array).append(Transform3D(basis, Vector3(px, y - 0.01, pz)))
	return kinds
