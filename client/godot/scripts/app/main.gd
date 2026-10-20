extends Node
## Starts the local Go server and wires its immutable publications to the
## existing 3D map and observer UI. It never simulates anything itself.
##
## User args (after `--`):
##   --snapshot PATH     load an engine snapshot (.asw)
##   --seed TEXT         world seed for the owned local Go server
##   --no-bridge         do not start the Go bridge even if it exists
##   --server PATH       local Go server executable to use
##   --world-source PATH Earth/import/climate source configuration
##   --layer ID          initial map mode (see MapLayers.DEFS)
##   --capture PNG       render, save a screenshot and quit (tests/docs)
##   --frames N          frames to wait before capturing (default 45)
##   --view x,z,dist[,yaw_deg,tilt_deg]   initial camera
##   --select x,y        select a cell
##   --ui-scale F        override the automatic interface scale

static var pending_world: Dictionary = {}
static var pending_source: Dictionary = {}

var _annual_trace := AnnualTrace.new("main")

var _launch: LaunchScreen
var _last_session_error := ""
var _startup: CanvasLayer
var _loading_label: Label
var _retry_button: Button
var _following_live := true
var _quitting := false
var _province_details: Dictionary = {}
var _province_history: Array = []
var _entity_query_key := ""
var _entity_details: Dictionary = {}

var args := {}
var world: WorldData
var map_view: MapView
var vegetation: VegetationLayer
var settlements: SettlementLayer
var history: HistoryOverlay
var hud: Hud
var source: HistorySource
var current_frame: HistoryFrame
var current_year := -9000
var current_layer := "terrain"
var _applied_layer := ""
var requested_layer := "terrain"   # last mode the user asked for; restored when data arrives
var overlay_opacity := 0.85
var toggles := {"borders": true, "labels": true, "settlements": true, "events": true, "vegetation": true}
var selection := {"kind": "", "id": -1}
var settings := {"quality": 1, "relief": 1}

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_PX := [9.0, 12.0, 20.0]
const RELIEF_SCALE := [1.0 / 650.0, 1.0 / 420.0, 1.0 / 300.0]


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	_apply_ui_scale()
	get_window().size_changed.connect(_apply_ui_scale)
	_load_settings()
	get_tree().auto_accept_quit = false
	if args.has("snapshot"):
		world = WorldData.load_file(str(args["snapshot"]))
		if world == null:
			_fatal("No se pudo abrir la geografía indicada.")
			return
	if args.has("no-bridge"):
		if world == null:
			_fatal("--no-bridge requiere --snapshot para abrir una geografía existente.")
			return
		source = GeographySource.new(world)
		_accept_world(world)
		return
	var bridge := BridgeSource.new(world, str(args.get("server", args.get("bridge", ""))))
	source = bridge
	if world == null:
		var defaults_path := OS.get_executable_path().get_base_dir().path_join("asabiya.json")
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(defaults_path)) if FileAccess.file_exists(defaults_path) else {}
		if config is Dictionary:
			bridge.world_config.merge(config.get("world", {}), true)
			bridge.history_seed = str(config.get("historySeed", "1"))
			bridge.source_config = config.get("source", {})
		var resuming_pending := not pending_world.is_empty()
		if resuming_pending:
			bridge.world_config = pending_world.duplicate(true)
			bridge.source_config = pending_source.duplicate(true)
			pending_world.clear(); pending_source.clear()
		if args.has("seed") and not resuming_pending: bridge.world_config["seed"] = str(args["seed"])
		if args.has("history-seed"): bridge.history_seed = str(args["history-seed"])
		if args.has("world-source") and not resuming_pending:
			var source_path: String = args["world-source"]
			var config_source: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
			if not config_source is Dictionary:
				_fatal("El archivo de configuración del mundo no es JSON válido.")
				return
			bridge.source_config = config_source
			for asset: Dictionary in bridge.source_config.get("assets", []):
				if not str(asset.get("path", "")).is_absolute_path():
					asset["path"] = source_path.get_base_dir().path_join(str(asset["path"]))
		for asset: Dictionary in bridge.source_config.get("assets", []):
			if not str(asset.get("path", "")).is_absolute_path():
				asset["path"] = OS.get_executable_path().get_base_dir().path_join(str(asset["path"]))
	_show_loading("Explora continentes, pueblos y ciudades. La historia comienza cuando tú decidas.")
	if world != null:
		_launch.seed_edit.editable = false
		_launch.launch.text = "Explorar la geografía cargada"
	bridge.world_ready.connect(_accept_world)
	bridge.frames_changed.connect(_on_frames_changed)
	bridge.status_changed.connect(func(text: String) -> void:
		if hud != null:
			hud.set_status(text)
			hud.set_session(source, world)
			_refresh_ui()
		elif _loading_label != null:
			_loading_label.text = text
			if _launch != null: _launch.update_message(text, bridge.last_error != ""))
	bridge.request_failed.connect(func(op: String, code: String, message: String):
		if hud != null: hud.show_request_error(op, code, message))
	_launch.session_requested.connect(func(seed_text: String):
		if world == null: bridge.world_config["seed"] = seed_text
		if not bridge.start(): _launch.update_message(bridge.last_error, true))
	if args.has("capture") or args.has("autostart"):
		_launch.show_progress("Iniciando Asabiya Native…")
		if not bridge.start(): _launch.update_message(bridge.last_error, true)


func _show_loading(text: String) -> void:
	_startup = CanvasLayer.new()
	add_child(_startup)
	_launch = LaunchScreen.new()
	_startup.add_child(_launch)
	var seed_text := "Asabiya"
	if source is BridgeSource: seed_text = str((source as BridgeSource).world_config.get("seed", seed_text))
	_launch.build(seed_text)
	_launch.message.text = text
	_launch.retry_requested.connect(func():
		if source != null: source.close()
		get_tree().reload_current_scene())
	_launch.quit_requested.connect(_request_close)
	_loading_label = _launch.message
	_retry_button = _launch.retry


func _accept_world(value: WorldData) -> void:
	world = value
	if _startup != null:
		_startup.queue_free()
		_startup = null
		_launch = null
		_loading_label = null
		_retry_button = null
	current_year = int(world.header.get("session", {}).get("year", -9000))
	_build_scene()
	hud.set_session(source, world)
	if args.has("layer"):
		requested_layer = str(args["layer"])
	_on_frames_changed()
	_apply_initial_view()
	if args.has("capture"): _capture(str(args["capture"]))


# ---------------------------------------------------------------- setup

static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var a := raw[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				out[key] = raw[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out


func _apply_ui_scale() -> void:
	var s := 1.0
	if args.has("ui-scale"):
		s = float(args["ui-scale"])
	elif DisplayServer.get_name() != "headless":
		var screen := DisplayServer.window_get_current_screen()
		s = DisplayServer.screen_get_scale(screen)
		if OS.get_name() == "Windows":
			s = DisplayServer.screen_get_dpi(screen) / 96.0
		var h := DisplayServer.screen_get_size(screen).y
		if s <= 1.01 and h >= 2000:
			s = 1.5
	var physical := Vector2(get_window().size)
	var fitting := minf(physical.x / 1000.0, physical.y / 640.0)
	var factor := clampf(minf(s, fitting), 0.75, 3.0)
	if not is_equal_approx(get_window().content_scale_factor, factor):
		get_window().content_scale_factor = factor


func _build_scene() -> void:
	map_view = MapView.new()
	map_view.name = "Map"
	add_child(map_view)
	map_view.setup(world)
	vegetation = VegetationLayer.new()
	vegetation.name = "Vegetation"
	map_view.add_child(vegetation)
	vegetation.setup_veg(world, map_view.mm)
	settlements = SettlementLayer.new()
	settlements.name = "Settlements"
	map_view.add_child(settlements)
	settlements.setup_settlements(world, map_view.mm)
	settlements.layout_changed.connect(func(): vegetation.set_clearings(settlements.clearings()))
	history = HistoryOverlay.new()
	history.name = "History"
	map_view.add_child(history)
	history.setup(world, map_view.mm)
	map_view.view_listeners.append(func(cam: Camera3D, z: float):
		vegetation.update_view(cam)
		settlements.update_view(cam)
		history.update_view(cam, z)
		_update_zoom_style(z))
	map_view.pick_handlers.append(func(screen: Vector2) -> Dictionary:
		if not settlements.visible:
			return {}
		var id := settlements.pick(map_view.camera, screen)
		return {"kind": "settlement", "id": id} if id >= 0 else {})
	map_view.cell_hovered.connect(_on_cell_hovered)
	map_view.cell_clicked.connect(func(c: int):
		if c < 0:
			_deselect()
		else:
			select_entity("cell", c, false))
	map_view.entity_clicked.connect(func(kind: String, id: int): select_entity(kind, id, false))
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	hud = Hud.new()
	hud.name = "Hud"
	layer.add_child(hud)
	hud.build(self)
	hud.layer_selected.connect(set_layer)
	hud.opacity_changed.connect(func(v: float):
		overlay_opacity = v
		_apply_layer_style())
	hud.toggle_changed.connect(_on_toggle)
	hud.year_requested.connect(set_year)
	hud.advance_requested.connect(func(n: int):
		if source.can_advance():
			hud.stop_playing()
			_following_live = true
			source.advance(n))
	hud.play_toggled.connect(func(on: bool):
		if source is BridgeSource:
			if on:
				_following_live = true
				(source as BridgeSource).start_live(hud.speed())
			else:
				(source as BridgeSource).pause())
	hud.fast_forward_requested.connect(func(years_count: int, interval: int):
		if source is BridgeSource:
			_following_live = true
			(source as BridgeSource).start_fast_forward(years_count, interval))
	if source is BridgeSource:
		(source as BridgeSource).progress_changed.connect(func(calculated: int, visualized: int, remaining: int):
			hud.set_annual_progress(calculated, current_year, remaining)
			_annual_trace.record("annual-progress", 0, {"calculatedYear":calculated,"visualizedYear":visualized,"remaining":remaining}))
	hud.playback_rate_changed.connect(func(rate: int):
		if source is BridgeSource: (source as BridgeSource).set_live_rate(rate))
	hud.fly_to.connect(func(c: int): select_entity("cell", c, true))
	hud.entity_requested.connect(func(kind: String, id: int): select_entity(kind, id, false))
	hud.world_requested.connect(_generate_world)
	hud.deselect_requested.connect(_deselect)
	hud.setting_changed.connect(func(k: String, v: Variant):
		settings[k] = v
		_save_settings()
		_apply_settings(k == "relief"))
	_apply_settings(false)


func _apply_initial_view() -> void:
	if args.has("view"):
		var v: PackedStringArray = str(args["view"]).split(",")
		map_view.camera.focus_on(Vector2(v[0].to_float(), v[1].to_float()), v[2].to_float(), true)
		if v.size() > 3:
			map_view.camera._goal_yaw = deg_to_rad(v[3].to_float())
		if v.size() > 4:
			map_view.camera._goal_tilt = v[4].to_float()
		map_view.camera._snap()
	if args.has("select"):
		var s: PackedStringArray = str(args["select"]).split(",")
		select_entity("cell", world.cell_id(s[0].to_int(), s[1].to_int()), false)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cfg.get_value("view", k, settings[k])


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("view", k, settings[k])
	cfg.save(SETTINGS_PATH)


func _apply_settings(relief_changed: bool) -> void:
	var q := clampi(int(settings["quality"]), 0, 2)
	var r := clampi(int(settings["relief"]), 0, 2)
	map_view.terrain.target_pixels_per_quad = QUALITY_PX[q]
	map_view.sun.directional_shadow_mode = [DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS][q]
	map_view.env.environment.ssao_enabled = q < 2
	vegetation.visibility_end = [110.0, 95.0, 60.0][q]
	map_view.mm.land_scale = RELIEF_SCALE[r]
	map_view.terrain.apply_params()
	hud.set_menu_checks(q, r)
	if relief_changed:
		# objects sit on the surface: re-place them for the new exaggeration
		vegetation.clear()
		settlements._cache.clear()
		settlements.set_settlements(current_frame.settlements if current_frame != null else [])
		history.rebuild(current_frame, history.label_mode)


# ---------------------------------------------------------------- frames & layers

func _on_frames_changed() -> void:
	if hud == null: return
	var ys := source.years()
	if not ys.is_empty() and (_following_live or not ys.has(current_year)):
		current_year = ys[ys.size() - 1]
	_load_frame()


func set_year(y: int) -> void:
	if hud.playing():
		hud.stop_playing()
		if source is BridgeSource: (source as BridgeSource).pause()
	_following_live = false
	current_year = y
	_load_frame()


func _load_frame() -> void:
	var frame_started := _annual_trace.begin()
	var next_frame: HistoryFrame = source.frame_at(current_year) if source != null else null
	if current_frame != null and next_frame != null and current_frame.year == next_frame.year and current_frame.state_digest == next_frame.state_digest:
		var refresh_start := _annual_trace.begin()
		_refresh_ui()
		_annual_trace.record("hud", refresh_start)
		if not hud.playing() and selection.get("kind") == "cell":
			_request_province_details(int(selection["id"]))
		return
	current_frame = next_frame
	if current_frame != null:
		current_year = current_frame.year
	current_layer = requested_layer if MapLayers.available(requested_layer, source, current_frame) else "terrain"
	var settlements_start := _annual_trace.begin()
	settlements.set_settlements(current_frame.settlements if current_frame != null else [])
	_annual_trace.record("settlements", settlements_start)
	var label_mode := "states"
	if current_layer in ["peoples", "cultures", "languages"]:
		label_mode = "peoples"
	elif current_layer == "religions":
		label_mode = "religions"
	var annotations_start := _annual_trace.begin()
	history.rebuild(current_frame, label_mode)
	_annual_trace.record("annotations", annotations_start)
	var chronicle_start := _annual_trace.begin()
	hud.set_chronicle(_collect_events())
	_annual_trace.record("chronicle", chronicle_start)
	if _applied_layer != current_layer or MapLayers.def(current_layer).get("requires", "") != "":
		var layers_start := _annual_trace.begin()
		_apply_layer()
		_annual_trace.record("layers", layers_start)
	var hud_start := _annual_trace.begin()
	_refresh_ui()
	_annual_trace.record("hud", hud_start)
	if selection["kind"] != "":
		select_entity(selection["kind"], selection["id"], false)
	_annual_trace.record("frame-applied", frame_started, {"year":current_year})


func _collect_events() -> Array:
	# Every publication includes the retained event window. Do not repeat it
	# once per cached frame.
	return current_frame.events if current_frame != null else []


func set_layer(id: String) -> void:
	if not MapLayers.available(id, source, current_frame):
		hud.set_status("Ese mapa requiere datos que el motor Go aún no envía.")
		_refresh_ui()
		return
	current_layer = id
	requested_layer = id
	var label_mode := "peoples" if id in ["peoples", "cultures", "languages"] else ("religions" if id == "religions" else "states")
	if label_mode != history.label_mode:
		history.rebuild(current_frame, label_mode)
	_apply_layer()
	_refresh_ui()


func _apply_layer() -> void:
	var r := MapLayers.build(current_layer, world, current_frame)
	_applied_layer = current_layer
	map_view.terrain.set_overlay(r["colors"], r["keys"])
	hud.set_legend(MapLayers.def(current_layer).get("name", ""), r["legend"])
	_apply_layer_style()


func _apply_layer_style() -> void:
	_update_zoom_style(map_view.camera.zoom_level())


func _update_zoom_style(z: float) -> void:
	if hud != null: hud.set_view_scale(z, map_view.camera.yaw)
	var d := MapLayers.def(current_layer)
	var op := 0.0 if current_layer in ["terrain", "provinces"] else overlay_opacity
	var prov := 0.0
	if toggles["borders"]:
		prov = 1.0 - smoothstep(0.38, 0.62, z)
	if current_layer == "provinces":
		prov = maxf(prov, 1.0 - smoothstep(0.75, 0.95, z))
	map_view.terrain.set_overlay_style(op, float(d.get("borders", 0.0)), prov)


func _refresh_ui() -> void:
	hud.refresh_layers(source, current_frame, current_layer)
	hud.refresh_timeline(source, current_year)
	hud.set_frame_stats(current_frame, current_year)


func _on_toggle(key: String, on: bool) -> void:
	toggles[key] = on
	match key:
		"vegetation":
			vegetation.set_enabled(on)
		"settlements":
			settlements.visible = on
		"labels":
			history.show_labels = on
			history.rebuild(current_frame, history.label_mode)
		"events":
			history.show_events = on
			history.rebuild(current_frame, history.label_mode)
	_apply_layer_style()


func _process(_dt: float) -> void:
	if source is BridgeSource:
		(source as BridgeSource).poll()
		if hud != null and hud.playing() and not (source as BridgeSource).is_live():
			hud.stop_playing()
		var bridge := source as BridgeSource
		if hud != null and not bridge.connected and bridge.last_error != "" and _last_session_error != bridge.last_error:
			_last_session_error = bridge.last_error
			hud.show_session_error(bridge.last_error)


# ---------------------------------------------------------------- selection & panels

func _on_cell_hovered(c: int) -> void:
	if c < 0:
		hud.set_hover("")
		return
	var p := world.cell_xy(c)
	var t := "%d,%d · %s" % [p.x, p.y, world.biome_name(c) if world.is_land(c) else "Mar"]
	if world.is_land(c):
		t += " · %d m" % int(world.elevation[c])
	if current_frame != null and current_frame.has_layer("owner"):
		var s := current_frame.owner[c]
		if s >= 0 and current_frame.states.has(s):
			t += "\n" + str(current_frame.states[s].get("name", ""))
	hud.set_hover(t)


func _deselect() -> void:
	selection = {"kind": "", "id": -1}
	map_view.select_cell(-1, -2.0)
	hud.hide_info()


func select_entity(kind: String, id: int, fly: bool) -> void:
	if kind == "cell" and (id < 0 or id >= world.cell_count()): return
	hud.remember_selection(kind, id)
	selection = {"kind": kind, "id": id}
	if kind.begins_with("engine:"):
		_show_engine_entity(kind.trim_prefix("engine:"), id)
		return
	match kind:
		"cell":
			map_view.select_cell(id, -2.0)
			if fly:
				map_view.camera.focus_on(world.cell_center(id), minf(map_view.camera.distance, 18.0))
			_province_details.clear()
			_province_history.clear()
			_show_cell(id)
			_request_province_details(id)
		"settlement":
			var s := current_frame.settlement_by_id(id) if current_frame != null else {}
			if s.is_empty():
				_deselect()
				return
			map_view.select_cell(int(s["cell"]), -2.0)
			if fly:
				map_view.camera.focus_on(world.cell_center(int(s["cell"])), 14.0)
			_show_settlement(s)
		"state":
			if current_frame == null or not current_frame.states.has(id):
				_deselect()
				return
			map_view.select_cell(-1, float(id) if current_layer in ["states", "wars"] else -2.0)
			if fly:
				_fly_to_group(current_frame.owner, id)
			_show_state(id)
		"people":
			if current_frame == null or not current_frame.peoples.has(id):
				_deselect()
				return
			map_view.select_cell(-1, float(id) if current_layer == "peoples" else -2.0)
			if fly:
				_fly_to_group(current_frame.people, id)
			_show_people(id)


func _fly_to_group(ids: PackedInt32Array, g: int) -> void:
	var sx := 0.0
	var cx := 0.0
	var z := 0.0
	var n := 0
	for i in world.land_cells:
		if ids[i] == g:
			var c := world.cell_center(i)
			var a := c.x / map_view.mm.map_w * TAU
			sx += sin(a)
			cx += cos(a)
			z += c.y
			n += 1
	if n == 0:
		return
	var x := fposmod(atan2(sx, cx) / TAU * map_view.mm.map_w, map_view.mm.map_w)
	map_view.camera.focus_on(Vector2(x, z / n), clampf(sqrt(n) * 9.0, 60.0, 600.0))


func _need(system: String) -> String:
	return "requiere «%s» del motor Go" % system


func _show_cell(c: int) -> void:
	var p := world.cell_xy(c)
	var land := world.is_land(c)
	var f := current_frame
	var title := "Provincia %d,%d" % [p.x, p.y] if land else "Mar %d,%d" % [p.x, p.y]
	var sub := "%.1f° %s · %.1f° %s · celda %d" % [absf(world.latitude_deg(c)), "N" if world.latitude_deg(c) >= 0 else "S", absf(world.longitude_deg(c)), "E" if world.longitude_deg(c) >= 0 else "O", c]
	var geo := [
		["Bioma", world.biome_name(c)],
		["Altitud", "%d m" % int(world.elevation[c])],
		["Temperatura media", "%.1f °C" % world.temperature[c]],
		["Amplitud estacional", "%.1f °C" % world.amplitude[c]],
		["Precipitación", "%d mm/año" % int(world.precipitation[c])],
		["Área", "%s km²" % Hud._fmt_int(world.area[c])],
	]
	if land:
		geo.append(["Masa de tierra", "#%d" % world.landmass[c]])
		geo.append(["Costa", "Sí" if world.coast[c] == 1 else "No"])
		geo.append(["Rugosidad", "%.2f" % world.roughness[c]])
		var rv := world.river[c]
		geo.append(["Río", ("Sí, fuerza %.2f" % rv) if rv >= 0.2 else "No"])
		var d := world.down[c]
		if d >= 0:
			var dp := world.cell_xy(d)
			geo.append(["Drena hacia", "%d,%d%s" % [dp.x, dp.y, " (mar)" if not world.is_land(d) else ""]])
	var sections := [["Geografía", geo]]
	if land:
		sections.append(["Territorio", [
			["Aptitud agrícola", "%.2f" % world.farming[c]],
			["Aptitud pastoral", "%.2f" % world.herding[c]],
			["Nómada", "Sí" if world.nomad[c] == 1 else "No"],
			["Estación de cultivo", "%.1f meses" % world.growing_season[c]],
			["Bosque inicial", "%d %%" % int(world.forest0[c] * 100.0)],
			["Coste de viaje", str(world.travel_cost[c])],
			["Malaria", "%.2f" % world.malaria[c]],
			["Monzón", "%.2f" % world.monsoon[c]],
			["Desierto", "Sí" if world.desert[c] == 1 else "No"],
		]])
		var pol := []
		var ruler = null
		if f != null and f.has_layer("owner"):
			var s := f.owner[c]
			if s >= 0 and f.states.has(s):
				var sid := s
				pol.append(["Estado", func(): select_entity("state", sid, false), str(f.states[s].get("name", "#%d" % s))])
				ruler = f.states[s].get("ruler")
				pol.append(["Autoridad", ruler if ruler != null else null, "el motor no envía gobernante"])
			else:
				pol.append(["Estado", "Sin Estado"])
		else:
			pol.append(["Estado", null, _need("states")])
			pol.append(["Autoridad", null, _need("states")])
		if f != null and f.has_layer("people"):
			var e := f.people[c]
			if e >= 0 and f.peoples.has(e):
				var pid := e
				pol.append(["Pueblo predominante", func(): select_entity("people", pid, false), str(f.peoples[e].get("name", "#%d" % e))])
			else:
				pol.append(["Pueblo predominante", "Deshabitada"])
		else:
			pol.append(["Pueblo predominante", null, _need("peoples")])
		if f != null and f.has_layer("religion"):
			var r := f.religion[c]
			if r >= 0 and f.religions.has(r):
				var rid := r
				pol.append(["Religión", func(): select_entity("engine:religion", rid, false), str(f.religions[r].get("name", "#%d" % r))])
			else: pol.append(["Religión", "Ninguna"])
		else:
			pol.append(["Religión", null, _need("religions")])
		pol.append(["Población", Hud._fmt_int(f.population[c]) if f != null and f.has_layer("population") else null, _need("population")])
		pol.append(["Capacidad de carga", Hud._fmt_int(f.carrying[c]) if f != null and f.has_layer("carrying") else null, _need("carrying")])
		pol.append(["Era tecnológica", hud.era_name(int(round(f.technology[c] * 7.0))) if f != null and f.has_layer("technology") else null, _need("technology")])
		sections.push_front(["Historia y sociedad", pol])
		var here := []
		if f != null:
			for s2 in f.settlements:
				if int(s2["cell"]) == c:
					var sid2 := int(s2["id"])
					here.append([SettlementLayer.TIER_NAMES[SettlementLayer.tier_of(s2)], func(): select_entity("settlement", sid2, false), str(s2.get("name", "#%d" % sid2))])
		if here.is_empty():
			here.append(["Asentamientos", null if f == null or not source.has_system("settlements") else "Ninguno", _need("settlements")])
		here.append(["Infraestructura", null, _need("infrastructure")])
		here.append(["Construcciones", null, _need("buildings")])
		here.append(["Historia territorial", "Observaciones cada diez años" if source.has_system("cellHistory") else null, _need("cellHistory")])
		sections.append(["Ocupación", here])
	if land and int(_province_details.get("year", -999999)) == current_year and int(_province_details.get("id", -1)) == c:
		var details: Dictionary = _province_details.get("data", {})
		var rows := []
		for spec in [["fortification","Fortificación"],["integration","Integración"],["cohesion","Cohesión"],["forest","Cobertura forestal"],["fertility","Fertilidad"],["salinity","Salinidad"],["malariaAdaptation","Adaptación a malaria"],["immunity","Inmunidad"],["infection","Infección"],["caravanActivity","Actividad de caravanas"]]:
			var number: Variant = details.get(spec[0])
			if number is int or number is float: rows.append([spec[1], "%.2f" % float(number)])
		sections.append(["Sociedad y entorno", rows])
		var technologies := []
		var levels: Array = details.get("technology", [])
		for k in levels.size():
			var name := "Técnica %d" % k
			if source is BridgeSource and k < (source as BridgeSource).tech_catalog.size():
				name = str((source as BridgeSource).tech_catalog[k].get("name", name))
			technologies.append([name, "%.1f %%" % (float(levels[k]) * 100.0)])
		sections.append(["Tecnologías", technologies])
	if not _province_history.is_empty():
		var changes := []
		for item: Dictionary in _province_history:
			if int(item.get("year", 0)) <= current_year:
				changes.append([Hud.fmt_year(int(item["year"])), "Estado #%d" % int(item["ownerPolityId"])])
		sections.append(["Propiedad observada cada 10 años", changes])
	hud.show_info(title, sub, sections)


func _show_settlement(s: Dictionary) -> void:
	var tier := SettlementLayer.tier_of(s)
	var f := current_frame
	var rows := [
		["Categoría", SettlementLayer.TIER_NAMES[tier]],
		["Población provincial", Hud._fmt_int(float(s["population"])) if s.has("population") else null, "el motor no la envía"],
		["Fundación", Hud.fmt_year(int(s["founded"])) if s.has("founded") else null, "el motor no la envía"],
	]
	var st := int(s.get("state", -1))
	if st >= 0 and f != null and f.states.has(st):
		rows.append(["Estado", func(): select_entity("state", st, false), str(f.states[st].get("name", ""))])
	var cell := int(s["cell"])
	rows.append(["Provincia", func(): select_entity("cell", cell, false), "%d,%d" % [world.cell_xy(cell).x, world.cell_xy(cell).y]])
	var feats := []
	var fd := SettlementLayer.features(s)
	for k in fd:
		if fd[k]:
			feats.append({"walls": "Murallas", "castle": "Fortaleza", "temple": "Templo", "port": "Puerto", "market": "Mercado"}.get(k, str(k)))
	rows.append(["Elementos de presentación", ", ".join(feats) if not feats.is_empty() else "Sin elementos destacados"])
	hud.show_info(str(s.get("name", "Asentamiento")), "Asentamiento del motor · %s" % Hud.fmt_year(current_year), [["Asentamiento", rows],
		["Representación", [UiTheme.muted("La disposición interna de edificios es una representación visual; la ciudad existe en Go; el tamaño visual usa población provincial y las murallas son un proxy de fortificación. No son entidades nuevas de edificios.", 11)]]])


func _show_state(id: int) -> void:
	var f := current_frame
	var s: Dictionary = f.states[id]
	var cells := 0
	var area := 0.0
	var pop := 0.0
	for i in world.land_cells:
		if f.owner[i] == id:
			cells += 1
			area += world.area[i]
			if f.has_layer("population"):
				pop += f.population[i]
	var rows := [
		["Territorio", "%d provincias · %s km²" % [cells, Hud._fmt_int(area)]],
		["Capital", s.get("capitalName", s.get("capital")), "el motor no la envía"],
		["Gobernante", s.get("ruler"), "el motor no lo envía"],
		["Dinastía", s.get("dynasty"), "el motor no la envía"],
		["Población", Hud._fmt_int(pop) if f.has_layer("population") else s.get("population"), _need("population")],
		["Cohesión", ("%.2f" % float(s["cohesion"])) if s.has("cohesion") else null, "el motor no la envía"],
		["Fundación", Hud.fmt_year(int(s["founded"])) if s.has("founded") else null, "el motor no la envía"],
	]
	rows.append(["Detalles históricos", func(): select_entity("engine:polity", id, false), "Ver detalles"])
	var ruler_id := int(s.get("rulerId", -1))
	if ruler_id >= 0:
		rows[2] = ["Gobernante", func(): select_entity("engine:ruler", ruler_id, false), str(s.get("ruler", "#%d" % ruler_id))]
	var hist := []
	for h in s.get("history", []):
		hist.append(UiTheme.muted("• " + str(h), 12))
	if hist.is_empty():
		hist.append(UiTheme.muted("El motor no ha enviado historia política para este Estado.", 12))
	hud.show_info(str(s.get("name", "Estado")), "Estado · %s" % Hud.fmt_year(current_year), [["Estado", rows], ["Historia política", hist]])


func _show_people(id: int) -> void:
	var f := current_frame
	var p: Dictionary = f.peoples[id]
	var cells := 0
	for i in world.land_cells:
		if f.people[i] == id:
			cells += 1
	var rows := [
		["Lengua", p.get("language"), "el motor no la envía"],
		["Familia", p.get("familyName", p.get("family")), "el motor no la envía"],
		["Vector cultural (6 componentes)", p.get("culture"), "el motor no lo envía"],
		["Tierra natal", p.get("homeland"), "el motor no la envía"],
		["Territorio", "%d provincias" % cells],
	]
	# demographic evolution across the frames received so far
	var evo := []
	for y in source.years():
		var fr := source.frame(y)
		if fr == null or not fr.has_layer("people") or not fr.has_layer("population"):
			continue
		var tot := 0.0
		for i in world.land_cells:
			if fr.people[i] == id:
				tot += fr.population[i]
		evo.append(UiTheme.muted("%s: %s" % [Hud.fmt_year(y), Hud._fmt_int(tot)], 12))
	if evo.is_empty():
		evo.append(UiTheme.muted("No disponible todavía: %s." % _need("population"), 12))
	hud.show_info(str(p.get("name", "Pueblo")), "Pueblo · %s" % Hud.fmt_year(current_year), [["Identidad", rows], ["Evolución demográfica", evo]])


# ---------------------------------------------------------------- input & misc

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if hud == null: return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit: return
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		if not hud.sim_buttons["play"].disabled: hud.sim_buttons["play"].pressed.emit()
	elif k.alt_pressed and k.keycode in [KEY_LEFT, KEY_RIGHT]:
		hud._navigate(-1 if k.keycode == KEY_LEFT else 1)
	elif k.ctrl_pressed and k.keycode == KEY_F:
		hud.focus_search()
	elif k.ctrl_pressed and k.keycode == KEY_Q:
		_request_close()
	elif k.keycode == KEY_F1:
		hud.help_panel.visible = not hud.help_panel.visible
	elif k.keycode == KEY_ESCAPE:
		if hud.dismiss_popovers(): return
		if hud.help_panel.visible:
			hud.help_panel.visible = false
		else:
			_deselect()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_9 and not k.ctrl_pressed:
		var quick := ["terrain", "states", "peoples", "religions", "population", "biomes", "elevation", "temperature", "farming"]
		set_layer(quick[k.keycode - KEY_1])
	else:
		return
	get_viewport().set_input_as_handled()


func _generate_world(seed_text: String) -> void:
	hud.set_status("Cerrando la sesión anterior y generando «%s»…" % seed_text)
	if source is BridgeSource:
		var bridge := source as BridgeSource
		pending_world = bridge.world_config.duplicate(true)
		pending_world["seed"] = seed_text
		pending_source = bridge.source_config.duplicate(true)
		await bridge.shutdown()
	else:
		pending_world = {"seed":seed_text,"width":400,"height":200,"detail":4,"landFraction":0.33}
		if source != null: source.close()
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _request_close()


func _request_close() -> void:
	if _quitting: return
	_quitting = true
	if source is BridgeSource: await (source as BridgeSource).shutdown()
	get_tree().quit()


func _exit_tree() -> void:
	if source != null:
		source.close()


func _capture(path: String) -> void:
	var frames := int(args.get("frames", "45"))
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURE ", path, " ", img.get_size(), " tris=", map_view.terrain.stats["triangles"], " veg=", vegetation.instance_count())
	get_tree().quit()


func _fatal(msg: String) -> void:
	push_error(msg)
	if _startup == null: _show_loading(msg)
	_launch.launch.hide()
	_launch.seed_edit.hide()
	_launch.update_message(msg, true)


func _request_province_details(id: int) -> void:
	if not source is BridgeSource or not (source as BridgeSource).connected or (source as BridgeSource).busy: return
	if (source as BridgeSource).is_live(): return
	var expected_year := current_year
	var latest := source.years()
	if latest.is_empty() or latest[latest.size() - 1] != expected_year: return
	(source as BridgeSource).query_province(id, func(response: Dictionary) -> void:
		if current_year != expected_year or selection != {"kind":"cell","id":id}: return
		if int(response.get("year", -999999)) != expected_year: return
		_province_details = {"year":expected_year,"id":id,"data":response.get("data", {})}
		_show_cell(id))
	(source as BridgeSource).query_history(id, func(response: Dictionary) -> void:
		if current_year != expected_year or selection != {"kind":"cell","id":id}: return
		if int(response.get("year", -999999)) != expected_year: return
		var records: Variant = response.get("data", {}).get("records", [])
		_province_history = records if records is Array else []
		_show_cell(id))


func _show_engine_entity(kind_name: String, id: int) -> void:
	if current_frame == null: return
	var value: Dictionary = current_frame.entity_records.get(kind_name, {}).get(id, {})
	if kind_name == "event":
		for item: Dictionary in current_frame.events:
			if int(item.get("id", -1)) == id:
				value = item
				break
	var query_key := "%s:%d:%d" % [kind_name, id, current_year]
	if kind_name != "event" and source is BridgeSource and (source as BridgeSource).connected and not (source as BridgeSource).busy and not (source as BridgeSource).is_live():
		var ys := source.years()
		if not ys.is_empty() and ys[ys.size() - 1] == current_year and _entity_query_key != query_key:
			_entity_query_key = query_key
			var expected_year := current_year
			(source as BridgeSource).query_entity(kind_name, id, func(response: Dictionary) -> void:
				if selection != {"kind":"engine:" + kind_name,"id":id} or current_year != expected_year: return
				if int(response.get("year", -999999)) != expected_year: return
				_entity_details = {"key":query_key,"fields":response.get("data", {}).get("fields", {})}
				_show_engine_entity(kind_name, id))
	if _entity_details.get("key", "") == query_key: value = _entity_details.get("fields", {})
	if value.is_empty():
		hud.set_status("No hay datos de esa entidad en la publicación seleccionada.")
		return
	var names := {"polity":"Estado","people":"Pueblo","ruler":"Gobernante","figure":"Figura histórica","city":"Asentamiento","religion":"Religión","war":"Guerra","route":"Ruta comercial","migration":"Migración","outbreak":"Epidemia","omen":"Presagio","cataclysm":"Cataclismo","event":"Acontecimiento"}
	var label: String = names.get(kind_name, "Historia")
	var sections := _entity_sections(kind_name, value)
	hud.show_info(str(value.get("name", "%s #%d" % [label, id])),
		"%s · %s" % [label, Hud.fmt_year(current_year)], sections)


func _entity_sections(kind_name: String, value: Dictionary) -> Array:
	# Human-facing facts and relationships; never expose a dump of transport
	# fields or long JSON arrays in the observer's inspector.
	var common := [["born","Fundación","year"],["alive","Activa","bool"]]
	var layouts := {
		"polity":common + [["cellsAtLastCensus","Provincias del último censo","count"],["peakCells","Extensión máxima","count"],["dynastyLabel","Dinastía","text"]],
		"people":common + [["languageStyle","Lengua","text"],["populationAtLastCensus","Población del último censo","count"],["cellsAtLastCensus","Provincias del último censo","count"]],
		"ruler":[["born","Nacimiento","year"],["since","Gobierna desde","year"],["competence","Competencia","number"],["charisma","Carisma","number"],["piety","Piedad","number"],["aggression","Agresividad","number"],["conquests","Conquistas","count"]],
		"figure":[["title","Título","text"],["born","Nacimiento","year"],["conquests","Conquistas","count"],["works","Obras","count"]],
		"city":[["born","Fundación","year"],["population","Población provincial","count"],["holy","Lugar sagrado","bool"]],
		"religion":common + [["populationAtLastCensus","Población del último censo","count"],["cellsAtLastCensus","Provincias del último censo","count"],["centralization","Centralización","number"]],
		"war":[["start","Inicio","year"],["active","Activa","bool"],["civil","Guerra civil","bool"],["holy","Guerra religiosa","bool"],["gainsAttackers","Ganancias atacantes","count"],["gainsDefenders","Ganancias defensores","count"]],
		"route":[["born","Apertura","year"],["last","Última actividad","year"],["active","Activa","bool"]],
		"migration":[["start","Inicio","year"],["population","Población","count"],["done","Concluida","bool"]],
		"outbreak":[["start","Inicio","year"],["deaths","Muertes","count"],["done","Concluida","bool"]],
		"omen":[["year","Año","year"],["place","Lugar","text"],["radiusKM","Radio (km)","number"]],
		"cataclysm":[["year","Año","year"],["place","Lugar","text"],["deaths","Muertes","count"],["radiusKM","Radio (km)","number"]],
		"event":[["year","Año","year"]]
	}
	var rows := []
	for spec: Array in layouts.get(kind_name, common):
		var field: Variant = value.get(spec[0])
		if field == null: continue
		var text := str(field)
		match spec[2]:
			"year": text = Hud.fmt_year(int(field))
			"bool": text = "Sí" if field else "No"
			"count": text = Hud._fmt_int(float(field))
			"number": text = "%.2f" % float(field)
		rows.append([spec[1], text])
	if kind_name == "war" and not value.get("active", false) and value.has("end"):
		rows.append(["Final", Hud.fmt_year(int(value["end"]))])
	var relations := [
		["capitalId","Capital","cell"],["cellId","Provincia","cell"],
		["originCellId","Origen","cell"],["holyCellId","Lugar sagrado","cell"],
		["fromCellId","Origen","cell"],["toCellId","Destino","cell"],
		["rulerId","Gobernante","ruler"],["peopleId","Pueblo","people"],
		["religionId","Religión","religion"],["ownerPolityId","Estado","polity"],
		["polityId","Estado","polity"],["founderFigureId","Fundador","figure"],
		["attackers","Atacante","polity"],["defenders","Defensor","polity"]
	]
	for relation: Array in relations:
		var raw: Variant = value.get(relation[0])
		if raw == null: continue
		var ids: Array = raw if raw is Array else [raw]
		for target_id: Variant in ids:
			if not (target_id is int or target_id is float): continue
			var ident := int(target_id)
			var target_kind: String = relation[2]
			if ident < 0 or (target_kind == "polity" and ident == 0): continue
			var entity_name := "#%d" % ident
			if target_kind == "cell":
				if ident >= world.cell_count(): continue
				var xy := world.cell_xy(ident)
				entity_name = "%d, %d" % [xy.x, xy.y]
			else:
				entity_name = str(current_frame.entity_records.get(target_kind, {}).get(ident, {}).get("name", entity_name))
			rows.append([relation[1], func(): select_entity("cell" if target_kind == "cell" else "engine:" + target_kind, ident, false), entity_name])
	var sections := [["Información", rows]]
	for spec in [["text","Crónica"],["why","Contexto"],["outcome","Resultado"],["followText","Consecuencias"]]:
		if value.get(spec[0]) is String and value[spec[0]] != "":
			sections.append([spec[1], [UiTheme.muted(str(value[spec[0]]), 14)]])
	return sections

## Explicit locate action, separate from opening linked entity sheets.
func focus_selection() -> void:
	var kind := str(selection.get("kind", ""))
	var id := int(selection.get("id", -1))
	if kind == "": return
	if kind == "cell":
		map_view.camera.focus_on(world.cell_center(id), 16.0)
	elif kind == "settlement" and current_frame != null:
		var place := current_frame.settlement_by_id(id)
		if not place.is_empty(): map_view.camera.focus_on(world.cell_center(int(place["cell"])), 14.0)
	elif kind == "state" and current_frame != null: _fly_to_group(current_frame.owner, id)
	elif kind == "people" and current_frame != null: _fly_to_group(current_frame.people, id)
	elif kind.begins_with("engine:") and current_frame != null:
		var record: Dictionary = current_frame.entity_records.get(kind.trim_prefix("engine:"), {}).get(id, {})
		var cell := int(record.get("cellId", record.get("capitalId", -1)))
		if cell >= 0 and cell < world.cell_count(): map_view.camera.focus_on(world.cell_center(cell), 16.0)
		elif kind == "engine:religion": _fly_to_group(current_frame.religion, id)
		elif kind == "engine:polity": _fly_to_group(current_frame.owner, id)
		elif kind == "engine:people": _fly_to_group(current_frame.people, id)
		else: hud.set_status("Esta entidad no tiene una localización geográfica disponible.")
