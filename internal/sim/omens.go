package sim

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

func (h *history) omenCheck(kind string, cell CellID) string {
	def := omenDef(kind)
	if def == nil {
		return "Unknown omen"
	}
	if cell < 0 || int(cell) >= h.world.Len() || !h.world.land[cell] {
		return "Choose a province on land"
	}
	if !h.rules.Sandbox && h.favor < float64(def.Cost) {
		return fmt.Sprintf("Needs %d favor; you have %.0f", def.Cost, math.Floor(h.favor))
	}
	var o *Polity
	if h.pol[cell] != 0 {
		o = h.polities[h.pol[cell]]
	}
	if def.Needs == "realm" && o == nil {
		return def.Name + " needs a province that belongs to a realm"
	}
	if def.Needs == "people" && float64(h.pop[cell])/float64(h.world.area[cell]) < .5 {
		return "Too few people live here for " + strings.ToLower(def.Name) + " to take hold"
	}
	if kind == "prophet" {
		count := 0
		for _, r := range h.religions {
			if r.Alive {
				count++
			}
		}
		if count >= 40 {
			return "The world already has as many faiths as it can hold"
		}
	}
	if kind == "plague" && h.infection[cell] != 0 {
		return "A plague is already raging here"
	}
	return ""
}
func (h *history) castOmen(kind string, cell CellID) (*Omen, string) {
	h.prepareAnnualState()
	if message := h.omenCheck(kind, cell); message != "" {
		return nil, message
	}
	def := omenDef(kind)
	r := h.r
	var o *Polity
	if h.pol[cell] != 0 {
		o = h.polities[h.pol[cell]]
	}
	place := h.placeName(cell)
	om := &Omen{ID: len(h.omens), Type: kind, Cell: cell, Year: h.year, Place: place, Religion: -1, Plague: -1, Cataclysm: -1}
	if o != nil {
		om.Owner = o.ID
	}
	area := []CellID{cell}
	if def.KM != 0 {
		area = h.cellsWithin(cell, def.KM)
	}
	populationArea := area
	if def.KM == 0 {
		populationArea = h.cellsWithin(cell, 450)
	}
	for _, i := range populationArea {
		om.PopulationBefore += float64(h.pop[i])
	}
	om.Cells = len(area)
	om.KM = def.KM
	realm := ""
	if o != nil {
		realm = " in the " + o.Full
	}
	switch kind {
	case "kindle":
		sum := 0.
		for _, i := range area {
			factor := 1 - .6*h.world.angDist(cell, i)*earthRadiusKM/def.KM
			h.cohesion[i] = float32(math.Min(1, float64(h.cohesion[i])+.4*factor))
			sum += float64(h.cohesion[i])
		}
		om.Text = "A comet blazes over " + place + realm + "; its people take it as a sign."
		om.Why = fmt.Sprintf("Your omen: asabiya across %d provinces rose to an average of %.2f.", len(area), sum/float64(len(area)))
	case "discord":
		count := 0
		for _, i := range area {
			if h.pol[i] == int32(o.ID) {
				h.cohesion[i] = float32(float64(h.cohesion[i]) * .45)
				count++
			}
		}
		o.Mandate = math.Max(0, o.Mandate-.5)
		o.Shock += .5
		o.E = math.Min(.12, o.E*1.3)
		om.Text = "Rival claimants divide the " + o.Full + " around " + place + "."
		om.Why = fmt.Sprintf("Your omen: asabiya fell by more than half in %d provinces, and the dynasty lost much of its mandate.", count)
		if o.Ruler.Figure >= 0 {
			h.deed(h.figures[o.Ruler.Figure], "Faced rival claimants (your omen)")
		}
	case "bounty", "drought":
		good := kind == "bounty"
		factor, years := .5, 60
		if good {
			factor = 1.45
			years = 100
		}
		lost := 0.
		for _, i := range area {
			h.kMod[i] = float32(factor)
			h.kModUntil[i] = float32(h.year + years)
			if !good {
				deaths := float64(h.pop[i]) * .18
				h.pop[i] = float32(float64(h.pop[i]) - deaths)
				lost += deaths
			}
		}
		if !good && lost > 1000 && h.eth[cell] >= 0 {
			h.pushPressure(int(h.eth[cell]), lost*.5, cell, 0, -1)
		}
		if good {
			om.Text = "Rains come on time over " + place + realm + ", year after year."
			om.Why = fmt.Sprintf("Your omen: the land of %d provinces can feed 45%% more people for a century.", len(area))
		} else {
			om.Text = "The rains fail over " + place + realm + "."
			om.Why = fmt.Sprintf("Your omen: %d provinces lost about %s people at once, and the land will feed half as many for sixty years; hunger may set peoples moving.", len(area), fmtK(lost))
		}
	case "spark":
		candidates := []int{}
		for f := 2; f < techCount; f++ {
			if f == TechGrain || f == TechXCrops || float64(h.tech[f][cell]) >= .5 {
				continue
			}
			ok := true
			for _, p := range v06.Tech[f].Pre {
				if float64(h.tech[p][cell]) < .5 {
					ok = false
					break
				}
			}
			if ok {
				candidates = append(candidates, f)
			}
		}
		keys := make(map[int]float64)
		for _, k := range candidates {
			keys[k] = float64(v06.Tech[k].Era) + r.Float64()*.9
		}
		sort.SliceStable(candidates, func(i, j int) bool { return keys[candidates[i]] < keys[candidates[j]] })
		got := candidates[:min(2, len(candidates))]
		for _, f := range got {
			h.seedTech(f, cell, 1, 2)
			h.seedTech(f, o.Capital, 1, 1)
			if f == TechWriting {
				for _, i := range h.polCells(o.ID) {
					h.tech[TechWriting][i] = float32(math.Max(float64(h.tech[TechWriting][i]), .35))
				}
			}
			h.firstTech(f, cell, o)
		}
		if len(got) == 0 {
			cells := h.polCells(o.ID)
			for k := 0; k < techCount; k++ {
				maximum := 0.
				for _, i := range cells {
					maximum = math.Max(maximum, float64(h.tech[k][i]))
				}
				if maximum >= .5 {
					for _, i := range cells {
						h.tech[k][i] = float32(math.Max(float64(h.tech[k][i]), maximum*.9))
					}
				}
			}
		}
		o.Culture = math.Min(1, o.Culture+.25)
		scholar := h.newRuler(h.langAt(cell), nil)
		scholar.Epithet = ""
		scholar.Birth = h.year - 30 - int(r.Float64()*15)
		scholar.Death = h.year + 10 + int(r.Float64()*30)
		figure := h.figFor(o, scholar, "scholar")
		figure.Title = "Scholar of the " + o.Full
		figure.Died = scholar.Death
		names := []string{}
		for _, k := range got {
			names = append(names, strings.ToLower(v06.Tech[k].Name))
		}
		if len(got) > 0 {
			h.deed(figure, "Brought "+strings.Join(names, " and ")+" to the "+o.Full+" (your omen)")
			pronoun := "it"
			if len(got) > 1 {
				pronoun = "them"
			}
			om.Why = "Your omen: the realm learns " + strings.Join(names, " and ") + "; neighbours will pick " + pronoun + " up in time."
		} else {
			h.deed(figure, "Gathered the scattered knowledge of the "+o.Full+" (your omen)")
			om.Why = "Your omen: there was nothing new within reach, so everything known anywhere in the realm spreads through all of it."
		}
		om.Text = figure.Name + " of " + place + " has an idea that changes the " + o.Full + "."
	case "prophet":
		religion := h.foundReligionAt(cell, true)
		figure := h.figures[religion.Founder]
		om.Text = "The prophet " + figure.Name + " begins to preach " + religion.Name + " at " + place + realm + "."
		adopted := ""
		if o != nil && o.Religion == religion.ID {
			adopted = "; the court adopts it"
		}
		om.Why = "Your omen: a new faith takes root" + adopted + "."
		om.Religion = religion.ID
	case "plague":
		prefix := ""
		if h.eth[cell] >= 0 {
			prefix = capFirst(h.peoples[h.eth[cell]].Language.Lex[LexRiver]) + " "
		}
		outbreak := &Outbreak{ID: len(h.outbreaks), Name: prefix + pick(r, plagueNames), Origin: cell, Year: h.year, Virulence: .16 + r.Float64()*.12, Cells: 1, Active: 1, Spread: [][2]int{{0, int(cell)}}, Omen: true}
		h.outbreaks = append(h.outbreaks, outbreak)
		h.infection[cell] = 3
		h.outbreakAt[cell] = int32(outbreak.ID)
		h.infections = append(h.infections, cell)
		h.immunity[cell] = 0
		om.Text = "The " + outbreak.Name + " breaks out at " + place + realm + "."
		om.Why = fmt.Sprintf("Your omen: it kills about %.0f%% of the unexposed it reaches each year.", jsRound(outbreak.Virulence*100))
		om.Plague = outbreak.ID
	case "doom":
		cat := h.randomCataclysm(cell, true)
		if cat == nil {
			return nil, "Nothing here can be broken that way"
		}
		om.Text = cat.Text
		om.Why = "Your omen: " + strings.ToLower(cat.Why[:1]) + cat.Why[1:]
		om.Cataclysm = cat.ID
	}
	if !h.rules.Sandbox {
		h.favor -= float64(def.Cost)
	}
	h.chron("omen", om.Text, cell)
	om.Entry = len(h.chronicle) - 1
	h.omens = append(h.omens, om)
	return om, om.Text
}

func (h *history) foundReligionAt(c CellID, omen bool) *Religion {
	r := h.r
	var o *Polity
	if h.pol[c] != 0 {
		o = h.polities[h.pol[c]]
	}
	l := h.langAt(c)
	var e *People
	if h.eth[c] >= 0 {
		e = h.peoples[h.eth[c]]
	}
	prophet := h.newRuler(l, nil)
	prophet.Epithet = ""
	prophet.Birth = h.year - (25 + int(r.Float64()*15))
	prophet.Death = prophet.Birth + 55 + int(r.Float64()*25)
	figure := h.figFor(o, prophet, "prophet")
	people, family := "people", -1
	if e != nil {
		people = e.Name
		family = e.Family
	}
	figure.Polity = 0
	if o != nil {
		figure.Polity = o.ID
	}
	figure.People = int(h.eth[c])
	figure.Title = "Prophet of the " + people
	figure.Died = prophet.Death
	god, base := capFirst(l.Lex[LexGod]), prophet.Base
	name := pick(r, []string{god + "ism", "the Way of " + base, "the " + god + " Covenant", "the Faith of " + god, base + "ism", "the " + capFirst(l.Lex[LexSun]) + " Path"})
	universal := r.Float64() < .65
	if h.city[c] < 0 {
		h.newCity(c, true)
	}
	kind, miss, cent := "ethnic", .15, .1
	if universal {
		kind = "universal"
		miss = .35 + .65*r.Float64()
		cent = .3 + .4*r.Float64()
	}
	owner := 0
	if o != nil {
		owner = o.ID
	}
	religion := &Religion{ID: len(h.religions), Name: name, Founder: figure.ID, Born: h.year, Origin: c, Holy: c, Polity: owner, People: int(h.eth[c]), Family: family, Kind: kind, Missionary: miss, Centralization: cent, Holder: owner, RGB: hsl(r.Float64()*360, .55, .48), Parent: -1, Alive: true, Omen: omen}
	h.religions = append(h.religions, religion)
	figure.Religion = religion.ID
	h.religion[c] = int32(religion.ID)
	for _, j := range h.world.neighbors[c] {
		if j >= 0 && h.pop[j] >= 1 && (o == nil || h.pol[j] == int32(o.ID)) {
			h.religion[j] = int32(religion.ID)
		}
	}
	if o != nil && r.Float64() < .4 {
		o.Religion = religion.ID
		religion.States = append(religion.States, o.ID)
	}
	realm, extra := "", ""
	if o != nil {
		realm = " in the " + o.Full
	}
	if omen {
		extra = " (your omen)"
	}
	h.deed(figure, "Began to preach "+name+realm+extra)
	return religion
}

func (h *history) omenFollow(om *Omen) {
	def := omenDef(om.Type)
	c := om.Cell
	var o *Polity
	if h.pol[c] != 0 {
		o = h.polities[h.pol[c]]
	}
	om.Followed = true
	radius := def.KM
	if radius == 0 {
		radius = 450
	}
	area := h.cellsWithin(c, radius)
	set := make(map[CellID]bool)
	population := 0.
	for _, i := range area {
		set[i] = true
		population += float64(h.pop[i])
	}
	change := jsRound(100 * (population/math.Max(1, om.PopulationBefore) - 1))
	born := []*Polity{}
	for _, p := range h.polities {
		if p != nil && p.Born > om.Year && set[p.Capital] && p.MaxCells >= 4 {
			born = append(born, p)
		}
	}
	sort.SliceStable(born, func(i, j int) bool { return born[i].MaxCells > born[j].MaxCells })
	born = born[:min(2, len(born))]
	var was *Polity
	if om.Owner != 0 {
		was = h.polities[om.Owner]
	}
	name := func(p *Polity) string {
		if p.Alive {
			return p.Full
		}
		return p.PeakName
	}
	text := "Fifty years after your " + strings.ToLower(def.Name) + " at " + om.Place + ": "
	if len(born) > 0 {
		names := []string{}
		for _, p := range born {
			names = append(names, name(p))
		}
		verb := "has"
		if len(born) > 1 {
			verb = "have"
		}
		text += "the " + strings.Join(names, " and the ") + " " + verb + " risen nearby; "
	}
	if o != nil && (was == nil || o.ID != was.ID) {
		text += "the land now belongs to the " + o.Full
	} else if o != nil {
		text += "it still belongs to the " + o.Full
	} else if was != nil {
		text += "it lies outside any realm"
	} else {
		text += "it remains stateless"
	}
	if was != nil && (o == nil || o.ID != was.ID) {
		if was.Alive {
			text += ", taken from the " + name(was)
		} else {
			text += " (the " + name(was) + " is gone)"
		}
	}
	text += "."
	direction := "up"
	if change < 0 {
		direction = "down"
	}
	why := fmt.Sprintf("Population of the area %s %.0f%%", direction, math.Abs(change))
	if o != nil {
		cohesion := o.S
		if math.IsNaN(cohesion) {
			cohesion = 0
		}
		why += fmt.Sprintf("; local asabiya %.2f, realm cohesion %.2f", h.cohesion[c], cohesion)
	}
	if om.Religion >= 0 {
		religion := h.religions[om.Religion]
		if religion.Alive {
			why += fmt.Sprintf("; %s holds %d provinces", religion.Name, religion.Cells)
		} else {
			why += "; " + religion.Name + " has died out"
		}
	}
	if om.Plague >= 0 {
		plague := h.outbreaks[om.Plague]
		why += "; the " + plague.Name + " killed about " + fmtK(plague.Deaths)
	}
	if om.Cataclysm >= 0 {
		cat := h.cataclysms[om.Cataclysm]
		why += "; " + cat.Name + " killed about " + fmtK(cat.Deaths)
	}
	h.chron("omen", text, c)
	// The explanatory sentence is retained with its omen for read-only views.
	om.FollowText = text
	om.FollowWhy = why + "."
}
func (h *history) omenPass() {
	if h.rules.Sandbox {
		h.favor = 9
	} else {
		h.favor = math.Min(5, h.favor+1./70)
	}
	for _, om := range h.omens {
		if !om.Followed && h.year-om.Year >= 50 {
			h.omenFollow(om)
		}
	}
	rate := h.rules.get("cataclysms")
	if rate > 0 && h.year-h.lastCataclysm > 150 && h.r.Float64() < rate/1000 {
		h.randomCataclysm(NoCell, false)
	}
}
