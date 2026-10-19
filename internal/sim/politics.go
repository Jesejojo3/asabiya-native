package sim

import (
	"fmt"
	"math"
	"slices"
	"strings"
)

// politics removes scheduling yields, not causal steps. The owning alive slice
// is read by index with a fresh length, so rebels created by civilWar are visited
// in the same year as JS's for...of over its shared next/alive array.
func (h *history) politics() {
	h.prepareAnnualState()
	h.politicalCensus()
	h.politicalLeaders()
	h.politicalBorders(h.rules.get("leaderInfl"))
	for _, id := range slices.Clone(h.activeMigrations) {
		h.migStep(h.migrations[id])
	}
	if h.year%5 == 0 {
		h.politicalTerritory()
	}
}
func (h *history) politicalLeaders() {
	w, r := h.world, h.r
	y := h.year
	influence := h.rules.get("leaderInfl")
	for index := 0; index < len(h.alive); index++ {
		id := h.alive[index]
		o := h.polities[id]
		if !o.Alive {
			continue
		}
		ruler, c := o.Ruler, o.Capital
		lm := w.landmass[c]
		size := w.landmassSizes[lm]
		o.Island = size >= 4 && size <= 700 && h.landmassPopulation[lm] > 0 && float64(o.LandmassN) >= .8*float64(h.landmassPopulation[lm])
		if o.Island && h.islandBy[lm] != id && o.Cells >= 4 {
			first := h.islandNames[lm] == ""
			if first {
				h.islandNames[lm] = placeWord(h.langAt(c), r)
			}
			h.islandBy[lm] = id
			if size >= 10 {
				again := " once more"
				if first {
					again = ""
				}
				h.chron("rise", "The "+o.Full+" unites the whole island of "+h.islandNames[lm]+again+".", c)
				h.deed(h.figFor(o, o.Ruler, "ruler"), "Unified the island of "+h.islandNames[lm])
			}
		}
		if y-ruler.Birth >= ruler.Death {
			h.succession(o)
			if !o.Alive || o.Cells == 0 {
				continue
			}
		}
		rn := o.Ruler
		competence := .5 + influence*(rn.Competence-.5)
		o.AggressionMultiplier = math.Max(.12, 1+influence*(4*rn.Aggression-2)*.6)
		anomaly := float64(h.anom[c])
		o.Wet = o.Wet*.92 + anomaly*.08
		o.Loot *= .9
		pasture := .22
		if o.NomF > .5 || o.Kind == "horde" {
			pasture = .5
		}
		over := 0.
		if o.Over != 0 {
			over = .15
		}
		o.Gate = clamp(.5+1.1*(1-o.Press)+pasture*anomaly+math.Min(.5, float64(o.Tributaries)*.15)-over+math.Min(.5, o.Loot/(o.Pop+1)*4)-math.Min(.3, float64(o.FortN)*.004), .15, 1.9)
		tech := func(k int) float64 { return float64(h.tech[k][c]) }
		horde, complexity := 1., 1.
		if o.Kind == "horde" {
			horde = 1.4
		} else {
			value := o.Complexity
			if value == 0 {
				value = .2
			}
			complexity = .75 + .5*math.Min(1.4, value)
		}
		o.Reach = h.rules.get("reach") * (1 + .8*tech(TechWriting) + .5*tech(TechLaw) + .7*tech(TechRoads) + .4*tech(TechCoin) + .6*tech(TechGunpowder)) * (.7 + .6*competence) * horde * complexity * (1 + .15*tech(TechKiteSignal) + .1*tech(TechPigeon))
		et := h.etOf(o)
		inequality := o.Inequality
		if !o.ComplexitySet {
			inequality = .5
		}
		o.E = clamp(o.E+.012*o.E*(1-o.Press)*(.8+.4*competence)*(.5+inequality), .004, .12)
		o.Shock *= .92
		o.Mandate = math.Min(1, o.Mandate+.006)
		h.statecraft(o, c, y)
		if o.Kind == "state" && o.Pop < 5000*h.rules.get("floor") {
			if o.LowYear == 0 {
				o.LowYear = y
			}
			if y-o.LowYear > 25 {
				if o.MaxCells >= 8 {
					h.chron("fall", "The "+o.Full+" dwindles below the numbers needed to sustain a ruler and his household; it dissolves back into villages and kin-groups.", c)
				}
				for _, i := range h.polCells(id) {
					h.pol[i] = 0
				}
				continue
			}
		} else {
			o.LowYear = 0
		}
		pressure := math.Max(0, o.Press-.85) * 3
		elites := math.Max(0, o.E/et-1.15) * 1.1
		cohesion := math.Max(0, .42-o.S) * 2.2
		distanceMultiplier := 1.
		if float64(h.tech[TechWriting][c]) < .5 {
			distanceMultiplier = 2.2
		}
		distance := math.Max(0, o.MD/o.Reach-.85) * distanceMultiplier
		inept := math.Max(0, .5-competence) * .8
		integration := math.Max(0, .45-o.Integration) * .8
		mandate := math.Max(0, .5-o.Mandate) * 1.2
		sizePressure, nichePressure := 0., 0.
		if o.Kind == "state" {
			sizePressure = math.Max(0, float64(o.Cells)/(170*(1+.6*tech(TechRoads)+.4*tech(TechWriting)+.3*tech(TechPaper)))-1) * .9
			nichePressure = h.rules.get("eco") * .8 * math.Max(0, o.ForeignShare-.35)
		}
		o.Why = []Factor{{"pP", pressure}, {"pE", elites}, {"pS", cohesion}, {"pX", distance}, {"pR", inept}, {"pI", integration}, {"pM", mandate}, {"pZ", sizePressure}, {"pN", nichePressure}, {"pT", o.PT}, {"pF", o.PF}, {"pQ", o.PQ}, {"sh", o.Shock}}
		o.Psi = pressure + elites + cohesion + distance + inept + integration + mandate + sizePressure + o.PT + o.PF + o.PQ + nichePressure + o.Shock
		island, collapseThreshold := 1., .12
		if o.Island {
			island = .4
			collapseThreshold = .08
		}
		if o.Kind == "state" && o.Cells >= 40 && o.Psi > 2.2 && r.Float64() < h.rules.get("crisis")*.008*(o.Psi-2)*island {
			o.Shock += .4
			if o.Cells >= 80 {
				h.chron("fall", "The "+o.Full+" shatters into rival kingdoms.", o.Capital)
			}
			h.civilWar(o, true)
		} else if o.Cells >= 3 && r.Float64() < h.rules.get("crisis")*.0035*o.Psi*o.Psi*island {
			h.civilWar(o, false)
		} else if o.Cells >= 2 && o.S < collapseThreshold && r.Float64() < .02 {
			h.collapse(o)
		}
		if o.Kind == "horde" && o.Cells <= 2 && y-o.Born > 30 && r.Float64() < .03 {
			for _, i := range h.polCells(id) {
				h.pol[i] = 0
			}
			continue
		}
		h.culture(o)
		if y%5 == 0 {
			if o.P5 != 0 && o.Pop < .8*o.P5 && o.Wet < -.3 {
				o.Mandate = math.Max(0, o.Mandate-.25)
			}
			if o.P5 != 0 && o.Pop < .8*o.P5 && o.Cells >= 15 && o.Wet < -.3 && y-o.FamineYear > 60 {
				o.FamineYear = y
				o.Shock += .5
				h.chron("famine", fmt.Sprintf("Years of drought bring famine to the %s; it loses %.0f%% of its people.", o.Full, jsRound((1-o.Pop/o.P5)*100)), c)
			}
			o.P5 = o.Pop
		}
		if o.ConquestDynasty && y%10 == 0 {
			ce := h.eth[c]
			if ce >= 0 && int(ce) != o.Core {
				o.AssimilationTime += 10
				if o.AssimilationTime >= 90 {
					old, nw := h.peoples[o.Core], h.peoples[ce]
					o.Core = int(ce)
					o.ConquestDynasty = false
					if o.Cells >= 15 {
						h.chron("people", fmt.Sprintf("Four generations on, the ruling %s of the %s have become %s in all but name.", old.Name, o.Full, nw.Name), c)
					}
				}
			} else {
				o.AssimilationTime = 0
			}
		}
		h.politicalMilestones(o, rn, c)
		if o.Kind == "state" {
			for k := 6; k < techCount; k++ {
				t := v06.Tech[k]
				em := t.Emergence
				if em == nil || float64(h.tech[k][c]) >= .5 {
					continue
				}
				population := em["pop"] * .6
				if o.Pop < population*.5 || (em["cells"] != 0 && float64(o.Cells) < em["cells"]) || (em["coast"] != 0 && !w.coast[c] && o.CoastN < 2) || (em["horse"] != 0 && tech(TechHorse) < .6) || (em["heavy"] != 0 && o.HeavyN < 3) {
					continue
				}
				ok := true
				for _, p := range t.Pre {
					if float64(h.tech[p][c]) < .7 {
						ok = false
						break
					}
				}
				if !ok {
					continue
				}
				fit := h.techFit(o, k)
				pressureBonus := 1.
				if em["press"] != 0 {
					pressureBonus = clamp((o.Press-.7)*5, 0, 2)
				}
				fitBonus := .6 + .8*fit
				if t.Synthetic {
					fitBonus = fit * fit * 2.5
				}
				if r.Float64() < em["b"]*h.rules.get("invent")*math.Min(3, math.Sqrt(o.Pop/population))*(.7+.9*o.Culture)*pressureBonus*fitBonus {
					h.seedTech(k, c, 1, 1)
					if k == TechWriting {
						for _, i := range w.landList {
							if h.pol[i] == int32(id) {
								h.tech[TechWriting][i] = float32(math.Max(float64(h.tech[TechWriting][i]), .35))
							}
						}
					}
					h.firstTech(k, c, o)
				}
			}
		}
		cr := h.religion[c]
		if cr >= 0 && int(cr) != o.Religion && r.Float64() < .04 {
			o.Religion = int(cr)
			religion := h.religions[cr]
			if !slices.Contains(religion.States, id) {
				religion.States = append(religion.States, id)
			}
			if o.Cells >= 30 {
				f := h.figFor(o, rn, "ruler")
				h.deed(f, "Made "+religion.Name+" the faith of the realm")
				h.chron("faith", capFirst(h.rulerName(o))+" makes "+religion.Name+" the faith of the "+o.Full+".", c)
			}
		}
		if o.Kind == "state" && tech(TechWriting) > .5 && o.Cells >= 10 && (o.Shock > .25 || cohesion > .2) && r.Float64() < h.rules.get("faith")*.0003 {
			h.foundReligion(o)
		}
		if o.Kind == "horde" && o.Cells >= 6 && o.Pop > 50000 && len(h.activeMigrations) < 10 && ((o.Wet < -.4 && o.Press > .75 && r.Float64() < .02*h.rules.get("wander")) || (o.S > .55 && rn.Aggression > .7 && r.Float64() < .006*h.rules.get("wander"))) {
			h.hordeMigration(o)
		}
		if o.Cells >= 2 && o.Enemies.Len() < 3 && r.Float64() < h.rules.get("warRate")*.02*o.AggressionMultiplier*o.Gate {
			h.chooseWar(o, rn)
		}
	}
	still := []int{}
	for _, wid := range h.activeWars {
		war := h.wars[wid]
		aAlive, dAlive := false, false
		for _, k := range war.Attackers {
			aAlive = aAlive || h.polities[k].Alive
		}
		for _, k := range war.Defenders {
			dAlive = dAlive || h.polities[k].Alive
		}
		last := war.LastGain
		if last == 0 {
			last = war.Start
		}
		fresh := y - last
		chance := .02
		if fresh > 8 {
			chance += .08
		}
		if y-war.Start > 40 {
			chance += .1
		}
		if !aAlive || !dAlive || r.Float64() < chance {
			h.endWar(war)
			continue
		}
		still = append(still, wid)
	}
	h.activeWars = still
	if y%5 == 0 {
		h.diplomacy()
	}
}

func (h *history) politicalMilestones(o *Polity, r *Ruler, c CellID) {
	if r.Figure >= 0 {
		f := h.figures[r.Figure]
		f.Conquests = r.Conquests
		if o.Cells > f.Realm {
			f.Realm = o.Cells
		}
		f.Title = capFirst(h.titleOf(o, r)) + " of the " + o.Full
	}
	milestones := [4]int{25, 50, 100, 200}
	for r.MilitaryInventions < 4 && r.Conquests >= milestones[r.MilitaryInventions] && o.Cells >= 25 {
		m := milestones[r.MilitaryInventions]
		r.MilitaryInventions++
		f := h.figFor(o, r, "ruler")
		f.Conquests = r.Conquests
		bits := []string{}
		if r.Exceptional == "aggr" {
			bits = append(bits, "a ruler of uncommon ferocity")
		}
		if o.Wet > .35 {
			bit := "during a run of wet years"
			if o.NomF > .5 || o.Kind == "horde" {
				bit = "with grass made rich by a run of wet years"
			}
			bits = append(bits, bit)
		} else if o.Wet < -.35 {
			bits = append(bits, "despite years of drought")
		}
		wet := ""
		if o.Wet > .35 {
			wet = " during a run of wet years"
		}
		h.deed(f, fmt.Sprintf("Had conquered %d provinces for the %s%s", m, o.Full, wet))
		extra := ""
		if len(bits) > 0 {
			extra = ", " + strings.Join(bits, ", ") + ","
		}
		h.chron("rise", fmt.Sprintf("%s of the %s%s has conquered %d provinces.", capFirst(h.rulerName(o)), o.Full, extra, m), c)
		if m >= 50 {
			h.spot(fmt.Sprintf("%s has conquered %d provinces", capFirst(h.rulerName(o)), m), c)
		}
	}
	if !o.FK && o.Cells >= 40 {
		o.FK = true
		f := h.figFor(o, o.FounderR, "founder")
		has := false
		for _, d := range f.Deeds {
			if strings.HasPrefix(d.Text, "Founded") {
				has = true
				break
			}
		}
		if !has {
			h.deed(f, "Founded the "+o.Base+" state")
		}
		h.chron("rise", "The "+o.Full+" rises under "+h.rulerName(o)+".", c)
	}
	if !o.FE && o.Cells >= 100 {
		o.FE = true
		f := h.figFor(o, r, "ruler")
		h.deed(f, fmt.Sprintf("Ruled the %s at %d provinces", o.Full, o.Cells))
		h.chron("rise", fmt.Sprintf("The %s realm grows to %d provinces under %s.", o.Base, o.Cells, h.rulerName(o)), c)
		h.spot(fmt.Sprintf("The %s reaches %d provinces", o.Full, o.Cells), c)
	}
}

func (h *history) chooseWar(o *Polity, r *Ruler) {
	best, weight, holy := 0, 0., false
	power := h.power(o)
	var religion *Religion
	holyOwner := 0
	if o.Religion >= 0 {
		religion = h.religions[o.Religion]
		holyOwner = int(h.pol[religion.Holy])
	}
	o.NB.Each(func(q, b int) {
		t := h.polities[q]
		expiry := o.Truce.Value(q)
		if expiry == 0 {
			expiry = -1e9
		}
		if t == nil || !t.Alive || o.Enemies.Has(q) || slices.Contains(o.Allies, q) || o.Over == q || t.Over == o.ID || expiry > h.year {
			return
		}
		wt := float64(b) * math.Pow(power/(h.power(t)+1), 1.5)
		if religion != nil && t.Religion != o.Religion && t.Religion >= 0 {
			wt *= 1 + .4*h.rules.get("zeal")*r.Piety
		}
		isHoly := religion != nil && q == holyOwner && t.Religion != o.Religion && r.Piety > .6
		if isHoly {
			wt *= 1 + 4*h.rules.get("zeal")
		}
		weight += wt
		if wt > 0 && h.r.Float64()*weight < wt {
			best = q
			holy = isHoly
		}
	})
	if best == 0 {
		return
	}
	t := h.polities[best]
	name := ""
	if holy {
		name = "the Holy War for " + h.holyName(religion)
	}
	war := h.declareWar([]*Polity{o}, []*Polity{t}, name, holy, false, holy)
	total := 0
	for _, k := range append(slices.Clone(war.Attackers), war.Defenders...) {
		total += h.polities[k].Cells
	}
	if holy || total >= 150 || (o.Cells >= 30 && t.Cells >= 30) {
		war.Notable = true
		allies, defenders := []string{}, []string{}
		for _, k := range war.Attackers[1:] {
			allies = append(allies, h.polities[k].Base)
		}
		for _, k := range war.Defenders[1:] {
			defenders = append(defenders, h.polities[k].Base)
		}
		prefix, extra := "War", ""
		if holy {
			prefix = "Holy war"
			extra = " to win back " + h.holyName(religion)
		}
		if len(allies) > 0 {
			extra += ", joined by " + strings.Join(allies, " and ")
		}
		if len(defenders) > 0 {
			verb := "comes"
			if len(defenders) > 1 {
				verb = "come"
			}
			extra += "; " + strings.Join(defenders, " and ") + " " + verb + " to the defence"
		}
		h.chron("war", prefix+": the "+o.Full+" attacks the "+t.Full+extra+".", t.Capital)
	}
}
