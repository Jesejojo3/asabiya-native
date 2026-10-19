package sim

import (
	"fmt"
	"math"
)

func (h *history) localPop(i CellID) float64 {
	t := float64(h.pop[i])
	for _, j := range h.world.neighbors[i] {
		if j >= 0 {
			t += float64(h.pop[j])
		}
	}
	return t * 1.8
}
func (h *history) exitPass(start, end float64) {
	h.prepareAnnualState()
	w := h.world
	for k, stop := int(math.Floor(start*float64(len(w.landList)))), int(math.Floor(end*float64(len(w.landList)))); k < stop; k++ {
		i := w.landList[k]
		if h.pop[i] < 1 || float64(w.farmSuitability[i]) < .1 {
			h.circE[i] = w.circumscription[i]
			continue
		}
		cx, cy := int(i)%w.config.Width, int(i)/w.config.Width
		total, n := 0., 0
		for dy := -3; dy <= 3; dy++ {
			yy := cy + dy
			if yy < 0 || yy >= w.config.Height {
				continue
			}
			for dx := -3; dx <= 3; dx++ {
				if dx == 0 && dy == 0 {
					continue
				}
				j := CellID(yy*w.config.Width + (cx+dx+w.config.Width)%w.config.Width)
				n++
				if !w.land[j] {
					continue
				}
				warm := .3
				if w.temperature[j] > 10 {
					warm = 1
				}
				quality := math.Max(float64(w.farmSuitability[j]), math.Max(.5*float64(w.forest[j])*warm, .4*float64(w.herdSuitability[j])))
				density := math.Max(.3, 7*quality)
				political := 1.
				if h.pol[j] != 0 {
					political = .4
				}
				total += quality * math.Max(0, 1-float64(h.pop[j])/float64(w.area[j])/density) * political
			}
		}
		ex, own := total/float64(n), float64(w.farmSuitability[i])+.1
		h.exit[i] = float32(ex)
		h.circE[i] = float32(clamp(math.Max(float64(w.circumscription[i]), 1-1.6*ex/own), 0, 1))
	}
}
func (h *history) poolPass() {
	h.prepareAnnualState()
	w, r := h.world, h.r
	for _, i := range w.landList {
		if h.pop[i] < 1 {
			h.plaguePool[i] = float32(float64(h.plaguePool[i]) * .98)
			continue
		}
		density := float64(h.pop[i]) / float64(w.area[i])
		city := 0.
		if h.city[i] >= 0 {
			city = .2
		}
		target := math.Min(1, .22*math.Log10(1+density)+.3*float64(h.tech[TechHerd][i])*float64(h.tech[TechFarm][i])+city)
		maximum := float64(h.plaguePool[i])
		for _, j := range w.neighbors[i] {
			if j < 0 || h.pop[j] < 1 {
				continue
			}
			contact := math.Min(1, math.Sqrt(float64(h.pop[i])*float64(h.pop[j]))/20000+float64(h.caravan[i]))
			maximum = math.Max(maximum, float64(h.plaguePool[j])*(.9+.08*contact))
		}
		if w.coast[i] && float64(h.tech[TechSail][i]) > .5 {
			for q := w.seaOffsets[i]; q < w.seaOffsets[i+1]; q++ {
				j := w.seaTargets[q]
				if h.pop[j] >= 1 {
					maximum = math.Max(maximum, float64(h.plaguePool[j])*.92)
				}
			}
		}
		h.bfsParent[i] = int32(jsRound(1000 * (float64(h.plaguePool[i]) + .06*(math.Max(target, maximum)-float64(h.plaguePool[i])))))
	}
	// v0.6 reuses the BFS parent scratch array, including stale slots for empty
	// cells. Do not silently replace those slots with the decayed dp value.
	for _, i := range w.landList {
		h.plaguePool[i] = float32(float64(h.bfsParent[i]) / 1000)
	}
	if r.Float64() < .04*h.rules.get("disease") {
		for attempt := 0; attempt < 60; attempt++ {
			c := w.landList[int(r.Float64()*float64(len(w.landList)))]
			if float64(h.tech[TechHerd][c]) < .6 || float64(w.herdSuitability[c]) < .3 || h.pop[c] < 100 {
				continue
			}
			n := 0
			cx, cy := int(c)%w.config.Width, int(c)/w.config.Width
			for dy := -9; dy <= 9; dy++ {
				yy := cy + dy
				if yy < 0 || yy >= w.config.Height {
					continue
				}
				for dx := -9; dx <= 9; dx++ {
					j := CellID(yy*w.config.Width + (cx+dx+w.config.Width)%w.config.Width)
					if w.land[j] && float64(h.tech[TechHerd][j]) > .3 && dx*dx+dy*dy <= 81 {
						h.rp[j] = float32(math.Max(float64(h.rp[j]), .65))
						n++
					}
				}
			}
			extra := ""
			e := h.eth[c]
			if e >= 0 {
				extra = " of the " + h.peoples[e].Name
			}
			h.chron("plague", "A cattle plague sweeps the herds"+extra+"; herders lose most of their beasts, and hunger drives many from the land.", c)
			if e >= 0 {
				h.pushPressure(int(e), float64(h.pop[c])*.3*math.Min(20, float64(n)), c, 0, -1)
			}
			break
		}
	}
}

func (h *history) caravanPass() {
	h.prepareAnnualState()
	w, r := h.world, h.r
	for _, i := range w.landList {
		if h.caravan[i] > 0 {
			h.caravan[i] = float32(float64(h.caravan[i]) * .82)
		}
	}
	arid := func(j CellID) bool { return w.land[j] && (w.desert[j] || w.precipitation[j] < 300) }
	sources := []CellID{}
	for t := 0; t < 2500 && len(sources) < 14; t++ {
		i := w.landList[int(r.Float64()*float64(len(w.landList)))]
		if arid(i) || h.pol[i] == 0 || float64(h.pop[i])/float64(w.area[i]) < 1.5 {
			continue
		}
		if float64(h.tech[TechCamel][i]) < .5 && float64(h.tech[TechWindCart][i]) < .5 {
			continue
		}
		ok := false
		for _, j := range w.neighbors[i] {
			if j >= 0 && arid(j) {
				ok = true
			}
		}
		if ok {
			sources = append(sources, i)
		}
	}
	for _, a := range sources {
		h.bfsStamp++
		stamp := h.bfsStamp
		q := []CellID{a}
		h.bfsMark[a] = stamp
		h.bfsParent[a] = -1
		h.bfsDistance[a] = 0
		hit := NoCell
		for head := 0; head < len(q) && hit < 0; head++ {
			i := q[head]
			if h.bfsDistance[i] > 70 {
				break
			}
			for _, j := range w.neighbors[i] {
				if j < 0 || !w.land[j] || h.bfsMark[j] == stamp {
					continue
				}
				if arid(j) {
					if len(q) < 6000 {
						h.bfsMark[j] = stamp
						h.bfsParent[j] = int32(i)
						h.bfsDistance[j] = h.bfsDistance[i] + 1
						q = append(q, j)
					}
				} else if h.bfsDistance[i] >= 8 && float64(h.pop[j])/float64(w.area[j]) > 1.5 && h.pol[j] != h.pol[a] {
					h.bfsParent[j] = int32(i)
					hit = j
					break
				}
			}
		}
		if hit < 0 {
			continue
		}
		path := []CellID{}
		for c, guard := hit, 0; c >= 0 && guard < 200; c, guard = CellID(h.bfsParent[c]), guard+1 {
			path = append(path, c)
			if c == a {
				break
			}
		}
		for _, c := range path {
			h.caravan[c] = 1
		}
		pa := h.polities[h.pol[a]]
		var pb *Polity
		if h.pol[hit] != 0 {
			pb = h.polities[h.pol[hit]]
		}
		var ea, eb *People
		fa, fb := -1, -1
		if h.eth[a] >= 0 {
			ea = h.peoples[h.eth[a]]
			fa = ea.Family
		}
		if h.eth[hit] >= 0 {
			eb = h.peoples[h.eth[hit]]
			fb = eb.Family
		}
		key := jsPairKey(fa, fb)
		var route *TradeRoute
		for _, x := range h.routes {
			if x.Key == key {
				route = x
				break
			}
		}
		points := []CellID{}
		for k, c := range path {
			if k%2 == 0 || k == len(path)-1 {
				points = append(points, c)
			}
		}
		if route == nil {
			route = &TradeRoute{ID: len(h.routes), NativeID: len(h.routeArchive), Key: key, Born: h.year, A: a, B: hit, Path: points}
			h.routeArchive = append(h.routeArchive, route)
			h.routes = append(h.routes, route)
			if ea != nil && eb != nil && ea.Family != eb.Family && !h.caravanPairs.Has(key) {
				h.caravanPairs.Add(key)
				an, bn := ea.Name, eb.Name
				if pa != nil {
					an = pa.Full
				}
				if pb != nil {
					bn = pb.Full
				}
				h.chron("migration", fmt.Sprintf("Caravans begin to cross the desert between the %s and the %s, carrying salt, gold, slaves and ideas.", an, bn), path[len(path)>>1])
			}
		} else {
			route.Path = points
			route.A = a
			route.B = hit
		}
		route.Last = h.year
	}
	next := h.routes[:0]
	for _, route := range h.routes {
		if h.year-route.Last < 80 {
			next = append(next, route)
		}
	}
	h.routes = next
}
