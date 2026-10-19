// Package sim owns the native world and simulation data. It has no dependency
// on Ebitengine, a window, a clock, or process-global mutable state.
package sim

import (
	"errors"
	"github.com/Jesejojo3/asabiya-native/internal/rng"
	"math"
	"sort"
	"unicode/utf8"
)

const WorldVersion = "native/world-v1"

type CellID int32

const NoCell CellID = -1

type WorldConfig struct {
	Seed         string  `json:"seed"`
	Width        int     `json:"width"`
	Height       int     `json:"height"`
	Detail       int     `json:"detail"`
	LandFraction float64 `json:"landFraction"`
}

func DefaultWorldConfig(seed string) WorldConfig {
	return WorldConfig{Seed: seed, Width: 400, Height: 200, Detail: 4, LandFraction: .33}
}

func (c WorldConfig) validate() error {
	if !utf8.ValidString(c.Seed) || len(c.Seed) > 1024 {
		return errors.New("seed must be valid UTF-8, at most 1024 bytes")
	}
	if c.Width < 24 || c.Width > 400 || c.Height < 16 || c.Height > 200 || c.Detail < 1 || c.Detail > 4 {
		return errors.New("dimensions must be width 24..400, height 16..200, detail 1..4")
	}
	if c.Width*c.Detail < 96 || c.Height*c.Detail < 64 {
		return errors.New("fine climate grid must be at least 96 by 64 for stable moisture integration")
	}
	if math.IsNaN(c.LandFraction) || c.LandFraction < .2 || c.LandFraction > .5 {
		return errors.New("land fraction must be finite and in 0.2..0.5")
	}
	return nil
}

// World is immutable after construction. Arrays are private so callers cannot
// mutate the map through a view. Cell IDs are row-major indices, stable within
// this world/version. Resizing or changing seeds creates a different world.
type World struct {
	config                                                                      WorldConfig
	position                                                                    rng.Position
	elevation, temperature, precipitation, amplitude, roughness, latitude, area []float32
	land, coast                                                                 []bool
	neighbors                                                                   [][4]CellID // west, east, north, south
	landmass                                                                    []int32
	landmassSizes                                                               []int
	landCells, coastCells                                                       int
}

type Cell struct {
	ID                CellID    `json:"id"`
	X                 int       `json:"x"`
	Y                 int       `json:"y"`
	Land              bool      `json:"land"`
	Coast             bool      `json:"coast"`
	Elevation         float32   `json:"elevationMeters"`
	Temperature       float32   `json:"temperatureC"`
	Precipitation     float32   `json:"precipitationMM"`
	SeasonalAmplitude float32   `json:"seasonalAmplitudeC"`
	Roughness         float32   `json:"roughness"`
	Latitude          float32   `json:"latitudeRadians"`
	Area              float32   `json:"areaKM2"`
	Neighbors         [4]CellID `json:"neighbors"`
	Landmass          int32     `json:"landmass"`
}

func (w *World) Config() WorldConfig       { return w.config }
func (w *World) Len() int                  { return len(w.land) }
func (w *World) RNGPosition() rng.Position { return w.position }
func (w *World) Cell(id CellID) (Cell, bool) {
	i := int(id)
	if i < 0 || i >= w.Len() {
		return Cell{}, false
	}
	return Cell{ID: id, X: i % w.config.Width, Y: i / w.config.Width, Land: w.land[i], Coast: w.coast[i],
		Elevation: w.elevation[i], Temperature: w.temperature[i], Precipitation: w.precipitation[i],
		SeasonalAmplitude: w.amplitude[i], Roughness: w.roughness[i], Latitude: w.latitude[i], Area: w.area[i],
		Neighbors: w.neighbors[i], Landmass: w.landmass[i]}, true
}

// GenerateWorld ports the procedural branch through climate, aggregation,
// geography and landmasses (v0.6 lines 522–582). Drainage/ecology/sea links,
// imported maps, Earth assets and climate fitting are not implemented yet.
func GenerateWorld(c WorldConfig) (*World, error) {
	if err := c.validate(); err != nil {
		return nil, err
	}
	r := rng.New(rng.WorldSeed(c.Seed))
	hw, hh := c.Width*c.Detail, c.Height*c.Detail
	e, err := generateElevation(hw, hh, c.LandFraction, r)
	if err != nil {
		return nil, err
	}
	t, p, a := generateClimate(e, hw, hh)
	n := c.Width * c.Height
	w := &World{config: c, position: r.Position(), elevation: make([]float32, n), temperature: make([]float32, n), precipitation: make([]float32, n), amplitude: make([]float32, n), roughness: make([]float32, n), latitude: make([]float32, n), area: make([]float32, n), land: make([]bool, n), coast: make([]bool, n), neighbors: make([][4]CellID, n), landmass: make([]int32, n)}
	for cy := 0; cy < c.Height; cy++ {
		for cx := 0; cx < c.Width; cx++ {
			i := cy*c.Width + cx
			se, se2, st, sp, sa, nl := 0.0, 0.0, 0.0, 0.0, 0.0, 0
			for dy := 0; dy < c.Detail; dy++ {
				for dx := 0; dx < c.Detail; dx++ {
					k := (cy*c.Detail+dy)*hw + cx*c.Detail + dx
					v := float64(e[k])
					se += v
					se2 += v * v
					st += float64(t[k])
					sp += float64(p[k])
					sa += float64(a[k])
					if v > 0 {
						nl++
					}
				}
			}
			count := float64(c.Detail * c.Detail)
			em := se / count
			w.land[i] = nl*2 >= c.Detail*c.Detail
			if w.land[i] {
				w.elevation[i] = float32(math.Max(em, 5))
				w.roughness[i] = float32(clamp(math.Sqrt(math.Max(0, se2/count-em*em))/700+math.Max(0, em-1200)/3000, 0, 1))
			} else {
				w.elevation[i] = float32(math.Min(em, -5))
			}
			w.temperature[i] = float32(st / count)
			w.precipitation[i] = float32(math.Max(0, sp/count))
			w.amplitude[i] = float32(sa / count)
			la := (90 - (float64(cy)+.5)/float64(c.Height)*180) * math.Pi / 180
			w.latitude[i] = float32(la)
			w.area[i] = float32((40075.0 / float64(c.Width)) * (20004.0 / float64(c.Height)) * math.Cos(la))
			w.neighbors[i] = [4]CellID{CellID(cy*c.Width + (cx+c.Width-1)%c.Width), CellID(cy*c.Width + (cx+1)%c.Width), NoCell, NoCell}
			if cy > 0 {
				w.neighbors[i][2] = CellID(i - c.Width)
			}
			if cy < c.Height-1 {
				w.neighbors[i][3] = CellID(i + c.Width)
			}
		}
	}
	w.indexLand()
	return w, nil
}

func generateElevation(hw, hh int, landFraction float64, r *rng.Mulberry32) ([]float32, error) {
	n1, n2, n3, n4 := makeNoise(r), makeNoise(r), makeNoise(r), makeNoise(r)
	raw := make([]float32, hw*hh)
	samples := make([]float64, 0, hw*hh/6)
	for y := 0; y < hh; y++ {
		lat := math.Pi/2 - (float64(y)+.5)/float64(hh)*math.Pi
		cl, sl := math.Cos(lat), math.Sin(lat)
		for x := 0; x < hw; x++ {
			lon := (float64(x)+.5)/float64(hw)*2*math.Pi - math.Pi
			X, Y, Z := cl*math.Cos(lon), cl*math.Sin(lon), sl
			wx := fbm(&n2, X*1.1+3.1, Y*1.1, Z*1.1, 3)
			wy := fbm(&n2, X*1.1, Y*1.1+7.3, Z*1.1, 3)
			wz := fbm(&n2, X*1.1, Y*1.1, Z*1.1+1.7, 3)
			qx, qy, qz := X+.75*wx, Y+.75*wy, Z+.75*wz
			c := fbm(&n1, qx*1.45, qy*1.45, qz*1.45, 6)
			rg := clamp(1-math.Abs(fbm(&n3, qx*2.7, qy*2.7, qz*2.7, 4)*1.7), 0, 1)
			rg = rg * rg * rg
			factor := .25
			if c > -.04 {
				factor = 1
			}
			v := c + .17*rg*factor + .05*fbm(&n4, X*7, Y*7, Z*7, 3)
			raw[y*hw+x] = float32(v)
			if x%3 == 0 && y%2 == 0 && r.Float64() < cl {
				samples = append(samples, v)
			}
		}
	}
	if len(samples) < 2 {
		return nil, errors.New("not enough elevation samples")
	}
	sort.Float64s(samples)
	sea, mx, mn := samples[int(float64(len(samples))*(1-landFraction))], samples[len(samples)-1], samples[0]
	if mx <= sea || sea <= mn {
		return nil, errors.New("degenerate elevation range")
	}
	for i, f := range raw {
		v := float64(f)
		if v > sea {
			raw[i] = float32(20 + math.Pow((v-sea)/(mx-sea), 1.35)*6200)
		} else {
			raw[i] = float32(-(60 + math.Pow((sea-v)/(sea-mn), .5)*5600))
		}
	}
	return raw, nil
}

func (w *World) indexLand() {
	for i := range w.land {
		w.landmass[i] = -1
		if !w.land[i] {
			continue
		}
		w.landCells++
		for _, j := range w.neighbors[i] {
			if j >= 0 && !w.land[j] {
				w.coast[i] = true
				w.coastCells++
				break
			}
		}
	}
	q := make([]int, 0, w.landCells)
	for start := range w.land {
		if !w.land[start] || w.landmass[start] >= 0 {
			continue
		}
		id := int32(len(w.landmassSizes))
		q = q[:0]
		q = append(q, start)
		w.landmass[start] = id
		for h := 0; h < len(q); h++ {
			for _, j := range w.neighbors[q[h]] {
				if j >= 0 && w.land[j] && w.landmass[j] < 0 {
					w.landmass[j] = id
					q = append(q, int(j))
				}
			}
		}
		w.landmassSizes = append(w.landmassSizes, len(q))
	}
}
