class_name MapMath
extends RefCounted
## Visual geometry shared by the CPU (picking, object placement) and the GPU
## (shaders/map_common.gdshaderinc). Both sides MUST stay in sync: same hash,
## same noise, same warp, same height curve.
##
## World units: 1 unit = 1 fine sample (≈25 km at the equator for 1600×800).
## X grows east and wraps every `map_w`; Z grows south in [0, map_h]; Y is up.
## Heights are a visual exaggeration of engine metres. They never feed back
## into the simulation.

const OCEAN_REF_DEPTH := 5600.0

var map_w := 1600.0
var map_h := 800.0
var detail := 4
var grid_w := 400
var grid_h := 200

# Visual parameters (uniforms on the GPU side).
var land_scale := 1.0 / 420.0      # units per metre above sea level
var ocean_scale := 1.8             # units at OCEAN_REF_DEPTH
var relief_detail := 0.55          # amplitude of the visual micro-relief (units)
var warp_amp := 0.85               # province border warp (units)

var _fw := 0
var _fh := 0
var _elev := PackedFloat32Array()


func setup(world: WorldData) -> void:
	_fw = world.fine_width
	_fh = world.fine_height
	_elev = world.elevation_fine
	map_w = float(_fw)
	map_h = float(_fh)
	detail = world.detail
	grid_w = world.width
	grid_h = world.height


func shader_params() -> Dictionary:
	return {
		"map_size": Vector2(map_w, map_h),
		"grid_size": Vector2(grid_w, grid_h),
		"cell_size": float(detail),
		"land_scale": land_scale,
		"ocean_scale": ocean_scale,
		"relief_detail": relief_detail,
		"warp_amp": warp_amp,
	}


# ---------------------------------------------------------------- hashing

## 32-bit integer hash; identical to hash2u() in map_common.gdshaderinc.
static func hash2u(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return h ^ (h >> 16)


static func rnd(x: int, y: int) -> float:
	return float(hash2u(x, y) & 0xFFFFFF) / 16777215.0


## Value noise in [-1, 1]. `periods` lattice cells span the map width so the
## noise wraps seamlessly at the longitude seam.
func vnoise(px: float, pz: float, periods: int, salt: int) -> float:
	var sx := px * float(periods) / map_w
	var sz := pz * float(periods) / map_w
	var ix := floori(sx)
	var iz := floori(sz)
	var fx := sx - ix
	var fz := sz - iz
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var x0 := posmod(ix, periods)
	var x1 := posmod(ix + 1, periods)
	var z0 := iz + salt
	var z1 := iz + 1 + salt
	z0 = maxi(z0, 0)
	z1 = maxi(z1, 0)
	var a := rnd(x0, z0)
	var b := rnd(x1, z0)
	var c := rnd(x0, z1)
	var d := rnd(x1, z1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz) * 2.0 - 1.0


func relief_noise(px: float, pz: float) -> float:
	var periods := int(map_w * 0.45)
	return vnoise(px, pz, periods, 0) * 0.6 + vnoise(px, pz, periods * 2, 1000) * 0.28 + vnoise(px, pz, periods * 4, 2000) * 0.12


## Ridged variant for highlands: sharp crests, broad valleys. Range ≈ [-1, 1].
func ridge_noise(px: float, pz: float) -> float:
	var periods := int(map_w * 0.2)
	var r1 := 1.0 - absf(vnoise(px, pz, periods, 21000))
	var r2 := 1.0 - absf(vnoise(px, pz, periods * 2, 22000))
	var r3 := 1.0 - absf(vnoise(px, pz, periods * 4, 23000))
	return (r1 * r1 * 0.55 + r2 * r2 * 0.3 * r1 + r3 * r3 * 0.15 * r2) * 2.0 - 0.9


func warp(px: float, pz: float) -> Vector2:
	var periods := int(map_w * 0.3)
	var wx := vnoise(px, pz, periods, 3000) + 0.45 * vnoise(px, pz, periods * 3, 4000)
	var wz := vnoise(px, pz, periods, 5000) + 0.45 * vnoise(px, pz, periods * 3, 6000)
	return Vector2(wx, wz) * warp_amp


# ---------------------------------------------------------------- sampling

func _texel(x: int, y: int) -> float:
	return _elev[clampi(y, 0, _fh - 1) * _fw + posmod(x, _fw)]


## Bilinear elevation in metres (texel centres at +0.5).
func elev_bilinear(px: float, pz: float) -> float:
	var sx := px - 0.5
	var sz := pz - 0.5
	var ix := floori(sx)
	var iz := floori(sz)
	var fx := sx - ix
	var fz := sz - iz
	return lerpf(lerpf(_texel(ix, iz), _texel(ix + 1, iz), fx), lerpf(_texel(ix, iz + 1), _texel(ix + 1, iz + 1), fx), fz)


static func _cr(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))


## Catmull-Rom elevation in metres.
func elev_bicubic(px: float, pz: float) -> float:
	var sx := px - 0.5
	var sz := pz - 0.5
	var ix := floori(sx)
	var iz := floori(sz)
	var fx := sx - ix
	var fz := sz - iz
	var r0 := _cr(_texel(ix - 1, iz - 1), _texel(ix, iz - 1), _texel(ix + 1, iz - 1), _texel(ix + 2, iz - 1), fx)
	var r1 := _cr(_texel(ix - 1, iz), _texel(ix, iz), _texel(ix + 1, iz), _texel(ix + 2, iz), fx)
	var r2 := _cr(_texel(ix - 1, iz + 1), _texel(ix, iz + 1), _texel(ix + 1, iz + 1), _texel(ix + 2, iz + 1), fx)
	var r3 := _cr(_texel(ix - 1, iz + 2), _texel(ix, iz + 2), _texel(ix + 1, iz + 2), _texel(ix + 2, iz + 2), fx)
	return _cr(r0, r1, r2, r3, fz)


## Smooth elevation: bicubic inland/offshore, bilinear near the coast so the
## coastline stays exactly where the engine's fine relief crosses zero.
func elev_smooth(px: float, pz: float) -> float:
	var b := elev_bilinear(px, pz)
	var c := elev_bicubic(px, pz)
	var t := smoothstep(60.0, 320.0, absf(b))
	var v := lerpf(b, c, t)
	# never let smoothing flip land/sea
	if b > 0.0:
		v = maxf(v, minf(b, 1.0))
	else:
		v = minf(v, maxf(b, -1.0))
	return v


func metres_to_units(e: float) -> float:
	if e >= 0.0:
		return e * land_scale
	return -ocean_scale * pow(-e / OCEAN_REF_DEPTH, 0.55)


## Relief character from the engine data (mirrors relief_params in GLSL).
func relief_params(px: float, pz: float, e: float) -> Vector2:
	var gx := elev_bilinear(px + 1.0, pz) - elev_bilinear(px - 1.0, pz)
	var gz := elev_bilinear(px, pz + 1.0) - elev_bilinear(px, pz - 1.0)
	var g := sqrt(gx * gx + gz * gz) * 0.5
	var steep := smoothstep(60.0, 700.0, g)
	var amp := relief_detail * (0.10 + 1.3 * steep + 0.35 * smoothstep(1500.0, 4500.0, e))
	return Vector2(amp, steep)


## Visual terrain height (units) at a world position, including micro-relief.
func height_at(px: float, pz: float) -> float:
	var e := elev_smooth(px, pz)
	var y := metres_to_units(e)
	if e > 0.0:
		var rp := relief_params(px, pz, e)
		var n := lerpf(relief_noise(px, pz), ridge_noise(px, pz), rp.y)
		y += n * rp.x * smoothstep(0.0, 60.0, e)
	return y


func is_land_at(px: float, pz: float) -> bool:
	return elev_bilinear(px, pz) > 0.0


# ---------------------------------------------------------------- cells

## Logical cell under a world position, after border warp, without land remap.
func raw_cell_at(px: float, pz: float) -> int:
	var x := fposmod(px, map_w)
	var q := Vector2(x, pz) + warp(x, pz)
	var cx := posmod(floori(q.x / detail), grid_w)
	var cy := clampi(floori(q.y / detail), 0, grid_h - 1)
	return cy * grid_w + cx


## Province (CellID) shown at a world position: coastal fine land inside a sea
## cell belongs to its remapped land neighbour, exactly as the shader draws it.
func cell_at(world: WorldData, px: float, pz: float) -> int:
	var raw := raw_cell_at(px, pz)
	if world.land[raw] == 1:
		return raw
	if is_land_at(px, pz) and world.land_remap[raw] >= 0:
		return world.land_remap[raw]
	return raw


func wrap_x_near(x: float, ref: float) -> float:
	return x + roundf((ref - x) / map_w) * map_w


## Intersects a ray with the visual height field. Returns a Vector3 or null.
func raycast(origin: Vector3, dir: Vector3, max_dist := 6000.0) -> Variant:
	if dir.length_squared() < 1e-12:
		return null
	dir = dir.normalized()
	var top := metres_to_units(9000.0) + relief_detail
	var bottom := metres_to_units(-OCEAN_REF_DEPTH * 1.6)
	var t0 := 0.0
	var t1 := max_dist
	# clip to the slab containing all terrain (and the sea surface at y=0)
	if absf(dir.y) > 1e-6:
		var ta := (top - origin.y) / dir.y
		var tb := (minf(bottom, 0.0) - origin.y) / dir.y
		t0 = maxf(0.0, minf(ta, tb))
		t1 = minf(max_dist, maxf(ta, tb))
	elif origin.y > top or origin.y < bottom:
		return null
	if t1 <= t0:
		return null
	var prev_t := t0
	var prev_d := _surface_gap(origin + dir * t0)
	if prev_d <= 0.0:
		return _clamp_hit(origin + dir * t0)
	var steps := 160
	var dt := (t1 - t0) / steps
	var t := t0
	for _i in steps:
		t += dt
		var p := origin + dir * t
		var d := _surface_gap(p)
		if d <= 0.0:
			var lo := prev_t
			var hi := t
			for _j in 14:
				var mid := 0.5 * (lo + hi)
				if _surface_gap(origin + dir * mid) > 0.0:
					lo = mid
				else:
					hi = mid
			return _clamp_hit(origin + dir * hi)
		prev_t = t
		prev_d = d
	return null


# Height of a point above the visible surface (terrain or sea level).
func _surface_gap(p: Vector3) -> float:
	if p.z < -2.0 or p.z > map_h + 2.0:
		return 1.0
	return p.y - maxf(height_at(p.x, clampf(p.z, 0.0, map_h)), 0.0)


func _clamp_hit(p: Vector3) -> Vector3:
	p.z = clampf(p.z, 0.0, map_h - 0.001)
	return p
