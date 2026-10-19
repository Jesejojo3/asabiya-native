class_name StrategyCamera
extends Camera3D
## Grand-strategy camera: orbits a focus point on the terrain.
##
## Controls
##   Left drag: grab-pan the map · Wheel: zoom to cursor · Right drag: rotate/tilt
##   WASD / arrows: pan · Q/E: rotate · R/F: tilt · Home: reset view
## Every motion is eased toward a goal state (configurable smoothing). The focus
## wraps around the longitude seam; the terrain repositions its chunks to the
## nearest copy, so crossing the seam is seamless.

signal moved

@export var min_distance := 3.5
@export var max_distance := 1050.0
@export var smoothing := 11.0          # higher = snappier
@export var zoom_step := 1.16
@export var pan_speed := 1.15          # screen heights per second at any zoom
@export var rotate_speed := 1.6
@export var edge_scroll := false
@export var yaw_limit_deg := 60.0

var mm: MapMath
var target := Vector3(800, 0, 400)
var distance := 900.0
var yaw := 0.0                         # radians, 0 = north up
var tilt := 0.0                        # user offset added to the zoom-driven pitch

var _goal_target := target
var _goal_distance := distance
var _goal_yaw := 0.0
var _goal_tilt := 0.0
var _dragging := false
var _drag_anchor := Vector3.ZERO
var _rotating := false
var _press_pos := Vector2.ZERO
var _moved_since_press := false
var _ground_y := 0.0


func setup(math: MapMath) -> void:
	mm = math
	reset_view(true)


func reset_view(instant := false) -> void:
	_goal_target = Vector3(mm.map_w * 0.5, 0, mm.map_h * 0.5)
	_goal_distance = max_distance * 0.86
	_goal_yaw = 0.0
	_goal_tilt = 0.0
	if instant:
		_snap()


func _snap() -> void:
	target = _goal_target
	distance = _goal_distance
	yaw = _goal_yaw
	tilt = _goal_tilt
	_apply()


func focus_on(p: Vector2, dist := -1.0, instant := false) -> void:
	_goal_target = Vector3(mm.wrap_x_near(p.x, target.x), 0, p.y)
	if dist > 0.0:
		_goal_distance = clampf(dist, min_distance, max_distance)
	if instant:
		_snap()


## 0 at the closest zoom, 1 at the world view.
func zoom_level() -> float:
	return clampf(log(distance / min_distance) / log(max_distance / min_distance), 0.0, 1.0)


func pitch() -> float:
	# oblique close up, near top-down from afar (degrees below horizon)
	var z := zoom_level()
	return clampf(lerpf(40.0, 74.0, pow(z, 0.7)) + tilt, 22.0, 88.0)


func _process(dt: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if edge_scroll and not _dragging:
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var s := vp.get_visible_rect().size
		if m.x < 4: move.x -= 1
		if m.x > s.x - 5: move.x += 1
		if m.y < 4: move.y -= 1
		if m.y > s.y - 5: move.y += 1
	if move != Vector2.ZERO and not _text_focus():
		var view_h := 2.0 * distance * tan(deg_to_rad(fov) * 0.5)
		var v := move.normalized().rotated(-yaw) * view_h * pan_speed * dt
		_goal_target += Vector3(v.x, 0, v.y)
	if not _text_focus():
		if Input.is_key_pressed(KEY_Q):
			_goal_yaw -= rotate_speed * dt
		if Input.is_key_pressed(KEY_E):
			_goal_yaw += rotate_speed * dt
		if Input.is_key_pressed(KEY_R):
			_goal_tilt = clampf(_goal_tilt - 40.0 * dt, -25.0, 14.0)
		if Input.is_key_pressed(KEY_F):
			_goal_tilt = clampf(_goal_tilt + 40.0 * dt, -25.0, 14.0)
	_goal_yaw = clampf(_goal_yaw, -deg_to_rad(yaw_limit_deg), deg_to_rad(yaw_limit_deg))
	_clamp_goal()
	var k := 1.0 - exp(-smoothing * dt)
	var before := global_transform
	# move along the shortest path around the seam
	_goal_target.x = mm.wrap_x_near(_goal_target.x, target.x)
	target = target.lerp(_goal_target, k)
	distance = exp(lerpf(log(distance), log(_goal_distance), k))
	yaw = lerpf(yaw, _goal_yaw, k)
	tilt = lerpf(tilt, _goal_tilt, k)
	# keep coordinates near [0, W): shift both states by whole map widths
	if target.x < 0.0 or target.x >= mm.map_w:
		var shift := floorf(target.x / mm.map_w) * mm.map_w
		target.x -= shift
		_goal_target.x -= shift
		if _dragging:
			_drag_anchor.x -= shift
	_apply()
	if not before.is_equal_approx(global_transform):
		moved.emit()


func _clamp_goal() -> void:
	_goal_distance = clampf(_goal_distance, min_distance, max_distance)
	# keep the poles inside the view more loosely when zoomed out
	var view_h := 2.0 * _goal_distance * tan(deg_to_rad(fov) * 0.5)
	var margin := minf(view_h * 0.35, mm.map_h * 0.5)
	_goal_target.z = clampf(_goal_target.z, margin * 0.4, mm.map_h - margin * 0.4)


func _apply() -> void:
	_ground_y = maxf(mm.height_at(target.x, clampf(target.z, 0.0, mm.map_h)), 0.0)
	var pr := deg_to_rad(pitch())
	var dir := Vector3(sin(yaw) * cos(pr), sin(pr), cos(yaw) * cos(pr))
	var focus := Vector3(target.x, _ground_y * clampf(1.0 - zoom_level() * 2.0, 0.0, 1.0), target.z)
	var pos := focus + dir * distance
	# never dip below the terrain in front of the camera
	var floor_y := maxf(mm.height_at(pos.x, clampf(pos.z, 0.0, mm.map_h)), 0.0) + 0.8
	pos.y = maxf(pos.y, floor_y)
	global_position = pos
	look_at(focus, Vector3.UP)
	near = clampf(distance * 0.01, 0.03, 4.0)
	far = distance * 3.0 + 400.0


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Ground point under a screen position (terrain or sea surface).
func ground_at_screen(screen: Vector2) -> Variant:
	var o := project_ray_origin(screen)
	var d := project_ray_normal(screen)
	return mm.raycast(o, d, far)


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var f := zoom_step * (mb.factor if mb.factor > 0.0 else 1.0)
				_zoom_at(mb.position, 1.0 / f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else f)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit = ground_at_screen(mb.position)
				_dragging = hit != null
				if hit != null:
					_drag_anchor = hit
				_press_pos = mb.position
				_moved_since_press = false
			else:
				_dragging = false
			return false  # let the click through for selection
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mb.pressed
			return true
	if event is InputEventMouseMotion:
		var mm_ev := event as InputEventMouseMotion
		if _rotating:
			_goal_yaw += mm_ev.relative.x * 0.006
			_goal_tilt = clampf(_goal_tilt - mm_ev.relative.y * 0.2, -25.0, 14.0)
			return true
		if _dragging:
			if mm_ev.position.distance_to(_press_pos) > 4.0:
				_moved_since_press = true
			if _moved_since_press:
				_drag_to(mm_ev.position)
			return true
	if event is InputEventKey and event.pressed and not event.echo and not _text_focus():
		if (event as InputEventKey).keycode == KEY_HOME:
			reset_view()
			return true
	if event is InputEventMagnifyGesture:
		_zoom_at(get_viewport().get_mouse_position(), 1.0 / (event as InputEventMagnifyGesture).factor)
		return true
	if event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		var view_h := 2.0 * distance * tan(deg_to_rad(fov) * 0.5)
		var v := pg.delta.rotated(-yaw) * view_h * 0.02
		_goal_target += Vector3(v.x, 0, v.y)
		return true
	return false


## True when the last left press turned into a drag (so it is not a click).
func was_drag() -> bool:
	return _moved_since_press


func _drag_to(screen: Vector2) -> void:
	# keep the grabbed ground point under the cursor (plane at anchor height)
	var o := project_ray_origin(screen)
	var d := project_ray_normal(screen)
	if absf(d.y) < 1e-4:
		return
	var t := (_drag_anchor.y - o.y) / d.y
	if t <= 0.0:
		return
	var p := o + d * t
	var delta := _drag_anchor - p
	_goal_target += Vector3(delta.x, 0, delta.z)
	target += Vector3(delta.x, 0, delta.z)
	_apply()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var new_d := clampf(_goal_distance * factor, min_distance, max_distance)
	var hit = ground_at_screen(screen)
	if hit != null:
		var h: Vector3 = hit
		h.x = mm.wrap_x_near(h.x, _goal_target.x)
		var frac := 1.0 - new_d / _goal_distance
		# zooming out drifts less toward the cursor than zooming in
		if frac < 0.0:
			frac *= 0.35
		_goal_target += Vector3(h.x - _goal_target.x, 0, h.z - _goal_target.z) * frac
	_goal_distance = new_d
