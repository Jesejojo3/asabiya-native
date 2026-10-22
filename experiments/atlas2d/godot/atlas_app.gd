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
var layer_ids := ["terrain","states","population","peoples","cultures","religions","biomes","technology"]
var layer_names := ["Terreno","Política · estados","Densidad de población","Pueblos","Cultura · componentes 1–3","Religiones","Biomas","Tecnología"]
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
	_build_ui()
	if benchmark and DisplayServer.get_name()=="headless":
		_fail("La captura de FPS necesita una ventana real. Usa --smoke-out para una comprobación headless.")
		return
	RenderingServer.frame_post_draw.connect(_post_draw)
	if benchmark:
		metrics.open(str(options["bench-out"]),float(options.get("seconds","30")),{
			"schema":"asabiya/atlas2d-measure-v1","godot":Engine.get_version_info(),
			"os":OS.get_name(),"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
			"renderer":RenderingServer.get_current_rendering_method(),"pid":OS.get_process_id(),
			"size":str(DisplayServer.window_get_size()),"vsync_requested":"disabled","scene":"procedural",
			"target_hardware_verified":false,"headless":DisplayServer.get_name()=="headless",
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
	play_button=_button(toolbar,"▶ Reproducir",func(): playing=true; review_year=-2147483648)
	pause_button=_button(toolbar,"Ⅱ Pausar y verificar",_pause)
	speed=OptionButton.new()
	for item: String in ["1 año/s","5 años/s","20 años/s","Máximo"]: speed.add_item(item)
	speed.selected=1
	toolbar.add_child(speed)
	layer_choice=OptionButton.new()
	for item: String in layer_names: layer_choice.add_item(item)
	layer_choice.selected=1
	layer_choice.item_selected.connect(func(index: int):
		desired_layer=layer_ids[index]
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
	panel.custom_minimum_size.x=310
	panel.size_flags_horizontal=Control.SIZE_FILL
	split.add_child(panel)
	inspector=RichTextLabel.new()
	inspector.size_flags_vertical=Control.SIZE_EXPAND_FILL
	inspector.text="Arrastra para desplazar. Rueda para acercar.\nSelecciona una provincia.\n\nGo calcula la historia; este cliente la observa."
	panel.add_child(inspector)
	legend=Label.new()
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(legend)
	chronicle=RichTextLabel.new()
	chronicle.custom_minimum_size.y=150
	panel.add_child(chronicle)
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)

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
	current=null
	world=null
	map.world=null
	map.frame=null
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
	source.status_changed.connect(func(message: String):
		if message!="": status.text=message)
	source.request_failed.connect(func(op: String,code: String,message: String): _fail(op+" · "+code+" · "+message))
	if not source.start(): _fail(source.last_error)

func _receive_frame() -> void:
	if not source.is_fast_forward(): source.stop_live() # Backpressure: publish this year before requesting the next.
	var years := source.years()
	if years.is_empty(): return
	var value := source.frame(years[-1])
	if benchmark and not initial_prepared:
		initial_prepared=true
		var count := int(options.get("year","0"))
		if count>0:
			preparing=true
			source.start_fast_forward(count,100)
	if preparing:
		status.text="Preparación explícita del benchmark: %d · no se presentan todos los años intermedios" % source.calculated_year
		queue.clear()
		if not source.is_fast_forward(): preparing=false
	queue.append(value)
	received_us[value.get_instance_id()]=Time.get_ticks_usec()

func _process(_delta: float) -> void:
	if source==null or _closing: return
	source.poll()
	if source.last_error!="" and not _failure:
		_fail(source.last_error)
		return
	if worker!=null and not worker.is_alive():
		var packet: Dictionary=worker.wait_to_finish()
		worker=null
		var publication: HistoryFrame=packet.frame
		# Review and live publications are explicitly separate views of the same Go data.
		if packet.layer!=desired_layer:
			queue.push_front(publication)
		elif review_year==-2147483648 or publication.year==review_year:
			var upload_ms := map.publish(packet)
			current=publication
			shown_layer=packet.layer
			_update_legend(packet.legend)
			metrics.publication_us=int(received_us.get(current.get_instance_id(),Time.get_ticks_usec()))
			received_us.erase(current.get_instance_id())
			metrics.updates+=1
			metrics.record("map_update",{"year":current.year,"projection_ms":packet.projection_ms,"upload_ms":upload_ms,"layer":shown_layer,"state_sha256":current.state_digest,"digest_mode":current.digest_mode})
			_update_panel()
			_refresh_review()
	if worker==null and not queue.is_empty() and world!=null:
		var next: HistoryFrame=queue.pop_front()
		worker=Thread.new()
		worker.start(AtlasProjection.layer.bind(world,next,desired_layer))
	if options.has("smoke-out") and current!=null and source.can_advance() and worker==null and queue.is_empty():
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
		if benchmark: rate=0
		next_year_us=Time.get_ticks_usec()+(int(1000000.0/rate) if rate>0 else 0)
		source.start_live(0)
	if bench_ready and metrics.started_us>0:
		var elapsed := (Time.get_ticks_usec()-metrics.started_us)/1000000.0
		if not options.has("no-pan"):
			map.target_center=Vector2(world.width*(0.5+sin(elapsed*0.2)*0.15),world.height*(0.5+sin(elapsed*0.12)*0.08))
		if elapsed>_next_selection:
			_next_selection=elapsed+1.0
			map.select_at(map.size*0.5)
	init_button.disabled=source.busy or playing
	step_button.disabled=not source.can_advance() or playing or worker!=null or not queue.is_empty()
	play_button.disabled=not source.connected or preparing
	pause_button.disabled=not source.connected
	review.disabled=playing or source.busy or worker!=null

func _step() -> void:
	playing=false
	review_year=-2147483648
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
	query_key=""
	_update_panel()
	metrics.record("selection_local",{"ms":(Time.get_ticks_usec()-started)/1000.0,"id":id,"year":current.year if current!=null else 0})
	metrics.selection_us=started

func _update_panel() -> void:
	if current==null or world==null: return
	var fingerprint := "SHA diferido explícito; pausa para verificar" if current.state_digest=="" else current.state_digest
	status.text="Año %d · %s · %.0f habitantes · %.1f FPS · %s\n%s" % [current.year,layer_names[layer_ids.find(shown_layer)],current.world_population,Engine.get_frames_per_second(),"Reproduciendo" if playing else "Pausa / revisión",fingerprint]
	chronicle.text="Crónica Go · últimos 5 de hasta 1000 eventos publicados\n"
	for i in range(maxi(0,current.events.size()-5),current.events.size()):
		var event: Dictionary=current.events[i]
		chronicle.text+="%s · %s\n" % [event.get("year",""),event.get("text",event.get("kind",""))]
	if selected<0 or selected>=world.cell_count(): return
	var id := selected
	var owner: int=current.owner[id]
	var people_id: int=current.people[id]
	var people: Dictionary=current.peoples.get(people_id,{})
	inspector.text="Provincia Go #%d · año %d\n%s\nPoblación provincial: %.2f\nPropietario: %s [ID %d]\nPueblo: %s [ID %d]\nCultura, 6 componentes: %s\nReligión ID: %d\nCapacidad: %.2f\nAltitud lógica: %.0f m\nBioma: %s\n\n" % [id,current.year,"Tierra" if world.is_land(id) else "Océano",current.population[id],current.states.get(owner,{}).get("name","Sin estado"),owner,people.get("name","Sin pueblo"),people_id,str(people.get("culture","No disponible")),current.religion[id],current.carrying[id],world.elevation[id],WorldData.BIOME_NAMES_ES[clampi(world.biome[id],0,9)]]
	inspector.text+="Las cifras y entidades pertenecen al año mostrado. Cultura RGB usa 3 de los 6 componentes reales.\n"
	var key := "%d/%d/%s" % [id,current.year,current.state_digest]
	if not playing and source.can_advance() and source.years()[-1]==current.year and query_key!=key:
		query_key=key
		var request_us := Time.get_ticks_usec()
		source.query_province(id,func(response: Dictionary):
			if current==null or key!=query_key or playing or int(response.get("year",-1))!=current.year: return
			metrics.record("selection_query",{"ms":(Time.get_ticks_usec()-request_us)/1000.0,"id":id,"year":current.year})
			var data: Dictionary=response.get("data",{})
			inspector.text+="\nConsulta Go: cohesión %s · integración %s\nFortificación: %s (índice; no edificios)\nCiudad ID: %s\n" % [str(data.get("cohesion","—")),str(data.get("integration","—")),str(data.get("fortification","—")),str(data.get("cityId","—"))])
		source.query_history(id,func(response: Dictionary):
			if current==null or key!=query_key or playing or int(response.get("year",-1))!=current.year: return
			var records: Array=response.get("data",{}).get("records",[]) if response.get("data",{}).get("records") is Array else []
			inspector.text+="\nPropiedad observada cada 10 años. Últimas %d de %d observaciones:\n" % [mini(12,records.size()),records.size()]
			for entry: Dictionary in records.slice(maxi(0,records.size()-12)):
				inspector.text+="%s · propietario ID %s\n" % [entry.get("year","—"),entry.get("ownerPolityId","—")])
	elif playing:
		inspector.text+="\nPausa para consultar detalle provincial e historial sin mezclar años."

func _update_legend(value: Dictionary) -> void:
	legend.text="Leyenda · "+layer_names[layer_ids.find(shown_layer)]+"\n"
	if value.get("kind")=="ramp":
		legend.text+="Violeta → azul → verde → amarillo → rojo\n%s → %s" % [str(value.get("min","")),str(value.get("max",""))]
	elif shown_layer=="cultures":
		legend.text+="RGB: componentes culturales 1, 2 y 3; los seis se consultan en el panel."
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
	if source!=null: source.close()
	get_tree().quit(code)
