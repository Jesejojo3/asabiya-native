package sim

// advanceYear is deliberately private until atomic commands, full-state digest
// and immutable publication are integrated. No renderer can observe its stages.
func (h *history) advanceYear() { h.advanceYearProfiled(nil) }

func (h *history) advanceYearProfiled(profile *workAccumulator) {
	clock := startWork(profile)
	if profile != nil { profile.mu.Lock(); profile.data.Years++; profile.mu.Unlock() }
	h.advanced = true
	h.prepareAnnualState()
	if h.snapshots.last == nil {
		h.snapshot()
	}
	h.year++
	h.climateStep()
	h.weather()
	h.hearthCheck()
	if h.volcanoYears > 0 {
		h.volcanoYears--
		if h.volcanoYears == 0 {
			h.dT = 0
		}
	} else if h.r.Float64() < .0012*h.rules.get("volcano") {
		h.volcano()
	}
	clock.mark(0)
	h.computeK()
	clock.mark(1)
	h.growth()
	clock.mark(2)
	h.migrate()
	h.seaHop()
	clock.mark(3)
	if h.year%3 == 0 {
		h.techStep(0, .34)
		h.techStep(.34, .67)
		h.techStep(.67, 1)
	}
	clock.mark(4)
	h.disease()
	// Go remainder matches JS here: the positive residues 5 and 7 cannot occur
	// in negative years. This inherited trade/disease-pool behavior is retained.
	if h.year%10 == 5 {
		h.poolPass()
	}
	if h.year%20 == 7 {
		h.caravanPass()
	}
	clock.mark(5)
	h.omenPass()
	h.politics()
	clock.mark(6)
	if h.year%20 == 0 {
		h.ethPass(true)
		h.relPass()
	}
	clock.mark(7)
	if h.year%10 == 0 {
		h.recordStats()
		h.cityPass()
		h.regionPass()
		h.mixPass()
		h.snapshot()
	}
	clock.mark(8)
}
