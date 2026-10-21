class_name SettlementLayer
extends InstanceBands
## Settlements delivered by the Go engine (HistoryFrame.settlements), shown as
## 3D clusters on the terrain. The engine decides that a settlement exists, its
## size and which features it has (walls, castle, temple, port, market…); the
## client only lays the buildings out. The internal layout (where each house
## stands) is presentation and is derived deterministically from the id.
##
## Nothing is drawn when the engine provides no settlements.

signal layout_changed

const TIER_NAMES := ["Aldea", "Pueblo", "Villa", "Ciudad", "Gran ciudad"]
## Presentation bands when the engine gives population but no tier.
const TIER_POP := [1000.0, 5000.0, 20000.0, 100000.0]

var world: WorldData
var _cache := {}         # settlement id -> {sig, kinds}
var _anchors := {}       # settlement id -> Vector3 (centre on the surface)
var _labels := {}        # settlement id -> Label3D
var _label_root: Node3D
var _settlements := []
var _clear_radius := {}   # settlement id -> footprint radius (for decoration)
var _presentation := {}
var _tile_members := {}
var _label_view_valid := false
var _label_camera_x := INF


func setup_settlements(w: WorldData, math: MapMath) -> void:
	world = w
	setup(math, 80.0, 260.0)
	visibility_margin = 60.0
	_label_root = Node3D.new()
	_label_root.name = "SettlementLabels"
	add_child(_label_root)


static func tier_of(s: Dictionary) -> int:
	if s.has("tier"):
		return clampi(int(s["tier"]), 0, 4)
	var p := float(s.get("population", 0.0))
	var t := 0
	for th in TIER_POP:
		if p >= th:
			t += 1
	return t


static func features(s: Dictionary) -> Dictionary:
	return s.get("features", {})


func set_settlements(list: Array) -> void:
	_settlements = list
	if profiler != null: profiler.counter("settlementsConsidered", list.size())
	var presentation := {}
	for settlement: Dictionary in list:
		presentation[int(settlement["id"])] = [settlement.get("cell"), tier_of(settlement), features(settlement), settlement.get("era", 2), settlement.get("name", "")]
	if presentation == _presentation and _cache.size() == presentation.size():
		if profiler != null: profiler.counter("settlementCacheHits", list.size())
		return
	_presentation = presentation
	var next_members := {}
	var dirty_tiles := {}
	var live := {}
	for settlement: Dictionary in list:
		var id := int(settlement["id"])
		var cell := int(settlement["cell"])
		if cell < 0 or cell >= world.cell_count(): continue
		live[id] = true
		var center := world.cell_center(cell)
		var tile := band_of(center.x, center.y)
		if not next_members.has(tile): next_members[tile] = []
		(next_members[tile] as Array).append(id)
		# Names/population within a tier do not change building geometry.
		var signature := [tier_of(settlement), features(settlement), cell, int(settlement.get("era", 2))]
		if not _cache.has(id) or _cache[id]["sig"] != signature:
			dirty_tiles[tile] = true
			_cache[id] = {"sig":signature,"kinds":_layout(settlement)}
			if profiler != null: profiler.counter("settlementLayoutsBuilt")
	for id: int in _cache.keys():
		if not live.has(id): _cache.erase(id)
	for id: int in _anchors.keys():
		if not live.has(id):
			_anchors.erase(id)
			_clear_radius.erase(id)
	# Includes the old tile on moves/deletions and the new tile on insertions.
	for tile: int in _tile_members:
		if _tile_members[tile] != next_members.get(tile, []): dirty_tiles[tile] = true
	for tile: int in next_members:
		if next_members[tile] != _tile_members.get(tile, []): dirty_tiles[tile] = true
	_tile_members = next_members
	if profiler != null: profiler.counter("settlementTilesDirty", dirty_tiles.size())
	for tile: int in dirty_tiles:
		if not _tile_members.has(tile):
			clear_band(tile)
			continue
		var merged := {}
		for id: int in _tile_members[tile]:
			var kinds: Dictionary = _cache[id]["kinds"]
			for kind: String in kinds:
				if not merged.has(kind): merged[kind] = []
				(merged[kind] as Array).append_array(kinds[kind])
		set_band(tile, merged)
	_rebuild_labels()
	if not dirty_tiles.is_empty(): layout_changed.emit()


func _layout(s: Dictionary) -> Dictionary:
	var id := int(s["id"])
	var cell := int(s["cell"])
	var tier := tier_of(s)
	var f := features(s)
	var era := int(s.get("era", 2))
	var c := world.cell_center(cell)
	# pull the centre toward land if the cell centre is in the fine sea
	if not mm.is_land_at(c.x, c.y):
		for k in 12:
			var a := k * TAU / 12.0
			var q := c + Vector2(cos(a), sin(a)) * 1.2
			if mm.is_land_at(q.x, q.y):
				c = q
				break
	var kinds := {}
	var add := func(kind: String, p: Vector2, rot: float, scale := 1.0) -> void:
		if not kinds.has(kind):
			kinds[kind] = []
		var y := mm.height_at(p.x, p.y)
		var b := Basis(Vector3.UP, rot).scaled(Vector3(scale, scale, scale))
		(kinds[kind] as Array).append(Transform3D(b, Vector3(p.x, y - 0.012, p.y)))
	_anchors[id] = Vector3(c.x, maxf(mm.height_at(c.x, c.y), 0.0), c.y)
	var radius: float = [0.22, 0.38, 0.6, 0.85, 1.15][tier]
	_clear_radius[id] = radius + 0.25
	var houses: int = [4, 11, 26, 55, 100][tier]
	var house_kind := "hut" if era <= 0 else ("longhouse" if era == 1 else "house")
	var core := "townhouse" if tier >= 3 else house_kind
	var r := func(k: int) -> float: return MapMath.rnd(id, k)
	var k := 0
	var placed := 0
	while placed < houses and k < houses * 4:
		k += 1
		# denser toward the centre; golden-angle spiral with jitter
		var t := float(k) / (houses * 1.2)
		var dist: float = radius * sqrt(t) * (0.85 + r.call(k * 5) * 0.3)
		var ang: float = k * 2.39996 + r.call(k * 5 + 1) * 0.6
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * dist
		if not mm.is_land_at(p.x, p.y):
			continue
		var kind: String = core if dist < radius * 0.55 else house_kind
		add.call(kind, p, ang + r.call(k * 5 + 2) * 0.5, 0.85 + r.call(k * 5 + 3) * 0.35)
		placed += 1
	# fields ring around villages and towns
	if tier <= 3:
		var nf: int = [3, 7, 12, 16, 0][tier]
		for j in nf:
			var ang2: float = j * TAU / nf + r.call(500 + j) * 0.5
			var p2: Vector2 = c + Vector2(cos(ang2), sin(ang2)) * (radius + 0.18 + r.call(600 + j) * 0.3)
			if mm.is_land_at(p2.x, p2.y):
				add.call("field", p2, ang2 + PI * 0.5, 1.0 + r.call(700 + j) * 0.6)
	if f.get("temple", tier >= 2):
		add.call("ziggurat" if era <= 1 else "temple", c + Vector2(radius * 0.25, -radius * 0.15), 0.0, 1.0 + tier * 0.15)
	if f.get("market", false):
		add.call("market", c + Vector2(-radius * 0.2, radius * 0.1), 0.3)
	if f.get("castle", false):
		add.call("keep", c + Vector2(-radius * 0.3, -radius * 0.3), 0.2, 1.0 + tier * 0.12)
	if f.get("walls", false):
		var wr := radius * 1.05
		var segs := 10 + tier * 4
		for j in segs:
			var a0 := j * TAU / segs
			var a1 := (j + 1) * TAU / segs
			var p0 := c + Vector2(cos(a0), sin(a0)) * wr
			var p1 := c + Vector2(cos(a1), sin(a1)) * wr
			var y0 := mm.height_at(p0.x, p0.y)
			var y1 := mm.height_at(p1.x, p1.y)
			if y0 < 0.0 and y1 < 0.0:
				continue
			var d3 := Vector3(p1.x - p0.x, y1 - y0, p1.y - p0.y)
			var seg_len := d3.length()
			var bx := d3 / seg_len
			var by := Vector3.UP
			var bz := bx.cross(by).normalized()
			by = bz.cross(bx)
			if not kinds.has("wall"):
				kinds["wall"] = []
			(kinds["wall"] as Array).append(Transform3D(Basis(bx * seg_len, by, bz), Vector3(p0.x, y0 - 0.02, p0.y)))
			if j % 2 == 0:
				add.call("tower", p0, 0.0, 0.8)
	if f.get("port", false):
		# dock on the nearest fine-sea direction
		for j in 16:
			var a3 := j * TAU / 16.0
			var q := c + Vector2(cos(a3), sin(a3)) * (radius + 0.25)
			if not mm.is_land_at(q.x, q.y):
				var edge := c + Vector2(cos(a3), sin(a3)) * radius
				add.call("dock", edge, -a3 + PI * 0.5)
				var sp := c + Vector2(cos(a3), sin(a3)) * (radius + 0.45)
				if not kinds.has("ship"):
					kinds["ship"] = []
				(kinds["ship"] as Array).append(Transform3D(Basis(Vector3.UP, -a3), Vector3(sp.x, 0.0, sp.y)))
				break
	return kinds


func _rebuild_labels() -> void:
	var live := {}
	for settlement: Dictionary in _settlements:
		var id := int(settlement["id"])
		if not _anchors.has(id): continue
		live[id] = true
		var tier := tier_of(settlement)
		var text := str(settlement.get("name", "#%d" % id))
		var signature := [text, tier, _anchors[id]]
		var label: Label3D = _labels.get(id)
		if label != null and label.get_meta("presentation", []) == signature: continue
		if label == null:
			label = Label3D.new()
			label.outline_size = 10
			label.outline_modulate = Color(0.05, 0.04, 0.03, 0.85)
			label.modulate = Color(1.0, 0.96, 0.86)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = false
			label.fixed_size = false
			label.visibility_range_end_margin = 10.0
			label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			_label_root.add_child(label)
			_labels[id] = label
		label.text = text
		label.font_size = 40 + tier * 10
		label.pixel_size = 0.0022 + tier * 0.0004
		label.visibility_range_end = 40.0 + tier * 45.0
		label.set_meta("anchor", _anchors[id])
		label.set_meta("tier", tier)
		label.set_meta("presentation", signature)
		_label_view_valid = false
	for id: int in _labels.keys():
		if not live.has(id):
			(_labels[id] as Label3D).queue_free()
			_labels.erase(id)


func update_view(cam: Camera3D) -> void:
	super.update_view(cam)
	var cx := cam.global_position.x
	if _label_view_valid and cx == _label_camera_x: return
	_label_view_valid = true
	_label_camera_x = cx
	for id in _labels:
		var l: Label3D = _labels[id]
		var a: Vector3 = l.get_meta("anchor")
		var position_next := Vector3(mm.wrap_x_near(a.x, cx), a.y + 0.35 + int(l.get_meta("tier")) * 0.08, a.z)
		if l.position != position_next: l.position = position_next


func clearings() -> Array:
	var out := []
	for id in _anchors:
		var a: Vector3 = _anchors[id]
		out.append([Vector2(a.x, a.z), float(_clear_radius.get(id, 1.0))])
	return out


## Screen-space pick: nearest settlement centre within `radius_px`.
func pick(cam: Camera3D, screen: Vector2, radius_px := 18.0) -> int:
	var best := -1
	var best_d := radius_px
	var cx := cam.global_position.x
	for id in _anchors:
		var a: Vector3 = _anchors[id]
		var p := Vector3(mm.wrap_x_near(a.x, cx), a.y, a.z)
		if cam.is_position_behind(p):
			continue
		if cam.global_position.distance_to(p) > visibility_end:
			continue
		var d := cam.unproject_position(p).distance_to(screen)
		if d < best_d:
			best_d = d
			best = id
	return best


func anchor(id: int) -> Variant:
	return _anchors.get(id)
