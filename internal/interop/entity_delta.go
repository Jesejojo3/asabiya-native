package interop

import (
	"math"
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
			if !seen || !sameEntityValue(reflect.ValueOf(old.Fields), reflect.ValueOf(record.Fields)) {
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

// DeepEqual treats +0 and -0 as equal, although JSON and the causal digest
// distinguish them. Compare the owned JSON projection recursively by float bits.
// Unsupported future kinds conservatively resend the record.
func sameEntityValue(a, b reflect.Value) bool {
	if !a.IsValid() || !b.IsValid() {
		return a.IsValid() == b.IsValid()
	}
	if a.Type() != b.Type() {
		return false
	}
	switch a.Kind() {
	case reflect.Float32:
		return math.Float32bits(float32(a.Float())) == math.Float32bits(float32(b.Float()))
	case reflect.Float64:
		return math.Float64bits(a.Float()) == math.Float64bits(b.Float())
	case reflect.Bool:
		return a.Bool() == b.Bool()
	case reflect.String:
		return a.String() == b.String()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return a.Int() == b.Int()
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return a.Uint() == b.Uint()
	case reflect.Interface, reflect.Pointer:
		if a.IsNil() || b.IsNil() {
			return a.IsNil() == b.IsNil()
		}
		return sameEntityValue(a.Elem(), b.Elem())
	case reflect.Map:
		if a.IsNil() != b.IsNil() || a.Len() != b.Len() {
			return false
		}
		it := a.MapRange()
		for it.Next() {
			other := b.MapIndex(it.Key())
			if !other.IsValid() || !sameEntityValue(it.Value(), other) {
				return false
			}
		}
		return true
	case reflect.Slice, reflect.Array:
		if a.Kind() == reflect.Slice && a.IsNil() != b.IsNil() {
			return false
		}
		if a.Len() != b.Len() {
			return false
		}
		for i := 0; i < a.Len(); i++ {
			if !sameEntityValue(a.Index(i), b.Index(i)) {
				return false
			}
		}
		return true
	case reflect.Struct:
		for i := 0; i < a.NumField(); i++ {
			if !sameEntityValue(a.Field(i), b.Field(i)) {
				return false
			}
		}
		return true
	default:
		return false
	}
}
