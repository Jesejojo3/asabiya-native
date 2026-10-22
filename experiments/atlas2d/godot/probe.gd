extends SceneTree
var base: ImageTexture
var overlay: ImageTexture
var canvas: Node2D
var started := 0
var last := 0
var output: FileAccess
var seconds := 10.0
var zoom := 4.0
var opts := {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=",true,1)
		opts[parts[0]]=parts[1] if parts.size()>1 else "true"
	var fixture: String=opts["fixture"]
	seconds=float(opts.get("seconds","10"))
	zoom=float(opts.get("zoom","4"))
	output=FileAccess.open(opts["out"],FileAccess.WRITE)
	output.store_line(JSON.stringify({"kind":"environment","engine":Engine.get_version_info(),"fixture":JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("probe.json"))),"size":"1920x1080","target_hardware_verified":false,"zoom":zoom,"gpu":RenderingServer.get_video_adapter_name()}))
	base=ImageTexture.create_from_image(Image.load_from_file(fixture.path_join("terrain.png")))
	overlay=ImageTexture.create_from_image(Image.load_from_file(fixture.path_join("political.png")))
	DisplayServer.window_set_size(Vector2i(1920,1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	canvas=Node2D.new()
	root.add_child(canvas)
	canvas.draw.connect(_draw_map)
	RenderingServer.frame_post_draw.connect(_frame)
	started=Time.get_ticks_usec()

func _process(_dt: float) -> bool:
	canvas.queue_redraw()
	return false

func _draw_map() -> void:
	var elapsed := (Time.get_ticks_usec()-started)/1000000.0
	var center := Vector2(400*(0.5+sin(elapsed*0.2)*0.15),200*(0.5+sin(elapsed*0.12)*0.08))
	var scale := minf(1920.0/400,1080.0/200)*zoom
	for wrap in range(-2,3):
		var rect := Rect2(Vector2(960,540)-center*scale+Vector2(wrap*400*scale,0),Vector2(400,200)*scale)
		canvas.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		canvas.draw_texture_rect(base,rect,false)
		# Both probes use linear sampling for this static texture comparison.
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		canvas.draw_texture_rect(overlay,rect,false)

func _frame() -> void:
	var now := Time.get_ticks_usec()
	var elapsed := (now-started)/1000000.0
	if elapsed>=3 and last>0:
		output.store_line(JSON.stringify({"kind":"frame","frame_ms":(now-last)/1000.0}))
	last=now
	if elapsed>=seconds+3:
		output.flush()
		quit()
