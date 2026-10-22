extends Control
## Observer only. All causal state, years, commands and fingerprints stay in Go.
var source: BridgeSource
var world: WorldData
var current: HistoryFrame
var map: AtlasMap
var title: Label
var status: Label
var inspector: RichTextLabel
var chronicle: RichTextLabel
var seed_input: LineEdit
var layer_choice: OptionButton
var speed: OptionButton
var step_button: Button
var play_button: Button
var init_button: Button
var pause_button: Button
var review: OptionButton
var legend: Label
var tabs: TabContainer
var entity_view: RichTextLabel
var entity_back: Button
var chronicle_kind: OptionButton
var chronicle_filter: LineEdit
var search_input: LineEdit
var search_kind: OptionButton
var search_results: ItemList
var world_view: RichTextLabel
var history_year: SpinBox
var history_mode: OptionButton
var history_button: Button
var history_exit: Button
## Every thematic layer of the shared catalog; a layer whose Go system is not
## published stays disabled and is never filled with substitute values.
var layer_ids: Array[String] = []
var layer_names: Array[String] = []
var entity_kind := ""
var entity_id := -1
var entity_trail: Array = []
var historical := {}
var _chronicle_signature := ""
var province_extra := {}
var desired_layer := "states"
var shown_layer := ""
var playing := false
var next_year_us := 0
var selected := -1
var worker: Thread
var queue: Array[HistoryFrame] = []
var received_us := {}
var options := {}
var metrics := AtlasMetrics.new()
var benchmark := false
var bench_ready := false
var preparing := false
var initial_prepared := false
var query_key := ""
var review_year := -2147483648
var _next_selection := 0.0
var _closing := false
var _failure := false
var _smoke_start := -2147483648
var _smoke_pausing := false
var _status_due_ms := 0

func _ready() -> void:
	get_tree().auto_accept_quit=false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=",true,1)
			options[parts[0]]=parts[1] if parts.size()==2 else "true"
	benchmark=options.has("bench-out")
	if options.has("width"):
		get_window().size=Vector2i(int(options.width),int(options.get("height","1080")))
	if benchmark: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Interactive use renders only when the map, panel or camera change; the
	# benchmark keeps continuous frames to measure capacity.
	OS.low_processor_usage_mode=not benchmark
	_build_ui()
	if benchmark and DisplayServer.get_name()=="headless":
		_fail("La captura de FPS necesita una ventana real. Usa --smoke-out para una comprobación headless.")
		return
	RenderingServer.frame_post_draw.connect(_post_draw)
	if benchmark:
		metrics.viewport=get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(metrics.viewport,not options.has("no-render-timing"))
		# Subsystem isolation for diagnosis only; never a product setting.
		match str(options.get("diag","")):
			"map-hidden": map.visible=false
			"panel-hidden": tabs.get_parent().visible=false
		metrics.open(str(options["bench-out"]),float(options.get("seconds","30")),{
			"schema":"asabiya/atlas2d-measure-v1","godot":Engine.get_version_info(),
			"os":OS.get_name(),"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
			"renderer":RenderingServer.get_current_rendering_method(),"pid":OS.get_process_id(),
			"size":str(DisplayServer.window_get_size()),"vsync_requested":"disabled","scene":"procedural",
			"target_hardware_verified":false,"diag":str(options.get("diag","none")),"headless":DisplayServer.get_name()=="headless",
			"build":JSON.parse_string(FileAccess.get_file_as_string("res://build-manifest.json"))})
	call_deferred("_initialize")

func _button(row: Container, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text=text
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	title=Label.new()
	title.text="ASABIYA ATLAS 2D  ·  Mundo procedural de prueba  ·  La Tierra real está pendiente"
	title.add_theme_font_size_override("font_size",20)
	column.add_child(title)
	var toolbar := HFlowContainer.new()
	column.add_child(toolbar)
	seed_input=LineEdit.new()
	seed_input.text=str(options.get("seed","Asabiya"))
	seed_input.custom_minimum_size.x=145
	seed_input.tooltip_text="Semilla de geografía Go; iniciar crea una sesión nueva. No guarda la anterior."
	toolbar.add_child(seed_input)
	init_button=_button(toolbar,"Nueva sesión",_initialize)
	step_button=_button(toolbar,"+1 año",_step)
	play_button=_button(toolbar,"▶ Reproducir",func():
		playing=true
		review_year=-2147483648
		if not historical.is_empty(): _exit_historical())
	pause_button=_button(toolbar,"Ⅱ Pausar y verificar",_pause)
	speed=OptionButton.new()
	for item: String in ["1 año/s","5 años/s","20 años/s","Máximo"]: speed.add_item(item)
	speed.selected=1
	toolbar.add_child(speed)
	layer_choice=OptionButton.new()
	for definition: Dictionary in MapLayers.DEFS:
		layer_ids.append(str(definition.id))
		layer_names.append("%s · %s" % [definition.group, definition.name])
		layer_choice.add_item(layer_names[-1])
	layer_choice.selected=layer_ids.find(desired_layer)
	layer_choice.item_selected.connect(func(index: int):
		desired_layer=layer_ids[index]
		historical.clear()
		if current!=null and worker==null and queue.is_empty(): queue.append(current))
	toolbar.add_child(layer_choice)
	_button(toolbar,"Mundo",func(): map.zoom_to(1))
	_button(toolbar,"Región",func(): map.zoom_to(4))
	_button(toolbar,"Provincia",func(): map.zoom_to(24))
	review=OptionButton.new()
	review.tooltip_text="Revisar hasta 24 publicaciones retenidas. No rebobina el motor."
	review.item_selected.connect(_review)
	toolbar.add_child(review)
	var split := HSplitContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(split)
	map=AtlasMap.new()
	map.custom_minimum_size=Vector2(320,240)
	map.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	map.province_selected.connect(_selected)
	split.add_child(map)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x=470
	panel.size_flags_horizontal=Control.SIZE_FILL
	split.add_child(panel)
	tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(_index: int): _refresh_tab())
	panel.add_child(tabs)
	inspector=_rich("Provincia")
	inspector.text="Arrastra para desplazar. Rueda para acercar.\nSelecciona una provincia.\n\nGo calcula la historia; este cliente la observa."
	var entity_box := VBoxContainer.new()
	entity_box.name="Entidad"
	tabs.add_child(entity_box)
	entity_back=_button(entity_box,"◀ Anterior",_entity_previous)
	entity_back.disabled=true
	entity_view=_rich("",entity_box)
	entity_view.text="Abre un Estado, pueblo, religión, ciudad u otra entidad desde una provincia, la crónica o la búsqueda."
	var chronicle_box := VBoxContainer.new()
	chronicle_box.name="Crónica"
	tabs.add_child(chronicle_box)
	var chronicle_bar := HBoxContainer.new()
	chronicle_box.add_child(chronicle_bar)
	chronicle_kind=OptionButton.new()
	chronicle_kind.item_selected.connect(func(_index: int): _refresh_chronicle(true))
	chronicle_bar.add_child(chronicle_kind)
	chronicle_filter=LineEdit.new()
	chronicle_filter.placeholder_text="Filtrar texto"
	chronicle_filter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	chronicle_filter.text_changed.connect(func(_text: String): _refresh_chronicle(true))
	chronicle_bar.add_child(chronicle_filter)
	chronicle=_rich("",chronicle_box)
	var search_box := VBoxContainer.new()
	search_box.name="Buscar"
	tabs.add_child(search_box)
	var search_bar := HBoxContainer.new()
	search_box.add_child(search_bar)
	search_input=LineEdit.new()
	search_input.placeholder_text="Nombre o ID"
	search_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	search_input.text_changed.connect(func(_text: String): _refresh_search())
	search_bar.add_child(search_input)
	search_kind=OptionButton.new()
	search_kind.add_item("Todo")
	for kind: String in AtlasEntities.SEARCH_KINDS: search_kind.add_item(AtlasEntities.NAMES[kind])
	search_kind.item_selected.connect(func(_index: int): _refresh_search())
	search_bar.add_child(search_kind)
	search_results=ItemList.new()
	search_results.size_flags_vertical=Control.SIZE_EXPAND_FILL
	search_results.item_activated.connect(_search_open)
	search_results.item_clicked.connect(func(index: int, _at: Vector2, _button: int): _search_open(index))
	search_box.add_child(search_results)
	var world_box := VBoxContainer.new()
	world_box.name="Mundo"
	tabs.add_child(world_box)
	world_view=_rich("",world_box)
	var history_bar := HFlowContainer.new()
	world_box.add_child(history_bar)
	history_year=SpinBox.new()
	history_year.rounded=true
	history_year.allow_greater=false
	history_year.allow_lesser=false
	history_year.tooltip_text="Año a consultar. Go devuelve la capa conservada más cercana anterior o igual."
	history_bar.add_child(history_year)
	history_mode=OptionButton.new()
	for item: String in ["Pueblos","Religiones","Densidad","Era tecnológica","Cohesión"]: history_mode.add_item(item)
	history_bar.add_child(history_mode)
	history_button=_button(history_bar,"Ver capa histórica Go",_request_historical)
	history_exit=_button(history_bar,"Volver al año publicado",_exit_historical)
	legend=Label.new()
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(legend)
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)

func _rich(title: String, parent: Control = null) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled=true
	label.selection_enabled=true
	label.size_flags_vertical=Control.SIZE_EXPAND_FILL
	label.meta_clicked.connect(_open_link)
	if parent==null:
		label.name=title
		tabs.add_child(label)
	else: parent.add_child(label)
	return label

func _initialize() -> void:
	if _closing: return
	playing=false
	bench_ready=false
	initial_prepared=false
	preparing=false
	if worker!=null:
		worker.wait_to_finish()
		worker=null
	if source!=null: source.close()
	queue.clear()
	received_us.clear()
	_held.clear()
	current=null
	world=null
	map.world=null
	map.frame=null
	map.selected=-1
	map.shader.set_shader_parameter("selected",-2.0)
	map._dirty=true
	inspector.text="Selecciona una provincia del nuevo mundo."
	legend.text=""
	chronicle.text=""
	entity_kind=""
	entity_id=-1
	entity_trail.clear()
	entity_back.disabled=true
	entity_view.text="Abre una entidad del nuevo mundo."
	historical.clear()
	province_extra.clear()
	_chronicle_signature=""
	search_results.clear()
	world_view.text=""
	review.clear()
	map.queue_redraw()
	selected=-1
	query_key=""
	review_year=-2147483648
	var executable: String=str(options.get("server",OS.get_executable_path().get_base_dir().path_join("asabiya-server.exe")))
	source=BridgeSource.new(null,executable)
	source.world_config.seed=seed_input.text
	if options.has("small"):
		source.world_config.width=48
		source.world_config.height=24
		source.world_config.detail=4
	source.world_ready.connect(func(value: WorldData):
		world=value
		map.set_world(value)
		map.zoom_to(float(options.get("zoom","1"))))
	source.frames_changed.connect(_receive_frame)
	source.progress_changed.connect(func(calculated: int, visualized: int, remaining: int):
		if preparing:
			status.text="Preparación histórica explícita · Go calcula todos los años · muestra cada 100\nCalculado: %d · mostrado: %d · quedan: %d. Pausar detiene al terminar el año en curso." % [calculated,visualized,remaining])
	source.status_changed.connect(func(message: String):
		if message!="": status.text=message)
	source.request_failed.connect(func(op: String,code: String,message: String): _fail(op+" · "+code+" · "+message))
	if not source.start(): _fail(source.last_error)

func _receive_frame() -> void:
	var entered := Time.get_ticks_usec()
	_phases["receive_entry_ms"]=(entered-_tick_started)/1000.0
	_receive_body()
	_phases["receive_ms"]=_phases.get("receive_ms",0.0)+(Time.get_ticks_usec()-entered)/1000.0

func _receive_body() -> void:
	if not source.is_fast_forward(): source.stop_live() # Backpressure: publish this year before requesting the next.
	var years := source.years()
	if years.is_empty(): return
	var value := source.frame(years[-1])
	if not initial_prepared and (benchmark or options.has("prepare-years")):
		initial_prepared=true
		var count := int(options.get("prepare-years",options.get("year","0")))
		if count>0:
			preparing=true
			source.start_fast_forward(count,100)
	if preparing:
		status.text="Preparación explícita del benchmark: %d · no se presentan todos los años intermedios" % source.calculated_year
		queue.clear()
		if not source.is_fast_forward(): preparing=false
	queue.append(value)
	received_us[value.get_instance_id()]=Time.get_ticks_usec()
	_retire(value)

## BridgeSource drops its oldest publication on the main thread. Holding one
## extra reference here moves that release (thousands of entity records) to a
## worker: the immutable frame is freed once no view or queue references it.
func _retire(latest: HistoryFrame) -> void:
	_held[latest.year]=latest
	var live := source.years()
	var released := []
	for year: int in _held.keys():
		var frame: HistoryFrame=_held[year]
		if live.has(year) or frame==current or queue.has(frame): continue
		released.append(frame)
		_held.erase(year)
	if released.is_empty() or options.has("release-on-main"): return
	_release_tasks.append(WorkerThreadPool.add_task(func(): released.clear()))

func _process(_delta: float) -> void:
	if source==null or _closing: return
	var tick_us := Time.get_ticks_usec()
	_tick()
	metrics.main_ms+=(Time.get_ticks_usec()-tick_us)/1000.0

## Main-thread phases of the last tick, recorded when a tick is slow.
var _phases := {}
var _held := {}
var _release_tasks: Array[int] = []
var _tick_started := 0
func _phase(name: String, started: int) -> int:
	var now := Time.get_ticks_usec()
	_phases[name]=_phases.get(name,0.0)+(now-started)/1000.0
	return now

func _tick() -> void:
	_phases.clear()
	var at := Time.get_ticks_usec()
	var tick_start := at
	_tick_started=at
	source.poll()
	at=_phase("poll",at)
	if source.last_error!="" and not _failure:
		_fail(source.last_error)
		return
	if worker!=null and not worker.is_alive():
		var packet: Dictionary=worker.wait_to_finish()
		worker=null
		at=_phase("join",at)
		var publication: HistoryFrame=packet.frame
		# Review and live publications are explicitly separate views of the same Go data.
		if packet.layer!=desired_layer:
			queue.push_front(publication)
		elif review_year==-2147483648 or publication.year==review_year:
			var upload_ms := map.publish(packet)
			at=_phase("publish",at)
			current=publication
			shown_layer=packet.layer
			historical.clear()
			map.routes_visible=shown_layer=="routes"
			_update_legend(packet.legend)
			metrics.publication_us=int(received_us.get(current.get_instance_id(),Time.get_ticks_usec()))
			received_us.erase(current.get_instance_id())
			metrics.updates+=1
			metrics.record("map_update",{"year":current.year,"projection_ms":packet.projection_ms,"upload_ms":upload_ms,"layer":shown_layer,"state_sha256":current.state_digest,"digest_mode":current.digest_mode})
			_update_panel()
			at=_phase("panel",at)
			_refresh_review()
			at=_phase("review",at)
	while not _release_tasks.is_empty() and WorkerThreadPool.is_task_completed(_release_tasks[0]):
		WorkerThreadPool.wait_for_task_completion(_release_tasks.pop_front())
	if worker==null and not queue.is_empty() and world!=null:
		var next: HistoryFrame=queue.pop_front()
		worker=Thread.new()
		worker.start(AtlasProjection.layer.bind(world,next,desired_layer))
		at=_phase("spawn",at)
	if benchmark and (at-tick_start)>20000:
		metrics.record("slow_tick",_phases.merged({"total_ms":(Time.get_ticks_usec()-tick_start)/1000.0}))
	if options.has("smoke-out") and not preparing and current!=null and source.can_advance() and worker==null and queue.is_empty():
		_export_smoke()
		if _closing: return
	if benchmark and not bench_ready and current!=null and not preparing and not source.busy and queue.is_empty() and worker==null:
		var actual := Vector2i(get_viewport().get_texture().get_size())
		var requested := Vector2i(int(options.get("width",str(actual.x))),int(options.get("height",str(actual.y))))
		if actual!=requested or get_window().size!=requested:
			_fail("Resolución inválida: framebuffer %s, ventana %s, solicitada %s" % [actual,get_window().size,requested])
			return
		bench_ready=true
		playing=options.has("active")
		metrics.record("ready",{"year":current.year,"go_pid":source._pid,"world_sha256":current.world_digest,"state_sha256":current.state_digest,"digest_mode":current.digest_mode,"layer":shown_layer,"window_size":[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y],"framebuffer_size":[get_viewport().get_texture().get_size().x,get_viewport().get_texture().get_size().y],"map_pixels":[map.size.x,map.size.y],"zoom_multiplier":float(options.get("zoom","1")),"world_config":source.world_config,"history_seed":source.history_seed})
		metrics.begin(current.year,playing)
	if playing and not preparing and worker==null and queue.is_empty() and source.can_advance() and Time.get_ticks_usec()>=next_year_us:
		review_year=-2147483648
		var rates := [1,5,20,0]
		var rate: int=rates[speed.selected]
		if benchmark: rate=int(options.get("rate","0"))
		next_year_us=Time.get_ticks_usec()+(int(1000000.0/rate) if rate>0 else 0)
		source.start_live(0)
	if bench_ready and metrics.started_us>0:
		var elapsed := (Time.get_ticks_usec()-metrics.started_us)/1000000.0
		if not options.has("no-pan"):
			map.target_center=Vector2(world.width*(0.5+sin(elapsed*0.2)*0.15),world.height*(0.5+sin(elapsed*0.12)*0.08))
		if elapsed>_next_selection:
			_next_selection=elapsed+1.0
			map.select_at(map.size*0.5)
	if current!=null and not preparing and not _failure and Time.get_ticks_msec()>=_status_due_ms:
		_status_due_ms=Time.get_ticks_msec()+1000
		_update_status()
	init_button.disabled=source.busy or playing or preparing
	step_button.disabled=preparing or not source.can_advance() or playing or worker!=null or not queue.is_empty()
	play_button.disabled=not source.connected or preparing
	pause_button.disabled=not source.connected
	review.disabled=preparing or playing or source.busy or worker!=null

func _step() -> void:
	playing=false
	review_year=-2147483648
	historical.clear()
	source.advance(1)

func _pause() -> void:
	playing=false
	review_year=-2147483648
	source.pause()

func _review(index: int) -> void:
	if source==null or playing or source.busy: return
	var year := int(review.get_item_metadata(index))
	var value := source.frame(year)
	if value!=null:
		review_year=year
		queue.append(value)

func _refresh_review() -> void:
	review.clear()
	for year in source.years():
		review.add_item("Año %d" % year)
		review.set_item_metadata(review.item_count-1,year)
		if year==current.year: review.select(review.item_count-1)

func _selected(id: int, started_us := 0) -> void:
	var started := started_us if started_us>0 else Time.get_ticks_usec()
	selected=id
	map.selected=id
	map.shader.set_shader_parameter("selected",float(id))
	map._dirty=true
	query_key=""
	_update_panel()
	metrics.record("selection_local",{"ms":(Time.get_ticks_usec()-started)/1000.0,"id":id,"year":current.year if current!=null else 0})
	metrics.selection_us=started

func _layer_label() -> String:
	if not historical.is_empty():
		return "Capa histórica Go %s · %s" % [AtlasEntities.fmt_year(historical.year),history_mode.get_item_text(["peoples","religions","population","technology","cohesion"].find(historical.mode))]
	var index := layer_ids.find(shown_layer)
	return layer_names[index] if index>=0 else shown_layer

func _update_status() -> void:
	var fingerprint := "SHA diferido explícito; pausa para verificar" if current.state_digest=="" else current.state_digest
	status.text="Año %s · %s · %.0f habitantes · %s · %s\n%s" % [AtlasEntities.fmt_year(current.year),_layer_label(),current.world_population,("%.1f FPS" % Engine.get_frames_per_second()) if not OS.low_processor_usage_mode else "%.0f fotogramas/s, render bajo demanda" % Engine.get_frames_per_second(),"Preparación Go · muestra cada 100 años" if preparing else ("Reproduciendo" if playing else "Pausa / revisión"),fingerprint]

func _update_panel() -> void:
	if current==null or world==null: return
	_update_status()
	_update_layer_availability()
	_refresh_tab()
	if selected<0 or selected>=world.cell_count(): return
	var id := selected
	var owner: int=current.owner[id]
	var people_id: int=current.people[id]
	var religion_id: int=current.religion[id]
	var people: Dictionary=current.peoples.get(people_id,{})
	var lines := PackedStringArray()
	lines.append("[b]Provincia Go #%d[/b] · %s" % [id,AtlasEntities.fmt_year(current.year)])
	lines.append("%s · coordenadas lógicas (%d, %d)" % ["Tierra" if world.is_land(id) else "Océano",id%world.width,id/world.width])
	lines.append("Población provincial: %.2f" % current.population[id])
	lines.append("Propietario: %s" % (AtlasEntities.link("polity",owner,AtlasEntities.label(current,"polity",owner)) if owner>0 else "Sin estado [ID 0]"))
	lines.append("Pueblo: %s" % (AtlasEntities.link("people",people_id,AtlasEntities.label(current,"people",people_id)) if people_id>=0 else "Sin pueblo [ID −1]"))
	var culture: Variant=people.get("culture")
	lines.append("Cultura, 6 componentes: %s" % (AtlasEntities.escape(str(culture)) if culture is Array else "No disponible"))
	lines.append("Religión: %s" % (AtlasEntities.link("religion",religion_id,AtlasEntities.label(current,"religion",religion_id)) if religion_id>=0 else "Sin religión [ID −1]"))
	for city: Dictionary in current.settlements:
		if int(city.cell)==id: lines.append("Ciudad: %s" % AtlasEntities.link("city",int(city.id),str(city.get("name","Ciudad #%d" % int(city.id)))))
	lines.append("Capacidad: %.2f" % current.carrying[id])
	lines.append("Tecnología (0–1): %.2f" % current.technology[id] if not current.technology.is_empty() else "Tecnología: No disponible")
	lines.append("Altitud lógica: %.0f m" % world.elevation[id])
	lines.append("Bioma: %s" % WorldData.BIOME_NAMES_ES[clampi(world.biome[id],0,9)])
	lines.append("\nLas cifras y entidades pertenecen al año mostrado. Cultura RGB usa 3 de los 6 componentes reales.")
	var key := "%d/%d/%s" % [id,current.year,current.state_digest]
	# Pause-only Go answers stay attached to their province/year/SHA key.
	var extra: Dictionary=province_extra.get(key,{})
	inspector.text="\n".join(lines)+"\n"+str(extra.get("query",""))+str(extra.get("history",""))
	if not playing and source.can_advance() and source.years()[-1]==current.year and query_key!=key:
		query_key=key
		var request_us := Time.get_ticks_usec()
		source.query_province(id,func(response: Dictionary):
			if current==null or key!=query_key or playing or int(response.get("year",-1))!=current.year: return
			metrics.record("selection_query",{"ms":(Time.get_ticks_usec()-request_us)/1000.0,"id":id,"year":current.year})
			var data: Dictionary=response.get("data",{})
			var city_id: Variant=data.get("cityId")
			_attach(key,"query","\nConsulta Go: cohesión %s · integración %s\nFortificación: %s (índice; no edificios)\nCiudad ID: %s\n" % [str(data.get("cohesion","—")),str(data.get("integration","—")),str(data.get("fortification","—")),AtlasEntities.link("city",int(city_id),"#%d" % int(city_id)) if (city_id is int or city_id is float) and int(city_id)>=0 else "—"]))
		source.query_history(id,func(response: Dictionary):
			if current==null or key!=query_key or playing or int(response.get("year",-1))!=current.year: return
			var records: Array=response.get("data",{}).get("records",[]) if response.get("data",{}).get("records") is Array else []
			var text := "\nPropiedad observada cada 10 años. Últimas %d de %d observaciones:\n" % [mini(12,records.size()),records.size()]
			for entry: Dictionary in records.slice(maxi(0,records.size()-12)):
				var holder := int(entry.get("ownerPolityId",0))
				text+="%s · %s\n" % [AtlasEntities.fmt_year(entry.get("year")),AtlasEntities.link("polity",holder,AtlasEntities.label(current,"polity",holder)) if holder>0 else "sin estado"]
			_attach(key,"history",text))
	elif playing:
		inspector.append_text("\nPausa para consultar detalle provincial e historial sin mezclar años.")

func _attach(key: String, part: String, text: String) -> void:
	if not province_extra.has(key): province_extra={key:{}}
	province_extra[key][part]=text
	if key==query_key: _update_panel()

func _update_layer_availability() -> void:
	for index in layer_ids.size():
		var available := MapLayers.available(layer_ids[index],source,current) and layer_ids[index]!="economy"
		layer_choice.set_item_disabled(index,not available)
		layer_choice.set_item_tooltip(index,"" if available else "Go no publica este campo en el contrato actual; la capa no se rellena con valores sustitutos.")

## BBCode links: "cell:ID" selects a province, "<kind>:ID" opens a Go entity.
func _open_link(meta: Variant) -> void:
	var parts := str(meta).split(":")
	if parts.size()!=2 or not parts[1].is_valid_int(): return
	var id := int(parts[1])
	if parts[0]=="cell":
		if world==null or id<0 or id>=world.cell_count(): return
		_selected(id)
		map.target_center=Vector2(id%world.width,floori(float(id)/world.width))+Vector2(0.5,0.5)
		if map.target_zoom<map.zoom_base()*4.0: map.zoom_to(4)
		tabs.current_tab=0
	elif AtlasEntities.NAMES.has(parts[0]):
		_open_entity(parts[0],id)

func _open_entity(kind: String, id: int, remember := true) -> void:
	if remember and entity_kind!="": entity_trail.append([entity_kind,entity_id])
	entity_kind=kind
	entity_id=id
	entity_back.disabled=entity_trail.is_empty()
	tabs.current_tab=1
	_refresh_tab()

func _entity_previous() -> void:
	if entity_trail.is_empty(): return
	var previous: Array=entity_trail.pop_back()
	_open_entity(previous[0],previous[1],false)

func _refresh_tab() -> void:
	if current==null or world==null or tabs==null: return
	match tabs.current_tab:
		1: if entity_kind!="": entity_view.text=AtlasEntities.render(current,world,entity_kind,entity_id)
		2: _refresh_chronicle(false)
		3: _refresh_search()
		4: _refresh_world()

func _refresh_chronicle(force: bool) -> void:
	if current==null: return
	var kinds := PackedStringArray()
	for event: Dictionary in current.events:
		var kind := str(event.get("kind",""))
		if kind!="" and not kinds.has(kind): kinds.append(kind)
	kinds.sort()
	var chosen := "" if chronicle_kind.selected<=0 else chronicle_kind.get_item_text(chronicle_kind.selected)
	var signature := "%d/%d/%s/%s/%s" % [current.year,current.events.size(),chosen,chronicle_filter.text,",".join(kinds)]
	if signature==_chronicle_signature and not force: return
	_chronicle_signature=signature
	chronicle_kind.clear()
	chronicle_kind.add_item("Todas las clases")
	for kind: String in kinds:
		chronicle_kind.add_item(kind)
		if kind==chosen: chronicle_kind.select(chronicle_kind.item_count-1)
	var needle := chronicle_filter.text.strip_edges().to_lower()
	var lines := PackedStringArray()
	var matched := 0
	for index in range(current.events.size()-1,-1,-1):
		var event: Dictionary=current.events[index]
		if chosen!="" and str(event.get("kind",""))!=chosen: continue
		if needle!="" and not (str(event.get("text",""))+" "+str(event.get("why",""))).to_lower().contains(needle): continue
		matched+=1
		if lines.size()<300: lines.append(AtlasEntities.event_line(current,world,event))
	chronicle.text="[b]Crónica Go[/b] · %d de %d acontecimientos retenidos en la publicación de %s (más recientes primero; máximo 300 en pantalla).\n\n%s" % [matched,current.events.size(),AtlasEntities.fmt_year(current.year),"\n".join(lines) if not lines.is_empty() else "Sin acontecimientos que coincidan."]

func _refresh_search() -> void:
	search_results.clear()
	if current==null: return
	var kind: String = "" if search_kind.selected<=0 else AtlasEntities.SEARCH_KINDS[search_kind.selected-1]
	for item: Array in AtlasEntities.search(current,search_input.text,kind):
		search_results.add_item("%s · %s #%d" % [item[2],AtlasEntities.NAMES[item[0]],item[1]])
		search_results.set_item_metadata(search_results.item_count-1,[item[0],item[1]])

func _search_open(index: int) -> void:
	if index<0 or index>=search_results.item_count: return
	var target: Array=search_results.get_item_metadata(index)
	_open_entity(target[0],target[1])

func _refresh_world() -> void:
	if current==null: return
	var counts := {}
	for kind: String in ["polity","people","religion","city","war"]:
		var alive := 0
		for record: Dictionary in current.entity_records.get(kind,{}).values():
			if record.get("alive",record.get("active",false)): alive+=1
		counts[kind]=alive
	var lines := PackedStringArray()
	lines.append("[b]Mundo Go[/b] · %s · semilla %s · historia %s" % [AtlasEntities.fmt_year(current.year),AtlasEntities.escape(str(source.world_config.get("seed",""))),AtlasEntities.escape(source.history_seed)])
	lines.append("Población total: %.0f" % current.world_population)
	lines.append("Estados (tipo state, vivos): %d · entidades políticas vivas de cualquier tipo: %d" % [current.state_count(),counts.polity])
	lines.append("Pueblos vivos: %d · religiones activas: %d · ciudades ocupadas: %d · guerras activas: %d" % [counts.people,counts.religion,current.settlements.size(),current.wars.size()])
	lines.append("SHA del estado: %s" % (current.state_digest if current.state_digest!="" else "diferido explícito (pausa para verificar)"))
	if not current.stats.is_empty():
		lines.append("\n[b]Estadísticas publicadas por Go[/b] (últimos registros)")
		for entry: Variant in current.stats.slice(maxi(0,current.stats.size()-12)):
			if not entry is Dictionary: continue
			var era := int(entry.get("leadingEra",-1))
			var era_name: String=str(source.era_names[era]) if era>=0 and era<source.era_names.size() else str(era)
			lines.append("%s · población %.0f · estados %d · hordas %d · pueblos %d · era líder %s · mayor: %s" % [AtlasEntities.fmt_year(entry.get("year")),float(entry.get("population",0)),int(entry.get("polities",0)),int(entry.get("hordes",0)),int(entry.get("livingPeoples",0)),AtlasEntities.escape(era_name),AtlasEntities.escape(str(entry.get("biggest","—")))])
	if not historical.is_empty():
		lines.append("\n[b]Mapa mostrado:[/b] capa histórica Go de %s (pedida: %s). No contiene propietarios; Go la conserva cada 50 años (cada 250 si tiene más de 1500 años)." % [AtlasEntities.fmt_year(historical.get("year")),AtlasEntities.fmt_year(historical.get("requested"))])
	world_view.text="\n".join(lines)
	var latest: int=source.years()[-1] if not source.years().is_empty() else current.year
	history_year.min_value=_history_start()
	history_year.max_value=latest
	if history_year.value<history_year.min_value or history_year.value>latest: history_year.value=latest
	var idle: bool=not playing and source.can_advance() and worker==null and queue.is_empty() and not source.years().is_empty() and source.years()[-1]==current.year
	history_button.disabled=not idle
	history_exit.disabled=historical.is_empty()

func _history_start() -> int:
	for entry: Variant in current.stats:
		if entry is Dictionary and entry.has("year"): return int(entry.year)
	return current.year

## Pause-only engine query; the overlay replaces the map until the user returns.
func _request_historical() -> void:
	if current==null or playing or not source.can_advance(): return
	var requested := int(history_year.value)
	var mode: String=["peoples","religions","population","technology","cohesion"][history_mode.selected]
	var expected_year := current.year
	source.request("get_historical_layer",{"year":requested},func(response: Dictionary):
		if current==null or playing or current.year!=expected_year: return
		var data: Dictionary=response.get("data",{})
		var packet := AtlasProjection.historical(world,current,data,mode)
		map.publish(packet)
		historical={"year":int(data.get("year",requested)),"requested":requested,"mode":mode}
		shown_layer=packet.layer
		metrics.record("historical_layer",{"requested":requested,"year":historical.year,"mode":mode,"ms":packet.projection_ms})
		_update_legend(packet.legend)
		_update_status()
		_refresh_world())

func _exit_historical() -> void:
	historical.clear()
	if current!=null and worker==null: queue.append(current)

func _update_legend(value: Dictionary) -> void:
	legend.text="Leyenda · "+_layer_label()+"\n"
	if value.get("kind")=="ramp":
		legend.text+="Violeta → azul → verde → amarillo → rojo\n%s → %s" % [str(value.get("min","")),str(value.get("max",""))]
	elif shown_layer=="cultures":
		legend.text+="RGB: componentes culturales 1, 2 y 3; los seis se consultan en el panel."
	elif value.get("kind")=="text":
		legend.text+=str(value.get("text",""))
	elif shown_layer in ["states","peoples","religions"]:
		legend.text+="Colores de entidades Go. Selecciona para ver nombre e ID. Tierra sin entidad conserva el color físico."
	elif value.get("kind")=="swatches":
		var names := PackedStringArray()
		for item: Array in value.get("items",[]): names.append(str(item[1]))
		legend.text+=", ".join(names)
	else:
		legend.text+="Color físico por elevación, temperatura y precipitación. Sombreado de pendientes."

func _post_draw() -> void:
	if current==null or not bench_ready: return
	if metrics.draw(current.year):
		# Pause verifies exact current Go state; benchmark interval already ended.
		playing=false
		source.pause()
		_finish_benchmark.call_deferred()

func _finish_benchmark() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while source.busy and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	var years := source.years()
	if not years.is_empty():
		var value := source.frame(years[-1])
		metrics.record("verified_pause",{"year":value.year,"state_sha256":value.state_digest,"digest_mode":value.digest_mode,"exact":value.state_digest!=""})
	metrics.file.flush()
	if options.has("screenshot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(options.screenshot))
	_close(0 if not source.busy and not _failure else 1)

func _export_smoke() -> void:
	if _smoke_start==-2147483648: _smoke_start=current.year
	if current.year<_smoke_start+3:
		source.advance(1)
	elif not _smoke_pausing:
		_smoke_pausing=true
		source.pause()
	else:
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(options.expected)))
		var success: bool = current.year==int(expected.get("year")) and current.state_digest==expected.get("stateSHA256") and current.state_digest!=""
		var file := FileAccess.open(str(options["smoke-out"]),FileAccess.WRITE)
		file.store_line(JSON.stringify({"ok":success,"year":current.year,"state_sha256":current.state_digest,"pid":OS.get_process_id(),"go_pid":source._pid,"mode":"functional; no GPU/FPS measurement"}))
		file.close()
		_close(0 if success else 1)

func _fail(message: String) -> void:
	_failure=true
	playing=false
	status.text="ERROR · "+message
	metrics.record("error",{"message":message})
	if benchmark or options.has("smoke-out"): _close(1)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: _close(0)

func _close(code: int) -> void:
	if _closing: return
	_closing=true
	if worker!=null:
		worker.wait_to_finish()
		worker=null
	for task: int in _release_tasks: WorkerThreadPool.wait_for_task_completion(task)
	_release_tasks.clear()
	if source!=null: source.close()
	get_tree().quit(code)
