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
var fast_mode := false
var initial_year := 0
var exact_digest := false
var columns_only := false
var checkpoint_digest := false
var map_layer := "terrain"

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args := App.parse_args(OS.get_cmdline_user_args())
	config["width"] = int(args.get("width",400))
	config["height"] = int(args.get("height",200))
	samples = int(args.get("samples",6))
	use_app = args.has("app")
	fast_mode = args.has("fast")
	exact_digest = args.has("exact")
	columns_only = args.has("columns")
	checkpoint_digest = args.has("checkpoints")
	map_layer = str(args.get("layer","terrain"))
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
		if use_app: application.set_layer(map_layer)
		if exact_digest: source._digest_checkpoints = false
		if checkpoint_digest: source._digest_checkpoints = true
		if columns_only: source.set("_field_changes",false)
		started = Time.get_ticks_usec()
		initial_year = seen_year
		if fast_mode: source.start_fast_forward(samples, 50)
		elif checkpoint_digest:
			source.frames_changed.connect(func():
				if source.years()[-1] >= initial_year + samples: source.stop_live())
			source.start_live(0)
		else: source.advance(1)
		phase = 2
	elif phase == 2 and not source.busy and source.years()[-1] > seen_year:
		count = source.years()[-1] - initial_year
		seen_year = source.years()[-1]
		if count >= samples:
			phase = 0
			_finish()
		elif not checkpoint_digest: source.advance(1)
	return false

func _finish() -> void:
	var elapsed := Time.get_ticks_usec() - started
	var frame: HistoryFrame = source.frame(seen_year)
	# Obtain a real SHA after the timed interval, including non-checkpoint years.
	var proof: Dictionary = {}
	source.request("get_replay",{},func(response:Dictionary): proof.assign(response.get("data",{})))
	var proof_deadline := Time.get_ticks_msec()+30000
	while proof.is_empty() and Time.get_ticks_msec()<proof_deadline and not source._stopped():
		if not use_app: source.poll()
		await process_frame
	if proof.is_empty() or proof.get("finalYear") != seen_year:
		printerr("PIPELINE ERROR final integrity query failed")
		source.close();quit(1);return
	print("PIPELINE ", JSON.stringify({"width":config["width"],"height":config["height"],"app":use_app,"layer":map_layer,"fast":fast_mode,"exact":exact_digest,"years":count,"elapsedMs":elapsed/1000.0,"msPerYear":elapsed/1000.0/count,"yearsPerSecond":count*1000000.0/elapsed,"staticBytes":Performance.get_monitor(Performance.MEMORY_STATIC),"digest":proof.get("finalSHA256"),"publicationDigest":frame.state_digest,"digestMode":frame.get("digest_mode") if frame.get("digest_mode") != null else "","headless":DisplayServer.get_name()=="headless"}))
	await source.shutdown()
	if application != null: application.queue_free()
	await process_frame
	quit(0)
