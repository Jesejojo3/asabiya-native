package interop

import (
	"encoding/json"
	"fmt"
	"reflect"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func mergeEntityRecords(dst map[string]map[int]sim.EntityRecord, updates map[string][]sim.EntityRecord) {
	for kind, records := range updates {
		if dst[kind] == nil {
			dst[kind] = make(map[int]sim.EntityRecord)
		}
		for _, record := range records {
			dst[kind][record.ID] = record
		}
	}
}

func TestSparseEntityPublicationPreservesFramesAndHistory(t *testing.T) {
	for _, size := range [][2]int{{24, 16}, {400, 200}} {
		t.Run(fmt.Sprintf("%dx%d", size[0], size[1]), func(t *testing.T) {
			full := throughputSession(t, size[0], size[1])
			sparse := throughputSession(t, size[0], size[1])
			snapshot := sparse.Handle(Request{Schema: LocalSchema, ID: "initial", Op: "get_state", Payload: json.RawMessage(`{"view":"map-columns-v1"}`)})
			if !snapshot.OK {
				t.Fatal(snapshot.Error)
			}
			first := snapshot.Data.(columnState)
			reconstructed := make(map[string]map[int]sim.EntityRecord)
			mergeEntityRecords(reconstructed, first.Entities)
			if !reflect.DeepEqual(reconstructed, byEntityID(full.simulation.MapSnapshot().Entities)) {
				t.Fatal("initial sparse entity baseline is incomplete")
			}
			removed := 0
			for i := 0; i < 15; i++ {
				x := full.Handle(Request{Schema: LocalSchema, ID: fmt.Sprintf("full-%d", i), Op: "advance", Payload: json.RawMessage(`{"view":"map-columns-v1"}`)})
				y := sparse.Handle(Request{Schema: LocalSchema, ID: fmt.Sprintf("sparse-%d", i), Op: "advance", Payload: json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed"}`)})
				if !x.OK || !y.OK { t.Fatalf("advance %d rejected: %v %v", i, x.Error, y.Error) }
				f := x.Data.(columnDelta)
				d := y.Data.(columnDelta)
				if !reflect.DeepEqual(f.Provinces, d.Provinces) ||
					f.StateSHA256 != d.StateSHA256 || f.RulesSHA256 != d.RulesSHA256 ||
					f.RNG != d.RNG || f.Year != d.Year || f.FromYear != d.FromYear ||
					!reflect.DeepEqual(f.Events, d.Events) ||
					!reflect.DeepEqual(f.Narrative, d.Narrative) {
					t.Fatalf("historical/map publication changed at step %d", i)
				}
				mergeEntityRecords(reconstructed, d.EntityUpserts)
				if !reflect.DeepEqual(reconstructed, byEntityID(f.EntityUpserts)) {
					t.Fatalf("entity reconstruction diverged at step %d", i)
				}
				for kind, records := range f.EntityUpserts {
					removed += len(records) - len(d.EntityUpserts[kind])
				}
			}
			if removed == 0 { t.Fatal("no unchanged entities suppressed") }
			if !reflect.DeepEqual(full.simulation.Replay(), sparse.simulation.Replay()) {
				t.Fatal("sparse presentation changed replay or RNG")
			}
			// Switching back to the original complete view is always lossless.
			plain := sparse.Handle(Request{Schema: LocalSchema, ID: "plain", Op: "advance", Payload: json.RawMessage(`{"view":"map-columns-v1"}`)})
			if !plain.OK { t.Fatal(plain.Error) }
			next := sparse.Handle(Request{Schema: LocalSchema, ID: "sparse-again", Op: "advance", Payload: json.RawMessage(`{"view":"map-columns-v1","entityMode":"changed"}`)})
			if !next.OK { t.Fatal(next.Error) }
			if !reflect.DeepEqual(next.Data.(columnDelta).EntityUpserts, sparse.simulation.MapSnapshot().Entities) {
				t.Fatal("missing cache did not fall back to full entity records")
			}
			invalid := sparse.Handle(Request{Schema: LocalSchema, ID: "invalid", Op: "advance", Payload: json.RawMessage(`{"view":"map","entityMode":"changed"}`)})
			if invalid.OK || invalid.Error.Code != "invalid_arguments" { t.Fatal("legacy view unexpectedly opted into sparse records") }
		})
	}
}

func byEntityID(input map[string][]sim.EntityRecord) map[string]map[int]sim.EntityRecord {
	m := make(map[string]map[int]sim.EntityRecord, len(input))
	mergeEntityRecords(m, input)
	return m
}
