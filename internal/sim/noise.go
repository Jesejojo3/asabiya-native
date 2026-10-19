package sim

import (
	"github.com/Jesejojo3/asabiya-native/internal/rng"
	"math"
)

// valueNoise follows makeNoise (v0.6 lines 391–405). Stored samples are float32;
// interpolation uses float64 as JS does when reading typed arrays.
type valueNoise struct {
	perm [512]uint8
	val  [256]float32
}

func makeNoise(r *rng.Mulberry32) valueNoise {
	var n valueNoise
	var p [256]uint8
	for i := range p {
		p[i] = uint8(i)
	}
	for i := 255; i > 0; i-- {
		j := int(r.Float64() * float64(i+1))
		p[i], p[j] = p[j], p[i]
	}
	for i := range n.perm {
		n.perm[i] = p[i&255]
	}
	for i := range n.val {
		n.val[i] = float32(r.Float64()*2 - 1)
	}
	return n
}

func (n *valueNoise) at(x, y, z float64) float64 {
	xi, yi, zi := math.Floor(x), math.Floor(y), math.Floor(z)
	xf, yf, zf := x-xi, y-yi, z-zi
	u, v, w := xf*xf*(3-2*xf), yf*yf*(3-2*yf), zf*zf*(3-2*zf)
	X, Y, Z := int(xi)&255, int(yi)&255, int(zi)&255
	a0, a1 := int(n.perm[X])+Y, int(n.perm[X+1])+Y
	b00, b01 := int(n.perm[a0])+Z, int(n.perm[a0+1])+Z
	b10, b11 := int(n.perm[a1])+Z, int(n.perm[a1+1])+Z
	c000, c001 := float64(n.val[n.perm[b00]]), float64(n.val[n.perm[b00+1]])
	c010, c011 := float64(n.val[n.perm[b01]]), float64(n.val[n.perm[b01+1]])
	c100, c101 := float64(n.val[n.perm[b10]]), float64(n.val[n.perm[b10+1]])
	c110, c111 := float64(n.val[n.perm[b11]]), float64(n.val[n.perm[b11+1]])
	x00, x01 := c000+(c100-c000)*u, c001+(c101-c001)*u
	x10, x11 := c010+(c110-c010)*u, c011+(c111-c011)*u
	y0, y1 := x00+(x10-x00)*v, x01+(x11-x01)*v
	return y0 + (y1-y0)*w
}

func fbm(n *valueNoise, x, y, z float64, octaves int) float64 {
	s, a, f, total := 0.0, 1.0, 1.0, 0.0
	for i := 0; i < octaves; i++ {
		k := float64(i)
		s += a * n.at(x*f+k*17.1, y*f-k*9.7, z*f+k*3.3)
		total += a
		a *= .5
		f *= 2.03
	}
	return s / total
}

func clamp(v, lo, hi float64) float64 { return math.Max(lo, math.Min(hi, v)) }
