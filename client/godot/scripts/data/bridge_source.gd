class_name BridgeSource
extends HistorySource
## Live connection to the Go engine through a local child process speaking
## JSON lines on stdin/stdout (protocol "asabiya-bridge/v1", proposed to the
## engine team in docs/client/API_REQUESTS.md). The client sends commands and
## renders whatever frames the engine returns; it never simulates anything.
##
## The process is optional: when no bridge executable is found the source
## reports itself unavailable and the session stays geography-only.

const PROTOCOL := "asabiya-bridge/v1"
const EXE_WIN := "asabiya-bridge.exe"
const EXE_UNIX := "asabiya-bridge"

var world: WorldData
var exe := ""
var prefix_args := PackedStringArray()   # e.g. a script path when exe is an interpreter
var available := false
var connected := false
var busy := false
var last_error := ""
var engine_info := {}

var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _thread: Thread
var _mutex := Mutex.new()
var _lines: Array[String] = []
var _next_id := 1
var _pending := {}          # id -> Callable(response: Dictionary)
var _frames := {}           # year -> HistoryFrame
var _years := PackedInt32Array()
var _systems := PackedStringArray()


func _init(w: WorldData, executable := "") -> void:
	world = w
	exe = executable if executable != "" else find_executable()
	available = exe != ""


static func find_executable() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var names := [EXE_WIN] if OS.get_name() == "Windows" else [EXE_UNIX, EXE_WIN]
	var dirs := [exe_dir, exe_dir.path_join("bin")]
	if not OS.has_feature("template"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../../build/bin").simplify_path())
	for d in dirs:
		for n in names:
			var p: String = d.path_join(n)
			if FileAccess.file_exists(p):
				return p
	return ""


func kind() -> String:
	return "bridge"


func label() -> String:
	if connected:
		return "Motor Go conectado"
	return "Motor Go no disponible"


func systems() -> PackedStringArray:
	return _systems


func years() -> PackedInt32Array:
	return _years


func frame(year: int) -> HistoryFrame:
	return _frames.get(year)


func can_advance() -> bool:
	return connected and not busy and bool(engine_info.get("canAdvance", false))


## Starts the engine process and opens the world matching the snapshot.
func start(extra_args := PackedStringArray()) -> bool:
	if not available:
		last_error = "No se encontró %s" % EXE_WIN
		return false
	var args := prefix_args.duplicate()
	args.append("--stdio")
	args.append_array(extra_args)
	# blocking pipes: the reader thread waits on get_line(); the process itself
	# always runs asynchronously
	var r := OS.execute_with_pipe(exe, args, true)
	if r.is_empty():
		last_error = "No se pudo iniciar %s" % exe
		return false
	_pid = int(r["pid"])
	_stdio = r["stdio"]
	_stderr = r.get("stderr")
	_thread = Thread.new()
	_thread.start(_reader)
	request({"cmd": "hello", "protocol": PROTOCOL}, func(resp: Dictionary) -> void:
		if not resp.get("ok", false):
			last_error = str(resp.get("error", "handshake rechazado"))
			status_changed.emit(last_error)
			return
		engine_info = resp
		connected = true
		request({"cmd": "open", "seed": world.world_seed, "historySeed": str(world.header.get("session", {}).get("historySeed", "1")), "worldDigest": world.header.get("world", {}).get("digest", "")}, _on_opened))
	return true


func _on_opened(resp: Dictionary) -> void:
	if not resp.get("ok", false):
		last_error = str(resp.get("error", "no se pudo abrir el mundo"))
		status_changed.emit(last_error)
		return
	engine_info.merge(resp, true)
	fetch_frame()


func fetch_frame() -> void:
	busy = true
	request({"cmd": "frame"}, func(resp: Dictionary) -> void:
		busy = false
		if resp.get("ok", false):
			_store(resp.get("frame", {}))
		else:
			last_error = str(resp.get("error", "frame"))
			status_changed.emit(last_error))


func advance(years_n: int) -> void:
	if not can_advance():
		return
	busy = true
	status_changed.emit("Simulando %d años…" % years_n)
	request({"cmd": "advance", "years": years_n}, func(resp: Dictionary) -> void:
		busy = false
		if resp.get("ok", false):
			if resp.has("frame"):
				_store(resp["frame"])
			else:
				fetch_frame()
		else:
			last_error = str(resp.get("error", "advance"))
			status_changed.emit(last_error))


func _store(fd: Dictionary) -> void:
	var f := parse_frame(fd, world.cell_count())
	if f == null:
		return
	_frames[f.year] = f
	_systems = PackedStringArray(fd.get("systems", _systems))
	var ys := PackedInt32Array(_frames.keys())
	ys.sort()
	_years = ys
	frames_changed.emit()
	status_changed.emit("Año %d recibido del motor" % f.year)


func request(msg: Dictionary, on_reply := Callable()) -> void:
	if _stdio == null:
		return
	var id := _next_id
	_next_id += 1
	msg["id"] = id
	if on_reply.is_valid():
		_pending[id] = on_reply
	_stdio.store_line(JSON.stringify(msg))
	_stdio.flush()


## Call every frame from the main thread.
func poll() -> void:
	if _stdio == null:
		return
	_mutex.lock()
	var lines := _lines.duplicate()
	_lines.clear()
	_mutex.unlock()
	for line in lines:
		var resp = JSON.parse_string(line)
		if typeof(resp) != TYPE_DICTIONARY:
			continue
		var id := int(resp.get("id", 0))
		if _pending.has(id):
			var cb: Callable = _pending[id]
			_pending.erase(id)
			cb.call(resp)
		elif resp.has("event"):
			status_changed.emit(str(resp.get("event")))
	if _pid > 0 and not OS.is_process_running(_pid) and connected:
		connected = false
		last_error = "El proceso del motor terminó"
		status_changed.emit(last_error)


func _reader() -> void:
	while _stdio != null and _stdio.is_open():
		var line := _stdio.get_line()
		if line == "" and _stdio.get_error() != OK:
			break
		if line.strip_edges() == "":
			continue
		_mutex.lock()
		_lines.append(line)
		_mutex.unlock()


func close() -> void:
	if _stdio != null:
		request({"cmd": "close"})
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _stdio != null:
		_stdio.close()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_stdio = null
	connected = false


# ---------------------------------------------------------------- decoding

static func _b64_i32(s: Variant) -> PackedInt32Array:
	if typeof(s) != TYPE_STRING or s == "":
		return PackedInt32Array()
	var raw := Marshalls.base64_to_raw(s)
	return raw.to_int32_array() if raw.size() % 4 == 0 else PackedInt32Array()


static func _b64_f32(s: Variant) -> PackedFloat32Array:
	if typeof(s) != TYPE_STRING or s == "":
		return PackedFloat32Array()
	var raw := Marshalls.base64_to_raw(s)
	return raw.to_float32_array() if raw.size() % 4 == 0 else PackedFloat32Array()


static func _rgb(v: Variant, fallback_id: int) -> Color:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Color8(int(v[0]), int(v[1]), int(v[2]))
	return MapLayers.id_color(fallback_id)


## Decodes a frame message. Per-cell arrays are base64 little-endian int32 /
## float32 of exactly n_cells entries; a wrong size drops that layer.
static func parse_frame(fd: Dictionary, n_cells: int) -> HistoryFrame:
	if not fd.has("year"):
		return null
	var f := HistoryFrame.new()
	f.year = int(fd["year"])
	var cells: Dictionary = fd.get("cells", {})
	var check_i := func(a: PackedInt32Array) -> PackedInt32Array:
		return a if a.size() == n_cells else PackedInt32Array()
	var check_f := func(a: PackedFloat32Array) -> PackedFloat32Array:
		return a if a.size() == n_cells else PackedFloat32Array()
	f.owner = check_i.call(_b64_i32(cells.get("owner")))
	f.people = check_i.call(_b64_i32(cells.get("people")))
	f.religion = check_i.call(_b64_i32(cells.get("religion")))
	f.population = check_f.call(_b64_f32(cells.get("population")))
	f.technology = check_f.call(_b64_f32(cells.get("technology")))
	f.wealth = check_f.call(_b64_f32(cells.get("wealth")))
	f.carrying = check_f.call(_b64_f32(cells.get("carrying")))
	for s in fd.get("states", []):
		var d: Dictionary = s
		d["rgb"] = _rgb(d.get("rgb"), int(d["id"]))
		f.states[int(d["id"])] = d
	for p in fd.get("peoples", []):
		var d2: Dictionary = p
		d2["rgb"] = _rgb(d2.get("rgb"), int(d2["id"]))
		f.peoples[int(d2["id"])] = d2
	for r in fd.get("religions", []):
		var d3: Dictionary = r
		d3["rgb"] = _rgb(d3.get("rgb"), int(d3["id"]))
		f.religions[int(d3["id"])] = d3
	f.settlements = fd.get("settlements", [])
	f.events = fd.get("events", [])
	for wv in fd.get("wars", []):
		var d4: Dictionary = wv
		d4["front"] = PackedInt32Array(d4.get("front", []))
		f.wars.append(d4)
	for rt in fd.get("routes", []):
		var d5: Dictionary = rt
		d5["cells"] = PackedInt32Array(d5.get("cells", []))
		f.routes.append(d5)
	f.world_population = float(fd.get("worldPopulation", 0.0))
	if f.world_population == 0.0 and not f.population.is_empty():
		for v in f.population:
			f.world_population += v
	return f
