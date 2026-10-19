package sim

// orderedMap models ECMAScript Map: insertion order, live growth, deletion and
// reinsertion at the end. Slots are never compacted while a traversal is live.
// The lookup map is never ranged over for a causal decision.
type orderedEntry[K comparable, V any] struct {
	key   K
	value V
	alive bool
}
type orderedMap[K comparable, V any] struct {
	entries []*orderedEntry[K, V]
	lookup  map[K]*orderedEntry[K, V]
}

func (m *orderedMap[K, V]) Get(k K) (V, bool) {
	if e := m.lookup[k]; e != nil && e.alive {
		return e.value, true
	}
	var zero V
	return zero, false
}
func (m *orderedMap[K, V]) Value(k K) V  { v, _ := m.Get(k); return v }
func (m *orderedMap[K, V]) Has(k K) bool { _, ok := m.Get(k); return ok }
func (m *orderedMap[K, V]) Set(k K, v V) {
	if m.lookup == nil {
		m.lookup = make(map[K]*orderedEntry[K, V])
	}
	if e := m.lookup[k]; e != nil && e.alive {
		e.value = v
		return
	}
	e := &orderedEntry[K, V]{key: k, value: v, alive: true}
	m.entries = append(m.entries, e)
	m.lookup[k] = e
}
func (m *orderedMap[K, V]) Delete(k K) {
	if e := m.lookup[k]; e != nil {
		e.alive = false
		delete(m.lookup, k)
	}
}
func (m *orderedMap[K, V]) Len() int { return len(m.lookup) }
func (m *orderedMap[K, V]) Each(f func(K, V)) {
	for i := 0; i < len(m.entries); i++ {
		e := m.entries[i]
		if e.alive {
			f(e.key, e.value)
		}
	}
}

type orderedSet[K comparable] struct{ values orderedMap[K, struct{}] }

func (s *orderedSet[K]) Add(k K)      { s.values.Set(k, struct{}{}) }
func (s *orderedSet[K]) Has(k K) bool { return s.values.Has(k) }
func (s *orderedSet[K]) Delete(k K)   { s.values.Delete(k) }
func (s *orderedSet[K]) Len() int     { return s.values.Len() }
func (s *orderedSet[K]) Keys() []K {
	out := make([]K, 0, s.Len())
	s.values.Each(func(k K, _ struct{}) { out = append(out, k) })
	return out
}
