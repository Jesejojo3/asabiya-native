extends SceneTree
## Acceptance contracts for the USER to run. Not executed by the implementer.
## No Go process, historical simulation, FPS measurement or screenshots.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _fixture() -> WorldData:
	var world := WorldData.new()
	world.width = 24
	world.height = 16
	world.detail = 4
	world.fine_width = 96
	world.fine_height = 64
	world.land.resize(world.cell_count())
	world.land.fill(1)
	world.area.resize(world.cell_count())
	world.area.fill(100.0)
	world.land_cells = PackedInt32Array(range(world.cell_count()))
	world.elevation_fine.resize(world.fine_width * world.fine_height)
	for z in world.fine_height:
		for x in world.fine_width:
			world.elevation_fine[z * world.fine_width + x] = sin(x * 0.31) * cos(z * 0.27) * 4200.0
	return world

func _frame(world: WorldData) -> HistoryFrame:
	var frame := HistoryFrame.new()
	frame.year = -100
	frame.owner.resize(world.cell_count())
	frame.people.resize(world.cell_count())
	frame.religion.resize(world.cell_count())
	frame.population.resize(world.cell_count())
	for cell in world.cell_count():
		frame.owner[cell] = 1 if cell % 2 == 0 else 2
		frame.people[cell] = cell % 3
		frame.religion[cell] = -1
		frame.population[cell] = cell * 0.125 + 1.0
	frame.states = {1:{"name":"Alpha"},2:{"name":"Beta"}}
	return frame

func _run() -> void:
	var world := _fixture()
	var math := MapMath.new()
	math.setup(world)
	for scale_value: float in [1.0 / 650.0, 1.0 / 420.0, 1.0 / 300.0]:
		math.land_scale = scale_value
		for point: Vector2 in [Vector2(0,0),Vector2(95.99,63.99),Vector2(-0.1,32),Vector2(7.5,7.5),Vector2(8.5,8.5),Vector2(48,32)]:
			for altitude: float in [0.8, 8.0, 60.0, 200.0]:
				for direction: Vector3 in [Vector3(0,-1,0),Vector3(0.7,-0.5,0.2),Vector3(-0.7,-0.5,-0.2)]:
					var origin := Vector3(point.x, altitude, point.y)
					var expected: Variant = _original_raycast(math, origin, direction, 6000.0)
					var actual: Variant = math.raycast(origin, direction, 6000.0)
					check(expected == actual, "raycast exact result / null matches original")
		# Exercise every 8x8 block, seam and pole including interpolation halos.
		for z in range(-1, world.fine_height + 1, 3):
			for x in range(-1, world.fine_width + 1, 3):
				var px := x + 0.37
				var pz := clampf(z + 0.83, 0.0, math.map_h)
				check(maxf(math.height_at(px,pz),0.0) <= math._pick_height_upper(px,pz), "conservative bound covers the full visual surface")
	var builder := FrameVisualIndex.new()
	var first := _frame(world)
	first.visual_index = builder.build(world, first)
	var expected_population := 0.0
	for cell in world.land_cells:
		if first.people[cell] == 1: expected_population += first.population[cell]
	check(first.people_totals(world,1)[1] == expected_population, "people total keeps original summation order")
	var original_shapes: Dictionary = first.visual_index["shapes"]["states"]
	var next := _frame(world)
	next.year = first.year # A same-year authoritative snapshot must invalidate on content.
	next.owner[0] = 2
	next.visual_index = builder.build(world,next)
	check(first.owner[0] == 1 and original_shapes[1]["n"] == 192, "next publication does not mutate the retained index/frame")
	check(next.visual_index["shapes"]["states"][1]["n"] == 191, "same-year membership changes invalidate the shape")
	check(next.visual_index["shapesReused"] == 2, "unchanged people/religion shape layers are reused")
	var overlay := HistoryOverlay.new()
	root.add_child(overlay)
	overlay.setup(world,math)
	overlay.rebuild(first,"states")
	var label_id: int = overlay._label_nodes[1].get_instance_id()
	first.events = [{"id":1,"year":first.year,"cell":1,"kind":"war"}]
	overlay.rebuild(first,"states")
	var marker_id: int = overlay._marker_nodes["e:1"].get_instance_id()
	next.events = first.events.duplicate(true)
	next.events.append({"id":2,"year":next.year,"cell":2,"kind":"plague"})
	overlay.rebuild(next,"states")
	check(overlay._label_nodes[1].get_instance_id() == label_id, "membership changes update the existing territory label")
	check(overlay._marker_nodes["e:1"].get_instance_id() == marker_id, "new events preserve existing marker resources")
	overlay.free()
	print("Phase 2.2 acceptance contracts: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)

# Independent copy of the pre-2.2 marching/refinement path, with the full height
# evaluator and no conservative bound or cache. Signs and arithmetic order stay exact.
func _gap(math: MapMath, point: Vector3) -> float:
	if point.z < -2.0 or point.z > math.map_h + 2.0: return 1.0
	return point.y - maxf(math.height_at(point.x,clampf(point.z,0.0,math.map_h)),0.0)

func _original_raycast(math: MapMath, origin: Vector3, direction: Vector3, max_distance: float) -> Variant:
	if direction.length_squared() < 1e-12: return null
	direction = direction.normalized()
	var top := math.metres_to_units(9000.0) + math.relief_detail
	var bottom := math.metres_to_units(-MapMath.OCEAN_REF_DEPTH * 1.6)
	var first := 0.0
	var last := max_distance
	if absf(direction.y) > 1e-6:
		var a := (top - origin.y) / direction.y
		var b := (minf(bottom,0.0) - origin.y) / direction.y
		first = maxf(0.0,minf(a,b))
		last = minf(max_distance,maxf(a,b))
	elif origin.y > top or origin.y < bottom: return null
	if last <= first: return null
	var previous := first
	if _gap(math,origin+direction*first) <= 0.0: return math._clamp_hit(origin+direction*first)
	var step := (last-first) / 160
	var distance_value := first
	for index in 160:
		distance_value += step
		if _gap(math,origin+direction*distance_value) <= 0.0:
			var low := previous
			var high := distance_value
			for iteration in 14:
				var middle := 0.5*(low+high)
				if _gap(math,origin+direction*middle) > 0.0: low=middle
				else: high=middle
			return math._clamp_hit(origin+direction*high)
		previous=distance_value
	return null
