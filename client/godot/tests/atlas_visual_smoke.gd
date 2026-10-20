extends SceneTree
## Remote software-render smoke: real Go initialization, no annual campaign.
const App := preload("res://scripts/app/main.gd")
var app: Node
var output := ""

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	output = ProjectSettings.globalize_path("res://../../build/atlas-preview")
	DirAccess.make_dir_recursive_absolute(output)
	App.pending_world = {"seed":"Asabiya","width":48,"height":24,"detail":4,"landFraction":0.33}
	App.pending_source = {}
	app = App.new()
	root.add_child(app)
	await _settle(2)
	await _capture("01-launch.png")
	app._launch.launch.pressed.emit()
	var deadline := Time.get_ticks_msec() + 60000
	while app.current_frame == null and Time.get_ticks_msec() < deadline:
		if app.source.last_error != "":
			printerr("Startup failed: ", app.source.last_error)
			app.source.close()
			quit(1)
			return
		await process_frame
	if app.current_frame == null:
		printerr("Startup publication timed out")
		app.source.close()
		quit(1)
		return
	print("REAL STARTUP world=", app.world.width, "x", app.world.height, " year=", app.current_frame.year, " generation=", app.source._session)
	var cell: int = app.world.land_cells[app.world.land_cells.size() / 2]
	app.select_entity("cell", cell, false)
	app.focus_selection()
	app.map_view.camera._snap()
	app.map_view.camera.moved.emit()
	await _settle(3)
	await _capture("02-province.png")
	app.map_view.camera.set_scale_view(1)
	app.set_layer("states")
	app.map_view.camera._snap()
	app.map_view.camera.moved.emit()
	await _settle(3)
	await _capture("03-regional.png")
	app.hud._toggle_maps(true)
	await _settle(2)
	await _capture("04-map-dock.png")
	app.hud.focus_search()
	app.hud.search_edit.text = "%d,%d" % [app.world.cell_xy(cell).x, app.world.cell_xy(cell).y]
	app.hud._on_search(app.hud.search_edit.text)
	await _settle(2)
	await _capture("05-search.png")
	var engine_pid: int = app.source._pid
	await app.source.shutdown()
	print("SERVER CLOSED ", not OS.is_process_running(engine_pid))
	app.queue_free()
	await process_frame
	print("Atlas software-render startup smoke passed; no annual advance requested; not a GPU benchmark")
	quit(0)

func _settle(count: int) -> void:
	for i in count: await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture == null:
		printerr("No rendered image")
		quit(1)
		return
	var status := picture.save_png(output.path_join(name))
	if status != OK:
		printerr("Capture failed ", status)
		quit(1)
	print("CAPTURE ", name, " ", picture.get_size())
