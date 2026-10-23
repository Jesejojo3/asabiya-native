package main

import (
	"errors"
	"flag"
	"fmt"
	"github.com/Jesejojo3/asabiya-native/internal/app"
	"github.com/Jesejojo3/asabiya-native/internal/mapsource"
	view "github.com/Jesejojo3/asabiya-native/internal/presentation/ebiten"
	"github.com/Jesejojo3/asabiya-native/internal/presentation/terrain"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"github.com/hajimehoshi/ebiten/v2"
	"os"
)

func run() error {
	o, err := app.Parse(os.Args[1:], os.Stderr)
	if err != nil {
		return err
	}
	if o.Output != "" || o.Cell != "" {
		return fmt.Errorf("--out and --cell are headless options; use asabiya-headless")
	}
	w, surface, err := mapsource.Generate(o.World, o.Source, true)
	if err != nil {
		return err
	}
	if _, err := sim.NewSimulationWithRules(w, o.HistorySeed, o.Rules); err != nil {
		return err
	}
	if o.PNG != "" {
		if err := terrain.WriteSurfacePNG(o.PNG, surface); err != nil {
			return err
		}
	}
	ebiten.SetWindowSize(1200, 600)
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	ebiten.SetWindowTitle(fmt.Sprintf("Asabiya Native | %s | terrain + climate preview | Esc: close", o.World.Seed))
	return ebiten.RunGame(view.New(w, surface))
}

func main() {
	if err := run(); err != nil && !errors.Is(err, flag.ErrHelp) {
		fmt.Fprintln(os.Stderr, "asabiya:", err)
		os.Exit(1)
	}
}
