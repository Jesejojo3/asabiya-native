package sim

import (
	"slices"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

type AnnualDelta struct {
	Earth                *EarthHistory             `json:"earth,omitempty"`
	RNG                  rng.Position              `json:"rng"`
	Rules                Rules                     `json:"rules"`
	Stats                []StatsEntry              `json:"stats"`
	FirstRetainedEventID int                       `json:"firstRetainedEventId"`
	Schema               string                    `json:"schema"`
	FromYear             int                       `json:"fromYear"`
	Year                 int                       `json:"year"`
	StateSHA256          string                    `json:"stateSHA256"`
	DigestMode           string                    `json:"digestMode,omitempty"`
	RulesSHA256          string                    `json:"rulesSHA256"`
	Provinces            []ProvinceView            `json:"provinces"`
	EntityUpserts        map[string][]EntityRecord `json:"entityUpserts"`
	CreatedPolities      []int                     `json:"createdPolityIds"`
	DeadPolities         []int                     `json:"deadPolityIds"`
	Events               []Event                   `json:"events"`
	Narrative            []EventText               `json:"narrative"`
	Favor                float64                   `json:"favor"`
}

// AdvanceYearWithDelta returns replacement records only for changed provinces.
// Entity upserts include the current entity records (not just births), so clients
// can apply them by stable ID without understanding the engine's internal census.
func (s *Simulation) AdvanceYearWithDelta() AnnualDelta {
	delta, _ := s.advanceYearWithDelta(false, 1)
	return delta
}

func (s *Simulation) advanceYearWithDelta(mapOnly bool, digestEvery int) (AnnualDelta, []MapProvinceView) {
	s.mu.Lock()
	defer s.mu.Unlock()
	h := s.h
	clock := startWork(s.workProfile)
	var before []ProvinceView
	var mapBefore []MapProvinceView
	if mapOnly {
		// Capture every province again, including sea cells. Reuse only storage:
		// no assumption about which commands or systems may change a field.
		if len(s.mapBefore) != s.world.Len() {
			s.mapBefore = make([]MapProvinceView, s.world.Len())
		}
		mapBefore = s.mapBefore
		for i := range mapBefore {
			mapBefore[i] = s.mapProvinceLocked(CellID(i))
		}
	} else {
		before = make([]ProvinceView, s.world.Len())
		for i := range before {
			before[i] = s.provinceLocked(CellID(i))
		}
	}
	alive := make([]bool, len(h.polities))
	for k, o := range h.polities {
		alive[k] = o != nil && o.Alive
	}
	eventStart := h.nextEventID
	from := h.year
	clock.mark(9)
	s.applyCommandLocked(s.nextCommandLocked("advance_year"))
	clock = startWork(s.workProfile)
	delta := AnnualDelta{Schema: "asabiya/annual-delta-v1", FromYear: from, Year: h.year, RulesSHA256: s.rulesDigestLocked(), EntityUpserts: make(map[string][]EntityRecord), Favor: h.favor}
	// Digest checkpoints are a strictly opt-in presentation mode.
	// All complete years and replay records are still produced.
	if digestEvery <= 1 || (h.year-h.start)%digestEvery == 0 {
		delta.StateSHA256 = s.stateDigestLocked()
	} else {
		delta.DigestMode = "deferred-v1"
	}
	delta.Earth = h.earthView()
	delta.RNG = h.r.Position()
	delta.Rules = h.rules.clone()
	delta.Stats = slices.Clone(h.stats)
	for k := range delta.Stats {
		delta.Stats[k].EraShare = slices.Clone(h.stats[k].EraShare)
	}
	if len(h.events) > 0 {
		delta.FirstRetainedEventID = h.events[0].ID
	}
	clock = startWork(s.workProfile)
	var mapChanges []MapProvinceView
	for i, p := range mapBefore {
		current := s.mapProvinceLocked(CellID(i))
		if !sameMapProvinceView(p, current) {
			if mapChanges == nil {
				mapChanges = make([]MapProvinceView, 0, len(s.world.landList))
			}
			mapChanges = append(mapChanges, current)
		}
	}
	for i, p := range before {
		current := s.provinceLocked(CellID(i))
		if p != current {
			delta.Provinces = append(delta.Provinces, current)
		}
	}
	clock.mark(11)
	for _, kind := range entityKinds {
		delta.EntityUpserts[kind] = s.entitiesLocked(kind)
	}
	for k, o := range h.polities {
		if o == nil {
			continue
		}
		if k >= len(alive) {
			delta.CreatedPolities = append(delta.CreatedPolities, k)
		} else if alive[k] && !o.Alive {
			delta.DeadPolities = append(delta.DeadPolities, k)
		}
	}
	for k, e := range h.events {
		if e.ID >= eventStart {
			copy := e
			copy.Entities = slices.Clone(e.Entities)
			delta.Events = append(delta.Events, copy)
			delta.Narrative = append(delta.Narrative, h.eventText[k])
		}
	}
	clock.mark(12)
	return delta, mapChanges
}
