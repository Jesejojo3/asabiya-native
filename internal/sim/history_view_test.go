package sim

import (
	"slices"
	"testing"
)

func TestSummaryCopiesEraShares(t *testing.T) {
	w, err := GenerateWorld(smallConfig("summary-copy"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	// Exercise every record, not only the initial record produced by newHistory.
	s.h.recordStats()
	first, second := s.Summary(), s.Summary()
	position := s.Status().HistoryRNG
	for i := range first.Stats {
		want := slices.Clone(s.h.stats[i].EraShare)
		if len(want) == 0 {
			t.Fatal("expected nonempty era shares")
		}
		first.Stats[i].EraShare[0] += 42
		if !slices.Equal(s.h.stats[i].EraShare, want) {
			t.Fatalf("summary mutation changed historical era shares in record %d", i)
		}
		if !slices.Equal(second.Stats[i].EraShare, want) {
			t.Fatalf("two summary queries share era storage in record %d", i)
		}
		if !slices.Equal(s.Summary().Stats[i].EraShare, want) {
			t.Fatalf("later summary changed in record %d", i)
		}
	}
	if s.Status().HistoryRNG != position {
		t.Fatal("summary queries consumed historical RNG")
	}
}

func TestDigestIncludesRuleOptions(t *testing.T) {
	w, err := GenerateWorld(smallConfig("digest-options"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	baseline := s.Digest()
	position := s.Status().HistoryRNG
	seen := make(map[string]uint8)
	for mask := uint8(0); mask < 4; mask++ {
		// Hold all historical data fixed to test configuration identity itself,
		// even when an option has no causal effect on a procedural initial world.
		s.h.rules.ShuffleNames = mask&1 != 0
		s.h.rules.Sandbox = mask&2 != 0
		digest := s.Digest()
		if previous, exists := seen[digest]; exists {
			t.Fatalf("option masks %d and %d have the same digest", previous, mask)
		}
		seen[digest] = mask
		if s.Digest() != digest {
			t.Fatalf("option mask %d is not reproducible", mask)
		}
	}
	s.h.rules.ShuffleNames, s.h.rules.Sandbox = false, false
	if s.Digest() != baseline || s.Status().HistoryRNG != position {
		t.Fatal("hashing options changed the default fingerprint or consumed RNG")
	}
}
