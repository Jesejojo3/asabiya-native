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

var world: WorldData
var mm: MapMath
var material: ShaderMaterial
var water_material: ShaderMaterial
var chunks: Array[MeshInstance3D] = []
var chunk_origin: Array[Vector2] = []
var lod_meshes: Array[ArrayMesh] = []
var water_planes: Array[MeshInstance3D] = []

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

var stats := {"triangles": 0, "chunks": 0}


func setup(w: WorldData, math: MapMath) -> void:
	world = w
	mm = math
	_build_textures()
	_build_material()
	_build_lod_meshes()
	_build_chunks()
	_build_water()


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
	var p := mm.shader_params()
	for k in p:
		material.set_shader_parameter(k, p[k])
		water_material.set_shader_parameter(k, p[k])


func set_river_texture(tex: Texture2D) -> void:
	river_tex = tex
	material.set_shader_parameter("river_tex", tex)


func _grid_mesh(n: int) -> ArrayMesh:
	var cs := float(chunk_size)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var step := cs / n
	for j in n + 1:
		for i in n + 1:
			verts.append(Vector3(i * step, 0.0, j * step))
			cols.append(Color(0, 0, 0))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			# alternate diagonals for a more isotropic surface
			if (i + j) % 2 == 0:
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	# skirts: duplicate the border ring, flagged to drop below the surface
	var ring: Array[int] = []
	for i in n + 1:
		ring.append(i)
	for j in range(1, n + 1):
		ring.append(j * (n + 1) + n)
	for i in range(n - 1, -1, -1):
		ring.append(n * (n + 1) + i)
	for j in range(n - 1, 0, -1):
		ring.append(j * (n + 1))
	var base := verts.size()
	for k in ring.size():
		verts.append(verts[ring[k]])
		cols.append(Color(1, 0, 0))
	for k in ring.size():
		var a2: int = ring[k]
		var b2: int = ring[(k + 1) % ring.size()]
		var a3: int = base + k
		var b3: int = base + (k + 1) % ring.size()
		idx.append_array([a2, a3, b2, b2, a3, b3])
		idx.append_array([a2, b2, a3, b2, b3, a3])  # both faces: skirts seen from any side
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
	for c in chunks:
		c.queue_free()
	chunks.clear()
	chunk_origin.clear()
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
			chunk_origin.append(Vector2(i * chunk_size, j * chunk_size))


func _build_water() -> void:
	for w in water_planes:
		w.queue_free()
	water_planes.clear()
	var pm := PlaneMesh.new()
	pm.size = Vector2(mm.map_w, mm.map_h)
	pm.subdivide_width = 8
	pm.subdivide_depth = 4
	pm.material = water_material
	for k in [-1, 0, 1]:
		var w := MeshInstance3D.new()
		w.name = "Sea_%d" % k
		w.mesh = pm
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = Vector3(mm.map_w * 0.5 + k * mm.map_w, 0.0, mm.map_h * 0.5)
		add_child(w)
		water_planes.append(w)


## Places every chunk at its longitude copy nearest to the camera and picks a
## LOD from the projected vertex spacing. Called every frame; O(chunks).
func update_view(cam: Camera3D) -> void:
	if chunks.is_empty() or cam == null:
		return
	var cp := cam.global_position
	var vh := float(get_viewport().get_visible_rect().size.y)
	var focal := vh / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var tris := 0
	var half := chunk_size * 0.5
	for k in chunks.size():
		var o := chunk_origin[k]
		var cx := mm.wrap_x_near(o.x + half, cp.x) - half
		var mi := chunks[k]
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
		var mesh := lod_meshes[lod]
		if mi.mesh != mesh:
			mi.mesh = mesh
		var n := lod_subdivisions[lod]
		tris += n * n * 2
	for k in water_planes.size():
		water_planes[k].position.x = mm.wrap_x_near(mm.map_w * 0.5, cp.x) + (k - 1) * mm.map_w
	stats["triangles"] = tris
	stats["chunks"] = chunks.size()


# ---------------------------------------------------------------- overlays

## Replaces the per-cell overlay (colours with alpha, group keys). Cheap: two
## 400×200 texture uploads, no geometry work.
func set_overlay(colors: PackedByteArray, keys: PackedFloat32Array) -> void:
	color_img.set_data(world.width, world.height, false, Image.FORMAT_RGBA8, colors)
	color_tex.update(color_img)
	key_img.set_data(world.width, world.height, false, Image.FORMAT_RF, keys.to_byte_array())
	key_tex.update(key_img)


func set_overlay_style(opacity: float, key_border: float, province_border: float) -> void:
	material.set_shader_parameter("overlay_opacity", opacity)
	material.set_shader_parameter("key_border", key_border)
	material.set_shader_parameter("province_border", province_border)
	water_material.set_shader_parameter("overlay_dim", 0.0)


func set_selection(cell: int, hovered: int, key: float) -> void:
	material.set_shader_parameter("selected_cell", cell)
	material.set_shader_parameter("hovered_cell", hovered)
	material.set_shader_parameter("selected_key", key)
