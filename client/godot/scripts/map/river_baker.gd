class_name RiverBaker
extends SubViewport
## Rasterises the engine's drainage network (down[] + river strength) into a
## mask texture at 2× the fine resolution, on the GPU, once per world.
## Red channel: major rivers (strength ≥ MAJOR). Green: every drawn river, so
## minor streams can fade in only at regional/provincial zoom.
##
## Geometry follows the engine exactly (cell centre → downstream centre); only
## the corners are rounded with quadratic curves for presentation. Rivers are
## drawn where river ≥ RIVER_MIN, the same threshold the v0.6 map used.

const RIVER_MIN := 0.3
const MAJOR := 0.55
const SCALE := 2.0

signal baked(texture: Texture2D)

var _paths: Array = []   # [PackedVector2Array points (fine units), width (fine units)]
var _map_w := 0.0
var _frames := 0
var _canvas: Node2D


func bake(world: WorldData) -> void:
	_map_w = world.fine_width
	size = Vector2i(world.fine_width * SCALE, world.fine_height * SCALE)
	transparent_bg = false
	disable_3d = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	render_target_update_mode = SubViewport.UPDATE_ONCE
	msaa_2d = Viewport.MSAA_4X
	_paths = build_paths(world)
	_canvas = Node2D.new()
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_canvas.queue_redraw()
	_frames = 0
	set_process(true)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames == 3:
		set_process(false)
		var img := get_texture().get_image()
		img.convert(Image.FORMAT_RG8)
		img.generate_mipmaps()
		baked.emit(ImageTexture.create_from_image(img))


## Pure function (also used by tests): river polylines in fine units.
static func build_paths(world: WorldData) -> Array:
	var n := world.cell_count()
	var main_up := PackedInt32Array()
	main_up.resize(n)
	main_up.fill(-1)
	for i in n:
		if world.land[i] != 1 or world.river[i] < RIVER_MIN:
			continue
		var d := world.down[i]
		if d < 0 or world.land[d] != 1:
			continue
		var cur := main_up[d]
		if cur < 0 or world.accumulation[i] > world.accumulation[cur]:
			main_up[d] = i
	var paths := []
	var W := float(world.fine_width)
	for i in n:
		if world.land[i] != 1 or world.river[i] < RIVER_MIN:
			continue
		var d := world.down[i]
		if d < 0:
			continue
		var c := world.cell_center(i)
		var cd := _near(world.cell_center(d), c, W)
		var a := c
		var u := main_up[i]
		if u >= 0:
			a = (c + _near(world.cell_center(u), c, W)) * 0.5
		var b := (c + cd) * 0.5
		var end_pt := b
		var pts := PackedVector2Array()
		var steps := 6
		for s in steps + 1:
			var t := float(s) / steps
			pts.append(a * (1.0 - t) * (1.0 - t) + c * 2.0 * (1.0 - t) * t + b * t * t)
		if world.land[d] != 1:
			pts.append(cd)  # mouth: run into the sea cell
		elif main_up[d] != i:
			# tributary: join the main stem at the middle of its curve
			var dc := cd
			var up2 := main_up[d]
			var a2 := dc
			if up2 >= 0:
				a2 = (dc + _near(world.cell_center(up2), dc, W)) * 0.5
			var dd := world.down[d]
			var b2 := dc
			if dd >= 0:
				b2 = (dc + _near(world.cell_center(dd), dc, W)) * 0.5
			end_pt = 0.25 * a2 + 0.5 * dc + 0.25 * b2
			pts.append(end_pt)
		var width := 0.14 + (world.river[i] - RIVER_MIN) * 0.75
		paths.append([pts, width, world.river[i] >= MAJOR])
	return paths


static func _near(p: Vector2, ref: Vector2, w: float) -> Vector2:
	return Vector2(p.x + roundf((ref.x - p.x) / w) * w, p.y)


func _on_draw() -> void:
	# minor pass first (green), then majors on top (red + green)
	for pass_major in [false, true]:
		for path in _paths:
			if path[2] == pass_major:
				_draw_path(path, Color(1, 1, 0) if pass_major else Color(0, 1, 0))


func _draw_path(path: Array, col: Color) -> void:
	var pts: PackedVector2Array = path[0]
	var width: float = maxf(path[1] * SCALE, 1.4)
	for shift in [-_map_w, 0.0, _map_w]:
		var scaled := PackedVector2Array()
		var inside := false
		for p in pts:
			var q: Vector2 = (p + Vector2(shift, 0.0)) * SCALE
			scaled.append(q)
			if q.x >= -8.0 and q.x <= size.x + 8.0:
				inside = true
		if not inside:
			continue
		_canvas.draw_polyline(scaled, col, width, true)
		for q in scaled:
			_canvas.draw_circle(q, width * 0.5, col, true, -1.0, true)
