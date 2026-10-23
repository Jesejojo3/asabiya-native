package sim

import (
	"fmt"
	"math"
	"strconv"
)

// jsPairKey reproduces [a,b].sort().join(':'): lexical, not numeric order.
func jsPairKey(a, b int) string {
	x, y := strconv.Itoa(a), strconv.Itoa(b)
	if y < x {
		x, y = y, x
	}
	return x + ":" + y
}

func (h *history) cropExchange(a, b CellID) {
	w := h.world
	if float64(h.tech[TechFarm][a]) < .5 || float64(h.tech[TechFarm][b]) < .5 || w.landmass[a] == w.landmass[b] || w.landmassSizes[w.landmass[a]] < 200 || w.landmassSizes[w.landmass[b]] < 200 {
		return
	}
	key := jsPairKey(int(w.landmass[a]), int(w.landmass[b]))
	if h.cropPairs.Has(key) {
		return
	}
	h.cropPairs.Add(key)
	h.seedTech(TechXCrops, a, 1, 1)
	h.seedTech(TechXCrops, b, 1, 1)
	h.recordDiscovery(TechXCrops, b)
	ca, _, _ := cropFor(float64(w.temperature[a]), float64(w.precipitation[a]), float64(w.river[a]))
	cb, _, _ := cropFor(float64(w.temperature[b]), float64(w.precipitation[b]), float64(w.river[b]))
	first, second := "homeland", "far shore"
	if h.eth[a] >= 0 {
		first = h.peoples[h.eth[a]].Name
	}
	if h.eth[b] >= 0 {
		second = h.peoples[h.eth[b]].Name
	}
	if cb == ca {
		cb = "other crops"
	}
	h.chron("ideas", fmt.Sprintf("Ships carry %s to the %s, and bring %s home to the %s. Over the coming centuries the new crops will let poor and marginal soils feed far more people.", ca, second, cb, first), b)
	h.spot("New crops cross the ocean", b)
}

func (h *history) seaHop() {
	h.prepareAnnualState()
	w, r := h.world, h.r
	c := w.coastList
	if len(c) == 0 {
		return
	}
	expected := float64(len(c)) * .004 * h.rules.get("seafaring")
	tries := int(math.Floor(expected))
	if r.Float64() < math.Mod(expected, 1) {
		tries++
	}
	for ; tries > 0; tries-- {
		i := c[int(r.Float64()*float64(len(c)))]
		if h.pop[i] < 30 {
			continue
		}
		sailing := float64(h.tech[TechSail][i])
		if r.Float64() > .04+.5*sailing {
			continue
		}
		angle := r.Float64() * 6.2832
		dx, dy := math.Cos(angle), math.Sin(angle)*.8
		reach := 2 + int(math.Floor(sailing*28)) + int(r.Float64()*3)
		if float64(h.tech[TechNavigation][i]) > .5 {
			reach += 14
		}
		if float64(h.tech[TechOcean][i]) > .5 {
			reach += 70
		}
		x, y := float64(int(i)%w.config.Width)+.5, float64(int(i)/w.config.Width)+.5
		seen := false
		target := NoCell
		for step := 0; float64(step) < float64(reach)*1.5; step++ {
			x += dx * .7
			y += dy * .7
			if y < 0 || y >= float64(w.config.Height) {
				break
			}
			j := CellID(int(math.Floor(y))*w.config.Width + (int(math.Floor(x))%w.config.Width+w.config.Width)%w.config.Width)
			if !w.land[j] {
				seen = true
				continue
			}
			if seen {
				target = j
				break
			}
		}
		if target < 0 || w.temperature[target] < -9 {
			continue
		}
		if h.pop[target] < 1 {
			h.pop[target] = float32(math.Min(60+float64(h.pop[i])*.02, float64(h.K[target])*.5+1))
			h.eth[target] = h.eth[i]
			h.religion[target] = h.religion[i]
			h.cohesion[target] = .4
			for k := range h.tech {
				h.tech[k][target] = float32(math.Max(float64(h.tech[k][target]), float64(h.tech[k][i])*.8))
			}
			h.tech[TechWriting][target] = float32(float64(h.tech[TechWriting][target]) * .3)
			mass := w.landmass[target]
			if h.lmFound[mass] == 0 {
				h.lmFound[mass] = 1
				if w.landmassSizes[mass] >= 4 {
					name := "island"
					if w.landmassSizes[mass] > 60 {
						name = "land"
					}
					h.chron("migration", fmt.Sprintf("Seafarers of the %s reach an unpeopled %s.", h.peoples[h.eth[i]].Name, name), target)
				}
			}
		} else if h.eth[target] != h.eth[i] {
			for k := range h.tech {
				h.tech[k][target] = float32(math.Max(float64(h.tech[k][target]), float64(h.tech[k][i])*.5))
			}
			if float64(h.tech[TechOcean][i]) > .5 && w.landmass[target] != w.landmass[i] {
				h.virginSoil(target, i)
				h.cropExchange(i, target)
				h.mixIn(target, int(h.eth[i]), .05)
				e1, e2 := h.peoples[h.eth[i]], h.peoples[h.eth[target]]
				key := strconv.Itoa(e1.Family) + ":" + strconv.Itoa(e2.Family)
				if e1.Family != e2.Family && !h.contacts.Has(key) && w.landmassSizes[w.landmass[target]] > 200 {
					h.contacts.Add(key)
					h.chron("migration", fmt.Sprintf("Ocean-going ships of the %s make landfall among the %s, across the open ocean.", e1.Name, e2.Name), target)
					h.spot(fmt.Sprintf("Ships of the %s reach the %s across the ocean", e1.Name, e2.Name), target)
				}
			}
		}
	}
}
