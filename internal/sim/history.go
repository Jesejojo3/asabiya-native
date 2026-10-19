package sim

import (
	"fmt"
	"math"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

const (
	WeatherCells   = WeatherGridWidth * WeatherGridHeight
	maxChronicle   = 30000
	chronicleTrim  = 4000
	initialFavor   = 3
	coastalSailing = .05
)

// Hearth is a scheduled origin of a technique (v0.6 newHistory 903–913).
// Non-farm hearths have no cell until hearthCheck places them.
type Hearth struct {
	Kind     string  `json:"kind"`
	Cell     CellID  `json:"cell"`
	Year     int     `json:"year"`
	Done     bool    `json:"done"`
	Fixed    bool    `json:"fixed,omitempty"`
	Crop     string  `json:"crop,omitempty"`
	Animal   string  `json:"animal,omitempty"`
	Grain    float64 `json:"grain,omitempty"`
	GrainSet bool    `json:"grainSet,omitempty"`
}

// ChronicleEntry keeps the legacy English sentence. It is narrative, not the
// structured event contract (EVENTS_AND_SAVE.md); it never feeds back into rules.
type ChronicleEntry struct {
	Year int    `json:"year"`
	Kind string `json:"kind"`
	Text string `json:"text"`
	Cell CellID `json:"cell"`
}

// StatsEntry is recordStats (v0.6 1902–1909) for the periods ported so far.
type StatsEntry struct {
	Year          int       `json:"year"`
	Population    float64   `json:"population"`
	Polities      int       `json:"polities"`
	Hordes        int       `json:"hordes"`
	LivingPeoples int       `json:"livingPeoples"`
	LeadingEra    int       `json:"leadingEra"`
	TempAnomaly   float64   `json:"temperatureAnomaly"`
	Orbital       float64   `json:"orbitalMonsoon"`
	EraShare      []float64 `json:"eraShare"`
}

// history is the mutable historical state (v0.6 S) for the systems ported so
// far. World stays immutable; every per-province array here belongs to one
// simulation. Fields are added only together with the systems that use them.
type history struct {
	annualState
	world *World
	rules Rules
	r     *rng.Mulberry32
	seed  string
	year  int
	start int
	famN  int

	tech       [techCount][]float32
	pop, K     []float32
	eth, eth2  []int32
	city       []int32
	fert       []float32
	wm         []float32
	ag         []float32 // AG: 40×20 weather anomaly field
	kMod       []float32
	kModUntil  []float32
	forest     []float32
	salt       []float32
	adapt      []float32
	rp         []float32
	circE      []float32
	lmFound    []uint8
	dT, gT     float64
	orbM, orb0 float64
	epoch      *Epoch
	epochs     []*Epoch
	favor      float64

	peoples   []*People
	hearths   []Hearth
	chronicle []ChronicleEntry
	stats     []StatsEntry
	seeds     []CellID
}

func (h *history) chron(kind, text string, cell CellID) {
	h.chronicle = append(h.chronicle, ChronicleEntry{Year: h.year, Kind: kind, Text: text, Cell: cell})
	if len(h.chronicle) > maxChronicle {
		h.chronicle = append([]ChronicleEntry(nil), h.chronicle[chronicleTrim:]...)
	}
}

func newFloat32(n int, v float32) []float32 {
	a := make([]float32, n)
	if v != 0 {
		for i := range a {
			a[i] = v
		}
	}
	return a
}

func newInt32(n int, v int32) []int32 {
	a := make([]int32, n)
	for i := range a {
		a[i] = v
	}
	return a
}

func (w *World) angDist(a, b CellID) float64 {
	d := float64(w.x3[a])*float64(w.x3[b]) + float64(w.y3[a])*float64(w.y3[b]) + float64(w.z3[a])*float64(w.z3[b])
	return math.Acos(clamp(d, -1, 1))
}

// ring visits a (2rad+1)² square in dy-then-dx order, clipped at the poles and
// wrapped in longitude, including the centre (v0.6 line 841).
func (w *World) ring(c CellID, rad int, f func(CellID)) {
	cx, cy := int(c)%w.config.Width, int(c)/w.config.Width
	for dy := -rad; dy <= rad; dy++ {
		y := cy + dy
		if y < 0 || y >= w.config.Height {
			continue
		}
		for dx := -rad; dx <= rad; dx++ {
			f(CellID(y*w.config.Width + (cx+dx+w.config.Width)%w.config.Width))
		}
	}
}

// newHistory ports v0.6 lines 864–916 for procedural worlds. The RNG order is:
// orbital phase, 800 weather anomalies, climateStep, founding seeds and their
// languages/peoples, ten ethPass rounds, farming hearths, then the five other
// technique hearths. snapshot() (map history for the time slider) is not part
// of the causal state and belongs to internal/history; it is not ported here.
func newHistory(w *World, historySeed string, rules Rules) *history {
	n := w.Len()
	start := int(rules.get("startYear"))
	h := &history{world: w, rules: rules, r: rng.New(rng.HistorySeed(historySeed, w.config.Seed)), seed: historySeed,
		year: start, start: start, pop: newFloat32(n, 0), K: newFloat32(n, 0), eth: newInt32(n, -1), eth2: newInt32(n, -1),
		city: newInt32(n, -1), fert: newFloat32(n, 1), wm: newFloat32(n, 1), ag: newFloat32(WeatherCells, 0),
		kMod: newFloat32(n, 1), kModUntil: newFloat32(n, -1e9), salt: newFloat32(n, 0), adapt: newFloat32(n, 0),
		rp: newFloat32(n, 0), lmFound: make([]uint8, len(w.landmassSizes)), favor: initialFavor}
	for k := range h.tech {
		h.tech[k] = newFloat32(n, 0)
	}
	// prepEco already ran when World was built; copy its mutable layers.
	h.forest = append([]float32(nil), w.forest...)
	h.circE = append([]float32(nil), w.circumscription...)
	r := h.r
	for _, c := range w.landList {
		h.adapt[c] = float32(float64(w.malaria[c]) * .5)
	}
	h.orb0 = r.Float64() * 23000
	for _, c := range w.coastList {
		h.tech[TechSail][c] = coastalSailing
	}
	for k := range h.ag {
		h.ag[k] = float32(gauss(r))
	}
	h.climateStep()
	h.computeK()

	// Founding stocks: procedural branch of v0.6 (Earth seeds are not ported).
	seeds, macros := []CellID{}, []string{}
	sep := .38
	bands := int(rules.get("bands"))
	for t := 0; t < 20000 && len(seeds) < bands; t++ {
		if t%4000 == 3999 {
			sep *= .7
		}
		i := w.landList[int(r.Float64()*float64(len(w.landList)))]
		if w.temperature[i] < 4 || w.precipitation[i] < 350 || w.landmassSizes[w.landmass[i]] < 20 {
			continue
		}
		ok := true
		for _, j := range seeds {
			if !(w.angDist(i, j) > sep) {
				ok = false
				break
			}
		}
		if ok {
			seeds = append(seeds, i)
			k := (len(seeds) - 1 + int(r.Float64()*float64(len(v06.Macros)))) % len(v06.Macros)
			macros = append(macros, v06.Macros[k].Key)
		}
	}
	q := make([]CellID, n)
	head, tail := 0, 0
	for k, i := range seeds {
		mac := macros[k]
		style := pick(r, v06.macroByKey[mac].Styles)
		lang := makeLanguage(r, style, mac)
		h.eth[i] = int32(h.newPeople(-1, -1, lang))
		q[tail] = i
		tail++
	}
	for head < tail {
		i := q[head]
		head++
		for _, j := range w.neighbors[i] {
			if j >= 0 && w.land[j] && h.eth[j] < 0 && w.temperature[j] > -9 {
				h.eth[j] = h.eth[i]
				q[tail] = j
				tail++
			}
		}
		if w.coast[i] {
			w.ring(i, 3, func(j CellID) {
				if w.land[j] && h.eth[j] < 0 && w.temperature[j] > -9 {
					h.eth[j] = h.eth[i]
					q[tail] = j
					tail++
				}
			})
		}
	}
	for _, i := range w.landList {
		if h.eth[i] >= 0 {
			h.pop[i] = float32(float64(h.K[i]) * .55)
			h.lmFound[w.landmass[i]] = 1
		}
	}
	for k := 0; k < 10; k++ {
		h.ethPass(false)
	}

	// Hearths: v0.6 uses the random branch for every non-Earth world.
	var cand []CellID
	for _, i := range w.landList {
		if float64(w.farmSuitability[i]) > .45 && w.landmassSizes[w.landmass[i]] > 40 {
			cand = append(cand, i)
		}
	}
	var hs []CellID
	hearthCount := int(rules.get("hearths"))
	for t := 0; t < 4000 && len(hs) < hearthCount && len(cand) > 0; t++ {
		i := cand[int(r.Float64()*float64(len(cand)))]
		if r.Float64() > float64(w.farmSuitability[i])*(.6+.4*float64(w.river[i])) {
			continue
		}
		ok := true
		for _, j := range hs {
			if !(w.angDist(i, j) > .32) {
				ok = false
				break
			}
		}
		if ok {
			hs = append(hs, i)
		}
	}
	jsInt := func(x float64) int { return int(int32(math.Trunc(x))) } // (expr)|0 in range
	for k, c := range hs {
		var offset float64
		if k == 0 {
			offset = 200 + r.Float64()*900
		} else {
			offset = 400 + r.Float64()*5500
		}
		h.hearths = append(h.hearths, Hearth{Kind: "farm", Cell: c, Year: jsInt(float64(h.start) + offset)})
	}
	for _, x := range []struct {
		kind       string
		base, span float64
	}{{"sail", 1500, 3000}, {"copper", 3800, 1800}, {"horse", 4000, 1500}, {"camel", 6500, 1500}, {"ard", 4300, 1500}} {
		h.hearths = append(h.hearths, Hearth{Kind: x.kind, Cell: NoCell, Year: jsInt(float64(h.start) + x.base + r.Float64()*x.span)})
	}
	first := NoCell
	if len(seeds) > 0 {
		first = seeds[0]
	}
	h.seeds = seeds
	h.chron("nature", fmt.Sprintf("Foragers of %d unrelated stocks people the habitable world.", len(seeds)), first)
	h.recordStats()
	return h
}

func (h *history) recordStats() {
	w := h.world
	tp := 0.0
	eraPop := make([]float64, len(v06.Eras))
	for _, c := range w.landList {
		p := float64(h.pop[c])
		if p < 1 {
			continue
		}
		tp += p
		eraPop[h.eraOf(int(c))] += p
	}
	living := 0
	for _, e := range h.peoples {
		if e.Alive {
			living++
		}
	}
	lead := 0
	for k := len(eraPop) - 1; k >= 0; k-- {
		if eraPop[k] > tp*.03 {
			lead = k
			break
		}
	}
	div := tp
	if div == 0 {
		div = 1
	}
	share := make([]float64, len(eraPop))
	for k, v := range eraPop {
		share[k] = v / div
	}
	// No polities exist before the political systems are ported.
	h.stats = append(h.stats, StatsEntry{Year: h.year, Population: tp, LivingPeoples: living, LeadingEra: lead,
		TempAnomaly: h.gT + h.epochTemp(), Orbital: h.orbM, EraShare: share})
}

func (h *history) langAt(c CellID) *Language {
	e := h.eth[c]
	if e < 0 {
		e = 0
	}
	return h.peoples[e].Language
}

// placeName is v0.6 line 2094: a city name (no cities yet), a place-word in the
// local tongue from a derived per-province RNG, or a coordinate description.
func (h *history) placeName(k CellID) string {
	w := h.world
	if k < 0 || int(k) >= w.Len() {
		return "the world"
	}
	if h.city[k] >= 0 {
		panic("cities are not ported yet")
	}
	if h.eth[k] >= 0 {
		return placeWord(h.langAt(k), rng.New(placeNameSeed(h.seed, w.config.Seed, k)))
	}
	la := float64(w.latitude[k]) * 180 / math.Pi
	lo := (float64(int(k)%w.config.Width)+.5)/float64(w.config.Width)*360 - 180
	ns, ew := "N", "E"
	if la < 0 {
		ns = "S"
	}
	if lo < 0 {
		ew = "W"
	}
	return fmt.Sprintf("the wilds at %s°%s %s°%s", toFixed0(math.Abs(la)), ns, toFixed0(math.Abs(lo)), ew)
}
