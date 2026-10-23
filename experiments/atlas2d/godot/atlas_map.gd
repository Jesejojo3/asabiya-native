class_name AtlasMap
extends Control
signal province_selected(id: int, started_us: int)
var world: WorldData
var frame: HistoryFrame
var center := Vector2(200,100)
var target_center := center
var zoom := 1.0
var target_zoom := 1.0
var selected := -1
var routes_visible := false
var _dirty := true
signal redrawn
var dragging := false
var moved := false
var drag_origin := Vector2.ZERO
var shader := ShaderMaterial.new()
var texture := PlaceholderTexture2D.new()
var _empty: ImageTexture

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	shader.shader = load("res://terrain.gdshader")
	material = shader
	texture.size = Vector2(1,1)
	var symbols := AtlasSymbols.new()
	symbols.map=self
	add_child(symbols)

func _float_texture(values: PackedFloat32Array, width: int, height: int) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(width,height,false,Image.FORMAT_RF,values.to_byte_array()))

func set_world(value: WorldData) -> void:
	world=value
	center=Vector2(world.width,world.height)*0.5
	target_center=center
	zoom_to(1)
	zoom=target_zoom
	shader.set_shader_parameter("grid_size",Vector2(world.width,world.height))
	shader.set_shader_parameter("fine_size",Vector2(world.fine_width,world.fine_height))
	shader.set_shader_parameter("heights",_float_texture(world.elevation_fine,world.fine_width,world.fine_height))
	shader.set_shader_parameter("temperatures",_float_texture(world.temperature_fine,world.fine_width,world.fine_height))
	shader.set_shader_parameter("rainfall",_float_texture(world.precipitation_fine,world.fine_width,world.fine_height))
	var ids := PackedFloat32Array(Array(world.land_remap))
	shader.set_shader_parameter("remap",_float_texture(ids,world.width,world.height))
	var blank := Image.create(world.width,world.height,false,Image.FORMAT_RGBA8)
	_empty=ImageTexture.create_from_image(blank)
	shader.set_shader_parameter("overlay",_empty)
	shader.set_shader_parameter("grouping",_float_texture(ids,world.width,world.height))
	_dirty=true

func publish(packet: Dictionary) -> float:
	var started := Time.get_ticks_usec()
	frame=packet.frame
	shader.set_shader_parameter("overlay",ImageTexture.create_from_image(Image.create_from_data(world.width,world.height,false,Image.FORMAT_RGBA8,packet.colors)))
	shader.set_shader_parameter("grouping",_float_texture(packet.keys,world.width,world.height))
	shader.set_shader_parameter("border_strength",float(packet.get("borders",MapLayers.def(packet.layer).get("borders",0.0))))
	_dirty=true
	return (Time.get_ticks_usec()-started)/1000.0

func _clamp_vertical_camera() -> void:
	if world==null or size.y<=0: return
	# The planet wraps horizontally, not vertically. Constrain the camera
	# so polar edges cannot leave a large empty strip in the map viewport.
	var half_visible := size.y*0.5/maxf(target_zoom,0.001)
	if half_visible*2.0>=world.height:
		target_center.y=world.height*0.5
	else:
		target_center.y=clampf(target_center.y,half_visible,world.height-half_visible)

func zoom_to(multiplier: float) -> void:
	if world == null: return
	if multiplier==1:
		target_center=Vector2(world.width,world.height)*0.5
	elif selected>=0:
		target_center=Vector2(selected%world.width,floori(float(selected)/world.width))+Vector2(0.5,0.5)
	target_zoom=zoom_base()*multiplier
	_clamp_vertical_camera()

func zoom_base() -> float:
	return maxf(0.1,minf(size.x/world.width,size.y/world.height)) if world!=null else 1.0

func screen_to_world(point: Vector2) -> Vector2:
	return center + (point-size*0.5)/zoom

func _process(delta: float) -> void:
	if world == null: return
	_clamp_vertical_camera()
	var shift := target_center-center
	shift.x=wrapf(shift.x,-world.width*0.5,world.width*0.5)
	# Redraw only while the camera moves or after a published change. The
	# easing tail ends once it is far below one screen pixel.
	if shift.length()*zoom<0.01 and absf(zoom-target_zoom)<target_zoom*1e-5:
		if center==target_center and zoom==target_zoom and not _dirty: return
		center=Vector2(fposmod(target_center.x,world.width),target_center.y)
		zoom=target_zoom
	else:
		var weight := 1.0-exp(-delta*16.0)
		center+=shift*weight
		center.x=fposmod(center.x,world.width)
		zoom=lerpf(zoom,target_zoom,weight)
	target_center.x=fposmod(target_center.x,world.width)
	_dirty=false
	shader.set_shader_parameter("cell_pixels",zoom)
	queue_redraw()
	redrawn.emit()

func _gui_input(event: InputEvent) -> void:
	if world==null: return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var at: Vector2 = target_center+(event.position-size*0.5)/target_zoom
			target_zoom=clampf(target_zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.2),0.3,160.0)
			target_center=at-(event.position-size*0.5)/target_zoom
			_clamp_vertical_camera()
			accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			dragging=event.pressed
			if event.pressed:
				moved=false
				drag_origin=event.position
			elif not moved:
				select_at(event.position)
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_origin)>4: moved=true
		target_center-=event.relative/target_zoom
		target_center.x=fposmod(target_center.x,world.width)
		target_center.y=clampf(target_center.y,0,world.height)

func select_at(point: Vector2) -> int:
	var started := Time.get_ticks_usec()
	selected=AtlasProjection.pick(world,screen_to_world(point))
	shader.set_shader_parameter("selected",float(selected))
	_dirty=true
	province_selected.emit(selected,started)
	return selected

func _notification(what: int) -> void:
	if what==NOTIFICATION_RESIZED: _dirty=true

func _draw() -> void:
	if world==null: return
	# Bathymetric fallback when the complete world fits with letterboxing.
	draw_rect(Rect2(Vector2.ZERO,size),Color("#0d3146"))
	# Only copies intersecting the viewport; no per-province nodes or meshes.
	var span := Vector2(world.width,world.height)*zoom
	var origin := size*0.5-center*zoom
	var first := floori((-origin.x-span.x)/span.x)
	var last := ceili((size.x-origin.x)/span.x)
	for wrap in range(first,last+1):
		var rect := Rect2(origin+Vector2(wrap*span.x,0),span)
		if rect.intersects(Rect2(Vector2.ZERO,size)):
			draw_texture_rect(texture,rect,false)
