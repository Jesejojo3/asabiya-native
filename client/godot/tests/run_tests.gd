extends SceneTree
## Headless test suite for the 3D client.
##   godot --headless --path client/godot --script res://tests/run_tests.gd -- --snapshot WORLD.asw
## Exit code 0 when every check passes.

var failures := 0
var checks := 0
var world: WorldData
var mm: MapMath
var bridge: BridgeSource
var _bridge_deadline := 0.0
var _bridge_phase := 0


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


func _initialize() -> void:
	var args := {}
	var raw := OS.get_cmdline_user_args()
	for i in raw.size():
		if raw[i] == "--snapshot" and i + 1 < raw.size():
			args["snapshot"] = raw[i + 1]
	if not args.has("snapshot"):
		printerr("usage: -- --snapshot WORLD.asw")
		quit(2)
		return
	test_snapshot(args["snapshot"])
	test_corrupt(args["snapshot"])
	test_math()
	test_cells()
	test_raycast()
	test_layers()
	test_culture_vector_and_coalitions()
	test_precision_wheel_and_live_pacing()
	test_rivers()
	test_frame_decoding()
	test_settlement_tiers()
	start_bridge_test(args["snapshot"])


func test_snapshot(path: String) -> void:
	world = WorldData.load_file(path)
	check(world != null, "snapshot loads")
	if world == null:
		quit(1)
		return
	check(world.width * world.height == world.land.size(), "cell layer sizes")
	check(world.has_fine and world.fine_width == world.width * world.detail, "fine layers present")
	check(world.land_cells.size() == int(world.header["world"]["landCells"]), "land count matches header")
	check(world.session_kind == "real", "engine session")
	mm = MapMath.new()
	mm.setup(world)


func test_corrupt(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	bytes[bytes.size() - 5] ^= 0x55
	var w := WorldData.new()
	check(w._parse(bytes) != "", "corrupted snapshot rejected")
	var w2 := WorldData.new()
	check(w2._parse(PackedByteArray([1, 2, 3])) != "", "garbage rejected")


func test_math() -> void:
	# hash identical to the GLSL constants (spot values computed by hand)
	check(MapMath.hash2u(0, 0) == 0, "hash(0,0)")
	check(MapMath.hash2u(1, 0) >= 0 and MapMath.hash2u(1, 0) <= 0xFFFFFFFF, "hash range")
	# noise wraps at the longitude seam
	var periods := int(mm.map_w * 0.45)
	for k in 20:
		var z := 37.3 + k * 31.7
		var x := 3.1 + k * 7.9
		check(absf(mm.vnoise(x, z, periods, 0) - mm.vnoise(x + mm.map_w, z, periods, 0)) < 1e-6, "noise periodic")
	check(absf(mm.height_at(0.2, 400.0) - mm.height_at(0.2 + mm.map_w, 400.0)) < 1e-5, "height periodic")
	# coastline preserved: smoothing never flips land/sea of the bilinear field
	var flips := 0
	for k in 4000:
		var x2 := fposmod(k * 12.37, mm.map_w)
		var z2 := fposmod(k * 7.91, mm.map_h)
		var b := mm.elev_bilinear(x2, z2)
		var s := mm.elev_smooth(x2, z2)
		if (b > 0.0) != (s > 0.0):
			flips += 1
	check(flips == 0, "smooth elevation keeps the coastline (%d flips)" % flips)
	# visual heights are monotonic in metres
	check(mm.metres_to_units(1000.0) > mm.metres_to_units(10.0), "land scale")
	check(mm.metres_to_units(-10.0) > mm.metres_to_units(-3000.0), "ocean scale")


func test_cells() -> void:
	# a land cell centre always picks its own province (warp < half a cell)
	var wrong := 0
	for i in world.land_cells:
		var c := world.cell_center(i)
		if mm.cell_at(world, c.x, c.y) != i:
			wrong += 1
	check(wrong == 0, "cell centres resolve to their CellID (%d wrong)" % wrong)
	# seam: x and x+W give the same cell
	for k in 50:
		var z := 5.0 + k * 15.0
		check(mm.cell_at(world, 0.3, z) == mm.cell_at(world, 0.3 + mm.map_w, z), "cell lookup wraps")
	check(world.cell_id(-1, 10) == world.cell_id(world.width - 1, 10), "cell_id wraps")
	check(world.cell_id(0, -1) == -1, "no cell beyond the pole")


func test_raycast() -> void:
	for k in 30:
		var x := fposmod(k * 53.1, mm.map_w)
		var z := 40.0 + fposmod(k * 23.7, mm.map_h - 80.0)
		var hit = mm.raycast(Vector3(x, 500.0, z), Vector3(0, -1, 0))
		check(hit != null, "vertical ray hits")
		if hit != null:
			var expect := maxf(mm.height_at(x, z), 0.0)
			check(absf((hit as Vector3).y - expect) < 0.02, "ray hit on surface")
	var oblique = mm.raycast(Vector3(800, 300, 900), Vector3(0, -1, -1))
	check(oblique != null, "oblique ray hits")
	check(mm.raycast(Vector3(800, 300, 400), Vector3(0, 1, 0)) == null, "upward ray misses")


func test_layers() -> void:
	for d in MapLayers.DEFS:
		var r := MapLayers.build(d["id"], world, null)
		check((r["colors"] as PackedByteArray).size() == world.cell_count() * 4, "layer %s colours" % d["id"])
		check((r["keys"] as PackedFloat32Array).size() == world.cell_count(), "layer %s keys" % d["id"])
		if d["requires"] != "":
			check(not MapLayers.available(d["id"], GeographySource.new(world), null), "history layer %s disabled without engine data" % d["id"])
			var any := false
			for b in (r["colors"] as PackedByteArray):
				if b != 0:
					any = true
					break
			check(not any, "history layer %s empty without engine data" % d["id"])


func test_rivers() -> void:
	var expected := 0
	for i in world.land_cells:
		if world.river[i] >= RiverBaker.RIVER_MIN and world.down[i] >= 0:
			expected += 1
	var paths := RiverBaker.build_paths(world)
	check(paths.size() == expected, "one river path per engine river cell (%d vs %d)" % [paths.size(), expected])


func test_precision_wheel_and_live_pacing() -> void:
	var camera := StrategyCamera.new()
	check(camera.wheel_ratio(0.2) > 1.0 and camera.wheel_ratio(0.2) < camera.wheel_ratio(1.0), "precision wheel keeps direction and scales its step")
	check(is_equal_approx(camera.wheel_ratio(0.0), camera.zoom_step), "wheel without a precision factor uses one normal step")
	check(is_equal_approx(camera.wheel_ratio(100.0), pow(camera.zoom_step, 3.0)), "a large wheel event is bounded")
	camera.free()
	# No process is launched here: inspect the producer's queue and scheduling
	# independently of network latency. The normal bridge scenario remains below.
	var live := BridgeSource.new(world, "not-launched")
	live.connected = true
	live.start_live(10)
	live.poll()
	check(live.busy and live._outgoing.size() == 1, "continuous play issues one year")
	check(live._outgoing[0]["op"] == "advance" and live._outgoing[0]["payload"] == {"view":"map"}, "continuous play publishes every complete year")
	live._live_due_us = 0
	live.poll()
	check(live._outgoing.size() == 1, "a slow calculation never queues a catch-up burst")
	live.busy = false
	live.poll()
	check(live._outgoing.size() == 1, "an unrelated publication cannot release the pending live year")
	live._outgoing.clear()
	live._live_advance_pending = false
	live.busy = false
	live.set_live_rate(1)
	live.poll()
	check(live._outgoing.is_empty(), "the next year waits for its wall-clock deadline")
	live.stop_live()
	live._live_due_us = 0
	live.poll()
	check(not live.is_live() and live._outgoing.is_empty(), "stopping continuous play stops scheduling")
	live.close()


func test_culture_vector_and_coalitions() -> void:
	var color: Variant = MapLayers.culture_color([0.1, 0.2, 0.3, 0.4, 0.5, 0.6])
	check(color is Color and (color as Color).is_equal_approx(Color(0.315, 0.38, 0.445)), "culture RGB uses the actual vector components")
	check(MapLayers.culture_color(0.5) == null, "culture is not a scalar")
	check(MapLayers.culture_color([0.1, 0.2, null, 0.4, 0.5, 0.6]) == null, "missing culture component stays unavailable")
	check(MapLayers.culture_color([0.1, 0.2, 0.3]) == null, "incomplete culture vector rejected")
	check(MapLayers.culture_color([0.1, 0.2, 0.3, 0.4, 0.5, 1.5]) == null, "invalid culture component rejected")
	var frame := HistoryFrame.new()
	frame.owner.resize(world.cell_count())
	frame.owner.fill(0)
	frame.people.resize(world.cell_count())
	frame.people.fill(-1)
	var cell := int(world.land_cells[0])
	frame.people[cell] = 7
	frame.peoples[7] = {"culture":[0.1, 0.2, 0.3, 0.4, 0.5, 0.6]}
	var cultures := MapLayers.build("cultures", world, frame)
	check((cultures["colors"] as PackedByteArray)[cell * 4 + 3] > 0, "culture vector paints real people cells")
	check((cultures["keys"] as PackedFloat32Array)[cell] == 7, "culture borders keep people IDs")
	frame.wars = [{"a":11,"b":21,"attackers":[11,12],"defenders":[21,22]}]
	frame.owner[cell] = 12
	var wars := MapLayers.build("wars", world, frame)
	check((wars["colors"] as PackedByteArray)[cell * 4 + 3] > 0, "coalition member beyond leader is painted at war")
	var participants := MapLayers.war_participants(frame.wars)
	check(participants.size() == 4 and participants.has(12) and participants.has(22), "all war participants are preserved")
	check(not MapLayers.war_participants([{"a":0,"b":0}]).has(0), "unowned land never becomes a war participant")
	check(MapLayers.war_participants([{"a":11,"b":21}]).size() == 2, "legacy a/b presentation frames remain supported")


func _fixture_frame(n: int) -> Dictionary:
	var provinces := []
	for i in n:
		provinces.append({"id":i,"ownerPolityId":7 if i == world.land_cells[0] else 0,"peopleId":-1,"religionId":-1,"population":0.0,"carryingCapacity":0.0,"era":0,"fortification":0.0})
	return {"schema":"asabiya/map-state-v1","year":-2500,"worldSHA256":world.header["world"]["digest"],"stateSHA256":"fixture",
		"provinces":provinces,"entities":{"polity":[{"id":7,"fields":{"name":"Prueba","alive":true,"rgb":[10,20,30]}}]}}


func test_frame_decoding() -> void:
	var decoder := NativeFrameDecoder.new(world)
	var f := decoder.consume(_fixture_frame(world.cell_count()), false)
	check(f != null and f.year == -2500, "native frame decodes")
	check(f.owner.size() == world.cell_count() and f.owner[world.land_cells[0]] == 7, "owner IDs preserved")
	check(f.owner[world.land_cells[1]] == 0, "polity zero means unowned")
	check((f.states[7]["rgb"] as Color).is_equal_approx(Color8(10, 20, 30)), "state colour")
	var result := MapLayers.build("states", world, f)
	check((result["colors"] as PackedByteArray)[world.land_cells[0] * 4 + 3] > 0, "state layer paints engine cells")
	check(decoder.consume({}, false) == null, "unknown schema rejected")
	var changed := {"schema":"asabiya/map-delta-v1","year":-2499,"fromYear":-2500,"provinces":[{"id":int(world.land_cells[0]),"ownerPolityId":0}]}
	var later := decoder.consume(changed, true)
	check(later != null and later.owner[world.land_cells[0]] == 0, "delta replaces a province")
	check(f.owner[world.land_cells[0]] == 7, "published old frame is immutable")
	check(decoder.consume(changed, true) == null, "out-of-order delta rejected")


func test_settlement_tiers() -> void:
	check(SettlementLayer.tier_of({"tier": 9}) == 4, "tier clamps")
	check(SettlementLayer.tier_of({"population": 500}) == 0, "hamlet by population")
	check(SettlementLayer.tier_of({"population": 30000}) == 3, "city by population")


func start_bridge_test(_snapshot: String) -> void:
	var server := BridgeSource.find_executable()
	var raw := OS.get_cmdline_user_args()
	for k in raw.size():
		if raw[k] == "--server" and k + 1 < raw.size(): server = raw[k + 1]
	if server == "":
		print("SKIP real TCP integration: pass --server PATH (no old stdio mock is used)")
		finish()
		return
	bridge = BridgeSource.new(world, server)
	check(bridge.start(), "Go server process starts")
	_bridge_deadline = Time.get_ticks_msec() + 60000.0
	_bridge_phase = 1


func _process(_delta: float) -> bool:
	if _bridge_phase == 0:
		return false
	bridge.poll()
	if _bridge_phase == 1 and not bridge.years().is_empty():
		check(bridge.connected, "local TCP handshake")
		check(bridge.has_system("states"), "bridge systems")
		var f := bridge.frame(bridge.years()[0])
		check(f != null and not f.owner.is_empty() and not f.peoples.is_empty(), "native frame content")
		check(bridge.can_advance(), "bridge can advance")
		bridge.advance(25)
		_bridge_phase = 2
	elif _bridge_phase == 2 and bridge.years().size() >= 2:
		check(bridge.years()[1] == bridge.years()[0] + 25, "advance produced a later frame")
		_bridge_phase = 0
		finish()
		return true
	if Time.get_ticks_msec() > _bridge_deadline:
		check(false, "bridge timed out in phase %d (%s)" % [_bridge_phase, bridge.last_error])
		_bridge_phase = 0
		finish()
		return true
	return false


func finish() -> void:
	if bridge != null:
		await bridge.shutdown()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
