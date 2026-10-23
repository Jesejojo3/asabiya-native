package sim

import (
	"fmt"
	"math"
)

var plagueNames = []string{"fever", "pox", "sweat", "plague", "flux", "ague"}

func (h *history) virginSoil(target, source CellID) {
	gap := float64(h.plaguePool[source]) - float64(h.plaguePool[target])
	if gap > .2 && h.infection[target] == 0 && h.pop[target] > 1000 && h.r.Float64() < .35*gap {
		prefix := ""
		if e := h.eth[source]; e >= 0 {
			prefix = capFirst(h.peoples[e].Language.Lex[LexSea]) + " "
		}
		o := &Outbreak{ID: len(h.outbreaks), Name: prefix + pick(h.r, plagueNames), Origin: target, Year: h.year, Virulence: .12 + .25*gap + h.r.Float64()*.08, Cells: 1, Active: 1, Spread: [][2]int{{0, int(target)}}, Virgin: true, From: int(h.eth[source]), Pool: float64(h.plaguePool[source])}
		h.outbreaks = append(h.outbreaks, o)
		h.infection[target] = 3
		h.outbreakAt[target] = int32(o.ID)
		h.infections = append(h.infections, target)
	}
}

func (h *history) disease() {
	h.prepareAnnualState()
	w, r := h.world, h.r
	scale := h.rules.get("disease")
	for attempt := 0; attempt < 40; attempt++ {
		i := w.landList[int(r.Float64()*float64(len(w.landList)))]
		if h.pop[i] < 1 || h.infection[i] != 0 {
			continue
		}
		density := float64(h.pop[i]) / float64(w.area[i])
		if r.Float64() < scale*.0002*density*(float64(h.tech[TechFarm][i])+float64(h.tech[TechHerd][i])) {
			prefix := ""
			if e := h.eth[i]; e >= 0 {
				prefix = capFirst(h.peoples[e].Language.Lex[LexRiver]) + " "
			}
			o := &Outbreak{ID: len(h.outbreaks), Name: prefix + pick(r, plagueNames), Origin: i, Year: h.year, Virulence: .04 + r.Float64()*.13, Cells: 1, Active: 1, Spread: [][2]int{{0, int(i)}}}
			h.outbreaks = append(h.outbreaks, o)
			h.infection[i] = 3
			h.outbreakAt[i] = int32(o.ID)
			h.infections = append(h.infections, i)
		}
	}
	next := make([]CellID, 0, len(h.infections))
	for _, o := range h.outbreaks {
		if !o.Done {
			o.Active = 0
		}
	}
	for _, i := range h.infections {
		if h.infection[i] == 0 {
			continue
		}
		o := h.outbreaks[h.outbreakAt[i]]
		density := float64(h.pop[i]) / float64(w.area[i])
		virgin := 1.0
		if o.Virgin {
			virgin = 1 + 2.5*math.Max(0, o.Pool-float64(h.plaguePool[i]))
		}
		mortality := math.Min(.7, o.Virulence*(1-float64(h.immunity[i]))*(.5+.5*math.Min(1, density/15))*virgin*(1-.2*float64(h.tech[TechFeverbark][i])))
		deaths := float64(h.pop[i]) * mortality
		h.pop[i] = float32(float64(h.pop[i]) - deaths)
		o.Deaths += deaths
		o.Active++
		if id := h.pol[i]; id != 0 {
			p := h.polities[id]
			p.Shock += .003
			p.PlagueDeaths += deaths
			o.Hit.Add(int(id))
		}
		spreadTo := func(j CellID) {
			h.infection[j] = 3
			h.outbreakAt[j] = int32(o.ID)
			next = append(next, j)
			o.Cells++
			if len(o.Spread) < 4000 {
				o.Spread = append(o.Spread, [2]int{h.year - o.Year, int(j)})
			}
		}
		for _, j := range w.neighbors[i] {
			if j < 0 || h.pop[j] < 1 || h.infection[j] != 0 || float64(h.immunity[j]) > .95 || h.outbreakAt[j] == int32(o.ID) {
				continue
			}
			dj := float64(h.pop[j]) / float64(w.area[j])
			same := .7
			if h.pol[j] == h.pol[i] {
				same = 1
			}
			if r.Float64() < .4*(1-float64(h.immunity[j]))*math.Min(1, (density+dj)/8+.15)*same {
				spreadTo(j)
			}
		}
		if w.coast[i] && float64(h.tech[TechSail][i]) > .5 {
			for q := w.seaOffsets[i]; q < w.seaOffsets[i+1]; q++ {
				j := w.seaTargets[q]
				if h.pop[j] < 1 || h.infection[j] != 0 || float64(h.immunity[j]) > .95 || h.outbreakAt[j] == int32(o.ID) {
					continue
				}
				if r.Float64() < .06*(1-float64(h.immunity[j])) {
					spreadTo(j)
				}
			}
		}
		h.infection[i]--
		if h.infection[i] == 0 {
			h.immunity[i] = float32(math.Max(float64(h.immunity[i]), .85))
			if o.Virgin {
				h.plaguePool[i] = float32(math.Max(float64(h.plaguePool[i]), o.Pool*.6))
			}
		} else {
			next = append(next, i)
		}
	}
	h.infections = next
	for _, o := range h.outbreaks {
		if o.Done || o.Active > 0 || o.Year == h.year {
			continue
		}
		o.Done = true
		o.End = h.year
		if o.Deaths > 250000 {
			count := fmtK(o.Deaths)
			extra := ""
			if o.Virgin {
				extra = ", most of them people who had never met such a disease"
			}
			h.chron("plague", fmt.Sprintf("The %s burns out after killing about %s across %d provinces%s.", o.Name, count, o.Cells, extra), o.Origin)
			if o.Deaths > 5e6 {
				h.spot(fmt.Sprintf("The %s has killed %s", o.Name, count), o.Origin)
			}
		}
	}
	if h.year%5 == 0 {
		for _, i := range w.landList {
			h.immunity[i] = float32(float64(h.immunity[i]) * .927)
		}
	}
}
