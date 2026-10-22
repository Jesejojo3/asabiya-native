extends SceneTree
## Sprint 01 integrity contracts: the Atlas observes Go and never changes it.
## Run: godot --headless --path build/atlas2d/project --script res://test_integrity.gd -- --server=ABS --small
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

func until(condition: Callable, label: String, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline: await process_frame
	var success: bool=condition.call()
	require(success,"Timeout: "+label)
	return success

func idle() -> bool:
	return app.current!=null and not app.source.busy and app.worker==null and app.queue.is_empty() and not app.playing

func ask(op: String, payload: Dictionary) -> Dictionary:
	var reply := {}
	app.source.request(op,payload,func(value: Dictionary): reply.merge(value))
	await until(func(): return not reply.is_empty(),"Go "+op)
	return reply

func replay() -> Dictionary:
	return (await ask("get_replay",{})).get("data",{})

func _run() -> void:
	app=load("res://atlas.tscn").instantiate()
	root.add_child(app)
	if not await until(idle,"initial publication"):
		finish()
		return
	var w: WorldData=app.world
	var first: HistoryFrame=app.current
	var first_world: String=first.world_digest
	var first_state: String=first.state_digest
	require(first_state!="","Initial publication carries an exact SHA")

	# Advance three years and pause: consecutive publications, exact pause.
	app.speed.selected=3
	app.playing=true
	await until(func(): return app.current.year>=first.year+3,"three years")
	app._pause()
	await until(idle,"pause settles")
	var years: PackedInt32Array=app.source.years()
	for k in range(1,years.size()): require(years[k]==years[k-1]+1,"Publications are consecutive without duplicates: %s" % years)
	var paused: HistoryFrame=app.current
	require(paused.state_digest!="","Pause publishes an exact SHA")
	var proof: Dictionary=await replay()
	require(int(proof.get("finalYear",0))==paused.year and str(proof.get("finalSHA256",""))==paused.state_digest,"Displayed year/SHA equal Go replay proof")

	# Pause really stops: two seconds of frames, no new year or request.
	var before_count := years.size()
	var wait_until := Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<wait_until: await process_frame
	require(app.source.years().size()==before_count and app.current.year==paused.year,"Paused session published no further year")
	var still: Dictionary=await replay()
	require(int(still.finalYear)==paused.year and str(still.finalSHA256)==paused.state_digest,"Go did not advance while paused")

	# Every read-only interaction against the paused state.
	var cell := -1
	for c: int in w.land_cells:
		if paused.owner[c]>0 and paused.people[c]>=0:
			cell=c
			break
	if cell<0: cell=w.land_cells[0]
	for index in app.layer_ids.size():
		if app.layer_choice.is_item_disabled(index): continue
		app.layer_choice.select(index)
		app.layer_choice.item_selected.emit(index)
		await until(func(): return app.shown_layer==app.layer_ids[index] and idle(),"layer "+app.layer_ids[index])
	require(app.layer_choice.is_item_disabled(app.layer_ids.find("economy")),"Unpublished economy layer stays disabled")
	app._selected(cell)
	await until(func(): return app.inspector.get_parsed_text().contains("Consulta Go") and app.inspector.get_parsed_text().contains("Propiedad observada"),"province query and ownership history")
	var province: Dictionary=(await ask("get_province",{"id":cell})).get("data",{})
	require(int(province.get("ownerPolityId",-1))==paused.owner[cell] and is_equal_approx(float(province.get("population",-1)),paused.population[cell]),"Panel owner/population equal Go get_province")
	var owner: int=paused.owner[cell]
	if owner>0:
		require(app.inspector.text.contains("[url=polity:%d]" % owner) or app.inspector.get_parsed_text().contains(AtlasEntities.label(paused,"polity",owner)),"Province panel links its Go owner")
		app._open_link("polity:%d" % owner)
		require(app.tabs.current_tab==1 and app.entity_view.get_parsed_text().contains("Go #%d" % owner),"Entity sheet shows the state ID")
		var record: Dictionary=paused.entity_records.get("polity",{}).get(owner,{})
		require(str(record.get("name",""))==str(paused.states.get(owner,{}).get("name","")),"State layer and entity record share identity")
		var entity: Dictionary=await ask("get_entity",{"kind":"polity","id":owner})
		require(int(entity.get("year",-1))==paused.year,"Entity query answers the displayed year")
		require(str(entity.get("data",{}).get("fields",{}).get("name",""))==str(record.get("name","")),"Published entity equals Go get_entity")
		var found: Array=AtlasEntities.search(paused,str(record.get("name","")),"polity")
		require(found.any(func(item: Array): return int(item[1])==owner),"Search finds the state by its Go name")
	var people_id: int=paused.people[cell]
	if people_id>=0:
		app._open_link("people:%d" % people_id)
		require(app.entity_view.get_parsed_text().contains("Go #%d" % people_id),"People sheet opens")
	app._open_link("polity:999999")
	require(app.entity_view.get_parsed_text().contains("no figura"),"Missing entity is reported, not invented")
	app._entity_previous()
	app.tabs.current_tab=2
	app._refresh_chronicle(true)
	var text: String=app.chronicle.get_parsed_text()
	require(text.contains("de %d acontecimientos" % paused.events.size()),"Chronicle counts the published events")
	for event: Dictionary in paused.events.slice(maxi(0,paused.events.size()-10)):
		if str(event.get("text",""))!="": require(text.contains(str(event.text)),"Chronicle shows Go event text %s" % event.get("id"))
	app.tabs.current_tab=3
	app.search_input.text="a"
	app._refresh_search()
	app.tabs.current_tab=4
	app._refresh_world()
	require(app.world_view.get_parsed_text().contains("%.0f" % paused.world_population),"World panel shows Go population")

	# Historical layer: Go answers a retained year at or before the request.
	var layer: Dictionary=(await ask("get_historical_layer",{"year":first.year})).get("data",{})
	require(int(layer.get("year",paused.year+1))<=first.year,"Historical layer is not newer than requested")
	var retained: HistoryFrame=app.source.frame(int(layer.get("year",-999999)))
	require(retained!=null,"The historical layer year is a retained publication in this test")
	if retained!=null:
		var ids: Array=layer.get("peopleIds",[])
		var cells: Array=layer.get("provinceIds",[])
		var same := true
		for k in cells.size():
			var c := int(cells[k])
			var expected: int=retained.people[c] if retained.population[c]>=1.0 else -1
			if int(ids[k])!=expected: same=false
		require(same,"Historical people layer equals the publication of the same year")
	app.history_year.value=first.year
	app._request_historical()
	await until(func(): return not app.historical.is_empty(),"historical overlay")
	require(app.shown_layer.begins_with("historical:"),"Historical overlay published")
	app._exit_historical()
	await until(func(): return app.historical.is_empty() and idle(),"back to the published year")
	app._review(0)
	await until(func(): return app.current.year==years[0] and idle(),"review older publication")
	app.review_year=-2147483648
	app.queue.append(app.source.frame(app.source.years()[-1]))
	await until(func(): return app.current.year==paused.year and idle(),"back to latest")
	var after: Dictionary=await replay()
	require(int(after.finalYear)==paused.year and str(after.finalSHA256)==paused.state_digest,"Interface operations did not change Go state")
	require(app.source.years().size()==before_count,"Interface operations did not request years")

	# Resume: three more consecutive years, no duplicate publication.
	app.playing=true
	await until(func(): return app.current.year>=paused.year+3,"resume")
	app._pause()
	await until(idle,"second pause")
	years=app.source.years()
	for k in range(1,years.size()): require(years[k]==years[k-1]+1,"Resume kept consecutive years: %s" % years)
	var resumed: Dictionary=await replay()
	require(int(resumed.finalYear)==app.current.year and str(resumed.finalSHA256)==app.current.state_digest,"Resumed state equals Go proof")

	# Determinism: same seed reproduces world and initial state; another seed differs.
	app._initialize()
	await until(idle,"same-seed session")
	require(app.current.world_digest==first_world and app.current.state_digest==first_state,"Same seed reproduces world and initial SHA")
	app.seed_input.text="Asabiya-integridad"
	app._initialize()
	await until(idle,"different-seed session")
	require(app.current.world_digest!=first_world,"Different seed produces a different world")
	finish()

func finish() -> void:
	print("ATLAS INTEGRITY: %d checks, %d failures" % [checks,failures])
	app._close(1 if failures>0 else 0)
