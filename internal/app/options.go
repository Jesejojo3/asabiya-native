// Package app connects command-line configuration to the renderer-free core.
package app

import (
	"flag"
	"fmt"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"io"
	"strconv"
	"strings"
)

type Options struct {
	World       sim.WorldConfig
	HistorySeed string
	Cell        string
	Output      string
	PNG         string
}

func Parse(args []string, stderr io.Writer) (Options, error) {
	o := Options{World: sim.DefaultWorldConfig("Asabiya"), HistorySeed: "1"}
	f := flag.NewFlagSet("asabiya", flag.ContinueOnError)
	f.SetOutput(stderr)
	f.StringVar(&o.World.Seed, "seed", o.World.Seed, "world seed (UTF-8)")
	f.StringVar(&o.HistorySeed, "history-seed", o.HistorySeed, "history seed (initialization only)")
	f.IntVar(&o.World.Width, "width", o.World.Width, "logical map width, 24..400")
	f.IntVar(&o.World.Height, "height", o.World.Height, "logical map height, 16..200")
	f.IntVar(&o.World.Detail, "detail", o.World.Detail, "fine-grid samples per axis, 1..4")
	f.Float64Var(&o.World.LandFraction, "land", o.World.LandFraction, "target surface land fraction, 0.2..0.5")
	f.StringVar(&o.Cell, "cell", "", "query cell x,y")
	f.StringVar(&o.Output, "out", "", "write JSON report to this file (headless)")
	f.StringVar(&o.PNG, "png", "", "write a terrain preview PNG")
	if err := f.Parse(args); err != nil {
		return o, err
	}
	if f.NArg() != 0 {
		return o, fmt.Errorf("unexpected arguments: %s", strings.Join(f.Args(), " "))
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
