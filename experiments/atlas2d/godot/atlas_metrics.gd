class_name AtlasMetrics
extends RefCounted
var file: FileAccess
var last_draw_us := 0
var started_us := 0
var sample_started_us := 0
var duration := 0.0
var warmup := 3.0
var start_year := 0
var active := false
var updates := 0
var selection_us := 0
var publication_us := 0
var finished := false
var sampling := false
var detailed := true
var buffered := PackedStringArray()
var write_us := 0
var serialize_us := 0
var callbacks := 0
var max_interval_ms := 0.0
var interval_total_ms := 0.0
var buffer_limit := 200000
var overflow := false
var buffered_bytes := 0

func flush_buffer() -> void:
	if file==null: return
	var before := Time.get_ticks_usec()
	for line: String in buffered: file.store_line(line)
	buffered.clear()
	file.flush()
	write_us+=Time.get_ticks_usec()-before

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
	if kind in ["environment","processes","sample_begin","end"]:
		row["utc_unix_ms"]=Time.get_unix_time_from_system()*1000.0
		row["clock_ticks_us_after"]=Time.get_ticks_usec()
	var before := Time.get_ticks_usec()
	var encoded := JSON.stringify(row)
	serialize_us+=Time.get_ticks_usec()-before
	if sampling and not finished:
		if buffered.size()<buffer_limit and buffered_bytes+encoded.length()*4<=64*1024*1024:
			buffered.append(encoded)
			buffered_bytes+=encoded.length()*4
		else: overflow=true
		return
	flush_buffer()
	file.store_line(encoded)
	if kind in ["environment","processes","ready","begin","sample_begin","end","verified_pause","error"]: file.flush()

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
		# Flush preparation before starting the clock. The sample boundary itself is
		# buffered too, so no lifecycle flush is hidden inside the measured window.
		flush_buffer()
		serialize_us=0
		write_us=0
		sampling=true
		sample_started_us=Time.get_ticks_usec()
		last_draw_us=sample_started_us
		record("sample_begin",{"year":year})
		return false
	if elapsed>=warmup and last_draw_us>0:
		var interval := (now-last_draw_us)/1000.0
		callbacks+=1
		max_interval_ms=maxf(max_interval_ms,interval)
		interval_total_ms+=interval
		if detailed: record("frame",{"post_draw_interval_ms":interval,"year":year,"godot_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		if selection_us>0:
			record("selection_post_draw",{"ms":(now-selection_us)/1000.0})
			selection_us=0
		if publication_us>0:
			record("map_post_draw",{"ms":(now-publication_us)/1000.0,"year":year})
			publication_us=0
	selection_us=0
	publication_us=0
	last_draw_us=now
	if sampling and now-sample_started_us>=duration*1000000.0:
		finished=true
		record("end",{"year":year,"start_year":start_year,"elapsed_seconds":elapsed,"updates":updates,"post_draw_callbacks":callbacks,"post_draw_interval_total_ms":interval_total_ms,"post_draw_interval_max_ms":max_interval_ms,"profiler_serialize_us":serialize_us,"profiler_write_us_before_end":write_us,"buffer_overflow":overflow})
		file.flush()
		return true
	return false
