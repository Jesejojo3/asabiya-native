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


func _fixture_frame(n: int) -> Dictionary:
	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	owner[world.land_cells[0]] = 7
	return {"year": -2500, "cells": {"owner": Marshalls.raw_to_base64(owner.to_byte_array()), "people": "AAAA"},
		"states": [{"id": 7, "name": "Prueba", "rgb": [10, 20, 30]}], "settlements": [{"id": 1, "cell": world.land_cells[0], "tier": 2}]}


func test_frame_decoding() -> void:
	var f := BridgeSource.parse_frame(_fixture_frame(world.cell_count()), world.cell_count())
	check(f != null and f.year == -2500, "frame decodes")
	check(f.owner.size() == world.cell_count() and f.owner[world.land_cells[0]] == 7, "owner layer decoded")
	check(f.people.is_empty(), "wrong-size layer dropped")
	check((f.states[7]["rgb"] as Color).is_equal_approx(Color8(10, 20, 30)), "state colour")
	var r := MapLayers.build("states", world, f)
	check((r["colors"] as PackedByteArray)[world.land_cells[0] * 4 + 3] > 0, "state layer paints engine cells")
	check(BridgeSource.parse_frame({}, 10) == null, "frame without year rejected")


func test_settlement_tiers() -> void:
	check(SettlementLayer.tier_of({"tier": 9}) == 4, "tier clamps")
	check(SettlementLayer.tier_of({"population": 500}) == 0, "hamlet by population")
	check(SettlementLayer.tier_of({"population": 30000}) == 3, "city by population")


func start_bridge_test(snapshot: String) -> void:
	var py := "python3"
	var out := []
	if OS.execute("python3", ["--version"], out) != 0:
		print("SKIP bridge plumbing (python3 not available)")
		finish()
		return
	bridge = BridgeSource.new(world, py)
	bridge.prefix_args = PackedStringArray([ProjectSettings.globalize_path("res://tests/mock_bridge.py"), "--snapshot", snapshot])
	check(bridge.start(), "bridge process starts")
	_bridge_deadline = Time.get_ticks_msec() + 15000.0
	_bridge_phase = 1


func _process(_delta: float) -> bool:
	if _bridge_phase == 0:
		return false
	bridge.poll()
	if _bridge_phase == 1 and not bridge.years().is_empty():
		check(bridge.connected, "bridge handshake")
		check(bridge.has_system("states"), "bridge systems")
		var f := bridge.frame(bridge.years()[0])
		check(f != null and not f.owner.is_empty() and f.states.size() == 3, "bridge frame content")
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
		bridge.close()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
