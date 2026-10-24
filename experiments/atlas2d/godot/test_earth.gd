extends SceneTree
## Real Earth, bounded camera, provincial identity, and Go-only publications.
var app: Control
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func require(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func until(condition: Callable, label: String, seconds := 90.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline: await process_frame
	var success: bool=condition.call()
	require(success,"Timeout: "+label)
	return success

func idle() -> bool:
	return app.current!=null and not app.source.busy and app.worker==null and app.queue.is_empty()

func _run() -> void:
	OS.low_processor_usage_mode=false
	app=load("res://atlas.tscn").instantiate()
	root.add_child(app)
	if not await until(idle,"Earth publication"):
		finish()
		return
	require(app.earth_mode,"Earth is the default")
	var w: WorldData=app.world
	require(w.width==400 and w.height==200 and w.has_fine,"400x200 Go cells and real fine relief")
	require(w.header.source.kind=="imported","Earth geometry does not activate legacy historical placements")
	var map: AtlasMap=app.map
	var original_size := map.size
	for viewport: Vector2 in [Vector2(800,600),Vector2(1500,400),Vector2(300,900)]:
		map.size=viewport
		map.zoom_to(1)
		require(w.width*map.target_zoom<=viewport.x+0.01 and w.height*map.target_zoom<=viewport.y+0.01,"Entire world fits "+str(viewport))
		map.target_zoom=0.001
		map.target_center=Vector2(-99999,99999)
		map._clamp_camera()
		require(is_equal_approx(map.target_zoom,map.zoom_base()),"Zoom cannot expose multiple worlds")
		map.zoom_to(4)
		map.target_center=Vector2(-99999,99999)
		map._clamp_camera()
		require(map.target_center.x>=0 and map.target_center.x<=w.width and map.target_center.y>=0 and map.target_center.y<=w.height,"Pan stays within Earth")
	map.size=Vector2(900,600)
	map.zoom_to(1)
	map.center=map.target_center
	map.zoom=map.target_zoom
	require(map.select_at(Vector2(0,0))==-1,"Letterbox cannot select a province")
	require(AtlasProjection.pick(w,Vector2(-0.1,100))==-1 and AtlasProjection.pick(w,Vector2(400,100))==-1,"No horizontal picking copies")
	map.size=original_size
	var cell := 0
	# Germany: recognizable land, using the same lat/lon transform as Go.
	var point := Vector2((10.0+180.0)/360.0*w.width,(90.0-48.0)/180.0*w.height)
	cell=AtlasProjection.pick(w,point)
	require(cell>=0 and w.is_land(cell),"Europe picks a Go land province")
	app._selected(cell)
	await until(func(): return app.inspector.get_parsed_text().contains("Consulta Go"),"Province query")
	var reply := {}
	app.source.request("get_province",{"id":cell},func(value: Dictionary): reply.merge(value))
	await until(func(): return not reply.is_empty(),"Independent province answer")
	require(int(reply.get("year",0))==app.current.year,"Province and publication share the year")
	require(is_equal_approx(float(reply.get("data",{}).get("population",-1)),app.current.population[cell]),"Province population is Go's publication")
	var first_year: int=app.current.year
	app._step()
	await until(func(): return idle() and app.current.year==first_year+1,"One complete Earth year")
	require(app.current.state_digest!="","Year carries its real SHA")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--earth-evidence="):
			var directory := argument.trim_prefix("--earth-evidence=")
			require(DisplayServer.get_name()!="headless","Screenshots require real rendering")
			if DisplayServer.get_name()=="headless": continue
			DirAccess.make_dir_recursive_absolute(directory)
			map.zoom_to(1)
			await until(func(): return map.center.distance_to(map.target_center)<0.001 and absf(map.zoom-map.target_zoom)<0.001,"World camera settles")
			await RenderingServer.frame_post_draw
			require(root.get_texture().get_image().save_png(directory.path_join("Tierra-mundial.png"))==OK,"World screenshot saved")
			map.selected=cell
			map.zoom_to(4)
			await until(func(): return map.center.distance_to(map.target_center)<0.001 and absf(map.zoom-map.target_zoom)<0.001,"Regional camera settles")
			await RenderingServer.frame_post_draw
			require(root.get_texture().get_image().save_png(directory.path_join("Tierra-regional.png"))==OK,"Regional screenshot saved")
	print("EARTH: %d checks, %d failures" % [checks,failures])
	finish()

func finish() -> void:
	if app!=null and app.source!=null: app.source.close()
	quit(0 if failures==0 else 1)
