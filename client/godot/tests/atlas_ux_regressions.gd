extends SceneTree
## Headless presentation contracts; no graphical or historical validation.
var checks := 0
var failures := 0

class ObserverStub extends Node:
	var world := WorldData.new()
	var current_frame := HistoryFrame.new()
	var current_year := -100
	var selection := {"kind":"", "id":-1}
	var source := BridgeSource.new()
	var picked: Array = []
	var located := 0
	func select_entity(kind: String, id: int, _fly: bool) -> void:
		selection = {"kind":kind, "id":id}
		picked.append(selection)
	func focus_selection() -> void: located += 1
	func _request_close() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var observer := ObserverStub.new()
	root.add_child(observer)
	observer.world.width = 4
	observer.world.height = 3
	observer.world.world_seed = "UX fixture"
	observer.current_frame.year = -100
	observer.current_frame.states = {7:{"name":"Estado de prueba"}}
	observer.current_frame.peoples = {9:{"name":"Pueblo de prueba"}}
	observer.current_frame.religions = {11:{"name":"Religión de prueba"}}
	observer.current_frame.settlements = [{"id":13,"cell":1,"name":"Ciudad de prueba"}]
	observer.source.connected = true
	var hud := Hud.new()
	root.add_child(hud)
	hud.build(observer)
	hud.set_session(observer.source, observer.world)
	hud.set_frame_stats(observer.current_frame, -100)
	await process_frame
	check(hud.top_year.text == Hud.fmt_year(-100), "engine year is formatted")
	check(hud.top_stats["states"].text == "1", "real state count")
	check(hud.speed() == 10, "previous live pacing default preserved")
	var original_eras := ["Foraging","Neolithic","Bronze Age","Iron Age","Classical","Medieval","Gunpowder age","Age of Sail"]
	for i in original_eras.size():
		check(Hud.fmt_era(i) == original_eras[i], "HTML era name " + str(i))
	check(Hud.fmt_era(-1) == "No disponible" and Hud.fmt_era(8) == "No disponible", "unknown era does not masquerade as a known era")
	observer.source.era_names = ["Nombre enviado por Go"]
	check(hud.era_name(0) == "Nombre enviado por Go", "server era catalog is authoritative")
	check(hud.era_name(7) == "Age of Sail", "partial catalog uses verified HTML fallback")
	observer.source.era_names = ["", null]
	check(hud.era_name(0) == "Foraging" and hud.era_name(1) == "Neolithic", "blank and invalid catalog labels use HTML fallback")
	observer.source.era_names = original_eras

	for icon in ["atlas","search","chronicle","home","focus","back","forward","close","play","pause","step","menu","people","state","city"]:
		check(AtlasIcons.get_icon(icon) != null, "original icon " + icon)
	check(AtlasIcons.get_icon("search") == AtlasIcons.get_icon("search"), "icon texture cached")
	var sections := [["Sociedad", [["Estado", func(): observer.select_entity("state", 7, false), "Estado de prueba"], ["Población", "12 000"]]], ["Geografía", [["Bioma", "Pradera"]]]]
	hud.show_info("Provincia 1,0", "Año observado", sections)
	var original := hud.info_body.get_child(0).get_instance_id()
	hud.show_info("Provincia 1,0", "Año observado", sections)
	check(hud.info_body.get_child(0).get_instance_id() == original, "unchanged inspector is not rebuilt")
	observer.selection = {"kind":"cell","id":2}
	hud.show_info("Provincia 1,0", "Año observado", sections)
	check(hud.info_body.get_child(0).get_instance_id() != original, "different entity IDs rebind relation callbacks even with identical text")
	check(hud._section_tabs.tab_count == 2, "context sections become tabs")
	hud._section_tabs.current_tab = 1
	check(not hud._section_nodes[0].visible and hud._section_nodes[1].visible, "section tab changes visible facts")
	hud.show_info("Provincia 1,0", "Año observado", [["Sociedad", [["Población", "12 001"]]], ["Geografía", [["Bioma", "Pradera"]]]])
	check(hud._section_tabs.current_tab == 1, "detail refresh preserves selected section")
	hud.remember_selection("cell", 1)
	hud.remember_selection("state", 7)
	hud.remember_selection("state", 7)
	check(hud._nav.size() == 2, "duplicate selection not added")
	hud._navigate(-1)
	check(observer.selection == {"kind":"cell","id":1}, "back restores contextual entity")
	hud._navigate(1)
	check(observer.selection == {"kind":"state","id":7}, "forward restores contextual entity")
	hud._navigate(-1)
	hud.remember_selection("people", 9)
	check(hud._nav.size() == 2 and hud._nav[1]["kind"] == "people", "new branch truncates forward history")
	for i in 50: hud.remember_selection("cell", i)
	check(hud._nav.size() == 32, "navigation memory bounded")
	hud._on_search("prueba")
	check(hud.search_results.item_count == 4, "states peoples religions and cities searchable")
	hud._on_search("religión")
	check(hud._search_targets == [["engine:religion",11]], "religion search uses engine entity")
	hud._on_search_pick(0)
	check(observer.selection == {"kind":"engine:religion","id":11}, "search opens entity without moving camera")
	var historical_kinds := ["figure","ruler","war","migration","route","outbreak","omen","cataclysm","polity","people"]
	for i in historical_kinds.size():
		var records := {}
		records[100 + i] = {"name":"Archivo histórico %d" % i, "title":"Astrónoma" if i == 0 else "", "alive":false}
		observer.current_frame.entity_records[historical_kinds[i]] = records
	hud._on_search("archivo histórico")
	check(hud._search_targets.size() == historical_kinds.size(), "all HTML historic inspector kinds are discoverable")
	for i in historical_kinds.size():
		check(hud._search_targets.has(["engine:" + historical_kinds[i], 100 + i]),
			"search navigates archived " + historical_kinds[i])
	hud._on_search("astrónoma")
	check(hud._search_targets == [["engine:figure",100]], "figure titles are searchable as in HTML v0.6")
	observer.current_frame.entity_records["omen"][200] = {"type":"kindle", "year":-100, "cellId":1}
	observer.current_frame.entity_records["route"][201] = {"born":-120, "fromCellId":1,"toCellId":2}
	hud._on_search("presagio kindle")
	check(hud._search_targets == [["engine:omen",200]], "unnamed native omen is searchable by actual type")
	hud._on_search("ruta comercial #201")
	check(hud._search_targets == [["engine:route",201]], "unnamed native trade route is searchable by ID")
	hud._on_search("archivo histórico")
	hud._on_search_pick(0)
	check(observer.selection == {"kind":"engine:figure","id":100}, "figure search opens a Go-backed record")
	observer.current_frame.entity_records["figure"] = {
		41:{"name":"Gobernante antiguo","title":"Rey","kind":"ruler","born":-300,"conquests":2,"realmCells":10,"deeds":[["conquista"]],"works":0},
		42:{"name":"Profeta recordada","title":"Reformadora","kind":"prophet","born":-500,"conquests":0,"realmCells":0,"deeds":[["obra"],["viaje"]],"works":1}
	}
	var figure_intents := []
	hud.entity_requested.connect(func(kind: String, id: int): figure_intents.append([kind, id]))
	hud._toggle_figures(true)
	check(hud.figures_panel.visible and hud.figure_list.item_count == 2, "figures catalogue opens from Atlas UX")
	check(int(hud.figure_list.get_item_metadata(0)) == 42, "HTML figure score prioritizes greater renown")
	hud.figure_filter.select(1)
	hud._fill_figures()
	check(hud.figure_list.item_count == 1 and int(hud.figure_list.get_item_metadata(0)) == 41, "ruler category matches HTML")
	hud.figure_filter.select(0)
	hud.figure_query.text = "reformadora"
	hud._fill_figures() # assigning LineEdit.text in a test does not emit text_changed
	check(hud.figure_list.item_count == 1 and int(hud.figure_list.get_item_metadata(0)) == 42, "figure titles are filtered")
	hud.figure_query.text = ""
	hud._fill_figures()
	hud._on_figure_activated(0)
	check(not hud.figures_panel.visible and figure_intents == [["engine:figure",42]], "figure index opens Go entity via intent")
	check(observer.source._outgoing.is_empty(), "figure browser does not mutate causal engine")
	# Historical disaster archive is computed from the published Go records only.
	observer.current_frame.entity_records["cataclysm"] = {
		5:{"name":"Gran temblor", "year":-120, "deaths":1000, "cellId":2},
		8:{"name":"Gran inundación", "year":-130, "deaths":5000, "cellId":1},
		9:{"name":"Cataclismo futuro", "year":-90, "deaths":9000, "cellId":3}
	}
	observer.current_frame.entity_records["outbreak"] = {
		3:{"name":"Fiebre antigua", "start":-130, "deaths":200000, "originCellId":1, "done":true},
		4:{"name":"Peste grave", "start":-120, "deaths":900000, "originCellId":2, "done":true},
		12:{"name":"Fiebre reciente", "start":-110, "deaths":100000, "originCellId":999, "done":false}
	}
	var map_focus_intents := []
	hud.focus_cell.connect(func(cell: int): map_focus_intents.append(cell))
	hud._toggle_disasters(true)
	check(hud.disasters_panel.visible and hud.cataclysm_list.item_count == 2,
		"historical disasters panel filters records after selected year")
	check(int(hud.cataclysm_list.get_item_metadata(0)["id"]) == 5,
		"cataclysms are sorted latest first")
	check(hud.outbreak_list.item_count == 3 and int(hud.outbreak_list.get_item_metadata(0)["id"]) == 4,
		"epidemic archive defaults to deadliest first")
	hud.disaster_sort.select(1)
	hud._fill_disasters()
	check(int(hud.outbreak_list.get_item_metadata(0)["id"]) == 12,
		"epidemic archive supports recent-first sort")
	hud.disaster_query.text = "antigua"
	hud._fill_disasters()
	check(hud.outbreak_list.item_count == 1 and int(hud.outbreak_list.get_item_metadata(0)["id"]) == 3,
		"epidemic archive supports native name search")
	hud.disaster_query.text = ""
	hud._fill_disasters()
	var previous_intents := figure_intents.size()
	hud._on_disaster_activated(hud.cataclysm_list, 0)
	check(not hud.disasters_panel.visible and map_focus_intents == [2],
		"cataclysm atlas action focuses Go's origin cell without selecting the province")
	check(figure_intents.size() == previous_intents + 1 and figure_intents[-1] == ["engine:cataclysm",5],
		"cataclysm atlas action opens native record inspector")
	hud._toggle_disasters(true)
	previous_intents = figure_intents.size()
	hud._on_disaster_activated(hud.outbreak_list, 0)
	check(map_focus_intents.size() == 1 and figure_intents.size() == previous_intents + 1
		and figure_intents[-1] == ["engine:outbreak",12],
		"invalid epidemic cell is not used for camera focus; record still opens")
	check(observer.source._outgoing.is_empty(),
		"disaster archive is a read-only projection of Go publications")
	# Fiches must show real Go fields without interpreting them as new mechanics.
	var app_script: Script = load("res://scripts/app/main.gd")
	var inspector: Variant = app_script.new()
	inspector.world = observer.world
	inspector.current_frame = observer.current_frame
	var people_sections: Array = inspector._entity_sections("people", {
		"languageStyle":"Celtic", "lexicon":["root","rio","dios","sol","mar","monte","madre","grano"],
		"soundChanges":["t>d"], "parentId":9, "children":[9, 8]
	})
	var found_river := false
	var found_parent := false
	for row: Array in people_sections[0][1]:
		if row[0] == "Río" and row[1] == "rio": found_river = true
		if row[0] == "Pueblo ancestral" and row[1] is Callable: found_parent = true
	check(found_river and found_parent, "people sheet exposes language lexicon and navigable ancestry")
	var faith_sections: Array = inspector._entity_sections("religion", {
		"parentId":11, "children":[12], "stateIds":[7], "missionary":0.5, "councils":2
	})
	var found_schism := false
	for row: Array in faith_sections[0][1]:
		if row[0] == "Cismas y ramas" and row[1] is Callable: found_schism = true
	check(found_schism, "faith sheet shows native schism descendants as links")
	var polity_sections: Array = inspector._entity_sections("polity", {
		"rulerId":10, "allies":[7], "warIds":[4], "metrics":{"cohesion":0.7,"treasury":25.0}
	})
	var found_allies := false
	for row: Array in polity_sections[0][1]:
		if row[0] == "Aliados" and row[1] is Callable: found_allies = true
	check(found_allies, "state sheet shows political ties without calculating alliances in Godot")
	var figure_sections: Array = inspector._entity_sections("figure", {
		"name":"Astrónoma", "deeds":[{"Year":-92,"Text":"Registró las estrellas"},{"Year":-86,"Text":"Enseñó navegación"}]
	})
	check(figure_sections.size() == 2 and figure_sections[1][0] == "Hazañas"
		and figure_sections[1][1].size() == 2
		and str(figure_sections[1][1][0][1]) == "Registró las estrellas",
		"figure sheet shows Go deeds as chronological records")
	inspector.free()
	var many_figures := {}
	for i in 100:
		many_figures[1000 + i] = {"name":"Muchos exploradores %d" % i}
	observer.current_frame.entity_records["figure"] = many_figures
	hud._on_search("muchos exploradores")
	check(hud.search_results.item_count == 40 and hud._search_targets.size() == 40,
		"search results stay bounded despite large figure archives")
	hud._on_search("1,2")
	check(hud._search_targets == [["cell",9]], "coordinate search")
	hud._on_search("unknown")
	check(hud._search_targets.is_empty(), "empty search has no actionable synthetic results")
	var intents := []
	hud.play_toggled.connect(func(on: bool): intents.append(["play",on]))
	hud.advance_requested.connect(func(years: int): intents.append(["advance",years]))
	hud.playback_rate_changed.connect(func(rate: int): intents.append(["rate",rate]))
	hud.sim_buttons["play"].pressed.emit()
	hud.sim_buttons["play"].pressed.emit()
	hud.sim_buttons["advance"].pressed.emit()
	hud.speed_option.select(6)
	hud.speed_option.item_selected.emit(6)
	check(intents == [["play",true],["play",false],["advance",1],["rate",0]], "transport preserves pause, single year and maximum-rate intents")
	check(observer.source._outgoing.is_empty(), "presentation emits intents without calculating years")
	observer.source._years = PackedInt32Array([-100])
	observer.source._frames[-100] = observer.current_frame
	observer.source.busy = true
	hud.refresh_timeline(observer.source, -100)
	check(hud.timeline_label.text == "FINALIZANDO AÑO", "pause makes in-flight annual result explicit")
	check(hud.top_year.text == Hud.fmt_year(-100), "in-flight year never replaces the published year")
	observer.source.busy = false
	hud.refresh_timeline(observer.source, -100)
	hud.set_chronicle([{"id":1,"year":-100,"kind":"foundation","text":"Acontecimiento recibido","cell":1}])
	hud._toggle_chronicle(true)
	check(hud.chronicle_list.item_count == 1 and hud.chronicle_list.get_item_text(0).contains("Acontecimiento recibido"), "chronicle uses received event text")
	hud.set_chronicle([
		{"id":1,"year":-110,"kind":"foundation","text":"Acontecimiento recibido","cell":1},
		{"id":2,"year":-105,"kind":"famine","text":"Mala cosecha","why":"Sequía prolongada","cell":2}
	])
	hud.chronicle_query.text = "sequía"
	hud._fill_chronicle()
	check(hud.chronicle_list.item_count == 1 and int(hud.chronicle_list.get_item_metadata(0)["event"]) == 2,
		"chronicle searches original Go event context, not only title")
	hud.chronicle_query.text = ""
	hud._fill_chronicle()
	check(hud.chronicle_list.item_count == 2, "chronicle shows both matching published records")
	var many_events := []
	for i in 501:
		many_events.append({"id":i + 10, "year":-100, "kind":"famine", "text":"Sequía original", "cell":-1})
	hud.set_chronicle(many_events)
	check(hud.chronicle_list.item_count == 300 and hud.chronicle_matches.text.contains("501"),
		"chronicle searches all retained records but limits displayed results to 300")
	hud._toggle_maps(true)
	check(not hud.chronicle_panel.visible and hud._layer_panel.visible, "right docks exclude each other")
	hud.focus_search()
	check(not hud._layer_panel.visible and hud._search_panel.visible, "search dismisses map dock")
	check(hud.dismiss_popovers(), "Escape can dismiss atlas docks")
	check(not hud._search_panel.visible and not hud._layer_panel.visible, "atlas docks close together")
	hud.show_request_error("get_entity", "not_found", "Entidad no disponible")
	check(hud._notice.visible and not hud._notice_recover.visible, "recoverable query has nonterminal notice")
	check(observer.source.connected, "UI query notice does not end session")
	check(observer.source._outgoing.is_empty(), "UI query notice sends no requests")
	hud.show_session_error("Transporte interrumpido")
	check(hud._notice_recover.visible, "terminal notice offers new session")
	check(observer.source._outgoing.is_empty(), "UI never retries uncertain advance")
	hud.set_view_scale(0.9, 0.0)
	check(hud._scale_buttons[0].button_pressed, "continental scale highlighted")
	hud.set_view_scale(0.6, 0.0)
	check(hud._scale_buttons[1].button_pressed, "regional scale highlighted")
	hud.set_view_scale(0.3, 0.0)
	check(hud._scale_buttons[2].button_pressed, "province scale highlighted")
	for dimensions in [Vector2(1000,640),Vector2(1280,720),Vector2(1600,900),Vector2(2560,1440)]:
		root.size = Vector2i(dimensions)
		hud.size = dimensions
		hud._fit_layout()
		await process_frame
		check(hud._scale_bar.size.y < 64, "orientation indicator stays on one line " + str(dimensions))
		check(hud.info_panel.offset_right < dimensions.x - 300, "inspector leaves map space " + str(dimensions))
		check(hud.info_panel.get_global_rect().end.y <= hud.timeline_panel.get_global_rect().position.y, "inspector clears timeline " + str(dimensions))
		check(hud._rail.get_parent().get_global_rect().end.x < hud.info_panel.get_global_rect().position.x, "rail clears inspector " + str(dimensions))
	var launch := LaunchScreen.new()
	root.add_child(launch)
	launch.build("Test")
	check(launch.launch.visible and not launch.progress.visible, "initial start screen waits for user")
	launch.launch.pressed.emit()
	check(not launch.launch.visible and launch.progress.visible, "launch enters progress state")
	launch.update_message("failure", true)
	check(launch.retry.visible and not launch.progress.visible, "startup failure permits explicit new session")
	var camera := StrategyCamera.new()
	camera.min_distance = 3.5
	camera.max_distance = 1000
	camera.set_scale_view(2)
	check(camera._goal_distance > camera.min_distance and camera._goal_distance < 30, "provincial camera target")
	camera.set_scale_view(1)
	check(camera._goal_distance > 80 and camera._goal_distance < 200, "regional camera target")
	check(camera.wheel_ratio(0.2) > 1.0, "precision wheel remains monotonic")
	camera.free()
	# The command UI must be a pure intent emitter with engine-owned catalogs.
	check(hud.command_panel != null and not hud.command_panel.visible, "intervention editor is initially hidden")
	hud.set_command_catalog({
		"omens":[{"Key":"fixture-omen","Name":"Presagio","Cost":3,"KM":120,"Needs":"none","desc":"Ejemplo"}],
		"parameters":[
			{"key":"fixture-live","label":"Editable","min":0.0,"max":1.0,"step":0.1,"default":0.2,"newWorld":false},
			{"key":"fixture-new","label":"Mundo nuevo","min":0.0,"max":2.0,"step":1.0,"default":1.0,"newWorld":true}
		]
	})
	hud.set_command_context({
		"year":-100,"nextSequence":5,"rulesSHA256":"go-hash","favor":4.0,
		"rules":{"sandbox":true,"values":{"fixture-live":0.2,"fixture-new":1.0}}
	})
	check(hud.command_panel._sandbox.button_pressed, "sandbox reflects effective Go rule without local toggle")
	check(not (hud.command_panel._controls["fixture-new"] as SpinBox).editable, "new-world parameter remains locked")
	var commands_sent: Array = []
	hud.command_requested.connect(func(kind_name: String, payload: Dictionary):
		commands_sent.append({"kind":kind_name,"payload":payload}))
	(hud.command_panel._controls["fixture-live"] as SpinBox).value = 0.6
	hud.command_panel._submit_rules()
	check(commands_sent.size() == 1 and commands_sent[0]["kind"] == "change_rules", "rule edits generate an intent")
	check(commands_sent[0]["payload"]["values"].has("fixture-live") and not commands_sent[0]["payload"]["values"].has("fixture-new"), "rule payload excludes new-world values")
	hud.command_panel._arm_omen()
	var targeted := hud.consume_omen_target(2)
	check(targeted == {"omen":"fixture-omen","cell":2}, "one map click consumes armed Go omen intent")
	check(hud.consume_omen_target(2).is_empty(), "omen cannot fire twice from a single arm")
	hud.set_command_pending(true)
	check(hud.command_panel._apply.disabled and hud.command_panel._sandbox.disabled, "UI blocks edits while command is in flight")
	hud.set_command_pending(false)
	hud.set_command_outcome({"accepted":false,"error":"sequence stale"})
	check(hud.command_panel._status.text.contains("sequence stale"), "Go rejection is visible to player")

	observer.source.close()
	launch.queue_free()
	hud.queue_free()
	observer.queue_free()
	await process_frame
	print("Atlas UX regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
