package sim

import "math"

// Biome IDs retain BIOMES/biomeOf ordering from v0.6 (503–507).
type Biome uint8

const (
	Ocean Biome = iota
	Ice
	Tundra
	BorealForest
	TemperateForest
	Grassland
	Steppe
	Desert
	Savanna
	TropicalForest
)

func biomeOf(t, p float64) Biome {
	if t < -9 {
		return Ice
	}
	if t < -1 {
		return Tundra
	}
	if t < 5 {
		if p < 250 {
			return Tundra
		}
		return BorealForest
	}
	if p < 150+8*math.Max(t, 0) {
		return Desert
	}
	if p < 330+13*math.Max(t, 0) {
		return Steppe
	}
	if t >= 20 {
		if p < 1300 {
			return Savanna
		}
		return TropicalForest
	}
	if p < 700 {
		return Grassland
	}
	return TemperateForest
}

type Ecology struct {
	Biome           Biome      `json:"biome"`
	Farming         float32    `json:"sF"`
	Herding         float32    `json:"sH"`
	Nomad           bool       `json:"nomad"`
	GrowingSeason   float32    `json:"growingSeasonMonths"`
	Leaching        float32    `json:"leach"`
	Tropical        float32    `json:"tropical"`
	TravelCost      uint8      `json:"travelCost"`
	Tsetse          bool       `json:"tsetse"`
	MonsoonZone     float32    `json:"monsoonZone"`
	Desert          bool       `json:"desert"`
	InitialForest   float32    `json:"forest0"`
	HeavySoil       float32    `json:"heavySoil"`
	Malaria         float32    `json:"malaria"`
	Onchocerciasis  float32    `json:"onchocerciasis"`
	Circumscription float32    `json:"circumscription"`
	Niche           [4]float32 `json:"niche"` // temperature, moisture, lifestyle, disease
}

func (w *World) prepareSuitability() {
	n := w.Len()
	w.farmSuitability = make([]float32, n)
	w.herdSuitability = make([]float32, n)
	w.nomad = make([]bool, n)
	w.biome = make([]Biome, n)
	w.growingSeason = make([]float32, n)
	w.leach = make([]float32, n)
	w.tropical = make([]float32, n)
	for i := 0; i < n; i++ {
		if !w.land[i] {
			continue
		}
		t, p, amp := float64(w.temperature[i]), float64(w.precipitation[i]), float64(w.amplitude[i])
		rv, elev, rough := float64(w.river[i]), float64(w.elevation[i]), float64(w.roughness[i])
		tw := t + amp/2
		w.biome[i] = biomeOf(t, p)
		if t < -9 {
			continue
		}
		half := amp / 2
		gs := 0.0
		if half < .5 {
			if t > 6 {
				gs = 12
			}
		} else if t-half >= 6 {
			gs = 12
		} else if t+half > 6 {
			gs = 12 * math.Acos(clamp((6-t)/half, -1, 1)) / math.Pi
		}
		w.growingSeason[i] = float32(gs)
		cold, boreal := 1.0, 1.0
		if t < 2 {
			cold = clamp((t+4)/6, 0, 1)
		}
		if w.biome[i] == BorealForest {
			boreal = .45
		}
		ts := clamp((gs-4.3)/2.2, 0, 1) * clamp((tw-14)/7, 0, 1) * clamp((31-t)/5, 0, 1) * cold * boreal
		loess := 0.0
		if t > 9.5 && t < 18 {
			loess = .62 * clamp((p-330)/120, 0, 1) * clamp((850-p)/150, 0, 1)
		}
		ps := math.Max(clamp((p-280)/450, 0, 1)*clamp((3400-p)/1600, .25, 1), loess)
		irr := rv * clamp((tw-14)/6, 0, 1)
		leach := 0.0
		if elev < 1500 {
			leach = clamp((p-1300)/900, 0, 1) * clamp((t-21)/3, 0, 1) * (1 - clamp((rv-.55)*2.5, 0, .8))
		}
		w.leach[i] = float32(leach)
		if elev < 1200 {
			w.tropical[i] = float32(clamp((t-22)/4, 0, 1) * clamp((p-1100)/800, 0, 1))
		}
		heightPenalty := 1.0
		if elev > 3500 {
			heightPenalty = .3
		}
		w.farmSuitability[i] = float32(math.Max(ts*ps, ts*irr*.95) * (1 - .65*rough) * heightPenalty * (1 - .7*leach))
		w.herdSuitability[i] = float32(clamp((tw-4)/10, 0, 1) * clamp((27-t)/7, 0, 1) * clamp((p-120)/180, 0, 1) * clamp((1100-p)/500, .15, 1) * (1 - .4*rough))
		// Read the rounded typed-array values, as in the original.
		w.nomad[i] = float64(w.herdSuitability[i]) > .45 && float64(w.farmSuitability[i]) < .3
	}
}

func (w *World) prepareTravel() {
	n := w.Len()
	w.travelCost = make([]uint8, n)
	w.tsetse = make([]bool, n)
	w.desert = make([]bool, n)
	w.monsoonZone = make([]float32, n)
	for i := 0; i < n; i++ {
		if !w.land[i] {
			continue
		}
		t, p, lat := float64(w.temperature[i]), float64(w.precipitation[i]), float64(w.latitude[i])*180/math.Pi
		cost := 2
		switch w.biome[i] {
		case Desert:
			cost = 8
			w.desert[i] = true
		case TropicalForest, Ice, Tundra:
			cost = 6
		case BorealForest:
			cost = 3
		}
		// rough is nonnegative: floor(x+.5) matches Math.round, not bankers' rounding.
		cost += int(math.Floor(float64(w.roughness[i])*8 + .5))
		if float64(w.river[i]) > .3 {
			cost = max(1, cost>>1)
		}
		w.travelCost[i] = uint8(min(20, cost))
		w.tsetse[i] = t > 22 && p > 900 && math.Abs(lat) < 14
		if p < 520 {
			hemisphere := 1.0
			if lat <= 0 {
				hemisphere = .45
			}
			w.monsoonZone[i] = float32(clamp((33-math.Abs(lat))/8, 0, 1) * clamp((math.Abs(lat)-9)/5, 0, 1) * hemisphere * clamp((520-p)/250, 0, 1))
		}
	}
}

// prepareEcology is prepEco (1927–1943), once during world construction.
// The legacy calls it from newHistory; moving this pure, RNG-free preparation
// before publication keeps World immutable and leaves historical RNG untouched.
func (w *World) prepareEcology() {
	if w.ecoReady {
		return
	}
	n := w.Len()
	w.forest = make([]float32, n)
	w.heavySoil = make([]float32, n)
	w.malaria = make([]float32, n)
	w.oncho = make([]float32, n)
	w.circumscription = make([]float32, n)
	good := make([]float32, n)
	for i := 0; i < n; i++ {
		if !w.land[i] {
			continue
		}
		t, p, rv := float64(w.temperature[i]), float64(w.precipitation[i]), float64(w.river[i])
		if !w.desert[i] {
			w.forest[i] = float32(clamp((p-380)/520, 0, 1) * clamp((t+6)/8, 0, 1) * (1 - .5*clamp((float64(w.elevation[i])-3000)/800, 0, 1)))
		}
		w.heavySoil[i] = float32(clamp((p-650)/400, 0, 1) * clamp((17-t)/5, 0, 1) * (1 - clamp(rv*2, 0, .6)))
		if w.elevation[i] < 1500 {
			w.malaria[i] = float32(clamp((t-19)/5, 0, 1) * clamp((p-650)/700, 0, 1))
		}
		if rv > .25 && float64(w.roughness[i]) > .12 {
			w.oncho[i] = float32(clamp((t-21)/3, 0, 1) * clamp((p-700)/300, 0, 1) * clamp((1900-p)/300, 0, 1))
		}
		extra := 0.0
		if float64(w.farmSuitability[i]) > .05 {
			extra = .5 * rv
		}
		good[i] = float32(float64(w.farmSuitability[i]) + extra)
	}
	sur := append([]float32(nil), good...)
	boxBlur(sur, w.config.Width, w.config.Height, 7, 6)
	for i := 0; i < n; i++ {
		if !w.land[i] {
			continue
		}
		own := float64(good[i])
		if own < .15 {
			continue
		}
		w.circumscription[i] = float32(clamp((1-float64(sur[i])/own)*1.3, 0, 1))
	}
	w.nicheTemperature = make([]float32, n)
	w.nicheMoisture = make([]float32, n)
	w.nicheLifestyle = make([]float32, n)
	w.nicheDisease = make([]float32, n)
	for i := 0; i < n; i++ {
		if !w.land[i] {
			continue
		}
		w.nicheTemperature[i] = float32(float64(w.temperature[i]) / 8)
		w.nicheMoisture[i] = float32(2 * clamp(math.Log(math.Max(1, float64(w.precipitation[i]))/150)/math.Log(20), 0, 1))
		if w.nomad[i] {
			w.nicheLifestyle[i] = 1.2
		} else if w.desert[i] {
			w.nicheLifestyle[i] = .8
		}
		tsetse := 0.0
		if w.tsetse[i] {
			tsetse = .5
		}
		w.nicheDisease[i] = float32(.8*float64(w.malaria[i]) + tsetse)
	}
	w.ecoReady = true
}

func (w *World) ecology(i int) Ecology {
	return Ecology{Biome: w.biome[i], Farming: w.farmSuitability[i], Herding: w.herdSuitability[i], Nomad: w.nomad[i], GrowingSeason: w.growingSeason[i], Leaching: w.leach[i], Tropical: w.tropical[i], TravelCost: w.travelCost[i], Tsetse: w.tsetse[i], MonsoonZone: w.monsoonZone[i], Desert: w.desert[i], InitialForest: w.forest[i], HeavySoil: w.heavySoil[i], Malaria: w.malaria[i], Onchocerciasis: w.oncho[i], Circumscription: w.circumscription[i], Niche: [4]float32{w.nicheTemperature[i], w.nicheMoisture[i], w.nicheLifestyle[i], w.nicheDisease[i]}}
}
