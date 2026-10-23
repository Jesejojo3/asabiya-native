package sim

import (
	"fmt"
	"math"
)

func (h *history) mixPass() {
	h.prepareAnnualState()
	w, r := h.world, h.r
	born := 0
	for _, i := range w.landList {
		b := h.eth2[i]
		if b < 0 {
			continue
		}
		if h.pop[i] < 1 || b == h.eth[i] {
			h.eth2[i] = -1
			continue
		}
		m := float64(h.mix[i])
		if m > .5 {
			a := h.eth[i]
			h.eth[i] = b
			h.eth2[i] = a
			m = 1 - m
			h.mix[i] = float32(m)
		}
		if m < .03 {
			h.eth2[i] = -1
			h.mixTime[i] = 0
			continue
		}
		if m > .25 {
			if h.mixTime[i] < 255 {
				h.mixTime[i]++
			}
		} else if h.mixTime[i] > 0 {
			h.mixTime[i]--
		}
		if h.mixTime[i] < 15 || born >= 2 || r.Float64() >= .08*h.rules.get("mixing") {
			continue
		}
		a := h.eth[i]
		if a < 0 {
			continue
		}
		nid := h.newPeople(int(a), int(b), nil)
		born++
		q := []CellID{i}
		h.lab[i] = -7
		count, pop := 0, 0.
		for head := 0; head < len(q) && count < 60; head++ {
			c := q[head]
			ea, eb := h.eth[c], h.eth2[c]
			if (ea == a && eb == b) || (ea == b && eb == a) {
				h.eth[c] = int32(nid)
				h.eth2[c] = -1
				h.mix[c] = 0
				h.mixTime[c] = 0
				count++
				pop += float64(h.pop[c])
				for _, j := range w.neighbors[c] {
					if j >= 0 && w.land[j] && h.lab[j] != -7 {
						h.lab[j] = -7
						q = append(q, j)
					}
				}
			}
		}
		for _, c := range q {
			h.lab[c] = 0
		}
		ne := h.peoples[nid]
		if count < 5 {
			for _, c := range q {
				if h.eth[c] == int32(nid) {
					h.eth[c] = a
					h.eth2[c] = -1
				}
			}
			ne.Alive = false
			ne.Stillborn = true
			continue
		}
		if pop > 300000 {
			h.chron("people", fmt.Sprintf("From long mingling of the %s and the %s, a new people emerges: the %s.", h.peoples[a].Name, h.peoples[b].Name, ne.Name), i)
			h.spot(fmt.Sprintf("A new people, the %s, is born of the %s and %s", ne.Name, h.peoples[a].Name, h.peoples[b].Name), i)
		}
	}
}

func (h *history) newCity(c CellID, holy bool) *City {
	city := &City{ID: len(h.cities), Name: cityWord(h.langAt(c), h.r), Cell: c, Born: h.year, People: int(h.eth[c]), Peak: float64(h.pop[c]), Holy: holy}
	h.city[c] = int32(city.ID)
	h.cities = append(h.cities, city)
	return city
}
func (h *history) cityPass() {
	h.prepareAnnualState()
	// Existing cities count before new foundations, exactly as the legacy pass.
	for _, o := range h.polities {
		if o != nil && o.Alive {
			o.CityPopulation = 0
		}
	}
	for _, i := range h.world.landList {
		p := h.pol[i]
		if h.city[i] >= 0 {
			if p != 0 {
				h.polities[p].CityPopulation += float64(h.pop[i])
			}
			continue
		}
		if h.pop[i] < 120000 || float64(h.tech[TechFarm][i]) < .5 || p == 0 {
			continue
		}
		o := h.polities[p]
		if i != o.Capital && float64(h.pop[i]) < math.Max(150000, o.MaxProvincePopulation*.6) {
			continue
		}
		h.newCity(i, false)
	}
	for _, c := range h.cities {
		if float64(h.pop[c.Cell]) > c.Peak {
			c.Peak = float64(h.pop[c.Cell])
		}
	}
}

func (h *history) polCells(id int) []CellID {
	out := []CellID{}
	for _, i := range h.world.landList {
		if int(h.pol[i]) == id {
			out = append(out, i)
		}
	}
	return out
}
