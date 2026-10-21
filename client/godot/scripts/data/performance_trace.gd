class_name PerformanceTrace
extends RefCounted
## Main-thread-only, opt-in telemetry. One owner opens ASABIYA_PROFILE_PATH.
## Stack scopes report inclusive and exclusive wall time. Worker spans are separate.
## RenderingServer memory monitors are estimates, not physical VRAM or GPU time.

const MAX_SAMPLES := 3600
const WINDOW_USEC := 2000000

var _trace_session := ""
var _file: FileAccess
var _samples := PackedFloat64Array()
var _scopes := {}
var _context := {}
var _stack: Array = []
var _worker_scopes := {}
var _counters := {}
var _observed_frame := -1
var _observed_start := 0
var _observed_scoped_usec := 0
var _window_start := 0
var _last_frame := 0
var _frames := 0
var _peak_static := 0.0


func _init() -> void:
	var path := OS.get_environment("ASABIYA_PROFILE_PATH")
	if path == "": return
	# Creating another world must not truncate the previous session.
	_trace_session = "%d-%d-%s" % [OS.get_process_id(), int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(16).hex_encode()]
	_file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if _file == null:
		push_warning("No se pudo crear el perfil de rendimiento: " + path)
		return
	_file.seek_end()
	record("environment", {"schema":"asabiya/client-profile-v3",
		"godot":Engine.get_version_info().get("string", ""),
		"os":OS.get_name(),"cpu":OS.get_processor_name(),
		"renderer":RenderingServer.get_current_rendering_method(),
		"headless":DisplayServer.get_name() == "headless",
		"timing":"CPU wall time, inclusive/exclusive; worker spans separate; no GPU timing"})
	_file.flush()


func enabled() -> bool:
	return _file != null


func begin() -> int:
	if _file == null: return 0
	var now := Time.get_ticks_usec()
	var frame_id := Engine.get_process_frames()
	if frame_id != _observed_frame:
		if not _stack.is_empty():
			counter("abandonedScopes", _stack.size())
			_stack.clear()
		_observed_frame = frame_id
		_observed_start = now
		_observed_scoped_usec = 0
	_stack.append({"started":now,"children":0})
	return now


func end(stage: String, started: int) -> void:
	if started == 0 or _file == null: return
	if _stack.is_empty() or int(_stack[-1]["started"]) != started:
		counter("scopeStackErrors")
		return
	var entry: Dictionary = _stack.pop_back()
	var elapsed := Time.get_ticks_usec() - started
	var exclusive := maxi(0, elapsed - int(entry["children"]))
	if _stack.is_empty(): _observed_scoped_usec += elapsed
	else: _stack[-1]["children"] += elapsed
	_add_sample(_scopes, stage, elapsed, exclusive)


func _add_sample(target: Dictionary, stage: String, inclusive_usec: int, exclusive_usec: int) -> void:
	if not target.has(stage):
		target[stage] = {"calls":0,"totalMs":0.0,"maxMs":0.0,"samples":[],
			"exclusiveTotalMs":0.0,"exclusiveMaxMs":0.0,"exclusiveSamples":[]}
	var scope: Dictionary = target[stage]
	var elapsed := float(inclusive_usec) / 1000.0
	var exclusive := float(exclusive_usec) / 1000.0
	scope["calls"] += 1
	scope["totalMs"] += elapsed
	scope["maxMs"] = maxf(scope["maxMs"], elapsed)
	scope["exclusiveTotalMs"] += exclusive
	scope["exclusiveMaxMs"] = maxf(scope["exclusiveMaxMs"], exclusive)
	var samples: Array = scope["samples"]
	var exclusive_samples: Array = scope["exclusiveSamples"]
	if samples.size() < MAX_SAMPLES:
		samples.append(elapsed)
		exclusive_samples.append(exclusive)


func counter(name: String, amount := 1) -> void:
	if _file != null: _counters[name] = _counters.get(name, 0) + amount


func worker_span(stage: String, usec: int) -> void:
	if _file != null: _add_sample(_worker_scopes, stage, usec, usec)


func worker_report(fields: Dictionary) -> void:
	if _file == null or fields.is_empty(): return
	var index_usec := int(fields.get("indexUsec", 0))
	var decode_usec := int(fields.get("decodeUsec", 0))
	_add_sample(_worker_scopes, "receive", int(fields.get("receiveUsec", 0)), int(fields.get("receiveUsec", 0)))
	_add_sample(_worker_scopes, "json-parse", int(fields.get("jsonUsec", 0)), int(fields.get("jsonUsec", 0)))
	if fields.has("decodeUsec"): _add_sample(_worker_scopes, "decode-publication", decode_usec, maxi(0, decode_usec - index_usec))
	if fields.has("indexUsec"): _add_sample(_worker_scopes, "visual-index", index_usec, index_usec)
	counter("responseBytes", int(fields.get("bytes", 0)))
	for name: String in ["shapesRebuilt", "shapesReused", "totalsCellsScanned"]:
		counter(name, int(fields.get(name, 0)))


## Called by a last-priority probe. Observed gap excludes named outer scopes,
## but includes bookkeeping/other callbacks between the first scope and probe.
## It is NOT TIME_PROCESS minus scope totals and is never a GPU measurement.
func finish_process_frame() -> void:
	if _file == null: return
	if _observed_frame == Engine.get_process_frames():
		if _stack.is_empty():
			var gap := maxi(0, Time.get_ticks_usec() - _observed_start - _observed_scoped_usec)
			_add_sample(_scopes, "main-unclassified-observed", gap, gap)
		else: counter("scopeStackErrors")
	frame()


func _summaries(source: Dictionary) -> Dictionary:
	var summaries := {}
	for stage: String in source:
		var scope: Dictionary = source[stage]
		var summary := {"calls":scope["calls"],"totalMs":scope["totalMs"],
			"meanMs":scope["totalMs"] / scope["calls"],"maxMs":scope["maxMs"],
			"exclusiveTotalMs":scope["exclusiveTotalMs"],"exclusiveMeanMs":scope["exclusiveTotalMs"] / scope["calls"],
			"exclusiveMaxMs":scope["exclusiveMaxMs"],"sampledCalls":scope["samples"].size(),
			"unsampledCalls":scope["calls"] - scope["samples"].size()}
		summary.merge(_percentiles(scope["samples"]))
		var exclusive := _percentiles(scope["exclusiveSamples"])
		for key: String in exclusive: summary["exclusiveP" + key.substr(1)] = exclusive[key]
		summaries[stage] = summary
	return summaries


func set_context(fields: Dictionary) -> void:
	if _file != null: _context.merge(fields, true)


func record(stage: String, fields: Dictionary) -> void:
	if _file == null: return
	var row := fields.duplicate()
	row["traceSession"] = _trace_session
	row["stage"] = stage
	row["ticksUsec"] = Time.get_ticks_usec()
	_file.store_line(JSON.stringify(row))


func _percentiles(samples: Variant) -> Dictionary:
	var result := {}
	if samples.is_empty(): return result
	var sorted: Variant = samples.duplicate()
	sorted.sort()
	for q in [0.5, 0.95, 0.99]:
		result["p%dMs" % int(q * 100.0)] = sorted[mini(sorted.size() - 1, ceili(sorted.size() * q) - 1)]
	return result


func frame() -> void:
	if _file == null: return
	var now := Time.get_ticks_usec()
	if _last_frame == 0:
		_last_frame = now
		_window_start = now
		return
	if _samples.size() < MAX_SAMPLES: _samples.append(float(now - _last_frame) / 1000.0)
	_last_frame = now
	_frames += 1
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	_peak_static = maxf(_peak_static, memory)
	if now - _window_start < WINDOW_USEC: return
	var fields := {"fps":float(_frames) * 1000000.0 / (now - _window_start),
		"windowUsec":now - _window_start,"context":_context.duplicate(),
		"sampledFrames":_samples.size(),"processMs":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"staticBytes":memory,"peakStaticBytes":_peak_static,
		"renderVideoBytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"renderTextureBytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"renderBufferBytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"drawCalls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphanNodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
	var quantiles := _percentiles(_samples)
	for key: String in quantiles: fields["frameP" + key.substr(1)] = quantiles[key]
	fields["cpuScopes"] = _summaries(_scopes)
	fields["workerScopes"] = _summaries(_worker_scopes)
	fields["counters"] = _counters.duplicate()
	record("frame-window", fields)
	_file.flush() # Once per window, never once per measured scope/frame.
	_samples.clear()
	_scopes.clear()
	_worker_scopes.clear()
	_counters.clear()
	_frames = 0
	_window_start = now


func close() -> void:
	if _file == null: return
	record("trace-end", {"partialWindowFrames":_frames})
	_file.flush()
	_file = null
