package sim

// Entity records are owned by history. ID relationships are indices/sentinels,
// never object addresses. Fields grow with the systems that consume them.
type Polity struct {
	ID                                               int
	Kind, Full                                       string
	Capital                                          CellID
	Core                                             int
	Alive                                            bool
	Burden, Inequality, Shock, PlagueDeaths, Culture float64
	Religion                                         int
}

type Religion struct {
	ID                         int
	Name, Kind                 string
	Family                     int
	Missionary, Centralization float64
}

type Spotlight struct {
	Year int
	Text string
	Cell CellID
}

type Outbreak struct {
	ID                      int
	Name                    string
	Origin                  CellID
	Year, End               int
	Deaths, Virulence, Pool float64
	Cells, Active           int
	Done, Virgin            bool
	From                    int
	Spread                  [][2]int
	Hit                     orderedSet[int]
}

type migrationPressure struct {
	Population    float64
	Year          int
	Cell          CellID
	By, Migration int
}
type Migration struct {
	ID, People, Religion                int
	Name, Kind, Cause                   string
	Population                          float64
	Cell                                CellID
	DX, DY                              float64
	Path                                []CellID
	Start, End, Steps, Max, Fails       int
	Cohesion, Military, Farm, Herd      float64
	Techs                               [techCount]float32
	Polity, Previous, By, SettledPolity int
	Done, Logged                        bool
	Result, StartText                   string
	Broke                               []int
}

func (h *history) spot(text string, cell CellID) {
	h.spotlights = append(h.spotlights, Spotlight{Year: h.year, Text: text, Cell: cell})
	if len(h.spotlights) > 60 {
		h.spotlights = h.spotlights[1:]
	}
}
