class_name InstanceBands
extends Node3D
## GPU-instanced objects grouped in square tiles ("bands", key = tz*1000+tx).
## Each tile is moved to its copy nearest the camera (seamless wrap) and culled
## and faded by distance as a unit; each model kind is one MultiMesh per tile.
## Used by settlements and decorative vegetation.

var profiler: PerformanceTrace
var mm: MapMath
var band_width := 80.0
var visibility_end := 140.0
var visibility_margin := 30.0
var cast_shadows := true
var _wrap_valid := false
var _wrap_camera_x := INF
var _bands := {}   # band index -> {node: Node3D, kinds: {kind: MultiMeshInstance3D}}


func setup(math: MapMath, width := 80.0, vis_end := 140.0) -> void:
	mm = math
	band_width = width
	visibility_end = vis_end


func band_of(x: float, z: float) -> int:
	var tx := int(floor(fposmod(x, mm.map_w) / band_width))
	var tz := clampi(int(floor(z / band_width)), 0, 999)
	return tz * 1000 + tx


func band_origin(band: int) -> Vector2:
	return Vector2((band % 1000) * band_width, (band / 1000) * band_width)


func clear() -> void:
	_wrap_valid = false
	for b in _bands.values():
		(b["node"] as Node3D).queue_free()
	_bands.clear()


func clear_band(band: int) -> void:
	_wrap_valid = false
	if _bands.has(band):
		if profiler != null: profiler.counter("bandsRemoved")
		(_bands[band]["node"] as Node3D).queue_free()
		_bands.erase(band)


## transforms_by_kind: {kind: Array[Transform3D]} in world coordinates with x
## inside [0, map_w); colors_by_kind optional {kind: PackedColorArray}.
func set_band(band: int, transforms_by_kind: Dictionary, colors_by_kind := {}) -> void:
	var buffers := {}
	var origin := band_origin(band)
	for kind: String in transforms_by_kind:
		var instances: Array = transforms_by_kind[kind]
		if instances.is_empty(): continue
		var colors: PackedColorArray = colors_by_kind.get(kind, PackedColorArray())
		buffers[kind] = {"count":instances.size(),"useColors":not colors.is_empty(),
			"buffer":pack_instances(instances, origin, band_width, mm, colors)}
	set_band_buffers(band, buffers)


## Pure packing: no rendering resources, safe on a vegetation worker. Godot's
## 3D MultiMesh layout is three row-major vec4s, followed by optional RGBA.
static func pack_instances(instances: Array, origin: Vector2, width: float, math: MapMath, colors := PackedColorArray()) -> PackedFloat32Array:
	var stride := 12 if colors.is_empty() else 16
	var buffer := PackedFloat32Array()
	buffer.resize(instances.size() * stride)
	for k in instances.size():
		var instance_transform: Transform3D = instances[k]
		var instance_basis := instance_transform.basis
		var at := k * stride
		buffer[at] = instance_basis.x.x
		buffer[at + 1] = instance_basis.y.x
		buffer[at + 2] = instance_basis.z.x
		buffer[at + 3] = math.wrap_x_near(instance_transform.origin.x, origin.x + width * 0.5) - origin.x
		buffer[at + 4] = instance_basis.x.y
		buffer[at + 5] = instance_basis.y.y
		buffer[at + 6] = instance_basis.z.y
		buffer[at + 7] = instance_transform.origin.y
		buffer[at + 8] = instance_basis.x.z
		buffer[at + 9] = instance_basis.y.z
		buffer[at + 10] = instance_basis.z.z
		buffer[at + 11] = instance_transform.origin.z - origin.y
		if stride == 16:
			var color: Color = colors[k]
			buffer[at + 12] = color.r
			buffer[at + 13] = color.g
			buffer[at + 14] = color.b
			buffer[at + 15] = color.a
	return buffer


## Rendering-resource publication stays on the main thread. Empty tiles remain
## present so the scheduler does not repeatedly regenerate sea/desert tiles.
func set_band_buffers(band: int, buffers: Dictionary) -> void:
	if profiler != null: profiler.counter("bandsPublished")
	clear_band(band)
	var node := Node3D.new()
	node.name = "Band%d" % band
	add_child(node)
	var origin := band_origin(band)
	node.position = Vector3(origin.x, 0, origin.y)
	var kinds := {}
	for kind: String in buffers:
		var data: Dictionary = buffers[kind]
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.use_colors = data.get("useColors", false)
		mesh.mesh = ModelLibrary.get_mesh(kind)
		mesh.instance_count = int(data["count"])
		mesh.buffer = data["buffer"]
		if profiler != null:
			profiler.counter("multiMeshesPublished")
			profiler.counter("instancesPublished", int(data["count"]))
			profiler.counter("instanceSourceBytes", data["buffer"].size() * 4)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = visibility_end
		instance.visibility_range_end_margin = visibility_margin
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(instance)
		kinds[kind] = instance
	_bands[band] = {"node":node,"kinds":kinds}


func has_band(band: int) -> bool:
	return _bands.has(band)


func update_view(cam: Camera3D) -> void:
	var cx := cam.global_position.x
	if _wrap_valid and cx == _wrap_camera_x: return
	_wrap_valid = true
	_wrap_camera_x = cx
	for band in _bands:
		var base := band_origin(band).x
		var node: Node3D = _bands[band]["node"]
		var wrapped := mm.wrap_x_near(base + band_width * 0.5, cx) - band_width * 0.5
		if node.position.x != wrapped: node.position.x = wrapped


func refresh_visibility() -> void:
	for band: int in _bands:
		var kinds: Dictionary = _bands[band]["kinds"]
		for kind: String in kinds:
			var instance: MultiMeshInstance3D = kinds[kind]
			instance.visibility_range_end = visibility_end
			instance.visibility_range_end_margin = visibility_margin


func instance_count() -> int:
	var n := 0
	for b in _bands.values():
		for mi in (b["kinds"] as Dictionary).values():
			n += (mi as MultiMeshInstance3D).multimesh.instance_count
	return n
