class_name PerformanceTrace
extends RefCounted
## Opt-in bounded telemetry. ASABIYA_PROFILE_PATH must name a writable JSONL file.
## GPU allocations are renderer estimates, not total driver/physical VRAM usage.

var _file: FileAccess
var _samples := PackedFloat64Array()
var _window_start := 0
var _last_frame := 0
var _frames := 0
var _peak_static := 0.0


func _init() -> void:
	var path := OS.get_environment("ASABIYA_PROFILE_PATH")
	if path == "":
		return
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("No se pudo crear el perfil de rendimiento: " + path)
		return
	_window_start = Time.get_ticks_usec()
	_last_frame = _window_start
	record("environment", {"godot":Engine.get_version_info().get("string", ""),
		"os":OS.get_name(),"cpu":OS.get_processor_name(),
		"renderer":RenderingServer.get_current_rendering_method(),
		"headless":DisplayServer.get_name() == "headless"})


func enabled() -> bool:
	return _file != null


func record(stage: String, fields: Dictionary) -> void:
	if _file == null:
		return
	var row := fields.duplicate()
	row["stage"] = stage
	row["ticksUsec"] = Time.get_ticks_usec()
	_file.store_line(JSON.stringify(row))
	_file.flush()


func frame() -> void:
	if _file == null:
		return
	var now := Time.get_ticks_usec()
	if _samples.size() < 3600:
		_samples.append(float(now - _last_frame) / 1000.0)
	_last_frame = now
	_frames += 1
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	_peak_static = maxf(_peak_static, memory)
	if now - _window_start < 2000000:
		return
	_samples.sort()
	var fields := {"fps":float(_frames) * 1000000.0 / (now - _window_start),
		"sampledFrames":_samples.size(),"processMs":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"staticBytes":memory,"peakStaticBytes":_peak_static,
		"renderVideoBytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"renderTextureBytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"renderBufferBytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"drawCalls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphanNodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
	for q in [0.5, 0.95, 0.99]:
		fields["frameP%dMs" % int(q * 100.0)] = _samples[mini(_samples.size() - 1, ceili(_samples.size() * q) - 1)]
	record("frame-window", fields)
	_samples.clear()
	_frames = 0
	_window_start = now
