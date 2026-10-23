// Package app connects command-line configuration to the renderer-free core.
package app

import (
	"flag"
	"fmt"
	"github.com/Jesejojo3/asabiya-native/internal/mapsource"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"io"
	"math"
	"strconv"
	"strings"
)

type Options struct {
	Source                   sim.WorldSource
	ReplayInput              string
	Years                    int
	CheckpointEvery          int
	SnapshotPath, ReplayPath string
	ExportPath               string
	World                    sim.WorldConfig
	HistorySeed              string
	Cell                     string
	Output                   string
	PNG                      string
	HighResolution           bool
	Peoples                  bool
	Rules                    sim.Rules
}

func Parse(args []string, stderr io.Writer) (Options, error) {
	o := Options{World: sim.DefaultWorldConfig("Asabiya"), Source: sim.DefaultWorldSource(), HistorySeed: "1", Rules: sim.DefaultRules()}
	var sourceFile, earthHTML, heightImage, temperatureImage, precipitationImage string
	startYear, bands := o.Rules.Values["startYear"], o.Rules.Values["bands"]
	f := flag.NewFlagSet("asabiya", flag.ContinueOnError)
	f.SetOutput(stderr)
	f.StringVar(&sourceFile, "world-source", "", "local world-source JSON (climate controls, input hashes and image scaling)")
	f.StringVar(&earthHTML, "earth-html", "", "load embedded Earth rasters from the preserved v0.6 HTML")
	f.StringVar(&heightImage, "height-image", "", "import a PNG/JPEG/GIF elevation image, black -11000 m, white 9000 m, midpoint sea level")
	f.StringVar(&temperatureImage, "temperature-image", "", "import temperature image, black -40 C, white 35 C")
	f.StringVar(&precipitationImage, "precipitation-image", "", "import precipitation image, black 0, white 4000 mm/year")
	f.StringVar(&o.World.Seed, "seed", o.World.Seed, "world seed (UTF-8)")
	f.StringVar(&o.HistorySeed, "history-seed", o.HistorySeed, "history seed (initialization only)")
	f.IntVar(&o.World.Width, "width", o.World.Width, "logical map width, 24..400")
	f.IntVar(&o.World.Height, "height", o.World.Height, "logical map height, 16..200")
	f.IntVar(&o.World.Detail, "detail", o.World.Detail, "fine-grid samples per axis, 1..4")
	f.Float64Var(&o.World.LandFraction, "land", o.World.LandFraction, "target surface land fraction, 0.2..0.5")
	f.StringVar(&o.Cell, "cell", "", "query cell x,y")
	f.StringVar(&o.Output, "out", "", "write JSON report to this file (headless)")
	f.StringVar(&o.PNG, "png", "", "write a terrain preview PNG")
	f.BoolVar(&o.HighResolution, "high-res", false, "retain fine layers for PNG export (requires --png in headless)")
	f.BoolVar(&o.Peoples, "peoples", false, "include every people, language and lineage in the report (headless)")
	f.IntVar(&o.Years, "years", 0, "complete historical years to advance (headless)")
	f.IntVar(&o.CheckpointEvery, "checkpoint-every", 0, "validate IDs/state and report a checkpoint at this year interval (headless)")
	f.StringVar(&o.SnapshotPath, "snapshot", "", "write a versioned complete read-only state JSON (headless)")
	f.StringVar(&o.ReplayPath, "replay", "", "write reproducible initial configuration and accepted/rejected commands (headless)")
	f.StringVar(&o.ExportPath, "export", "", "write geography binary, manifest and historical states for Godot (headless)")
	f.StringVar(&o.ReplayInput, "replay-in", "", "reconstruct a recorded native replay before optional additional years (headless)")
	f.Float64Var(&startYear, "start-year", startYear, "history start year, -12000..-4000 in steps of 500 (rule startYear)")
	f.Float64Var(&bands, "bands", bands, "founding peoples, 3..24 (rule bands)")
	if err := f.Parse(args); err != nil {
		return o, err
	}
	if f.NArg() != 0 {
		return o, fmt.Errorf("unexpected arguments: %s", strings.Join(f.Args(), " "))
	}
	if o.Years < 0 || o.Years > 100000 || o.CheckpointEvery < 0 {
		return o, fmt.Errorf("years must be 0..100000 and checkpoint-every nonnegative")
	}
	if sourceFile != "" {
		if earthHTML != "" || heightImage != "" || temperatureImage != "" || precipitationImage != "" {
			return o, fmt.Errorf("world-source cannot be combined with image/Earth input flags")
		}
		var err error
		o.Source, err = mapsource.ReadConfig(sourceFile)
		if err != nil {
			return o, err
		}
	} else {
		if earthHTML != "" && heightImage != "" {
			return o, fmt.Errorf("choose Earth or an imported height image")
		}
		if earthHTML != "" {
			o.Source.Kind = "earth"
			o.Source.FitClimate = true
			o.Source.Assets = append(o.Source.Assets, sim.SourceAsset{Role: "earth-html", Path: earthHTML})
		}
		if heightImage != "" {
			o.Source.Kind = "imported"
			o.Source.Assets = append(o.Source.Assets, sim.SourceAsset{Role: "height", Path: heightImage, Min: -11000, Max: 9000, Midpoint: true})
		}
		if temperatureImage != "" {
			o.Source.Assets = append(o.Source.Assets, sim.SourceAsset{Role: "temperature", Path: temperatureImage, Min: -40, Max: 35})
		}
		if precipitationImage != "" {
			o.Source.Assets = append(o.Source.Assets, sim.SourceAsset{Role: "precipitation", Path: precipitationImage, Min: 0, Max: 4000})
		}
	}
	o.Rules.Values["startYear"], o.Rules.Values["bands"] = startYear, bands
	if err := o.Rules.Validate(); err != nil {
		return o, err
	}
	if math.Mod(startYear, 500) != 0 {
		return o, fmt.Errorf("start year must be a multiple of 500, as the original slider")
	}
	return o, nil
}

func (o Options) QueryCell(w *sim.World) (*sim.Cell, error) {
	if o.Cell == "" {
		return nil, nil
	}
	parts := strings.Split(o.Cell, ",")
	if len(parts) != 2 {
		return nil, fmt.Errorf("cell must be x,y")
	}
	x, ex := strconv.Atoi(parts[0])
	y, ey := strconv.Atoi(parts[1])
	c := w.Config()
	if ex != nil || ey != nil || x < 0 || x >= c.Width || y < 0 || y >= c.Height {
		return nil, fmt.Errorf("cell coordinates out of bounds")
	}
	cell, ok := w.Cell(sim.CellID(y*c.Width + x))
	if !ok {
		return nil, fmt.Errorf("invalid cell")
	}
	return &cell, nil
}
