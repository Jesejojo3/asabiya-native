package sim

import "math"

// generateClimate ports genClimate and boxBlur (v0.6 lines 407–410, 425–467), using
// the original CDEF defaults. These are generation parameters, not weather or
// annual rules. Each typed-array write rounds to float32; reads use float64.
func generateClimate(e []float32, width, height int) ([]float32, []float32, []float32) {
	n := len(e)
	t, p, a := make([]float32, n), make([]float32, n), make([]float32, n)
	mZ, oZ, cZ := make([]float32, n), make([]float32, n), make([]float32, n)
	mR, mM, oM := make([]float32, n), make([]float32, n), make([]float32, n)
	baseRow := make([]float32, height)
	latOf := func(y int) float64 { return 90 - (float64(y)+.5)/float64(height)*180 }
	sq := func(x float64) float64 { return x * x }
	for y := range baseRow {
		lat := latOf(y)
		abs := math.Abs(lat)
		baseRow[y] = float32(math.Max(60, 260+3150*math.Exp(-sq((lat-3)/13))+1400*math.Exp(-sq((abs-50)/12))-590*math.Exp(-sq((abs-24)/7))-150*clamp((abs-65)/20, 0, 1)))
	}
	march := func(length int, index func(int) int, km, bp float64, outM, outO, outC []float32, mode int) {
		m, prev, ds := 1.0, 0.0, 0.0
		floor := math.Min(.95, .75+.9*bp/2000)
		dry := .038
		recharge := .25
		if mode != 0 {
			floor = .75 * .3
			recharge = .05
		}
		if mode == 1 {
			dry *= .45
		} else if mode == 2 {
			dry *= 2.5
		}
		for step := 0; step < 2*length; step++ {
			i := index(step % length)
			v := float64(e[i])
			rain := 0.0
			if v <= 0 {
				m += (1 - m) * recharge
				prev = 0
				ds = 0
			} else {
				dh := v - prev
				if dh > 0 {
					rain = m * (1 - math.Exp(-dh/1500))
					m -= rain
				}
				m += (floor - m) * dry * (km / 31)
				prev = v
				ds += km
			}
			if step >= length {
				outM[i] = float32(m)
				if outO != nil {
					outO[i] = float32(rain)
				}
				if outC != nil {
					outC[i] = float32(1 - math.Exp(-ds/650))
				}
			}
		}
	}
	for y := 0; y < height; y++ {
		lat := latOf(y)
		abs := math.Abs(lat)
		east := abs >= 30 && abs < 62
		km := math.Max(5, 40075*math.Cos(lat*math.Pi/180)/float64(width))
		offset := y * width
		index := func(k int) int {
			if east {
				return offset + k
			}
			return offset + width - 1 - k
		}
		reverse := func(k int) int {
			if east {
				return offset + width - 1 - k
			}
			return offset + k
		}
		march(width, index, km, float64(baseRow[y]), mZ, oZ, cZ, 0)
		march(width, reverse, km, float64(baseRow[y]), mR, nil, nil, 1)
	}
	kmV := 20004.0 / float64(height)
	y0, y1 := int(45.0/180*float64(height)), int(135.0/180*float64(height))
	for x := 0; x < width; x++ {
		ys := int(102.0 / 180 * float64(height))
		ys2 := int(78.0 / 180 * float64(height))
		march(ys-y0, func(k int) int { return (ys-k)*width + x }, kmV, 0, mM, oM, nil, 2)
		march(y1-ys2, func(k int) int { return (ys2+k)*width + x }, kmV, 0, mM, oM, nil, 2)
	}
	for y := 0; y < height; y++ {
		lat := latOf(y)
		abs := math.Abs(lat)
		s := math.Sin(lat * math.Pi / 180)
		s2 := s * s
		seaT := 29 - 47*s2*(.55+.5*s2*s2)
		mon := .62 * clamp((52-abs)/20, 0, 1) * clamp((abs-2)/6, 0, 1)
		eastW := clamp((abs-18)/8, 0, 1)
		for x := 0; x < width; x++ {
			i := y*width + x
			v := float64(e[i])
			cont := 0.0
			if v > 0 {
				cont = float64(cZ[i])
			}
			maritime := 0.0
			if abs >= 30 && abs < 62 {
				maritime = 5.5 * (1 - cont) * clamp((abs-30)/15, 0, 1)
			}
			t[i] = float32(seaT - 6*.001*math.Max(0, v) + maritime)
			mm := math.Max(float64(mR[i])*eastW, float64(mM[i]))
			orog := math.Max(float64(oZ[i]), mon*float64(oM[i]))
			bp := float64(baseRow[y])
			prec := bp
			if v > 0 {
				prec = bp*(.12+.88*float64(mZ[i])) + 575*mon*mm + 2400*orog*(.35+bp/1400)
			}
			p[i] = float32(prec)
			a[i] = float32(.5 + abs*(.165+.55*cont))
		}
	}
	boxBlur(p, width, height, 4, 2)
	boxBlur(a, width, height, 6, 2)
	boxBlur(t, width, height, 1, 1)
	return t, p, a
}

func boxBlur(a []float32, w, h, rx, ry int) {
	tmp := make([]float32, len(a))
	for y := 0; y < h; y++ {
		offset := y * w
		s := 0.0
		for d := -rx; d <= rx; d++ {
			s += float64(a[offset+(d+w)%w])
		}
		for x := 0; x < w; x++ {
			tmp[offset+x] = float32(s / float64(2*rx+1))
			s += float64(a[offset+(x+rx+1)%w]) - float64(a[offset+(x-rx+w)%w])
		}
	}
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			s, count := 0.0, 0
			for d := -ry; d <= ry; d++ {
				yy := y + d
				if yy >= 0 && yy < h {
					s += float64(tmp[yy*w+x])
					count++
				}
			}
			a[y*w+x] = float32(s / float64(count))
		}
	}
}
