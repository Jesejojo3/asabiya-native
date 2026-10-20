package interop

import (
	"reflect"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

// Only the explicitly negotiated entityMode=changed may use this cache.
// The legacy map and map-columns-v1 payloads remain complete by default.
// EntityRecord values returned by the simulation own their nested fields.
func (s *Session) cacheEntityState(year int, entities map[string][]sim.EntityRecord) {
	byKind := make(map[string]map[int]sim.EntityRecord, len(entities))
	for kind, records := range entities {
		current := make(map[int]sim.EntityRecord, len(records))
		for _, record := range records {
			current[record.ID] = record
		}
		byKind[kind] = current
	}
	s.entityCache = byKind
	s.entityCacheYear = year
}

// Suppress only byte-equivalent logical records between consecutive complete
// years. A stale/missing baseline falls back to FULL records instead of
// attempting a delta that might corrupt the receiving client's entity cache.
// No historical state, RNG, digest, replay, or province content is modified.
func (s *Session) filterEntityChanges(delta *mapDelta) {
	if s.entityCache == nil || s.entityCacheYear != delta.FromYear {
		s.cacheEntityState(delta.Year, delta.EntityUpserts)
		return
	}
	for kind, records := range delta.EntityUpserts {
		baseline := s.entityCache[kind]
		if baseline == nil {
			baseline = make(map[int]sim.EntityRecord, len(records))
			s.entityCache[kind] = baseline
		}
		var changed []sim.EntityRecord
		for _, record := range records {
			old, seen := baseline[record.ID]
			if !seen || !reflect.DeepEqual(old.Fields, record.Fields) {
				changed = append(changed, record)
			}
			baseline[record.ID] = record
		}
		if len(changed) == 0 {
			delete(delta.EntityUpserts, kind)
		} else {
			delta.EntityUpserts[kind] = changed
		}
	}
	s.entityCacheYear = delta.Year
}
