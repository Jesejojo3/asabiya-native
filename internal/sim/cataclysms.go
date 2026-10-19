package sim

import (
	"fmt"
	"math"
	"slices"
	"sort"
	"strings"
)

const earthRadiusKM = 6371

type Cataclysm struct {
	ID                int
	Kind, Name, Place string
	Year              int
	Cell              CellID
	KM                float64
	Scope             string
	Deaths            float64
	Omen              bool
	Hit               []int
	EraFrom, EraTo    int
	Text, Why         string
}
type Omen struct {
	ID                               int
	Type                             string
	Cell                             CellID
	Year, Owner                      int
	Place                            string
	PopulationBefore                 float64
	Followed                         bool
	Cells                            int
	KM                               float64
	Religion, Plague, Cataclysm      int
	Entry                            int
	Text, Why, FollowText, FollowWhy string
}

func (h *history) cellsWithin(origin CellID, km float64) []CellID {
	h.withinStamp++
	stamp := h.withinStamp
	q := []CellID{origin}
	h.withinMark[origin] = stamp
	out := []CellID{}
	for head := 0; head < len(q); head++ {
		i := q[head]
		if h.world.land[i] {
			out = append(out, i)
		}
		for _, j := range h.world.neighbors[i] {
			if j < 0 || h.withinMark[j] == stamp {
				continue
			}
			h.withinMark[j] = stamp
			if h.world.angDist(origin, j)*earthRadiusKM <= km {
				q = append(q, j)
			}
		}
	}
	return out
}
func (h *history) leadEra() int {
	total := 0.
	eras := make([]float64, len(v06.Eras))
	for _, i := range h.world.landList {
		p := float64(h.pop[i])
		if p < 1 {
			continue
		}
		total += p
		eras[h.eraOf(int(i))] += p
	}
	for k := len(eras) - 1; k >= 0; k-- {
		if eras[k] > total*.03 {
			return k
		}
	}
	return 0
}
func (h *history) cataSite(site string) CellID {
	w, r := h.world, h.r
	best, score := NoCell, -1.
	if site == "leader" {
		var leader *Polity
		value := -1.
		for _, id := range h.alive {
			o := h.polities[id]
			if o.Kind != "state" {
				continue
			}
			n := 0
			for _, f := range h.tech {
				if float64(f[o.Capital]) > .5 {
					n++
				}
			}
			v := float64(n) * math.Sqrt(o.Pop)
			if v > value {
				value = v
				leader = o
			}
		}
		if leader != nil {
			return leader.Capital
		}
	}
	for attempt := 0; attempt < 400; attempt++ {
		i := w.landList[int(r.Float64()*float64(len(w.landList)))]
		p := float64(h.pop[i])
		value := math.Sqrt(p + 1)
		switch site {
		case "any":
			value = r.Float64()
		case "mountain":
			value = float64(w.roughness[i]) * math.Sqrt(p+1)
		case "lowland":
			coast := 0.
			if w.coast[i] {
				coast = 1
			}
			low := .2
			if w.elevation[i] < 400 {
				low = 1
			}
			value = (coast + float64(w.river[i])) * math.Sqrt(p+1) * low
		}
		value *= .7 + .6*r.Float64()
		if value > score {
			score = value
			best = i
		}
	}
	return best
}
func (h *history) randomCataclysm(origin CellID, omen bool) *Cataclysm {
	era := 0
	if len(h.stats) > 0 {
		era = h.stats[len(h.stats)-1].LeadingEra
	}
	options := []*CataclysmDef{}
	total := 0.
	for i := range interventions.Cataclysms {
		c := &interventions.Cataclysms[i]
		if slices.Contains(c.Eras, era) {
			options = append(options, c)
			total += c.Weight
		}
	}
	if len(options) == 0 {
		return nil
	}
	x := h.r.Float64() * total
	chosen := options[0]
	for _, c := range options {
		x -= c.Weight
		if x <= 0 {
			chosen = c
			break
		}
	}
	return h.cataclysm(chosen.Key, origin, omen)
}
func (h *history) setKMod(i CellID, factor float64, years int) {
	if float64(h.kModUntil[i]) > float64(h.year) {
		h.kMod[i] = float32(math.Min(float64(h.kMod[i]), factor))
		h.kModUntil[i] = float32(math.Max(float64(h.kModUntil[i]), float64(h.year+years)))
	} else {
		h.kMod[i] = float32(factor)
		h.kModUntil[i] = float32(h.year + years)
	}
}
func (h *history) cataclysm(kind string, origin CellID, omen bool) *Cataclysm {
	h.prepareAnnualState()
	c := cataclysmDef(kind)
	if c == nil {
		return nil
	}
	if origin < 0 {
		site := "people"
		if c.Scope == "region" {
			site = c.Site
		}
		origin = h.cataSite(site)
	}
	if origin < 0 {
		return nil
	}
	place := h.placeName(origin)
	before := h.leadEra()
	name := strings.Replace(c.Title, "{place}", place, 1)
	for _, prior := range h.cataclysms {
		if prior.Name == name {
			name += " of " + formatYear(h.year)
			break
		}
	}
	cat := &Cataclysm{ID: len(h.cataclysms), Kind: kind, Name: name, Place: place, Year: h.year, Cell: origin, Scope: c.Scope, Omen: omen}
	if c.Scope == "region" {
		cat.KM = c.KM
	}
	weights := make([]float32, h.world.Len())
	if c.Scope == "region" {
		for _, i := range h.cellsWithin(origin, c.KM) {
			weights[i] = float32(1 - .6*h.world.angDist(origin, i)*earthRadiusKM/c.KM)
		}
	} else {
		for _, i := range h.world.landList {
			weights[i] = 1
		}
	}
	jitter := .75 + .5*h.r.Float64()
	deaths := 0.
	for _, i := range h.world.landList {
		weight := float64(weights[i])
		if weight == 0 {
			if c.World != nil {
				h.setKMod(i, c.World.KMod, c.World.KYears)
			}
			continue
		}
		d := float64(h.pop[i]) * c.Population * weight * jitter
		deaths += d
		h.pop[i] = float32(float64(h.pop[i]) - d)
		h.fort[i] = float32(float64(h.fort[i]) * (1 - c.Infrastructure*weight))
		h.integ[i] = float32(float64(h.integ[i]) * (1 - .5*c.Infrastructure*weight))
		for k := 2; k < techCount; k++ {
			if k == TechSail || k == TechGrain {
				continue
			}
			v := float64(h.tech[k][i])
			if v > 0 {
				h.tech[k][i] = float32(v * (1 - clamp(c.Technology*weight*jitter*(.35+.25*float64(v06.Tech[k].Era)), 0, .95)))
			}
		}
		h.cohesion[i] = float32(float64(h.cohesion[i]) * (1 - (1-c.Cohesion)*weight))
		h.setKMod(i, 1-(1-c.KMod)*weight, c.KYears)
	}
	var hitWeights orderedMap[int, float64]
	counts := make(map[int]int)
	for _, i := range h.world.landList {
		p := int(h.pol[i])
		if p == 0 {
			continue
		}
		counts[p]++
		if weights[i] != 0 {
			hitWeights.Set(p, hitWeights.Value(p)+float64(weights[i]))
		}
	}
	type impact struct {
		polity *Polity
		share  float64
	}
	hit := []impact{}
	hitWeights.Each(func(id int, weight float64) {
		o := h.polities[id]
		share := weight / float64(counts[id])
		if share < .05 {
			return
		}
		o.Shock += .8 * share
		o.Mandate = math.Max(0, o.Mandate-.4*share)
		o.Culture *= 1 - .5*share*math.Min(1, c.Technology)
		if o.ComplexitySet {
			o.Treasury -= .8 * share
		}
		if o.Ruler != nil && o.Ruler.Figure >= 0 {
			extra := ""
			if omen {
				extra = " (your omen)"
			}
			h.deed(h.figures[o.Ruler.Figure], "Struck by "+cat.Name+extra)
		}
		hit = append(hit, impact{o, share})
	})
	sort.SliceStable(hit, func(i, j int) bool { return hit[i].polity.Pop*hit[i].share > hit[j].polity.Pop*hit[j].share })
	for _, p := range hit[:min(12, len(hit))] {
		cat.Hit = append(cat.Hit, p.polity.ID)
	}
	cat.Deaths = deaths
	cat.EraFrom = before
	cat.EraTo = h.leadEra()
	h.cataclysms = append(h.cataclysms, cat)
	h.lastCataclysm = h.year
	realm := ""
	if c.Scope == "region" && len(hit) > 0 {
		realm = " in the " + hit[0].polity.Full
	}
	cat.Text = cat.Name + ": " + strings.Replace(c.Text, "{place}", place, 1) + realm + "."
	regression := ""
	if cat.EraTo < cat.EraFrom {
		regression = "; the world slides back from the " + v06.Eras[cat.EraFrom] + " to the " + v06.Eras[cat.EraTo]
	}
	cat.Why = c.Why + " About " + fmtK(deaths) + " dead" + regression + "."
	if !omen {
		h.chron("cata", cat.Text, origin)
		h.spot(cat.Text, origin)
	}
	return cat
}

func (h *history) volcano() {
	h.prepareAnnualState()
	r := h.r
	great := r.Float64() < .15
	if great {
		h.dT = -2.3
		h.volcanoYears = 4 + int(r.Float64()*3)
	} else {
		h.dT = -.8 - .6*r.Float64()
		h.volcanoYears = 1 + int(r.Float64()*2)
		h.chron("nature", "A great eruption veils the sun; harvests fail across the cooler lands for several years.", NoCell)
		return
	}
	h.chron("nature", "A colossal eruption darkens the sky: the sun is dim for years, summers fail across the world, and hunger stalks every land.", NoCell)
	h.spot("A volcanic winter grips the world", NoCell)
	for _, id := range h.alive {
		o := h.polities[id]
		o.Mandate = math.Max(0, o.Mandate-.25)
		o.Shock += .15
	}
	if r.Float64() < .5 {
		w := h.world
		best, score := NoCell, 0.
		for attempt := 0; attempt < 300; attempt++ {
			i := w.landList[int(r.Float64()*float64(len(w.landList)))]
			city := 0.
			if h.city[i] >= 0 {
				city = 2
			}
			density := float64(h.pop[i]) / float64(w.area[i]) * (1 + float64(h.caravan[i])*3 + city)
			if density > score && h.infection[i] == 0 {
				score = density
				best = i
			}
		}
		if best >= 0 {
			prefix := ""
			if h.eth[best] >= 0 {
				prefix = capFirst(h.peoples[h.eth[best]].Language.Lex[LexRiver]) + " "
			}
			o := &Outbreak{ID: len(h.outbreaks), Name: prefix + pick(r, plagueNames), Origin: best, Year: h.year, Virulence: .18 + r.Float64()*.1, Cells: 1, Active: 1, Spread: [][2]int{{0, int(best)}}}
			h.outbreaks = append(h.outbreaks, o)
			h.infection[best] = 3
			h.outbreakAt[best] = int32(o.ID)
			h.infections = append(h.infections, best)
			h.chron("plague", fmt.Sprintf("In the hungry years after the eruption, the %s breaks out.", o.Name), best)
		}
	}
}
