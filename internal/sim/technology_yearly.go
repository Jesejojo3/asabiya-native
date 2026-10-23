package sim

import (
	"fmt"
	"math"
)

var firstTechnologyVerbs = map[string]string{
	"plough": "forge a heavy iron plough that turns the wet, clay soils", "manure": "begin to gather manure and night soil to feed their fields", "kitesig": "fly signal kites to send orders across the realm", "windcart": "build sail-driven wagons that cross the flat deserts", "fungal": "cultivate fungal gardens on the forest floor", "ledger": "build geared engines to keep the treasury accounts", "tidemill": "harness the tides to turn mills and forge hammers", "feverbark": "brew a bark remedy that tames the marsh fevers", "saltflush": "dig flushing canals that rinse the salt from their fields", "pigeon": "train birds to carry messages between cities", "irrig": "dig the first irrigation canals", "wheel": "build the first wheeled carts and chariots", "writing": "begin to keep written records", "iron": "learn to smelt iron", "coin": "strike the first coins", "law": "write down the first law code", "roads": "lay the first long paved roads", "nav": "learn to steer by the stars across open seas", "caval": "field the first armoured horsemen", "paper": "make the first paper", "crops": "rotate their fields and add fodder crops", "gun": "make the first gunpowder weapons", "ocean": "build ships that can cross oceans",
}

func (h *history) firstTech(k int, cell CellID, polity *Polity) {
	if h.firstDiscoveries[k] != nil {
		return
	}
	h.recordDiscovery(k, cell)
	if polity != nil {
		h.firstDiscoveries[k].Polity = polity.ID
	}
	t := v06.Tech[k]
	verb := firstTechnologyVerbs[t.Key]
	if verb == "" {
		return
	}
	where := "a distant people"
	if polity != nil {
		where = "the " + polity.Full
	} else if e := h.eth[cell]; e >= 0 {
		where = "the " + h.peoples[e].Name
	}
	extra := ""
	if t.Synthetic {
		extra = ", a path our own history never took"
	}
	h.chron("ideas", fmt.Sprintf("Scholars and craftsmen of %s %s%s.", where, verb, extra), cell)
	if k >= 8 {
		h.spot(t.Name+" first appears in "+where, cell)
	}
}

// techStep preserves in-place cell/technology order, bands, maxima tie order,
// contact costs, institutional decay and the conversion RNG calls.
func (h *history) techStep(start, end float64) {
	h.prepareAnnualState()
	w, r := h.world, h.r
	diffusion, loss := .12*h.rules.get("techDiff"), .006*h.rules.get("techLoss")
	var known [techCount]int
	knownCount := 0
	var institutional [techCount]bool
	for k := 0; k < techCount; k++ {
		if h.firstDiscoveries[k] != nil || k == TechSail {
			known[knownCount] = k
			knownCount++
		}
		institutional[k] = k == TechWriting || k == TechCoin || k == TechLaw || k == TechRoads || k == TechPaper
	}
	for index, stop := int(math.Floor(start*float64(len(w.landList)))), int(math.Floor(end*float64(len(w.landList)))); index < stop; index++ {
		i := w.landList[index]
		if h.pop[i] < 1 {
			continue
		}
		pi := h.pol[i]
		var polity *Polity
		if pi != 0 {
			polity = h.polities[pi]
		}
		connected := float64(h.pop[i])
		for _, j := range w.neighbors[i] {
			if j >= 0 {
				connected += float64(h.pop[j])
			}
		}
		riverBonus := (1 + .5*float64(w.river[i])) * (1 + .3*float64(h.tech[TechPaper][i]) + .2*float64(h.tech[TechRoads][i]))
		seaStart, seaEnd := w.seaOffsets[i], w.seaOffsets[i]
		if float64(h.tech[TechSail][i]) > .3 {
			seaEnd = w.seaOffsets[i+1]
		}
		dark := polity == nil || polity.Culture < .1
		contact := [4]float64{1, 1, 1, 1}
		pigeons := 1 + .4*float64(h.tech[TechPigeon][i])
		neighbors := [4]CellID{NoCell, NoCell, NoCell, NoCell}
		for d, j := range w.neighbors[i] {
			if j < 0 {
				continue
			}
			contact[d] = min64(1, .25+math.Sqrt(float64(h.pop[i])*float64(h.pop[j]))/6000+float64(h.caravan[i])+float64(h.caravan[j])) * pigeons
			if h.pop[j] >= 1 {
				neighbors[d] = j
			}
		}
		cosLat := float64(w.cosLat[i])
		lowContact := connected < 3000
		noFarm := float64(h.tech[TechFarm][i]) < .3 && float64(h.tech[TechHerd][i]) < .3
		for _, f := range known[:knownCount] {
			a := h.tech[f]
			t := float64(a[i])
			if t < .995 {
				maximum, multiplier, same := 0.0, 1.0, false
				for d, j := range neighbors {
					if j >= 0 && float64(a[j]) > maximum {
						maximum = float64(a[j])
						same = pi != 0 && h.pol[j] == pi
						multiplier = contact[d]
						if d >= 2 {
							multiplier *= cosLat
						}
					}
				}
				for q := seaStart; q < seaEnd; q++ {
					j := w.seaTargets[q]
					if h.pop[j] < 1 {
						continue
					}
					v := float64(a[j]) * .9
					if v > maximum {
						maximum = v
						same = false
						multiplier = .7
					}
				}
				if maximum > t {
					border := .6
					if same {
						border = 1
					}
					rate := diffusion * riverBonus * border * min64(1, multiplier)
					if f >= 3 && f != TechSail && f != TechCamel && noFarm {
						rate *= .02
					}
					switch f {
					case TechFarm:
						rate *= .2 + float64(w.farmSuitability[i])
					case TechHerd, TechHorse:
						rate *= .2 + float64(w.herdSuitability[i])
					case TechIrrigation:
						rate *= .2 + float64(w.river[i])
					}
					if f == TechSail && !w.coast[i] {
						rate *= .3
					}
					if f == TechCamel {
						factor := 0.0
						if w.desert[i] || float64(w.herdSuitability[i]) > .3 {
							factor = 1
						}
						rate *= .2 + factor
					}
					switch {
					case f == TechGrain:
						rate *= .05 + .95*(1-float64(w.tropical[i]))*(1-float64(w.leach[i]))
					case f == TechArd:
						if w.tsetse[i] {
							rate *= .03
						} else {
							rate *= .3 + .7*(1-float64(w.heavySoil[i]))
						}
					case f == TechPlough:
						rate *= .1 + float64(w.heavySoil[i])
					case f == TechXCrops:
						factor := .2
						if float64(h.tech[TechFarm][i]) > .5 {
							factor = 1
						}
						rate *= .3 * factor
					case f >= TechKiteSignal:
						rate *= .5
					}
					t += rate * (maximum - t)
				}
				if institutional[f] && dark && maximum < .5 {
					factor := .985
					if pi != 0 {
						factor = .994
					}
					t *= factor
				}
			} else if institutional[f] && dark {
				maximum := 0.0
				for _, j := range neighbors {
					if j >= 0 {
						maximum = max64(maximum, float64(a[j]))
					}
				}
				if maximum < .5 {
					factor := .985
					if pi != 0 {
						factor = .994
					}
					t *= factor
				}
			}
			if lowContact && t > 0 {
				factor := 1.0
				if f == TechFarm {
					factor = .3
				}
				t *= 1 - loss*factor
			}
			a[i] = float32(t)
		}
		if h.firstDiscoveries[TechIrrigation] == nil || float64(h.tech[TechIrrigation][i]) < .5 {
			if float64(h.tech[TechFarm][i]) > .8 && float64(w.river[i]) > .25 && w.precipitation[i] < 1000 && float64(h.pop[i])/float64(w.area[i]) > 4 && r.Float64() < .0008*h.rules.get("invent") {
				h.seedTech(TechIrrigation, i, 1, 1)
				h.firstTech(TechIrrigation, i, polity)
			}
		}
		ri := h.religion[i]
		if ri < 0 {
			continue
		}
		religion := h.religions[ri]
		j := w.neighbors[i][int(r.Float64()*4)]
		if seaEnd > seaStart && r.Float64() < .2 {
			j = w.seaTargets[seaStart+int32(r.Float64()*float64(seaEnd-seaStart))]
		}
		if j < 0 || h.pop[j] < 1 || h.religion[j] == ri || (religion.Kind == "ethnic" && h.eth[j] >= 0 && h.peoples[h.eth[j]].Family != religion.Family) {
			continue
		}
		qj := h.pol[j]
		stateReligion := -1
		if qj != 0 {
			stateReligion = h.polities[qj].Religion
		}
		same, bias, newcomer := 1.0, 1.0, .6
		if pi != 0 && qj == pi {
			same = 1.5
		}
		if stateReligion == int(ri) {
			bias = 4
		} else if stateReligion >= 0 {
			bias = .25
		}
		if h.religion[j] < 0 {
			newcomer = 1.3
		}
		probability := .09 * religion.Missionary * h.rules.get("faith") * min64(1, .15+math.Sqrt(float64(h.pop[i])*float64(h.pop[j]))/15000+2*float64(h.caravan[j])) * same * bias * newcomer * (1 + .5*float64(h.tech[TechPaper][i])) * (.7 + .6*religion.Centralization)
		if r.Float64() < probability {
			h.religion[j] = ri
		}
	}
}
