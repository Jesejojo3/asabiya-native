package sim

import (
	"fmt"
	"math"
	"slices"
)

func (h *history) declareWar(attackers, defenders []*Polity, name string, notable, civil, holy bool) *War {
	a, d := attackers[0], defenders[0]
	if name == "" {
		name = "the " + a.Base + "–" + d.Base + " War"
	}
	war := &War{ID: len(h.wars), Name: name, Start: h.year, Civil: civil, Holy: holy, Notable: notable}
	for _, p := range attackers {
		war.Attackers = append(war.Attackers, p.ID)
	}
	for _, p := range defenders {
		war.Defenders = append(war.Defenders, p.ID)
	}
	r := h.r
	if !civil {
		for _, al := range a.Allies {
			p := h.polities[al]
			if p != nil && p.Alive && !slices.Contains(d.Allies, al) && !slices.Contains(war.Defenders, al) && !p.Enemies.Has(d.ID) {
				chance := .6
				if holy && p.Religion == a.Religion {
					chance = .85
				}
				if r.Float64() < chance {
					war.Attackers = append(war.Attackers, al)
				}
			}
		}
		for _, al := range d.Allies {
			p := h.polities[al]
			if p != nil && p.Alive && !slices.Contains(war.Attackers, al) && !slices.Contains(war.Defenders, al) && r.Float64() < .75 {
				war.Defenders = append(war.Defenders, al)
			}
		}
		if holy {
			d.NB.Each(func(q, _ int) {
				p := h.polities[q]
				if p != nil && p.Alive && p.Kind == "state" && p.Religion == a.Religion && !slices.Contains(war.Attackers, q) && !slices.Contains(war.Defenders, q) && !p.Enemies.Has(d.ID) && r.Float64() < .3*h.rules.get("zeal") {
					war.Attackers = append(war.Attackers, q)
				}
			})
		}
	}
	for _, id := range war.Attackers {
		war.ASet.Add(id)
		for _, did := range war.Defenders {
			pa, pd := h.polities[id], h.polities[did]
			if !pa.Enemies.Has(did) {
				pa.Enemies.Set(did, war.ID)
				pd.Enemies.Set(id, war.ID)
			}
		}
	}
	for _, k := range append(slices.Clone(war.Attackers), war.Defenders...) {
		h.polities[k].WarsF = append(h.polities[k].WarsF, war.ID)
	}
	h.wars = append(h.wars, war)
	h.activeWars = append(h.activeWars, war.ID)
	return war
}
func (h *history) endWar(war *War) {
	war.End = h.year
	for _, a := range war.Attackers {
		for _, d := range war.Defenders {
			pa, pd := h.polities[a], h.polities[d]
			if id, ok := pa.Enemies.Get(d); ok && id == war.ID {
				pa.Enemies.Delete(d)
				pd.Enemies.Delete(a)
			}
			pa.Truce.Set(d, h.year+25)
			pd.Truce.Set(a, h.year+25)
		}
	}
	a, d := h.polities[war.Attackers[0]], h.polities[war.Defenders[0]]
	years := h.year - war.Start
	out := "it ends without decisive gains"
	if war.Civil {
		if a.Alive && d.Alive {
			out = a.Base + " and the other rebels keep their independence"
		} else if a.Alive {
			out = "the rebels prevail"
		} else {
			out = "the old regime restores its rule"
		}
	} else if war.GainA > war.GainD+2 {
		out = fmt.Sprintf("the %s side takes %d provinces", a.Base, war.GainA-war.GainD)
	} else if war.GainD > war.GainA+2 {
		out = fmt.Sprintf("the %s side turns the tide and takes %d provinces", d.Base, war.GainD-war.GainA)
	}
	war.Outcome = out
	if war.Notable || war.GainA+war.GainD >= 25 {
		plural := "s"
		if years == 1 {
			plural = ""
		}
		cell := d.Capital
		if a.Alive {
			cell = a.Capital
		}
		h.chron("war", fmt.Sprintf("%s ends after %d year%s; %s.", capFirst(war.Name), years, plural, out), cell)
	}
	var win *Polity
	if war.GainA > war.GainD+2 {
		win = a
	} else if war.GainD > war.GainA+2 {
		win = d
	}
	if win != nil && win.Alive && absInt(war.GainA-war.GainD) >= 15 {
		h.deed(h.figFor(win, win.Ruler, "ruler"), "Victor in "+war.Name)
	}
}
func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func (h *history) attack(o *Polity, i, j CellID, sea bool) {
	w, r := h.world, h.r
	q := h.pol[j]
	di := h.dd(i)
	attack := math.Pow(h.strength(o)+1, h.rules.get("scaleExp")) * (.5*o.S + .5*float64(h.cohesion[i])) * h.milAt(i) * math.Exp(-di/o.Reach)
	if sea {
		var defender *Polity
		if q != 0 {
			defender = h.polities[q]
		}
		naval := func(x *Polity) float64 {
			if x == nil {
				return 0
			}
			return (.3 + float64(h.tech[TechNavigation][x.Capital]) + .5*float64(h.tech[TechOcean][x.Capital])) * math.Min(1, .2+2*float64(x.CoastN)/math.Max(1, float64(x.Cells)))
		}
		attack *= clamp(.35+.5*(naval(o)-.7*naval(defender)), .15, .9)
	}
	if q == 0 && h.pop[j] < 1 {
		chance := .005
		if o.Kind == "horde" {
			chance = .15
		} else if h.dd(i) < .45*o.Reach || h.fort[i] > .3 {
			chance = .05
		}
		if !sea && r.Float64() < chance && (o.Kind != "horde" || w.nomad[j] || w.desert[j]) {
			h.pol[j] = int32(o.ID)
			h.taken[j] = int32(h.year)
			cost := w.travelCost[j]
			if cost == 0 {
				cost = 2
			}
			h.dist[j] = uint16(min(65534, int(h.dist[i])+int(cost)))
		}
		return
	}
	defense := h.defense(j)
	if q == 0 && o.Kind == "state" {
		defense *= (2.2 + 2*float64(h.forest[j]) + 2*float64(w.roughness[j])) / (1 + 3*float64(h.tech[TechGunpowder][i]))
	}
	if w.nomad[j] && o.Kind != "horde" && o.NomF < .4 {
		defense *= 2.5 / (1 + 2*float64(h.tech[TechGunpowder][i]))
	}
	if w.tsetse[j] && !w.tsetse[o.Capital] {
		defense *= 1.5
	}
	if w.desert[j] && float64(w.river[j]) < .3 && o.Kind != "horde" && h.tech[TechCamel][i] < .5 {
		defense *= 1.5
	}
	offset, circ := 0., 1.
	if q != 0 {
		offset = .1
		if o.Kind == "state" {
			circ = 1 + .8*float64(h.circE[j])
		}
	}
	chance := clamp(((attack-defense)/(attack+defense)*1.6+offset)*circ, 0, .92)
	var d *Polity
	if q != 0 {
		d = h.polities[q]
	}
	kin := d != nil && h.peoples[d.Core].Family == h.peoples[o.Core].Family
	family := -2
	if o.Core >= 0 {
		family = h.peoples[o.Core].Family
	}
	unity := 1.
	if h.uni[j] > .25 && int(h.uniFamily[j]) == family && o.Cells >= 12 {
		unity = 1 + .5*float64(h.uni[j])
	} else if d != nil && h.uni[j] > .25 && h.peoples[d.Core].Family != int(h.uniFamily[j]) {
		unity = 1 + .3*float64(h.uni[j])
	}
	tropical := 1.
	if w.tropical[j] > .5 && w.tropical[o.Capital] < .3 {
		tropical = .45
	}
	related := chance
	if kin && d.Religion == o.Religion {
		related = math.Min(.9, chance*1.15+.01)
	}
	cereal := 1.
	if o.Kind == "state" {
		cereal = .1 + .9*math.Pow(h.cerealEff(j), 1.5)
	}
	chance = tropical * unity * related * cereal
	ecology := 1.2
	if o.Kind == "horde" {
		ecology = .4
	}
	chance *= math.Exp(-h.rules.get("eco") * ecology * math.Pow(math.Max(0, h.ecoD(j, o)-.4), 1.3))
	if r.Float64() < chance {
		ej := h.eth[j]
		integration := .08
		if ej >= 0 && h.peoples[ej].Family == h.peoples[o.Core].Family {
			integration = .35
		}
		if h.religion[j] == int32(o.Religion) && o.Religion >= 0 {
			integration += .15
		}
		h.integ[j] = float32(integration)
		h.pol[j] = int32(o.ID)
		h.taken[j] = int32(h.year)
		h.pop[j] = float32(float64(h.pop[j]) * .93)
		h.cohesion[j] = float32(math.Max(float64(h.cohesion[j])*.8, .05))
		cost := int(w.travelCost[j])
		if sea {
			cost = 6
		} else if cost == 0 {
			cost = 2
		}
		h.dist[j] = uint16(min(65534, int(h.dist[i])+cost))
		if o.Kind == "horde" && ej >= 0 && int(ej) != o.Core {
			h.displace(j, .2, o.ID)
		}
		o.Conquests++
		o.Ruler.Conquests++
		if d != nil {
			d.LastBy = o.ID
			d.Shock += .004
			mandate := d.Mandate
			if mandate == 0 {
				mandate = 1
			}
			d.Mandate = math.Max(0, mandate-.01)
			if wid, ok := o.Enemies.Get(int(q)); ok {
				war := h.wars[wid]
				if war.ASet.Has(o.ID) {
					war.GainA++
				} else {
					war.GainD++
				}
				war.LastGain = h.year
				if j == d.Capital && o.Kind == "state" && (float64(d.Cells) < .7*float64(o.Cells) || d.S < .35) {
					h.decisive(o, d, war)
				}
			}
		}
	}
}
func (h *history) raid(o *Polity, i, j CellID) {
	q := h.pol[j]
	if q == 0 {
		return
	}
	t := h.polities[q]
	if t.Over == o.ID {
		return
	}
	attack := math.Pow(o.Pop+1, .75) * (.5*o.S + .5*float64(h.cohesion[i])) * h.milAt(i)
	defense := h.defense(j)
	if h.r.Float64() < clamp((attack-defense*.6)/(attack+defense), .05, .9) {
		taken := float64(h.pop[j]) * .03
		h.pop[j] = float32(float64(h.pop[j]) - taken)
		o.Loot += taken * .5
		t.Shock += .012
		t.Raided++
		h.displace(j, .04, o.ID)
	}
}
func (h *history) decisive(o, d *Polity, war *War) {
	kin := h.peoples[d.Core].Family == h.peoples[o.Core].Family
	identity := h.uni[d.Capital] > .3 && int(h.uniFamily[d.Capital]) == h.peoples[o.Core].Family
	annex := float64(d.Cells) <= .35*float64(o.Cells) || (kin || identity) && h.r.Float64() < .7 || h.r.Float64() < .35
	n, old := d.Cells, d.Full
	if annex {
		for _, i := range h.polCells(d.ID) {
			h.pol[i] = int32(o.ID)
			limit := .12
			if kin {
				limit = .4
			}
			h.integ[i] = float32(math.Min(float64(h.integ[i]), limit))
			distance := 4
			if h.dist[d.Capital] < 65535 {
				distance = int(h.dist[d.Capital])
			}
			h.dist[i] = uint16(min(65534, distance+int(h.dist[i])))
		}
		o.Conquests += n
		o.Ruler.Conquests += n
		d.LastBy = o.ID
		if n >= 8 {
			h.chron("war", fmt.Sprintf("The capital of the %s falls, and with it the whole realm: the %s annexes all %d provinces.", old, o.Full, n), o.Capital)
			if n >= 25 {
				h.spot("The "+o.Full+" swallows the "+old, o.Capital)
			}
		}
	} else {
		d.Over = o.ID
		o.Tributaries++
		h.endWar(war)
		h.activeWars = slices.DeleteFunc(h.activeWars, func(k int) bool { return k == war.ID })
		if n >= 8 {
			h.chron("war", fmt.Sprintf("With its capital taken, the %s submits and becomes a vassal of the %s.", old, o.Full), d.Capital)
		}
	}
}
func (h *history) distBFS() {
	for i := range h.dist {
		h.dist[i] = 65535
	}
	var buckets [32][]CellID
	pending := 0
	for _, id := range h.alive {
		c := h.polities[id].Capital
		if h.pol[c] == int32(id) {
			h.dist[c] = 0
			buckets[0] = append(buckets[0], c)
			pending++
		}
	}
	w, terrain := h.world, h.rules.get("terrain")
	for d := 0; pending > 0 && d < 60000; d++ {
		bucket := buckets[d&31]
		buckets[d&31] = nil
		for _, i := range bucket {
			pending--
			if int(h.dist[i]) != d {
				continue
			}
			p := h.pol[i]
			horde := h.polities[p].Kind == "horde"
			for direction, j := range w.neighbors[i] {
				if j < 0 || h.pol[j] != p {
					continue
				}
				cost := 2 + (float64(w.travelCost[j])-2)*terrain
				if direction < 2 {
					cost *= float64(w.cosLat[i])
				}
				if h.tech[TechRoads][j] > .5 {
					cost *= .6
				}
				if w.desert[j] && (h.tech[TechCamel][j] > .5 || horde) {
					cost *= .5
				}
				if horde && w.nomad[j] {
					cost = math.Min(cost, 1.5)
				}
				nd := d + max(1, min(30, int(jsRound(cost))))
				if int(h.dist[j]) > nd {
					h.dist[j] = uint16(nd)
					buckets[nd&31] = append(buckets[nd&31], j)
					pending++
				}
			}
			if w.coast[i] && h.tech[TechSail][i] > .5 {
				for q := w.seaOffsets[i]; q < w.seaOffsets[i+1]; q++ {
					j, dl := w.seaTargets[q], int(w.seaDistances[q])
					if dl > 3 && h.tech[TechNavigation][i] < .5 {
						continue
					}
					if h.pol[j] != p {
						continue
					}
					nd := d + min(30, 2+2*dl)
					if int(h.dist[j]) > nd {
						h.dist[j] = uint16(nd)
						buckets[nd&31] = append(buckets[nd&31], j)
						pending++
					}
				}
			}
		}
	}
}
