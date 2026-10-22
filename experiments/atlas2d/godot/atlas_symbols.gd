class_name AtlasSymbols
extends Control
## Real city IDs only. No building or ruin records are inferred from decoration.
var map: AtlasMap
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	if map==null or map.world==null or map.frame==null or map.zoom<10: return
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
