extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	_test_recoverable_queries()
	_test_busy_query_error()
	_test_terminal_failures()
	_test_integrity()
	var args := OS.get_cmdline_user_args()
	var server := ""
	for i in range(args.size() - 1):
		if args[i] == "--server":
			server = args[i + 1]
	check(server != "", "a real Go server is required")
	if server != "":
		await _test_real_sessions(server)
	print("Bridge stability: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _stub() -> BridgeSource:
	var bridge := BridgeSource.new(null, "not-launched")
	bridge.connected = true
	bridge._session = 2
	var frame := HistoryFrame.new()
	frame.year = 7
	frame.state_digest = "retained"
	bridge._frames[7] = frame
	bridge._years = PackedInt32Array([7])
	return bridge


func _id(bridge: BridgeSource) -> String:
	return str(bridge._next_id - 1)


func _error(id: String, code: String) -> Dictionary:
	return {"schema":BridgeSource.PROTOCOL,"id":id,"session":2,"ok":false,
		"error":{"code":code,"message":"fixture rejection"}}


func _test_recoverable_queries() -> void:
	for op: String in ["get_province","get_province_history","get_entity","list_entities","get_historical_layer","get_replay","get_status"]:
		for code: String in ["not_found","invalid_arguments","not_ready","unknown_operation"]:
			var bridge := _stub()
			var calls := {"failed_callback":0,"success":0}
			var errors: Array = []
			var messages: Array[String] = []
			bridge.request_failed.connect(func(operation: String, error_code: String, message: String): errors.append([operation,error_code,message]))
			bridge.status_changed.connect(func(text: String): messages.append(text))
			bridge.request(op, {}, func(_response: Dictionary): calls["failed_callback"] += 1)
			var rejected_id := _id(bridge)
			bridge.request("get_province", {"id":0}, func(_response: Dictionary): calls["success"] += 1)
			var next_id := _id(bridge)
			bridge._outgoing.clear()
			bridge._push(_error(rejected_id, code))
			bridge.poll()
			check(bridge.connected and not bridge._stopped() and bridge.can_advance(), "%s/%s preserves the session" % [op,code])
			check(bridge._pending_ops.has(next_id) and bridge._pending.has(next_id) and not bridge._pending_ops.has(rejected_id), "only the rejected request is released")
			check(errors == [[op,code,"fixture rejection"]] and messages.size() == 1 and code in messages[0], "recoverable error has an explicit signal and user-facing status")
			check(calls["failed_callback"] == 0 and bridge.frame(7).state_digest == "retained", "failed queries do not invoke success callbacks or alter frames")
			bridge._push({"schema":BridgeSource.PROTOCOL,"id":next_id,"session":2,"ok":true,"data":{"id":0}})
			bridge.poll()
			check(calls["success"] == 1 and bridge.connected and bridge._pending.is_empty() and bridge._pending_ops.is_empty(), "a later query succeeds after the rejection")
			bridge.close()


func _test_busy_query_error() -> void:
	var bridge := _stub()
	bridge._live_running = true
	bridge._live_advance_pending = true
	bridge.busy = true
	bridge._remaining = 3
	bridge.request("advance", {"view":"map"})
	var advance_id := _id(bridge)
	bridge.request("get_entity", {"kind":"people","id":-1})
	var query_id := _id(bridge)
	bridge._push(_error(query_id, "not_found"))
	bridge.poll()
	check(bridge.busy and bridge._live_advance_pending and bridge._remaining == 3, "query rejection does not release or cancel an unrelated annual request")
	check(bridge._pending_ops.has(advance_id) and bridge._outgoing.size() == 2, "query rejection does not enqueue another annual request")
	bridge.close()


func _test_terminal_failures() -> void:
	for code: String in ["stale_session","invalid_json","invalid_request","future_unknown_error"]:
		var bridge := _stub()
		bridge.start_live(0)
		bridge.request("get_province", {"id":0})
		bridge._push(_error(_id(bridge), code))
		bridge._push({"_connected":true})
		bridge.poll()
		check(bridge._stopped() and not bridge.connected and not bridge.is_live() and bridge._outgoing.is_empty(), "critical error stops the session and discards later replies")
		check(bridge.frame(7).state_digest == "retained", "terminal failure retains the last valid frame")
		bridge.close()
	var transport := _stub()
	transport.start_live(0)
	transport.poll()
	var next_id: int = transport._next_id
	transport._push({"_error":"annual response timed out; acceptance unknown"})
	transport._push({"_connected":true})
	transport.poll()
	transport.poll()
	transport.request("advance", {"view":"map"})
	check(transport._stopped() and transport._next_id == next_id and transport._outgoing.is_empty(), "uncertain annual result never retries or restarts")
	transport.close()
	var rejected := _stub()
	rejected.request("advance", {"view":"map"})
	rejected._push(_error(_id(rejected), "invalid_arguments"))
	rejected.poll()
	check(rejected._stopped() and rejected._outgoing.is_empty(), "query recovery policy never swallows an annual rejection")
	rejected.close()


func _test_integrity() -> void:
	var request := {"id":"9","op":"get_province"}
	var valid := {"schema":BridgeSource.PROTOCOL,"id":"9","session":2,"ok":true,"data":{}}
	check(BridgeSource._response_integrity_error(valid, request, 2) == "", "valid response passes integrity")
	for change: Dictionary in [{"schema":"other"},{"id":"10"},{"session":3},{"session":2.5},{"session":"2"},{"ok":1}]:
		var response: Dictionary = valid.duplicate(true)
		response.merge(change, true)
		check(BridgeSource._response_integrity_error(response, request, 2) != "", "schema, request, exact session and result types remain mandatory")
	var malformed := _error("9", "not_found")
	malformed["error"] = {"message":"missing code"}
	check(BridgeSource._response_integrity_error(malformed, request, 2) != "", "malformed error cannot be classified as recoverable")
	check(BridgeSource._response_integrity_error(valid, {}, 2) != "", "unsolicited response is rejected")
	for op: String in ["create_world","start_history"]:
		var created: Dictionary = valid.duplicate(true)
		created["session"] = 3
		check(BridgeSource._response_integrity_error(created, {"id":"9","op":op}, 2) == "", "successful initialization increments generation exactly once")
		check(BridgeSource._response_integrity_error(_error("9","invalid_arguments"), {"id":"9","op":op}, 2) == "", "rejected initialization retains its generation")


func _wait_for(bridge: BridgeSource, condition: Callable, timeout_ms: int = 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		bridge.poll()
		if condition.call():
			return true
		if bridge._stopped():
			return false
		await process_frame
	return false


func _test_real_sessions(server: String) -> void:
	var bridge := BridgeSource.new(null, server)
	bridge.world_config = {"seed":"bridge-stability","width":24,"height":16,"detail":4,"landFraction":0.33}
	var errors: Array = []
	bridge.request_failed.connect(func(op: String, code: String, message: String): errors.append([op,code,message]))
	for cycle: int in range(3):
		check(bridge.start(), "real server starts on cycle %d" % cycle)
		var pid: int = bridge._pid
		check(not bridge.start() and bridge._pid == pid, "duplicate start cannot replace the owned process")
		var ready: bool = await _wait_for(bridge, func(): return not bridge.years().is_empty() and bridge.can_advance())
		check(ready, "real geography and initial compact frame load on cycle %d: %s" % [cycle,bridge.last_error])
		if not ready:
			bridge.close()
			return
		check(not bridge.is_live() and bridge._remaining == 0 and not bridge._live_advance_pending, "restart clears old annual scheduling")
		var initial_year: int = bridge.years()[0]
		var initial_digest: String = bridge.frame(initial_year).state_digest
		var generation: int = bridge._session
		var callbacks := {"bad":0,"province":0,"replay":{}}
		var errors_before := errors.size()
		bridge.query_entity("people", 999999, func(_r: Dictionary): callbacks["bad"] += 1)
		bridge.query_province(999999, func(_r: Dictionary): callbacks["bad"] += 1)
		bridge.request("get_historical_layer", {"year":initial_year - 1000}, func(_r: Dictionary): callbacks["bad"] += 1)
		bridge.request("get_province", {"id":"bad"}, func(_r: Dictionary): callbacks["bad"] += 1)
		bridge.query_province(0, func(_r: Dictionary): callbacks["province"] += 1)
		bridge.request("get_replay", {}, func(r: Dictionary): callbacks["replay"] = r["data"])
		var queried: bool = await _wait_for(bridge, func(): return not (callbacks["replay"] as Dictionary).is_empty())
		check(queried and callbacks["province"] == 1 and callbacks["bad"] == 0, "real valid queries succeed after not_found and invalid_arguments")
		check(errors.size() == errors_before + 4, "all real recoverable query failures are reported")
		if not queried:
			bridge.close()
			return
		check(bridge._pid == pid and OS.is_process_running(pid) and bridge._session == generation, "recoverable failures preserve PID and generation")
		check(callbacks["replay"]["finalSHA256"] == initial_digest and callbacks["replay"]["finalYear"] == initial_year, "queries do not advance or alter causal history")
		bridge.advance(1)
		var advanced: bool = await _wait_for(bridge, func(): return bridge.years().has(initial_year + 1) and bridge.can_advance())
		check(advanced and bridge.years().size() == 2, "one explicit advance still publishes exactly one year after errors")
		bridge._remaining = 7
		bridge._since_publication = 3
		bridge._live_advance_pending = true
		await bridge.shutdown()
		check(not OS.is_process_running(pid) and bridge._pid == -1 and bridge._thread == null, "graceful shutdown reaps the real server and worker")
		check(bridge._pending.is_empty() and bridge._pending_ops.is_empty() and bridge._outgoing.is_empty() and bridge.years().is_empty(), "shutdown releases requests and cached frames")
		bridge.close()
	check(bridge.start(), "real server starts for interrupted annual request")
	var ready: bool = await _wait_for(bridge, func(): return bridge.can_advance() and not bridge.years().is_empty())
	check(ready, "interruption scenario initializes")
	if ready:
		bridge.start_live(0)
		bridge.poll()
		var pid: int = bridge._pid
		var next_id: int = bridge._next_id
		OS.kill(pid)
		var failed: bool = await _wait_for(bridge, func(): return bridge._stopped())
		check(failed and not bridge.connected and not bridge.is_live(), "real process loss ends live scheduling safely")
		for i in range(5):
			bridge.poll()
			await process_frame
		check(bridge._pid == pid and bridge._next_id == next_id and bridge._outgoing.is_empty(), "real uncertain annual request is neither retried nor restarted")
	bridge.close()
