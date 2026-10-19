package sim

import "math"

// growth keeps the local (unrounded) p for ecological effects after writing the
// float32 population array, including fertility recovery and salinity order.
func (h *history) growth() {
	h.prepareAnnualState()
	w := h.world
	growth, degrade := h.rules.get("growth"), h.rules.get("degrade")
	for _, i := range w.landList {
		p := float64(h.pop[i])
		if p <= 0 {
			continue
		}
		capacity := float64(h.K[i])
		t := func(k int) float64 { return float64(h.tech[k][i]) }
		if p < capacity {
			p += growth * p * (1 - p/capacity) * (.6 + .4*math.Min(1, t(TechFarm)+.5*t(TechHerd)))
		} else {
			excess := (p - capacity) * .2
			p -= excess
			if h.pol[i] == 0 && p > 1.2*capacity && p > 20000 && h.eth[i] >= 0 {
				h.pushPressure(int(h.eth[i]), excess*.35, i, 0, -1)
			}
		}
		if p < .5 {
			p = 0
			h.eth[i] = -1
			h.eth2[i] = -1
			h.religion[i] = -1
		}
		h.pop[i] = float32(p)
		pressure, farm := p/capacity, t(TechFarm)
		if farm > .3 && float64(w.farmSuitability[i]) > .1 {
			silt, leach := clamp(float64(w.river[i])*1.5, 0, .8), float64(w.leach[i])
			if pressure > .7 {
				h.fert[i] = float32(math.Max(.3, float64(h.fert[i])-degrade*.0012*(pressure-.7)*farm*(1+1.5*leach)*(1-.45*t(TechCrops))*(1-.5*t(TechManure))*(1-silt)))
			}
			extra := 0.0
			if pressure < .5 {
				extra = 1 + leach
			}
			h.fert[i] = float32(float64(h.fert[i]) + .0025*(1-float64(h.fert[i]))*(1+.6*t(TechHerd)*float64(w.herdSuitability[i])+extra))
			if float64(h.forest[i]) < .15 && float64(w.roughness[i]) > .3 {
				h.fert[i] = float32(math.Max(.3, float64(h.fert[i])-.0003*float64(w.roughness[i])*farm))
			}
			irrigation := t(TechIrrigation) * math.Min(1, float64(w.river[i])*2)
			if irrigation > .1 && w.precipitation[i] < 550 && pressure > .5 {
				h.salt[i] = float32(math.Min(.85, float64(h.salt[i])+.0004*irrigation*math.Min(1.2, pressure)*(1-.9*t(TechSaltFlush))))
			}
			if h.salt[i] > 0 && (pressure < .3 || t(TechSaltFlush) > .5) {
				h.salt[i] = float32(math.Max(0, float64(h.salt[i])-.0004-.002*t(TechSaltFlush)))
			}
		}
		forest0 := float64(w.forest[i])
		if forest0 > 0 {
			forest := float64(h.forest[i])
			if farm > .2 && pressure > .6 {
				forest -= .0015 * farm * math.Min(1, (pressure-.6)*2.5) * forest * (1 + 2.5*t(TechIron) + .5*t(TechCopper))
			} else {
				forest += .004 * (forest0 - forest) * (1 - .6*t(TechHerd)*math.Min(1, pressure*3))
			}
			h.forest[i] = float32(clamp(forest, 0, forest0))
		}
		if h.rp[i] > 0 {
			h.rp[i] = float32(float64(h.rp[i]) * .96)
		}
		if w.malaria[i] > 0 {
			h.adapt[i] = float32(float64(h.adapt[i]) + .0012*float64(w.malaria[i])*math.Max(0, .55-float64(h.adapt[i])))
		}
	}
}

func (h *history) mixIn(cell CellID, people int, share float64) {
	if people < 0 || people == int(h.eth[cell]) {
		return
	}
	if int(h.eth2[cell]) == people {
		h.mix[cell] = float32(math.Min(1, float64(h.mix[cell])+share))
	} else if h.eth2[cell] < 0 || share > float64(h.mix[cell]) {
		h.eth2[cell] = int32(people)
		h.mix[cell] = float32(share)
		h.mixTime[cell] = 0
	}
}

func (h *history) migrate() {
	h.prepareAnnualState()
	w, r := h.world, h.r
	mg := h.rules.get("migration")
	reverse := h.year&1 != 0
	for k := 0; k < len(w.landList); k++ {
		index := k
		if reverse {
			index = len(w.landList) - 1 - k
		}
		i := w.landList[index]
		p := float64(h.pop[i])
		if p < 1 {
			continue
		}
		pressure := p / float64(h.K[i])
		if pressure < .55 {
			continue
		}
		j := w.neighbors[i][int(r.Float64()*4)]
		if j < 0 || !w.land[j] {
			continue
		}
		capacity := float64(h.K[j])
		if capacity < 2 && float64(w.farmSuitability[j]) < .05 && float64(w.herdSuitability[j]) < .05 {
			continue
		}
		area := float64(w.area[j])
		effective := math.Max(capacity, math.Max(area*3*float64(w.farmSuitability[j])*float64(h.tech[TechFarm][i])*(1+.6*float64(h.tech[TechCopper][i])+.6*float64(h.tech[TechIron][i])), area*1.1*float64(w.herdSuitability[j])*float64(h.tech[TechHerd][i])))
		population := float64(h.pop[j])
		difference := pressure - population/effective
		if difference < .1 {
			continue
		}
		mobility := mg * (.08 + .25*float64(h.tech[TechHerd][i])*float64(w.herdSuitability[i])*(.5+float64(h.tech[TechHorse][i])))
		if h.pol[j] != 0 && h.pol[j] != h.pol[i] {
			mobility *= .4
		} else if h.pol[i] != 0 && h.pol[j] == 0 {
			o := h.polities[h.pol[i]]
			if o.Kind == "state" {
				mobility *= 1 + 2*math.Max(0, o.Burden-.7) + 1.5*math.Max(0, o.Inequality-.5)
			}
		}
		moved := math.Min(p*mobility*difference/(1+difference), p*.3)
		h.pop[i] = float32(float64(h.pop[i]) - moved)
		h.pop[j] = float32(float64(h.pop[j]) + moved)
		if population < 1 || h.eth[j] < 0 {
			h.eth[j] = h.eth[i]
			h.eth2[j] = -1
			h.religion[j] = h.religion[i]
			h.cohesion[j] = h.cohesion[i]
			h.adapt[j] = h.adapt[i]
			for f := range h.tech {
				h.tech[f][j] = float32(math.Max(float64(h.tech[f][j]), float64(h.tech[f][i])*.9))
			}
		} else if h.eth[j] != h.eth[i] {
			h.mixIn(j, int(h.eth[i]), moved/(population+moved)*.6)
			if h.eth2[j] == h.eth[i] && h.mix[j] > .5 {
				old := h.eth[j]
				h.eth[j] = h.eth2[j]
				h.eth2[j] = old
				h.mix[j] = float32(1 - float64(h.mix[j]))
			}
			for f := range h.tech {
				h.tech[f][j] = float32(math.Max(float64(h.tech[f][j]), float64(h.tech[f][i])*.8))
			}
		}
	}
}
