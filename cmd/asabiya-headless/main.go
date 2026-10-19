package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/Jesejojo3/asabiya-native/internal/app"
	"github.com/Jesejojo3/asabiya-native/internal/interop"
	"github.com/Jesejojo3/asabiya-native/internal/presentation/terrain"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"io"
	"os"
	"runtime"
	"runtime/debug"
)

type environment struct {
	Go             string `json:"go"`
	OS             string `json:"os"`
	Arch           string `json:"arch"`
	GOAMD64        string `json:"goamd64"`
	NumericBackend string `json:"numericBackend"`
}

type report struct {
	Checkpoints []sim.SimulationStatus `json:"checkpoints,omitempty"`
	Schema      string                 `json:"schema"`
	Environment environment            `json:"environment"`
	World       sim.WorldSummary       `json:"world"`
	BaseWorld   sim.BaseWorldSummary   `json:"baseWorld"`
	Simulation  sim.SimulationStatus   `json:"simulation"`
	History     historyReport          `json:"history"`
	Peoples     []sim.PeopleView       `json:"peoples,omitempty"`
	Cell        *sim.Cell              `json:"cell,omitempty"`
	CellHistory *sim.CellHistory       `json:"cellHistory,omitempty"`
	SeaLinks    []sim.SeaLink          `json:"seaLinks,omitempty"`
}

// historyReport is the initialized history (summary, hearths, chronicle,
// statistics and its native digest); --peoples adds every people.
type historyReport struct {
	sim.HistorySummary
}

func run(args []string, stdout, stderr io.Writer) error {
	o, err := app.Parse(args, stderr)
	if err != nil {
		return err
	}
	var checkpoints []sim.SimulationStatus
	var replayInput *sim.Replay
	if o.ReplayInput != "" {
		data, err := os.ReadFile(o.ReplayInput)
		if err != nil {
			return err
		}
		var replay sim.Replay
		if err = json.Unmarshal(data, &replay); err != nil {
			return err
		}
		replayInput = &replay
		o.World = replay.World
		o.HistorySeed = replay.HistorySeed
		o.Rules = replay.InitialRules
	}
	if o.HighResolution && o.PNG == "" {
		return fmt.Errorf("--high-res requires --png in headless")
	}
	var w *sim.World
	var surface *sim.Surface
	if o.HighResolution || o.ExportPath != "" {
		w, surface, err = sim.GenerateWorldWithSurface(o.World)
	} else {
		w, err = sim.GenerateWorld(o.World)
	}
	if err != nil {
		return err
	}
	var s *sim.Simulation
	if replayInput != nil {
		s, err = sim.ReplayOnWorld(w, *replayInput)
	} else {
		s, err = sim.NewSimulationWithRules(w, o.HistorySeed, o.Rules)
	}
	if err != nil {
		return err
	}
	for n := 1; n <= o.Years; n++ {
		s.AdvanceYear()
		if o.CheckpointEvery > 0 && n%o.CheckpointEvery == 0 {
			if err := s.Validate(); err != nil {
				return fmt.Errorf("year %d: %w", s.Status().Year, err)
			}
			checkpoints = append(checkpoints, s.Status())
			fmt.Fprintf(stderr, "Completed %d years; year %d; RNG calls %d\n", n, s.Status().Year, s.Status().HistoryRNG.Calls)
		}
	}
	if o.Years > 0 || replayInput != nil {
		if err := s.Validate(); err != nil {
			return err
		}
	}
	if o.SnapshotPath != "" {
		data, err := json.Marshal(s.Snapshot())
		if err != nil {
			return err
		}
		if err = os.WriteFile(o.SnapshotPath, append(data, '\n'), 0644); err != nil {
			return err
		}
	}
	if o.ReplayPath != "" {
		data, err := json.Marshal(s.Replay())
		if err != nil {
			return err
		}
		if err = os.WriteFile(o.ReplayPath, append(data, '\n'), 0644); err != nil {
			return err
		}
	}
	if o.ExportPath != "" {
		if err := interop.WriteBundle(o.ExportPath, w, surface, s); err != nil {
			return err
		}
	}
	cell, err := o.QueryCell(w)
	if err != nil {
		return err
	}
	if o.PNG != "" {
		var err error
		if surface != nil {
			err = terrain.WriteSurfacePNG(o.PNG, surface)
		} else {
			err = terrain.WritePNG(o.PNG, w)
		}
		if err != nil {
			return err
		}
	}
	env := environment{Go: runtime.Version(), OS: runtime.GOOS, Arch: runtime.GOARCH, NumericBackend: "Go math; no V8 parity"}
	if bi, ok := debug.ReadBuildInfo(); ok {
		for _, v := range bi.Settings {
			if v.Key == "GOAMD64" {
				env.GOAMD64 = v.Value
			}
		}
	}
	r := report{Schema: "asabiya/headless-v3", Environment: env, World: w.Summary(), BaseWorld: w.BaseSummary(), Simulation: s.Status(),
		History: historyReport{s.Summary()}, Cell: cell}
	if o.Years > 0 || replayInput != nil {
		r.Schema = "asabiya/headless-v4"
	}
	r.Checkpoints = checkpoints
	if o.Peoples {
		r.Peoples = s.Peoples()
	}
	if cell != nil {
		r.SeaLinks, _ = w.SeaLinks(cell.ID)
		ch, _ := s.Cell(cell.ID)
		r.CellHistory = &ch
	}
	data, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if o.Output != "" {
		if err := os.WriteFile(o.Output, data, 0644); err != nil {
			return err
		}
	}
	_, err = stdout.Write(data)
	return err
}

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}
		fmt.Fprintln(os.Stderr, "asabiya-headless:", err)
		os.Exit(1)
	}
}
