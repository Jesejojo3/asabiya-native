package sim

import (
	"encoding/json"
	"math"
	"reflect"
	"testing"
)

func TestMapPublicationReconstructsFullState(t *testing.T) {
	for _, seed := range []string{"map-publication", "Earth-like"} {
		t.Run(seed, func(t *testing.T) {
			w, err := GenerateWorld(smallConfig(seed))
			if err != nil {
				t.Fatal(err)
			}
			full, err := NewSimulation(w, "1")
			if err != nil {
				t.Fatal(err)
			}
			compact, err := NewSimulation(w, "1")
			if err != nil {
				t.Fatal(err)
			}
			initial := compact.MapSnapshot()
			initialJSON, err := json.Marshal(initial)
			if err != nil {
				t.Fatal(err)
			}
			rows := append([]MapProvinceView(nil), initial.Provinces...)
			for year := 0; year < 30; year++ {
				want := full.AdvanceYearWithDelta()
				got := compact.AdvanceYearWithMapDelta()
				if got.FromYear+1 != got.Year || got.FromYear != want.FromYear {
					t.Fatal("compact publication lost an annual boundary")
				}
				metadata := got.AnnualDelta
				metadata.Schema = want.Schema
				want.Provinces = nil
				if !reflect.DeepEqual(metadata, want) {
					t.Fatalf("annual metadata diverged in year %d", got.Year)
				}
				for _, p := range got.Provinces {
					rows[p.ID] = p
				}
				view := full.Snapshot()
				for i, p := range view.Provinces {
					projected := MapProvinceView{ID: p.ID, Owner: p.OwnerPolity,
						People: p.People, Religion: p.Religion, Population: p.Population,
						Capacity: p.Capacity, Fortification: p.Fortification, Era: p.Era}
					if !sameMapProvinceView(rows[i], projected) {
						t.Fatalf("province %d diverged in year %d", i, got.Year)
					}
				}
				if full.StateDigest() != compact.StateDigest() ||
					full.Status().HistoryRNG != compact.Status().HistoryRNG {
					t.Fatal("publication projection changed causal state or RNG")
				}
			}
			afterJSON, err := json.Marshal(initial)
			if err != nil || string(initialJSON) != string(afterJSON) {
				t.Fatal("later years mutated the initial map snapshot")
			}
			if !reflect.DeepEqual(full.Replay(), compact.Replay()) {
				t.Fatal("compact publication changed replay")
			}
			view := compact.MapSnapshot()
			before := compact.StateDigest()
			view.Provinces[0].Population = 999
			view.Rules.Values["growth"] = .03
			if compact.StateDigest() != before {
				t.Fatal("map publication exposes mutable causal state")
			}
		})
	}
}

func TestMapPublicationPreservesFloatBits(t *testing.T) {
	negativeZero := math.Float32frombits(1 << 31)
	for _, pair := range [][2]MapProvinceView{
		{{Population: 0}, {Population: negativeZero}},
		{{Capacity: 0}, {Capacity: negativeZero}},
		{{Fortification: 0}, {Fortification: negativeZero}},
	} {
		if sameMapProvinceView(pair[0], pair[1]) {
			t.Fatal("compact map comparison suppressed signed zero")
		}
	}
}
