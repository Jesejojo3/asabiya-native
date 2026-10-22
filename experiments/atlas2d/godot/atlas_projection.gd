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

## Overlay for a historical map layer returned by Go `get_historical_layer`
## (land provinces only; recorded every 50 years, older than 1500 years every
## 250). Same colour conventions as the live layers; values are not altered.
static func historical(w: WorldData, frame: HistoryFrame, data: Dictionary, mode: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var n := w.cell_count()
	var colors := PackedByteArray()
	colors.resize(n * 4)
	var keys := PackedFloat32Array()
	keys.resize(n)
	keys.fill(-1.0)
	var cells: Array = data.get("provinceIds", [])
	var field: Array = data.get({"peoples":"peopleIds","religions":"religionIds","population":"densityLog","technology":"era","cohesion":"cohesionByte"}.get(mode, "peopleIds"), [])
	var eras := 1
	for value: Variant in data.get("era", []):
		if int(value) != 255: eras = maxi(eras, int(value) + 1)
	var legend := {"kind":"ramp","min":"bajo","max":"alto"}
	for k in mini(cells.size(), field.size()):
		var i := int(cells[k])
		if i < 0 or i >= n: continue
		var v := int(field[k])
		var c := Color()
		match mode:
			"peoples", "religions":
				if v < 0: continue
				var kind := "people" if mode == "peoples" else "religion"
				var rgb: Variant = AtlasEntities.record(frame, kind, v).get("rgb")
				c = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2])) if rgb is Array and rgb.size() == 3 else MapLayers.id_color(v)
				keys[i] = v
			"population":
				if v <= 0: continue
				c = MapLayers.ramp(v / 252.0)
			"technology":
				if v == 255: continue
				c = MapLayers.ramp(float(v) / maxf(1.0, eras - 1))
			"cohesion":
				c = MapLayers.ramp(v / 255.0)
		colors[i * 4] = c.r8
		colors[i * 4 + 1] = c.g8
		colors[i * 4 + 2] = c.b8
		colors[i * 4 + 3] = 158
	match mode:
		"peoples", "religions": legend = {"kind":"text","text":"Colores de entidades Go en la capa histórica."}
		"population": legend = {"kind":"ramp","min":"0,01 hab/km²","max":"100 hab/km²"}
		"technology": legend = {"kind":"ramp","min":"era inicial","max":"era más avanzada de la capa"}
		"cohesion": legend = {"kind":"ramp","min":"0","max":"1"}
	return {"colors":colors, "keys":keys, "legend":legend, "frame":frame, "layer":"historical:" + mode,
		"borders":0.8 if mode in ["peoples","religions"] else 0.0, "historicalYear":int(data.get("year", 0)),
		"projection_ms":(Time.get_ticks_usec() - started) / 1000.0}


static func layer(w: WorldData, frame: HistoryFrame, id: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := MapLayers.build(id, w, frame)
	result["frame"] = frame
	result["layer"] = id
	result["projection_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return result
