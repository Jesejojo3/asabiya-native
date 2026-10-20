class_name NativeFrameDecoder
extends RefCounted
## Worker-owned publication adapter for asabiya/state-v1 / annual-delta-v1.
## No simulation rules live here. Packed arrays are copied explicitly when
## published; UI code treats every HistoryFrame as immutable.

const MAX_VISIBLE_EVENTS := 1000

var world: WorldData
var year := 0
var digest := ""
var world_digest := ""
var owner := PackedInt32Array()
var people := PackedInt32Array()
var religion := PackedInt32Array()
var population := PackedFloat32Array()
var carrying := PackedFloat32Array()
var technology := PackedFloat32Array()
var fortification := PackedFloat32Array()
var era := PackedInt32Array()
var entities := {}
var events := {}
var narrative := {}
var stats: Array = []
var regional: Dictionary = {}

func _init(w: WorldData = null) -> void:
	world = w

static func _array(value: Variant) -> Array:
	return value if value is Array else []

static func _object(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func consume(data: Dictionary, delta: bool) -> HistoryFrame:
	if world == null:
		return null
	var schema: String = data.get("schema", "")
	if not schema in (["asabiya/annual-delta-v1","asabiya/map-delta-v1"] if delta else ["asabiya/state-v1","asabiya/map-state-v1"]):
		return null
	var expected: String = world.header.get("world", {}).get("digest", "")
	var previous_entities: Dictionary = entities.duplicate()
	if not delta:
		world_digest = str(data.get("worldSHA256", ""))
		if world_digest != expected:
			return null
		var n := world.cell_count()
		owner.resize(n); owner.fill(0)
		people.resize(n); people.fill(-1)
		religion.resize(n); religion.fill(-1)
		population.resize(n); carrying.resize(n)
		technology.resize(n); fortification.resize(n); era.resize(n)
		entities = {}; events.clear(); narrative.clear()
	elif int(data.get("fromYear", -999999)) != year:
		return null
	var provinces: Array = _array(data.get("provinces"))
	if not delta and provinces.size() != world.cell_count():
		return null
	for p: Dictionary in provinces:
		var i := int(p.get("id", -1))
		if i < 0 or i >= owner.size():
			return null
		owner[i] = int(p.get("ownerPolityId", 0))
		people[i] = int(p.get("peopleId", -1))
		religion[i] = int(p.get("religionId", -1))
		population[i] = float(p.get("population", 0.0))
		carrying[i] = float(p.get("carryingCapacity", 0.0))
		fortification[i] = float(p.get("fortification", 0.0))
		era[i] = int(p.get("era", 0))
		technology[i] = float(era[i]) / 7.0 # display scale of the Go-provided era
	var upserts: Dictionary = _object(data.get("entityUpserts" if delta else "entities"))
	for kind: String in upserts:
		if not entities.has(kind):
			entities[kind] = {}
		for record: Dictionary in _array(upserts[kind]):
			var id := int(record["id"])
			var fields: Dictionary = _object(record.get("fields"))
			var prior: Dictionary = _object(previous_entities.get(kind, {}).get(id))
			entities[kind][id] = prior if prior == fields else fields
	for e: Dictionary in _array(data.get("events")):
		events[int(e["id"])] = e
	for t: Dictionary in _array(data.get("narrative")):
		narrative[int(t["eventId"])] = t
	if delta:
		var first := int(data.get("firstRetainedEventId", 0))
		for id: int in events.keys():
			if id < first:
				events.erase(id); narrative.erase(id)
	year = int(data["year"])
	digest = str(data.get("stateSHA256", ""))
	stats = _array(data.get("stats"))
	regional = _object(data.get("earth"))
	return _publish()

static func _color(value: Variant, id: int) -> Color:
	if value is Array and value.size() == 3:
		return Color8(int(value[0]), int(value[1]), int(value[2]))
	return MapLayers.id_color(id)

func _publish() -> HistoryFrame:
	var f := HistoryFrame.new()
	f.year = year; f.world_digest = world_digest; f.state_digest = digest
	f.owner = owner.duplicate(); f.people = people.duplicate(); f.religion = religion.duplicate()
	f.population = population.duplicate(); f.carrying = carrying.duplicate(); f.technology = technology.duplicate()
	f.stats = stats; f.regional = regional
	for kind: String in entities:
		f.entity_records[kind] = entities[kind].duplicate()
	var rulers: Dictionary = entities.get("ruler", {})
	for id: int in entities.get("polity", {}):
		var p: Dictionary = entities["polity"][id]
		if not p.get("alive", false):
			continue
		var state: Dictionary = p.duplicate()
		state["rgb"] = _color(p.get("rgb"), id)
		state["capital"] = p.get("capitalId")
		state["dynasty"] = p.get("dynastyLabel")
		state["founded"] = p.get("born")
		state["ruler"] = rulers.get(int(p.get("rulerId", -1)), {}).get("name")
		var metrics: Dictionary = p.get("metrics", {})
		if metrics.has("cohesion"): state["cohesion"] = metrics["cohesion"]
		var census: Array = _array(p.get("censusHistory"))
		var observations := []
		for k in range(maxi(0, census.size() - 24), census.size() - 1, 2):
			var y := int(census[k])
			var date := "%d a. C." % (1 - y) if y <= 0 else "%d d. C." % y
			observations.append("%s · %d provincias" % [date, int(census[k + 1])])
		state["history"] = observations
		f.states[id] = state
	for id: int in entities.get("people", {}):
		var p: Dictionary = entities["people"][id]
		if not p.get("alive", false): continue
		var e: Dictionary = p.duplicate()
		e["rgb"] = _color(p.get("rgb"), id)
		e["family"] = p.get("familyId")
		e["language"] = p.get("languageStyle")
		# The legacy culture is a numeric axis; do not invent a named culture.
		f.peoples[id] = e
	for id: int in entities.get("religion", {}):
		var r: Dictionary = entities["religion"][id].duplicate()
		r["rgb"] = _color(r.get("rgb"), id)
		r["founded"] = r.get("born")
		f.religions[id] = r
	for id: int in entities.get("city", {}):
		var city: Dictionary = entities["city"][id]
		var cell := int(city["cellId"])
		# cityPass preserves named sites after abandonment. Only occupied sites
		# are displayed as active settlements; the historical entity stays queryable.
		if cell < 0 or cell >= population.size() or population[cell] < 1.0: continue
		var s := {"id":id,"cell":cell,"name":city.get("name", ""),"founded":city.get("born"),
			"population":population[cell],"state":owner[cell],"era":era[cell],
			"features":{"walls":fortification[cell] > 0.0},"holy":city.get("holy", false),
			"populationScope":"province","featuresScope":"fortification proxy; house layout decorative"}
		f.settlements.append(s)
	for id: int in entities.get("war", {}):
		var war: Dictionary = entities["war"][id]
		if not war.get("active", false): continue
		var attackers: Array = _array(war.get("attackers"))
		var defenders: Array = _array(war.get("defenders"))
		var w: Dictionary = war.duplicate()
		w["id"] = id; w["a"] = int(attackers[0]) if not attackers.is_empty() else 0
		w["b"] = int(defenders[0]) if not defenders.is_empty() else 0
		w["started"] = war.get("start"); w["front"] = PackedInt32Array()
		# Exact battle fronts are absent from the Go model; none are fabricated.
		f.wars.append(w)
	for id: int in entities.get("route", {}):
		var r: Dictionary = entities["route"][id]
		if r.get("active", false):
			f.routes.append({"id":id,"cells":PackedInt32Array(_array(r.get("path"))),"from":r.get("fromCellId"),"to":r.get("toCellId")})
	var ids: Array = events.keys(); ids.sort()
	for id: int in ids.slice(maxi(0, ids.size() - MAX_VISIBLE_EVENTS)):
		var e: Dictionary = events[id].duplicate()
		e["text"] = narrative.get(id, {}).get("text", "")
		e["why"] = narrative.get(id, {}).get("why", "")
		e["refs"] = _array(e.get("entities"))
		f.events.append(e)
	for value: float in population:
		f.world_population += value
	return f
