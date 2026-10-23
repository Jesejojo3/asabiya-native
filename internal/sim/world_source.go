package sim

import (
	"fmt"
	"math"
)

// ClimateConfig contains the generation-time CDEF controls. Annual weather and
// historical rules remain separate; changing these controls requires a new world.
type ClimateConfig struct {
	TEq      float64 `json:"tEq"`
	TGrad    float64 `json:"tGrad"`
	Lapse    float64 `json:"lapse"`
	RainBelt float64 `json:"rainBelt"`
	Midlat   float64 `json:"midlat"`
	SubDry   float64 `json:"subDry"`
	Dry      float64 `json:"dry"`
	Floor    float64 `json:"floor"`
	Orog     float64 `json:"orog"`
	Recycle  float64 `json:"recycle"`
	Monsoon  float64 `json:"monsoon"`
	MonsoonP float64 `json:"monsoonP"`
	Maritime float64 `json:"maritime"`
	ContKM   float64 `json:"contKm"`
	Seas     float64 `json:"seas"`
	ContSeas float64 `json:"contSeas"`
}

func DefaultClimate() ClimateConfig {
	return ClimateConfig{TEq: 29, TGrad: 47, Lapse: 6, RainBelt: 3150, Midlat: 1400, SubDry: 590, Dry: .038, Floor: .75, Orog: 2400, Recycle: .9, Monsoon: .62, MonsoonP: 575, Maritime: 5.5, ContKM: 650, Seas: .165, ContSeas: .55}
}

func (c ClimateConfig) Validate() error {
	for _, p := range []struct {
		name          string
		value, lo, hi float64
	}{
		{"tEq", c.TEq, 22, 32}, {"tGrad", c.TGrad, 30, 60}, {"lapse", c.Lapse, 4, 9},
		{"rainBelt", c.RainBelt, 600, 4000}, {"midlat", c.Midlat, 200, 2000}, {"subDry", c.SubDry, 0, 800},
		{"dry", c.Dry, .002, .06}, {"floor", c.Floor, 0, .95}, {"orog", c.Orog, 0, 5000},
		{"recycle", c.Recycle, 0, 1}, {"monsoon", c.Monsoon, 0, 1.2}, {"monsoonP", c.MonsoonP, 0, 2500},
		{"maritime", c.Maritime, 0, 8}, {"contKm", c.ContKM, 300, 3000}, {"seas", c.Seas, .05, .4}, {"contSeas", c.ContSeas, 0, 1},
	} {
		if math.IsNaN(p.value) || math.IsInf(p.value, 0) || p.value < p.lo || p.value > p.hi {
			return fmt.Errorf("climate %s must be finite and in %g..%g", p.name, p.lo, p.hi)
		}
	}
	return nil
}

// SourceAsset identifies an input by its bytes. Path is a local locator only:
// it is recorded for replay but is deliberately excluded from the world digest.
// Min/Max/Midpoint apply to 8-bit luminance image imports, not Earth resources.
type SourceAsset struct {
	Role     string  `json:"role"`
	Path     string  `json:"path"`
	SHA256   string  `json:"sha256"`
	Bytes    int64   `json:"bytes"`
	Min      float64 `json:"min,omitempty"`
	Max      float64 `json:"max,omitempty"`
	Midpoint bool    `json:"midpoint,omitempty"`
}

type WorldSource struct {
	Kind       string        `json:"kind"`
	Climate    ClimateConfig `json:"climate"`
	FitClimate bool          `json:"fitClimate"`
	Resampling string        `json:"resampling,omitempty"`
	Assets     []SourceAsset `json:"assets,omitempty"`
}

// WorldInputs are fine row-major rasters. Construction copies all retained data;
// callers may release these buffers once GenerateWorldWithInputs returns.
type WorldInputs struct {
	Height, Temperature, Precipitation []float32
	Koppen                             []uint8
}

func DefaultWorldSource() WorldSource {
	return WorldSource{Kind: "procedural", Climate: DefaultClimate()}
}
func cloneWorldSource(s WorldSource) WorldSource {
	s.Assets = append([]SourceAsset(nil), s.Assets...)
	return s
}
func (w *World) Source() WorldSource { return cloneWorldSource(w.source) }
func (w *World) Version() string {
	if w.extended {
		return "native/world-v3"
	}
	return WorldVersion
}

func validateWorldInputs(s WorldSource, in WorldInputs, n int) error {
	if s.Kind != "procedural" && s.Kind != "earth" && s.Kind != "imported" {
		return fmt.Errorf("unknown world source %q", s.Kind)
	}
	if err := s.Climate.Validate(); err != nil {
		return err
	}
	for _, asset := range s.Assets {
		if math.IsNaN(asset.Min) || math.IsNaN(asset.Max) || math.IsInf(asset.Min, 0) || math.IsInf(asset.Max, 0) {
			return fmt.Errorf("source asset scales must be finite")
		}
	}
	if s.Kind != "procedural" && in.Height == nil {
		return fmt.Errorf("%s source requires elevation input", s.Kind)
	}
	if s.Kind == "procedural" && in.Height != nil {
		return fmt.Errorf("use imported source for an elevation override")
	}
	for _, layer := range []struct {
		name string
		v    []float32
	}{{"height", in.Height}, {"temperature", in.Temperature}, {"precipitation", in.Precipitation}} {
		if layer.v == nil {
			continue
		}
		if len(layer.v) != n {
			return fmt.Errorf("%s input must contain %d fine cells", layer.name, n)
		}
		land := 0
		for _, v := range layer.v {
			f := float64(v)
			if math.IsNaN(f) || math.IsInf(f, 0) {
				return fmt.Errorf("%s input contains a non-finite value", layer.name)
			}
			if layer.name == "precipitation" && v < 0 {
				return fmt.Errorf("precipitation must be nonnegative")
			}
			if v > 0 {
				land++
			}
		}
		if layer.name == "height" && land*50 < n {
			return fmt.Errorf("elevation input requires at least two percent positive samples")
		}
	}
	if in.Koppen != nil {
		if len(in.Koppen) != n {
			return fmt.Errorf("Koppen input must contain %d fine cells", n)
		}
		for _, v := range in.Koppen {
			if v > 32 {
				return fmt.Errorf("unknown Koppen code %d", v)
			}
		}
	}
	if s.FitClimate && in.Koppen == nil {
		return fmt.Errorf("climate fitting requires Koppen input")
	}
	return nil
}

func aggregateFine(values []float32, c WorldConfig) []float32 {
	out := make([]float32, c.Width*c.Height)
	width := c.Width * c.Detail
	for y := 0; y < c.Height; y++ {
		for x := 0; x < c.Width; x++ {
			sum := 0.
			for dy := 0; dy < c.Detail; dy++ {
				for dx := 0; dx < c.Detail; dx++ {
					sum += float64(values[(y*c.Detail+dy)*width+x*c.Detail+dx])
				}
			}
			out[y*c.Width+x] = float32(sum / float64(c.Detail*c.Detail))
		}
	}
	return out
}

func aggregateKoppen(values []uint8, c WorldConfig) []uint8 {
	out := make([]uint8, c.Width*c.Height)
	width := c.Width * c.Detail
	for y := 0; y < c.Height; y++ {
		for x := 0; x < c.Width; x++ {
			var counts [33]int
			best, n := uint8(0), 0
			for dy := 0; dy < c.Detail; dy++ {
				for dx := 0; dx < c.Detail; dx++ {
					v := values[(y*c.Detail+dy)*width+x*c.Detail+dx]
					if v == 0 || v >= 32 {
						continue
					}
					counts[v]++
					if counts[v] > n {
						best, n = v, counts[v]
					}
				}
			}
			out[y*c.Width+x] = best
		}
	}
	return out
}

type ClimateGroupScore struct {
	OK    float64 `json:"ok"`
	Total float64 `json:"total"`
}
type ClimateGrade struct {
	Score      float64              `json:"score"`
	Per        [6]ClimateGroupScore `json:"per"`
	Code       []uint8              `json:"code"`
	FitChanged int                  `json:"fitChanged"`
}

func kgGroup(c uint8) int {
	switch {
	case c >= 1 && c <= 4:
		return 0
	case c == 5 || c == 6:
		return 2
	case c == 7 || c == 8:
		return 1
	case c >= 9 && c <= 17:
		return 3
	case c >= 18 && c <= 29:
		return 4
	case c == 30 || c == 31:
		return 5
	}
	return -1
}
func simClimateGroup(t, p, a float64) int {
	if t+a/2 < 10 {
		return 5
	}
	th := math.Max(0, 20*t+140)
	if p < th {
		if p < th/2 {
			return 1
		}
		return 2
	}
	if t-a/2 >= 18 {
		return 0
	}
	if t-a/2 > 0 {
		return 3
	}
	return 4
}
func fitClimate(t, p, a, e []float32, kg []uint8) int {
	changed := 0
	for i := range e {
		if e[i] <= 0 {
			continue
		}
		g := kgGroup(kg[i])
		if g < 0 {
			continue
		}
		T, P, A := float64(t[i]), float64(p[i]), float64(a[i])
		T0, P0 := T, P
		if g == 5 {
			if T+A/2 >= 10 {
				T -= T + A/2 - 9.5
			}
		} else if T+A/2 < 10 {
			T += 10.5 - (T + A/2)
		}
		if g == 0 && T-A/2 < 18 {
			T += 18.5 - (T - A/2)
		}
		if g == 3 {
			if T-A/2 >= 18 {
				T -= T - A/2 - 17.5
			}
			if T-A/2 <= 0 {
				T += .5 - (T - A/2)
			}
		}
		if g == 4 && T-A/2 > 0 {
			T -= T - A/2 + .5
		}
		th := math.Max(0, 20*T+140)
		if g == 1 {
			if P >= th/2 {
				P = th * .35
			}
		} else if g == 2 {
			if P >= th {
				P = th * .8
			} else if P < th/2 {
				P = th * .65
			}
		} else if g != 5 && P < th {
			P = th*1.25 + 40
		}
		t[i], p[i] = float32(T), float32(P)
		if T != T0 || P != P0 {
			changed++
		}
	}
	return changed
}
func (w *World) gradeClimate() *ClimateGrade {
	if w.koppen == nil {
		return nil
	}
	g := &ClimateGrade{Code: make([]uint8, w.Len()), FitChanged: w.fitChanged}
	ok, total := 0., 0.
	rank := [6]int{3, 0, 0, 2, 1, 0}
	for _, i := range w.landList {
		og := kgGroup(w.koppen[i])
		if og < 0 {
			continue
		}
		sg := simClimateGroup(float64(w.rawTemperature[i]), float64(w.rawPrecipitation[i]), float64(w.rawAmplitude[i]))
		area := float64(w.area[i])
		g.Per[og].Total += area
		total += area
		if sg == og {
			g.Per[og].OK += area
			ok += area
			g.Code[i] = 1
			continue
		}
		sb, ob := sg == 1 || sg == 2, og == 1 || og == 2
		switch {
		case sb && !ob:
			g.Code[i] = 2
		case ob && !sb:
			g.Code[i] = 3
		case sb && ob:
			if sg == 1 {
				g.Code[i] = 2
			} else {
				g.Code[i] = 3
			}
		case rank[sg] < rank[og]:
			g.Code[i] = 4
		default:
			g.Code[i] = 5
		}
	}
	if total > 0 {
		g.Score = ok / total
	}
	return g
}
func (w *World) ClimateGrade() *ClimateGrade {
	if w.climateGrade == nil {
		return nil
	}
	g := *w.climateGrade
	g.Code = append([]uint8(nil), g.Code...)
	return &g
}
func (w *World) Koppen() []uint8 { return append([]uint8(nil), w.koppen...) }
