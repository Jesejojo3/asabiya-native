extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	_test_fragments()
	_test_frames()
	_test_layer_inputs()
	print("Deep publication: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func _test_fragments() -> void:
	var line := (JSON.stringify({"text":"Historia · años 🌍","n":1})+"\n").to_utf8_buffer()
	# Split at every byte, including inside multibyte UTF-8 and before LF.
	for split in range(1,line.size()):
		var buffer := LocalResponseBuffer.new()
		buffer.append(line.slice(0,split))
		check(not buffer.complete and buffer.error=="","partial response stays pending")
		buffer.append(line.slice(split))
		check(buffer.complete and JSON.parse_string(buffer.take_text())["text"]=="Historia · años 🌍","fragmented response decodes exactly once")
		check(not buffer.complete and buffer.bytes.is_empty(),"response storage resets")
	var single := LocalResponseBuffer.new()
	for b in line: single.append(PackedByteArray([b]))
	check(single.complete and single.error=="","one-byte reads")
	for bad in ["{}\n{}\n","{}\ntrailing","\n\n"]:
		var buffer := LocalResponseBuffer.new()
		buffer.append(bad.to_utf8_buffer())
		check(buffer.error!="" and not buffer.complete,"extra record rejected without waiting")
	var bounded := LocalResponseBuffer.new()
	bounded.limit=3
	bounded.append("1234".to_utf8_buffer())
	check(bounded.error!="" and bounded.bytes.is_empty(),"message bound before allocation")
func _test_frames() -> void:
	var world := WorldData.new()
	world.width=2;world.height=2
	world.header={"world":{"digest":"world"}}
	var rows:=[]
	for i in 4: rows.append({"id":i,"population":float(i),"carryingCapacity":float(i*2)})
	var snapshot:Dictionary={"schema":"asabiya/map-state-v1","year":1,"worldSHA256":"world","stateSHA256":"a".repeat(64),"provinces":rows}
	snapshot["entities"]={"polity":[{"id":1,"fields":{"metric":0.0}}]}
	var decoder:=NativeFrameDecoder.new(world)
	var first:=decoder.consume(snapshot,false)
	check(first!=null,"exact snapshot accepted")
	var original:=first.population.duplicate()
	var patch:Dictionary={"worldPopulation":128.5,"schema":"asabiya/map-fields-delta-v1","fromYear":1,"year":2,"stateSHA256":"b".repeat(64),"provinces":{
		"ownerPolityId":{"id":[1],"values":[7]},"peopleId":{"id":[1],"values":[8]},"religionId":{"id":[1],"values":[9]},
		"population":{"id":[1],"values":[123.5]},"carryingCapacity":{"id":[2],"values":[456.25]},"fortification":{"id":[3],"values":[0.25]},"era":{"id":[0],"values":[5]}}}
	patch["entityUpserts"]={"polity":[{"id":1,"fields":JSON.parse_string('{"metric":-0.0}')}]}
	var second:=decoder.consume(patch,true)
	check(second!=null and second.owner[1]==7 and second.people[1]==8 and second.religion[1]==9,"integer fields decoded")
	check(second.population[1]==123.5 and second.carrying[2]==456.25 and decoder.fortification[3]==0.25 and is_equal_approx(second.technology[0],5.0/7.0),"numeric fields decoded")
	check(second.world_population==128.5,"Go aggregate matches original cell-order sum")
	var entity_bits:=PackedFloat64Array([second.entity_records["polity"][1]["metric"]]).to_byte_array()
	check((entity_bits[7]&128)!=0 and first.entity_records["polity"][1]["metric"]==0.0,"authoritative entity upsert preserves negative zero")
	check(first.population==original and first.owner[1]==0 and first.technology[0]==0.0,"prior arrays remain immutable")
	var broken:Dictionary=patch.duplicate(true)
	broken["fromYear"]=2;broken["year"]=3
	broken["provinces"]["era"]["values"]=[]
	check(decoder.consume(broken,true)==null and decoder.year==2 and decoder.population==second.population,"invalid patch leaves baseline intact")
	var malformed:=patch.duplicate(true);malformed["provinces"]=[]
	var strict:=NativeFrameDecoder.new(world);strict.consume(snapshot,false)
	check(strict.consume(malformed,true)==null and strict.year==1,"field container must be a dictionary")
	var deferred:Dictionary={"schema":"asabiya/map-fields-delta-v1","fromYear":2,"year":3,"stateSHA256":"","digestMode":"deferred-v1","provinces":{}}
	var third:=decoder.consume(deferred,true)
	check(third!=null and third.state_digest=="" and third.digest_mode=="deferred-v1","deferred fingerprint stays explicitly absent")
	for invalid in [null,"","a".repeat(63),"G".repeat(64)]:
		var bad:Dictionary=snapshot.duplicate(true)
		bad["stateSHA256"]=invalid
		check(NativeFrameDecoder.new(world).consume(bad,false)==null,"malformed exact SHA rejected")
	var bad:Dictionary=snapshot.duplicate(true)
	bad["digestMode"]="deferred-v1";bad["stateSHA256"]=""
	check(NativeFrameDecoder.new(world).consume(bad,false)==null,"snapshot may never defer SHA")
	var bridge:=BridgeSource.new()
	bridge._on_catalog({"data":{"mapColumnsV1":true,"entityChangesV1":true,"mapFieldChangesV1":true,"digestCheckpointsV1":25}})
	check(bridge._advance_payload().get("provinceMode")=="changed-fields-v1" and not bridge._advance_payload().has("digestMode"),"negotiated fields retain annual SHA")
	bridge._live_running = true
	check(bridge._advance_payload().get("digestMode") == "checkpoint-v1", "fluid live playback explicitly requests checkpoints")
	bridge._live_running = false
	check(not bridge._advance_payload().has("digestMode"), "individual steps retain exact SHA")
	var legacy := BridgeSource.new()
	legacy._on_catalog({"data":{"mapColumnsV1":true}})
	legacy._live_running = true
	check(not legacy._advance_payload().has("digestMode"), "old servers fall back to annual SHA")
	legacy.close()
	bridge.close()

func _test_layer_inputs() -> void:
	var world:=WorldData.new()
	world.width=2;world.height=2
	world.land_cells=PackedInt32Array([0,1,2,3])
	var a:=HistoryFrame.new()
	a.owner=PackedInt32Array([1,1,0,0])
	a.states={1:{"rgb":Color.RED,"ruler":"Old"}}
	a.people=PackedInt32Array([2,2,2,2])
	a.peoples={2:{"rgb":Color.GREEN,"culture":[0.1,0.2,0.3,0.4,0.5,0.6],"family":1}}
	var old:=MapLayers.signature("states",world,a)
	var image:=MapLayers.build("states",world,a)
	a.states[1]["ruler"]="New"
	check(MapLayers.signature("states",world,a)==old and MapLayers.build("states",world,a)==image,"unrelated ruler changes do not rebuild identical overlay")
	a.states[1]["rgb"]=Color.BLUE
	check(MapLayers.signature("states",world,a)!=old and MapLayers.build("states",world,a)!=image,"state color invalidates overlay")
	var culture:=MapLayers.signature("cultures",world,a)
	a.peoples[2]["culture"]=[0.7,0.2,0.3,0.4,0.5,0.6]
	check(MapLayers.signature("cultures",world,a)!=culture,"cultural axes invalidate overlay")
	var language:=MapLayers.signature("languages",world,a)
	a.peoples[2]["family"]=3
	check(MapLayers.signature("languages",world,a)!=language,"language family invalidates overlay")
	var newer:=WorldData.new()
	check(MapLayers.signature("states",newer,a)!=MapLayers.signature("states",world,a),"new geography invalidates overlay")
