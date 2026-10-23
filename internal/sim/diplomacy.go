package sim

import (
	"math"
	"slices"
)

func (h *history) affinity(o, p *Polity) (float64, *Polity) {
	affinity := 0.
	var threat *Polity
	if o.Religion >= 0 && o.Religion == p.Religion {
		affinity += .45
	} else if o.Religion >= 0 && p.Religion >= 0 {
		affinity -= .2
	}
	affinity += .3 * (1 - h.ethDistance(o.Core, p.Core))
	op, pp := h.power(o), h.power(p)
	o.NB.Each(func(id, _ int) {
		if threat != nil || id == p.ID || !p.NB.Has(id) {
			return
		}
		t := h.polities[id]
		if t != nil && t.Alive && h.power(t) > 1.3*math.Max(op, pp) {
			affinity += .45
			if t.Religion >= 0 && t.Religion != o.Religion && o.Religion == p.Religion {
				affinity += .25
			}
			threat = t
		}
	})
	expiry := o.Truce.Value(p.ID)
	if expiry == 0 {
		expiry = -1e9
	}
	if expiry > h.year-10 {
		affinity -= .4
	}
	if o.Enemies.Has(p.ID) {
		affinity -= 1
	}
	return affinity, threat
}
func (h *history) diplomacy() {
	r := h.r
	for _, id := range h.alive {
		o := h.polities[id]
		allies := []int{}
		for _, q := range o.Allies {
			p := h.polities[q]
			if p == nil || !p.Alive || o.Enemies.Has(q) {
				continue
			}
			if q > id {
				a, _ := h.affinity(o, p)
				if a < .15 && r.Float64() < .3 {
					p.Allies = slices.DeleteFunc(p.Allies, func(x int) bool { return x == id })
					if o.Cells >= 40 && p.Cells >= 40 {
						h.chron("diplomacy", "The alliance between the "+o.Full+" and the "+p.Full+" lapses.", o.Capital)
					}
					continue
				}
			}
			allies = append(allies, q)
		}
		o.Allies = allies
		if o.Cells < 2 {
			continue
		}
		o.NB.Each(func(q, _ int) {
			if q <= id {
				return
			}
			p := h.polities[q]
			if p == nil || !p.Alive || slices.Contains(o.Allies, q) || o.Enemies.Has(q) || p.Cells < 2 || len(o.Allies) >= 3 || len(p.Allies) >= 3 {
				return
			}
			a, threat := h.affinity(o, p)
			marriage := r.Float64() < .06 && o.Kind == "state" && p.Kind == "state"
			if marriage {
				a += .3
			}
			if a > .55 && r.Float64() < .25*h.rules.get("allyRate") {
				o.Allies = append(o.Allies, q)
				p.Allies = append(p.Allies, id)
				if o.Cells >= 30 && p.Cells >= 30 {
					extra := ""
					if threat != nil {
						extra = " against the " + threat.Full
					}
					if o.Religion >= 0 && o.Religion == p.Religion && threat != nil && threat.Religion != o.Religion {
						extra += ", brothers in " + h.religions[o.Religion].Name + " against an unbelieving power"
					}
					if marriage {
						extra += ", sealed by a royal marriage"
					}
					h.chron("diplomacy", "The "+o.Full+" and the "+p.Full+" conclude an alliance"+extra+".", o.Capital)
				}
			}
		})
		if o.Kind == "horde" && o.Cells >= 6 {
			o.NB.Each(func(q, _ int) {
				p := h.polities[q]
				if p == nil || !p.Alive || p.Kind == "horde" || p.Over != 0 || o.Enemies.Has(q) || p.Cells < 3 {
					return
				}
				if h.power(o) > 1.3*h.power(p) && p.Raided > 3 && r.Float64() < .15 {
					p.Over = id
					o.Tributaries++
					if p.Cells >= 25 {
						h.chron("diplomacy", "Worn down by raids, the "+p.Full+" agrees to pay tribute to the "+o.Full+".", p.Capital)
					}
				}
			})
		}
		o.Raided = 0
		year := h.year
		if o.Over != 0 && o.OverYear == 0 {
			o.OverYear = year
		}
		if o.Over == 0 {
			o.OverYear = 0
		}
		if o.Over != 0 && o.Kind == "state" {
			overlord := h.polities[o.Over]
			if overlord != nil && overlord.Alive && overlord.Kind == "state" && year-o.OverYear > 40 && h.power(overlord) > 3*h.power(o) {
				family := 1.
				if h.peoples[overlord.Core].Family == h.peoples[o.Core].Family {
					family = 2
				}
				if r.Float64() < .01*family {
					n, old := o.Cells, o.Full
					for _, c := range h.polCells(o.ID) {
						h.pol[c] = int32(overlord.ID)
						h.integ[c] = float32(math.Max(float64(h.integ[c])*.6, .3))
						distance := 0
						if h.dist[o.Capital] < 65535 {
							distance = int(h.dist[o.Capital])
						}
						h.dist[c] = uint16(min(65534, distance+int(h.dist[c])+4))
					}
					overlord.Tributaries = max(0, overlord.Tributaries-1)
					o.Over = 0
					if n >= 10 {
						h.chron("diplomacy", "The "+overlord.Full+" absorbs its long-time vassal, the "+old+".", o.Capital)
					}
					continue
				}
			}
		}
		if o.Over != 0 {
			overlord := h.polities[o.Over]
			if overlord == nil || !overlord.Alive || h.power(o) > h.power(overlord) {
				if overlord != nil && overlord.Alive && o.Cells >= 25 {
					h.chron("diplomacy", "The "+o.Full+" stops paying tribute to the "+overlord.Full+".", o.Capital)
				}
				if overlord != nil {
					overlord.Tributaries = max(0, overlord.Tributaries-1)
				}
				o.Over = 0
			}
		}
	}
}
