package interop

import (
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"math"
)

// Field patches are opt-in. Each field has its own ordered CellID list and
// replacement values; absence means unchanged, never zero or deletion.
type fieldPatch[T int | float32] struct {
	IDs    []sim.CellID `json:"id"`
	Values []T          `json:"values"`
}
type mapFields struct {
	Owner         *fieldPatch[int]     `json:"ownerPolityId,omitempty"`
	People        *fieldPatch[int]     `json:"peopleId,omitempty"`
	Religion      *fieldPatch[int]     `json:"religionId,omitempty"`
	Population    *fieldPatch[float32] `json:"population,omitempty"`
	Capacity      *fieldPatch[float32] `json:"carryingCapacity,omitempty"`
	Fortification *fieldPatch[float32] `json:"fortification,omitempty"`
	Era           *fieldPatch[int]     `json:"era,omitempty"`
}
type fieldDelta struct {
	sim.AnnualDelta
	Provinces       mapFields `json:"provinces"`
	WorldPopulation float64   `json:"worldPopulation"`
}

func newField[T int | float32](count int) *fieldPatch[T] {
	if count == 0 {
		return nil
	}
	return &fieldPatch[T]{IDs: make([]sim.CellID, 0, count), Values: make([]T, 0, count)}
}
func addField[T int | float32](patch **fieldPatch[T], id sim.CellID, value T) {
	(*patch).IDs = append((*patch).IDs, id)
	(*patch).Values = append((*patch).Values, value)
}

func (s *Session) packFieldDelta(delta mapDelta) any {
	// A missed baseline must send complete changed rows. This also handles
	// status-only advances, commands, restarts and switching from legacy views.
	if len(s.mapCache) == 0 || s.mapCacheYear != delta.FromYear {
		return packDelta(s.filterMapDelta(delta))
	}
	for _, p := range delta.Provinces {
		if int(p.ID) < 0 || int(p.ID) >= len(s.mapCache) {
			s.mapCache = nil
			return packDelta(delta)
		}
	}
	// Count first to allocate each changed column exactly once. Large population
	// columns otherwise repeatedly grow and copy their backing arrays.
	var counts [7]int
	for _, p := range delta.Provinces {
		old := s.mapCache[p.ID]
		if p.Owner != old.Owner {
			counts[0]++
		}
		if p.People != old.People {
			counts[1]++
		}
		if p.Religion != old.Religion {
			counts[2]++
		}
		if math.Float32bits(p.Population) != math.Float32bits(old.Population) {
			counts[3]++
		}
		if math.Float32bits(p.Capacity) != math.Float32bits(old.Capacity) {
			counts[4]++
		}
		if math.Float32bits(p.Fortification) != math.Float32bits(old.Fortification) {
			counts[5]++
		}
		if p.Era != old.Era {
			counts[6]++
		}
	}
	fields := mapFields{newField[int](counts[0]), newField[int](counts[1]), newField[int](counts[2]), newField[float32](counts[3]), newField[float32](counts[4]), newField[float32](counts[5]), newField[int](counts[6])}
	for _, p := range delta.Provinces {
		old := s.mapCache[p.ID]
		if p.Owner != old.Owner {
			addField(&fields.Owner, p.ID, p.Owner)
		}
		if p.People != old.People {
			addField(&fields.People, p.ID, p.People)
		}
		if p.Religion != old.Religion {
			addField(&fields.Religion, p.ID, p.Religion)
		}
		if math.Float32bits(p.Population) != math.Float32bits(old.Population) {
			addField(&fields.Population, p.ID, p.Population)
		}
		if math.Float32bits(p.Capacity) != math.Float32bits(old.Capacity) {
			addField(&fields.Capacity, p.ID, p.Capacity)
		}
		if math.Float32bits(p.Fortification) != math.Float32bits(old.Fortification) {
			addField(&fields.Fortification, p.ID, p.Fortification)
		}
		if p.Era != old.Era {
			addField(&fields.Era, p.ID, p.Era)
		}
		s.mapCache[p.ID] = p
	}
	s.mapCacheYear = delta.Year
	delta.Schema = "asabiya/map-fields-delta-v1"
	// Match the client's original float64 reduction in ascending CellID order.
	// This is a presentation aggregate, not a cached or causal quantity.
	var population float64
	for _, p := range s.mapCache {
		population += float64(p.Population)
	}
	return fieldDelta{AnnualDelta: delta.AnnualDelta, Provinces: fields, WorldPopulation: population}
}
