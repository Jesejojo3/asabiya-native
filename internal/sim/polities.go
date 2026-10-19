package sim

import (
	"fmt"
	"math"
	"slices"
)

func (h *history) tierOf(o *Polity) string {
	n, p := o.Cells-o.WasteN, o.Pop
	if o.Kind == "horde" {
		if n < 6 || p < 20000 {
			return "Clans"
		}
		if n < 25 || p < 200000 {
			return "Horde"
		}
		return "Confederation"
	}
	nom := o.NomF > .5
	floor := h.rules.get("floor")
	if p < 60000*floor || (n < 4 && p < 240000*floor) {
		return "Chiefdom"
	}
	if n < 20 || (!nom && o.ADM < .25) || p < 600000*floor {
		if nom {
			return "Khanate"
		}
		return "Kingdom"
	}
	if nom {
		return "Khaganate"
	}
	return "Empire"
}
func fullName(o *Polity) string {
	if o.Tier == "Horde" || o.Tier == "Clans" {
		return o.Base + " " + o.Tier
	}
	return o.Tier + " of " + o.Base
}

type polityOptions struct {
	Base, Kind      string
	Origin          *PolityOrigin
	ConquestDynasty bool
	Restores        int
}

func (h *history) newPolity(c CellID, from *Polity, opt polityOptions) int {
	h.prepareAnnualState()
	r := h.r
	id := len(h.polities)
	e := int(h.eth[c])
	if e < 0 {
		e = 0
	}
	l := h.peoples[e].Language
	base := opt.Base
	if base == "" {
		base = l.Place
		duplicate := from != nil
		for _, k := range h.alive {
			if h.polities[k].Base == base {
				duplicate = true
				break
			}
		}
		if duplicate {
			base = placeWord(l, r)
		}
	}
	rgb := hsl(r.Float64()*360, .42+.22*r.Float64(), .5+.1*r.Float64())
	dyn := personName(l, r)
	kind := opt.Kind
	if kind == "" {
		kind = "state"
	}
	o := &Polity{ID: id, Base: base, Core: e, Capital: c, Born: h.year, Dynasty: dyn, Generation: 1, Kind: kind, E: .02, S: .5, Press: .5, Cells: 1, Pop: float64(h.pop[c]), K: 1, MaxCells: 1, Alive: true, FamineYear: -1e9, Reach: h.rules.get("reach"), Gate: 1, AggressionMultiplier: 1, Tier: "Chiefdom", Religion: int(h.religion[c]), Culture: .2, ConquestDynasty: opt.ConquestDynasty, Restores: opt.Restores, RGB: rgb}
	o.Origin = PolityOrigin{Type: "emerged", People: e}
	if from != nil {
		o.From = from.ID
		o.Origin = PolityOrigin{Type: "rebellion", From: from.ID}
	}
	if opt.Origin != nil {
		o.Origin = *opt.Origin
	}
	o.Ruler = h.newRuler(l, o)
	o.FounderR = o.Ruler
	o.Tier = h.tierOf(o)
	o.Full = fullName(o)
	o.PeakName = o.Full
	if from != nil {
		from.Kids = append(from.Kids, id)
		if from.ComplexitySet {
			o.ComplexitySet = true
			o.Complexity = from.Complexity * .55
			o.Inequality = from.Inequality * .85
			o.Treasury = .2
		}
	}
	h.polities = append(h.polities, o)
	h.alive = append(h.alive, id)
	h.pol[c] = int32(id)
	h.dist[c] = 0
	h.integ[c] = float32(math.Max(float64(h.integ[c]), .7))
	o.Mandate = 1
	if opt.Base == "" && kind == "state" {
		for _, f := range h.fallen {
			if h.year-f.Died > 900 || f.RestoredBy != 0 {
				continue
			}
			if f.Core < 0 || f.Core >= len(h.peoples) || h.peoples[f.Core].Family != h.peoples[e].Family {
				continue
			}
			if !slices.Contains(f.Sample, c) && h.world.angDist(c, f.Capital) > .06 {
				continue
			}
			if r.Float64() < .5 {
				f.RestoredBy = id
				o.Base = f.Base
				o.Restores = f.ID
				o.Origin = PolityOrigin{Type: "restoration", From: f.ID, People: e}
				o.Full = fullName(o)
				h.chron("rise", "Claiming the legacy of the fallen "+f.PeakName+", a new state rises in its old heartland and takes its name.", c)
			}
			break
		}
	}
	return id
}
func (h *history) etOf(o *Polity) float64 {
	c := o.Capital
	return .02 * (1 + float64(h.tech[TechWriting][c]) + .5*float64(h.tech[TechCoin][c]) + .5*float64(h.tech[TechLaw][c]))
}
func (h *history) cerealEff(i CellID) float64 {
	return float64(h.tech[TechGrain][i]) * (1 - .75*float64(h.world.leach[i])) * (1 - .65*float64(h.world.tropical[i]))
}
func (h *history) strength(o *Polity) float64 {
	if o.Kind == "horde" {
		return o.Pop + o.Loot*3
	}
	return o.Tax*1.6 + .25*o.Pop
}
func (h *history) power(o *Polity) float64 {
	return math.Pow(h.strength(o)+1, h.rules.get("scaleExp")) * (.3 + o.S) * h.milAt(o.Capital)
}
func (h *history) dd(i CellID) float64 {
	if h.dist[i] >= 65534 {
		return 40
	}
	return math.Min(60, float64(h.dist[i])*.5)
}
func (h *history) ecoD(i CellID, o *Polity) float64 {
	if o.Niche == nil {
		return 0
	}
	w := h.world
	v := o.Niche
	a, b, c, d := float64(w.nicheTemperature[i])-v[0], float64(w.nicheMoisture[i])-v[1], float64(w.nicheLifestyle[i])-v[2], float64(w.nicheDisease[i])-v[3]
	return math.Sqrt(a*a + b*b + c*c + d*d)
}
func (h *history) isWaste(i CellID, horde bool) bool {
	w := h.world
	if h.pop[i] < 1 {
		return true
	}
	if float64(h.pop[i])/float64(w.area[i]) < .25 && float64(w.farmSuitability[i]) < .12 {
		return true
	}
	if float64(h.tech[TechFarm][i])*float64(w.farmSuitability[i]) >= .12 || h.caravan[i] >= .3 || h.city[i] >= 0 {
		return false
	}
	desert := 0.
	if w.desert[i] {
		desert = 1
	}
	past := float64(h.tech[TechHerd][i]) * math.Max(float64(w.herdSuitability[i]), desert*float64(h.tech[TechCamel][i])*.6)
	if horde {
		return past < .15
	}
	return float64(h.K[i])/float64(w.area[i]) < 2.5
}
func (h *history) defense(j CellID) float64 {
	w := h.world
	q := h.pol[j]
	var strength float64
	if q != 0 {
		d := h.polities[q]
		strength = math.Pow(h.strength(d)+1, h.rules.get("scaleExp")) * (.5*d.S + .5*float64(h.cohesion[j])) * h.milAt(j) * math.Exp(-h.dd(j)/d.Reach) * (.6 + .4*float64(h.integ[j]))
	} else {
		strength = math.Pow(float64(h.pop[j])*4+1, .75) * float64(h.cohesion[j]) * h.milAt(j) * .8
	}
	return strength * (1 + 1.6*float64(w.roughness[j])) * (1 + 2.5*float64(h.fort[j]))
}
func (h *history) displace(j CellID, fraction float64, by int) float64 {
	p := float64(h.pop[j]) * fraction
	if p < 1 {
		return 0
	}
	h.pop[j] = float32(float64(h.pop[j]) - p)
	h.pushPressure(int(h.eth[j]), p, j, by, -1)
	return p
}
func (h *history) collapse(o *Polity) {
	lost := 0
	for _, i := range h.world.landList {
		if h.pol[i] == int32(o.ID) && h.dist[i] > 2 && i != o.Capital {
			h.pol[i] = 0
			h.cohesion[i] = .3
			lost++
		}
	}
	if o.MaxCells >= 20 && lost >= 5 {
		h.chron("fall", fmt.Sprintf("The %s loses its grip; %d provinces fall away into stateless hands.", o.Full, lost), o.Capital)
	}
}
