package interop

import (
	"math"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func TestMapProjectionSuppressesOnlyUnchangedRecords(t *testing.T) {
	s := &Session{}
	before := s.projectMapState(sim.StateView{Year: -9000, Provinces: []sim.ProvinceView{
		{ID: 0, Population: 100, People: 2}, {ID: 1},
	}})
	delta := s.projectMapDelta(sim.AnnualDelta{FromYear: -9000, Year: -8999, Provinces: []sim.ProvinceView{
		{ID: 0, Population: 105, People: 2},
		{ID: 1, WeatherAnomaly: 1}, // Detailed change, identical map projection.
	}})
	if len(delta.Provinces) != 1 || delta.Provinces[0].ID != 0 || delta.Provinces[0].Population != 105 {
		t.Fatalf("unexpected projected delta: %+v", delta.Provinces)
	}
	if delta.Year != -8999 || delta.FromYear != -9000 || before.Provinces[0].Population != 100 {
		t.Fatal("annual boundary or previous publication was changed")
	}
	oldDelta := delta.Provinces[0]
	next := s.projectMapDelta(sim.AnnualDelta{FromYear: -8999, Year: -8998, Provinces: []sim.ProvinceView{{ID: 0, Population: 110, People: 2}}})
	if len(next.Provinces) != 1 || delta.Provinces[0] != oldDelta {
		t.Fatal("subsequent publication mutated the preceding delta")
	}
}

func TestMapProjectionFallbackAndExactFloatBits(t *testing.T) {
	s := &Session{}
	s.projectMapState(sim.StateView{Year: 1, Provinces: []sim.ProvinceView{{ID: 0}}})
	negativeZero := math.Float32frombits(1 << 31)
	delta := s.projectMapDelta(sim.AnnualDelta{FromYear: 1, Year: 2, Provinces: []sim.ProvinceView{{ID: 0, Fortification: negativeZero}}})
	if len(delta.Provinces) != 1 || math.Float32bits(delta.Provinces[0].Fortification) != 1<<31 {
		t.Fatal("signed zero was suppressed")
	}
	stale := s.projectMapDelta(sim.AnnualDelta{FromYear: 5, Year: 6, Provinces: []sim.ProvinceView{{ID: 0}}})
	if len(stale.Provinces) != 1 || s.mapCache != nil {
		t.Fatal("stale baseline did not retain the unfiltered delta")
	}
	missing := s.projectMapDelta(sim.AnnualDelta{FromYear: 6, Year: 7, Provinces: []sim.ProvinceView{{ID: 0}}})
	if len(missing.Provinces) != 1 {
		t.Fatal("a delta without a baseline was filtered")
	}
}
