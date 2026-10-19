package sim

// Annual state is added together with its causal systems. It is not a second
// simulation and does not expose a partial AdvanceYear API.
type annualState struct {
	cities                        []*City
	figures                       []*Figure
	rulers                        []*Ruler
	familyTitles                  map[int]FamilyTitle
	lab, bfsParent, bfsMark       []int32
	bfsDistance                   []int16
	bfsStamp                      int32
	exit                          []float32
	routes                        []*TradeRoute
	caravanPairs                  orderedSet[string]
	annualReady                   bool
	anom                          []float32
	firstDiscoveries              [techCount]*Discovery
	pol                           []int32
	cohesion                      []float32
	religion                      []int32
	mix                           []float32
	mixTime                       []uint8
	immunity, plaguePool, caravan []float32
	infection                     []uint8
	outbreakAt                    []int32
	infections                    []CellID
	outbreaks                     []*Outbreak
	polities                      []*Polity
	religions                     []*Religion
	pressure                      orderedMap[int, *migrationPressure]
	migrations                    []*Migration
	activeMigrations              []int
	contacts, cropPairs           orderedSet[string]
	spotlights                    []Spotlight
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
	n := h.world.Len()
	h.pol = make([]int32, n)
	h.cohesion = newFloat32(n, .3)
	h.religion = newInt32(n, -1)
	h.mix = make([]float32, n)
	h.mixTime = make([]uint8, n)
	h.immunity = make([]float32, n)
	h.plaguePool = make([]float32, n)
	h.caravan = make([]float32, n)
	h.infection = make([]uint8, n)
	h.outbreakAt = newInt32(n, -1)
	h.polities = []*Polity{nil}
	h.familyTitles = make(map[int]FamilyTitle)
	h.lab = make([]int32, n)
	h.bfsParent = make([]int32, n)
	h.bfsMark = make([]int32, n)
	h.bfsDistance = make([]int16, n)
	h.exit = make([]float32, n)
	h.annualReady = true
}

func (h *history) recordDiscovery(k int, c CellID) {
	if h.firstDiscoveries[k] == nil {
		h.firstDiscoveries[k] = &Discovery{Year: h.year, Cell: c, People: int(h.eth[c])}
	}
}
