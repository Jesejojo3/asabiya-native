package sim

// Annual state is added together with its causal systems. It is not a second
// simulation and does not expose a partial AdvanceYear API.
type annualState struct {
	annualReady      bool
	anom             []float32
	firstDiscoveries [techCount]*Discovery
}

type Discovery struct {
	Year   int    `json:"year"`
	Cell   CellID `json:"cell"`
	Polity int    `json:"polity"`
	People int    `json:"people"`
}

func (h *history) prepareAnnualState() {
	if h.annualReady {
		return
	}
	h.anom = make([]float32, h.world.Len())
	h.annualReady = true
}

func (h *history) recordDiscovery(k int, c CellID) {
	if h.firstDiscoveries[k] == nil {
		h.firstDiscoveries[k] = &Discovery{Year: h.year, Cell: c, People: int(h.eth[c])}
	}
}
