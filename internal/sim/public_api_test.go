package sim

import (
	"encoding/json"
	"math"
	"reflect"
	"sync"
	"testing"
)

func TestFullDigestAndCommandReplay(t *testing.T) {
	w, err := GenerateWorld(smallConfig("public-replay"))
	if err != nil {
		t.Fatal(err)
	}
	a, _ := NewSimulation(w, "1")
	b, _ := NewSimulation(w, "1")
	initial := a.InitialSummary()
	if a.Digest() != initial.SHA256 {
		t.Fatal("initial compatibility projection changed")
	}
	if a.StateDigest() != b.StateDigest() {
		t.Fatal("initial full states differ")
	}
	cell := w.landList[0]
	command := func(kind string) Command {
		return Command{Schema: CommandSchema, Profile: NativeProfile, Sequence: a.NextSequence(), TargetYear: a.Status().Year, Kind: kind}
	}
	enabled := true
	c := command("set_sandbox")
	c.Sandbox = &enabled
	if !a.ApplyCommand(c).Accepted {
		t.Fatal("sandbox rejected")
	}
	c = command("cast_omen")
	c.Omen = "kindle"
	c.Cell = cell
	if !a.ApplyCommand(c).Accepted {
		t.Fatal("omen rejected")
	}
	c = command("change_rules")
	c.Values = map[string]float64{"growth": .02}
	c.ExpectedRulesSHA256 = a.RulesDigest()
	if !a.ApplyCommand(c).Accepted {
		t.Fatal("rules rejected")
	}
	c.Values["growth"] = .03
	for n := 0; n < 12; n++ {
		a.AdvanceYear()
	}
	before, position, sequence := a.StateDigest(), a.Status().HistoryRNG, a.NextSequence()
	c = command("change_rules")
	c.Values = map[string]float64{"growth": .015, "bands": 24}
	if a.ApplyCommand(c).Accepted {
		t.Fatal("retroactive initialization change accepted")
	}
	c = command("change_rules")
	c.ExpectedRulesSHA256 = "stale"
	if a.ApplyCommand(c).Accepted {
		t.Fatal("stale rules accepted")
	}
	c = command("advance_year")
	c.TargetYear--
	if a.ApplyCommand(c).Accepted {
		t.Fatal("past boundary accepted")
	}
	if a.StateDigest() != before || a.Status().HistoryRNG != position || a.NextSequence() != sequence || a.Rules().Values["growth"] != .02 {
		t.Fatal("rejected command changed state, rules, sequence or RNG")
	}
	replay := a.Replay()
	for _, record := range replay.Commands {
		result := b.ApplyCommand(record.Command)
		if result.Accepted != record.Accepted || result.Error != record.Error || result.RNGAfter != record.RNGAfter {
			t.Fatalf("replay diverged at sequence %d", record.Command.Sequence)
		}
	}
	if a.StateDigest() != b.StateDigest() {
		t.Fatal("replay did not reconstruct the complete state")
	}
	if a.InitialSummary().SHA256 != initial.SHA256 {
		t.Fatal("initial projection was not retained")
	}
	replay.InitialRules.Values["growth"] = .03
	replay.Commands[2].Command.Values["growth"] = .03
	if a.Replay().InitialRules.Values["growth"] != .012 || a.Replay().Commands[2].Command.Values["growth"] != .02 {
		t.Fatal("replay exposes mutable internal maps")
	}
	// Arrays omitted by the old initialization digest now affect the full hash.
	baseline := a.StateDigest()
	a.h.bfsParent[cell]++
	if a.StateDigest() == baseline {
		t.Fatal("causal BFS scratch missing from full digest")
	}
	a.h.bfsParent[cell]--
	if a.StateDigest() != baseline {
		t.Fatal("digest is not reproducible")
	}
	a.h.withinStamp++
	if a.StateDigest() != baseline {
		t.Fatal("query marker bookkeeping leaked into causal hash")
	}
}

func TestImmutableSnapshotAndDeltaReconstruction(t *testing.T) {
	w, _ := GenerateWorld(smallConfig("delta"))
	s, _ := NewSimulation(w, "1")
	before := s.Snapshot()
	digest := s.StateDigest()
	before.Rules.Values["growth"] = .03
	before.Provinces[w.landList[0]].Population = 999
	before.Stats[0].EraShare[0] = 999
	people := before.Entities["people"][0]
	people.Fields["name"] = "mutated"
	if refs, ok := people.Fields["children"].([]int); ok && len(refs) > 0 {
		refs[0] = 999
	}
	if s.StateDigest() != digest {
		t.Fatal("snapshot aliases mutable historical data")
	}
	old := s.Snapshot()
	delta := s.AdvanceYearWithDelta()
	after := s.Snapshot()
	for _, p := range delta.Provinces {
		old.Provinces[p.ID] = p
	}
	old.Year = delta.Year
	old.StateSHA256 = delta.StateSHA256
	old.RNG = delta.RNG
	old.Rules = delta.Rules
	old.Favor = delta.Favor
	old.Entities = delta.EntityUpserts
	old.Stats = delta.Stats
	old.Events = append(old.Events, delta.Events...)
	old.Narrative = append(old.Narrative, delta.Narrative...)
	first, _ := json.Marshal(old)
	second, _ := json.Marshal(after)
	if string(first) != string(second) {
		t.Fatal("applying delta does not reconstruct the published state")
	}
	if delta.FromYear+1 != delta.Year || after.Year != s.Status().Year || after.StateSHA256 != s.Digest() {
		t.Fatal("delta is not a complete annual boundary")
	}
	for _, p := range after.Provinces {
		if math.IsNaN(float64(p.Population)) || p.Population < 0 {
			t.Fatal("invalid province population")
		}
	}
	if _, ok := s.Entity("dynasty", 0); ok {
		t.Fatal("invented dynasty entities")
	}
	if _, ok := s.Province(NoCell); ok {
		t.Fatal("invalid cell accepted")
	}
	delta.Rules.Values["growth"] = .03
	if len(delta.Events) > 0 {
		delta.Events[0].Entities = append(delta.Events[0].Entities, EntityRef{Kind: "bad", ID: 999})
	}
	if reflect.DeepEqual(s.Rules(), delta.Rules) {
		t.Fatal("delta exposes rule map")
	}
}

func TestQueriesAndAnnualWriterShareOnlyCompleteBoundaries(t *testing.T) {
	w, _ := GenerateWorld(smallConfig("concurrent-queries"))
	s, _ := NewSimulation(w, "1")
	start := s.Status().Year
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for n := 0; n < 30; n++ {
			s.AdvanceYear()
		}
	}()
	go func() {
		defer wg.Done()
		for n := 0; n < 15; n++ {
			view := s.Snapshot()
			if view.Year < start || view.Year > start+30 {
				t.Error("invalid publication year")
			}
			if _, err := json.Marshal(view); err != nil {
				t.Error(err)
			}
			s.Summary()
			s.Digest()
			s.Peoples()
			s.Cell(w.landList[0])
			s.Entity("people", 0)
		}
	}()
	wg.Wait()
	if s.Status().Year != start+30 {
		t.Fatal("annual writes lost")
	}
}
