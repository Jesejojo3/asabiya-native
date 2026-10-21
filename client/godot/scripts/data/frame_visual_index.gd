class_name FrameVisualIndex
extends RefCounted
## Worker-owned, derived presentation data. Never changes a HistoryFrame input.
## Published dictionaries are replaced, not mutated, on later publications.

var _world_id := 0
var _inputs := {}
var _shapes := {}
var _sin := PackedFloat64Array()
var _cos := PackedFloat64Array()


func build(world: WorldData, frame: HistoryFrame) -> Dictionary:
	if _world_id != world.get_instance_id():
		_world_id = world.get_instance_id()
		_inputs = {}
		_shapes = {}
		_sin.resize(world.width)
		_cos.resize(world.width)
		for x in world.width:
			var angle := world.cell_center(x).x / world.fine_width * TAU
			_sin[x] = sin(angle)
			_cos[x] = cos(angle)
	var rebuilt := 0
	var reused := 0
	var shape_layers := {}
	for layer: String in ["states", "peoples", "religions"]:
		var ids: PackedInt32Array = frame.owner if layer == "states" else (frame.people if layer == "peoples" else frame.religion)
		if _inputs.has(layer) and _inputs[layer] == ids:
			reused += 1
		else:
			_shapes[layer] = _group_shapes(world, ids)
			_inputs[layer] = ids # Immutable, detached publication arrays.
			rebuilt += 1
		shape_layers[layer] = _shapes[layer]
	var state_totals := {}
	var people_totals := {}
	var has_population := frame.has_layer("population")
	for cell in world.land_cells:
		var owner := frame.owner[cell] if not frame.owner.is_empty() else -1
		var people := frame.people[cell] if not frame.people.is_empty() else -1
		var population := float(frame.population[cell]) if has_population else 0.0
		if owner >= 0:
			if not state_totals.has(owner): state_totals[owner] = [0, 0.0, 0.0]
			var total: Array = state_totals[owner]
			total[0] += 1
			total[1] += world.area[cell]
			total[2] += population
		if people >= 0:
			if not people_totals.has(people): people_totals[people] = [0, 0.0]
			var total: Array = people_totals[people]
			total[0] += 1
			total[1] += population
	var by_id := {}
	var by_cell := {}
	for settlement: Dictionary in frame.settlements:
		by_id[int(settlement["id"])] = settlement
		var cell := int(settlement["cell"])
		if not by_cell.has(cell): by_cell[cell] = []
		(by_cell[cell] as Array).append(settlement)
	return {"shapes":shape_layers,"stateTotals":state_totals,"peopleTotals":people_totals,
		"settlementsById":by_id,"settlementsByCell":by_cell,
		"shapesRebuilt":rebuilt,"shapesReused":reused,"totalsCellsScanned":world.land_cells.size()}


func _group_shapes(world: WorldData, ids: PackedInt32Array) -> Dictionary:
	if ids.is_empty(): return {}
	var sums := {}
	for cell in world.land_cells:
		var group := ids[cell]
		if group < 0: continue
		if not sums.has(group): sums[group] = [0.0, 0.0, 0.0, 0, INF, -INF]
		var value: Array = sums[group]
		var center := world.cell_center(cell)
		value[0] += _sin[cell % world.width]
		value[1] += _cos[cell % world.width]
		value[2] += center.y
		value[3] += 1
		value[4] = minf(value[4], center.y)
		value[5] = maxf(value[5], center.y)
	var result := {}
	for group: int in sums:
		var value: Array = sums[group]
		var angle := atan2(value[0], value[1])
		result[group] = {"x":fposmod(angle / TAU * world.fine_width, world.fine_width),
			"z":value[2] / value[3],"n":value[3],
			"spread":sqrt(value[0] * value[0] + value[1] * value[1]) / value[3],"dz":value[5] - value[4]}
	return result
