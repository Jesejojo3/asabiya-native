package sim

import (
	"fmt"
	"math"
)

func (h *history) polShape(o *Polity) *RealmShape {
	w := h.world
	columns := make([]bool, w.config.Width)
	la0, la1, sum, count := 90., -90., 0., 0
	for _, i := range w.landList {
		if h.pol[i] != int32(o.ID) || h.isWaste(i, false) {
			continue
		}
		latitude := float64(w.latitude[i]) * 57.2958
		la0 = math.Min(la0, latitude)
		la1 = math.Max(la1, latitude)
		columns[int(i)%w.config.Width] = true
		sum += latitude
		count++
	}
	if count < 10 {
		return nil
	}
	gap, run := 0, 0
	for k := 0; k < 2*w.config.Width; k++ {
		if columns[k%w.config.Width] {
			run = 0
		} else {
			run++
			gap = max(gap, run)
		}
	}
	gap = min(gap, w.config.Width)
	span := float64(w.config.Width-gap+1) * 360 / float64(w.config.Width)
	mean := sum / float64(count)
	eastWest := span * 111 * math.Cos(mean/57.2958)
	northSouth := (la1 - la0 + 180/float64(w.config.Height)) * 111
	return &RealmShape{EW: int(jsRound(eastWest)), NS: int(jsRound(northSouth)), N: count}
}
func (h *history) shapePass() {
	for _, id := range h.alive {
		o := h.polities[id]
		if o.Kind != "state" {
			continue
		}
		real := o.Cells - o.WasteN
		if real < 60 || float64(real) < float64(o.ShapeN)*1.08 {
			continue
		}
		shape := h.polShape(o)
		if shape == nil {
			continue
		}
		o.ShapeN = real
		o.Shape = shape
		if !o.InShapes {
			o.InShapes = true
			h.shapes = append(h.shapes, o.ID)
		}
	}
}
func (h *history) regionPass() {
	if h.year%50 == 0 {
		h.shapePass()
	}
	clear(h.landmassPopulation)
	for _, i := range h.world.landList {
		if h.pop[i] >= 1 {
			h.landmassPopulation[h.world.landmass[i]]++
		}
	}
	remaining := h.darkWatch[:0]
	for _, watch := range h.darkWatch {
		if h.year-watch.Year < 100 {
			remaining = append(remaining, watch)
			continue
		}
		literacy := 0.
		for _, c := range watch.Cells {
			literacy += float64(h.tech[TechWriting][c])
		}
		literacy /= math.Max(1, float64(len(watch.Cells)))
		o := h.polities[watch.Polity]
		if literacy < .3 && o != nil {
			h.chron("culture", fmt.Sprintf("A century after the fall of the %s, writing has fallen out of use in most of its old lands.", o.PeakName), o.Capital)
		}
	}
	h.darkWatch = remaining
	h.earthRegionPass()
}
