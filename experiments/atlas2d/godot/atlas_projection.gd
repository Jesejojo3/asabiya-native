class_name AtlasProjection
extends RefCounted
## Pure presentation: no clocks, RNG or mutation of engine publications.

static func pick(w: WorldData, point: Vector2) -> int:
	if w == null or point.y < 0 or point.y >= w.height: return -1
	var x := fposmod(point.x, w.width)
	var id := floori(point.y) * w.width + floori(x)
	var fx := clampi(floori(x * w.detail), 0, w.fine_width - 1)
	var fy := clampi(floori(point.y * w.detail), 0, w.fine_height - 1)
	if w.elevation_fine[fy * w.fine_width + fx] > 0 and w.land_remap[id] >= 0:
		return w.land_remap[id]
	return id

static func layer(w: WorldData, frame: HistoryFrame, id: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := MapLayers.build(id, w, frame)
	result["frame"] = frame
	result["layer"] = id
	result["projection_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return result
