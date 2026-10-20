package interop

import (
	"encoding/json"
	"fmt"
	"runtime"
	"testing"
)

// Both paths use the same world, history, atomic years, map JSON and projection
// cache. Startup is excluded; the baseline materializes full provincial views.
func BenchmarkMapAnnualPublication(b *testing.B) {
	for _, compact := range []bool{false, true} {
		name := "full-then-project"
		if compact {
			name = "compact"
		}
		b.Run(name, func(b *testing.B) {
			s := &Session{}
			created := s.Handle(Request{Schema: LocalSchema, ID: "create", Op: "create_world",
				Payload: json.RawMessage(`{"world":{"seed":"Asabiya","width":400,"height":200,"detail":4,"landFraction":0.33},"fine":false}`)})
			if !created.OK {
				b.Fatal(created.Error)
			}
			started := s.Handle(Request{Schema: LocalSchema, ID: "start", Op: "start_history",
				Payload: json.RawMessage(`{"historySeed":"1","view":"map"}`)})
			if !started.OK {
				b.Fatal(started.Error)
			}
			b.ReportAllocs()
			b.ResetTimer()
			var totalBytes int64
			for i := 0; i < b.N; i++ {
				var delta mapDelta
				if compact {
					delta = s.filterMapDelta(s.simulation.AdvanceYearWithMapDelta())
				} else {
					delta = s.projectMapDelta(s.simulation.AdvanceYearWithDelta())
				}
				encoded, err := json.Marshal(delta)
				if err != nil {
					b.Fatal(err)
				}
				totalBytes += int64(len(encoded))
				runtime.KeepAlive(encoded)
			}
			b.StopTimer()
			b.ReportMetric(float64(totalBytes)/float64(b.N), "wire-B/op")
			b.Log(fmt.Sprintf("finalYear=%d state=%s", s.simulation.Status().Year, s.simulation.StateDigest()))
		})
	}
}
