class_name TerrainRenderer
extends Node3D
## Real 3D terrain: chunked grid meshes displaced on the GPU by the engine's
## fine elevation (1600×800), with distance-based LOD, skirts against cracks,
## a seamless longitude wrap and an opaque sea surface.
##
## Geography textures are uploaded once. Historical data only touches the small
## per-cell textures (400×200), so political changes never rebuild geometry.

const TerrainShader := preload("res://shaders/terrain.gdshader")
const WaterShader := preload("res://shaders/water.gdshader")

## Engine biome palette (legacy BCOL, Asabiya v0.6 line 2333), linearised by
## Godot from sRGB.
const BIOME_COLORS := [
	Color8(40, 70, 100), Color8(234, 239, 240), Color8(170, 175, 158), Color8(104, 124, 98),
	Color8(121, 145, 96), Color8(174, 178, 121), Color8(196, 186, 137), Color8(216, 199, 160),
	Color8(188, 177, 112), Color8(84, 126, 79)]

@export var chunk_size := 80
@export var lod_subdivisions: PackedInt32Array = [160, 80, 40, 20, 10]
@export var target_pixels_per_quad := 12.0  # quality: 9 high, 12 medium, 20 low

const SEA_TILE := 16  # fine samples per sea tile side

var world: WorldData
var mm: MapMath
var material: ShaderMaterial
var water_material: ShaderMaterial
var chunks: Array[MeshInstance3D] = []
var chunk_origin: Array[Vector2] = []
var lod_meshes: Array[ArrayMesh] = []
var water_planes: Array[MeshInstance3D] = []
var water_tiles := 0

var elev_tex: ImageTexture
var temp_tex: ImageTexture
var prec_tex: ImageTexture
var remap_tex: ImageTexture
var color_img: Image
var color_tex: ImageTexture
var key_img: Image
var key_tex: ImageTexture
var river_tex: Texture2D
var river_baker: RiverBaker

var _trace: PerformanceTrace

var stats := {"triangles": 0, "chunks": 0}
var _view_valid := false
var _view_position := Vector3.ZERO
var _view_projection := Vector3.ZERO
var _overlay_colors := PackedByteArray()
var _overlay_keys := PackedFloat32Array()
var _overlay_style := Vector3(INF, INF, INF)
var _selection := Vector3(INF, INF, INF)
var _chunk_lods := PackedInt32Array()
var _lod_quality := -1.0


func setup(w: WorldData, math: MapMath, trace: PerformanceTrace = null) -> void:
	_view_valid = false
	_overlay_colors.clear()
	_overlay_keys.clear()
	world = w
	mm = math
	_trace = trace
	var started := Time.get_ticks_usec()
	_build_textures()
	if _trace != null: _trace.record("terrain-textures", {"elapsedUsec":Time.get_ticks_usec() - started})
	started = Time.get_ticks_usec()
	_build_material()
	_build_lod_meshes()
	_build_chunks()
	_build_water()
	if _trace != null:
		_trace.record("terrain-geometry", {"elapsedUsec":Time.get_ticks_usec() - started,
			"chunks":chunks.size(),"lodLevels":lod_meshes.size()})


func _build_textures() -> void:
	var fw := world.fine_width
	var fh := world.fine_height
	var ei := Image.create_from_data(fw, fh, false, Image.FORMAT_RF, world.elevation_fine.to_byte_array())
	elev_tex = ImageTexture.create_from_image(ei)
	var ti := Image.create_from_data(fw, fh, false, Image.FORMAT_RF, world.temperature_fine.to_byte_array())
	ti.convert(Image.FORMAT_RH)
	temp_tex = ImageTexture.create_from_image(ti)
	var pi := Image.create_from_data(fw, fh, false, Image.FORMAT_RF, world.precipitation_fine.to_byte_array())
	pi.convert(Image.FORMAT_RH)
	prec_tex = ImageTexture.create_from_image(pi)
	# remap: R = land cell owning fine land here (-1 none), G = cell is land
	var n := world.cell_count()
	var rg := PackedFloat32Array()
	rg.resize(n * 2)
	for i in n:
		rg[i * 2] = float(world.land_remap[i])
		rg[i * 2 + 1] = 1.0 if world.land[i] == 1 else 0.0
	var ri := Image.create_from_data(world.width, world.height, false, Image.FORMAT_RGF, rg.to_byte_array())
	remap_tex = ImageTexture.create_from_image(ri)
	color_img = Image.create(world.width, world.height, false, Image.FORMAT_RGBA8)
	color_img.fill(Color(0, 0, 0, 0))
	color_tex = ImageTexture.create_from_image(color_img)
	var keys := PackedFloat32Array()
	keys.resize(n)
	keys.fill(-1.0)
	key_img = Image.create_from_data(world.width, world.height, false, Image.FORMAT_RF, keys.to_byte_array())
	key_tex = ImageTexture.create_from_image(key_img)
	# rivers: placeholder until the baker finishes (needs a rendering frame)
	var blank := Image.create(4, 4, false, Image.FORMAT_R8)
	river_tex = ImageTexture.create_from_image(blank)


func _build_material() -> void:
	material = ShaderMaterial.new()
	material.shader = TerrainShader
	water_material = ShaderMaterial.new()
	water_material.shader = WaterShader
	apply_params()
	var cols := PackedVector3Array()
	for c in BIOME_COLORS:
		var l: Color = c.srgb_to_linear()
		cols.append(Vector3(l.r, l.g, l.b))
	material.set_shader_parameter("biome_colors", cols)
	for m in [material, water_material]:
		m.set_shader_parameter("elev_tex", elev_tex)
	material.set_shader_parameter("temp_tex", temp_tex)
	material.set_shader_parameter("prec_tex", prec_tex)
	material.set_shader_parameter("river_tex", river_tex)
	material.set_shader_parameter("cell_remap_tex", remap_tex)
	material.set_shader_parameter("cell_color_tex", color_tex)
	material.set_shader_parameter("cell_key_tex", key_tex)


## Pushes the shared geometry parameters (vertical exaggeration…) to the GPU.
func apply_params() -> void:
	_view_valid = false
	var p := mm.shader_params()
	for k in p:
		material.set_shader_parameter(k, p[k])
		water_material.set_shader_parameter(k, p[k])


func set_river_texture(tex: Texture2D) -> void:
	river_tex = tex
	material.set_shader_parameter("river_tex", tex)


func _grid_mesh(n: int) -> ArrayMesh:
	var cs := float(chunk_size)
	var base := (n + 1) * (n + 1)
	var ring := PackedInt32Array()
	ring.resize(n * 4)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(base + n * 4)
	cols.resize(verts.size())
	cols.fill(Color(0, 0, 0))
	idx.resize(n * n * 6 + n * 48)
	var step := cs / n
	for j in n + 1:
		for i in n + 1:
			verts[j * (n + 1) + i] = Vector3(i * step, 0.0, j * step)
	var at := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			# Same alternating diagonals, with no temporary Array per quad.
			idx[at] = a
			idx[at + 1] = b
			if (i + j) % 2 == 0:
				idx[at + 2] = d
				idx[at + 3] = a
			else:
				idx[at + 2] = c
				idx[at + 3] = b
			idx[at + 4] = d
			idx[at + 5] = c
			at += 6
	var r := 0
	for i in n + 1:
		ring[r] = i
		r += 1
	for j in range(1, n + 1):
		ring[r] = j * (n + 1) + n
		r += 1
	for i in range(n - 1, -1, -1):
		ring[r] = n * (n + 1) + i
		r += 1
	for j in range(n - 1, 0, -1):
		ring[r] = j * (n + 1)
		r += 1
	for k in ring.size():
		verts[base + k] = verts[ring[k]]
		cols[base + k] = Color(1, 0, 0)
	for k in ring.size():
		var a2 := ring[k]
		var b2 := ring[(k + 1) % ring.size()]
		var a3 := base + k
		var b3 := base + (k + 1) % ring.size()
		# Both skirt faces keep their original winding.
		idx[at] = a2
		idx[at + 1] = a3
		idx[at + 2] = b2
		idx[at + 3] = b2
		idx[at + 4] = a3
		idx[at + 5] = b3
		idx[at + 6] = a2
		idx[at + 7] = b2
		idx[at + 8] = a3
		idx[at + 9] = b2
		idx[at + 10] = b3
		idx[at + 11] = a3
		at += 12
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

func _build_lod_meshes() -> void:
	lod_meshes.clear()
	for n in lod_subdivisions:
		lod_meshes.append(_grid_mesh(n))


func _build_chunks() -> void:
	_view_valid = false
	for c in chunks:
		c.queue_free()
	chunks.clear()
	chunk_origin.clear()
	_chunk_lods.clear()
	_lod_quality = -1.0
	var nx := ceili(mm.map_w / chunk_size)
	var nz := ceili(mm.map_h / chunk_size)
	var aabb := AABB(Vector3(0, mm.metres_to_units(-9000.0) - 4.0, 0), Vector3(chunk_size, mm.metres_to_units(9000.0) - mm.metres_to_units(-9000.0) + 8.0, chunk_size))
	for j in nz:
		for i in nx:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [i, j]
			mi.mesh = lod_meshes[lod_meshes.size() - 1]
			mi.custom_aabb = aabb
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.position = Vector3(i * chunk_size, 0, j * chunk_size)
			add_child(mi)
			chunks.append(mi)
			_chunk_lods.append(-1)
			chunk_origin.append(Vector2(i * chunk_size, j * chunk_size))


func _build_water() -> void:
	for w in water_planes:
		w.queue_free()
	water_planes.clear()
	var started := Time.get_ticks_usec()
	var sea := _sea_mesh()
	if _trace != null: _trace.record("terrain-sea-tiles", {"elapsedUsec":Time.get_ticks_usec() - started, "tiles":water_tiles})
	for k in [-1, 0, 1]:
		var w := MeshInstance3D.new()
		w.name = "Sea_%d" % k
		w.mesh = sea
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = Vector3(mm.map_w * 0.5 + k * mm.map_w, 0.0, mm.map_h * 0.5)
		add_child(w)
		water_planes.append(w)


## The sea surface only where it can be drawn. The water shader discards every
## fragment whose bilinear fine elevation is > 0; a tile whose texels (plus a
## two-texel margin) are all > 0 would be discarded entirely, so it is omitted.
## Same plane, height and vertex positions as the former 1600×800 PlaneMesh;
## land-only views no longer shade a full-screen discarded sea.
func _sea_mesh() -> ArrayMesh:
	var fw := world.fine_width
	var fh := world.fine_height
	var elev := world.elevation_fine
	var tx_count := ceili(float(fw) / SEA_TILE)
	var tz_count := ceili(float(fh) / SEA_TILE)
	# Minimum per tile, then a 3×3 tile dilation covers the bilinear footprint.
	var tile_min := PackedFloat32Array()
	tile_min.resize(tx_count * tz_count)
	tile_min.fill(INF)
	for z in fh:
		var row := z * fw
		var trow := (z / SEA_TILE) * tx_count
		for x in fw:
			var v := elev[row + x]
			var t := trow + x / SEA_TILE
			if v < tile_min[t]: tile_min[t] = v
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	water_tiles = 0
	for tz in tz_count:
		for tx in tx_count:
			var wet := false
			for dz in [-1, 0, 1]:
				var nz: int = tz + dz
				if nz < 0 or nz >= tz_count: continue
				for dx in [-1, 0, 1]:
					if tile_min[nz * tx_count + posmod(tx + dx, tx_count)] <= 0.0: wet = true
			if not wet: continue
			water_tiles += 1
			var x0 := tx * SEA_TILE - mm.map_w * 0.5
			var z0 := tz * SEA_TILE - mm.map_h * 0.5
			var x1 := minf(float((tx + 1) * SEA_TILE), mm.map_w) - mm.map_w * 0.5
			var z1 := minf(float((tz + 1) * SEA_TILE), mm.map_h) - mm.map_h * 0.5
			var base := verts.size()
			verts.append_array([Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x0, 0.0, z1), Vector3(x1, 0.0, z1)])
			idx.append_array([base, base + 1, base + 2, base + 2, base + 1, base + 3])
	var mesh := ArrayMesh.new()
	if water_tiles == 0: return mesh
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, water_material)
	return mesh


## Places every chunk at its longitude copy nearest to the camera and picks a
## LOD from the projected vertex spacing. Runs only for an invalidated view.
func update_view(cam: Camera3D) -> void:
	if chunks.is_empty() or cam == null:
		return
	var cp := cam.global_position
	var vh := float(get_viewport().get_visible_rect().size.y)
	var projection := Vector3(vh, cam.fov, target_pixels_per_quad)
	if _view_valid and cp == _view_position and projection == _view_projection:
		return
	var started := _trace.begin() if _trace != null else 0
	_view_valid = true
	_view_position = cp
	_view_projection = projection
	var focal := vh / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var tris := 0
	var half := chunk_size * 0.5
	for k in chunks.size():
		var o := chunk_origin[k]
		var cx := mm.wrap_x_near(o.x + half, cp.x) - half
		var mi := chunks[k]
		if mi.position.x != cx:
			mi.position.x = cx
		# distance from camera to the chunk footprint
		var dx := maxf(0.0, maxf(cx - cp.x, cp.x - (cx + chunk_size)))
		var dz := maxf(0.0, maxf(o.y - cp.z, cp.z - (o.y + chunk_size)))
		var dy := maxf(0.0, cp.y - 6.0)
		var dist := maxf(0.5, sqrt(dx * dx + dz * dz + dy * dy))
		# coarsest LOD whose projected vertex spacing stays under the target
		var lod := 0
		for l in lod_subdivisions.size():
			var spacing := float(chunk_size) / lod_subdivisions[l]
			if spacing / dist * focal <= target_pixels_per_quad:
				lod = l
		# Refine immediately. Coarsen only with 8% headroom, retaining at least
		# the original detail while avoiding swaps around a single boundary.
		var previous := _chunk_lods[k]
		if previous >= 0 and lod > previous and target_pixels_per_quad == _lod_quality:
			var stable := previous
			for level in range(previous + 1, lod + 1):
				if float(chunk_size) / lod_subdivisions[level] / dist * focal <= target_pixels_per_quad * 0.92:
					stable = level
			lod = stable
		_chunk_lods[k] = lod
		var mesh := lod_meshes[lod]
		if mi.mesh != mesh:
			mi.mesh = mesh
		var n := lod_subdivisions[lod]
		tris += n * n * 2 + n * 16
	for k in water_planes.size():
		water_planes[k].position.x = mm.wrap_x_near(mm.map_w * 0.5, cp.x) + (k - 1) * mm.map_w
	_lod_quality = target_pixels_per_quad
	stats["triangles"] = tris
	stats["chunks"] = chunks.size()
	if _trace != null: _trace.end("terrain-lod", started)


# ---------------------------------------------------------------- overlays

## Replaces the per-cell overlay (colours with alpha, group keys). Cheap: two
## 400×200 texture uploads, no geometry work.
func set_overlay(colors: PackedByteArray, keys: PackedFloat32Array) -> void:
	var colors_changed := colors != _overlay_colors
	var keys_changed := keys != _overlay_keys
	var changed := colors_changed or keys_changed
	var started := _trace.begin() if changed and _trace != null else 0
	if colors_changed:
		color_img.set_data(world.width, world.height, false, Image.FORMAT_RGBA8, colors)
		color_tex.update(color_img)
		if _trace != null:
			_trace.counter("overlayColorUploads")
			_trace.counter("overlaySourceBytes", colors.size())
		_overlay_colors = colors.duplicate()
	if keys_changed:
		key_img.set_data(world.width, world.height, false, Image.FORMAT_RF, keys.to_byte_array())
		key_tex.update(key_img)
		if _trace != null:
			_trace.counter("overlayKeyUploads")
			_trace.counter("overlaySourceBytes", keys.size() * 4)
		_overlay_keys = keys.duplicate()
	if _trace != null: _trace.end("terrain-overlay-upload", started)


func set_overlay_style(opacity: float, key_border: float, province_border: float) -> void:
	var style := Vector3(opacity, key_border, province_border)
	if style == _overlay_style:
		return
	_overlay_style = style
	material.set_shader_parameter("overlay_opacity", opacity)
	material.set_shader_parameter("key_border", key_border)
	material.set_shader_parameter("province_border", province_border)
	water_material.set_shader_parameter("overlay_dim", 0.0)


func set_selection(cell: int, hovered: int, key: float) -> void:
	var value := Vector3(cell, hovered, key)
	if value == _selection:
		return
	_selection = value
	material.set_shader_parameter("selected_cell", cell)
	material.set_shader_parameter("hovered_cell", hovered)
	material.set_shader_parameter("selected_key", key)
