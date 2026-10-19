package sim

import (
	"math"
	"strings"
	"testing"
)

func checkHistoryInvariants(t *testing.T, s *Simulation) {
	t.Helper()
	h, w := s.h, s.world
	if h.r.Position().Calls == 0 {
		t.Fatal("newHistory consumed no historical draws")
	}
	peopled := 0
	cellsByPeople := make([]int, len(h.peoples))
	for i := 0; i < w.Len(); i++ {
		p, k, e := float64(h.pop[i]), float64(h.K[i]), h.eth[i]
		if math.IsNaN(p) || math.IsInf(p, 0) || p < 0 || math.IsNaN(k) || math.IsInf(k, 0) {
			t.Fatalf("invalid population/capacity at %d: %v %v", i, p, k)
		}
		if !w.land[i] {
			if p != 0 || k != 0 || e != -1 {
				t.Fatalf("ocean cell %d has history state", i)
			}
			continue
		}
		if k < 1 {
			t.Fatalf("land K below the original floor of 1 at %d: %v", i, k)
		}
		if e >= 0 {
			if int(e) >= len(h.peoples) || w.temperature[i] <= -9 {
				t.Fatalf("invalid people assignment at %d", i)
			}
			// newHistory settles at 55% of carrying capacity.
			if p != float64(float32(k*.55)) {
				t.Fatalf("initial density at %d is %v, want 0.55*K=%v", i, p, k*.55)
			}
			if p >= 1 {
				peopled++
				cellsByPeople[e]++
			}
		} else if p != 0 {
			t.Fatalf("population without people at %d", i)
		}
	}
	for id, e := range h.peoples {
		if e.ID != id || e.Name == "" || e.Language == nil || e.Language.People != e.Name {
			t.Fatalf("invalid people %d: %+v", id, e)
		}
		// v0.6 records Cells/Pop at the start of ethPass, before that pass's
		// splits move provinces to new peoples (oracle-confirmed), so they are
		// a lagging census. Peoples() also reports the live count.
		if e.Cells > 0 && !e.Alive {
			t.Fatalf("people %d has cells but is not alive", id)
		}
		if v := s.Peoples()[id]; v.CurrentCells != cellsByPeople[id] {
			t.Fatalf("people %d live cells %d, counted %d", id, v.CurrentCells, cellsByPeople[id])
		}
		if e.Parent >= 0 {
			if e.Parent >= id || e.Family != h.peoples[e.Parent].Family || e.Depth != h.peoples[e.Parent].Depth+1 {
				t.Fatalf("invalid lineage for %d", id)
			}
		} else if e.Family != id || e.Depth != 0 {
			t.Fatalf("founding people %d must head its own family", id)
		}
		for _, v := range e.Culture {
			if v < 0 || v > 1 {
				t.Fatalf("culture outside 0..1 for %d", id)
			}
		}
	}
	if len(h.seeds) > 0 && h.famN != len(h.seeds) {
		t.Fatalf("families %d != founding stocks %d", h.famN, len(h.seeds))
	}
	for _, v := range h.ag {
		if math.IsNaN(float64(v)) || math.IsInf(float64(v), 0) {
			t.Fatal("non-finite weather anomaly")
		}
	}
	farm := 0
	for k, x := range h.hearths {
		if x.Kind == "farm" {
			if !w.land[x.Cell] || float64(w.farmSuitability[x.Cell]) <= .45 || x.Year < h.start+200 || x.Year > h.start+5900 {
				t.Fatalf("invalid farm hearth %+v", x)
			}
			if k != farm {
				t.Fatal("farm hearths must precede the other techniques")
			}
			farm++
		} else if x.Cell != NoCell || x.Year < h.start+1500 || x.Year > h.start+8000 {
			t.Fatalf("invalid technique hearth %+v", x)
		}
	}
	if len(h.hearths) != farm+5 || farm > int(h.rules.get("hearths")) {
		t.Fatalf("unexpected hearths: %+v", h.hearths)
	}
	sum := s.Summary()
	if sum.PeopledCells != peopled || sum.Peoples != len(h.peoples) || len(sum.Stats) != 1 || sum.Stats[0].Year != h.start {
		t.Fatalf("summary inconsistent: %+v", sum)
	}
}

func TestHistoryReproducibleAndValidAcrossSeeds(t *testing.T) {
	for _, seed := range []string{"Asabiya", "Pangea", "México 🌍"} {
		c := DefaultWorldConfig(seed)
		c.Width, c.Height = 160, 80
		w, err := GenerateWorld(c)
		if err != nil {
			t.Fatal(err)
		}
		a, err := NewSimulation(w, "1")
		if err != nil {
			t.Fatal(err)
		}
		b, _ := NewSimulation(w, "1")
		other, _ := NewSimulation(w, "2")
		if a.Digest() != b.Digest() || a.Status() != b.Status() {
			t.Fatalf("%s: same seeds produced different histories", seed)
		}
		if a.Digest() == other.Digest() {
			t.Fatalf("%s: history seed has no effect", seed)
		}
		if a.World().Digest() != w.Digest() {
			t.Fatal("history mutated the world")
		}
		checkHistoryInvariants(t, a)
		checkHistoryInvariants(t, other)
		if len(a.h.seeds) == 0 {
			t.Fatalf("%s: no founding stocks", seed)
		}
	}
}

func TestDefaultWorldHistory(t *testing.T) {
	w, err := GenerateWorld(DefaultWorldConfig("Asabiya"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	checkHistoryInvariants(t, s)
	sum := s.Summary()
	if sum.FoundingStocks != 10 || sum.Families != 10 || sum.Peoples < 10 || sum.Population < 1e6 {
		t.Fatalf("unexpected default founding: %+v", sum)
	}
	if !strings.HasPrefix(sum.Chronicle[0].Text, "Foragers of 10 unrelated stocks") {
		t.Fatal("missing founding chronicle")
	}
}

func TestRulesValidationAndStartYear(t *testing.T) {
	w, err := GenerateWorld(smallConfig("rules"))
	if err != nil {
		t.Fatal(err)
	}
	for _, edit := range []func(*Rules){
		func(r *Rules) { r.Values["bands"] = 2.5 }, func(r *Rules) { r.Values["startYear"] = -13000 },
		func(r *Rules) { r.Values["growth"] = math.NaN() }, func(r *Rules) { r.Values["typo"] = 1 },
		func(r *Rules) { delete(r.Values, "hearths") }, func(r *Rules) { r.HearthMode = "x" }, func(r *Rules) { r.Version = "v0" },
	} {
		r := DefaultRules()
		edit(&r)
		if _, err := NewSimulationWithRules(w, "1", r); err == nil {
			t.Fatalf("accepted invalid rules %+v", r)
		}
	}
	r := DefaultRules()
	r.Values["startYear"] = -6000
	r.Values["bands"] = 3
	s, err := NewSimulationWithRules(w, "1", r)
	if err != nil {
		t.Fatal(err)
	}
	if s.Status().StartYear != -6000 || s.Status().Year != -6000 || len(s.h.seeds) > 3 {
		t.Fatalf("rules not applied: %+v", s.Status())
	}
	checkHistoryInvariants(t, s)
	// The caller's map is copied: later edits cannot reach the running history.
	r.Values["bands"] = 24
	if s.Rules().Values["bands"] != 3 {
		t.Fatal("rules aliased with caller")
	}
	if len(ParameterDefs()) != 40 || DefaultRules().Validate() != nil {
		t.Fatal("default rules invalid")
	}
}

func TestPlaceNamesAndQueries(t *testing.T) {
	w, err := GenerateWorld(smallConfig("names"))
	if err != nil {
		t.Fatal(err)
	}
	s, _ := NewSimulation(w, "1")
	for i := 0; i < w.Len(); i++ {
		c, ok := s.Cell(CellID(i))
		if !ok || c.PlaceName == "" {
			t.Fatalf("missing place name at %d", i)
		}
		again, _ := s.Cell(CellID(i))
		if again.PlaceName != c.PlaceName {
			t.Fatal("place names must be stable (derived RNG)")
		}
		if c.People < 0 && !strings.HasPrefix(c.PlaceName, "the wilds at ") {
			t.Fatalf("unpeopled place name %q", c.PlaceName)
		}
	}
	before := s.Status().HistoryRNG
	s.Cell(0)
	if s.Status().HistoryRNG != before {
		t.Fatal("queries consumed the historical RNG")
	}
	if _, ok := s.Cell(NoCell); ok {
		t.Fatal("accepted invalid cell")
	}
	views := s.Peoples()
	if len(views) != len(s.h.peoples) {
		t.Fatal("peoples view length")
	}
	if len(views) > 0 {
		views[0].Name = "changed"
		if s.h.peoples[0].Name == "changed" {
			t.Fatal("view aliases state")
		}
	}
}
