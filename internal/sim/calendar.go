package sim

// advanceYear is deliberately private until atomic commands, full-state digest
// and immutable publication are integrated. No renderer can observe its stages.
func (h *history) advanceYear() {
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
	h.computeK()
	h.growth()
	h.migrate()
	h.seaHop()
	if h.year%3 == 0 {
		h.techStep(0, .34)
		h.techStep(.34, .67)
		h.techStep(.67, 1)
	}
	h.disease()
	// Go remainder matches JS here: the positive residues 5 and 7 cannot occur
	// in negative years. This inherited trade/disease-pool behavior is retained.
	if h.year%10 == 5 {
		h.poolPass()
	}
	if h.year%20 == 7 {
		h.caravanPass()
	}
	h.omenPass()
	h.politics()
	if h.year%20 == 0 {
		h.ethPass(true)
		h.relPass()
	}
	if h.year%10 == 0 {
		h.recordStats()
		h.cityPass()
		h.regionPass()
		h.mixPass()
		h.snapshot()
	}
}
