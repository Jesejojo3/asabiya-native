extends SceneTree
var checks := 0
var failures := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: printerr("FAIL ", text)
func _initialize() -> void: call_deferred("_run")
func _wait(bridge: BridgeSource, condition: Callable) -> bool:
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		bridge.poll()
		if condition.call(): return true
		if bridge._stopped(): return false
		await process_frame
	return false
func _new_source(server: String) -> BridgeSource:
	var bridge := BridgeSource.new(null,server)
	bridge.world_config = {"seed":"throughput-integrity","width":24,"height":16,"detail":4,"landFraction":0.33}
	return bridge
func _run() -> void:
	_test_columns()
	var raw := OS.get_cmdline_user_args()
	var server := ""
	for i in range(raw.size()-1):
		if raw[i] == "--server": server = raw[i+1]
	check(server != "", "real server required")
	if server != "": await _test_fast(server)
	print("Annual throughput: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_columns() -> void:
	var world := WorldData.new()
	world.width=4; world.height=3
	world.header={"world":{"digest":"fixture"}}
	var rows := []
	var cols := {"id":[],"ownerPolityId":[],"peopleId":[],"religionId":[],"population":[],"carryingCapacity":[],"fortification":[],"era":[]}
	for i in 12:
		var p := {"id":i,"ownerPolityId":i%3,"peopleId":1,"religionId":-1,"population":float(i*10),"carryingCapacity":float(i*20),"fortification":0.0,"era":i%8}
		rows.append(p)
		for key in cols: cols[key].append(p[key])
	var base := {"schema":"asabiya/map-state-v1","worldSHA256":"fixture","stateSHA256":"same","year":-9000,"provinces":rows}
	var column: Dictionary=base.duplicate(true)
	column["schema"]="asabiya/map-columns-state-v1";column["provinces"]=cols
	var a:=NativeFrameDecoder.new(world)
	var b:=NativeFrameDecoder.new(world)
	var x:=a.consume(base,false)
	var y:=b.consume(column,false)
	check(x!=null and y!=null,"legacy and column snapshots decode")
	check(x.owner==y.owner and x.population==y.population and x.technology==y.technology and x.world_population==y.world_population,"lossless numeric columns")
	var old_pop:=y.population.duplicate()
	var delta:= {"schema":"asabiya/map-columns-delta-v1","fromYear":-9000,"year":-8999,"stateSHA256":"next","provinces":{}}
	for key in cols: delta["provinces"][key]=[cols[key][2]]
	delta["provinces"]["population"][0]=123.5
	var next:=b.consume(delta,true)
	check(next!=null and is_equal_approx(next.population[2],123.5),"sparse columns update province")
	check(y.population==old_pop,"prior frame remains immutable")
	var broken: Dictionary=delta.duplicate(true)
	broken["fromYear"]=-8999;broken["year"]=-8998;broken["provinces"]["era"]=[]
	check(b.consume(broken,true)==null,"truncated column is rejected")

func _test_fast(server: String) -> void:
	var a:=_new_source(server)
	var b:=_new_source(server)
	check(a.start() and b.start(),"independent sessions start")
	var ready_a: bool=await _wait(a,func():return a.can_advance() and not a.years().is_empty())
	var ready_b: bool=await _wait(b,func():return b.can_advance() and not b.years().is_empty())
	check(ready_a and ready_b,"real initial frames load")
	if not ready_a or not ready_b: a.close();b.close();return
	check(a._map_view=="map-columns-v1" and b._map_view=="map-columns-v1","new view negotiated through catalog")
	var initial:int=a.years()[0]
	var shown:Array=[]
	b.frames_changed.connect(func():shown.append(b.years()[-1]))
	for i in 125:
		a.advance(1)
		var advanced:bool=await _wait(a,func():return a.can_advance() and a.years()[-1]==initial+i+1)
		check(advanced,"observation publishes atomic year "+str(i))
		if not advanced: a.close();b.close();return
	b.start_fast_forward(125,25)
	var completed:bool=await _wait(b,func():return b.can_advance() and not b.is_fast_forward())
	check(completed,"explicit fast-forward completes")
	check(shown==[initial+25,initial+50,initial+75,initial+100,initial+125],"only actual configured visual states are published")
	var final_a:HistoryFrame=a.frame(initial+125)
	var final_b:HistoryFrame=b.frame(initial+125)
	check(final_a!=null and final_b!=null and final_a.state_digest==final_b.state_digest,"fast-forward and observation digests match")
	if final_a!=null and final_b!=null:check(final_a.population==final_b.population and final_a.events==final_b.events,"population and retained events match")
	var replay:Dictionary={}
	a.request("get_replay",{},func(r:Dictionary):replay["a"]=r["data"])
	b.request("get_replay",{},func(r:Dictionary):replay["b"]=r["data"])
	var got_a:bool=await _wait(a,func():return replay.has("a"))
	var got_b:bool=await _wait(b,func():return replay.has("b"))
	check(got_a and got_b and replay["a"]==replay["b"],"all commands and RNG positions match")
	b.start_fast_forward(1000,50)
	var progressed:bool=await _wait(b,func():return b.calculated_year>=initial+130)
	check(progressed,"progress reports calculated years separately")
	b.pause()
	var paused:bool=await _wait(b,func():return b.can_advance() and not b.is_fast_forward())
	check(paused and b.years()[-1]<initial+1125,"pause stops before requested total and publishes a complete year")
	var stopped_year:int=b.years()[-1]
	for i in 10:b.poll();await process_frame
	check(b.years()[-1]==stopped_year,"pause never silently continues calculating")
	var query:Dictionary={}
	b.query_province(0,func(r:Dictionary):query["value"]=r)
	var queried:bool=await _wait(b,func():return not query.is_empty())
	check(queried,"queries work after fast-forward pause")
	b.start_fast_forward(1000,50)
	var pid:int=b._pid
	var request_id:int=b._next_id
	OS.kill(pid)
	var failed:bool=await _wait(b,func():return b._stopped())
	check(failed and not b.is_live(),"transport loss terminates fast scheduling")
	check(b._next_id==request_id and b._outgoing.is_empty(),"uncertain fast advance is never retried")
	await a.shutdown()
	b.close()
	check(a._thread==null and b._thread==null,"all session workers are joined")
