class_name PerformanceTrace
extends RefCounted
## Main-thread-only, opt-in telemetry. One owner opens ASABIYA_PROFILE_PATH.
## CPU scopes can nest: their durations must not be added together.
## RenderingServer memory monitors are estimates, not physical VRAM or GPU time.

const MAX_SAMPLES := 3600
const WINDOW_USEC := 2000000

var _file: FileAccess
var _samples := PackedFloat64Array()
var _scopes := {}
var _context := {}
var _window_start := 0
var _last_frame := 0
var _frames := 0
var _peak_static := 0.0


func _init() -> void:
	var path := OS.get_environment("ASABIYA_PROFILE_PATH")
	if path == "": return
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("No se pudo crear el perfil de rendimiento: " + path)
		return
	record("environment", {"schema":"asabiya/client-profile-v2",
		"godot":Engine.get_version_info().get("string", ""),
		"os":OS.get_name(),"cpu":OS.get_processor_name(),
		"renderer":RenderingServer.get_current_rendering_method(),
		"headless":DisplayServer.get_name() == "headless",
		"timing":"CPU wall time; nested scopes; no GPU timing"})
	_file.flush()


func enabled() -> bool:
	return _file != null


func begin() -> int:
	return Time.get_ticks_usec() if _file != null else 0


func end(stage: String, started: int) -> void:
	if started == 0 or _file == null: return
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	if not _scopes.has(stage):
		_scopes[stage] = {"calls":0,"totalMs":0.0,"maxMs":0.0,"samples":[]}
	var scope: Dictionary = _scopes[stage]
	scope["calls"] += 1
	scope["totalMs"] += elapsed
	scope["maxMs"] = maxf(scope["maxMs"], elapsed)
	var samples: Array = scope["samples"]
	if samples.size() < MAX_SAMPLES: samples.append(elapsed)


func set_context(fields: Dictionary) -> void:
	if _file != null: _context.merge(fields, true)


func record(stage: String, fields: Dictionary) -> void:
	if _file == null: return
	var row := fields.duplicate()
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
	var scopes := {}
	for stage: String in _scopes:
		var scope: Dictionary = _scopes[stage]
		var summary := {"calls":scope["calls"],"totalMs":scope["totalMs"],
			"meanMs":scope["totalMs"] / scope["calls"],"maxMs":scope["maxMs"],
			"sampledCalls":scope["samples"].size()}
		summary.merge(_percentiles(scope["samples"]))
		scopes[stage] = summary
	fields["cpuScopes"] = scopes
	record("frame-window", fields)
	_file.flush() # Once per window, never once per measured scope/frame.
	_samples.clear()
	_scopes.clear()
	_frames = 0
	_window_start = now


func close() -> void:
	if _file == null: return
	_file.flush()
	_file = null
