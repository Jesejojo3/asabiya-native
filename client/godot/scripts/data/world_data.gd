class_name WorldData
extends RefCounted
## Static geography loaded from an engine snapshot (asabiya/snapshot-v1).
##
## Holds only data produced by the Go engine. Nothing here is simulated or
## invented by the client: derived fields (river polylines, coastal remap) are
## presentation helpers and are documented as such.

const MAGIC := "ASBYSNP1"
const SCHEMA := "asabiya/snapshot-v1"
const BIOME_NAMES_ES := ["Océano", "Hielo", "Tundra", "Bosque boreal", "Bosque templado", "Pradera", "Estepa", "Desierto", "Sabana", "Selva tropical"]

var header: Dictionary = {}
var source_path := ""
var world_seed := ""
var width := 0          # logical grid (cells)
var height := 0
var detail := 1         # fine samples per cell axis
var fine_width := 0
var fine_height := 0
var session_kind := "real"
var available: PackedStringArray = []

# Cell layers (row-major, CellID = y * width + x)
var land := PackedByteArray()
var coast := PackedByteArray()
var biome := PackedByteArray()
var travel_cost := PackedByteArray()
var desert := PackedByteArray()
var nomad := PackedByteArray()
var elevation := PackedFloat32Array()
var temperature := PackedFloat32Array()
var precipitation := PackedFloat32Array()
var amplitude := PackedFloat32Array()
var roughness := PackedFloat32Array()
var area := PackedFloat32Array()
var landmass := PackedInt32Array()
var down := PackedInt32Array()
var accumulation := PackedFloat32Array()
var river := PackedFloat32Array()
var farming := PackedFloat32Array()
var herding := PackedFloat32Array()
var growing_season := PackedFloat32Array()
var forest0 := PackedFloat32Array()
var malaria := PackedFloat32Array()
var monsoon := PackedFloat32Array()

# Fine layers (fine_width × fine_height). When a snapshot is coarse these are
# synthesised by repeating cell values, and `has_fine` is false.
var has_fine := false
var elevation_fine := PackedFloat32Array()
var temperature_fine := PackedFloat32Array()
var precipitation_fine := PackedFloat32Array()

# Presentation helper: for each cell, which land cell owns fine-land fragments
# that fall inside it (itself if land, an adjacent land cell for a coastal sea
# cell, -1 otherwise). Needed because the engine decides land per cell by a
# 4×4 majority while the fine relief draws its own coastline (audit O1).
var land_remap := PackedInt32Array()
var land_cells := PackedInt32Array()


static func load_file(path: String) -> WorldData:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("No se pudo leer el snapshot: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var w := WorldData.new()
	var err := w._parse(bytes)
	if err != "":
		push_error("Snapshot inválido %s: %s" % [path, err])
		return null
	w.source_path = path
	return w


func _parse(bytes: PackedByteArray) -> String:
	if bytes.size() < 12 or bytes.slice(0, 8).get_string_from_ascii() != MAGIC:
		return "no es un snapshot de Asabiya"
	var hl := bytes.decode_u32(8)
	if hl <= 0 or 12 + hl > bytes.size():
		return "cabecera truncada"
	var parsed = JSON.parse_string(bytes.slice(12, 12 + hl).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return "cabecera JSON inválida"
	header = parsed
	if header.get("schema", "") != SCHEMA:
		return "esquema no soportado: %s" % header.get("schema", "?")
	var data := bytes.slice(12 + hl)
	var expected: String = header.get("dataSHA256", "")
	if expected != "":
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(data)
		if ctx.finish().hex_encode() != expected:
			return "suma de comprobación incorrecta"
	var wi: Dictionary = header.get("world", {})
	world_seed = str(wi.get("seed", ""))
	width = int(wi.get("width", 0))
	height = int(wi.get("height", 0))
	detail = int(wi.get("detail", 1))
	fine_width = int(wi.get("fineWidth", 0))
	fine_height = int(wi.get("fineHeight", 0))
	session_kind = str(header.get("session", {}).get("kind", "real"))
	available = PackedStringArray(header.get("available", []))
	if width <= 0 or height <= 0:
		return "dimensiones inválidas"
	var layers := {}
	for l in header.get("layers", []):
		var off := int(l["offset"])
		var n := int(l["bytes"])
		if off < 0 or off + n > data.size():
			return "capa fuera de rango: %s" % l["name"]
		layers[l["name"]] = data.slice(off, off + n)
	var n_cells := width * height
	var get_u8 := func(name: String) -> PackedByteArray:
		return layers.get(name, PackedByteArray())
	var get_f32 := func(name: String) -> PackedFloat32Array:
		return (layers.get(name, PackedByteArray()) as PackedByteArray).to_float32_array()
	var get_i32 := func(name: String) -> PackedInt32Array:
		return (layers.get(name, PackedByteArray()) as PackedByteArray).to_int32_array()
	land = get_u8.call("land")
	coast = get_u8.call("coast")
	biome = get_u8.call("biome")
	travel_cost = get_u8.call("travelCost")
	desert = get_u8.call("desert")
	nomad = get_u8.call("nomad")
	elevation = get_f32.call("elevation")
	temperature = get_f32.call("temperature")
	precipitation = get_f32.call("precipitation")
	amplitude = get_f32.call("seasonalAmplitude")
	roughness = get_f32.call("roughness")
	area = get_f32.call("area")
	landmass = get_i32.call("landmass")
	down = get_i32.call("down")
	accumulation = get_f32.call("accumulation")
	river = get_f32.call("river")
	farming = get_f32.call("farming")
	herding = get_f32.call("herding")
	growing_season = get_f32.call("growingSeason")
	forest0 = get_f32.call("forest0")
	malaria = get_f32.call("malaria")
	monsoon = get_f32.call("monsoonZone")
	for arr in [land, biome, elevation, temperature, precipitation, landmass, down, river]:
		if arr.size() != n_cells:
			return "capa por celda con tamaño incorrecto"
	if fine_width > 0 and layers.has("elevationFine"):
		has_fine = true
		elevation_fine = get_f32.call("elevationFine")
		temperature_fine = get_f32.call("temperatureFine")
		precipitation_fine = get_f32.call("precipitationFine")
		if elevation_fine.size() != fine_width * fine_height:
			return "capa fina con tamaño incorrecto"
	else:
		_synthesise_fine()
	_build_helpers()
	return ""


func _synthesise_fine() -> void:
	# Coarse snapshot: repeat each cell value over a 4×4 block so the renderer
	# works unchanged. Marked via has_fine = false (shown in the UI).
	has_fine = false
	detail = 4
	fine_width = width * detail
	fine_height = height * detail
	elevation_fine.resize(fine_width * fine_height)
	temperature_fine.resize(fine_width * fine_height)
	precipitation_fine.resize(fine_width * fine_height)
	for y in fine_height:
		var cy := y / detail
		for x in fine_width:
			var c := cy * width + x / detail
			var k := y * fine_width + x
			elevation_fine[k] = elevation[c]
			temperature_fine[k] = temperature[c]
			precipitation_fine[k] = precipitation[c]


func _build_helpers() -> void:
	var n := width * height
	land_remap.resize(n)
	var lc := PackedInt32Array()
	for i in n:
		if land[i] == 1:
			land_remap[i] = i
			lc.append(i)
			continue
		land_remap[i] = -1
		# Sea cell: if any fine sample inside is land, attribute it to the land
		# neighbour (n8 order) with the most fine land along the shared side.
		var cx := i % width
		var cy := i / width
		var best := -1
		var best_score := -1.0
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var ny: int = cy + dy
				if ny < 0 or ny >= height:
					continue
				var j: int = ny * width + posmod(cx + dx, width)
				if land[j] != 1:
					continue
				var score: float = elevation[j] + (1000.0 if dx == 0 or dy == 0 else 0.0)
				if score > best_score:
					best_score = score
					best = j
		land_remap[i] = best
	land_cells = lc


func cell_count() -> int:
	return width * height


func cell_xy(id: int) -> Vector2i:
	return Vector2i(id % width, id / width)


func cell_id(x: int, y: int) -> int:
	if y < 0 or y >= height:
		return -1
	return y * width + posmod(x, width)


func is_land(id: int) -> bool:
	return id >= 0 and id < land.size() and land[id] == 1


## Cell centre in fine/world units (x east, z south).
func cell_center(id: int) -> Vector2:
	var p := cell_xy(id)
	return Vector2((p.x + 0.5) * detail, (p.y + 0.5) * detail)


func latitude_deg(id: int) -> float:
	var y := id / width
	return 90.0 - (y + 0.5) / height * 180.0


func longitude_deg(id: int) -> float:
	var x := id % width
	return (x + 0.5) / width * 360.0 - 180.0


func biome_name(id: int) -> String:
	var b := int(biome[id])
	return BIOME_NAMES_ES[b] if b < BIOME_NAMES_ES.size() else "?"


func has_system(name: String) -> bool:
	return available.has(name)
