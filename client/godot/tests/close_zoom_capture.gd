extends SceneTree
## Opt-in graphical measurement harness. Also runs against an UNMODIFIED #22
## checkout via --path BASE/client/godot --script /absolute/path/to/this/file.
## Never loaded by the product scene; no changes to renderer or Go defaults.
const App := preload("res://scripts/app/main.gd")

var app: Node
var args: Dictionary
var rows: Array = []
var publications: Array = []
var recording := false
var invalid_reason := ""
var last_draw_us := 0
var start_us := 0
var output := ""
var metadata: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	args = App.parse_args(OS.get_cmdline_user_args())
	output = str(args.get("output", ""))
	if output.is_empty() or DisplayServer.get_name() == "headless":
		_fail("A graphical display and --output DIRECTORY are required; headless is not a GPU benchmark.")
		return
	var version := Engine.get_version_info()
	if version.get("major") != 4 or version.get("minor") != 7 or version.get("patch") != 2 or version.get("status") != "stable" or version.get("build") != "official":
		_fail("Use the pinned official Godot 4.7.2 editor.")
		return
	if str(args.get("mode", "paused")) not in ["paused", "active"]:
		_fail("--mode must be paused or active.")
		return
	var diagnostic := str(args.get("diagnostic", "none"))
	if diagnostic not in ["none", "shadows-off", "ssao-off", "terrain-hidden", "vegetation-hidden", "lod-coarse"]:
		_fail("Unknown diagnostic; no measurement was started.")
		return
	if not DirAccess.dir_exists_absolute(output) and DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create measurement directory.")
		return
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(int(args.get("width", 1920)), int(args.get("height", 1080)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	App.pending_world = {"seed":str(args.get("seed", "Asabiya")), "width":400, "height":200, "detail":4, "landFraction":0.33}
	App.pending_source = {}
	app = App.new()
	root.add_child(app)
	app._launch.launch.pressed.emit()
	if not await _wait_ready(180.0): return
	# Pin user-dependent settings without saving or replacing their settings.cfg.
	app.settings = {"quality":1, "relief":1}
	app._apply_settings(false)
	root.content_scale_factor = 1.0
	var history_years := int(args.get("history-years", 10000))
	if history_years < 0 or history_years > 10000:
		_fail("--history-years must be between 0 and 10000.")
		return
	if history_years > 0:
		app.source.advance(history_years)
		if not await _wait_ready(1200.0): return
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
	# Diagnostic ablations are NEVER candidates for the visual acceptance gate.
	match diagnostic:
		"shadows-off": app.map_view.sun.shadow_enabled = false
		"ssao-off": app.map_view.env.environment.ssao_enabled = false
		"terrain-hidden": app.map_view.terrain.visible = false
		"vegetation-hidden": app.vegetation.visible = false
		"lod-coarse":
			app.map_view.terrain.target_pixels_per_quad *= 2.0
			app.map_view.invalidate_view()
	# Pointer stays over terrain; manual keyboard/window changes invalidate runs.
	root.warp_mouse(Vector2(root.size) * Vector2(0.5, 0.4))
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, not args.has("no-gpu-timing"))
	await _settle(float(args.get("warmup-seconds", 20)))
	var visual_deadline := Time.get_ticks_msec() + 120000
	while app.vegetation._task >= 0 or app.vegetation.is_processing() or app.map_view.river_baker != null:
		if Time.get_ticks_msec() >= visual_deadline:
			_fail("Visual warm-up did not finish.")
			return
		await process_frame
	if not await _wait_ready(120.0): return
	# Warm-up is paused for BOTH cases: all cases begin at exactly the same state.
	if not await _proof("initial", 60.0): return
	var expected_size := Vector2i(int(args.get("width", 1920)), int(args.get("height", 1080)))
	if root.size != expected_size or Vector2i(root.get_texture().get_size()) != expected_size:
		_fail("Requested %s pixels; window=%s, texture=%s. Run rejected." % [expected_size, root.size, root.get_texture().get_size()])
		return
	var picture := root.get_texture().get_image()
	if picture == null or picture.save_png(output.path_join("view-before.png")) != OK:
		_fail("Cannot save the pre-measurement visual reference.")
		return
	await _settle(2.0) # Exclude screenshot GPU readback and any late shader work.
	metadata.merge({"schema":"asabiya/close-zoom-run-v1", "revision":str(args.get("revision", "unknown")),
		"mode":str(args.get("mode", "paused")), "diagnostic":diagnostic,
		"godot":Engine.get_version_info(), "os":OS.get_name(), "cpu":OS.get_processor_name(),
		"gpu":RenderingServer.get_video_adapter_name(), "vendor":RenderingServer.get_video_adapter_vendor(),
		"api":RenderingServer.get_video_adapter_api_version(), "renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(),
		"width":root.size.x, "height":root.size.y, "viewportSize":str(root.get_texture().get_size()),
		"uiScale":root.content_scale_factor,
		"vsync":DisplayServer.window_get_vsync_mode(), "maxFps":Engine.max_fps,
		"gpuTiming":not args.has("no-gpu-timing"), "cpuScopes":OS.get_environment("ASABIYA_PROFILE_PATH") != "",
		"world":app.source.world_config.duplicate(true), "historySeed":app.source.history_seed,
		"historyYears":history_years, "cell":cell, "distance":app.map_view.camera.distance,
		"yaw":app.map_view.camera.yaw, "tilt":app.map_view.camera.tilt,
		"cameraTransform":str(app.map_view.camera.global_transform), "cameraProjection":str(app.map_view.camera.get_camera_projection()),
		"layer":app.current_layer, "quality":app.settings.duplicate(), "rate":int(args.get("rate", 0)),
		"requestedSeconds":float(args.get("seconds", 60)), "warmupSeconds":float(args.get("warmup-seconds", 20)),
		"serverPid":app.source._pid, "clientPid":OS.get_process_id(),
		"notes":"Source/editor graphical run; not exported-release or presentation-latency certification. GPU timers may lag; never force a render sync."})
	if not _write_json("ready.json", metadata): return
	app.source.frames_changed.connect(_publication)
	root.focus_exited.connect(func():
		if recording: invalid_reason = "window lost focus")
	root.window_input.connect(_input)
	root.size_changed.connect(func():
		if recording: invalid_reason = "window resized")
	RenderingServer.frame_post_draw.connect(_drawn)
	start_us = Time.get_ticks_usec()
	last_draw_us = 0
	metadata["measuredStartedUnixSeconds"] = Time.get_unix_time_from_system()
	metadata["staticBytesBeforeCapture"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	recording = true
	if metadata["mode"] == "active":
		app.hud._playing = true
		app.source.start_live(int(metadata["rate"]))
	await _settle(float(metadata["requestedSeconds"]))
	recording = false
	metadata["measuredFinishedUnixSeconds"] = Time.get_unix_time_from_system()
	metadata["actualSeconds"] = (Time.get_ticks_usec() - start_us) / 1000000.0
	metadata["measuredFinalYear"] = app.current_year
	app.source.pause()
	if not await _wait_ready(120.0): return
	if not await _proof("final", 60.0): return
	metadata["publications"] = publications
	metadata["samples"] = rows.size()
	metadata["staticBytesAfterCapture"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	metadata["collectorNominalScalarBytes"] = rows.size() * 15 * 8 # Excludes Array/Variant overhead.
	if not invalid_reason.is_empty():
		metadata["valid"] = false
		metadata["invalidReason"] = invalid_reason
	else: metadata["valid"] = rows.size() >= 2
	var file := FileAccess.open(output.path_join("frames.jsonl"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot save raw frames.")
		return
	for row: Array in rows: file.store_line(JSON.stringify(row))
	file.close()
	metadata["columns"] = ["elapsedMs", "frameMs", "processMs", "renderCpuMs", "renderGpuMs", "drawCalls", "shadowDrawCalls", "primitives", "shadowPrimitives", "staticBytes", "renderVideoBytes", "nodes", "year", "terrainAssignedTriangles", "canvasDrawCalls"]
	metadata["summary"] = _summarize()
	if not _write_json("run.json", metadata): return
	var final_picture := root.get_texture().get_image()
	if final_picture != null: final_picture.save_png(output.path_join("view-after.png"))
	await app.source.shutdown()
	app.queue_free()
	await process_frame
	print("CLOSE_ZOOM_COMPLETE ", output)
	quit(0 if metadata["valid"] else 1)

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
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	last_draw_us = now

func _summarize() -> Dictionary:
	var summary := {}
	if rows.is_empty(): return summary
	for spec: Array in [["frameMs", 1], ["processMs", 2], ["renderCpuMs", 3], ["renderGpuMs", 4], ["drawCalls", 5], ["shadowDrawCalls", 6], ["primitives", 7], ["shadowPrimitives", 8], ["staticBytes", 9], ["renderVideoBytes", 10], ["canvasDrawCalls", 14]]:
		var values: Array = []
		for row: Array in rows: values.append(float(row[int(spec[1])]))
		values.sort()
		summary[spec[0]] = {"p50":_quantile(values, 0.5), "p95":_quantile(values, 0.95), "p99":_quantile(values, 0.99), "max":values[-1]}
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
	# Both the first and last time bins can be partial.
	for window: int in windows:
		if window > 0 and window < int(float(rows[-1][0]) / 1000.0): full_windows.append(windows[window])
	summary["minFullSecondFrames"] = full_windows.min() if not full_windows.is_empty() else null
	summary["gpuTimingAvailable"] = args.has("no-gpu-timing") == false and float(summary["renderGpuMs"]["p50"]) > 0.0
	return summary

func _quantile(sorted: Array, fraction: float) -> float:
	return float(sorted[maxi(0, ceili(sorted.size() * fraction) - 1)])

func _publication() -> void:
	if recording:
		publications.append({"elapsedMs":(Time.get_ticks_usec() - start_us) / 1000.0, "year":app.current_year})

func _wait_ready(seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if app.source.last_error != "":
			_fail(app.source.last_error)
			return false
		if app.current_frame != null and not app.source.busy and not app.source.is_live(): return true
		await process_frame
	_fail("Timeout waiting for an exact complete state.")
	return false

func _proof(label: String, seconds: float) -> bool:
	var reply: Dictionary = {}
	app.source.request("get_replay", {}, func(response: Dictionary): reply.assign(response))
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while reply.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	if not reply.get("ok", false):
		_fail("Replay proof failed.")
		return false
	var replay: Dictionary = reply.get("data", {})
	metadata[label + "Year"] = replay.get("finalYear")
	metadata[label + "SHA256"] = replay.get("finalSHA256")
	return _write_json(label + "-replay.json", replay)

func _settle(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline: await process_frame

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
	printerr("CLOSE_ZOOM_ERROR ", message)
	if not output.is_empty() and DirAccess.dir_exists_absolute(output):
		var file := FileAccess.open(output.path_join("error.txt"), FileAccess.WRITE)
		if file != null: file.store_string(message)
	if app != null and app.source != null: app.source.close()
	quit(1)
