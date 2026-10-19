class_name InstanceBands
extends Node3D
## GPU-instanced objects grouped in square tiles ("bands", key = tz*1000+tx).
## Each tile is moved to its copy nearest the camera (seamless wrap) and culled
## and faded by distance as a unit; each model kind is one MultiMesh per tile.
## Used by settlements and decorative vegetation.

var mm: MapMath
var band_width := 80.0
var visibility_end := 140.0
var visibility_margin := 30.0
var cast_shadows := true
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
	for b in _bands.values():
		(b["node"] as Node3D).queue_free()
	_bands.clear()


func clear_band(band: int) -> void:
	if _bands.has(band):
		(_bands[band]["node"] as Node3D).queue_free()
		_bands.erase(band)


## transforms_by_kind: {kind: Array[Transform3D]} in world coordinates with x
## inside [0, map_w); colors_by_kind optional {kind: PackedColorArray}.
func set_band(band: int, transforms_by_kind: Dictionary, colors_by_kind := {}) -> void:
	clear_band(band)
	var node := Node3D.new()
	node.name = "Band%d" % band
	add_child(node)
	node.position = Vector3(band_origin(band).x, 0, band_origin(band).y)
	var kinds := {}
	for kind in transforms_by_kind:
		var xs: Array = transforms_by_kind[kind]
		if xs.is_empty():
			continue
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		var cols: PackedColorArray = colors_by_kind.get(kind, PackedColorArray())
		m.use_colors = not cols.is_empty()
		m.mesh = ModelLibrary.get_mesh(kind)
		m.instance_count = xs.size()
		var o := band_origin(band)
		for k in xs.size():
			var t: Transform3D = xs[k]
			t.origin.x = mm.wrap_x_near(t.origin.x, o.x + band_width * 0.5) - o.x
			t.origin.z -= o.y
			m.set_instance_transform(k, t)
			if m.use_colors:
				m.set_instance_color(k, cols[k])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = visibility_end
		mi.visibility_range_end_margin = visibility_margin
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mi)
		kinds[kind] = mi
	_bands[band] = {"node": node, "kinds": kinds}


func has_band(band: int) -> bool:
	return _bands.has(band)


func update_view(cam: Camera3D) -> void:
	var cx := cam.global_position.x
	for band in _bands:
		var base := band_origin(band).x
		var node: Node3D = _bands[band]["node"]
		node.position.x = mm.wrap_x_near(base + band_width * 0.5, cx) - band_width * 0.5


func instance_count() -> int:
	var n := 0
	for b in _bands.values():
		for mi in (b["kinds"] as Dictionary).values():
			n += (mi as MultiMeshInstance3D).multimesh.instance_count
	return n
