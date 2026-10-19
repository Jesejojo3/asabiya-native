package sim

import "slices"

type HistoricalLayerView struct {
	Year         int      `json:"year"`
	ProvinceIDs  []CellID `json:"provinceIds"`
	PeopleIDs    []int32  `json:"peopleIds"`
	ReligionIDs  []int16  `json:"religionIds"`
	DensityLog   []int    `json:"densityLog"`
	CohesionByte []int    `json:"cohesionByte"`
	Era          []int    `json:"era"`
}

func (s *Simulation) HistoricalLayer(year int) (HistoricalLayerView, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if year < s.h.start || year > s.h.year {
		return HistoricalLayerView{}, false
	}
	l := s.h.layerAt(year)
	if l == nil {
		return HistoricalLayerView{}, false
	}
	out := HistoricalLayerView{Year: l.Year, ProvinceIDs: slices.Clone(s.world.landList), PeopleIDs: make([]int32, len(l.People)), ReligionIDs: slices.Clone(l.Religion), DensityLog: make([]int, len(l.Density)), CohesionByte: make([]int, len(l.Cohesion)), Era: make([]int, len(l.Era))}
	for k := range l.People {
		out.PeopleIDs[k] = l.People[k] - 1
		out.DensityLog[k] = int(l.Density[k])
		out.CohesionByte[k] = int(l.Cohesion[k])
		out.Era[k] = int(l.Era[k])
	}
	return out, true
}
