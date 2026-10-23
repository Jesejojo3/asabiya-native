package sim

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
)

func TestOriginalDemographyTechnologyDiseaseContract(t *testing.T) {
	b, err := os.ReadFile("../../tests/native/demography-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Snapshots []struct {
			Phase string
			RNG   struct {
				Seed  uint32
				Calls uint64
			}
			Sums       []float64
			Samples    [][]float64
			Identities [][6]int
			Infections []CellID
			Outbreaks  []struct {
				ID                      int
				Name                    string
				Origin                  CellID
				Year, End               int
				Deaths, Virulence, Pool float64
				Cells, Active           int
				Done, Virgin            bool
				From                    int
				Spread                  [][2]int
				Hit                     []int
			}
			Migrations int
		}
	}
	if err = json.Unmarshal(b, &fixture); err != nil {
		t.Fatal(err)
	}
	w := historyContractWorld(t)
	for i := range w.roughness {
		w.roughness[i] = .4
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	h := s.h
	h.prepareAnnualState()
	h.year = -8995
	h.religions = append(h.religions, &Religion{ID: 0, Name: "Contract religion", Kind: "universal", Family: 0, Missionary: .7, Centralization: .6})
	for k := range h.firstDiscoveries {
		h.firstDiscoveries[k] = &Discovery{Year: h.year, Cell: w.landList[0], People: 0}
	}
	for k, i := range w.landList {
		multiplier := .9
		if k%3 == 0 {
			multiplier = 1.8
		}
		h.pop[i] = float32(math.Max(100, float64(h.K[i])) * multiplier)
		if k%5 == 0 {
			h.pop[i] = 0
		}
		h.eth[i] = int32(k % len(h.peoples))
		h.religion[i] = -1
		if k%3 == 0 {
			h.religion[i] = 0
		}
		h.immunity[i] = float32(float64(k%5) * .12)
		h.plaguePool[i] = float32(float64(k%7) * .1)
		h.forest[i] = float32(float64(w.forest[i]) * .1)
		h.rp[i] = .25
		for j := range h.tech {
			h.tech[j][i] = float32(float64((k+j)%7) / 6)
		}
	}
	origin := NoCell
	for _, i := range w.landList {
		if h.pop[i] > 0 {
			origin = i
			break
		}
	}
	h.infection[origin] = 3
	h.outbreakAt[origin] = 0
	h.infections = append(h.infections, origin)
	h.outbreaks = append(h.outbreaks, &Outbreak{ID: 0, Name: "Contract fever", Origin: origin, Year: h.year - 1, Virulence: .23, Pool: .7, Cells: 1, Active: 1, Spread: [][2]int{{0, int(origin)}}, Virgin: true})
	steps := []func(){h.growth, h.migrate, h.seaHop, func() { h.techStep(0, .34); h.techStep(.34, .67); h.techStep(.67, 1) }, func() {
		for j := 0; j < 5; j++ {
			h.disease()
			h.year++
		}
	}}
	for index, step := range steps {
		step()
		want := fixture.Snapshots[index]
		p := h.r.Position()
		if p.Seed != want.RNG.Seed || p.Calls != want.RNG.Calls {
			t.Fatalf("%s RNG Go=%+v JS=%+v", want.Phase, p, want.RNG)
		}
		fields := [][]float32{h.pop, h.fert, h.forest, h.salt, h.adapt, h.rp, h.mix, h.immunity, h.plaguePool}
		fields = append(fields, h.tech[:]...)
		for k, a := range fields {
			sum := 0.
			for _, i := range w.landList {
				sum += float64(a[i])
			}
			if !near(sum, want.Sums[k]) {
				t.Fatalf("%s sum field %d: %.17g / %.17g", want.Phase, k, sum, want.Sums[k])
			}
		}
		for _, sample := range want.Samples {
			i := int(sample[0])
			for k, a := range fields {
				if !near(float64(a[i]), sample[k+1]) {
					t.Fatalf("%s cell %d field %d: %.17g / %.17g", want.Phase, i, k, a[i], sample[k+1])
				}
			}
		}
		for k, i := range w.landList {
			actual := [6]int{int(h.eth[i]), int(h.eth2[i]), int(h.religion[i]), int(h.mixTime[i]), int(h.infection[i]), int(h.outbreakAt[i])}
			if actual != want.Identities[k] {
				t.Fatalf("%s identities cell %d: %v / %v", want.Phase, i, actual, want.Identities[k])
			}
		}
		if !reflect.DeepEqual(h.infections, want.Infections) {
			t.Fatalf("%s infection order differs", want.Phase)
		}
		if len(h.outbreaks) != len(want.Outbreaks) || len(h.migrations) != want.Migrations {
			t.Fatalf("%s entity counts differ", want.Phase)
		}
		for k, o := range h.outbreaks {
			v := want.Outbreaks[k]
			if o.ID != v.ID || o.Name != v.Name || o.Origin != v.Origin || o.Year != v.Year || o.End != v.End || o.Cells != v.Cells || o.Active != v.Active || o.Done != v.Done || o.Virgin != v.Virgin || o.From != v.From || !near(o.Deaths, v.Deaths) || !near(o.Virulence, v.Virulence) || !near(o.Pool, v.Pool) || !reflect.DeepEqual(o.Spread, v.Spread) || !reflect.DeepEqual(o.Hit.Keys(), v.Hit) {
				t.Fatalf("%s outbreak %d differs: %+v / %+v", want.Phase, k, o, v)
			}
		}
	}
}

func TestLiveOrderedCollections(t *testing.T) {
	var m orderedMap[int, int]
	m.Set(1, 10)
	m.Set(2, 20)
	m.Set(3, 30)
	var visited [][2]int
	m.Each(func(k, v int) {
		visited = append(visited, [2]int{k, v})
		if k == 1 {
			m.Delete(2)
			m.Set(2, 21)
			m.Set(3, 31)
			m.Set(99, 990)
		}
	})
	want := [][2]int{{1, 10}, {3, 31}, {2, 21}, {99, 990}}
	if !reflect.DeepEqual(visited, want) || m.Len() != 4 {
		t.Fatalf("live Map order %v, want %v", visited, want)
	}
	if jsPairKey(9, 10) != "10:9" {
		t.Fatal("legacy lexical pair key changed")
	}
}
