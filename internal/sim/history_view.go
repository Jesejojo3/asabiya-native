package sim

import (
	"crypto/sha256"
	"encoding/hex"
	"math"
	"slices"
)

const HistoryDigestVersion = "native/history-init-v1"

type HistorySummary struct {
	Version            string           `json:"version"`
	RulesVersion       string           `json:"rulesVersion"`
	StartYear          int              `json:"startYear"`
	Year               int              `json:"year"`
	FoundingStocks     int              `json:"foundingStocks"`
	Peoples            int              `json:"peoples"`
	LivingPeoples      int              `json:"livingPeoples"`
	Families           int              `json:"families"`
	Population         float64          `json:"population"`
	PeopledCells       int              `json:"peopledCells"`
	CarryingCapacity   float64          `json:"carryingCapacity"`
	LandmassesSettled  int              `json:"landmassesSettled"`
	TemperatureAnomaly float64          `json:"temperatureAnomalyC"`
	OrbitalMonsoon     float64          `json:"orbitalMonsoon"`
	Epoch              *Epoch           `json:"epoch,omitempty"`
	Hearths            []Hearth         `json:"hearths"`
	Chronicle          []ChronicleEntry `json:"chronicle"`
	Stats              []StatsEntry     `json:"stats"`
	SHA256             string           `json:"sha256"`
}

func (s *Simulation) Summary() HistorySummary {
	h, w := s.h, s.world
	sum := HistorySummary{Version: HistoryDigestVersion, RulesVersion: h.rules.Version, StartYear: h.start, Year: h.year,
		FoundingStocks: len(h.seeds), Peoples: len(h.peoples), TemperatureAnomaly: h.gT + h.epochTemp(), OrbitalMonsoon: h.orbM,
		Hearths: append([]Hearth(nil), h.hearths...), Chronicle: append([]ChronicleEntry(nil), h.chronicle...),
		Stats: append([]StatsEntry(nil), h.stats...), SHA256: s.Digest()}
	for i := range sum.Stats {
		sum.Stats[i].EraShare = slices.Clone(h.stats[i].EraShare)
	}
	if h.epoch != nil {
		e := *h.epoch
		sum.Epoch = &e
	}
	fams := map[int]bool{}
	for _, e := range h.peoples {
		fams[e.Family] = true
		if e.Alive {
			sum.LivingPeoples++
		}
	}
	sum.Families = len(fams)
	for _, c := range w.landList {
		p := float64(h.pop[c])
		sum.Population += p
		sum.CarryingCapacity += float64(h.K[c])
		if p >= 1 {
			sum.PeopledCells++
		}
	}
	for _, f := range h.lmFound {
		if f != 0 {
			sum.LandmassesSettled++
		}
	}
	return sum
}

// PeopleView is a value copy for headless/UI consumers.
type PeopleView struct {
	ID           int        `json:"id"`
	Name         string     `json:"name"`
	Family       int        `json:"family"`
	Parent       int        `json:"parent"`
	Depth        int        `json:"depth"`
	Born         int        `json:"born"`
	Alive        bool       `json:"alive"`
	Cells        int        `json:"cells"`      // legacy census at the last ethPass
	Population   float64    `json:"population"` // legacy census at the last ethPass
	CurrentCells int        `json:"currentCells"`
	CurrentPop   float64    `json:"currentPopulation"`
	Macro        string     `json:"macroFamily"`
	Style        string     `json:"style"`
	Homeland     string     `json:"homeland"`
	Root         string     `json:"root"`
	Lexicon      [8]string  `json:"lexicon"`
	SoundChanges []string   `json:"soundChanges"`
	Culture      [6]float32 `json:"culture"`
	RGB          [3]uint8   `json:"rgb"`
}

func (s *Simulation) Peoples() []PeopleView {
	out := make([]PeopleView, len(s.h.peoples))
	cells, pop := make([]int, len(out)), make([]float64, len(out))
	for _, c := range s.world.landList {
		if e := s.h.eth[c]; e >= 0 && s.h.pop[c] >= 1 {
			cells[e]++
			pop[e] += float64(s.h.pop[c])
		}
	}
	for i, e := range s.h.peoples {
		l := e.Language
		out[i] = PeopleView{ID: e.ID, Name: e.Name, Family: e.Family, Parent: e.Parent, Depth: e.Depth, Born: e.Born, Alive: e.Alive,
			Cells: e.Cells, Population: e.Pop, Macro: l.Macro, Style: l.Style, Homeland: l.Place, Root: l.Lex[LexRoot],
			Lexicon: l.Lex, SoundChanges: l.SoundChanges(), Culture: e.Culture, RGB: e.RGB,
			CurrentCells: cells[i], CurrentPop: pop[i]}
	}
	return out
}

type CellHistory struct {
	People           int     `json:"people"`
	PeopleName       string  `json:"peopleName,omitempty"`
	Population       float32 `json:"population"`
	CarryingCapacity float32 `json:"carryingCapacity"`
	DensityPerKM2    float64 `json:"densityPerKM2"`
	PlaceName        string  `json:"placeName"`
}

func (s *Simulation) Cell(id CellID) (CellHistory, bool) {
	h, w := s.h, s.world
	if id < 0 || int(id) >= w.Len() {
		return CellHistory{}, false
	}
	c := CellHistory{People: int(h.eth[id]), Population: h.pop[id], CarryingCapacity: h.K[id],
		DensityPerKM2: float64(h.pop[id]) / float64(w.area[id]), PlaceName: h.placeName(id)}
	if c.People >= 0 {
		c.PeopleName = h.peoples[c.People].Name
	}
	return c, true
}

// Digest is a native regression fingerprint of the initialized history: rules,
// RNG position, every state array and every people/hearth/chronicle record, in
// creation order. It is not a save format.
func (s *Simulation) Digest() string {
	h := s.h
	d := sha256.New()
	writeString(d, HistoryDigestVersion)
	writeString(d, h.rules.Version)
	for _, p := range v06.Parameters {
		writeU64(d, math.Float64bits(h.rules.Values[p.Key]))
	}
	writeString(d, h.rules.HearthMode)
	writeString(d, h.seed)
	pos := h.r.Position()
	for _, v := range []uint64{uint64(pos.Seed), pos.Calls, uint64(int64(h.year)), uint64(int64(h.start)), uint64(h.famN),
		math.Float64bits(h.dT), math.Float64bits(h.gT), math.Float64bits(h.orbM), math.Float64bits(h.orb0), math.Float64bits(h.favor)} {
		writeU64(d, v)
	}
	f32 := func(a []float32) {
		writeU64(d, uint64(len(a)))
		for _, v := range a {
			writeU32(d, math.Float32bits(v))
		}
	}
	i32 := func(a []int32) {
		writeU64(d, uint64(len(a)))
		for _, v := range a {
			writeU32(d, uint32(v))
		}
	}
	for _, a := range [][]float32{h.pop, h.K, h.fert, h.wm, h.ag, h.kMod, h.kModUntil, h.forest, h.salt, h.adapt, h.rp, h.circE} {
		f32(a)
	}
	for _, a := range [][]int32{h.eth, h.eth2, h.city} {
		i32(a)
	}
	for k := range h.tech {
		f32(h.tech[k])
	}
	d.Write(h.lmFound)
	writeU64(d, uint64(len(h.peoples)))
	for _, e := range h.peoples {
		writeString(d, e.Name)
		l := e.Language
		for _, x := range []string{l.Style, l.Macro, l.Place, l.People, l.Land, l.PlaceSuffix, l.PeopleSuffix, l.PrePeople, l.PrePlace} {
			writeString(d, x)
		}
		for _, x := range l.Lex {
			writeString(d, x)
		}
		for _, x := range l.SoundChanges() {
			writeString(d, x)
		}
		for _, v := range e.Culture {
			writeU32(d, math.Float32bits(v))
		}
		died := uint64(math.MaxUint64)
		if e.Died != nil {
			died = uint64(int64(*e.Died))
		}
		alive := uint64(0)
		if e.Alive {
			alive = 1
		}
		for _, v := range []uint64{uint64(int64(e.Family)), uint64(int64(e.Parent)), uint64(int64(e.Parent2)), uint64(e.Depth),
			uint64(int64(e.Born)), math.Float64bits(e.Hue), math.Float64bits(e.Sat), math.Float64bits(e.Lit), alive, uint64(e.Cells),
			math.Float64bits(e.Pop), math.Float64bits(e.Peak), math.Float64bits(e.Lon), math.Float64bits(e.Lat), died, uint64(len(e.Kids))} {
			writeU64(d, v)
		}
		for _, k := range e.Kids {
			writeU64(d, uint64(k))
		}
	}
	writeU64(d, uint64(len(h.hearths)))
	for _, x := range h.hearths {
		writeString(d, x.Kind)
		writeU64(d, uint64(int64(x.Cell)))
		writeU64(d, uint64(int64(x.Year)))
	}
	writeU64(d, uint64(len(h.epochs)))
	for _, e := range h.epochs {
		writeString(d, e.Kind)
		writeU64(d, uint64(int64(e.Start)))
		writeU64(d, uint64(int64(e.End)))
		writeU64(d, math.Float64bits(e.Amp))
	}
	writeU64(d, uint64(len(h.chronicle)))
	for _, c := range h.chronicle {
		writeU64(d, uint64(int64(c.Year)))
		writeString(d, c.Kind)
		writeString(d, c.Text)
		writeU64(d, uint64(int64(c.Cell)))
	}
	// False/false is the implicit v1 encoding, preserving the existing default
	// golden. Nondefault options append a versioned trailer with distinct bits;
	// both options affect identity even before they affect any historical data.
	var options uint32
	if h.rules.ShuffleNames {
		options |= 1
	}
	if h.rules.Sandbox {
		options |= 2
	}
	if options != 0 {
		writeString(d, "rules/options-v1")
		writeU32(d, options)
	}
	return hex.EncodeToString(d.Sum(nil))
}
