extends SceneTree
const App := preload("res://scripts/app/main.gd")
var source: BridgeSource
var application: Node
var phase := 0
var count := 0
var samples := 6
var seen_year := 0
var started := 0
var deadline := 0
var config := {"seed":"Asabiya","width":400,"height":200,"detail":4,"landFraction":0.33}
var use_app := false

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args := App.parse_args(OS.get_cmdline_user_args())
	config["width"] = int(args.get("width",400))
	config["height"] = int(args.get("height",200))
	samples = int(args.get("samples",6))
	use_app = args.has("app")
	deadline = Time.get_ticks_msec() + 120000
	if use_app:
		App.pending_world = config.duplicate()
		App.pending_source = {}
		application = App.new()
		root.add_child(application)
		source = application.source
		application._launch.launch.pressed.emit()
	else:
		source = BridgeSource.new(null, str(args.get("server","")))
		source.world_config = config
		if not source.start(): printerr(source.last_error); quit(1); return
	phase = 1

func _process(_dt: float) -> bool:
	if phase == 0: return false
	if not use_app: source.poll()
	if source.last_error != "":
		printerr("PIPELINE ERROR ", source.last_error)
		source.close();quit(1);phase=0;return false
	if Time.get_ticks_msec() > deadline:
		printerr("PIPELINE TIMEOUT");source.close();quit(1);phase=0;return false
	if phase == 1 and not source.years().is_empty() and not source.busy:
		seen_year = source.years()[-1]
		started = Time.get_ticks_usec()
		source.advance(1)
		phase = 2
	elif phase == 2 and not source.busy and source.years()[-1] > seen_year:
		count += 1
		seen_year = source.years()[-1]
		if count >= samples:
			phase = 0
			_finish()
		else: source.advance(1)
	return false

func _finish() -> void:
	var elapsed := Time.get_ticks_usec() - started
	var frame: HistoryFrame = source.frame(seen_year)
	print("PIPELINE ", JSON.stringify({"width":config["width"],"height":config["height"],"app":use_app,"years":count,"elapsedMs":elapsed/1000.0,"msPerYear":elapsed/1000.0/count,"yearsPerSecond":count*1000000.0/elapsed,"staticBytes":Performance.get_monitor(Performance.MEMORY_STATIC),"digest":frame.state_digest,"headless":DisplayServer.get_name()=="headless"}))
	await source.shutdown()
	if application != null: application.queue_free()
	await process_frame
	quit(0)
