extends Node
## Entry point and controller. Loads an engine snapshot, chooses the history
## source (live Go bridge when present, otherwise the snapshot alone) and wires
## the 3D map and the observer UI. It never simulates anything itself.
##
## User args (after `--`):
##   --snapshot PATH     load an engine snapshot (.asw)
##   --seed TEXT         generate one with asabiya-snapshot(.exe) next to the app
##   --no-bridge         do not start the Go bridge even if it exists
##   --bridge PATH       bridge executable to use
##   --layer ID          initial map mode (see MapLayers.DEFS)
##   --capture PNG       render, save a screenshot and quit (tests/docs)
##   --frames N          frames to wait before capturing (default 45)
##   --view x,z,dist[,yaw_deg,tilt_deg]   initial camera
##   --select x,y        select a cell
##   --ui-scale F        override the automatic interface scale

static var pending_snapshot := ""

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
var requested_layer := "terrain"   # last mode the user asked for; restored when data arrives
var overlay_opacity := 0.85
var toggles := {"borders": true, "labels": true, "settlements": true, "events": true, "vegetation": true}
var selection := {"kind": "", "id": -1}
var settings := {"quality": 1, "relief": 1}
var _play_accum := 0.0

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_PX := [9.0, 12.0, 20.0]
const RELIEF_SCALE := [1.0 / 650.0, 1.0 / 420.0, 1.0 / 300.0]


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	_apply_ui_scale()
	var path := resolve_snapshot()
	if path == "":
		_fatal("No hay ningún mundo para abrir.\nColoca asabiya-snapshot.exe junto a la aplicación o usa --snapshot RUTA.")
		return
	world = WorldData.load_file(path)
	if world == null:
		_fatal("No se pudo abrir el mundo:\n%s" % path)
		return
	current_year = int(world.header.get("session", {}).get("year", -9000))
	_load_settings()
	_build_scene()
	_choose_source()
	if args.has("layer"):
		requested_layer = str(args["layer"])
		current_layer = requested_layer
	_on_frames_changed()
	_apply_initial_view()
	if args.has("capture"):
		_capture(str(args["capture"]))


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


func resolve_snapshot() -> String:
	if pending_snapshot != "":
		var p := pending_snapshot
		pending_snapshot = ""
		return p
	if args.has("snapshot"):
		return str(args["snapshot"])
	if args.has("seed"):
		var r := SnapshotLocator.generate(str(args["seed"]))
		if r.has("error"):
			push_error(r["error"])
		return r.get("path", "")
	return SnapshotLocator.find_default()


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
	get_window().content_scale_factor = clampf(s, 0.75, 3.0)


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
			source.advance(n))
	hud.play_toggled.connect(func(_on: bool): _play_accum = 0.0)
	hud.fly_to.connect(func(c: int): select_entity("cell", c, true))
	hud.entity_requested.connect(func(kind: String, id: int): select_entity(kind, id, true))
	hud.world_requested.connect(_generate_world)
	hud.deselect_requested.connect(_deselect)
	hud.setting_changed.connect(func(k: String, v: Variant):
		settings[k] = v
		_save_settings()
		_apply_settings(k == "relief"))
	_apply_settings(false)


func _choose_source() -> void:
	var bridge := BridgeSource.new(world, str(args.get("bridge", "")))
	if bridge.available and not args.has("no-bridge"):
		source = bridge
		bridge.frames_changed.connect(_on_frames_changed)
		bridge.status_changed.connect(func(t: String):
			hud.set_status(t)
			hud.set_session(source, world)
			_refresh_ui())
		if not bridge.start():
			hud.set_status(bridge.last_error)
	else:
		source = GeographySource.new(world)
	hud.set_session(source, world)


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
	var ys := source.years()
	if not ys.is_empty() and not ys.has(current_year):
		current_year = ys[ys.size() - 1]
	_load_frame()


func set_year(y: int) -> void:
	current_year = y
	_load_frame()


func _load_frame() -> void:
	current_frame = source.frame_at(current_year) if source != null else null
	if current_frame != null:
		current_year = current_frame.year
	current_layer = requested_layer if MapLayers.available(requested_layer, source, current_frame) else "terrain"
	settlements.set_settlements(current_frame.settlements if current_frame != null else [])
	var label_mode := "states"
	if current_layer in ["peoples", "cultures", "languages"]:
		label_mode = "peoples"
	elif current_layer == "religions":
		label_mode = "religions"
	history.rebuild(current_frame, label_mode)
	hud.set_chronicle(_collect_events())
	_apply_layer()
	_refresh_ui()
	if selection["kind"] != "":
		select_entity(selection["kind"], selection["id"], false)


func _collect_events() -> Array:
	var out := []
	for y in source.years():
		if y > current_year:
			break
		var f := source.frame(y)
		if f != null:
			for e in f.events:
				out.append(e)
	return out


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
	map_view.terrain.set_overlay(r["colors"], r["keys"])
	hud.set_legend(MapLayers.def(current_layer).get("name", ""), r["legend"])
	_apply_layer_style()


func _apply_layer_style() -> void:
	_update_zoom_style(map_view.camera.zoom_level())


func _update_zoom_style(z: float) -> void:
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


func _process(dt: float) -> void:
	if source is BridgeSource:
		(source as BridgeSource).poll()
	if hud != null and hud.playing():
		_play_accum += dt * hud.speed()
		if _play_accum >= 1.0:
			_play_accum = 0.0
			var ys := source.years()
			var idx := ys.bsearch(current_year)
			if idx + 1 < ys.size():
				set_year(ys[idx + 1])
			elif source.can_advance():
				source.advance(10)
			elif not (source is BridgeSource and (source as BridgeSource).busy):
				hud.stop_playing()


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
	selection = {"kind": kind, "id": id}
	match kind:
		"cell":
			map_view.select_cell(id, -2.0)
			if fly:
				map_view.camera.focus_on(world.cell_center(id), minf(map_view.camera.distance, 60.0))
			_show_cell(id)
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
			var a := c.x / world.fine_width * TAU
			sx += sin(a)
			cx += cos(a)
			z += c.y
			n += 1
	if n == 0:
		return
	var x := fposmod(atan2(sx, cx) / TAU * world.fine_width, world.fine_width)
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
	var sections := [["Geografía (motor)", geo]]
	if land:
		sections.append(["Recursos y aptitudes (motor)", [
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
				pol.append(["Estado", func(): select_entity("state", sid, true), str(f.states[s].get("name", "#%d" % s))])
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
				pol.append(["Pueblo predominante", func(): select_entity("people", pid, true), str(f.peoples[e].get("name", "#%d" % e))])
			else:
				pol.append(["Pueblo predominante", "Deshabitada"])
		else:
			pol.append(["Pueblo predominante", null, _need("peoples")])
		if f != null and f.has_layer("religion"):
			var r := f.religion[c]
			pol.append(["Religión", str(f.religions[r].get("name", "#%d" % r)) if r >= 0 and f.religions.has(r) else "Ninguna"])
		else:
			pol.append(["Religión", null, _need("religions")])
		pol.append(["Población", Hud._fmt_int(f.population[c]) if f != null and f.has_layer("population") else null, _need("population")])
		pol.append(["Capacidad de carga", Hud._fmt_int(f.carrying[c]) if f != null and f.has_layer("carrying") else null, _need("carrying")])
		pol.append(["Tecnología", ("%d %%" % int(f.technology[c] * 100.0)) if f != null and f.has_layer("technology") else null, _need("technology")])
		sections.append(["Historia y sociedad", pol])
		var here := []
		if f != null:
			for s2 in f.settlements:
				if int(s2["cell"]) == c:
					var sid2 := int(s2["id"])
					here.append([SettlementLayer.TIER_NAMES[SettlementLayer.tier_of(s2)], func(): select_entity("settlement", sid2, true), str(s2.get("name", "#%d" % sid2))])
		if here.is_empty():
			here.append(["Asentamientos", null if f == null or not source.has_system("settlements") else "Ninguno", _need("settlements")])
		here.append(["Infraestructura", null, _need("infrastructure")])
		here.append(["Construcciones", null, _need("buildings")])
		here.append(["Historia territorial", null, _need("cellHistory")])
		sections.append(["Ocupación", here])
	hud.show_info(title, sub, sections)


func _show_settlement(s: Dictionary) -> void:
	var tier := SettlementLayer.tier_of(s)
	var f := current_frame
	var rows := [
		["Categoría", SettlementLayer.TIER_NAMES[tier]],
		["Población", Hud._fmt_int(float(s["population"])) if s.has("population") else null, "el motor no la envía"],
		["Fundación", Hud.fmt_year(int(s["founded"])) if s.has("founded") else null, "el motor no la envía"],
	]
	var st := int(s.get("state", -1))
	if st >= 0 and f != null and f.states.has(st):
		rows.append(["Estado", func(): select_entity("state", st, true), str(f.states[st].get("name", ""))])
	var cell := int(s["cell"])
	rows.append(["Provincia", func(): select_entity("cell", cell, true), "%d,%d" % [world.cell_xy(cell).x, world.cell_xy(cell).y]])
	var feats := []
	var fd := SettlementLayer.features(s)
	for k in fd:
		if fd[k]:
			feats.append({"walls": "Murallas", "castle": "Fortaleza", "temple": "Templo", "port": "Puerto", "market": "Mercado"}.get(k, str(k)))
	rows.append(["Construcciones", ", ".join(feats) if not feats.is_empty() else "Ninguna registrada"])
	hud.show_info(str(s.get("name", "Asentamiento")), "Asentamiento del motor · %s" % Hud.fmt_year(current_year), [["Asentamiento", rows],
		["Representación", [UiTheme.muted("La disposición interna de edificios es una representación visual; la existencia, tamaño y construcciones vienen del motor.", 11)]]])


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
		["Cultura", p.get("cultureName"), "el motor no la envía"],
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
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed and k.keycode == KEY_F:
		hud.focus_search()
	elif k.ctrl_pressed and k.keycode == KEY_Q:
		get_tree().quit()
	elif k.keycode == KEY_F1:
		hud.help_panel.visible = not hud.help_panel.visible
	elif k.keycode == KEY_ESCAPE:
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
	hud.set_status("Generando «%s» con el motor…" % seed_text)
	await get_tree().process_frame
	var r := SnapshotLocator.generate(seed_text)
	if r.has("error"):
		hud.set_status(str(r["error"]))
		return
	pending_snapshot = r["path"]
	if source != null:
		source.close()
	get_tree().reload_current_scene()


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
	var layer := CanvasLayer.new()
	add_child(layer)
	var p := PanelContainer.new()
	p.theme = UiTheme.build()
	p.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(p)
	var l := Label.new()
	l.text = msg
	p.add_child(l)
