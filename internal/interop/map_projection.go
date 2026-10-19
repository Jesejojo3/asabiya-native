package interop

import "github.com/Jesejojo3/asabiya-native/internal/sim"

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
