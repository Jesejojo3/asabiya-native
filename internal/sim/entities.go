package sim

// Entity records are owned by history. ID relationships are indices/sentinels,
// never object addresses. Fields grow with the systems that consume them.
type Polity struct {
	RGB                                                                                       [3]uint8
	Base, Dynasty, PeakName                                                                   string
	Born, Died, Generation, Cells, MaxCells, Conquests, From, LastBy, Crises                  int
	Over, Tributaries, OverYear, Era, Raided, Invaded                                         int
	E, S, Press, MD, ADM, NomF, Pop, K, MaxPop                                                float64
	Wet, P5, Reach, Gate, AggressionMultiplier, Psi                                           float64
	FamineYear, LowYear, CoastN, FarmN, FortN, LandmassN, WasteN, PloughN, HeavyN             int
	Tax, Integration, Mandate, Complexity, Treasury, WarCost, PT, PF, PQ, P10, Specialization float64
	ComplexitySet                                                                             bool
	Niche                                                                                     *[4]float64
	ForeignShare, ForeignPopulation                                                           float64
	Fac                                                                                       *[2]float64
	LX, LY, Loot                                                                              float64
	FK, FE, Island, ConquestDynasty, Departed, WallLogged                                     bool
	SettledYear, AssimilationTime, Restores, RestoredBy                                       int
	Hist, Allies, WarsF, Kids, Successors                                                     []int
	Sample                                                                                    []CellID
	Enemies, Truce, NB                                                                        orderedMap[int, int]
	Origin                                                                                    PolityOrigin
	FounderR                                                                                  *Ruler
	Why                                                                                       []Factor
	GoldStart                                                                                 int
	Works                                                                                     []Work
	Golds                                                                                     [][2]int
	CultureWhy                                                                                [6]float64
	Shape                                                                                     *RealmShape
	ShapeN                                                                                    int
	InShapes                                                                                  bool
	Tier                                                                                      string
	CityPopulation, MaxProvincePopulation                                                     float64
	Ruler                                                                                     *Ruler
	Rulers                                                                                    []RulerRecord
	NameUse                                                                                   map[string]int
	ID                                                                                        int
	Kind, Full                                                                                string
	Capital                                                                                   CellID
	Core                                                                                      int
	Alive                                                                                     bool
	Burden, Inequality, Shock, PlagueDeaths, Culture                                          float64
	Religion                                                                                  int
}

type PolityOrigin struct {
	Type                             string
	From, People, Migration, Settled int
	Why                              string
}
type Factor struct {
	Key   string
	Value float64
}
type Work struct {
	Year   int
	Name   string
	Figure int
}
type RealmShape struct{ EW, NS, N int }
type DarkWatch struct {
	Year, Polity int
	Cells        []CellID
}
type War struct {
	ID                                 int
	Name                               string
	Attackers, Defenders               []int
	Start, End, GainA, GainD, LastGain int
	Civil, Holy, Notable               bool
	ASet                               orderedSet[int]
	Why, Outcome                       string
}

type Religion struct {
	Founder, Born, Polity, People, Holder, Parent int
	Origin, Holy                                  CellID
	RGB                                           [3]uint8
	Kids, States                                  []int
	Cells, Peak, Councils                         int
	Population, Lon, Lat                          float64
	Alive                                         bool
	Died                                          int
	ID                                            int
	Name, Kind                                    string
	Family                                        int
	Missionary, Centralization                    float64
}

type Spotlight struct {
	Year int
	Text string
	Cell CellID
}

type City struct {
	ID           int
	Name         string
	Cell         CellID
	Born, People int
	Peak         float64
	Holy         bool
}
type Ruler struct {
	ID                                                 int
	Base, Name, Epithet, Exceptional                   string
	Female                                             bool
	Aggression, Competence, Charisma, Piety            float64
	Conquests, Since, MilitaryInventions, Birth, Death int
	Figure                                             int
}
type RulerRecord struct {
	Name, Base, Epithet, Dynasty string
	From, To, Conquests, Figure  int
}
type Deed struct {
	Year int
	Text string
}
type Figure struct {
	ID                                                            int
	Name, Kind, Title, Exceptional                                string
	Polity, People, Born, Died, Conquests, Realm, Religion, Works int
	Deeds                                                         []Deed
}
type FamilyTitle struct {
	Word           string
	Figure, Polity int
}
type TradeRoute struct {
	ID         int
	Key        string
	Born, Last int
	A, B       CellID
	Path       []CellID
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
