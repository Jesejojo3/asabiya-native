package sim

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

func TestOriginalSocietyContract(t *testing.T) {
	data, err := os.ReadFile("../../tests/native/society-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var want struct {
		RNG struct {
			Seed  uint32
			Calls uint64
		}
		FirstPeople int
		People      []struct {
			ID               int
			Name             string
			Parent, Parent2  int
			Alive, Stillborn bool
		}
		Cells     [][9]float64
		Cities    []City
		Religions []Religion
		Rulers    []struct {
			Name, Kind                           string
			Born, Died, Polity, People, Religion int
		}
		Routes int
	}
	if err = json.Unmarshal(data, &want); err != nil {
		t.Fatal(err)
	}
	w := historyContractWorld(t)
	s, _ := NewSimulation(w, "1")
	h := s.h
	h.prepareAnnualState()
	h.year = -4500
	h.rules.Values["mixing"] = 10
	h.rules.Values["faith"] = 10
	h.polities = append(h.polities, &Polity{ID: 1, Kind: "state", Full: "Contract kingdom", Capital: w.landList[0], Core: 0, Alive: true, Religion: -1, MaxProvincePopulation: 200000})
	first := len(h.peoples)
	for _, i := range w.landList {
		h.pop[i] = 200000
		h.eth[i] = 0
		h.eth2[i] = 1
		h.mix[i] = .4
		h.mixTime[i] = 15
		h.pol[i] = 1
		h.tech[TechFarm][i] = 1
		h.tech[TechPaper][i] = 1
		h.tech[TechWriting][i] = .8
	}
	h.mixPass()
	h.cityPass()
	h.foundReligion(h.polities[1])
	for _, i := range w.landList {
		h.religion[i] = 0
	}
	h.polities[1].Religion = 0
	for j := 0; j < 8; j++ {
		h.year += 20
		h.relPass()
	}
	h.exitPass(0, .5)
	h.exitPass(.5, 1)
	h.poolPass()
	h.caravanPass()
	p := h.r.Position()
	if p.Seed != want.RNG.Seed || p.Calls != want.RNG.Calls {
		t.Fatalf("RNG differs Go=%+v JS=%+v", p, want.RNG)
	}
	if first != want.FirstPeople || len(h.peoples)-first != len(want.People) {
		t.Fatal("new people counts differ")
	}
	for k, v := range want.People {
		e := h.peoples[first+k]
		if e.ID != v.ID || e.Name != v.Name || e.Parent != v.Parent || e.Parent2 != v.Parent2 || e.Alive != v.Alive || e.Stillborn != v.Stillborn {
			t.Fatalf("new people %d differs", e.ID)
		}
	}
	for k, i := range w.landList {
		actual := [9]float64{float64(h.eth[i]), float64(h.eth2[i]), float64(h.mix[i]), float64(h.mixTime[i]), float64(h.city[i]), float64(h.religion[i]), float64(h.exit[i]), float64(h.circE[i]), float64(h.plaguePool[i])}
		for j, v := range actual {
			if !near(v, want.Cells[k][j]) {
				t.Fatalf("cell %d field %d: %v / %v", i, j, v, want.Cells[k][j])
			}
		}
	}
	if len(h.cities) != len(want.Cities) || len(h.religions) != len(want.Religions) || len(h.figures) != len(want.Rulers) || len(h.routes) != want.Routes {
		t.Fatal("entity counts differ")
	}
	for k, c := range h.cities {
		if !reflect.DeepEqual(*c, want.Cities[k]) {
			t.Fatalf("city %d differs: %+v / %+v", k, c, want.Cities[k])
		}
	}
	for k, r := range h.religions {
		v := want.Religions[k]
		if r.ID != v.ID || r.Name != v.Name || r.Founder != v.Founder || r.Born != v.Born || r.Origin != v.Origin || r.Holy != v.Holy || r.Polity != v.Polity || r.People != v.People || r.Family != v.Family || r.Kind != v.Kind || r.Holder != v.Holder || r.RGB != v.RGB || r.Parent != v.Parent || r.Cells != v.Cells || r.Peak != v.Peak || r.Alive != v.Alive || r.Councils != v.Councils || r.Died != v.Died || !near(r.Population, v.Population) || !near(r.Missionary, v.Missionary) || !near(r.Centralization, v.Centralization) || !near(r.Lon, v.Lon) || !near(r.Lat, v.Lat) || !equalInts(r.Kids, v.Kids) || !equalInts(r.States, v.States) {
			t.Fatalf("religion %d differs: %+v / %+v", k, r, v)
		}
	}
	for k, f := range h.figures {
		v := want.Rulers[k]
		if f.Name != v.Name || f.Kind != v.Kind || f.Born != v.Born || f.Died != v.Died || f.Polity != v.Polity || f.People != v.People || f.Religion != v.Religion {
			t.Fatalf("figure %d differs", k)
		}
	}
}
func equalInts(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if v != b[k] {
			return false
		}
	}
	return true
}

func TestOriginalDesertCaravanContract(t *testing.T) {
	data, err := os.ReadFile("../../tests/native/society-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var want struct {
		Trade struct {
			RNG struct {
				Seed  uint32
				Calls uint64
			}
			Created     []TradeRoute
			Intensities []float32
			Remaining   int
		}
	}
	if err = json.Unmarshal(data, &want); err != nil {
		t.Fatal(err)
	}
	w := historyContractWorld(t)
	s, _ := NewSimulation(w, "1")
	h := s.h
	h.prepareAnnualState()
	h.year = 27
	for i := range w.land {
		w.land[i] = false
		w.coast[i] = false
	}
	w.landList = make([]CellID, w.config.Width)
	h.polities = append(h.polities, &Polity{ID: 1, Full: "West kingdom"}, &Polity{ID: 2, Full: "East kingdom"})
	for x := 0; x < w.config.Width; x++ {
		i := CellID((w.config.Height/2)*w.config.Width + x)
		w.landList[x] = i
		w.land[i] = true
		w.desert[i] = x >= 10 && x <= 20
		w.precipitation[i] = 800
		if w.desert[i] {
			w.precipitation[i] = 100
		}
		w.area[i] = 100
		h.pop[i] = 10000
		h.pol[i] = 1
		h.eth[i] = 0
		if x >= 16 {
			h.pol[i] = 2
			h.eth[i] = 1
		}
		h.tech[TechCamel][i] = 1
	}
	h.caravanPass()
	if len(h.routes) != len(want.Trade.Created) || len(h.routes) == 0 {
		t.Fatal("route creation differs")
	}
	for k, r := range h.routes {
		if !reflect.DeepEqual(*r, want.Trade.Created[k]) {
			t.Fatalf("route %d differs", k)
		}
	}
	for k, i := range w.landList {
		if h.caravan[i] != want.Trade.Intensities[k] {
			t.Fatalf("route intensity cell %d differs", i)
		}
	}
	h.year = 107
	clear(h.tech[TechCamel])
	h.caravanPass()
	p := h.r.Position()
	if p.Seed != want.Trade.RNG.Seed || p.Calls != want.Trade.RNG.Calls || len(h.routes) != want.Trade.Remaining {
		t.Fatal("route expiry or RNG differs")
	}
}
