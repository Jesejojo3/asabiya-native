package sim

import (
	"github.com/Jesejojo3/asabiya-native/internal/rng"
	"slices"
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
	s.mu.Lock()
	defer s.mu.Unlock()
	h := s.h
	before := make([]ProvinceView, s.world.Len())
	for i := range before {
		before[i] = s.provinceLocked(CellID(i))
	}
	alive := make([]bool, len(h.polities))
	for k, o := range h.polities {
		alive[k] = o != nil && o.Alive
	}
	eventStart := h.nextEventID
	from := h.year
	s.applyCommandLocked(s.nextCommandLocked("advance_year"))
	delta := AnnualDelta{Schema: "asabiya/annual-delta-v1", FromYear: from, Year: h.year, StateSHA256: s.stateDigestLocked(), RulesSHA256: s.rulesDigestLocked(), EntityUpserts: make(map[string][]EntityRecord), Favor: h.favor}
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
	for i, p := range before {
		current := s.provinceLocked(CellID(i))
		if p != current {
			delta.Provinces = append(delta.Provinces, current)
		}
	}
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
	return delta
}
