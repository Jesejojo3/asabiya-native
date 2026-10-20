package interop

import "testing"

// BenchmarkCoreComparable measures only year computation and command accounting.
// World creation, history initialization and 20 warm-up years are excluded.
// The immutable JavaScript original is benchmarked separately on the same runner
// with equal dimensions, seeds, starting epoch, warm-up and measured-year count.
func BenchmarkCoreComparable(b *testing.B) {
    session := throughputSession(b, 400, 200)
    for year := 0; year < 20; year++ {
        session.simulation.AdvanceYear()
    }
    initial := session.simulation.Status().Year
    b.ReportAllocs()
    b.ResetTimer()
    for year := 0; year < b.N; year++ {
        session.simulation.AdvanceYear()
    }
    b.StopTimer()
    final := session.simulation.Status().Year
    if final-initial != b.N {
        b.Fatalf("years advanced = %d, expected %d", final-initial, b.N)
    }
    b.Logf("GO_CORE world=400x200 seed=Asabiya historySeed=1 warmupYears=20 measuredYears=%d initialYear=%d finalYear=%d", b.N, initial, final)
}
