class_name MapView
extends Node3D
## Owns the 3D world: environment, lighting, terrain, camera and map layers.
## Knows nothing about where data comes from (see scripts/data/*_source.gd).

signal cell_hovered(cell: int)
signal cell_clicked(cell: int)
signal entity_clicked(kind: String, id: int)

var profiler: PerformanceTrace
var world: WorldData
var mm: MapMath
var terrain: TerrainRenderer
var camera: StrategyCamera
var sun: DirectionalLight3D
var env: WorldEnvironment
var river_baker: RiverBaker

var hovered_cell := -1
var selected_cell := -1
var selected_key := -2.0
var _hover_dirty := false
var _last_mouse := Vector2(-1, -1)
var _last_gui_id := 0
var _view_dirty := true
var _view_transform := Transform3D.IDENTITY
var _view_projection := Projection()
var _view_size := Vector2.ZERO
var _environment_distance := -1.0
var _minor_rivers := -1.0

## Extra layers (settlements, labels, markers) register here to get view updates.
var view_listeners: Array[Callable] = []
## Screen-space pick handlers: Callable(screen: Vector2) -> Dictionary {kind,id}
var pick_handlers: Array[Callable] = []


func setup(w: WorldData, trace: PerformanceTrace = null) -> void:
	profiler = trace
	world = w
	mm = MapMath.new()
	mm.setup(w)
	_build_environment()
	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(w, mm, profiler)
	camera = StrategyCamera.new()
	camera.name = "Camera"
	camera.fov = 38.0
	add_child(camera)
	camera.setup(mm, profiler)
	camera.make_current()
	camera.moved.connect(invalidate_picking)
	get_viewport().size_changed.connect(invalidate_picking)
	if DisplayServer.get_name() != "headless":
		river_baker = RiverBaker.new()
		river_baker.name = "RiverBaker"
		add_child(river_baker)
		river_baker.baked.connect(_on_rivers_baked)
		river_baker.bake(w)


func _on_rivers_baked(tex: Texture2D) -> void:
	terrain.set_river_texture(tex)
	river_baker.queue_free()
	river_baker = null


func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.067, 0.086)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.32
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 1.4
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.55, 0.62, 0.72)
	e.fog_density = 1.0
	e.fog_depth_begin = 600.0
	e.fog_depth_end = 2600.0
	e.fog_depth_curve = 1.6
	e.fog_aerial_perspective = 0.25
	e.glow_enabled = false
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34.0, -38.0, 0.0)
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func invalidate_picking() -> void:
	_hover_dirty = true
	_view_dirty = true


func invalidate_view() -> void:
	_view_dirty = true


func _process(_dt: float) -> void:
	if camera == null: return
	var started := profiler.begin() if profiler != null else 0
	var viewport_size := get_viewport().get_visible_rect().size
	var projection := camera.get_camera_projection()
	var camera_changed := camera.global_transform != _view_transform or projection != _view_projection or viewport_size != _view_size
	if _view_dirty or camera_changed:
		_view_dirty = false
		_view_transform = camera.global_transform
		_view_projection = projection
		_view_size = viewport_size
		terrain.update_view(camera)
		if camera.distance != _environment_distance:
			_environment_distance = camera.distance
			sun.directional_shadow_max_distance = clampf(camera.distance * 2.6, 40.0, 1800.0)
			env.environment.fog_depth_begin = camera.distance * 2.2 + 60.0
			env.environment.fog_depth_end = camera.distance * 7.0 + 500.0
		var z := camera.zoom_level()
		var minor := 1.0 - smoothstep(0.42, 0.6, z)
		if minor != _minor_rivers:
			_minor_rivers = minor
			terrain.material.set_shader_parameter("minor_rivers", minor)
		for listener in view_listeners: listener.call(camera, z)
		if camera_changed: _hover_dirty = true
		if profiler != null and profiler.enabled():
			profiler.set_context({"cameraDistance":camera.distance,"zoom":z,"viewportWidth":viewport_size.x,"viewportHeight":viewport_size.y})
	var mouse := get_viewport().get_mouse_position()
	var gui := get_viewport().gui_get_hovered_control()
	var gui_id := gui.get_instance_id() if gui != null else 0
	if mouse != _last_mouse or gui_id != _last_gui_id:
		_last_mouse = mouse
		_last_gui_id = gui_id
		_hover_dirty = true
	if _hover_dirty:
		_hover_dirty = false
		var hover_started := profiler.begin() if profiler != null else 0
		_update_hover(mouse)
		if profiler != null: profiler.end("hover-pick", hover_started)
	if profiler != null: profiler.end("map-view", started)


func _update_hover(mouse: Vector2) -> void:
	var c := -1
	if not _mouse_over_ui():
		var hit = camera.ground_at_screen(mouse)
		if profiler != null and profiler.enabled():
			profiler.counter("hoverQueries")
			if camera.last_pick_cached: profiler.counter("pickCacheHits")
			else:
				profiler.counter("pickSamples", mm.pick_samples)
				profiler.counter("pickFullHeights", mm.pick_full_heights)
				profiler.counter("pickBoundsSkipped", mm.pick_bounds_skipped)
				profiler.counter("pickBoundsBuilt", mm.pick_bounds_built)
				profiler.counter("pickNonpositive", mm.pick_nonpositive)
		if hit != null:
			c = mm.cell_at(world, hit.x, hit.z)
	if c != hovered_cell:
		hovered_cell = c
		_push_selection()
		cell_hovered.emit(c)


func _mouse_over_ui() -> bool:
	var h := get_viewport().gui_get_hovered_control()
	return h != null and h.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _push_selection() -> void:
	terrain.set_selection(selected_cell, hovered_cell, selected_key)


func select_cell(c: int, key := -2.0) -> void:
	selected_cell = c
	selected_key = key
	_push_selection()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if camera.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not camera.was_drag():
			for h in pick_handlers:
				var r: Dictionary = h.call(mb.position)
				if not r.is_empty():
					entity_clicked.emit(r["kind"], r["id"])
					return
			var hit = camera.ground_at_screen(mb.position)
			if hit != null:
				cell_clicked.emit(mm.cell_at(world, hit.x, hit.z))
			else:
				cell_clicked.emit(-1)


## World position on the visible surface for a cell centre (for markers).
func cell_surface(c: int) -> Vector3:
	var p := world.cell_center(c)
	var x := mm.wrap_x_near(p.x, camera.target.x if camera else p.x)
	return Vector3(x, maxf(mm.height_at(p.x, p.y), 0.0), p.y)
