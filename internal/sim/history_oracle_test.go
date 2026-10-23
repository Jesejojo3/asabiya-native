package sim

import (
	"bytes"
	"encoding/json"
	"math"
	"os"
	"testing"
)

const (
	historyInputPath    = "../../tests/native/history-contract-input.v06.json"
	historyContractPath = "../../tests/native/history-contract.v06.json"
)

// historyInput is the subset of World read by v0.6 newHistory and its callees.
type historyInput struct {
	Schema      string    `json:"schema"`
	Seed        string    `json:"seed"`
	HistorySeed string    `json:"historySeed"`
	Width       int       `json:"width"`
	Height      int       `json:"height"`
	Land        []int     `json:"land"` // []int, not []uint8: encoding/json writes bytes as base64
	Coast       []int     `json:"coast"`
	Desert      []int     `json:"desert"`
	Nomad       []int     `json:"nomad"`
	Tsetse      []int     `json:"tsetse"`
	LM          []int32   `json:"lm"`
	LMSize      []int     `json:"lmSize"`
	NB          []int32   `json:"nb"`
	T           []float32 `json:"T"`
	Pr          []float32 `json:"Pr"`
	Amp         []float32 `json:"amp"`
	Area        []float32 `json:"area"`
	RV          []float32 `json:"rv"`
	Lat         []float32 `json:"lat"`
	X3          []float32 `json:"x3"`
	Y3          []float32 `json:"y3"`
	Z3          []float32 `json:"z3"`
	SF          []float32 `json:"sF"`
	SH          []float32 `json:"sH"`
	MonZone     []float32 `json:"monZone"`
	Heavy       []float32 `json:"heavy"`
	Leach       []float32 `json:"leach"`
	Trop        []float32 `json:"trop"`
	Oncho       []float32 `json:"oncho"`
	Mal         []float32 `json:"mal"`
	Forest0     []float32 `json:"forest0"`
	Circ        []float32 `json:"circ"`
}

func historyContractWorld(t *testing.T) *World {
	t.Helper()
	c := DefaultWorldConfig("Asabiya")
	c.Width, c.Height = 128, 64
	w, err := GenerateWorld(c)
	if err != nil {
		t.Fatal(err)
	}
	return w
}

func exportHistoryInput(w *World, historySeed string) historyInput {
	b := func(a []bool) []int {
		out := make([]int, len(a))
		for i, v := range a {
			if v {
				out[i] = 1
			}
		}
		return out
	}
	nb := make([]int32, 0, 4*w.Len())
	for _, n := range w.neighbors {
		for _, j := range n {
			nb = append(nb, int32(j))
		}
	}
	return historyInput{Schema: "asabiya/history-contract-input-v1", Seed: w.config.Seed, HistorySeed: historySeed,
		Width: w.config.Width, Height: w.config.Height, Land: b(w.land), Coast: b(w.coast), Desert: b(w.desert), Nomad: b(w.nomad),
		Tsetse: b(w.tsetse), LM: w.landmass, LMSize: w.landmassSizes, NB: nb, T: w.temperature, Pr: w.precipitation, Amp: w.amplitude,
		Area: w.area, RV: w.river, Lat: w.latitude, X3: w.x3, Y3: w.y3, Z3: w.z3, SF: w.farmSuitability, SH: w.herdSuitability,
		MonZone: w.monsoonZone, Heavy: w.heavySoil, Leach: w.leach, Trop: w.tropical, Oncho: w.oncho, Mal: w.malaria,
		Forest0: w.forest, Circ: w.circumscription}
}

// TestWriteHistoryInput regenerates the Go-side input for the JS oracle only
// when ASABIYA_WRITE_HISTORY_INPUT=1. Normal runs verify it below.
func TestWriteHistoryInput(t *testing.T) {
	if os.Getenv("ASABIYA_WRITE_HISTORY_INPUT") != "1" {
		t.Skip("set ASABIYA_WRITE_HISTORY_INPUT=1 to regenerate the oracle input")
	}
	data, err := json.Marshal(exportHistoryInput(historyContractWorld(t), "1"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(historyInputPath, append(data, '\n'), 0o644); err != nil {
		t.Fatal(err)
	}
}

type historyContract struct {
	ReferenceSHA256 string `json:"referenceSha256"`
	RNG             struct{ Seed, Calls uint64 }
	Year            int
	GT, Orb0, OrbM  float64
	FamN            int `json:"famN"`
	AG, K, Pop      []float64
	Eth             []int32
	Sail, Adapt     []float64
	LMFound         []int `json:"lmFound"`
	Peoples         []struct {
		Name                    string
		Lang                    languageFixtureLang
		Culture                 []float64
		Family, Parent, Parent2 int
		Depth, Born             int
		Hue, Sat, Lit           float64
		RGB                     [3]int
		Alive                   bool
		Cells                   int
		Pop, Peak, Lon, Lat     float64
		Kids                    []int
		Died                    *int
	}
	Hearths []struct {
		Kind string
		Cell int
		Year int
	}
	Chronicle []struct {
		Year int
		Kind string
		Text string
		Cell int
	}
	Stats []struct {
		Year         int
		Pop, GT, Orb float64
		PE, Lead     int
	}
	Places [][2]any
}

func near(a, b float64) bool {
	return a == b || math.Abs(a-b) <= math.Max(1e-9, 2e-6*math.Max(math.Abs(a), math.Abs(b)))
}

func TestOriginalHistoryContract(t *testing.T) {
	w := historyContractWorld(t)
	want, err := os.ReadFile(historyInputPath)
	if err != nil {
		t.Fatal(err)
	}
	// Compare decoded values, not bytes: a Windows checkout may rewrite line endings.
	var stored historyInput
	if err := json.Unmarshal(want, &stored); err != nil {
		t.Fatal(err)
	}
	got, _ := json.Marshal(exportHistoryInput(w, "1"))
	norm, _ := json.Marshal(stored)
	if !bytes.Equal(got, norm) {
		t.Fatal("history oracle input no longer matches the native world; investigate before regenerating")
	}
	b, err := os.ReadFile(historyContractPath)
	if err != nil {
		t.Fatal(err)
	}
	var c historyContract
	if err := json.Unmarshal(b, &c); err != nil {
		t.Fatal(err)
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	h := s.h
	// Discrete outcomes must be identical: RNG consumption, assignments, names.
	if pos := h.r.Position(); uint64(pos.Seed) != c.RNG.Seed || pos.Calls != c.RNG.Calls {
		t.Fatalf("RNG position %+v, original %+v", pos, c.RNG)
	}
	if h.year != c.Year || h.famN != c.FamN || len(h.peoples) != len(c.Peoples) {
		t.Fatalf("year/famN/peoples: %d %d %d, original %d %d %d", h.year, h.famN, len(h.peoples), c.Year, c.FamN, len(c.Peoples))
	}
	for i, e := range h.eth {
		if e != c.Eth[i] {
			t.Fatalf("eth[%d]=%d, original %d", i, e, c.Eth[i])
		}
	}
	for i, e := range h.peoples {
		o := c.Peoples[i]
		if e.Name != o.Name || !sameLang(toFixture(e.Language), o.Lang) || e.Family != o.Family || e.Parent != o.Parent ||
			e.Parent2 != o.Parent2 || e.Depth != o.Depth || e.Born != o.Born || e.Alive != o.Alive || e.Cells != o.Cells || len(e.Kids) != len(o.Kids) {
			t.Fatalf("people %d differs: %+v vs %+v", i, e, o)
		}
		if (e.Died == nil) != (o.Died == nil) || (e.Died != nil && *e.Died != *o.Died) {
			t.Fatalf("people %d death differs", i)
		}
		for k := range e.Kids {
			if e.Kids[k] != o.Kids[k] {
				t.Fatalf("people %d kids differ", i)
			}
		}
		for k := range e.RGB {
			if int(e.RGB[k]) != o.RGB[k] {
				t.Fatalf("people %d colour differs: %v vs %v", i, e.RGB, o.RGB)
			}
		}
		for k, v := range e.Culture {
			if !near(float64(v), o.Culture[k]) {
				t.Fatalf("people %d culture[%d] %v vs %v", i, k, v, o.Culture[k])
			}
		}
		for _, p := range [][2]float64{{e.Hue, o.Hue}, {e.Sat, o.Sat}, {e.Lit, o.Lit}, {e.Pop, o.Pop}, {e.Peak, o.Peak}, {e.Lon, o.Lon}, {e.Lat, o.Lat}} {
			if !near(p[0], p[1]) {
				t.Fatalf("people %d float field %v vs %v", i, p[0], p[1])
			}
		}
	}
	if len(h.hearths) != len(c.Hearths) {
		t.Fatalf("hearths %d vs %d", len(h.hearths), len(c.Hearths))
	}
	for i, x := range h.hearths {
		o := c.Hearths[i]
		if x.Kind != o.Kind || int(x.Cell) != o.Cell || x.Year != o.Year {
			t.Fatalf("hearth %d: %+v vs %+v", i, x, o)
		}
	}
	if len(h.chronicle) != len(c.Chronicle) {
		t.Fatalf("chronicle %d vs %d", len(h.chronicle), len(c.Chronicle))
	}
	for i, x := range h.chronicle {
		o := c.Chronicle[i]
		if x.Year != o.Year || x.Kind != o.Kind || x.Text != o.Text || int(x.Cell) != o.Cell {
			t.Fatalf("chronicle %d: %+v vs %+v", i, x, o)
		}
	}
	for i := range h.lmFound {
		if int(h.lmFound[i]) != c.LMFound[i] {
			t.Fatal("landmass settlement differs")
		}
	}
	// Continuous state: Go math is not V8, so allow a few ULPs of float32.
	for _, f := range []struct {
		name string
		got  []float32
		want []float64
	}{{"AG", h.ag, c.AG}, {"K", h.K, c.K}, {"pop", h.pop, c.Pop}, {"sail", h.tech[TechSail], c.Sail}, {"adapt", h.adapt, c.Adapt}} {
		if len(f.got) != len(f.want) {
			t.Fatalf("%s length", f.name)
		}
		for i := range f.got {
			if !near(float64(f.got[i]), f.want[i]) {
				t.Fatalf("%s[%d]=%v, original %v", f.name, i, f.got[i], f.want[i])
			}
		}
	}
	for _, p := range [][2]float64{{h.gT, c.GT}, {h.orb0, c.Orb0}, {h.orbM, c.OrbM}} {
		if !near(p[0], p[1]) {
			t.Fatalf("scalar %v vs %v", p[0], p[1])
		}
	}
	if len(h.stats) != len(c.Stats) {
		t.Fatal("stats length")
	}
	for i, x := range h.stats {
		o := c.Stats[i]
		if x.Year != o.Year || x.LivingPeoples != o.PE || x.LeadingEra != o.Lead || !near(x.Population, o.Pop) || !near(x.TempAnomaly, o.GT) || !near(x.Orbital, o.Orb) {
			t.Fatalf("stats %d: %+v vs %+v", i, x, o)
		}
	}
	for _, p := range c.Places {
		cell := CellID(int(p[0].(float64)))
		if got := h.placeName(cell); got != p[1].(string) {
			t.Fatalf("placeName(%d)=%q, original %q", cell, got, p[1])
		}
	}
}
