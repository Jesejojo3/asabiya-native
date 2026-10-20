package interop

import (
	"encoding/json"
	"fmt"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"math"
	"os"
	"reflect"
	"slices"
	"testing"
	"time"
)

func BenchmarkFieldWirePublication(b *testing.B) {
	for _, mode := range []string{"columns", "fields"} {
		b.Run(mode, func(b *testing.B) {
			s := throughputSession(b, 400, 200)
			payload := json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed"}`)
			if mode == "fields" {
				payload = json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed","provinceMode":"changed-fields-v1"}`)
			}
			for i := 0; i < 20; i++ {
				s.Handle(Request{Schema: LocalSchema, ID: "warmup", Op: "advance", Payload: payload})
			}
			b.ReportAllocs()
			b.ResetTimer()
			total := 0
			for i := 0; i < b.N; i++ {
				r := s.Handle(Request{Schema: LocalSchema, ID: "bench", Op: "advance", Payload: payload})
				if !r.OK {
					b.Fatal(r.Error)
				}
				wire, e := json.Marshal(r.Data)
				if e != nil {
					b.Fatal(e)
				}
				total += len(wire)
			}
			b.StopTimer()
			b.ReportMetric(float64(total)/float64(b.N), "wire-B/year")
		})
	}
}

func applyFieldDelta(rows []mapProvince, fields mapFields) {
	applyField(fields.Owner, func(id int, v int) { rows[id].Owner = v })
	applyField(fields.People, func(id int, v int) { rows[id].People = v })
	applyField(fields.Religion, func(id int, v int) { rows[id].Religion = v })
	applyField(fields.Era, func(id int, v int) { rows[id].Era = v })
	applyField(fields.Population, func(id int, v float32) { rows[id].Population = v })
	applyField(fields.Capacity, func(id int, v float32) { rows[id].Capacity = v })
	applyField(fields.Fortification, func(id int, v float32) { rows[id].Fortification = v })
}
func applyField[T int | float32](p *fieldPatch[T], f func(int, T)) {
	if p != nil {
		for i, id := range p.IDs {
			f(int(id), p.Values[i])
		}
	}
}

func TestFieldPublicationReconstructionAndRecovery(t *testing.T) {
	for _, size := range [][2]int{{24, 16}, {400, 200}} {
		t.Run(fmt.Sprint(size), func(t *testing.T) {
			a, b := throughputSession(t, size[0], size[1]), throughputSession(t, size[0], size[1])
			rows := slices.Clone(a.simulation.MapSnapshot().Provinces)
			for i := 0; i < 30; i++ {
				if i == 5 { // Status-only advancement invalidates the base; get_state restores it.
					for _, s := range []*Session{a, b} {
						s.Handle(Request{Schema: LocalSchema, ID: "status", Op: "advance", Payload: json.RawMessage(`{"publication":"status"}`)})
					}
				}
				if i == 10 { // A real rules command also invalidates both presentation caches.
					for _, s := range []*Session{a, b} {
						enabled := true
						payload, _ := json.Marshal(sim.Command{Schema: sim.CommandSchema, Profile: sim.NativeProfile, Sequence: s.simulation.NextSequence(), TargetYear: s.simulation.Status().Year, Kind: "set_sandbox", Sandbox: &enabled})
						r := s.Handle(Request{Schema: LocalSchema, ID: "command", Op: "apply_command", Payload: payload})
						if !r.OK || !r.Data.(map[string]any)["result"].(sim.CommandResult).Accepted {
							t.Fatal("command was not accepted")
						}
					}
				}
				if i == 15 {
					for _, s := range []*Session{a, b} {
						s.Handle(Request{Schema: LocalSchema, ID: "snapshot", Op: "get_state", Payload: json.RawMessage(`{"view":"map-columns-v1"}`)})
					}
					rows = slices.Clone(a.simulation.MapSnapshot().Provinces)
				}
				if i == 5 || i == 10 { // Receiver gets the exact current boundary before advancing again.
					rows = slices.Clone(a.simulation.MapSnapshot().Provinces)
				}
				x := a.Handle(Request{Schema: LocalSchema, ID: "columns", Op: "advance", Payload: json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed"}`)})
				y := b.Handle(Request{Schema: LocalSchema, ID: "fields", Op: "advance", Payload: json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed","provinceMode":"changed-fields-v1"}`)})
				if !x.OK || !y.OK {
					t.Fatalf("advance failed: %v %v", x.Error, y.Error)
				}
				want := x.Data.(columnDelta)
				switch got := y.Data.(type) {
				case fieldDelta:
					if i == 5 || i == 10 {
						t.Fatal("stale baseline used for field patch")
					}
					applyFieldDelta(rows, got.Provinces)
					var total float64
					for _, p := range rows {
						total += float64(p.Population)
					}
					if total != got.WorldPopulation {
						t.Fatal("population aggregate changed summation order")
					}
					got.Schema = want.Schema
					if !reflect.DeepEqual(got.AnnualDelta, want.AnnualDelta) {
						t.Fatal("field patch changed annual metadata")
					}
				case columnDelta:
					if i != 5 && i != 10 && (i < 5 || i >= 15) {
						t.Fatal("unexpected full-row fallback")
					}
					c := got.Provinces
					for k, id := range c.ID {
						rows[id] = mapProvince{ID: id, Owner: c.Owner[k], People: c.People[k], Religion: c.Religion[k], Population: c.Population[k], Capacity: c.Capacity[k], Fortification: c.Fortification[k], Era: c.Era[k]}
					}
				default:
					t.Fatalf("unexpected publication: %T", got)
				}
				expected := a.simulation.MapSnapshot()
				for k, p := range expected.Provinces {
					if !sameMapProvince(rows[k], p) {
						t.Fatalf("province %d diverged at step %d", k, i)
					}
				}
				wire, err := json.Marshal(y.Data)
				if err != nil || !json.Valid(wire) {
					t.Fatal("invalid wire JSON")
				}
				if want.StateSHA256 != b.simulation.StateDigest() {
					t.Fatal("digest changed")
				}
			}
			if !reflect.DeepEqual(a.simulation.Replay(), b.simulation.Replay()) {
				t.Fatal("replay changed")
			}
			for _, payload := range []string{`{"view":"map","provinceMode":"changed-fields-v1"}`, `{"view":"map-columns-v1","provinceMode":"unknown"}`, `{"view":"map-columns-v1","provinceMode":"changed-fields-v1","publication":"status"}`} {
				before := b.simulation.Status()
				r := b.Handle(Request{Schema: LocalSchema, ID: "invalid", Op: "advance", Payload: json.RawMessage(payload)})
				if r.OK || b.simulation.Status() != before {
					t.Fatal("invalid negotiation advanced history")
				}
			}
		})
	}
}

func TestFieldPatchesPreserveAllBitsAndPublicationOwnership(t *testing.T) {
	old := mapProvince{ID: 0}
	s := &Session{mapCache: []mapProvince{old}, mapCacheYear: 1}
	next := mapProvince{ID: 0, Owner: 4, People: 5, Religion: 6, Era: 7, Population: math.Float32frombits(1 << 31), Capacity: math.Float32frombits(1 << 31), Fortification: math.Float32frombits(1 << 31)}
	got := s.packFieldDelta(mapDelta{AnnualDelta: sim.AnnualDelta{FromYear: 1, Year: 2}, Provinces: []mapProvince{next}}).(fieldDelta)
	rows := []mapProvince{old}
	applyFieldDelta(rows, got.Provinces)
	if !sameMapProvince(rows[0], next) {
		t.Fatal("field loss or signed zero suppressed")
	}
	s.packFieldDelta(mapDelta{AnnualDelta: sim.AnnualDelta{FromYear: 2, Year: 3}, Provinces: []mapProvince{old}})
	rows[0] = old
	applyFieldDelta(rows, got.Provinces)
	if !sameMapProvince(rows[0], next) {
		t.Fatal("later publication mutated an earlier patch")
	}
}

// Opt-in late window with naturally formed states. It never adjusts the rules,
// regenerates fixtures, or fast-forwards by changing the historical clock.
func TestMatureFieldPublicationWindow(t *testing.T) {
	if os.Getenv("ASABIYA_MATURE_PUBLICATION") != "1" {
		t.Skip("opt-in 5500-year causal warmup")
	}
	a, b := throughputSession(t, 400, 200), throughputSession(t, 400, 200)
	for i := 0; i < 5500; i++ {
		a.simulation.AdvanceYear()
		b.simulation.AdvanceYear()
	}
	for _, s := range []*Session{a, b} {
		s.cacheMapState(s.simulation.MapSnapshot())
	}
	left := slices.Clone(a.simulation.MapSnapshot().Provinces)
	right := slices.Clone(left)
	var elapsed [2]time.Duration
	var wire [2]int
	for i := 0; i < 50; i++ {
		var metadata [2]sim.AnnualDelta
		for k, s := range []*Session{a, b} {
			payload := json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed"}`)
			if k == 1 {
				payload = json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed","provinceMode":"changed-fields-v1"}`)
			}
			started := time.Now()
			r := s.Handle(Request{Schema: LocalSchema, ID: "mature", Op: "advance", Payload: payload})
			if !r.OK {
				t.Fatal(r.Error)
			}
			data, err := json.Marshal(r.Data)
			if err != nil {
				t.Fatal(err)
			}
			elapsed[k] += time.Since(started)
			wire[k] += len(data)
			switch d := r.Data.(type) {
			case columnDelta:
				metadata[k] = d.AnnualDelta
				c := d.Provinces
				for j, id := range c.ID {
					left[id] = mapProvince{ID: id, Owner: c.Owner[j], People: c.People[j], Religion: c.Religion[j], Population: c.Population[j], Capacity: c.Capacity[j], Fortification: c.Fortification[j], Era: c.Era[j]}
				}
			case fieldDelta:
				metadata[k] = d.AnnualDelta
				applyFieldDelta(right, d.Provinces)
			default:
				t.Fatalf("unexpected mature view: %T", d)
			}
		}
		metadata[1].Schema = metadata[0].Schema
		if !reflect.DeepEqual(metadata[0], metadata[1]) {
			t.Fatalf("mature metadata diverged at %d", i)
		}
		for j, p := range left {
			if !sameMapProvince(p, right[j]) {
				t.Fatalf("mature province %d diverged at %d", j, i)
			}
		}
	}
	if !reflect.DeepEqual(a.simulation.Replay(), b.simulation.Replay()) {
		t.Fatal("mature replay diverged")
	}
	t.Logf("MATURE warmup=5500 samples=50 year=%d states=%d columnsMs=%.3f fieldsMs=%.3f columnsBytes=%d fieldsBytes=%d digest=%s", a.simulation.Status().Year, a.simulation.LivingStates(), float64(elapsed[0].Microseconds())/50000, float64(elapsed[1].Microseconds())/50000, wire[0]/50, wire[1]/50, a.simulation.StateDigest())
}
