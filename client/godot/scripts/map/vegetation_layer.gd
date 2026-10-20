class_name VegetationLayer
extends InstanceBands
## DECORATIVE ONLY. Trees, shrubs and rocks scattered from the engine's
## geography (biome, initial forest cover forest0, elevation). They carry no
## causal meaning, are not selectable and never represent historical forest
## change; when the engine exposes current forest cover they can follow it.
## Built lazily per 80×80 tile near the camera, at most one tile per frame.

const BUILD_RADIUS := 150.0

var world: WorldData
var enabled := true
var _task := -1
var _task_key := -1
var _task_result := {}
var _clearings: Array = []   # [Vector2 centre, radius] around engine settlements


func setup_veg(w: WorldData, math: MapMath) -> void:
	world = w
	setup(math, 80.0, 95.0)
	cast_shadows = false
	visibility_margin = 20.0


func update_view(cam: Camera3D) -> void:
	super.update_view(cam)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		set_band(_task_key, _task_result)
	if not enabled or _task >= 0:
		return
	var t := cam.global_position
	if t.y > BUILD_RADIUS:
		return
	# build the nearest missing tile around the camera focus, off the main thread
	var focus := Vector2(t.x, t.z)
	if cam is StrategyCamera:
		focus = Vector2((cam as StrategyCamera).target.x, (cam as StrategyCamera).target.z)
	var tx0 := floori((focus.x - BUILD_RADIUS) / band_width)
	var tx1 := floori((focus.x + BUILD_RADIUS) / band_width)
	var tz0 := maxi(0, floori((focus.y - BUILD_RADIUS) / band_width))
	var tz1 := mini(floori(mm.map_h / band_width) - 1, floori((focus.y + BUILD_RADIUS) / band_width))
	var best := -1
	var best_d := INF
	for tz in range(tz0, tz1 + 1):
		for tx in range(tx0, tx1 + 1):
			var key := tz * 1000 + posmod(tx, int(mm.map_w / band_width))
			if has_band(key):
				continue
			var c := Vector2((tx + 0.5) * band_width, (tz + 0.5) * band_width)
			var d := c.distance_to(focus)
			if d < best_d:
				best_d = d
				best = key
	if best >= 0:
		_task_key = best
		_task = WorkerThreadPool.add_task(func(): _task_result = compute_tile(best), false, "vegetation")


## Keeps decoration out of engine settlements. Rebuilds the affected tiles.
func set_clearings(list: Array) -> void:
	if list == _clearings:
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_clearings = list
	clear()


func _cleared_in(list: Array, px: float, pz: float) -> bool:
	for c in list:
		var d := Vector2(mm.wrap_x_near(px, c[0].x), pz).distance_to(c[0])
		if d < c[1]:
			return true
	return false


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Pure computation (thread-safe: reads immutable world data only).
func compute_tile(key: int) -> Dictionary:
	var o := band_origin(key)
	var kinds := {"conifer": [], "broadleaf": [], "palm": [], "shrub": [], "rock": []}
	var cs := world.detail
	var cx0 := int(o.x) / cs
	var cz0 := int(o.y) / cs
	var n := int(band_width) / cs
	var local_clear := []
	var tile_c := o + Vector2(band_width, band_width) * 0.5
	for c in _clearings:
		var cc: Vector2 = c[0]
		if absf(mm.wrap_x_near(cc.x, tile_c.x) - tile_c.x) < band_width and absf(cc.y - tile_c.y) < band_width:
			local_clear.append(c)
	for cz in range(cz0, mini(cz0 + n, world.height)):
		for cxi in range(cx0, cx0 + n):
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
				if not mm.is_land_at(px, pz) or (not local_clear.is_empty() and _cleared_in(local_clear, px, pz)):
					continue
				var e := mm.elev_bilinear(px, pz)
				var kk := kind
				if e > 2600.0:
					kk = "rock" if hs < 0.5 else "conifer"
				if e > 4200.0:
					continue
				var y := mm.height_at(px, pz)
				var s := (0.75 + hs * 0.6) * 2.2
				var basis := Basis(Vector3.UP, hs * TAU).scaled(Vector3(s, s, s))
				(kinds[kk] as Array).append(Transform3D(basis, Vector3(px, y - 0.01, pz)))
	return kinds
