class_name MapLayers
extends RefCounted
## Thematic map modes drawn on the 3D terrain itself (no separate flat maps).
##
## Each layer turns world data and, when the engine provides it, a HistoryFrame
## into a per-cell colour (RGBA8) plus a grouping key used for borders. Layers
## that need historical systems stay disabled until the Go engine supplies
## them; the client never substitutes invented values.

const RAMP := [Color8(48, 18, 59), Color8(70, 107, 227), Color8(40, 187, 236), Color8(50, 241, 152),
	Color8(164, 252, 60), Color8(237, 208, 58), Color8(251, 128, 34), Color8(200, 40, 20)]

## id, name, group, required system ("" = geography), key border strength
const DEFS := [
	{"id": "terrain", "name": "Terreno", "group": "Geografía", "requires": "", "borders": 0.0},
	{"id": "provinces", "name": "Provincias", "group": "Geografía", "requires": "", "borders": 0.0},
	{"id": "biomes", "name": "Biomas", "group": "Geografía", "requires": "", "borders": 0.55},
	{"id": "elevation", "name": "Altitud", "group": "Geografía", "requires": "", "borders": 0.0},
	{"id": "landmass", "name": "Masas de tierra", "group": "Geografía", "requires": "", "borders": 0.8},
	{"id": "temperature", "name": "Temperatura", "group": "Clima", "requires": "", "borders": 0.0},
	{"id": "precipitation", "name": "Precipitación", "group": "Clima", "requires": "", "borders": 0.0},
	{"id": "farming", "name": "Aptitud agrícola", "group": "Recursos", "requires": "", "borders": 0.0},
	{"id": "herding", "name": "Aptitud pastoral", "group": "Recursos", "requires": "", "borders": 0.0},
	{"id": "forest", "name": "Bosque inicial", "group": "Recursos", "requires": "", "borders": 0.0},
	{"id": "travel", "name": "Coste de viaje", "group": "Recursos", "requires": "", "borders": 0.0},
	{"id": "malaria", "name": "Malaria", "group": "Recursos", "requires": "", "borders": 0.0},
	{"id": "states", "name": "Estados", "group": "Política", "requires": "states", "borders": 1.0},
	{"id": "wars", "name": "Guerras", "group": "Política", "requires": "wars", "borders": 1.0},
	{"id": "peoples", "name": "Pueblos", "group": "Cultura", "requires": "peoples", "borders": 0.8},
	{"id": "cultures", "name": "Culturas", "group": "Cultura", "requires": "peoples", "borders": 0.7},
	{"id": "languages", "name": "Lenguas", "group": "Cultura", "requires": "peoples", "borders": 0.7},
	{"id": "religions", "name": "Religiones", "group": "Cultura", "requires": "religions", "borders": 0.8},
	{"id": "population", "name": "Población", "group": "Demografía", "requires": "population", "borders": 0.0},
	{"id": "carrying", "name": "Capacidad de carga", "group": "Demografía", "requires": "carrying", "borders": 0.0},
	{"id": "technology", "name": "Tecnología", "group": "Demografía", "requires": "technology", "borders": 0.0},
	{"id": "economy", "name": "Economía", "group": "Economía", "requires": "economy", "borders": 0.0},
	{"id": "routes", "name": "Rutas comerciales", "group": "Economía", "requires": "routes", "borders": 0.0},
]

const BIOME_LEGEND := [
	Color8(234, 239, 240), Color8(170, 175, 158), Color8(104, 124, 98), Color8(121, 145, 96),
	Color8(174, 178, 121), Color8(196, 186, 137), Color8(216, 199, 160), Color8(188, 177, 112), Color8(84, 126, 79)]


static func def(id: String) -> Dictionary:
	for d in DEFS:
		if d["id"] == id:
			return d
	return {}


static func available(id: String, source: HistorySource, frame: HistoryFrame) -> bool:
	var d := def(id)
	var req: String = d.get("requires", "")
	if req == "":
		return true
	return source != null and source.has_system(req) and frame != null


static func ramp(t: float) -> Color:
	t = clampf(t, 0.0, 1.0) * (RAMP.size() - 1)
	var k := mini(RAMP.size() - 2, floori(t))
	return (RAMP[k] as Color).lerp(RAMP[k + 1], t - k)


## Golden-angle hue for stable, distinct colours per integer id.
static func id_color(id: int, sat := 0.55, val := 0.82) -> Color:
	return Color.from_hsv(fposmod(id * 0.61803398875, 1.0), sat, val)


## Go exports six culture components, not one scalar index. RGB displays
## components 1–3 only; the complete vector stays available in the people panel.
## This is a visual encoding, not a new cultural metric in the simulation.
static func culture_color(value: Variant) -> Variant:
	if not value is Array or value.size() != 6:
		return null
	for component: Variant in value:
		if not (component is float or component is int):
			return null
		if not is_finite(float(component)) or float(component) < 0.0 or float(component) > 1.0:
			return null
	return Color(0.25 + 0.65 * float(value[0]), 0.25 + 0.65 * float(value[1]), 0.25 + 0.65 * float(value[2]))


static func war_participants(wars: Array) -> Dictionary:
	var participants := {}
	for war: Dictionary in wars:
		for side: String in ["attackers", "defenders"]:
			var members: Variant = war.get(side)
			if members is Array:
				for member: Variant in members:
					var id := int(member)
					if id > 0: participants[id] = true
		# Legacy presentation frames may only have a/b. Native frames retain
		# both complete coalitions, including participants beyond their leaders.
		for side: String in ["a", "b"]:
			var id := int(war.get(side, 0))
			if id > 0: participants[id] = true
	return participants


## Returns {colors: PackedByteArray (RGBA8), keys: PackedFloat32Array,
##          legend: {kind: "ramp"|"swatches"|"none", ...}}
static func build(id: String, w: WorldData, frame: HistoryFrame) -> Dictionary:
	var n := w.cell_count()
	var colors := PackedByteArray()
	colors.resize(n * 4)
	var keys := PackedFloat32Array()
	keys.resize(n)
	keys.fill(-1.0)
	var legend := {"kind": "none"}
	var put := func(i: int, c: Color, a: float) -> void:
		colors[i * 4] = c.r8
		colors[i * 4 + 1] = c.g8
		colors[i * 4 + 2] = c.b8
		colors[i * 4 + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
	match id:
		"terrain", "provinces":
			for i in w.land_cells:
				keys[i] = 0.0
		"biomes":
			for i in w.land_cells:
				var b := int(w.biome[i])
				put.call(i, BIOME_LEGEND[clampi(b - 1, 0, 8)], 0.75)
				keys[i] = b
			var sw := []
			for b in range(1, 10):
				sw.append([BIOME_LEGEND[b - 1], WorldData.BIOME_NAMES_ES[b]])
			legend = {"kind": "swatches", "items": sw}
		"elevation":
			for i in w.land_cells:
				put.call(i, ramp(w.elevation[i] / 5000.0), 0.8)
			legend = {"kind": "ramp", "min": "0 m", "max": "5000 m"}
		"landmass":
			for i in w.land_cells:
				put.call(i, id_color(w.landmass[i], 0.45, 0.85), 0.7)
				keys[i] = w.landmass[i]
			legend = {"kind": "text", "text": "Cada color es una masa de tierra conectada del motor."}
		"temperature":
			for i in w.land_cells:
				put.call(i, ramp((w.temperature[i] + 25.0) / 55.0), 0.8)
			legend = {"kind": "ramp", "min": "−25 °C", "max": "30 °C"}
		"precipitation":
			for i in w.land_cells:
				put.call(i, ramp(sqrt(w.precipitation[i] / 3000.0)), 0.8)
			legend = {"kind": "ramp", "min": "0 mm", "max": "3000 mm"}
		"farming":
			for i in w.land_cells:
				put.call(i, ramp(w.farming[i]), 0.8)
			legend = {"kind": "ramp", "min": "0", "max": "1 (sF)"}
		"herding":
			for i in w.land_cells:
				put.call(i, ramp(w.herding[i]), 0.8)
			legend = {"kind": "ramp", "min": "0", "max": "1 (sH)"}
		"forest":
			for i in w.land_cells:
				var f := w.forest0[i]
				if f > 0.05:
					put.call(i, Color8(34, 110, 52), 0.15 + 0.75 * f)
			legend = {"kind": "swatches", "items": [[Color8(34, 110, 52), "Cobertura forestal inicial (forest0)"]]}
		"travel":
			for i in w.land_cells:
				put.call(i, ramp(float(w.travel_cost[i]) / 12.0), 0.8)
			legend = {"kind": "ramp", "min": "fácil", "max": "difícil (tcost)"}
		"malaria":
			for i in w.land_cells:
				if w.malaria[i] > 0.02:
					put.call(i, ramp(w.malaria[i]), 0.25 + 0.6 * w.malaria[i])
			legend = {"kind": "ramp", "min": "0", "max": "1"}
		"states":
			if frame != null and frame.has_layer("owner"):
				var palette := {}
				for state: int in frame.states:
					palette[state] = frame.states[state].get("rgb", id_color(state))
				for i in w.land_cells:
					var s := frame.owner[i]
					if s >= 0 and frame.states.has(s):
						put.call(i, palette[s], 0.62)
						keys[i] = s
		"wars":
			if frame != null and frame.has_layer("owner"):
				var at_war := war_participants(frame.wars)
				for i in w.land_cells:
					var s := frame.owner[i]
					if s > 0:
						keys[i] = s
						if at_war.has(s):
							put.call(i, Color8(200, 50, 40), 0.45)
				for wv in frame.wars:
					for c in wv.get("front", PackedInt32Array()):
						put.call(c, Color8(240, 40, 25), 0.85)
		"peoples", "cultures", "languages":
			if frame != null and frame.has_layer("people"):
				# Validate cultural vectors / convert HSV once per entity, not
				# once per province. Keep the same colours and grouping keys.
				var palette := {}
				for people: int in frame.peoples:
					var info: Dictionary = frame.peoples[people]
					var group := people
					var color: Variant = info.get("rgb", id_color(people))
					if id == "cultures":
						color = culture_color(info.get("culture"))
					elif id == "languages":
						group = int(info.get("family", people))
						color = id_color(group * 7 + 3, 0.6, 0.78)
					if color != null: palette[people] = [color, group]
				for i in w.land_cells:
					var people := frame.people[i]
					if people < 0 or not palette.has(people): continue
					var entry: Array = palette[people]
					put.call(i, entry[0], 0.62)
					keys[i] = entry[1]
				if id == "cultures":
					legend = {"kind":"text", "text":"Color: componentes 1–3 del vector cultural. Consulta los seis valores en cada pueblo; límites por pueblo."}
		"religions":
			if frame != null and frame.has_layer("religion"):
				var palette := {}
				for religion: int in frame.religions:
					palette[religion] = frame.religions[religion].get("rgb", id_color(religion))
				for i in w.land_cells:
					var r := frame.religion[i]
					if r >= 0 and frame.religions.has(r):
						put.call(i, palette[r], 0.65)
						keys[i] = r
		"population":
			if frame != null and frame.has_layer("population"):
				for i in w.land_cells:
					var p := frame.population[i]
					if p >= 1.0:
						put.call(i, ramp((log(p / maxf(w.area[i], 1.0)) / log(10.0) + 2.0) / 4.0), 0.8)
				legend = {"kind": "ramp", "min": "0,01 hab/km²", "max": "100 hab/km²"}
		"carrying":
			if frame != null and frame.has_layer("carrying"):
				for i in w.land_cells:
					var k2 := frame.carrying[i]
					if k2 > 0.0:
						put.call(i, ramp((log(k2 / maxf(w.area[i], 1.0)) / log(10.0) + 2.0) / 4.0), 0.8)
				legend = {"kind": "ramp", "min": "0,01 /km²", "max": "100 /km²"}
		"technology":
			if frame != null and frame.has_layer("technology"):
				var has_population := frame.has_layer("population")
				for i in w.land_cells:
					if has_population and frame.population[i] < 1.0:
						continue
					put.call(i, ramp(frame.technology[i]), 0.8)
				legend = {"kind": "ramp", "min": "inicial", "max": "avanzada"}
		"economy":
			if frame != null and frame.has_layer("wealth"):
				for i in w.land_cells:
					if frame.wealth[i] > 0.0:
						put.call(i, ramp(frame.wealth[i]), 0.8)
				legend = {"kind": "ramp", "min": "baja", "max": "alta"}
	return {"colors": colors, "keys": keys, "legend": legend}

## Immutable inputs that determine the rendered overlay. Changes to rulers,
## chronicles or population cannot invalidate a purely political/cultural map.
## World identity prevents reuse across sessions with different geography.
static func signature(id: String, world: WorldData, frame: HistoryFrame) -> Dictionary:
	var key := {"layer":id,"world":world.get_instance_id()}
	if frame == null:
		key["frame"] = false
		return key
	var records: Dictionary = {}
	match id:
		"states":
			key["cells"] = frame.owner
			for i: int in frame.states: records[i] = frame.states[i].get("rgb",id_color(i))
		"wars":
			key["cells"] = frame.owner
			key["participants"] = war_participants(frame.wars)
			var fronts := []
			for war: Dictionary in frame.wars: fronts.append(war.get("front",PackedInt32Array()))
			key["fronts"] = fronts
		"peoples","cultures","languages":
			key["cells"] = frame.people
			for i: int in frame.peoples:
				var p: Dictionary = frame.peoples[i]
				records[i] = p.get("rgb",id_color(i)) if id=="peoples" else (p.get("culture") if id=="cultures" else p.get("family",i))
		"religions":
			key["cells"] = frame.religion
			for i: int in frame.religions: records[i] = frame.religions[i].get("rgb",id_color(i))
		"population": key["values"] = frame.population
		"carrying": key["values"] = frame.carrying
		"technology": key["values"] = frame.technology; key["population"] = frame.population
		"economy": key["values"] = frame.wealth
	key["records"] = records
	return key
