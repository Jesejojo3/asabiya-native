package sim

import "math"

func (h *history) politicalBorders(influence float64) {
	w, r := h.world, h.r
	y := h.year
	for _, id := range h.alive {
		h.polities[id].NB = orderedMap[int, int]{}
	}
	rise, decay, warRate, fortify := h.rules.get("asabR"), h.rules.get("asabD"), h.rules.get("warRate")*.03, h.rules.get("fortify")
	for index := 0; index < len(w.landList); index++ {
		k := index
		if y&1 != 0 {
			k = len(w.landList) - 1 - index
		}
		i := w.landList[k]
		p, pi, ei, ri := h.pol[i], float64(h.pop[i]), int(h.eth[i]), int(h.religion[i])
		var o *Polity
		if p != 0 {
			o = h.polities[p]
		}
		horde := o != nil && o.Kind == "horde"
		frontier, threat := false, false
		candidate, raidCandidate := NoCell, NoCell
		candidateWeight, raidWeight := 0., 0.
		candidateSea := false
		latitude := float64(w.cosLat[i])
		for direction, j := range w.neighbors[i] {
			if j < 0 || !w.land[j] {
				continue
			}
			q := h.pol[j]
			weight := latitude
			if direction < 2 {
				weight = 1
			}
			if q == p {
				continue
			}
			ej := int(h.eth[j])
			if ej >= 0 && ei >= 0 && ej != ei && h.ethDistance(ei, ej) > .22 {
				frontier = true
			} else if ri >= 0 && h.religion[j] >= 0 && int(h.religion[j]) != ri {
				frontier = true
			}
			if o != nil {
				if q != 0 {
					t := h.polities[q]
					o.NB.Set(int(q), o.NB.Value(int(q))+1)
					if t.Kind == "horde" || o.Enemies.Has(int(q)) {
						threat = true
					}
					if o.Enemies.Has(int(q)) || (horde && t.Kind == "horde") {
						candidateWeight += 3 * weight
						if r.Float64()*candidateWeight < 3*weight {
							candidate = j
						}
					} else if horde && t.Kind == "state" {
						raidWeight += weight
						if r.Float64()*raidWeight < weight {
							raidCandidate = j
						}
					}
				} else if !horde || w.nomad[j] || w.desert[j] || h.pop[j] >= 1 {
					candidateWeight += weight
					if r.Float64()*candidateWeight < weight {
						candidate = j
					}
				}
			}
		}
		if o != nil && w.coast[i] && float64(h.tech[TechSail][i]) > .5 {
			for q2 := w.seaOffsets[i]; q2 < w.seaOffsets[i+1]; q2++ {
				j := w.seaTargets[q2]
				if w.seaDistances[q2] > 3 && float64(h.tech[TechNavigation][i]) < .5 {
					continue
				}
				q := h.pol[j]
				if q == p {
					continue
				}
				if q != 0 {
					o.NB.Set(int(q), o.NB.Value(int(q))+1)
					if o.Enemies.Has(int(q)) {
						candidateWeight++
						if r.Float64()*candidateWeight < 1 {
							candidate = j
							candidateSea = true
						}
					}
				}
			}
		}
		cohesion := float64(h.cohesion[i])
		if o != nil {
			loss := decay
			if o.Island {
				loss *= .5
			}
			if o.ConquestDynasty {
				loss *= 1.6
			}
			if frontier {
				cohesion += rise * cohesion * (1 - cohesion)
			} else {
				cohesion -= loss * cohesion
			}
			cohesion += .004 * influence * (o.Ruler.Charisma - .5)
			if ri >= 0 && ri == o.Religion {
				cohesion += .0015 * (.5 + h.religions[ri].Centralization)
			}
			h.cohesion[i] = float32(clamp(cohesion, .02, 1))
			if h.integ[i] < 1 {
				family := ei >= 0 && h.peoples[ei].Family == h.peoples[o.Core].Family
				famMultiplier, relMultiplier, unity := .6, .8, 1.
				if family {
					famMultiplier = 1.5
				}
				if ri >= 0 && ri == o.Religion {
					relMultiplier = 1.2
				}
				if float64(h.uni[i]) > .3 && int(h.uniFamily[i]) == h.peoples[o.Core].Family {
					unity = 1.6
				}
				h.integ[i] = float32(math.Min(1, float64(h.integ[i])+.0011/(1+.8*h.rules.get("eco")*h.ecoD(i, o))*(.5+float64(h.tech[TechWriting][i])+float64(h.tech[TechRoads][i])+.5*float64(h.tech[TechLaw][i]))*famMultiplier*relMultiplier*unity))
			}
			if candidate >= 0 && int(h.taken[i]) != y {
				q := h.pol[candidate]
				if horde && q == 0 && !w.nomad[candidate] && !w.desert[candidate] && h.pop[candidate] >= 1 {
					if r.Float64() < h.rules.get("raid")*.02*o.AggressionMultiplier*o.Gate {
						taken := float64(h.pop[candidate]) * .03
						h.pop[candidate] = float32(float64(h.pop[candidate]) - taken)
						o.Loot += taken * .5
						h.displace(candidate, .02, o.ID)
					}
				} else {
					rate := warRate * 2 * (1 + 3*float64(h.circE[candidate]))
					if q == 0 {
						mobility := 1.
						if !horde {
							mobility = math.Min(1, math.Max(.1, float64(h.pop[i])/float64(w.area[i])/6)) * (.3 + .7*math.Min(1, o.Press)) * (1 + 2*float64(h.tech[TechGunpowder][i]))
						}
						rate = warRate * mobility
					}
					if r.Float64() < rate*o.AggressionMultiplier*o.Gate {
						h.attack(o, i, candidate, candidateSea)
					}
				}
			}
			if horde && raidCandidate >= 0 && r.Float64() < h.rules.get("raid")*.025*o.AggressionMultiplier*o.Gate*(1-.8*float64(h.fort[raidCandidate])) {
				h.raid(o, i, raidCandidate)
			}
			c := o.Core
			if ei >= 0 && c >= 0 && ei != c && pi >= 1 && !o.ConquestDynasty {
				religious := 1.
				if ri >= 0 && ri == o.Religion {
					religious = 1.5
				}
				if r.Float64() < h.rules.get("assim")*.004*o.S*(1-.8*h.ethDistance(ei, c))*religious {
					h.eth[i] = int32(c)
				}
			}
			if o.ConquestDynasty && ei != c && pi >= 1 {
				h.mixIn(i, c, .0006)
			}
			if o.Religion >= 0 && ri != o.Religion && pi >= 1 {
				religion := h.religions[o.Religion]
				if !(religion.Kind == "ethnic" && ei >= 0 && h.peoples[ei].Family != religion.Family) && r.Float64() < .003*h.rules.get("faith")*o.S*(religion.Missionary+.3)*(.7+.6*religion.Centralization) {
					h.religion[i] = int32(o.Religion)
				}
			}
			if threat && !horde && o.S > .45 && o.Gate > .7 && float64(h.tech[TechWriting][o.Capital]) > .3 && h.fort[i] < 1 {
				h.fort[i] = float32(math.Min(1, float64(h.fort[i])+.006*fortify*(1+float64(h.tech[TechRoads][i]))))
			}
		} else {
			if frontier {
				cohesion += rise * .6 * cohesion * (1 - cohesion)
			} else {
				cohesion += (.3 - cohesion) * .02
			}
			h.cohesion[i] = float32(clamp(cohesion, .02, 1))
			if pi >= 1 {
				density := pi / float64(w.area[i])
				agriculture := float64(h.tech[TechFarm][i]) * float64(w.farmSuitability[i])
				desert := 0.
				if w.desert[i] {
					desert = 1
				}
				pasture := float64(h.tech[TechHerd][i]) * math.Max(float64(w.herdSuitability[i]), desert*float64(h.tech[TechCamel][i])*.6)
				if agriculture > .35 && density > 4.5 && !w.nomad[i] && h.localPop(i) >= 15000*h.rules.get("floor") {
					cereal := h.cerealEff(i)
					chance := h.rules.get("formRate") * .0012 * (.2 + 1.6*h.rules.get("circ")*float64(h.circE[i])) * (.4 + float64(h.cohesion[i])) * (1 + math.Min(2, density/15)) * math.Min(1, .05+float64(h.tech[TechCopper][i])+float64(h.tech[TechWriting][i])+float64(h.tech[TechHorse][i])*.5+math.Min(.4, math.Max(0, density-5)/25)+.15*math.Max(0, float64(h.circE[i])-.5)) * (.03 + .97*cereal*cereal)
					if r.Float64() < chance {
						id := h.newPolity(i, nil, polityOptions{})
						for _, j := range w.neighbors[i] {
							if j >= 0 && w.land[j] && h.pol[j] == 0 && int(h.eth[j]) == ei && h.pop[j] >= 1 && r.Float64() < .5 {
								h.pol[j] = int32(id)
								h.dist[j] = 2
							}
						}
					}
				} else if pasture > .3 && density > .5 && (w.nomad[i] || w.desert[i]) && frontier {
					if r.Float64() < h.rules.get("nomad")*.0003*(.4+float64(h.cohesion[i]))*(.5+float64(h.tech[TechHorse][i])+float64(h.tech[TechCamel][i])) {
						id := h.newPolity(i, nil, polityOptions{Kind: "horde"})
						for _, j := range w.neighbors[i] {
							if j >= 0 && w.land[j] && h.pol[j] == 0 && (w.nomad[j] || w.desert[j]) && h.pop[j] >= 1 && r.Float64() < .6 {
								h.pol[j] = int32(id)
								h.dist[j] = 2
							}
						}
					}
				}
			}
		}
		if h.fort[i] > 0 {
			keep := o != nil && !horde && o.S > .3 && o.Press < 1
			decay := .99
			if keep {
				decay = .9995
			}
			h.fort[i] = float32(float64(h.fort[i]) * decay)
			if float64(h.fort[i]) < .01 {
				h.fort[i] = 0
			}
		}
	}
	for _, id := range h.alive {
		o := h.polities[id]
		if o.FortN >= 8 && !o.WallLogged && o.Cells >= 20 {
			o.WallLogged = true
			h.chron("culture", "The "+o.Full+" begins to fortify its frontier with a great line of walls and forts.", o.Capital)
			h.spot("The "+o.Full+" builds a great wall", o.Capital)
		}
	}
}

func (h *history) politicalTerritory() {
	w, r := h.world, h.r
	h.distBFS()
	for _, i := range w.landList {
		p := h.pol[i]
		var o *Polity
		if p != 0 {
			o = h.polities[p]
		}
		if o != nil && o.Kind == "state" && o.Cells >= 60 && float64(h.integ[i]) > .55 && h.pop[i] >= 1 && h.ecoD(i, o) < .6 {
			family := h.peoples[o.Core].Family
			if int(h.uniFamily[i]) != family {
				if float64(h.uni[i]) < .15 {
					h.uniFamily[i] = int32(family)
					h.uni[i] = 0
				} else {
					h.uni[i] = float32(float64(h.uni[i]) * .985)
					continue
				}
			}
			h.uni[i] = float32(float64(h.uni[i]) + .0035*(1-float64(h.uni[i])))
		} else {
			h.uni[i] = float32(float64(h.uni[i]) * .9975)
		}
	}
	if h.year%10 == 0 {
		h.exitPass(0, .25)
		h.exitPass(.25, .5)
		h.exitPass(.5, .75)
		h.exitPass(.75, 1)
	}
	for _, i := range w.landList {
		p := h.pol[i]
		if p == 0 {
			continue
		}
		o := h.polities[p]
		if o.Kind != "state" || i == o.Capital {
			continue
		}
		cereal := h.cerealEff(i)
		if h.isWaste(i, false) {
			rim := 0
			for _, j := range w.neighbors[i] {
				if j >= 0 && h.pol[j] == p && !h.isWaste(j, false) {
					rim++
				}
			}
			keep := rim > 0 || float64(h.fort[i]) > .3 || float64(h.caravan[i]) > .3 || (h.dd(i) < .35*o.Reach && o.S > .4 && o.Burden < 1.1)
			if !keep && r.Float64() < .3 {
				h.pol[i] = 0
				continue
			}
		}
		if cereal < .35 && r.Float64() < .15*(1-cereal/.35)*(1.2-.5*float64(h.integ[i])) {
			h.pol[i] = 0
		}
	}
}
