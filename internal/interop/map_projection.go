package interop

import (
	"math"
	"slices"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

// A renderer publication omits detailed epidemiology and the 32 technique
// values per cell. Those remain queryable through get_province. This is one
// optional view on the existing local protocol, never a second simulation.
type mapProvince struct {
	ID            sim.CellID `json:"id"`
	Owner         int        `json:"ownerPolityId"`
	People        int        `json:"peopleId"`
	Religion      int        `json:"religionId"`
	Population    float32    `json:"population"`
	Capacity      float32    `json:"carryingCapacity"`
	Fortification float32    `json:"fortification"`
	Era           int        `json:"era"`
}

func projectProvinces(provinces []sim.ProvinceView) []mapProvince {
	out := make([]mapProvince, len(provinces))
	for k, p := range provinces {
		out[k] = mapProvince{ID: p.ID, Owner: p.OwnerPolity, People: p.People, Religion: p.Religion, Population: p.Population, Capacity: p.Capacity, Fortification: p.Fortification, Era: p.Era}
	}
	return out
}

type mapState struct {
	sim.StateView
	Provinces []mapProvince `json:"provinces"`
}
type mapDelta struct {
	sim.AnnualDelta
	Provinces []mapProvince `json:"provinces"`
}

func projectState(view sim.StateView) mapState {
	p := projectProvinces(view.Provinces)
	view.Provinces = nil
	view.Schema = "asabiya/map-state-v1"
	return mapState{StateView: view, Provinces: p}
}
func projectDelta(view sim.AnnualDelta) mapDelta {
	p := projectProvinces(view.Provinces)
	view.Provinces = nil
	view.Schema = "asabiya/map-delta-v1"
	return mapDelta{AnnualDelta: view, Provinces: p}
}

// Keep a private baseline for the map fields, not for the simulation. A change
// in detailed weather/technology need not resend an identical map record.
// Session.Handle holds the session lock. No returned publication is mutated.
func (s *Session) projectMapState(view sim.StateView) mapState {
	state := projectState(view)
	s.mapCache = slices.Clone(state.Provinces)
	s.mapCacheYear = state.Year
	return state
}

func sameMapProvince(a, b mapProvince) bool {
	return a.ID == b.ID && a.Owner == b.Owner && a.People == b.People && a.Religion == b.Religion && a.Era == b.Era &&
		math.Float32bits(a.Population) == math.Float32bits(b.Population) &&
		math.Float32bits(a.Capacity) == math.Float32bits(b.Capacity) &&
		math.Float32bits(a.Fortification) == math.Float32bits(b.Fortification)
}

func (s *Session) projectMapDelta(view sim.AnnualDelta) mapDelta {
	delta := projectDelta(view)
	if len(s.mapCache) == 0 || s.mapCacheYear != delta.FromYear {
		s.mapCache = nil
		return delta
	}
	for _, p := range delta.Provinces {
		if int(p.ID) < 0 || int(p.ID) >= len(s.mapCache) {
			s.mapCache = nil
			return delta
		}
	}
	changed := delta.Provinces[:0]
	for _, p := range delta.Provinces {
		if !sameMapProvince(p, s.mapCache[p.ID]) {
			changed = append(changed, p)
		}
		s.mapCache[p.ID] = p
	}
	delta.Provinces = changed
	s.mapCacheYear = delta.Year
	return delta
}
