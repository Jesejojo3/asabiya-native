package sim

import "math"

// MapProvinceView is the compact, engine-owned projection used by map consumers.
// Detailed province queries and the full annual publication remain available.
type MapProvinceView struct {
	ID            CellID  `json:"id"`
	Owner         int     `json:"ownerPolityId"`
	People        int     `json:"peopleId"`
	Religion      int     `json:"religionId"`
	Population    float32 `json:"population"`
	Capacity      float32 `json:"carryingCapacity"`
	Fortification float32 `json:"fortification"`
	Era           int     `json:"era"`
}

type MapStateView struct {
	StateView
	Provinces []MapProvinceView `json:"provinces"`
}

type MapAnnualDelta struct {
	AnnualDelta
	Provinces []MapProvinceView `json:"provinces"`
}

func (s *Simulation) mapProvinceLocked(i CellID) MapProvinceView {
	h := s.h
	return MapProvinceView{
		ID: i, Owner: int(h.pol[i]), People: int(h.eth[i]),
		Religion: int(h.religion[i]), Population: h.pop[i], Capacity: h.K[i],
		Fortification: h.fort[i], Era: h.eraOf(int(i)),
	}
}

func (s *Simulation) mapProvincesLocked() []MapProvinceView {
	out := make([]MapProvinceView, s.world.Len())
	for i := range out {
		out[i] = s.mapProvinceLocked(CellID(i))
	}
	return out
}

// MapSnapshot captures the same state boundary as Snapshot under a single lock.
// It never constructs the detailed provincial records (including technologies).
func (s *Simulation) MapSnapshot() MapStateView {
	s.mu.RLock()
	defer s.mu.RUnlock()
	view := s.snapshotMetadataLocked()
	view.Schema = "asabiya/map-state-v1"
	return MapStateView{StateView: view, Provinces: s.mapProvincesLocked()}
}

// AdvanceYearWithMapDelta executes the same atomic year and command path as the
// full delta. Only the publication projection differs; no render code or clock
// enters the engine. Both returned data and the comparison baseline are owned
// values, so later years cannot mutate previously published records.
func (s *Simulation) AdvanceYearWithMapDelta() MapAnnualDelta {
	delta, provinces := s.advanceYearWithDelta(true, 1)
	delta.Schema = "asabiya/map-delta-v1"
	return MapAnnualDelta{AnnualDelta: delta, Provinces: provinces}
}

// AdvanceYearWithMapDeltaCheckpoints preserves every causal year and all map,
 // event and entity records, but computes the expensive full state SHA only on
 // scheduled years. Other years carry a declared deferred digest marker.
 // Call MapSnapshot or StateDigest to obtain the exact SHA at any year.
func (s *Simulation) AdvanceYearWithMapDeltaCheckpoints(interval int) MapAnnualDelta {
	if interval != 25 { panic("unsupported digest checkpoint interval") }
	delta, provinces := s.advanceYearWithDelta(true, interval)
	delta.Schema = "asabiya/map-delta-v1"
	return MapAnnualDelta{AnnualDelta: delta, Provinces: provinces}
}

func sameMapProvinceView(a, b MapProvinceView) bool {
	return a.ID == b.ID && a.Owner == b.Owner && a.People == b.People &&
		a.Religion == b.Religion && a.Era == b.Era &&
		math.Float32bits(a.Population) == math.Float32bits(b.Population) &&
		math.Float32bits(a.Capacity) == math.Float32bits(b.Capacity) &&
		math.Float32bits(a.Fortification) == math.Float32bits(b.Fortification)
}
