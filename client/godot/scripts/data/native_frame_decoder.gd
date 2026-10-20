class_name NativeFrameDecoder
extends RefCounted
## Worker-owned publication adapter for asabiya/state-v1 / annual-delta-v1.
## No simulation rules live here. Packed arrays are explicitly duplicated on
## publication because GDScript array objects are shared by reference.

const MAX_VISIBLE_EVENTS := 1000

var _trace := AnnualTrace.new("decoder")

var world: WorldData
var year := 0
var digest := ""
var digest_mode := ""
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
	var started := _trace.begin()
	if world == null:
		return null
	var total_population: Variant = data.get("worldPopulation")
	if total_population != null and (not (total_population is int or total_population is float) or not is_finite(float(total_population))): return null
	var schema: String = data.get("schema", "")
	var mode: String = str(data.get("digestMode", ""))
	var sha: Variant = data.get("stateSHA256")
	# Only a complete-year delta may defer its expensive cryptographic SHA.
	# An empty digest is never presented as an actual SHA-256 fingerprint.
	if mode != "" and (not delta or mode != "deferred-v1" or sha != ""):
		return null
	if mode == "" and not _valid_sha256(sha): return null
	if delta and int(data.get("year", -999999)) != year + 1: return null
	var field_patch := schema == "asabiya/map-fields-delta-v1"
	if field_patch and not delta: return null
	if field_patch and not data.get("provinces") is Dictionary: return null
	if field_patch: schema = "asabiya/map-delta-v1"
	var columnar := schema in ["asabiya/map-columns-state-v1", "asabiya/map-columns-delta-v1"]
	if columnar: schema = "asabiya/map-delta-v1" if schema.ends_with("delta-v1") else "asabiya/map-state-v1"
	if not schema in (["asabiya/annual-delta-v1","asabiya/map-delta-v1"] if delta else ["asabiya/state-v1","asabiya/map-state-v1"]):
		return null
	var expected: String = world.header.get("world", {}).get("digest", "")
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
	var provinces: Array = [] if columnar or field_patch else _array(data.get("provinces"))
	if field_patch and not _apply_fields(_object(data.get("provinces"))): return null
	if columnar and not _apply_columns(_object(data.get("provinces")), delta): return null
	if not columnar and not delta and provinces.size() != world.cell_count():
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
			# Upserts are authoritative. Variant equality also equates signed zeros,
			# so it cannot safely decide that a returned record is unchanged.
			entities[kind][id] = fields
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
	digest = sha
	digest_mode = mode
	stats = _array(data.get("stats"))
	regional = _object(data.get("earth"))
	_trace.record("consume-apply", started, {"year":year,"rows":provinces.size()})
	return _publish(total_population)

static func _color(value: Variant, id: int) -> Color:
	if value is Array and value.size() == 3:
		return Color8(int(value[0]), int(value[1]), int(value[2]))
	return MapLayers.id_color(id)

func _publish(total_population: Variant = null) -> HistoryFrame:
	var started := _trace.begin()
	var f := HistoryFrame.new()
	f.year = year; f.world_digest = world_digest; f.state_digest = digest; f.digest_mode = digest_mode
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
	if total_population != null:
		f.world_population = float(total_population)
	else:
		for value: float in population: f.world_population += value
	_trace.record("publish-frame", started, {"year":year,"cells":population.size(),"events":f.events.size()})
	return f

func _apply_columns(rows: Dictionary, delta: bool) -> bool:
	var ids: Array = _array(rows.get("id"))
	var n := ids.size()
	for key in ["ownerPolityId","peopleId","religionId","population","carryingCapacity","fortification","era"]:
		if not rows.get(key) is Array or rows[key].size() != n: return false
	if not delta and n != world.cell_count(): return false
	for k in n:
		var i := int(ids[k])
		if i < 0 or i >= world.cell_count() or (not delta and i != k): return false
		if k > 0 and i <= int(ids[k-1]): return false
	if not delta:
		owner = PackedInt32Array(rows["ownerPolityId"])
		people = PackedInt32Array(rows["peopleId"])
		religion = PackedInt32Array(rows["religionId"])
		population = PackedFloat32Array(rows["population"])
		carrying = PackedFloat32Array(rows["carryingCapacity"])
		fortification = PackedFloat32Array(rows["fortification"])
		era = PackedInt32Array(rows["era"])
		for i in n: technology[i] = float(era[i]) / 7.0
		return true
	var owners: Array = rows["ownerPolityId"]
	var peoples: Array = rows["peopleId"]
	var faiths: Array = rows["religionId"]
	var populations: Array = rows["population"]
	var capacities: Array = rows["carryingCapacity"]
	var forts: Array = rows["fortification"]
	var eras: Array = rows["era"]
	for k in n:
		var i := int(ids[k])
		owner[i] = int(owners[k]); people[i] = int(peoples[k]); religion[i] = int(faiths[k])
		population[i] = float(populations[k]); carrying[i] = float(capacities[k]); fortification[i] = float(forts[k])
		era[i] = int(eras[k]); technology[i] = float(era[i]) / 7.0
	return true

static func _valid_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for i in value.length():
		var c: int = value.unicode_at(i)
		if not (c >= 48 and c <= 57) and not (c >= 97 and c <= 102): return false
	return true

func _apply_fields(fields: Dictionary) -> bool:
	# Stage only changed arrays. duplicate() creates a separate PackedArray
	# object with COW storage; writes detach from every retained frame. Validation
	# and assignment share one pass, and failure never commits a partial patch.
	var staged: Dictionary = {}
	for key: String in fields:
		var destination: Variant
		var integer := true
		match key:
			"ownerPolityId": destination = owner.duplicate()
			"peopleId": destination = people.duplicate()
			"religionId": destination = religion.duplicate()
			"era": destination = era.duplicate()
			"population": destination = population.duplicate(); integer = false
			"carryingCapacity": destination = carrying.duplicate(); integer = false
			"fortification": destination = fortification.duplicate(); integer = false
			_: return false
		var patch: Variant = fields[key]
		if not patch is Dictionary or not patch.get("id") is Array or not patch.get("values") is Array: return false
		var ids: Array = patch["id"]
		var values: Array = patch["values"]
		if ids.size() != values.size(): return false
		var previous := -1
		for k in ids.size():
			var id: Variant = ids[k]
			var value: Variant = values[k]
			if not (id is int or id is float) or int(id) != id: return false
			var i := int(id)
			if i <= previous or i >= owner.size(): return false
			if not (value is int or value is float) or not is_finite(float(value)): return false
			if integer and (int(value) != value or value < -2147483648 or value > 2147483647): return false
			destination[i] = value
			if not integer and not is_finite(destination[i]): return false
			previous = i
		staged[key] = destination
	for key: String in staged:
		match key:
			"ownerPolityId": owner = staged[key]
			"peopleId": people = staged[key]
			"religionId": religion = staged[key]
			"population": population = staged[key]
			"carryingCapacity": carrying = staged[key]
			"fortification": fortification = staged[key]
			"era":
				era = staged[key]
				for id: Variant in fields[key]["id"]: technology[int(id)] = float(era[int(id)]) / 7.0
	return true
