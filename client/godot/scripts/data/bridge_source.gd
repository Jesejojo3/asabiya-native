class_name BridgeSource
extends HistorySource
## One owned Go process and one local TCP protocol: asabiya/local-v1.
## Networking, JSON decoding, and frame construction run on a worker thread.
## Scene nodes and callbacks are touched only by poll() on the graphics thread.

signal world_ready(value: WorldData)
signal request_failed(op: String, code: String, message: String)
signal progress_changed(calculated_year: int, visualized_year: int, remaining: int)
signal command_context_changed(context: Dictionary)
signal command_result_received(result: Dictionary)
signal command_pending_changed(pending: bool)

const PROTOCOL := "asabiya/local-v1"
const EXE_WIN := "asabiya-server.exe"
const MAX_FRAMES := 24
const MAX_RESPONSE_BYTES := 256 * 1024 * 1024

var world: WorldData
var exe := ""
var available := false
var connected := false
var busy := false
var last_error := ""
var engine_info := {"canAdvance": true}
var world_config := {"seed":"Asabiya","width":400,"height":200,"detail":4,"landFraction":0.33}
var source_config: Dictionary = {}
var history_seed := "1"
var tech_catalog: Array = []
var era_names: Array = []
var command_catalog: Dictionary = {}
var _map_view := "map"
var _sparse_entities := false
# Exact fingerprints are required for retained observation frames. The wire
# checkpoint mode remains supported for explicitly opted-in external consumers.
var _digest_checkpoints := false
var _field_changes := false
var _fast_active := false
var _fast_cancel := true
var _fast_progress: Dictionary = {}
var calculated_year := 0
var fast_remaining := 0

var _pid := -1
var _endpoint := ""
var _directory := ""
var _thread: Thread
var _mutex := Mutex.new()
var _stop := false
var _outgoing: Array = []
var _received: Array = []
var _pending := {}
var _pending_ops := {}
var _next_id := 1
var _session := 0
var _frames := {}
var _years := PackedInt32Array()
var _remaining := 0
var _since_publication := 0
var _closing := false
var _paused := false
var _live_running := false
var _live_advance_pending := false
var _live_interval_us := 100000
var _live_due_us := 0

func _init(w: WorldData = null, executable := "") -> void:
	world = w
	exe = executable if executable != "" else find_executable()
	available = exe != ""
	if world != null:
		var config: Dictionary = world.header.get("world", {})
		world_config = {"seed":world.world_seed,"width":world.width,"height":world.height,
			"detail":world.detail,"landFraction":float(config.get("landFraction", 0.33))}
		source_config = world.header.get("source", {})
		history_seed = str(world.header.get("session", {}).get("historySeed", "1"))

static func find_executable() -> String:
	var base := OS.get_executable_path().get_base_dir()
	var dirs := [base, base.path_join("bin")]
	if not OS.has_feature("template"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../../build/bin").simplify_path())
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../../bin").simplify_path())
	for d: String in dirs:
		var path := d.path_join(EXE_WIN)
		if FileAccess.file_exists(path):
			return path
	return ""

func kind() -> String:
	return "bridge" # UI provider category retained; wire protocol is TCP only.

func label() -> String:
	return "Motor Go conectado" if connected else "Motor Go desconectado"

func systems() -> PackedStringArray:
	return PackedStringArray(["history","states","peoples","religions","population",
		"technology","settlements","wars","routes","events","carrying","cellHistory"])

func years() -> PackedInt32Array:
	return _years.duplicate()

func frame(year: int) -> HistoryFrame:
	return _frames.get(year)

func can_advance() -> bool:
	return connected and not busy and not _live_advance_pending and not _closing

func start(_extra_args := PackedStringArray()) -> bool:
	if _thread != null or (_pid > 0 and OS.is_process_running(_pid)):
		last_error = "La sesión anterior debe cerrarse antes de reiniciar el motor."
		return false
	_closing = false
	_stop = false
	_sparse_entities = false
	_digest_checkpoints = false
	_field_changes = false
	connected = false
	busy = false
	_live_running = false
	_live_advance_pending = false
	_remaining = 0
	_since_publication = 0
	_paused = false
	_live_due_us = 0
	last_error = ""
	_fast_active = false
	_fast_cancel = true
	_fast_progress.clear()
	_pending.clear()
	_pending_ops.clear()
	_outgoing.clear()
	_received.clear()
	_session = 0
	_frames.clear()
	_years.clear()
	if not available:
		last_error = "No se encontró %s junto a Asabiya Native." % EXE_WIN
		return false
	busy = true
	_directory = OS.get_user_data_dir().path_join("sessions").path_join("%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		last_error = "No se pudo crear la carpeta local de la sesión."
		busy = false
		return false
	_endpoint = _directory.path_join("endpoint.json")
	_pid = OS.create_process(exe, PackedStringArray(["--port","0","--endpoint-file",_endpoint,
		"--log-file",_directory.path_join("engine.log"),"--parent-pid",str(OS.get_process_id())]), false)
	if _pid <= 0:
		last_error = "No se pudo iniciar el motor Go."
		busy = false
		return false
	_thread = Thread.new()
	var err := _thread.start(_worker)
	if err != OK:
		last_error = "No se pudo iniciar la conexión local."
		OS.kill(_pid)
		_pid = -1
		_thread = null
		busy = false
		return false
	status_changed.emit("Iniciando el motor Go…")
	return true

func _on_connected(_response: Dictionary) -> void:
	connected = true
	var payload := {"world":world_config,"fine":true}
	if not source_config.is_empty():
		payload["source"] = source_config
	request("create_world", payload, _on_created)

func _on_created(response: Dictionary) -> void:
	var summary: Dictionary = response.get("data", {})
	if world != null and str(summary.get("sha256", "")) != str(world.header.get("world", {}).get("digest", "")):
		_fail("El mundo del archivo no coincide con el que generó Go. No se mezclará su historia.")
		return
	status_changed.emit("Preparando el relieve fino del mundo…")
	request("get_catalog", {}, _on_catalog)

func _on_catalog(response: Dictionary) -> void:
	var data: Dictionary = response.get("data", {})
	tech_catalog = data.get("technologies", [])
	era_names = data.get("eras", [])
	command_catalog = {"omens": data.get("omens", []), "parameters": data.get("parameters", [])}
	_map_view = "map-columns-v1" if data.get("mapColumnsV1", false) else "map"
	_sparse_entities = _map_view == "map-columns-v1" and bool(data.get("entityChangesV1", false))
	_field_changes = _map_view == "map-columns-v1" and bool(data.get("mapFieldChangesV1", false))
	request("export_geography", {"directory":_directory.path_join("world")}, _on_geography)

func _on_geography(response: Dictionary) -> void:
	var loaded: WorldData = response.get("_world")
	if loaded == null:
		_fail("No se pudo abrir la geografía exportada por Go.")
		return
	world = loaded
	status_changed.emit("Inicializando las sociedades humanas…")
	# Queue Go initialization before synchronous main-thread scene construction.
	request("start_history", {"historySeed":history_seed,"view":_map_view}, _on_frame)
	world_ready.emit(world)

func _on_frame(response: Dictionary) -> void:
	var publication: HistoryFrame = response.get("_frame")
	if publication == null:
		_fail("El motor devolvió un estado incompatible con la geografía o el calendario.")
		return
	if _remaining <= 0: busy = false
	_store(publication)
	if _remaining > 0 and not _closing:
		_next_advance()
	else:
		busy = false

func _store(publication: HistoryFrame) -> void:
	_frames[publication.year] = publication
	calculated_year = maxi(calculated_year, publication.year) if _fast_active else publication.year
	var ys := PackedInt32Array(_frames.keys())
	ys.sort()
	while ys.size() > MAX_FRAMES:
		_frames.erase(ys[0])
		ys.remove_at(0)
	_years = ys
	frames_changed.emit()
	status_changed.emit("")


func is_live() -> bool:
	return _live_running or _fast_active


func set_live_rate(years_per_second: int) -> void:
	_live_interval_us = 0 if years_per_second == 0 else int(1000000.0 / clampi(years_per_second, 1, 50))
	_live_due_us = Time.get_ticks_usec() + _live_interval_us


func start_live(years_per_second: int) -> void:
	if not connected or _closing or _fast_active: return
	set_live_rate(years_per_second)
	_live_running = true
	_paused = false
	_remaining = 0
	_live_due_us = Time.get_ticks_usec()


func stop_live() -> void:
	_live_running = false
	_mutex.lock()
	_fast_cancel = true
	_mutex.unlock()

func fetch_frame() -> void:
	if not connected: return
	busy = true
	request("get_state", {"view":_map_view}, _on_frame)

func advance(count: int) -> void:
	if not can_advance() or count < 1: return
	stop_live()
	busy = true
	_remaining = clampi(count, 1, 10000)
	_paused = false
	_since_publication = 0
	_next_advance()

func _advance_payload() -> Dictionary:
	var payload: Dictionary = {"view":_map_view}
	if _sparse_entities:
		payload["entityMode"] = "changed"
	if _field_changes:
		payload["provinceMode"] = "changed-fields-v1"
	if _digest_checkpoints:
		payload["digestMode"] = "checkpoint-v1"
	return payload

func _next_advance() -> void:
	if _remaining <= 0:
		fetch_frame()
		return
	if _remaining == 1 and _since_publication == 0:
		_remaining = 0
		request("advance", _advance_payload(), _on_frame)
		return
	request("advance", {"publication":"status"}, func(response: Dictionary) -> void:
		_remaining = maxi(0, _remaining - 1)
		if _paused: return
		_since_publication += 1
		var data: Dictionary = response.get("data", {})
		status_changed.emit("Año %d · quedan %d años del avance solicitado" % [int(data.get("year", 0)), _remaining])
		if _remaining <= 0 or _since_publication >= 50:
			_since_publication = 0
			fetch_frame()
		else:
			_next_advance())

func pause() -> void:
	stop_live()
	_remaining = 0 # One already accepted year finishes atomically.
	_paused = true
	if _fast_active: return
	if connected:
		request("pause", {}, func(_response: Dictionary) -> void:
			fetch_frame())

func refresh_command_context() -> void:
	if not connected or _fast_active or _stop or _closing: return
	request("get_status", {}, func(response: Dictionary) -> void:
		var context: Dictionary = response.get("data", {}).get("commandContext", {})
		if not context.is_empty(): command_context_changed.emit(context))


func submit_command(kind_name: String, arguments: Dictionary) -> void:
	if not connected or busy or _fast_active or _remaining > 0 or _stop or _closing:
		command_result_received.emit({"accepted":false, "error":"La simulación está ocupada o no está conectada. Pausa el avance antes de intervenir."})
		return
	if kind_name not in ["set_sandbox", "change_rules", "cast_omen"]:
		command_result_received.emit({"accepted":false, "error":"Tipo de intervención no permitido."})
		return
	stop_live()
	busy = true
	command_pending_changed.emit(true)
	# The command's sequence, completed year and rules hash must come from Go.
	# Do not trust a cached Godot frame or synthesize a replay sequence.
	request("get_status", {}, func(status_response: Dictionary) -> void:
		var context: Dictionary = status_response.get("data", {}).get("commandContext", {})
		if context.is_empty():
			busy = false
			command_pending_changed.emit(false)
			command_result_received.emit({"accepted":false, "error":"Go no proporcionó un contexto de comando."})
			return
		command_context_changed.emit(context)
		var command := {
			"schema":"asabiya/command-v1", "profile":"native",
			"sequence":int(context.get("nextSequence", 0)),
			"targetYear":int(context.get("year", 0)),
			"expectedRulesSHA256":str(context.get("rulesSHA256", "")),
			"kind":kind_name,
		}
		match kind_name:
			"set_sandbox":
				command["sandbox"] = bool(arguments.get("sandbox", false))
			"change_rules":
				command["values"] = arguments.get("values", {})
			"cast_omen":
				command["omen"] = str(arguments.get("omen", ""))
				command["cell"] = int(arguments.get("cell", -1))
		request("apply_command_status", command, func(result_response: Dictionary) -> void:
			var data: Dictionary = result_response.get("data", {})
			var updated: Dictionary = data.get("commandContext", {})
			if not updated.is_empty(): command_context_changed.emit(updated)
			var result: Dictionary = data.get("result", {})
			command_result_received.emit(result)
			command_pending_changed.emit(false)
			if bool(result.get("accepted", false)):
				# Go invalidated its compact publication baseline. Re-fetch
				# authoritative state; Godot never applies the omen locally.
				fetch_frame()
			else:
				busy = false))


func query_province(id: int, callback: Callable) -> void:
	request("get_province", {"id":id}, callback)

func query_entity(kind_name: String, id: int, callback: Callable) -> void:
	request("get_entity", {"kind":kind_name,"id":id}, callback)

func query_history(id: int, callback: Callable) -> void:
	request("get_province_history", {"id":id}, callback)

func request(op: String, payload: Dictionary = {}, callback := Callable()) -> void:
	if _stop or (_closing and op != "shutdown"): return
	var id := str(_next_id)
	_next_id += 1
	if callback.is_valid(): _pending[id] = callback
	_pending_ops[id] = op
	_mutex.lock()
	_outgoing.append({"schema":PROTOCOL,"id":id,"op":op,"payload":payload})
	_mutex.unlock()

func poll() -> void:
	if _closing or _stopped(): return
	_mutex.lock()
	var replies: Array = _received
	_received = []
	var progress: Dictionary = _fast_progress
	_fast_progress = {}
	_mutex.unlock()
	if not progress.is_empty():
		calculated_year = int(progress["year"])
		fast_remaining = int(progress["remaining"])
		progress_changed.emit(calculated_year, _years[-1] if not _years.is_empty() else calculated_year, fast_remaining)
	for response: Dictionary in replies:
		if response.has("_error"):
			connected = false
			_fail(str(response["_error"]))
			break
		if response.has("_fast_frame"):
			var frame: HistoryFrame = response["_fast_frame"]
			calculated_year = maxi(calculated_year, frame.year)
			if response.get("done", false):
				_fast_active = false
				busy = false
				fast_remaining = 0
			_store(frame)
			progress_changed.emit(calculated_year, frame.year, fast_remaining)
			continue
		if response.has("_connected"):
			_on_connected(response)
			continue
		_session = int(response.get("session", _session))
		var id := str(response.get("id", ""))
		if not _pending_ops.has(id):
			_fail("El motor respondió a una petición que ya no pertenece a esta sesión.")
			break
		var op: String = _pending_ops[id]
		var callback: Callable = _pending.get(id, Callable())
		_pending.erase(id)
		_pending_ops.erase(id)
		if not response.get("ok", false):
			var detail: Dictionary = response.get("error", {})
			var code := str(detail.get("code", ""))
			var message := str(detail.get("message", "El motor rechazó la petición."))
			if _is_recoverable_request_error(op, code):
				_report_request_error(op, code, message)
				if _closing or _stopped(): break
				continue
			_fail(message)
			break
		if callback.is_valid(): callback.call(response)
		if _closing or _stopped(): break
	# Continuous play is wall-clock paced, with at most one complete year in
	# flight. Publish every year, never replay cached frames or batch 10/50-year
	# jumps. A slow calculation lowers the achieved rate; it never queues a burst.
	if _live_running and can_advance() and Time.get_ticks_usec() >= _live_due_us:
		_live_due_us = Time.get_ticks_usec() + _live_interval_us
		_live_advance_pending = true
		busy = true
		request("advance", _advance_payload(), func(response: Dictionary):
			_live_advance_pending = false
			_on_frame(response))

static func _is_query(op: String) -> bool:
	return op in ["get_province", "get_province_history", "get_entity",
		"list_entities", "get_historical_layer", "get_replay", "get_status"]


static func _is_recoverable_request_error(op: String, code: String) -> bool:
	return _is_query(op) and code in ["not_found", "invalid_arguments", "not_ready", "unknown_operation"]


func _report_request_error(op: String, code: String, message: String) -> void:
	last_error = "No se pudo completar la consulta (%s): %s" % [code, message]
	status_changed.emit(last_error)
	request_failed.emit(op, code, message)


func _fail(message: String) -> void:
	stop_live()
	_fast_active = false
	_live_advance_pending = false
	connected = false
	busy = false
	_remaining = 0
	last_error = message
	_pending.clear()
	_pending_ops.clear()
	_mutex.lock()
	_outgoing.clear()
	_stop = true
	_mutex.unlock()
	# Release the owned server after a terminal transport/protocol failure.
	# Never retry an annual operation whose acceptance is uncertain.
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	status_changed.emit(message)

func _push(response: Dictionary) -> void:
	_mutex.lock()
	_received.append(response)
	_mutex.unlock()

func _stopped() -> bool:
	_mutex.lock()
	var value := _stop
	_mutex.unlock()
	return value

static func _response_integrity_error(response: Dictionary, inflight: Dictionary, session: int) -> String:
	if inflight.is_empty() or response.get("schema", "") != PROTOCOL or str(response.get("id", "")) != str(inflight.get("id", "")):
		return "La respuesta no corresponde a la sesión o petición enviada."
	if not response.get("ok") is bool:
		return "El motor envió una respuesta sin resultado válido."
	var op: String = inflight.get("op", "")
	var expected_session := session + 1 if op in ["create_world", "start_history"] and response["ok"] else session
	var generation: Variant = response.get("session")
	if not (generation is int or generation is float) or generation != expected_session:
		return "La respuesta pertenece a otra sesión del motor."
	if not response["ok"]:
		var detail: Variant = response.get("error")
		if not detail is Dictionary or not detail.get("code") is String or not detail.get("message") is String:
			return "El motor envió un error de protocolo incompleto."
	return ""


func _worker() -> void:
	var trace := AnnualTrace.new("worker")
	var request_started := 0
	var deadline := Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(_endpoint) and not _stopped():
		if not OS.is_process_running(_pid) or Time.get_ticks_msec() > deadline:
			_push({"_error":"El motor no publicó su puerto local. Consulta engine.log en " + _directory})
			return
		OS.delay_msec(10)
	if _stopped(): return
	var endpoint_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_endpoint))
	if not endpoint_data is Dictionary or endpoint_data.get("schema", "") != "asabiya/local-endpoint-v1" or endpoint_data.get("protocol", "") != PROTOCOL:
		_push({"_error":"El motor publicó un protocolo local incompatible."})
		return
	var parts: PackedStringArray = str(endpoint_data.get("address", "")).split(":")
	if parts.size() != 2 or parts[0] != "127.0.0.1":
		_push({"_error":"El cliente sólo admite el servidor local 127.0.0.1."})
		return
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", parts[1].to_int()) != OK:
		_push({"_error":"No se pudo conectar con el motor local."})
		return
	var incoming := LocalResponseBuffer.new()
	incoming.limit = MAX_RESPONSE_BYTES
	var pending_bytes := PackedByteArray()
	var sent := 0
	var session := 0
	var inflight: Dictionary = {}
	var ready := false
	var decoder := NativeFrameDecoder.new(world)
	var fast: Dictionary = {}
	while not _stopped():
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_push({"_error":"Se perdió la conexión con Go. La vista recibida se conserva; crea una nueva sesión para reiniciar."})
			break
		if status != StreamPeerTCP.STATUS_CONNECTED:
			if Time.get_ticks_msec() > deadline:
				_push({"_error":"Se agotó el tiempo para conectar con el motor."})
				break
			OS.delay_msec(2)
			continue
		if not ready:
			ready = true
			peer.set_no_delay(true)
			_push({"_connected":true})
		if pending_bytes.is_empty() and inflight.is_empty():
			_mutex.lock()
			if not _outgoing.is_empty(): inflight = _outgoing.pop_front()
			_mutex.unlock()
			if inflight.has("_fast_start"):
				fast = {"job":inflight["id"],"sequence":0,"remaining":inflight["years"],"every":inflight["every"],"since":0,"year":decoder.year}
				inflight = {}
			if inflight.is_empty() and not fast.is_empty():
				_mutex.lock()
				var cancelled := _fast_cancel
				var backlog := _received.size()
				_mutex.unlock()
				if backlog < 2:
					var snapshot: bool = cancelled or int(fast["remaining"]) <= 0 or int(fast["since"]) >= int(fast["every"])
					fast["sequence"] = int(fast["sequence"]) + 1
					inflight = {"schema":PROTOCOL,"id":"ff-%s-%d" % [fast["job"],fast["sequence"]],"op":"get_state" if snapshot else "advance","payload":{"view":_map_view} if snapshot else {"publication":"status"},"_local_fast":true}
			if not inflight.is_empty():
				inflight["session"] = session
				request_started = trace.begin()
				var wire := inflight.duplicate()
				wire.erase("_local_fast")
				pending_bytes = (JSON.stringify(wire) + "\n").to_utf8_buffer()
				sent = 0
				deadline = Time.get_ticks_msec() + 180000
		if not pending_bytes.is_empty():
			var written: Array = peer.put_partial_data(pending_bytes.slice(sent))
			if int(written[0]) != OK:
				_push({"_error":"No se pudo enviar una petición al motor."})
				break
			sent += int(written[1])
			if sent >= pending_bytes.size(): pending_bytes.clear()
		# This is an absolute request deadline, including a slow/trickling peer.
		if not inflight.is_empty() and Time.get_ticks_msec() > deadline:
			_push({"_error":"El motor tardó demasiado. No se repetirá un avance cuyo resultado sea incierto."})
			break
		var count := mini(peer.get_available_bytes(), 1048576)
		if count > 0:
			var chunk: Array = peer.get_partial_data(count)
			if int(chunk[0]) != OK:
				_push({"_error":"No se pudo recibir la respuesta del motor."})
				break
			var raw: PackedByteArray = chunk[1]
			incoming.append(raw)
			if incoming.error != "":
				_push({"_error":incoming.error})
				break
			# Requests are serialized: one complete NDJSON record per response.
			if incoming.complete:
				var parse_started := trace.begin()
				var response_bytes := incoming.bytes.size()
				var value: Variant = JSON.parse_string(incoming.take_text())
				trace.record("json-parse", parse_started, {"bytes":response_bytes})
				if not value is Dictionary:
					_push({"_error":"El motor envió JSON inválido."})
					break
				var response: Dictionary = value
				var integrity_error := _response_integrity_error(response, inflight, session)
				if integrity_error != "":
					_push({"_error":integrity_error})
					break
				var op: String = inflight.get("op", "")
				session = int(response["session"])
				if response.get("ok", false):
					var data: Dictionary = response.get("data", {})
					if op == "export_geography":
						var loaded := WorldData.load_bundle(str(data.get("directory", "")).path_join("manifest.json"))
						response["_world"] = loaded
						decoder.world = loaded
					elif op == "get_state" or op == "start_history" or (op == "advance" and data.get("schema", "") != "asabiya/advance-status-v1"):
						response["_frame"] = decoder.consume(data, op == "advance")
						response.erase("data") # Do not retain large raw provincial dictionaries.
				var terminal: bool = not response["ok"] and not _is_recoverable_request_error(op, str(response.get("error", {}).get("code", "")))
				trace.record("request-decode", request_started, {"op":op,"bytes":response_bytes})
				if inflight.get("_local_fast", false) and not terminal:
					if not response.get("ok", false):
						_push({"_error":"No se pudo completar el avance rápido."})
						break
					if op == "advance":
						var status_data: Dictionary = response.get("data", {})
						var next_year := int(status_data.get("year", -999999))
						if status_data.get("schema", "") != "asabiya/advance-status-v1" or next_year != int(fast["year"]) + 1:
							_push({"_error":"El avance rápido perdió un límite anual; no se reintentará."})
							break
						fast["year"] = next_year
						fast["remaining"] = int(fast["remaining"]) - 1
						fast["since"] = int(fast["since"]) + 1
						_mutex.lock()
						_fast_progress = {"year":next_year,"remaining":fast["remaining"]}
						_mutex.unlock()
					else:
						var frame: HistoryFrame = response.get("_frame")
						if frame == null or frame.year != int(fast["year"]):
							_push({"_error":"El estado visual no coincide con el año calculado."})
							break
						_mutex.lock()
						var done: bool = _fast_cancel or int(fast["remaining"]) <= 0
						_mutex.unlock()
						_push({"_fast_frame":frame,"done":done})
						fast["since"] = 0
						if done: fast.clear()
				else:
					_push(response)
				inflight = {}
				if terminal: break
		else:
			OS.delay_msec(2)
	peer.disconnect_from_host()

func shutdown() -> void:
	if _closing: return
	stop_live()
	_remaining = 0
	_pending.clear()
	_pending_ops.clear()
	_mutex.lock()
	_outgoing.clear()
	_mutex.unlock()
	if connected:
		request("shutdown")
	_closing = true
	var deadline := Time.get_ticks_msec() + 3000
	while _pid > 0 and OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
		await (Engine.get_main_loop() as SceneTree).process_frame
	close()

func close() -> void:
	_closing = true
	stop_live()
	_fast_active = false
	_remaining = 0
	_since_publication = 0
	_paused = true
	_live_due_us = 0
	_live_advance_pending = false
	_mutex.lock()
	_stop = true
	_outgoing.clear()
	_mutex.unlock()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_pid = -1
	_pending.clear()
	_pending_ops.clear()
	_received.clear()
	_frames.clear()
	_years.clear()
	connected = false
	busy = false
	# Remove only our generated geography, never a user-provided snapshot.
	var owned_root := OS.get_user_data_dir().path_join("sessions").simplify_path() + "/"
	if _directory.simplify_path().begins_with(owned_root):
		for name: String in ["geography.bin", "manifest.json"]:
			DirAccess.remove_absolute(_directory.path_join("world").path_join(name))
		DirAccess.remove_absolute(_directory.path_join("world"))

## Explicit fast-forward uses existing one-year status requests. Only the worker
## chains them, serially, without waiting for the graphics thread between years.
func start_fast_forward(years_count: int, publish_every: int) -> void:
	if not can_advance() or _fast_active: return
	stop_live()
	_remaining = 0
	_paused = false
	busy = true
	_fast_active = true
	fast_remaining = clampi(years_count, 1, 10000)
	var id := str(_next_id)
	_next_id += 1
	_mutex.lock()
	_fast_cancel = false
	_fast_progress = {}
	_outgoing.append({"_fast_start":true,"id":id,"years":fast_remaining,"every":clampi(publish_every, 1, 100)})
	_mutex.unlock()

func is_fast_forward() -> bool:
	return _fast_active
