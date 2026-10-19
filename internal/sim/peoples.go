package sim

import (
	"fmt"
	"math"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

// People is an ethnic group (v0.6 newEth, lines 813–823). IDs are indices into
// the history's peoples list, assigned in creation order and never reused.
// Culture is stored as float32, like the original Float32Array.
type People struct {
	Stillborn     bool       `json:"stillborn,omitempty"`
	LastMigration int        `json:"lastMigration,omitempty"`
	ID            int        `json:"id"`
	Name          string     `json:"name"`
	Language      *Language  `json:"language"`
	Culture       [6]float32 `json:"culture"`
	Family        int        `json:"family"`
	Parent        int        `json:"parent"`
	Parent2       int        `json:"parent2"`
	Depth         int        `json:"depth"`
	Born          int        `json:"born"`
	Hue           float64    `json:"hue"`
	Sat           float64    `json:"sat"`
	Lit           float64    `json:"lit"`
	RGB           [3]uint8   `json:"rgb"`
	Alive         bool       `json:"alive"`
	Cells         int        `json:"cells"`
	Pop           float64    `json:"population"`
	Peak          float64    `json:"peak"`
	Lon           float64    `json:"lonRadians"`
	Lat           float64    `json:"latRadians"`
	Kids          []int      `json:"children"`
	Died          *int       `json:"died,omitempty"`
}

// gauss is v0.6 line 386: Box–Muller with u=r()||1e-9. Two draws.
func gauss(r *rng.Mulberry32) float64 {
	u := r.Float64()
	if u == 0 {
		u = 1e-9
	}
	v := r.Float64()
	return math.Sqrt(-2*math.Log(u)) * math.Cos(6.283185307*v)
}

// jsRound is Math.round: ties toward +Infinity, exact for all finite values.
func jsRound(x float64) float64 {
	f := math.Floor(x)
	if x-f >= .5 {
		return f + 1
	}
	return f
}

func (h *history) ethDistance(a, b int) float64 {
	if a == b {
		return 0
	}
	if a < 0 || b < 0 {
		return 1
	}
	av, bv := h.peoples[a].Culture, h.peoples[b].Culture
	distance := 0.
	for k := 0; k < 6; k++ {
		delta := float64(av[k]) - float64(bv[k])
		distance += delta * delta
	}
	distance = math.Sqrt(distance/6) * 1.6
	if h.peoples[a].Family != h.peoples[b].Family {
		distance += .35
	}
	return math.Min(1, distance)
}

// hsl is v0.6 line 390, used for the people's map colour.
func hsl(h, s, l float64) [3]uint8 {
	h = math.Mod(math.Mod(h, 360)+360, 360) / 360
	f := func(n float64) uint8 {
		k := math.Mod(n+h*12, 12)
		a := s * math.Min(l, 1-l)
		return uint8(jsRound(255 * (l - a*math.Max(-1, math.Min(math.Min(k-3, 9-k), 1)))))
	}
	return [3]uint8{f(0), f(8), f(4)}
}

// newPeople is newEth(par, par2, lang). par/par2 < 0 mean none. The draw order
// is: language (when derived), six culture values, then colour.
func (h *history) newPeople(par, par2 int, lang *Language) int {
	r := h.r
	id := len(h.peoples)
	var p, p2 *People
	if par >= 0 {
		p = h.peoples[par]
	}
	if par2 >= 0 {
		p2 = h.peoples[par2]
	}
	if lang == nil {
		switch {
		case p2 != nil:
			lang = hybridLanguage(p.Language, p2.Language, r)
		case p != nil:
			lang = childLanguage(p.Language, r)
		default:
			panic("newPeople without language or parent")
		}
	}
	e := &People{ID: id, Name: lang.People, Language: lang, Family: id, Parent: -1, Parent2: -1, Born: h.year, Alive: true}
	for k := 0; k < 6; k++ {
		if p != nil {
			base := float64(p.Culture[k])
			if p2 != nil {
				base = (float64(p.Culture[k]) + float64(p2.Culture[k])) / 2
			}
			e.Culture[k] = float32(clamp(base+gauss(r)*.12, 0, 1))
		} else {
			e.Culture[k] = float32(r.Float64())
		}
	}
	if p != nil {
		if p2 != nil {
			e.Hue = (p.Hue+p2.Hue)/2 + gauss(r)*10
		} else {
			e.Hue = p.Hue + gauss(r)*16
		}
		e.Sat = clamp(p.Sat+gauss(r)*.05, .32, .72)
		e.Lit = clamp(p.Lit+gauss(r)*.06, .36, .68)
		e.Family, e.Parent, e.Depth = p.Family, par, p.Depth+1
		if p2 != nil {
			e.Parent2 = par2
		}
	} else {
		e.Hue = math.Mod(float64(h.famN)*137.508+20, 360)
		e.Sat, e.Lit = .55, .52
		h.famN++
	}
	e.RGB = hsl(e.Hue, e.Sat, e.Lit)
	if p != nil {
		p.Kids = append(p.Kids, id)
	}
	if p2 != nil {
		p2.Kids = append(p2.Kids, id)
	}
	h.peoples = append(h.peoples, e)
	return id
}

// hypot3 follows V8's n-ary Math.hypot: scale by the largest magnitude and sum
// the squares with Kahan compensation. Bit parity with V8 is not required.
func hypot3(a, b, c float64) float64 {
	m := math.Max(math.Abs(a), math.Max(math.Abs(b), math.Abs(c)))
	if m == 0 {
		return 0
	}
	sum, comp := 0.0, 0.0
	for _, v := range [3]float64{a, b, c} {
		x := v / m
		s := x*x - comp
		t := sum + s
		comp = (t - sum) - s
		sum = t
	}
	return math.Sqrt(sum) * m
}

// ethPass is v0.6 lines 1815–1840: recompute each people's extent, split
// peoples spread wider than splitDist, then let living cultures drift.
func (h *history) ethPass(log bool) {
	w, r := h.world, h.r
	n := len(h.peoples)
	sx, sy, sz, pp := make([]float64, n), make([]float64, n), make([]float64, n), make([]float64, n)
	cnt := make([]int, n)
	for _, c := range w.landList {
		i := int(c)
		e := h.eth[i]
		if e < 0 || h.pop[i] < 1 {
			continue
		}
		sx[e] += float64(w.x3[i])
		sy[e] += float64(w.y3[i])
		sz[e] += float64(w.z3[i])
		cnt[e]++
		pp[e] += float64(h.pop[i])
	}
	for e := 0; e < n; e++ {
		o := h.peoples[e]
		o.Cells, o.Pop = cnt[e], pp[e]
		if pp[e] > o.Peak {
			o.Peak = pp[e]
		}
		if o.Alive && cnt[e] == 0 {
			y := h.year
			o.Died = &y
		}
		o.Alive = cnt[e] > 0
		if cnt[e] > 0 {
			m := hypot3(sx[e], sy[e], sz[e])
			if m == 0 {
				m = 1
			}
			sx[e] /= m
			sy[e] /= m
			sz[e] /= m
			o.Lon = math.Atan2(sy[e], sx[e])
			o.Lat = math.Asin(clamp(sz[e], -1, 1))
		}
	}
	md, far := make([]float64, n), make([]int, n)
	for e := range md {
		md[e], far[e] = 2, -1
	}
	for _, c := range w.landList {
		i := int(c)
		e := h.eth[i]
		if e < 0 || h.pop[i] < 1 {
			continue
		}
		d := float64(w.x3[i])*sx[e] + float64(w.y3[i])*sy[e] + float64(w.z3[i])*sz[e]
		if d < md[e] {
			md[e], far[e] = d, i
		}
	}
	threshold := h.rules.get("splitDist") * 2 * math.Pi / float64(w.config.Width)
	made := 0
	for e := 0; e < n && made < 12; e++ {
		if cnt[e] < 6 || far[e] < 0 {
			continue
		}
		if math.Acos(clamp(md[e], -1, 1)) <= threshold || r.Float64() > .5 {
			continue
		}
		f := far[e]
		c := h.newPeople(e, -1, nil)
		made++
		for _, cell := range w.landList {
			i := int(cell)
			if int(h.eth[i]) != e {
				continue
			}
			df := float64(w.x3[i])*float64(w.x3[f]) + float64(w.y3[i])*float64(w.y3[f]) + float64(w.z3[i])*float64(w.z3[f])
			dc := float64(w.x3[i])*sx[e] + float64(w.y3[i])*sy[e] + float64(w.z3[i])*sz[e]
			if df > dc {
				h.eth[i] = int32(c)
			}
		}
		if log && pp[e] > 2e6 && cnt[e] >= 30 {
			dlat := float64(w.latitude[f]) - math.Asin(clamp(sz[e], -1, 1))
			dlon := math.Atan2(float64(w.y3[f]), float64(w.x3[f])) - math.Atan2(sy[e], sx[e])
			if dlon > math.Pi {
				dlon -= 2 * math.Pi
			}
			if dlon < -math.Pi {
				dlon += 2 * math.Pi
			}
			dir := "west"
			if math.Abs(dlat) > math.Abs(dlon)*math.Cos(float64(w.latitude[f])) {
				dir = "south"
				if dlat > 0 {
					dir = "north"
				}
			} else if dlon > 0 {
				dir = "east"
			}
			h.chron("people", fmt.Sprintf("The %s drift apart; in the %s a new people, the %s, emerges.", h.peoples[e].Name, dir, h.peoples[c].Name), CellID(f))
		}
	}
	// for(const o of E): includes peoples created in this pass.
	for _, o := range h.peoples {
		if o.Alive {
			for k := 0; k < 6; k++ {
				o.Culture[k] = float32(clamp(float64(o.Culture[k])+gauss(r)*.015, 0, 1))
			}
		}
	}
}
