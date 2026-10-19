package sim

import (
	"fmt"
	"math"
	"strconv"
)

// Epoch is a centuries-long climate anomaly (v0.6 EPOCH_KINDS, 919–923).
type Epoch struct {
	Kind   string  `json:"kind"`
	Start  int     `json:"start"`
	End    int     `json:"end"`
	Amp    float64 `json:"amp"`
	Cell   CellID  `json:"cell"`
	Where  string  `json:"where"`
	CX     int     `json:"cx,omitempty"`
	CY     int     `json:"cy,omitempty"`
	Radius float64 `json:"radius,omitempty"`
	Done   bool    `json:"done"`
}

// climateStep is v0.6 lines 924–942. newHistory calls it once at the start
// year; the annual calendar will call it every year once AdvanceYear exists.
func (h *history) climateStep() {
	r, y, w := h.r, h.year, h.world
	h.gT += -h.gT/150 + .35*math.Sqrt(2.0/150)*gauss(r)
	if h.epoch != nil {
		e := h.epoch
		if y >= e.End {
			k := v06.epochKind(e.Kind)
			if e.Kind == "dry" {
				h.chron("nature", fmt.Sprintf("%s %s after %d years.", k.End, e.Where, y-e.Start), e.Cell)
			} else {
				h.chron("nature", k.End, e.Cell)
			}
			e.Done = true
			h.epoch = nil
		}
	} else if r.Float64() < .0007*h.rules.get("epochs") {
		u := r.Float64()
		k := &v06.EpochKinds[0]
		for i := range v06.EpochKinds {
			if u < v06.EpochKinds[i].Weight {
				k = &v06.EpochKinds[i]
				break
			}
			u -= v06.EpochKinds[i].Weight
		}
		amp := k.Amp[0] + r.Float64()*(k.Amp[1]-k.Amp[0])
		dur := int(jsRound(k.Duration[0] + r.Float64()*(k.Duration[1]-k.Duration[0])))
		e := &Epoch{Kind: k.Kind, Start: y, End: y + dur, Amp: amp, Cell: NoCell}
		if k.Kind == "dry" {
			c := NoCell
			for t := 0; t < 200; t++ {
				i := w.landList[int(r.Float64()*float64(len(w.landList)))]
				if h.pop[i] > 1000 && w.temperature[i] > 5 {
					c = i
					break
				}
			}
			if c < 0 {
				// v0.6 returns here: no epoch, and orbM is NOT recomputed this call.
				return
			}
			e.Cell = c
			e.CX, e.CY = int(c)%w.config.Width, int(c)/w.config.Width
			e.Radius = 10 + r.Float64()*12
			e.Where = h.regionName(c)
			h.chron("nature", fmt.Sprintf("%s %s; it will last for generations.", k.Start, e.Where), c)
		} else {
			h.chron("nature", k.Start, NoCell)
		}
		h.epoch = e
		h.epochs = append(h.epochs, e)
	}
	// Earth has a fixed orbital curve and consumes no orbital-phase draw.
	if h.world.source.Kind == "earth" {
		h.orbM = 1 / (1 + math.Exp((float64(y)+3300)/320))
	} else {
		h.orbM = .5 + .5*math.Cos(2*math.Pi*(float64(y)-h.orb0)/23000)
	}
}

func (c *legacyCatalog) epochKind(kind string) *epochKind {
	for i := range c.EpochKinds {
		if c.EpochKinds[i].Kind == kind {
			return &c.EpochKinds[i]
		}
	}
	panic("unknown epoch kind " + kind)
}

func (h *history) epochTemp() float64 {
	e := h.epoch
	if e == nil || e.Kind == "dry" {
		return 0
	}
	y := float64(h.year)
	ramp := math.Min(1, math.Min((y-float64(e.Start))/40, (float64(e.End)-y)/40))
	return e.Amp * math.Max(0, ramp)
}

// toFixed0 is Number.prototype.toFixed(0) for finite non-negative values.
func toFixed0(x float64) string { return strconv.FormatFloat(jsRound(x), 'f', 0, 64) }

func (h *history) regionName(c CellID) string {
	w := h.world
	la := float64(w.latitude[c]) * 180 / math.Pi
	lo := (float64(int(c)%w.config.Width)+.5)/float64(w.config.Width)*360 - 180
	if e := h.eth[c]; e >= 0 {
		return "lands of the " + h.peoples[e].Name
	}
	ns, ew := "N", "E"
	if la < 0 {
		ns = "S"
	}
	if lo < 0 {
		ew = "W"
	}
	return fmt.Sprintf("region near %s°%s, %s°%s", toFixed0(math.Abs(la)), ns, toFixed0(math.Abs(lo)), ew)
}

// computeK is v0.6 lines 958–980: carrying capacity of every land province
// from climate, weather, monsoon, rivers, coasts, ecology, technology,
// soils, forest, salinity, disease and temporary omen modifiers. Every term
// is kept even when the initial technology arrays are zero.
func (h *history) computeK() {
	w := h.world
	dT := h.dT + h.gT + h.epochTemp()
	orb := h.orbM
	tk := &h.tech
	b2f := func(b bool) float64 {
		if b {
			return 1
		}
		return 0
	}
	for _, c := range w.landList {
		i := int(c)
		T := float64(w.temperature[i]) + dT
		if T < -9 {
			h.K[i] = 1
			continue
		}
		wm, mz := float64(h.wm[i]), float64(w.monsoonZone[i])
		pn := float64(w.precipitation[i])*wm + orb*mz*420
		ar, rv, coast := float64(w.area[i]), float64(w.river[i]), b2f(w.coast[i])
		npp := math.Min(3000/(1+math.Exp(1.315-.119*(T+float64(w.amplitude[i])*.15))), 3000*(1-math.Exp(-.000664*pn)))
		kf := ar * .1 * npp / 1000 * (1 + .5*coast + .4*rv)
		dry := clamp(wm, .3, 1.6)
		sh := float64(w.herdSuitability[i])
		if mz > 0 {
			sh = math.Max(sh, orb*mz*.7)
		}
		if w.desert[i] {
			sh = math.Max(sh, .25*float64(tk[TechCamel][i]))
		}
		kh := ar * 1.6 * sh * float64(tk[TechHerd][i]) * math.Min(1.3, dry) * (1 + .2*float64(tk[TechHorse][i])) * (1 - float64(h.rp[i]))
		irrig := float64(tk[TechIrrigation][i])
		irr := irrig * rv
		wf := 1 + (math.Min(dry, 1.25)-1)*(1-.75*irr)
		hv, lc := float64(w.heavySoil[i]), float64(w.leach[i])
		sf, forest := float64(w.farmSuitability[i]), float64(h.forest[i])
		t := func(k int) float64 { return float64(tk[k][i]) }
		kfa := ar * 3.5 * sf * t(TechFarm) * float64(h.fert[i]) * wf *
			(1 + .8*t(TechCopper) + .9*t(TechIron)*(1-.4*lc) + 1.0*t(TechCrops) + .7*t(TechWriting) + .55*t(TechArd)*(1-.6*hv) +
				.7*t(TechPlough)*hv + .6*t(TechManure) + t(TechXCrops)*(.25+.8*lc+.5*float64(w.tropical[i])+.3*(1-sf)) +
				.4*t(TechFungal)*math.Max(lc, forest) + .15*t(TechTidemill)*coast) *
			(1 + rv*(.25+2.2*irrig))
		kfa *= (.45 + .55*(1-forest)) * (1 - .6*float64(h.salt[i])) * (1 - .5*float64(w.oncho[i]))
		if w.temperature[i] < 12 {
			kfa *= clamp(1+.18*dT, .4, 1.35)
		}
		if hv > 0 {
			kfa *= 1 - .7*hv*(1-math.Max(t(TechPlough), .4*t(TechIron)))
		}
		k := math.Max(math.Max(1, kf), math.Max(kh+.4*kf, kfa+.3*kh+.2*kf)) *
			(1 - .5*float64(w.malaria[i])*(1-float64(h.adapt[i]))*(1-.5*t(TechFeverbark)))
		h.K[i] = float32(k)
		if float64(h.kModUntil[i]) > float64(h.year) {
			h.K[i] = float32(math.Max(1, float64(h.K[i])*float64(h.kMod[i])))
		}
	}
}
