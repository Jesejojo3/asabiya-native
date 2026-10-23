class_name AtlasSymbols
extends Control
## Real city IDs only. No building or ruin records are inferred from decoration.
var map: AtlasMap
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.redrawn.connect(queue_redraw)
func _point(cell: int) -> Vector2:
	var coordinate := Vector2(cell%map.world.width,floori(float(cell)/map.world.width))+Vector2(0.5,0.5)
	var offset := coordinate-map.center
	offset.x=wrapf(offset.x,-map.world.width*0.5,map.world.width*0.5)
	return map.size*0.5+offset*map.zoom

func _draw() -> void:
	if map==null or map.world==null or map.frame==null: return
	if map.routes_visible:
		# Active Go trade routes along their published cell paths.
		for route: Dictionary in map.frame.routes:
			var cells: PackedInt32Array=route.get("cells",PackedInt32Array())
			if cells.size()<2: continue
			var points := PackedVector2Array()
			var previous := _point(cells[0])
			points.append(previous)
			for k in range(1,cells.size()):
				var point := _point(cells[k])
				# Keep the polyline continuous across the longitude seam.
				var span := map.world.width*map.zoom
				point.x=previous.x+wrapf(point.x-previous.x,-span*0.5,span*0.5)
				points.append(point)
				previous=point
			draw_polyline(points,Color(0.95,0.78,0.35,0.9),maxf(1.0,minf(3.0,map.zoom*0.25)),true)
	if map.zoom<10: return
	var font := ThemeDB.fallback_font
	for city: Dictionary in map.frame.settlements:
		var id := int(city.cell)
		var coordinate := Vector2(id%map.world.width,floori(float(id)/map.world.width))+Vector2(0.5,0.5)
		var offset := coordinate-map.center
		offset.x=wrapf(offset.x,-map.world.width*0.5,map.world.width*0.5)
		var point := map.size*0.5+offset*map.zoom
		if Rect2(Vector2.ZERO,map.size).grow(30).has_point(point):
			draw_circle(point,3.5,Color(1.0,0.88,0.54))
			if map.zoom>20: draw_string(font,point+Vector2(6,-4),str(city.get("name","")),HORIZONTAL_ALIGNMENT_LEFT,140,13,Color.WHITE)
