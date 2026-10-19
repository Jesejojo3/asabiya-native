package sim

import "math"

// Geometry preserves the original float32 spherical fields. GridX/GridY are
// derived rather than stored twice; their ranges fit the legacy Int16 arrays.
type Geometry struct {
	X3           float32 `json:"x3"`
	Y3           float32 `json:"y3"`
	Z3           float32 `json:"z3"`
	CosLongitude float32 `json:"cosLon"`
	SinLongitude float32 `json:"sinLon"`
	CosLatitude  float32 `json:"cosLat"`
	GridX        int16   `json:"cxA"`
	GridY        int16   `json:"cyA"`
}

func (w *World) prepareGeometry() {
	n := w.Len()
	w.x3 = make([]float32, n)
	w.y3 = make([]float32, n)
	w.z3 = make([]float32, n)
	w.cosLon = make([]float32, n)
	w.sinLon = make([]float32, n)
	w.cosLat = make([]float32, n)
	for i := 0; i < n; i++ {
		x, y := i%w.config.Width, i/w.config.Width
		lat := (90 - (float64(y)+.5)/float64(w.config.Height)*180) * math.Pi / 180
		lon := ((float64(x)+.5)/float64(w.config.Width)*360 - 180) * math.Pi / 180
		w.cosLon[i] = float32(math.Cos(lon))
		w.sinLon[i] = float32(math.Sin(lon))
		w.x3[i] = float32(math.Cos(lat) * math.Cos(lon))
		w.y3[i] = float32(math.Cos(lat) * math.Sin(lon))
		w.z3[i] = float32(math.Sin(lat))
		// v0.6 intentionally reads the rounded latitude typed array here.
		w.cosLat[i] = float32(math.Max(.2, math.Cos(float64(w.latitude[i]))))
	}
}

func (w *World) geometry(i int) Geometry {
	return Geometry{X3: w.x3[i], Y3: w.y3[i], Z3: w.z3[i], CosLongitude: w.cosLon[i], SinLongitude: w.sinLon[i], CosLatitude: w.cosLat[i], GridX: int16(i % w.config.Width), GridY: int16(i / w.config.Width)}
}

// visit8 is the exact dy-then-dx order of genWorld's n8: no polar wrapping,
// longitudinal wrapping, and diagonals. Do not replace with four-neighbor order.
func (w *World) visit8(i CellID, visit func(CellID)) {
	x, y := int(i)%w.config.Width, int(i)/w.config.Width
	for dy := -1; dy <= 1; dy++ {
		yy := y + dy
		if yy < 0 || yy >= w.config.Height {
			continue
		}
		for dx := -1; dx <= 1; dx++ {
			if dx == 0 && dy == 0 {
				continue
			}
			visit(CellID(yy*w.config.Width + (x+dx+w.config.Width)%w.config.Width))
		}
	}
}
