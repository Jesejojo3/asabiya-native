// Command asabiya-profile measures the causal engine independently of clients,
// annual publication, JSON and hashing. Startup and warmup are outside timing.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"runtime"
	"runtime/pprof"
	"time"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	warmup := flag.Int("warmup", 20, "complete years before measurement")
	years := flag.Int("years", 300, "complete years to measure")
	windows := flag.Int("windows", 1, "consecutive measured windows over the same history")
	cpu := flag.String("cpu", "", "optional CPU profile output")
	flag.Parse()
	if *warmup < 0 || *warmup > 20000 || *years < 1 || *years > 10000 || *windows < 1 || *windows > 10 {
		return fmt.Errorf("warmup must be 0..20000 and years 1..10000 and windows 1..10")
	}
	w, err := sim.GenerateWorld(sim.DefaultWorldConfig("Asabiya"))
	if err != nil {
		return err
	}
	s, err := sim.NewSimulation(w, "1")
	if err != nil {
		return err
	}
	for i := 0; i < *warmup; i++ {
		s.AdvanceYear()
	}
	for window := 0; window < *windows; window++ {
		profile := *cpu
		if profile != "" && *windows > 1 {
			profile = fmt.Sprintf("%s.%d", profile, window)
		}
		if err := measure(s, *warmup, *years, window, profile); err != nil {
			return err
		}
	}
	return nil
}

func measure(s *sim.Simulation, warmup, years, window int, cpu string) error {
	s.EnableWorkProfile()
	from := s.Status()
	if cpu != "" {
		f, err := os.Create(cpu)
		if err != nil {
			return err
		}
		defer f.Close()
		if err := pprof.StartCPUProfile(f); err != nil {
			return err
		}
	}
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	started := time.Now()
	for i := 0; i < years; i++ {
		s.AdvanceYear()
	}
	elapsed := time.Since(started)
	runtime.ReadMemStats(&after)
	if cpu != "" {
		pprof.StopCPUProfile()
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{
		"go": runtime.Version(), "os": runtime.GOOS, "arch": runtime.GOARCH,
		"gomaxprocs": runtime.GOMAXPROCS(0), "warmup": warmup, "years": years, "window": window,
		"from": from, "to": s.Status(), "livingStates": s.LivingStates(),
		"elapsedMs": float64(elapsed) / 1e6, "msPerYear": float64(elapsed) / 1e6 / float64(years),
		"allocatedBytes": after.TotalAlloc - before.TotalAlloc, "allocations": after.Mallocs - before.Mallocs,
		"stages": sim.ProfileStages, "profile": s.WorkProfile(), "sha256": s.StateDigest(),
	})
}
