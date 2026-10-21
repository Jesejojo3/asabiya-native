class_name HistoryFrame
extends RefCounted
## Historical state at one year, as delivered by a HistorySource.
##
## Per-cell arrays are indexed by CellID and use -1 / 0 for "none". Entity
## dictionaries are keyed by integer ids. All of it is produced by the Go
## engine; the client never fills these with invented values.

var year := 0
# Optional worker-built, immutable presentation sidecar; never part of SHA/replay.
var visual_index: Dictionary = {}

var world_digest := ""
var state_digest := ""
var digest_mode := "" # deferred-v1 means no fingerprint exists in this publication.
var entity_records: Dictionary = {}
var stats: Array = []
var regional: Dictionary = {}

var owner := PackedInt32Array()       # state id per cell (0 none; people/religion use -1)
var people := PackedInt32Array()      # people id per cell (-1 none)
var religion := PackedInt32Array()    # religion id per cell (-1 none)
var population := PackedFloat32Array()
var technology := PackedFloat32Array() # 0..1 progress, or era index / (eras-1)
var wealth := PackedFloat32Array()     # 0..1 economic activity
var carrying := PackedFloat32Array()   # carrying capacity (people)

var states := {}      # id -> {name, rgb: Color, capital, ruler, dynasty, cohesion, founded, kind, history: Array[String]}
var peoples := {}     # id -> {name, rgb, family, language, culture, homeland}
var religions := {}   # id -> {name, rgb, founded}
var settlements := [] # [{id, cell, name, tier, population, founded, state, features: {...}}]
var events := []      # [{year, kind, text, cell, refs}]
var wars := []        # [{id, a, b, started, front: PackedInt32Array}]
var routes := []      # [{id, cells: PackedInt32Array, volume}]

var world_population := 0.0


func has_layer(name: String) -> bool:
	match name:
		"owner": return not owner.is_empty()
		"people": return not people.is_empty()
		"religion": return not religion.is_empty()
		"population": return not population.is_empty()
		"technology": return not technology.is_empty()
		"wealth": return not wealth.is_empty()
		"carrying": return not carrying.is_empty()
	return false


func state_cells() -> Dictionary:
	var out := {}
	for i in owner.size():
		var s := owner[i]
		if s > 0:
			out[s] = int(out.get(s, 0)) + 1
	return out


func state_count() -> int:
	var count := 0
	for record: Dictionary in states.values():
		if record.get("kind", "state") == "state": count += 1
	return count


func settlement_by_id(id: int) -> Dictionary:
	if visual_index.has("settlementsById"): return visual_index["settlementsById"].get(id, {})
	for s in settlements:
		if int(s["id"]) == id:
			return s
	return {}


func settlements_in_cell(cell: int) -> Array:
	if visual_index.has("settlementsByCell"): return visual_index["settlementsByCell"].get(cell, [])
	var found := []
	for settlement: Dictionary in settlements:
		if int(settlement["cell"]) == cell: found.append(settlement)
	return found


func state_totals(world: WorldData, id: int) -> Array:
	if visual_index.has("stateTotals"): return visual_index["stateTotals"].get(id, [0, 0.0, 0.0])
	var result := [0, 0.0, 0.0]
	for cell in world.land_cells:
		if owner[cell] == id:
			result[0] += 1
			result[1] += world.area[cell]
			if has_layer("population"): result[2] += population[cell]
	return result


func people_totals(world: WorldData, id: int) -> Array:
	if visual_index.has("peopleTotals"): return visual_index["peopleTotals"].get(id, [0, 0.0])
	var result := [0, 0.0]
	for cell in world.land_cells:
		if people[cell] == id:
			result[0] += 1
			if has_layer("population"): result[1] += population[cell]
	return result
