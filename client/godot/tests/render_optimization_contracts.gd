extends SceneTree
## Phase 2.3 contracts for the exact shader restructures (headless, no GPU).
## Mirrors the integer/lattice logic of map_common.gdshaderinc posmod_i() and
## vnoise_cross() and checks it against MapMath.vnoise, the CPU mirror of
## vnoise(). GPU pixel equality is checked separately by the harness
## (--equivalence) on the real driver.
var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures < 20: printerr("FAIL ", label)


## Same arithmetic as the shader: float quotient plus one correction step.
static func posmod_float(a: int, m: int) -> int:
	var r := a - m * int(floor(float(a) / float(m)))
	if r < 0: r += m
	elif r >= m: r -= m
	return r


static func bilerp(a: float, b: float, c: float, d: float, ux: float, uz: float) -> float:
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz) * 2.0 - 1.0


## GDScript transcription of vnoise_cross(); returns [centre, xm, xp, zm, zp].
static func vnoise_cross(mm: MapMath, px: float, pz: float, d: float, periods: int, salt: int) -> Array:
	var k := float(periods)
	# Plain floats: Vector2 would round to 32 bits, unlike MapMath.vnoise.
	var sx := px * k / mm.map_w
	var sz := pz * k / mm.map_w
	var ix := floori(sx)
	var iz := floori(sz)
	var x0 := posmod_float(ix, periods)
	var x1 := posmod_float(ix + 1, periods)
	var z0 := maxi(iz + salt, 0)
	var z1 := maxi(iz + 1 + salt, 0)
	var h00 := MapMath.rnd(x0, z0)
	var h10 := MapMath.rnd(x1, z0)
	var h01 := MapMath.rnd(x0, z1)
	var h11 := MapMath.rnd(x1, z1)
	var u := func(v: float) -> float:
		var f := v - floorf(v)
		return f * f * (3.0 - 2.0 * f)
	var out := [bilerp(h00, h10, h01, h11, u.call(sx), u.call(sz))]
	var sxm := (px - d) * k / mm.map_w
	var sxp := (px + d) * k / mm.map_w
	var cross_m := floori(sxm) < ix
	var cross_p := floori(sxp) > ix
	assert(not (cross_m and cross_p))
	var xe := posmod_float(ix - 1 if cross_m else ix + 2, periods)
	var e0 := MapMath.rnd(xe, z0)
	var e1 := MapMath.rnd(xe, z1)
	out.append(bilerp(e0, h00, e1, h01, u.call(sxm), u.call(sz)) if cross_m else bilerp(h00, h10, h01, h11, u.call(sxm), u.call(sz)))
	out.append(bilerp(h10, e0, h11, e1, u.call(sxp), u.call(sz)) if cross_p else bilerp(h00, h10, h01, h11, u.call(sxp), u.call(sz)))
	var szm := (pz - d) * k / mm.map_w
	var szp := (pz + d) * k / mm.map_w
	cross_m = floori(szm) < iz
	cross_p = floori(szp) > iz
	var ze := maxi((iz - 1 if cross_m else iz + 2) + salt, 0)
	e0 = MapMath.rnd(x0, ze)
	e1 = MapMath.rnd(x1, ze)
	out.append(bilerp(e0, e1, h00, h10, u.call(sx), u.call(szm)) if cross_m else bilerp(h00, h10, h01, h11, u.call(sx), u.call(szm)))
	out.append(bilerp(h01, h11, e0, e1, u.call(sx), u.call(szp)) if cross_p else bilerp(h00, h10, h01, h11, u.call(sx), u.call(szp)))
	return out


func _run() -> void:
	for m in [3, 7, 360, 400, 720, 1280, 1440, 2880, 9600, 22400]:
		for a in range(-60000, 60001, 37):
			check(posmod_float(a, m) == posmod(a, m), "posmod %d %d" % [a, m])
		for a in [-m - 1, -m, -m + 1, -1, 0, 1, m - 1, m, m + 1, 2 * m, -2 * m, 16777215, -16777215]:
			check(posmod_float(a, m) == posmod(a, m), "posmod edge %d %d" % [a, m])
	var mm := MapMath.new()
	mm.map_w = 1600.0
	mm.map_h = 800.0
	var eps := 0.25
	var octaves := [[720, 0], [1440, 1000], [2880, 2000], [320, 21000], [640, 22000], [1280, 23000]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var points: Array = []
	for i in 4000: points.append([rng.randf_range(-1700.0, 3300.0), rng.randf_range(-0.5, 800.5)])
	# Lattice boundaries, the longitude seam and exact neighbour crossings.
	for octave: Array in octaves:
		var cell: float = mm.map_w / float(octave[0])
		for j in 40:
			var x := cell * (j - 20) + mm.map_w * float(j % 3 - 1)
			points.append([x, cell * j])
			points.append([x - eps, cell * j + eps])
			points.append([x + eps - 1e-4, cell * j - eps + 1e-4])
	points.append([0.0, 0.0])
	points.append([1600.0, 800.0])
	for q: Array in points:
		var p := {"x":float(q[0]), "y":float(q[1])}
		for octave: Array in octaves:
			var got := vnoise_cross(mm, p.x, p.y, eps, octave[0], octave[1])
			var want := [mm.vnoise(p.x, p.y, octave[0], octave[1]), mm.vnoise(p.x - eps, p.y, octave[0], octave[1]),
				mm.vnoise(p.x + eps, p.y, octave[0], octave[1]), mm.vnoise(p.x, p.y - eps, octave[0], octave[1]),
				mm.vnoise(p.x, p.y + eps, octave[0], octave[1])]
			for k in 5: check(got[k] == want[k], "vnoise_cross %s periods %d point %d" % [p, octave[0], k])
	# Exact skips: mix(a, b, 0) == a and the snow bound.
	for a in [-1.0, -0.3, 0.0, 0.7, 1.0]:
		check(lerpf(a, 0.0, 0.0) == a and lerpf(a, 0.9, 0.0) == a, "mix with zero weight")
	var worst := 0.0
	for q: Array in points.slice(0, 1500): worst = maxf(worst, absf(mm.relief_noise(float(q[0]) * 2.0, float(q[1]) * 2.0)))
	check(worst <= 1.0 + 1e-6, "relief_noise bound used by the snow skip: %f" % worst)
	check(3300.0 + 140.0 * 1.000001 + 900.0 < 4350.0, "snow skip threshold")
	print("render optimization contracts: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
