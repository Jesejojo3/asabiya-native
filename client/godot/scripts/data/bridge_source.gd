class_name BridgeSource
extends HistorySource
## One owned Go process and one local TCP protocol: asabiya/local-v1.
## Networking, JSON decoding, and frame construction run on a worker thread.
## Scene nodes and callbacks are touched only by poll() on the graphics thread.

signal world_ready(value: WorldData)

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

var _pid := -1
var _endpoint := ""
var _directory := ""
var _thread: Thread
var _mutex := Mutex.new()
var _stop := false
var _outgoing: Array = []
var _received: Array = []
var _pending := {}
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
	if not available:
		last_error = "No se encontró %s junto a Asabiya Native." % EXE_WIN
		return false
	busy = true
	_directory = OS.get_user_data_dir().path_join("sessions").path_join("%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		last_error = "No se pudo crear la carpeta local de la sesión."
		return false
	_endpoint = _directory.path_join("endpoint.json")
	_pid = OS.create_process(exe, PackedStringArray(["--port","0","--endpoint-file",_endpoint,
		"--log-file",_directory.path_join("engine.log"),"--parent-pid",str(OS.get_process_id())]), false)
	if _pid <= 0:
		last_error = "No se pudo iniciar el motor Go."
		return false
	_thread = Thread.new()
	var err := _thread.start(_worker)
	if err != OK:
		last_error = "No se pudo iniciar la conexión local."
		OS.kill(_pid)
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
	request("export_geography", {"directory":_directory.path_join("world")}, _on_geography)

func _on_geography(response: Dictionary) -> void:
	var loaded: WorldData = response.get("_world")
	if loaded == null:
		_fail("No se pudo abrir la geografía exportada por Go.")
		return
	world = loaded
	world_ready.emit(world)
	status_changed.emit("Inicializando las sociedades humanas…")
	request("start_history", {"historySeed":history_seed,"view":"map"}, _on_frame)

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
	var ys := PackedInt32Array(_frames.keys())
	ys.sort()
	while ys.size() > MAX_FRAMES:
		_frames.erase(ys[0])
		ys.remove_at(0)
	_years = ys
	frames_changed.emit()
	status_changed.emit("")


func is_live() -> bool:
	return _live_running


func set_live_rate(years_per_second: int) -> void:
	_live_interval_us = 0 if years_per_second == 0 else int(1000000.0 / clampi(years_per_second, 1, 50))
	_live_due_us = Time.get_ticks_usec() + _live_interval_us


func start_live(years_per_second: int) -> void:
	if not connected or _closing: return
	set_live_rate(years_per_second)
	_live_running = true
	_paused = false
	_remaining = 0
	_live_due_us = Time.get_ticks_usec()


func stop_live() -> void:
	_live_running = false

func fetch_frame() -> void:
	if not connected: return
	busy = true
	request("get_state", {"view":"map"}, _on_frame)

func advance(count: int) -> void:
	if not can_advance() or count < 1: return
	stop_live()
	busy = true
	_remaining = clampi(count, 1, 10000)
	_paused = false
	_since_publication = 0
	_next_advance()

func _next_advance() -> void:
	if _remaining <= 0:
		fetch_frame()
		return
	if _remaining == 1 and _since_publication == 0:
		_remaining = 0
		request("advance", {"view":"map"}, _on_frame)
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
	if connected:
		request("pause", {}, func(_response: Dictionary) -> void:
			fetch_frame())

func query_province(id: int, callback: Callable) -> void:
	request("get_province", {"id":id}, callback)

func query_entity(kind_name: String, id: int, callback: Callable) -> void:
	request("get_entity", {"kind":kind_name,"id":id}, callback)

func query_history(id: int, callback: Callable) -> void:
	request("get_province_history", {"id":id}, callback)

func request(op: String, payload: Dictionary = {}, callback := Callable()) -> void:
	if _closing and op != "shutdown": return
	var id := str(_next_id)
	_next_id += 1
	if callback.is_valid(): _pending[id] = callback
	_mutex.lock()
	_outgoing.append({"schema":PROTOCOL,"id":id,"op":op,"payload":payload})
	_mutex.unlock()

func poll() -> void:
	_mutex.lock()
	var replies: Array = _received
	_received = []
	_mutex.unlock()
	for response: Dictionary in replies:
		if response.has("_error"):
			connected = false
			_fail(str(response["_error"]))
			continue
		if response.has("_connected"):
			_on_connected(response)
			continue
		_session = int(response.get("session", _session))
		var id := str(response.get("id", ""))
		var callback: Callable = _pending.get(id, Callable())
		_pending.erase(id)
		if not response.get("ok", false):
			var detail: Dictionary = response.get("error", {})
			_fail(str(detail.get("message", "El motor rechazó la petición.")))
			continue
		if callback.is_valid(): callback.call(response)
	# Continuous play is wall-clock paced, with at most one complete year in
	# flight. Publish every year, never replay cached frames or batch 10/50-year
	# jumps. A slow calculation lowers the achieved rate; it never queues a burst.
	if _live_running and can_advance() and Time.get_ticks_usec() >= _live_due_us:
		_live_due_us = Time.get_ticks_usec() + _live_interval_us
		_live_advance_pending = true
		busy = true
		request("advance", {"view":"map"}, func(response: Dictionary):
			_live_advance_pending = false
			_on_frame(response))

func _fail(message: String) -> void:
	stop_live()
	_live_advance_pending = false
	connected = false
	busy = false
	_remaining = 0
	last_error = message
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

func _worker() -> void:
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
	var incoming := PackedByteArray()
	var pending_bytes := PackedByteArray()
	var sent := 0
	var session := 0
	var inflight: Dictionary = {}
	var ready := false
	var decoder := NativeFrameDecoder.new(world)
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
			if not inflight.is_empty():
				inflight["session"] = session
				pending_bytes = (JSON.stringify(inflight) + "\n").to_utf8_buffer()
				sent = 0
				deadline = Time.get_ticks_msec() + 180000
		if not pending_bytes.is_empty():
			var written: Array = peer.put_partial_data(pending_bytes.slice(sent))
			if int(written[0]) != OK:
				_push({"_error":"No se pudo enviar una petición al motor."})
				break
			sent += int(written[1])
			if sent >= pending_bytes.size(): pending_bytes.clear()
		var count := mini(peer.get_available_bytes(), 1048576)
		if count > 0:
			var chunk: Array = peer.get_partial_data(count)
			if int(chunk[0]) != OK:
				_push({"_error":"No se pudo recibir la respuesta del motor."})
				break
			var raw: PackedByteArray = chunk[1]
			incoming.append_array(raw)
			if incoming.size() > MAX_RESPONSE_BYTES:
				_push({"_error":"La respuesta del motor supera el límite de memoria del cliente."})
				break
			# Requests are serialized: one complete NDJSON record per response.
			if not incoming.is_empty() and incoming[incoming.size() - 1] == 10:
				var value: Variant = JSON.parse_string(incoming.get_string_from_utf8())
				incoming.clear()
				if not value is Dictionary:
					_push({"_error":"El motor envió JSON inválido."})
					break
				var response: Dictionary = value
				if response.get("schema", "") != PROTOCOL or str(response.get("id", "")) != str(inflight.get("id", "")):
					_push({"_error":"La respuesta no corresponde a la sesión o petición enviada."})
					break
				session = int(response.get("session", session))
				var op: String = inflight.get("op", "")
				if response.get("ok", false):
					var data: Dictionary = response.get("data", {})
					if op == "export_geography":
						var loaded := WorldData.load_bundle(str(data.get("directory", "")).path_join("manifest.json"))
						response["_world"] = loaded
						decoder.world = loaded
					elif op == "get_state" or op == "start_history" or (op == "advance" and data.get("schema", "") != "asabiya/advance-status-v1"):
						response["_frame"] = decoder.consume(data, op == "advance")
						response.erase("data") # Do not retain large raw provincial dictionaries.
				_push(response)
				inflight = {}
		elif not inflight.is_empty() and Time.get_ticks_msec() > deadline:
			_push({"_error":"El motor tardó demasiado. No se repetirá un avance cuyo resultado sea incierto."})
			break
		else:
			OS.delay_msec(2)
	peer.disconnect_from_host()

func shutdown() -> void:
	if _closing: return
	stop_live()
	_remaining = 0
	if connected:
		request("shutdown")
	_closing = true
	var deadline := Time.get_ticks_msec() + 3000
	while _pid > 0 and OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
		await (Engine.get_main_loop() as SceneTree).process_frame
	close()

func close() -> void:
	stop_live()
	_live_advance_pending = false
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_pending.clear()
	connected = false
	busy = false
	# Remove only our generated geography, never a user-provided snapshot.
	var owned_root := OS.get_user_data_dir().path_join("sessions").simplify_path() + "/"
	if _directory.simplify_path().begins_with(owned_root):
		for name: String in ["geography.bin", "manifest.json"]:
			DirAccess.remove_absolute(_directory.path_join("world").path_join(name))
		DirAccess.remove_absolute(_directory.path_join("world"))
