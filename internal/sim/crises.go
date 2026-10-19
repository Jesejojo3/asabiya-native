package sim

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

var causeLabels = map[string]string{"pN": "rule stretched over lands unlike its own", "pT": "a government that cost more than it returned", "pF": "an empty treasury and mounting debts", "pQ": "a widening gulf between the great and the poor", "pZ": "an empire grown too large to govern", "pI": "restless, poorly integrated provinces", "pM": "a dynasty that had lost its mandate", "pP": "population pressing on the land", "pE": "too many elites competing for office", "pS": "weak cohesion", "pX": "an overextended realm", "pR": "an inept ruler", "sh": "recent famine, plague, invasion or succession strife"}

func topCauses(why []Factor) []string {
	values := []Factor{}
	for _, f := range why {
		if f.Value > .08 {
			values = append(values, f)
		}
	}
	sort.SliceStable(values, func(i, j int) bool { return values[i].Value > values[j].Value })
	out := []string{}
	for _, f := range values[:min(2, len(values))] {
		out = append(out, causeLabels[f.Key])
	}
	return out
}
func (h *history) civilWar(o *Polity, breakup bool) {
	w, r := h.world, h.r
	cells := h.polCells(o.ID)
	if len(cells) < 3 {
		return
	}
	score := func(i CellID) float64 {
		distance := float64(h.dist[i])
		if h.dist[i] == 65535 {
			distance = 9999
		}
		return distance * (1.2 - float64(h.integ[i])) * (1 + h.rules.get("eco")*h.ecoD(i, o))
	}
	sort.SliceStable(cells, func(i, j int) bool { return score(cells[i]) > score(cells[j]) })
	count := 1
	if r.Float64() < .5 {
		count++
	}
	if len(cells) >= 80 && r.Float64() < .5 {
		count++
	}
	count += len(cells) / 250
	if breakup {
		count += 2
	}
	count = max(1, min(6, count))
	top := cells[:max(1, int(jsRound(float64(len(cells))*.6)))]
	seeds := []CellID{}
	for attempt := 0; attempt < 60 && len(seeds) < count; attempt++ {
		c := pick(r, top)
		if c == o.Capital {
			continue
		}
		separated := true
		for _, q := range seeds {
			if h.world.angDist(q, c) <= .07 {
				separated = false
				break
			}
		}
		if separated {
			seeds = append(seeds, c)
		}
	}
	if len(seeds) == 0 {
		return
	}
	oldName := o.Full
	causes := topCauses(o.Why)
	why := ""
	if breakup {
		why = "A confederation held together by one leader rarely outlives him."
	} else if len(causes) > 0 {
		why = "Driven by " + strings.Join(causes, " and ") + "."
	}
	for _, i := range cells {
		h.lab[i] = -2
	}
	q := []CellID{o.Capital}
	h.lab[o.Capital] = int32(o.ID)
	if !breakup {
		for k := len(cells) - 1; k >= 0; k-- {
			c := cells[k]
			if c == o.Capital {
				continue
			}
			if k >= len(top) || (float64(h.integ[c]) > .8 && r.Float64() < .7) {
				h.lab[c] = int32(o.ID)
				q = append(q, c)
			}
		}
	}
	eligible := []CellID{}
	for _, c := range seeds {
		if h.lab[c] == -2 {
			eligible = append(eligible, c)
		}
	}
	if len(eligible) == 0 {
		for _, i := range cells {
			h.lab[i] = 0
		}
		return
	}
	ids := []int{}
	for _, c := range eligible {
		id := h.newPolity(c, o, polityOptions{Kind: o.Kind, Origin: &PolityOrigin{Type: "rebellion", From: o.ID, Why: why}})
		h.lab[c] = int32(id)
		q = append(q, c)
		ids = append(ids, id)
	}
	for head := 0; head < len(q); head++ {
		i := q[head]
		label := h.lab[i]
		for _, j := range w.neighbors[i] {
			if j >= 0 && h.lab[j] == -2 {
				h.lab[j] = label
				q = append(q, j)
			}
		}
	}
	for _, i := range cells {
		label := h.lab[i]
		if label > 0 && label != int32(o.ID) {
			h.pol[i] = label
			h.cohesion[i] = float32(math.Min(1, float64(h.cohesion[i])+.12))
		}
		h.pop[i] = float32(float64(h.pop[i]) * .94)
		h.lab[i] = 0
	}
	o.E = .7 * h.etOf(o)
	o.Shock = .2
	o.Crises++
	if o.ComplexitySet {
		scale, ineq := .85, .88
		if breakup {
			scale = .7
			ineq = .7
		}
		o.Complexity *= scale
		o.Inequality = math.Max(.2, o.Inequality*ineq)
	}
	rebels := []*Polity{}
	for _, id := range ids {
		p := h.polities[id]
		p.Religion = o.Religion
		if h.religion[p.Capital] >= 0 {
			p.Religion = int(h.religion[p.Capital])
		}
		rebels = append(rebels, p)
	}
	for _, i := range cells {
		p := h.pol[i]
		if p != 0 && i != h.polities[p].Capital && h.cerealEff(i) < .3 && r.Float64() < .6 {
			h.pol[i] = 0
		}
	}
	big := len(cells) >= 40
	war := h.declareWar(rebels, []*Polity{o}, "the "+o.Base+" Civil War", big, true, false)
	war.Why = why
	if big && !breakup {
		names := []string{}
		for _, id := range ids {
			names = append(names, h.polities[id].Base)
		}
		name := names[0]
		verb := "breaks"
		if len(names) > 1 {
			name = strings.Join(names[:len(names)-1], ", ") + " and " + names[len(names)-1]
			verb = "break"
		}
		h.chron("war", fmt.Sprintf("Civil war breaks the %s; %s %s away.", oldName, name, verb), o.Capital)
	}
}
func (h *history) succession(o *Polity) {
	r := h.r
	l := h.peoples[0].Language
	if o.Core >= 0 {
		l = h.peoples[o.Core].Language
	}
	et := h.etOf(o)
	old, r0 := o.Dynasty, o.Ruler
	chance := .06 + .25*math.Max(0, o.E/et-1) + .35*math.Max(0, .6-o.Mandate)
	o.Rulers = append(o.Rulers, RulerRecord{Name: r0.Name, Base: r0.Base, Epithet: r0.Epithet, From: r0.Since, To: h.year, Conquests: r0.Conquests, Figure: r0.Figure, Dynasty: o.Dynasty})
	if len(o.Rulers) > 60 {
		o.Rulers = o.Rulers[1:]
	}
	o.Ruler = h.newRuler(l, o)
	usurp := r.Float64() < chance
	if r0.Figure >= 0 {
		f := h.figures[r0.Figure]
		f.Died = h.year
		text := fmt.Sprintf("Died at %d", h.year-r0.Birth)
		if usurp {
			text = fmt.Sprintf("Overthrown at %d by %s", h.year-r0.Birth, o.Ruler.Name)
		}
		h.deed(f, text)
		family := -1
		if o.Core >= 0 {
			family = h.peoples[o.Core].Family
		}
		_, hasTitle := h.familyTitles[family]
		if (f.Conquests >= 80 || f.Realm >= 200) && family >= 0 && !hasTitle && r.Float64() < .25 {
			base := strings.TrimRight(strings.ToLower(r0.Base), "aeiou")
			title := base + pick(r, []string{"ar", "or", "an", "er", "ar"})
			h.familyTitles[family] = FamilyTitle{Word: title, Figure: f.ID, Polity: o.ID}
			h.chron("culture", fmt.Sprintf("The name of %s outlives its bearer: rulers of the %s family of peoples will style themselves %s.", f.Name, h.peoples[family].Name, title), o.Capital)
		}
	}
	if o.Kind == "horde" && r.Float64() < .1+.45*(1-o.S) {
		o.Shock += .6
		if o.Cells >= 10 {
			h.chron("war", fmt.Sprintf("On the death of %s, the %s begins to splinter among rival chiefs.", r0.Name, o.Full), o.Capital)
		}
		h.civilWar(o, true)
		return
	}
	if usurp {
		o.Dynasty = personName(l, r)
		o.Generation = 1
		o.Shock += .3
		o.Mandate = .75
		if o.Cells >= 60 {
			f := h.figFor(o, o.Ruler, "usurper")
			h.deed(f, "Seized the throne of the "+o.Full+", ending the House of "+old)
			h.chron("war", o.Ruler.Name+" seizes the throne of the "+o.Full+"; the House of "+old+" falls.", o.Capital)
		}
	} else {
		o.Generation++
	}
}

// Statecraft is kept in its original location before yearly crisis pressure.
func (h *history) statecraft(o *Polity, c CellID, year int) {
	r := h.r
	t := func(k int) float64 { return float64(h.tech[k][c]) }
	if !o.ComplexitySet {
		o.ComplexitySet = true
		o.Complexity = .2
		o.Treasury = .3
		o.Inequality = .25
		o.WarCost = 0
	}
	if o.Kind != "state" {
		o.PT = 0
		o.PF = 0
		o.PQ = 0
		o.Burden = 0
		return
	}
	real := math.Max(1, float64(o.Cells-o.WasteN))
	o.WarCost *= .995
	target := .15 + .35*t(TechWriting) + .2*t(TechLaw) + .2*t(TechRoads) + .15*t(TechPaper) + .3*math.Min(1, real/250) + .1*math.Min(1, float64(o.FortN)/20) + .2*math.Min(1, o.WarCost)
	if target > o.Complexity {
		o.Complexity += .01 * (target - o.Complexity)
	} else {
		o.Complexity += .0015 * (target - o.Complexity)
	}
	exponent, ledger := 1.8, 1.
	if t(TechLedger) > .5 {
		exponent = 1.6
		ledger = 1.1
	}
	upkeep := .28 * math.Pow(o.Complexity, exponent) * o.Pop
	revenue := o.Tax*ledger + 1
	o.Burden = upkeep / revenue
	o.PT = math.Max(0, o.Burden-1) * 1.2
	atWar := o.Enemies.Len() > 0
	warDrain := 0.
	if atWar {
		warDrain = .02
	}
	o.Treasury = clamp(o.Treasury+.04*(1-o.Burden)-warDrain, -2, 1)
	o.PF = math.Max(0, -o.Treasury) * .6
	if o.Treasury < -1.2 && t(TechLaw) > .5 && r.Float64() < .02 {
		if o.Inequality > .5 && r.Float64() < .5 {
			o.Treasury = 0
			o.Inequality = math.Max(.2, o.Inequality-.12)
			o.Mandate = math.Min(1, o.Mandate+.15)
			if real >= 25 {
				h.chron("culture", capFirst(h.rulerName(o))+" of the "+o.Full+" proclaims a jubilee: debts are cancelled and debt-slaves freed.", c)
			}
		} else {
			o.Treasury = -.2
			o.Mandate = math.Max(0, o.Mandate-.2)
			o.Shock += .3
			if real >= 25 {
				h.chron("fall", "The treasury of the "+o.Full+" is empty: the crown defaults on its debts and its soldiers go unpaid.", c)
			}
		}
	}
	plough := float64(o.PloughN) / real
	peace := .0004
	if atWar {
		peace = 0
	}
	o.Inequality = clamp(o.Inequality+.0012*(o.Press-.75)*(1+.8*plough)+peace-.0004*(1-plough)*(o.Inequality-.25), .15, .92)
	factor := .6
	if o.Press > .85 {
		factor = 1.6
	}
	o.PQ = math.Max(0, o.Inequality-.55) * factor
	if year%10 == 0 {
		if o.P10 != 0 && o.Pop < .8*o.P10 && o.PlagueDeaths > .1*o.P10 {
			was := o.Inequality
			o.Inequality = math.Max(.2, o.Inequality-.15)
			if real >= 30 && was > .45 {
				h.chron("culture", "After the great dying, labour is scarce in the "+o.Full+": wages rise and the great landholders lose their grip.", c)
			}
		}
		o.P10 = o.Pop
		o.PlagueDeaths = 0
	}
	warNeed := 0.
	if atWar {
		warNeed = .3
	}
	need := clamp((o.Press-.8)*2+warNeed+.5*math.Max(0, o.Burden-.8)-.3*math.Max(0, 1-o.Press), -1, 1)
	energy := clamp(-.8+.6*t(TechArd)+.5*t(TechIron)+.4*t(TechHorse)+.3*(float64(o.CoastN)/math.Max(1, float64(o.Cells)))+.4*float64(h.world.river[c])+.3*t(TechCamel)+.3*t(TechWheel), -1, 1)
	if !o.CensusReady {
		energy = math.NaN()
	} // JS coastN is absent until census
	o.Fac = &[2]float64{need, energy}
}

func (h *history) techFit(o *Polity, k int) float64 {
	p := v06.Tech[k].Pos
	if len(p) == 0 || o.Fac == nil {
		return 1
	}
	dx, dy := p[0]-o.Fac[0], p[1]-o.Fac[1]
	return math.Exp(-(dx*dx + dy*dy) / .6)
}

var culturalWorks = []string{"epic", "temple", "chronicle", "law treatise", "observatory", "song cycle", "palace", "book of hymns", "philosophy", "great library"}

func (h *history) culture(o *Polity) {
	c := o.Capital
	surplus, stability, lit := clamp(1.15-o.Press, 0, 1), clamp(1-o.Psi/2, 0, 1), float64(h.tech[TechWriting][c])
	coast := 0.
	if h.world.coast[c] {
		coast = .3
	}
	connection := .5*clamp(float64(o.NB.Len()+len(o.Allies))/8, 0, 1) + .5*clamp(float64(h.tech[TechPaper][c])+coast, 0, 1)
	urban := clamp(o.CityPopulation/(o.Pop+1)*4, 0, 1)
	patron := clamp(o.E/h.etOf(o), 0, 2) / 2
	horde := 1.
	if o.Kind == "horde" {
		horde = .5
	}
	target := (.3 + .7*math.Sqrt(surplus)) * stability * (.3 + .7*lit) * (.5 + .5*(.4*urban+.3*connection+.3*patron)) * horde
	o.Culture += (target - o.Culture) * .05
	o.CultureWhy = [6]float64{surplus, stability, lit, connection, urban, patron}
	if o.Culture > .5 {
		if o.GoldStart == 0 {
			o.GoldStart = h.year
		}
		if h.r.Float64() < .01*o.Culture && o.Cells >= 6 {
			ruler := h.newRuler(h.langAt(c), nil)
			ruler.Epithet = ""
			ruler.Birth = h.year - 30 - int(h.r.Float64()*20)
			ruler.Death = h.year + int(h.r.Float64()*25)
			f := h.figFor(o, ruler, "sage")
			f.Title = "Sage of the " + o.Full
			f.Died = ruler.Death
			f.Works = 1
			kind := pick(h.r, culturalWorks)
			name := "the " + kind + " of " + ruler.Base
			o.Works = append(o.Works, Work{Year: h.year, Name: name, Figure: f.ID})
			h.deed(f, "Created "+name)
			if o.Cells >= 25 {
				h.chron("culture", "In the "+o.Full+", "+ruler.Base+" completes "+name+".", c)
			}
		}
	} else if o.GoldStart != 0 && o.Culture < .38 {
		duration := h.year - o.GoldStart
		if duration >= 60 {
			o.Golds = append(o.Golds, [2]int{o.GoldStart, h.year})
			parts := []string{}
			if surplus > .4 {
				parts = append(parts, "ample harvests")
			}
			if stability > .6 {
				parts = append(parts, "long peace at home")
			}
			if urban > .5 {
				parts = append(parts, "great cities")
			}
			if connection > .5 {
				parts = append(parts, "busy contacts abroad")
			}
			if patron > .5 {
				parts = append(parts, "rich patrons")
			}
			works := 0
			for _, w := range o.Works {
				if w.Year >= o.GoldStart {
					works++
				}
			}
			if o.Cells >= 20 && works >= 1 {
				extra := ""
				if len(parts) > 0 {
					extra = ", fed by " + strings.Join(parts[:min(3, len(parts))], ", ")
				}
				plural, verb := "", "s"
				if works > 1 {
					plural = "s"
					verb = ""
				}
				h.chron("culture", fmt.Sprintf("Looking back, the years %s to %s were a flowering for the %s%s; %d great work%s date%s from it.", formatYear(o.GoldStart), formatYear(h.year), o.Full, extra, works, plural, verb), c)
			}
		}
		o.GoldStart = 0
	}
}
