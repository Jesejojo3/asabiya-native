extends SceneTree
var app: Control
var expected: Dictionary
var server := ""
var failures := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): server=arg.trim_prefix("--server=")
		if arg.begins_with("--expected="): expected=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--expected=")))
	_run.call_deferred()

func require(value: bool, message: String) -> void:
	if not value:
		failures+=1
		push_error(message)

func until(condition: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+20000
	while not condition.call() and Time.get_ticks_msec()<deadline: await process_frame
	var success: bool=condition.call()
	require(success,"Timeout: "+label)
	return success

func _run() -> void:
	app=load("res://atlas.tscn").instantiate()
	# Disable _ready's auto-init only through normal command-line options:
	# --server=... --small are also supplied by the runner.
	root.add_child(app)
	if not await until(func(): return app.current!=null,"initial Go publication"):
		app._close(1)
		return
	var first: HistoryFrame=app.current
	var initial_pop := first.population.duplicate()
	var w: WorldData=app.world
	var id: int=w.land_cells[w.land_cells.size()/2]
	var at := Vector2(id%w.width,floori(float(id)/w.width))+Vector2(0.5,0.5)
	require(AtlasProjection.pick(w,at)==AtlasProjection.pick(w,at+Vector2(w.width,0)),"Horizontal wrapping changed ID")
	require(AtlasProjection.pick(w,Vector2(0,-0.1))==-1,"Polar outside area must not select a province")
	for cell in w.land_cells:
		var point := Vector2(cell%w.width,floori(float(cell)/w.width))+Vector2(0.5,0.5)
		require(AtlasProjection.pick(w,point)==cell,"Land cell IDs must remain Go IDs")
	app.source.frames_changed.connect(func():
		if app.source.years()[-1]>=first.year+3 and app.playing: app._pause())
	app.playing=true
	app.speed.selected=3
	if not await until(func(): return app.current.year==first.year+3 and not app.source.busy and app.worker==null and app.queue.is_empty(),"three annual frames and exact pause"):
		app._close(1)
		return
	require(app.current.state_digest==expected.get("stateSHA256"),"Godot observer changed authoritative Go digest")
	require(app.current.year==int(expected.get("year")),"Calendar diverged")
	require(first.population==initial_pop,"Worker mutated an earlier publication")
	require(app.source.years().size()==4,"Playback omitted an annual publication")
	var response := {}
	app.source.query_province(id,func(value: Dictionary): response.merge(value))
	if await until(func(): return not response.is_empty(),"province query"):
		var data: Dictionary=response.data
		require(int(data.id)==id,"Query province ID mismatch")
		require(int(response.year)==app.current.year,"Panel and map represent different years")
		require(int(data.ownerPolityId)==app.current.owner[id],"Political layer owner differs from Go query")
		require(is_equal_approx(float(data.population),app.current.population[id]),"Panel population differs from Go query")
	app.desired_layer="population"
	app.queue.append(app.current)
	if await until(func(): return app.shown_layer=="population" and app.worker==null,"additional real layer"):
		var image: Image=app.map.shader.get_shader_parameter("overlay").get_image()
		var wanted: Dictionary=MapLayers.build("population",w,app.current)
		require(image.get_data()==wanted.colors,"Uploaded thematic texture differs from engine projection")
	app._selected(id)
	require(app.inspector.text.contains("#%d"%id),"Selected ID absent from panel")
	app.review_year=first.year
	app.queue.append(first)
	if await until(func(): return app.current.year==first.year,"historical observation"):
		require(app.current.population==initial_pop,"Review changed old population")
		require(app.source.years()[-1]==first.year+3,"Review rewound causal Go state")
	print("ATLAS TESTS: %d failures · exact Go SHA %s" % [failures,expected.get("stateSHA256")])
	app._close(1 if failures>0 else 0)
