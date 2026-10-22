extends Node
## Phase 2.3 graphical diagnosis harness. Opt-in only: loaded by
## tests/render_diagnosis_runner.gd (editor/sources) or by main.gd when an
## exported build is started with `-- --render-diagnosis`.
## One process prepares history ONCE through the worker-chained fast-forward
## (the same one-year `advance` requests, not frame-locked), proves the causal
## state with get_replay, then measures a plan of single-variable experiments
## that are applied and reverted at runtime, with baseline captures interleaved
## to expose drift. Runs against PR #22/#24 sources and this branch unchanged.
const App := preload("res://scripts/app/main.gd")
const SCHEMA := "asabiya/render-diagnosis-v1"
const COLUMNS := ["elapsedMs", "frameMs", "processMs", "renderCpuMs", "renderGpuMs", "drawCalls", "shadowDrawCalls",
	"primitives", "shadowPrimitives", "staticBytes", "renderVideoBytes", "nodes", "year", "terrainAssignedTriangles",
	"canvasDrawCalls", "renderTextureBytes", "renderBufferBytes"]
## Experiments that only isolate a subsystem; none is an accepted optimization.
const VARIANTS := ["base", "shadows-off", "shadow-atlas-4096", "shadow-atlas-2048", "shadow-splits-2", "shadow-splits-1",
	"shadow-distance-half", "shadow-distance-double", "shadow-filter-hard", "shadow-filter-low", "shadow-blend-off",
	"shadow-terrain-caster-off", "ssao-off", "ssao-half-size-off", "msaa-off", "msaa-off-fxaa", "msaa-off-smaa", "tonemap-linear",
	"fog-off", "terrain-hidden", "water-hidden", "vegetation-hidden", "settlements-hidden", "overlay-hidden",
	"ui-hidden", "terrain-fragment-min", "terrain-normal-hw", "terrain-overlay-off", "terrain-vertex-min",
	"terrain-noise-off", "water-fragment-min", "water-priority-first", "water-priority-last", "sea-full-plane", "lod-coarse", "lod-fine", "render-scale-0.75", "render-scale-0.5",
	"res-720", "res-720-lod-matched", "shader-baseline", "baseline-render"]
## Default plans. "acceptance" never contains a diagnostic ablation.
const PLANS := {
	"acceptance": ["base"],
	"diagnosis": ["base", "shadows-off", "ssao-off", "msaa-off", "base", "terrain-hidden", "terrain-fragment-min",
		"terrain-vertex-min", "base", "shadow-atlas-4096", "shadow-atlas-2048", "shadow-splits-2", "base",
		"shadow-splits-1", "shadow-distance-half", "shadow-filter-hard", "base", "shadow-terrain-caster-off",
		"shadow-blend-off", "ssao-half-size-off", "base", "msaa-off-fxaa", "msaa-off-smaa", "base",
		"tonemap-linear", "fog-off",
		"terrain-normal-hw", "terrain-noise-off", "terrain-overlay-off", "base", "water-hidden", "water-fragment-min", "sea-full-plane",
		"vegetation-hidden", "base", "settlements-hidden", "overlay-hidden", "ui-hidden", "base", "lod-coarse",
		"lod-fine", "render-scale-0.75", "base", "render-scale-0.5", "res-720", "res-720-lod-matched", "base"],
	"mobile": ["base", "shadows-off", "msaa-off", "base", "terrain-hidden", "terrain-fragment-min", "terrain-vertex-min",
		"base", "shadow-atlas-4096", "shadow-splits-2", "shadow-filter-hard", "base", "vegetation-hidden",
		"render-scale-0.75", "res-720", "base"],
	# Each Phase 2.3 change against the candidate, then both reverted together.
	"ab-candidate": ["base", "shader-baseline", "sea-full-plane", "baseline-render", "base", "shader-baseline",
		"sea-full-plane", "baseline-render", "base", "shader-baseline", "sea-full-plane", "baseline-render", "base"],
	"smoke": ["base", "shadows-off", "terrain-fragment-min", "base"],
}

var app: Node
var args: Dictionary
var output := ""
var metadata: Dictionary = {}
var rows: Array = []
var publications: Array = []
var recording := false
var invalid_reason := ""
var last_draw_us := 0
var start_us := 0
var _phase_started := 0
var _baseline_terrain_shader: Shader
var _baseline_water_shader: Shader


var root: Window


func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")


func _run() -> void:
	args = App.parse_args(OS.get_cmdline_user_args())
	output = str(args.get("output", ""))
	if args.has("self-check"):
		# Packaging check: proves this build contains and can start the harness.
		print("RENDER_DIAGNOSIS_SELF_CHECK ", JSON.stringify({"schema":SCHEMA, "exported":not OS.has_feature("editor"),
			"renderer":RenderingServer.get_current_rendering_method(), "variants":VARIANTS.size()}))
		get_tree().quit(0)
		return
	if output.is_empty() or DisplayServer.get_name() == "headless":
		_fail("A graphical display and --output DIRECTORY are required; headless is not a GPU benchmark.")
		return
	var version := Engine.get_version_info()
	if version.get("major") != 4 or version.get("minor") != 7 or version.get("patch") != 2 or version.get("status") != "stable" or version.get("build") != "official":
		_fail("Use the pinned official Godot 4.7.2 build.")
		return
	if not DirAccess.dir_exists_absolute(output) and DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create measurement directory.")
		return
	var plan := _plan()
	for name: String in plan:
		if name not in VARIANTS and name != "active":
			_fail("Unknown experiment %s; nothing was measured." % name)
			return
	if plan.has("active") and plan.find("active") != plan.size() - 1:
		_fail("The active capture changes history and must be the last experiment.")
		return
	_phase("launch")
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = _requested_size()
	var product_sync := args.has("product-sync")
	if not product_sync:
		# Capacity measurement; --product-sync keeps the exported configuration.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	App.pending_world = {"seed":str(args.get("seed", "Asabiya")), "width":400, "height":200, "detail":4, "landFraction":0.33}
	App.pending_source = {}
	app = App.new()
	root.add_child(app)
	app._launch.launch.pressed.emit()
	if not await _wait_ready(180.0, "launch"): return
	app.settings = {"quality":1, "relief":1}
	app._apply_settings(false)
	root.content_scale_factor = 1.0
	var history_years := int(args.get("history-years", 10000))
	if history_years < 0 or history_years > 10000:
		_fail("--history-years must be between 0 and 10000.")
		return
	var prepare_started := Time.get_ticks_msec()
	if history_years > 0 and not await _prepare(history_years): return
	metadata["prepareSeconds"] = (Time.get_ticks_msec() - prepare_started) / 1000.0
	_phase("view")
	var cell := int(args.get("cell", -1))
	if cell < 0:
		# Stable row-major tie break; no RNG. Prefer a populated province.
		cell = int(app.world.land_cells[0])
		for candidate: int in app.world.land_cells:
			if app.current_frame.population[candidate] > app.current_frame.population[cell]: cell = candidate
	if cell >= app.world.cell_count() or not app.world.is_land(cell):
		_fail("The chosen cell must be land in this world.")
		return
	app.select_entity("cell", cell, false)
	app.map_view.camera.focus_on(app.world.cell_center(cell), float(args.get("distance", 18.0)), true)
	app.map_view.camera._goal_yaw = deg_to_rad(float(args.get("yaw", 0.0)))
	app.map_view.camera._goal_tilt = float(args.get("tilt", 0.0))
	app.map_view.camera._snap()
	app.map_view.camera.moved.emit()
	app.set_layer(str(args.get("layer", "terrain")))
	root.warp_mouse(Vector2(root.size) * Vector2(0.5, 0.4))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), not args.has("no-gpu-timing"))
	_phase("visual-warmup")
	await _settle(float(args.get("warmup-seconds", 20)))
	var visual_deadline := Time.get_ticks_msec() + 120000
	while app.vegetation._task >= 0 or app.vegetation.is_processing() or app.map_view.river_baker != null:
		if Time.get_ticks_msec() >= visual_deadline:
			_fail("Visual warm-up did not finish.")
			return
		await get_tree().process_frame
	if not await _wait_ready(120.0, "visual-warmup"): return
	_phase("proof-initial")
	if not await _proof("initial", 60.0): return
	var expected := str(args.get("expected-sha", ""))
	if not expected.is_empty() and str(metadata.get("initialSHA256", "")) != expected:
		_fail("Prepared history differs from the expected SHA %s (got %s). Scenarios are not comparable." % [expected, metadata.get("initialSHA256", "")])
		return
	if root.size != _requested_size() or Vector2i(root.get_texture().get_size()) != _requested_size():
		_fail("Requested %s pixels; window=%s, texture=%s. Run rejected." % [_requested_size(), root.size, root.get_texture().get_size()])
		return
	_baseline_terrain_shader = app.map_view.terrain.material.shader
	_baseline_water_shader = app.map_view.terrain.water_material.shader
	metadata.merge({"schema":SCHEMA, "revision":str(args.get("revision", "unknown")), "label":str(args.get("label", "")),
		"plan":plan, "godot":Engine.get_version_info(), "os":OS.get_name(), "cpu":OS.get_processor_name(),
		"gpu":RenderingServer.get_video_adapter_name(), "vendor":RenderingServer.get_video_adapter_vendor(),
		"api":RenderingServer.get_video_adapter_api_version(), "renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(), "executable":OS.get_executable_path().get_file(),
		"exported":not OS.has_feature("editor"), "productSync":product_sync,
		"width":root.size.x, "height":root.size.y, "uiScale":root.content_scale_factor,
		"vsync":DisplayServer.window_get_vsync_mode(), "maxFps":Engine.max_fps,
		"msaa3d":root.msaa_3d, "shadowAtlas":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		"softShadowQuality":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
		"gpuTiming":not args.has("no-gpu-timing"), "world":app.source.world_config.duplicate(true),
		"historySeed":app.source.history_seed, "historyYears":history_years, "cell":cell,
		"distance":app.map_view.camera.distance, "yaw":app.map_view.camera.yaw, "tilt":app.map_view.camera.tilt,
		"cameraTransform":str(app.map_view.camera.global_transform), "layer":app.current_layer,
		"quality":app.settings.duplicate(), "seconds":_seconds(), "settleSeconds":_settle_seconds(),
		"serverPid":app.source._pid, "clientPid":OS.get_process_id(), "columns":COLUMNS,
		"notes":"Graphical run. GPU timers are asynchronous; zero means unavailable. Variants other than base are ablations, not optimizations."})
	if not _write_json("ready.json", metadata): return
	var picture := root.get_texture().get_image()
	if picture != null: picture.save_png(output.path_join("view-base.png"))
	app.source.frames_changed.connect(_publication)
	root.focus_exited.connect(func():
		if recording: invalid_reason = "window lost focus")
	root.window_input.connect(_input)
	root.size_changed.connect(func():
		if recording and not str(metadata.get("_resizing", "")).is_empty(): return
		if recording: invalid_reason = "window resized")
	RenderingServer.frame_post_draw.connect(_drawn)
	if args.has("equivalence") and not await _equivalence(): return
	var experiments: Array = []
	var index := 0
	for name: String in plan:
		index += 1
		var result := await _experiment(index, name)
		if result.is_empty(): return
		experiments.append(result)
		metadata["experiments"] = experiments
		_write_json("experiments.json", {"schema":SCHEMA, "experiments":experiments})
	if not plan.has("active"):
		_phase("proof-final")
		if not await _wait_ready(120.0, "proof-final"): return
		if not await _proof("final", 60.0): return
		if metadata.get("finalSHA256") != metadata.get("initialSHA256"):
			_fail("Paused session changed the causal state.")
			return
	metadata["valid"] = experiments.all(func(e: Dictionary): return e.get("valid", false))
	metadata.erase("_resizing")
	if not _write_json("run.json", metadata): return
	_phase("shutdown")
	await app.source.shutdown()
	app.queue_free()
	await get_tree().process_frame
	print("RENDER_DIAGNOSIS_COMPLETE ", output)
	get_tree().quit(0 if metadata["valid"] else 1)


## Worker-chained preparation with a heartbeat that names the failing stage.
func _prepare(years: int) -> bool:
	_phase("prepare")
	var log := FileAccess.open(output.path_join("prepare-progress.jsonl"), FileAccess.WRITE)
	var started := Time.get_ticks_msec()
	var timeout_ms := int(float(args.get("prepare-timeout", 1800)) * 1000.0)
	var stall_ms := int(float(args.get("stall-timeout", 180)) * 1000.0)
	var start_year := int(app.current_year)
	var target := start_year + years
	app._following_live = true
	app.source.start_fast_forward(years, clampi(int(args.get("publish-every", 100)), 1, 100))
	var last_year := start_year
	var last_progress := started
	var next_beat := started
	var frames := 0
	while true:
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		var calculated := int(app.source.calculated_year)
		if calculated != last_year:
			last_year = calculated
			last_progress = now
		var alive := OS.is_process_running(int(app.source._pid))
		var done: bool = not app.source.is_fast_forward() and not app.source.busy and app.current_frame != null and int(app.current_year) == target
		if now >= next_beat or done:
			next_beat = now + 1000
			var beat := {"elapsedS":(now - started) / 1000.0, "calculatedYear":calculated, "visualYear":app.current_year,
				"remaining":app.source.fast_remaining, "fastActive":app.source.is_fast_forward(), "busy":app.source.busy,
				"serverAlive":alive, "lastError":app.source.last_error, "framesRendered":frames,
				"staticBytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
			if log != null:
				log.store_line(JSON.stringify(beat))
				log.flush()
		if done: break
		var reason := ""
		if app.source.last_error != "": reason = "bridge error: " + app.source.last_error
		elif not alive: reason = "Go server process exited during preparation"
		elif now - last_progress > stall_ms: reason = "no annual progress for %d s (stalled at year %d)" % [stall_ms / 1000, last_year]
		elif now - started > timeout_ms: reason = "preparation exceeded %d s at year %d of %d" % [timeout_ms / 1000, last_year, target]
		elif not app.source.is_fast_forward() and not app.source.busy and int(app.current_year) != target and calculated >= target:
			reason = "fast-forward finished at visual year %d, expected %d" % [app.current_year, target]
		if not reason.is_empty():
			if log != null: log.close()
			_fail("Preparation failed: " + reason)
			return false
	if log != null: log.close()
	# The fast-forward progress line is not part of the PR #24 measured view.
	app.hud.set_status("")
	metadata["preparedYear"] = app.current_year
	metadata["preparationMethod"] = "BridgeSource.start_fast_forward (worker-chained one-year advance requests)"
	return await _wait_ready(120.0, "prepare")


## Pixel equivalence of the Phase 2.3 render changes on THIS GPU/driver, in
## several views (measurement view, coast, extreme relief, poles, longitude
## seam, world zoom): terrain shader vs the PR #22 copy (sea hidden) and sea
## tiles vs the PR #22 full plane (sea shader with TIME frozen at 0 in both
## shots). Written to equivalence.json; never part of a timing capture.
func _equivalence() -> bool:
	_phase("equivalence")
	var terrain = app.map_view.terrain
	var camera = app.map_view.camera
	var baseline_path := "res://tests/baseline/terrain_2193a9d.gdshader"
	if not ResourceLoader.exists(baseline_path):
		metadata["equivalence"] = {"available":false, "reason":"baseline shader copy not present in this tree"}
		return true
	var saved := {"target":camera.target, "distance":camera.distance, "yaw":camera._goal_yaw, "tilt":camera._goal_tilt}
	var before: Image = await _static_shot()
	var still := Shader.new()
	still.code = _baseline_water_shader.code.replace("TIME", "0.0")
	var views := _equivalence_views()
	var results := {}
	for view: String in views:
		var spec: Array = views[view]
		camera.focus_on(spec[0], spec[1], true)
		camera._goal_yaw = deg_to_rad(spec[2])
		camera._goal_tilt = float(saved["tilt"])
		camera._snap()
		camera.moved.emit()
		await _settle(_settle_seconds())
		await _visual_idle()
		# Event markers animate; they are not affected by either change.
		app.history.visible = false
		for plane: MeshInstance3D in terrain.water_planes: plane.visible = false
		var shots: Array = []
		for shader: Shader in [_baseline_terrain_shader, load(baseline_path), _baseline_terrain_shader]:
			terrain.material.shader = shader
			await _settle(_settle_seconds())
			shots.append(root.get_texture().get_image())
		terrain.material.shader = _baseline_terrain_shader
		for plane: MeshInstance3D in terrain.water_planes: plane.visible = true
		terrain.water_material.shader = still
		var undo_sea: Callable = _apply("sea-full-plane")
		await _settle(_settle_seconds())
		var sea_baseline := root.get_texture().get_image()
		undo_sea.call()
		await _settle(_settle_seconds())
		var sea_candidate := root.get_texture().get_image()
		terrain.water_material.shader = _baseline_water_shader
		app.history.visible = true
		await _settle(1.0)
		root.get_texture().get_image().save_png(output.path_join("equivalence-%s.png" % view))
		results[view] = {"terrainShader":_image_difference(shots[0], shots[1]), "repeatability":_image_difference(shots[0], shots[2]),
			"seaTiles":_image_difference(sea_candidate, sea_baseline), "center":str(spec[0]), "distance":camera.distance}
		# Keep both images only when a comparison differs, for visual review.
		for pair: Array in [["terrainShader", shots[0], shots[1]], ["repeatability", shots[0], shots[2]], ["seaTiles", sea_candidate, sea_baseline]]:
			if int(results[view][pair[0]].get("differingPixels", 0)) != 0:
				pair[1].save_png(output.path_join("equivalence-%s-%s-a.png" % [view, pair[0]]))
				pair[2].save_png(output.path_join("equivalence-%s-%s-b.png" % [view, pair[0]]))
	camera.focus_on(saved["target"] if saved["target"] is Vector2 else Vector2(saved["target"].x, saved["target"].z), saved["distance"], true)
	camera._goal_yaw = saved["yaw"]
	camera._goal_tilt = saved["tilt"]
	camera._snap()
	camera.moved.emit()
	await _settle(_settle_seconds())
	await _visual_idle()
	# Timed experiments must start from exactly the measurement view again.
	var restored := _image_difference(before, await _static_shot())
	if int(restored.get("differingPixels", -1)) != 0:
		_fail("The measurement view was not restored after the equivalence check.")
		return false
	# A view whose two candidate shots differ is unstable and proves nothing.
	var summary := {"available":true, "stableViews":0, "unstableViews":[], "terrainShaderIdentical":true,
		"seaTilesDifferingPixels":0, "seaTilesPixelsOver8":0}
	for view: String in results:
		var r: Dictionary = results[view]
		if int(r["repeatability"].get("differingPixels", -1)) != 0:
			summary["unstableViews"].append(view)
			continue
		summary["stableViews"] += 1
		if int(r["terrainShader"].get("differingPixels", -1)) != 0: summary["terrainShaderIdentical"] = false
		summary["seaTilesDifferingPixels"] += int(r["seaTiles"].get("differingPixels", 0))
		for bucket in r["seaTiles"].get("deltaHistogram", {}):
			if int(bucket) > 8: summary["seaTilesPixelsOver8"] += int(r["seaTiles"]["deltaHistogram"][bucket])
	var result := summary.merged({"views":results, "seaTiles":terrain.water_tiles})
	metadata["equivalence"] = summary
	return _write_json("equivalence.json", result)


## Deterministic views from the world data (no RNG).
func _equivalence_views() -> Dictionary:
	var world = app.world
	var populated := int(metadata.get("cell", app.selection.get("id", 0)))
	var coast := -1
	var high := -1
	for c: int in world.land_cells:
		if world.coast[c] == 1 and (coast < 0 or app.current_frame.population[c] > app.current_frame.population[coast]): coast = c
		if high < 0 or world.elevation[c] > world.elevation[high]: high = c
	var w: float = app.map_view.mm.map_w
	var h: float = app.map_view.mm.map_h
	var views := {"measurement":[world.cell_center(populated), float(args.get("distance", 18.0)), 0.0],
		"seam":[Vector2(0.0, h * 0.5), 40.0, 0.0], "north-pole":[Vector2(w * 0.5, 12.0), 60.0, 0.0],
		"south-pole":[Vector2(w * 0.25, h - 12.0), 60.0, 0.0], "world":[Vector2(w * 0.5, h * 0.5), 1000.0, 0.0]}
	if coast >= 0: views["coast"] = [world.cell_center(coast), 12.0, 0.0]
	if high >= 0: views["relief"] = [world.cell_center(high), 8.0, 0.0]
	if args.has("equivalence-views"):
		var keep := str(args["equivalence-views"]).split(",", false)
		for name: String in views.keys():
			if not keep.has(name): views.erase(name)
	return views


## The view without its time-animated parts (sea waves, event markers).
func _static_shot() -> Image:
	var terrain = app.map_view.terrain
	app.history.visible = false
	for plane: MeshInstance3D in terrain.water_planes: plane.visible = false
	await _settle(1.0)
	var shot := root.get_texture().get_image()
	app.history.visible = true
	for plane: MeshInstance3D in terrain.water_planes: plane.visible = true
	return shot


func _visual_idle() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while (app.vegetation._task >= 0 or app.vegetation.is_processing()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _image_difference(a: Image, b: Image) -> Dictionary:
	if a == null or b == null or a.get_size() != b.get_size(): return {"comparable":false}
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var da := a.get_data()
	var db := b.get_data()
	var differing := 0
	var max_delta := 0
	var histogram := {}
	for i in range(0, da.size(), 4):
		var delta := maxi(maxi(absi(da[i] - db[i]), absi(da[i + 1] - db[i + 1])), absi(da[i + 2] - db[i + 2]))
		if delta > 0:
			differing += 1
			max_delta = maxi(max_delta, delta)
			var bucket := 1 if delta == 1 else (2 if delta == 2 else (4 if delta <= 4 else (8 if delta <= 8 else 255)))
			histogram[bucket] = int(histogram.get(bucket, 0)) + 1
	return {"comparable":true, "pixels":da.size() / 4, "differingPixels":differing, "maxChannelDelta":max_delta,
		"deltaHistogram":histogram}


func _experiment(index: int, name: String) -> Dictionary:
	var tag := "%02d-%s" % [index, name]
	_phase("apply:" + tag)
	var revert: Variant = _apply(name)
	if revert is String:
		return {"index":index, "name":name, "valid":false, "unavailable":str(revert)}
	await _settle(_settle_seconds())
	if name.begins_with("res-"):
		var expected := Vector2i(1280, 720)
		if root.size != expected or Vector2i(root.get_texture().get_size()) != expected:
			(revert as Callable).call()
			return {"index":index, "name":name, "valid":false, "unavailable":"window could not be resized to 1280x720"}
	if name != "active" and not args.has("no-screenshots"):
		var picture := root.get_texture().get_image()
		if picture != null: picture.save_png(output.path_join("view-%s.png" % tag))
		await _settle(1.0) # Exclude readback and late pipeline compilation.
	rows = []
	publications = []
	invalid_reason = ""
	last_draw_us = 0
	var static_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	_phase("measure:" + tag)
	start_us = Time.get_ticks_usec()
	var started_unix := Time.get_unix_time_from_system()
	recording = true
	if name == "active":
		app.hud._playing = true
		app.source.start_live(int(args.get("rate", 0)))
	await _settle(clampf(float(args.get("active-seconds", 60)), 10.0, 300.0) if name == "active" else _seconds())
	recording = false
	var actual := (Time.get_ticks_usec() - start_us) / 1000000.0
	_phase("revert:" + tag)
	if name == "active":
		app.source.pause()
		if not await _wait_ready(120.0, "active-pause"): return {}
		if not await _proof("final", 60.0): return {}
	else:
		(revert as Callable).call()
	var file := FileAccess.open(output.path_join("frames-%s.jsonl" % tag), FileAccess.WRITE)
	if file == null:
		_fail("Cannot save raw frames.")
		return {}
	for row: Array in rows: file.store_line(JSON.stringify(row))
	file.close()
	var result := {"index":index, "name":name, "tag":tag, "samples":rows.size(), "actualSeconds":actual,
		"startedUnixSeconds":started_unix, "staticBytesBefore":static_before,
		"staticBytesAfter":Performance.get_monitor(Performance.MEMORY_STATIC),
		"renderer":RenderingServer.get_current_rendering_method(), "summary":_summarize(), "publications":publications.duplicate(),
		"valid":invalid_reason.is_empty() and rows.size() >= 2}
	if not invalid_reason.is_empty(): result["invalidReason"] = invalid_reason
	return result


## Returns a revert Callable, or a String explaining why the variant does not apply.
func _apply(name: String) -> Variant:
	var mv = app.map_view
	var sun: DirectionalLight3D = mv.sun
	var env: Environment = mv.env.environment
	var terrain = mv.terrain
	var nothing := func(): pass
	match name:
		"base", "active": return nothing
		"baseline-render":
			# PR #22 terrain shader and sea plane together (whole Phase 2.3 render delta).
			var undo_shader: Variant = _apply("shader-baseline")
			if undo_shader is String: return undo_shader
			var undo_sea: Callable = _apply("sea-full-plane")
			return func():
				undo_sea.call()
				(undo_shader as Callable).call()
		"shader-baseline":
			var code_path := "res://tests/baseline/terrain_2193a9d.gdshader"
			if not ResourceLoader.exists(code_path): return "baseline shader copy not present in this tree"
			terrain.material.shader = load(code_path)
			return func(): terrain.material.shader = _baseline_terrain_shader
		"shadows-off":
			sun.shadow_enabled = false
			return func(): sun.shadow_enabled = true
		"shadow-atlas-4096", "shadow-atlas-2048":
			var size := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"))
			var bits16 := bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits"))
			RenderingServer.directional_shadow_atlas_set_size(4096 if name.ends_with("4096") else 2048, bits16)
			return func(): RenderingServer.directional_shadow_atlas_set_size(size, bits16)
		"shadow-splits-2", "shadow-splits-1":
			var mode := sun.directional_shadow_mode
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if name.ends_with("2") else DirectionalLight3D.SHADOW_ORTHOGONAL
			return func(): sun.directional_shadow_mode = mode
		"shadow-distance-half", "shadow-distance-double":
			var distance := sun.directional_shadow_max_distance
			sun.directional_shadow_max_distance = distance * (0.5 if name.ends_with("half") else 2.0)
			return func(): sun.directional_shadow_max_distance = distance
		"shadow-filter-hard", "shadow-filter-low":
			var quality := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD if name.ends_with("hard") else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			return func(): RenderingServer.directional_soft_shadow_filter_set_quality(quality)
		"shadow-blend-off":
			sun.directional_shadow_blend_splits = false
			return func(): sun.directional_shadow_blend_splits = true
		"shadow-terrain-caster-off":
			for chunk: MeshInstance3D in terrain.chunks: chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return func():
				for chunk: MeshInstance3D in terrain.chunks: chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"ssao-off":
			if not env.ssao_enabled: return "SSAO is not enabled in this configuration"
			env.ssao_enabled = false
			return func(): env.ssao_enabled = true
		"ssao-half-size-off":
			if not env.ssao_enabled: return "SSAO is not enabled in this configuration"
			var half := bool(ProjectSettings.get_setting("rendering/environment/ssao/half_size"))
			RenderingServer.environment_set_ssao_quality(ProjectSettings.get_setting("rendering/environment/ssao/quality"), not half,
				ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target"), ProjectSettings.get_setting("rendering/environment/ssao/blur_passes"),
				ProjectSettings.get_setting("rendering/environment/ssao/fadeout_from"), ProjectSettings.get_setting("rendering/environment/ssao/fadeout_to"))
			return func(): RenderingServer.environment_set_ssao_quality(ProjectSettings.get_setting("rendering/environment/ssao/quality"), half,
				ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target"), ProjectSettings.get_setting("rendering/environment/ssao/blur_passes"),
				ProjectSettings.get_setting("rendering/environment/ssao/fadeout_from"), ProjectSettings.get_setting("rendering/environment/ssao/fadeout_to"))
		"msaa-off", "msaa-off-fxaa":
			var msaa := root.msaa_3d
			var ssaa := root.screen_space_aa
			if msaa == Viewport.MSAA_DISABLED: return "MSAA is already disabled"
			root.msaa_3d = Viewport.MSAA_DISABLED
			if name.ends_with("fxaa"): root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			return func():
				root.msaa_3d = msaa
				root.screen_space_aa = ssaa
		"msaa-off-smaa":
			var msaa := root.msaa_3d
			var ssaa := root.screen_space_aa
			if msaa == Viewport.MSAA_DISABLED: return "MSAA is already disabled"
			if not ClassDB.class_has_integer_constant("Viewport", "SCREEN_SPACE_AA_SMAA"): return "SMAA not available in this Godot build"
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.screen_space_aa = ClassDB.class_get_integer_constant("Viewport", "SCREEN_SPACE_AA_SMAA")
			return func():
				root.msaa_3d = msaa
				root.screen_space_aa = ssaa
		"tonemap-linear":
			var tonemap := env.tonemap_mode
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			return func(): env.tonemap_mode = tonemap
		"fog-off":
			env.fog_enabled = false
			return func(): env.fog_enabled = true
		"terrain-hidden":
			terrain.visible = false
			return func(): terrain.visible = true
		"water-hidden":
			for plane: MeshInstance3D in terrain.water_planes: plane.visible = false
			return func():
				for plane: MeshInstance3D in terrain.water_planes: plane.visible = true
		"vegetation-hidden":
			app.vegetation.visible = false
			return func(): app.vegetation.visible = true
		"settlements-hidden":
			app.settlements.visible = false
			return func(): app.settlements.visible = true
		"overlay-hidden":
			app.history.visible = false
			return func(): app.history.visible = true
		"ui-hidden":
			var layer: CanvasLayer = app.hud.get_parent()
			layer.visible = false
			return func(): layer.visible = true
		"terrain-fragment-min", "terrain-normal-hw", "terrain-overlay-off", "terrain-vertex-min", "terrain-noise-off":
			var code := _terrain_variant(name, _baseline_terrain_shader.code)
			if code.is_empty(): return "terrain shader layout differs; variant %s not derivable" % name
			var shader := Shader.new()
			shader.code = code
			terrain.material.shader = shader
			return func(): terrain.material.shader = _baseline_terrain_shader
		"water-fragment-min":
			var code: String = _baseline_water_shader.code
			var at := code.find("void fragment()")
			if at < 0: return "water shader layout differs"
			var shader := Shader.new()
			shader.code = code.substr(0, at) + "void fragment() {\n\tfloat e = elev_bilinear(v_world.xz);\n\tif (e > 0.0) { discard; }\n\tALBEDO = deep_color;\n\tROUGHNESS = 0.18;\n\tSPECULAR = 0.55;\n}\n"
			terrain.water_material.shader = shader
			return func(): terrain.water_material.shader = _baseline_water_shader
		"sea-full-plane":
			# PR #22 sea geometry: one 1600x800 plane per longitude copy.
			var plane := PlaneMesh.new()
			plane.size = Vector2(app.map_view.mm.map_w, app.map_view.mm.map_h)
			plane.subdivide_width = 8
			plane.subdivide_depth = 4
			plane.material = terrain.water_material
			var meshes: Array = []
			for sea: MeshInstance3D in terrain.water_planes:
				meshes.append(sea.mesh)
				sea.mesh = plane
			return func():
				for k in terrain.water_planes.size(): terrain.water_planes[k].mesh = meshes[k]
		"water-priority-first", "water-priority-last":
			# Opaque draw order only (sort key priority); depth testing decides pixels.
			var material: ShaderMaterial = terrain.water_material
			var priority := material.render_priority
			material.render_priority = -1 if name.ends_with("first") else 1
			return func(): material.render_priority = priority
		"lod-coarse", "lod-fine":
			var target: float = terrain.target_pixels_per_quad
			terrain.target_pixels_per_quad = target * (2.0 if name.ends_with("coarse") else 0.5)
			mv.invalidate_view()
			return func():
				terrain.target_pixels_per_quad = target
				mv.invalidate_view()
		"render-scale-0.75", "render-scale-0.5":
			var scale := root.scaling_3d_scale
			root.scaling_3d_scale = 0.75 if name.ends_with("0.75") else 0.5
			return func(): root.scaling_3d_scale = scale
		"res-720", "res-720-lod-matched":
			var size := root.size
			var target: float = terrain.target_pixels_per_quad
			metadata["_resizing"] = name
			root.size = Vector2i(1280, 720)
			if name.ends_with("matched"):
				# LOD uses viewport height: scale the target so chunk LODs match 1080p.
				terrain.target_pixels_per_quad = target * 720.0 / float(size.y)
			mv.invalidate_view()
			return func():
				root.size = size
				terrain.target_pixels_per_quad = target
				mv.invalidate_view()
				metadata["_resizing"] = ""
	return "unknown variant"


## Derives diagnostic terrain shaders from the loaded code; empty if anchors moved.
func _terrain_variant(name: String, code: String) -> String:
	match name:
		"terrain-fragment-min":
			var at := code.find("void fragment()")
			if at < 0: return ""
			return code.substr(0, at) + "void fragment() {\n\tALBEDO = biome_colors[4];\n\tROUGHNESS = 0.92;\n\tSPECULAR = 0.35;\n}\n"
		"terrain-vertex-min":
			var begin := code.find("void vertex()")
			var end := code.find("int biome_of(")
			if begin < 0 or end < begin: return ""
			return code.substr(0, begin) + "void vertex() {\n\tvec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n\tfloat e = elev_hw(wp.xz);\n\tfloat h = metres_to_units(e);\n\tif (COLOR.r > 0.5) { h -= skirt_depth; }\n\tVERTEX.y = h;\n\tv_world = vec3(wp.x, h, wp.z);\n\tv_elev = e;\n}\n\n" + code.substr(end)
		"terrain-normal-hw", "terrain-noise-off":
			var begin := code.find("\tfloat e = elev_bilinear(p);\n\tvec2 rp = relief_params(p, e);")
			var end := code.find("\tbool fine_land = e > 0.0;")
			if begin < 0 or end < begin: return ""
			var block := ""
			if name == "terrain-normal-hw":
				# Hardware-filtered elevation, no relief noise: removes most normal ALU/fetches.
				block = "\tfloat e = elev_bilinear(p);\n\tvec2 rp = vec2(0.0);\n\tfloat eps = 0.25;\n\tfloat hc = metres_to_units(e);\n\tfloat hl = metres_to_units(elev_hw(p - vec2(eps, 0.0)));\n\tfloat hr = metres_to_units(elev_hw(p + vec2(eps, 0.0)));\n\tfloat hu = metres_to_units(elev_hw(p - vec2(0.0, eps)));\n\tfloat hd = metres_to_units(elev_hw(p + vec2(0.0, eps)));\n\tvec3 n = normalize(vec3(hl - hr, 2.0 * eps, hu - hd));\n\tfloat cavity = clamp(((hl + hr + hu + hd) * 0.25 - hc) * 6.0, -1.0, 1.0);\n"
			else:
				# Same normal structure, relief noise removed everywhere in the fragment.
				block = code.substr(begin, end - begin)
				return (code.substr(0, begin) + block + code.substr(end)).replace("float mottling = relief_noise(p * 3.1) * 0.5 + vnoise(p, int(map_size.x * 6.0), 9000) * 0.5;", "float mottling = 0.0;").replace("relief_noise(p * 2.0)", "0.0").replace("vec2 rp = relief_params(p, e);", "vec2 rp = vec2(0.0);")
			return code.substr(0, begin) + block + code.substr(end)
		"terrain-overlay-off":
			var anchor := "\t// --- overlays: thematic colour, province and group borders, selection\n\tif (fine_land) {"
			if code.find(anchor) < 0: return ""
			return code.replace(anchor, "\t// --- overlays disabled for diagnosis\n\tif (false) {")
	return ""


func _drawn() -> void:
	if not recording: return
	var now := Time.get_ticks_usec()
	if last_draw_us == 0:
		last_draw_us = now
		return
	var rid := root.get_viewport_rid()
	rows.append([(now - start_us) / 1000.0, (now - last_draw_us) / 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(rid),
		RenderingServer.viewport_get_measured_render_time_gpu(rid),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.MEMORY_STATIC), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), app.current_year, app.map_view.terrain.stats["triangles"],
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)])
	last_draw_us = now


func _summarize() -> Dictionary:
	var summary := {}
	if rows.is_empty(): return summary
	for column in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16]:
		var values: Array = []
		for row: Array in rows: values.append(float(row[column]))
		values.sort()
		summary[COLUMNS[column]] = {"p50":_quantile(values, 0.5), "p95":_quantile(values, 0.95), "p99":_quantile(values, 0.99), "max":values[-1]}
	var fps: Array = []
	var over_budget := 0
	var total_ms := 0.0
	var windows := {}
	for row: Array in rows:
		fps.append(1000.0 / maxf(float(row[1]), 0.001))
		total_ms += float(row[1])
		if float(row[1]) > 1000.0 / 30.0: over_budget += 1
		var window := int(float(row[0]) / 1000.0)
		windows[window] = int(windows.get(window, 0)) + 1
	fps.sort()
	summary["fpsP50"] = _quantile(fps, 0.5)
	summary["fpsMean"] = rows.size() * 1000.0 / total_ms
	summary["over33msPercent"] = 100.0 * over_budget / rows.size()
	var full_windows: Array = []
	for window: int in windows:
		if window > 0 and window < int(float(rows[-1][0]) / 1000.0): full_windows.append(windows[window])
	summary["minFullSecondFrames"] = full_windows.min() if not full_windows.is_empty() else null
	summary["gpuTimingAvailable"] = not args.has("no-gpu-timing") and float(summary["renderGpuMs"]["p50"]) > 0.0
	return summary


func _quantile(sorted: Array, fraction: float) -> float:
	return float(sorted[maxi(0, ceili(sorted.size() * fraction) - 1)])


func _plan() -> Array:
	var raw := str(args.get("plan", "diagnosis"))
	var plan: Array = PLANS[raw].duplicate() if PLANS.has(raw) else Array(raw.split(",", false))
	if args.has("active") and not plan.has("active"): plan.append("active")
	return plan


func _requested_size() -> Vector2i:
	return Vector2i(int(args.get("width", 1920)), int(args.get("height", 1080)))


func _seconds() -> float:
	return clampf(float(args.get("seconds", 15)), 5.0, 300.0)


func _settle_seconds() -> float:
	return clampf(float(args.get("settle-seconds", 4)), 1.0, 60.0)


func _phase(name: String) -> void:
	# Read by the Windows runner to tag process samples; never parsed for results.
	var file := FileAccess.open(output.path_join("phase.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"phase":name, "unixSeconds":Time.get_unix_time_from_system()}))
	file.close()


func _publication() -> void:
	if recording:
		publications.append({"elapsedMs":(Time.get_ticks_usec() - start_us) / 1000.0, "year":app.current_year})


func _wait_ready(seconds: float, stage: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if app.source.last_error != "":
			_fail("%s: %s" % [stage, app.source.last_error])
			return false
		if app.current_frame != null and not app.source.busy and not app.source.is_live(): return true
		await get_tree().process_frame
	_fail("Timeout waiting for an exact complete state during %s (busy=%s, live=%s, year=%s, serverAlive=%s)." % [stage,
		app.source.busy, app.source.is_live(), app.current_year, OS.is_process_running(int(app.source._pid))])
	return false


func _proof(label: String, seconds: float) -> bool:
	var reply: Dictionary = {}
	app.source.request("get_replay", {}, func(response: Dictionary): reply.assign(response))
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while reply.is_empty() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if not reply.get("ok", false):
		_fail("Replay proof failed (%s)." % label)
		return false
	var replay: Dictionary = reply.get("data", {})
	metadata[label + "Year"] = replay.get("finalYear")
	metadata[label + "SHA256"] = replay.get("finalSHA256")
	return _write_json(label + "-replay.json", replay)


func _settle(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline: await get_tree().process_frame


func _write_json(name: String, value: Dictionary) -> bool:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	if file == null:
		_fail("Cannot write " + name)
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true


func _input(event: InputEvent) -> void:
	if recording and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		invalid_reason = "manual input during measurement"


func _fail(message: String) -> void:
	printerr("RENDER_DIAGNOSIS_ERROR ", message)
	_phase("failed")
	if not output.is_empty() and DirAccess.dir_exists_absolute(output):
		var file := FileAccess.open(output.path_join("error.txt"), FileAccess.WRITE)
		if file != null: file.store_string(message)
		if not metadata.is_empty(): _write_json("run.json", metadata.merged({"valid":false, "invalidReason":message}))
	if app != null and app.source != null: app.source.close()
	get_tree().quit(1)
