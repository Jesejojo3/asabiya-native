package sim

import "fmt"

func (h *history) seedTech(k int, c CellID, value float64, radius int) {
	w := h.world
	w.ring(c, radius, func(j CellID) {
		if !w.land[j] {
			return
		}
		v := value
		if j != c {
			v *= .85
		}
		if v > float64(h.tech[k][j]) {
			h.tech[k][j] = float32(v)
		}
	})
}

func (h *history) nearestPeopled(c CellID, radius int, test func(CellID) bool) CellID {
	w := h.world
	best := NoCell
	distance := int(^uint(0) >> 1)
	cx, cy := int(c)%w.config.Width, int(c)/w.config.Width
	for dy := -radius; dy <= radius; dy++ {
		y := cy + dy
		if y < 0 || y >= w.config.Height {
			continue
		}
		for dx := -radius; dx <= radius; dx++ {
			j := CellID(y*w.config.Width + (cx+dx+w.config.Width)%w.config.Width)
			if !w.land[j] || h.pop[j] < 1 || (test != nil && !test(j)) {
				continue
			}
			d := dx*dx + dy*dy
			if d < distance {
				distance = d
				best = j
			}
		}
	}
	return best
}

func cropFor(t, p, river float64) (string, string, float64) {
	if t > 22 && p > 1500 {
		return "yams and taro", "pigs and fowl", 0
	}
	if t > 20 && p > 1000 {
		if river > .3 {
			return "rice", "pigs and water buffalo", 1
		}
		return "millet and rice", "pigs and water buffalo", 1
	}
	if t > 17 && p < 900 {
		return "sorghum and millet", "cattle", 1
	}
	if t >= 9 && (p < 800 || river > .3) {
		return "wheat and barley", "sheep and goats", 1
	}
	if t < 9 {
		return "rye and oats", "cattle and sheep", 1
	}
	return "maize and beans", "turkeys and dogs", 1
}

// hearthCheck is v0.6 1114–1146. The retry years and the complete 500-draw
// search are preserved; no early exit when a promising site is encountered.
func (h *history) hearthCheck() {
	h.prepareAnnualState()
	w, r, y := h.world, h.r, h.year
	for index := range h.hearths {
		f := &h.hearths[index]
		if f.Done || y < f.Year {
			continue
		}
		c := f.Cell
		if f.Fixed {
			var test func(CellID) bool
			if f.Kind == "farm" {
				test = func(j CellID) bool { return float64(w.farmSuitability[j]) > .15 }
			}
			c = h.nearestPeopled(f.Cell, 4, test)
			if c < 0 {
				f.Year = y + 20
				continue
			}
		}
		if f.Kind == "farm" {
			if h.pop[c] < 1 || h.eth[c] < 0 {
				f.Year = y + 20
				continue
			}
			h.seedTech(TechFarm, c, 1, 2)
			h.seedTech(TechHerd, c, .6, 1)
			h.recordDiscovery(TechFarm, c)
			h.recordDiscovery(TechHerd, c)
			crop, animal, grain := f.Crop, f.Animal, 1.0
			if f.GrainSet {
				grain = f.Grain
			}
			if crop == "" {
				crop, animal, grain = cropFor(float64(w.temperature[c]), float64(w.precipitation[c]), float64(w.river[c]))
			}
			h.seedTech(TechGrain, c, grain, 2)
			h.recordDiscovery(TechGrain, c)
			e := h.peoples[h.eth[c]]
			h.chron("ideas", fmt.Sprintf("Among the %s, people begin to sow %s and keep %s.", e.Name, crop, animal), c)
			f.Done = true
			continue
		}
		if !f.Fixed {
			best := NoCell
			bestPopulation := 0.0
			for attempt := 0; attempt < 500; attempt++ {
				i := w.landList[int(r.Float64()*float64(len(w.landList)))]
				if h.pop[i] < 1 || h.eth[i] < 0 {
					continue
				}
				ok := false
				switch f.Kind {
				case "copper":
					ok = float64(h.tech[TechFarm][i]) > .5 && float64(w.roughness[i]) > .2
				case "horse":
					ok = float64(w.herdSuitability[i]) > .45 && float64(w.farmSuitability[i]) < .35 && float64(h.tech[TechHerd][i]) > .2
				case "camel":
					ok = float64(h.tech[TechHerd][i]) > .3 && (w.desert[i] || w.precipitation[i] < 350)
				case "ard":
					ok = float64(h.tech[TechFarm][i]) > .8 && float64(h.tech[TechHerd][i]) > .5 && !w.tsetse[i] && w.precipitation[i] < 900
				default:
					ok = w.coast[i] && h.pop[i] > 200
				}
				if ok && float64(h.pop[i]) > bestPopulation {
					bestPopulation = float64(h.pop[i])
					best = i
				}
			}
			if best < 0 {
				f.Year = y + 25
				continue
			}
			c = best
		}
		if h.eth[c] < 0 {
			f.Year = y + 20
			continue
		}
		e := h.peoples[h.eth[c]]
		switch f.Kind {
		case "copper":
			h.seedTech(TechCopper, c, 1, 1)
			h.chron("ideas", fmt.Sprintf("Smiths among the %s learn to smelt copper, and later bronze.", e.Name), c)
			h.recordDiscovery(TechCopper, c)
		case "horse":
			h.seedTech(TechHorse, c, 1, 1)
			h.seedTech(TechHerd, c, 1, 1)
			h.chron("ideas", fmt.Sprintf("On the grasslands, the %s tame and ride the horse.", e.Name), c)
			h.recordDiscovery(TechHorse, c)
		case "ard":
			h.seedTech(TechArd, c, 1, 1)
			h.chron("ideas", fmt.Sprintf("Farmers among the %s yoke oxen to a scratch plough; one family can now till far more land.", e.Name), c)
			h.recordDiscovery(TechArd, c)
		case "camel":
			h.seedTech(TechCamel, c, 1, 2)
			h.chron("ideas", fmt.Sprintf("The %s tame the camel; the deserts begin to open to caravans and raiders.", e.Name), c)
			h.recordDiscovery(TechCamel, c)
		default:
			h.seedTech(TechSail, c, 1, 1)
			h.chron("ideas", fmt.Sprintf("The %s build boats that can cross open sea.", e.Name), c)
		}
		f.Done = true
	}
}
