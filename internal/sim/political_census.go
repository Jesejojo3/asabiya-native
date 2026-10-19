package sim

import (
	"fmt"
	"math"
	"slices"
	"sort"
	"strings"
)

type polityCensus struct {
	sS, dS, ad, nom, cx, cy, yy, ig float64
	n                               [4]float64
	nw, foreign                     float64
}

func (h *history) politicalCensus() {
	w, r := h.world, h.r
	sample := h.year%10 == 0
	counts := make([]polityCensus, len(h.polities))
	for _, id := range h.alive {
		o := h.polities[id]
		o.Pop = 0
		o.K = 0
		o.Cells = 0
		o.MaxProvincePopulation = -1
		o.MaxProvince = NoCell
		o.CoastN = 0
		o.FarmN = 0
		o.FortN = 0
		o.LandmassN = 0
		o.Tax = 0
		o.WasteN = 0
		o.PloughN = 0
		o.HeavyN = 0
		o.Trade = 0
		o.CensusReady = true
		if sample {
			o.Sample = []CellID{}
		}
	}
	for _, i := range w.landList {
		id := h.pol[i]
		if id == 0 {
			continue
		}
		o := h.polities[id]
		v := &counts[id]
		pp := float64(h.pop[i])
		o.Pop += pp
		o.K += float64(h.K[i])
		o.Cells++
		v.sS += float64(h.cohesion[i])
		distance := h.dd(i)
		v.dS += distance
		ecology := 0.
		if pp >= 1 {
			v.n[0] += pp * float64(w.nicheTemperature[i])
			v.n[1] += pp * float64(w.nicheMoisture[i])
			v.n[2] += pp * float64(w.nicheLifestyle[i])
			v.n[3] += pp * float64(w.nicheDisease[i])
			v.nw += pp
			if o.Niche != nil {
				ecology = h.ecoD(i, o)
				if ecology > .8 {
					v.foreign += pp
				}
			}
		}
		v.ad += float64(h.tech[TechWriting][i])
		v.ig += float64(h.integ[i])
		plough := float64(h.tech[TechArd][i]) > .5 && !w.tsetse[i]
		reach := o.Reach
		if reach == 0 {
			reach = 6
		}
		if pp >= 1 {
			bonus := .8
			if plough {
				bonus = 1.1
			}
			o.Tax += pp * float64(h.tech[TechFarm][i]) * h.cerealEff(i) * math.Exp(-distance/reach) * (.5 + .5*float64(h.integ[i])) * (.6 + .4*float64(h.circE[i])) * bonus / (1 + .3*h.rules.get("eco")*ecology)
		}
		if plough {
			o.PloughN++
		}
		if float64(w.heavySoil[i]) > .4 {
			o.HeavyN++
		}
		if h.isWaste(i, o.Kind == "horde") {
			o.WasteN++
		}
		if float64(h.caravan[i]) > .3 {
			trade := 1500 * float64(h.caravan[i])
			o.Tax += trade
			o.Trade += trade
		}
		if w.nomad[i] {
			v.nom++
		}
		if w.coast[i] {
			o.CoastN++
		}
		if float64(h.tech[TechFarm][i]) > .5 && float64(w.farmSuitability[i]) > .25 && pp/float64(w.area[i]) > 2 {
			o.FarmN++
		}
		if float64(h.fort[i]) > .5 {
			o.FortN++
		}
		v.cx += float64(w.cosLon[i])
		v.cy += float64(w.sinLon[i])
		v.yy += float64(int(i) / w.config.Width)
		if pp > o.MaxProvincePopulation {
			o.MaxProvincePopulation = pp
			o.MaxProvince = i
		}
		if sample {
			if len(o.Sample) < 24 {
				o.Sample = append(o.Sample, i)
			} else if r.Float64() < 24/float64(o.Cells) {
				o.Sample[int(r.Float64()*24)] = i
			}
		}
	}
	next := []int{}
	for _, id := range h.alive {
		o := h.polities[id]
		v := counts[id]
		if o.Cells == 0 {
			o.Alive = false
			o.Died = h.year
			o.Enemies.Each(func(q, _ int) {
				p := h.polities[q]
				if p != nil {
					p.Enemies.Delete(id)
				}
			})
			o.Enemies.Clear()
			for _, q := range o.Allies {
				p := h.polities[q]
				if p != nil {
					p.Allies = slices.DeleteFunc(p.Allies, func(x int) bool { return x == id })
				}
			}
			if o.Ruler.Figure >= 0 {
				f := h.figures[o.Ruler.Figure]
				if f.Died == 0 {
					f.Died = h.year
					h.deed(f, "Died as the "+o.Full+" fell")
				}
			}
			var successorCounts orderedMap[int, int]
			for _, c := range o.Sample {
				q := int(h.pol[c])
				if q != 0 && q != id {
					successorCounts.Set(q, successorCounts.Value(q)+1)
				}
			}
			pairs := [][2]int{}
			successorCounts.Each(func(q, c int) { pairs = append(pairs, [2]int{q, c}) })
			sort.SliceStable(pairs, func(i, j int) bool { return pairs[i][1] > pairs[j][1] })
			o.Successors = []int{}
			for _, p := range pairs[:min(6, len(pairs))] {
				o.Successors = append(o.Successors, p[0])
			}
			if o.MaxCells >= 40 {
				h.fallen = append(h.fallen, o)
				if len(h.fallen) > 60 {
					h.fallen = h.fallen[1:]
				}
				if float64(h.tech[TechWriting][o.Capital]) > .6 {
					h.darkWatch = append(h.darkWatch, DarkWatch{Year: h.year, Polity: id, Cells: slices.Clone(o.Sample)})
				}
			}
			if !o.Departed && o.MaxCells >= 25 {
				by := ""
				if o.LastBy != 0 && h.polities[o.LastBy] != nil {
					by = " by the " + h.polities[o.LastBy].Full
				}
				successors := []string{}
				for _, k := range o.Successors[:min(3, len(o.Successors))] {
					if p := h.polities[k]; p != nil {
						successors = append(successors, p.Full)
					}
				}
				lands := ""
				if len(successors) > 0 {
					lands = " Its lands pass to the " + strings.Join(successors, ", the ") + "."
				}
				h.chron("fall", fmt.Sprintf("The %s is extinguished%s. Founded %s, it held %d provinces at its height.%s", o.PeakName, by, formatYear(o.Born), o.MaxCells, lands), o.Capital)
			}
			continue
		}
		next = append(next, id)
		if v.nw > 0 {
			var niche [4]float64
			for q := range niche {
				niche[q] = v.n[q] / v.nw
				if o.Niche != nil {
					niche[q] = o.Niche[q]*.8 + niche[q]*.2
				}
			}
			o.Niche = &niche
		}
		o.ForeignShare = 0
		if o.Pop > 0 {
			o.ForeignShare = v.foreign / o.Pop
		}
		o.ForeignPopulation = v.foreign
		o.S = v.sS / float64(o.Cells)
		o.Integration = v.ig / float64(o.Cells)
		o.Press = 1
		if o.K > 0 {
			o.Press = o.Pop / o.K
		}
		o.MD = v.dS / float64(o.Cells)
		o.ADM = v.ad / float64(o.Cells)
		o.NomF = v.nom / float64(o.Cells)
		if h.pol[o.Capital] != int32(id) && o.MaxProvince >= 0 {
			o.Capital = o.MaxProvince
			if h.eth[o.Capital] >= 0 && !o.ConquestDynasty {
				o.Core = int(h.eth[o.Capital])
			}
		}
		if o.Kind == "horde" && float64(o.FarmN) >= math.Max(3, float64(o.Cells)*.3) {
			old := o.Full
			o.Kind = "state"
			o.ConquestDynasty = true
			o.SettledYear = h.year
			o.Origin.Settled = h.year
			o.Tier = h.tierOf(o)
			o.Full = fullName(o)
			if o.Cells >= 8 {
				h.chron("rise", "Masters now of settled farmland, the "+old+" put down roots and rule as the "+o.Full+".", o.Capital)
				h.spot("Nomad conquerors settle as the "+o.Full, o.Capital)
			}
		}
		o.Tier = h.tierOf(o)
		o.Full = fullName(o)
		if o.Cells > o.MaxCells {
			o.MaxCells = o.Cells
			o.PeakName = o.Full
		}
		if o.Pop > o.MaxPop {
			o.MaxPop = o.Pop
		}
		o.LX = math.Atan2(v.cy, v.cx)
		o.LY = v.yy / float64(o.Cells)
		c := o.Capital
		tierBonus := 0.
		switch o.Tier {
		case "Empire", "Khaganate":
			tierBonus = 1.6
		case "Kingdom", "Khanate":
			tierBonus = .8
		}
		o.Specialization = clamp(.9*math.Log10(math.Max(o.Pop, 1000))-2.7+.6*math.Log10(float64(o.Cells)+1)+tierBonus+float64(h.tech[TechWriting][c])+.8*float64(h.tech[TechLaw][c])+.6*float64(h.tech[TechCoin][c])+.5*float64(h.tech[TechPaper][c])+.5*float64(h.tech[TechRoads][c]), 0, 10)
	}
	h.alive = next
	for _, i := range w.landList {
		if id := h.pol[i]; id != 0 {
			o := h.polities[id]
			if w.landmass[i] == w.landmass[o.Capital] {
				o.LandmassN++
			}
		}
	}
}
