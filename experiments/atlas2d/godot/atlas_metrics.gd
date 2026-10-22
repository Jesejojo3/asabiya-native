class_name AtlasMetrics
extends RefCounted
var file: FileAccess
var last_draw_us := 0
var started_us := 0
var duration := 0.0
var warmup := 3.0
var start_year := 0
var active := false
var updates := 0
var selection_us := 0
var publication_us := 0
var finished := false
var sampling := false
## Main-thread milliseconds spent by the Atlas in _process since the last draw.
var main_ms := 0.0
var viewport := RID()

func open(path: String, seconds: float, metadata: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	file=FileAccess.open(path,FileAccess.WRITE)
	assert(file!=null,"Cannot write benchmark output")
	duration=seconds
	record("environment",metadata)

func record(kind: String, values: Dictionary) -> void:
	if file==null: return
	var row := values.duplicate()
	row["kind"]=kind
	row["ticks_us"]=Time.get_ticks_usec()
	file.store_line(JSON.stringify(row))
	if kind in ["environment","ready","begin","sample_begin","end","verified_pause","error"]: file.flush()

func begin(year: int, is_active: bool) -> void:
	started_us=Time.get_ticks_usec()
	last_draw_us=0
	start_year=year
	active=is_active
	record("begin",{"year":year,"active":active,"warmup_seconds":warmup,"duration_seconds":duration})

func draw(year: int) -> bool:
	if started_us==0 or finished: return false
	var now := Time.get_ticks_usec()
	var elapsed := (now-started_us)/1000000.0
	if elapsed>=warmup and not sampling:
		sampling=true
		record("sample_begin",{"year":year})
	if elapsed>=warmup and last_draw_us>0:
		record("frame",{"frame_ms":(now-last_draw_us)/1000.0,"year":year,"godot_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),
			"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"main_ms":main_ms})
		main_ms=0.0
		if selection_us>0:
			record("selection_present",{"ms":(now-selection_us)/1000.0})
			selection_us=0
		if publication_us>0:
			record("map_present",{"ms":(now-publication_us)/1000.0,"year":year})
			publication_us=0
	selection_us=0
	publication_us=0
	last_draw_us=now
	if elapsed>=warmup+duration:
		finished=true
		record("end",{"year":year,"start_year":start_year,"elapsed_seconds":elapsed,"updates":updates})
		file.flush()
		return true
	return false
