// Command asabiya-snapshot exports an engine world as a binary snapshot for the
// Godot 3D client (client/godot). It belongs to the client tooling: it reads
// only the public sim API and never changes simulation code or results.
//
//	asabiya-snapshot --seed Asabiya --out worlds/Asabiya.asw
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func run(args []string, stdout, stderr io.Writer) error {
	f := flag.NewFlagSet("asabiya-snapshot", flag.ContinueOnError)
	f.SetOutput(stderr)
	c := sim.DefaultWorldConfig("Asabiya")
	history := "1"
	out := ""
	coarse := false
	f.StringVar(&c.Seed, "seed", c.Seed, "world seed (UTF-8)")
	f.StringVar(&history, "history-seed", history, "history seed")
	f.IntVar(&c.Width, "width", c.Width, "logical map width, 24..400")
	f.IntVar(&c.Height, "height", c.Height, "logical map height, 16..200")
	f.IntVar(&c.Detail, "detail", c.Detail, "fine samples per axis, 1..4")
	f.Float64Var(&c.LandFraction, "land", c.LandFraction, "land fraction, 0.2..0.5")
	f.StringVar(&out, "out", "", "output .asw path (required)")
	f.BoolVar(&coarse, "coarse", false, "omit the fine 1600x800 layers")
	if err := f.Parse(args); err != nil {
		return err
	}
	if f.NArg() != 0 || out == "" {
		return errors.New("usage: asabiya-snapshot --out FILE [--seed S]")
	}
	var w *sim.World
	var surface *sim.Surface
	var err error
	if coarse {
		w, err = sim.GenerateWorld(c)
	} else {
		w, surface, err = sim.GenerateWorldWithSurface(c)
	}
	if err != nil {
		return err
	}
	s, err := sim.NewSimulation(w, history)
	if err != nil {
		return err
	}
	data, err := Build(w, surface, s.Status(), map[string]string{"tool": "asabiya-snapshot", "go": runtime.Version()})
	if err != nil {
		return err
	}
	if dir := filepath.Dir(out); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	tmp := out + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, out); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "{\"ok\":true,\"path\":%q,\"bytes\":%d,\"digest\":%q}\n", out, len(data), w.Digest())
	return nil
}

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}
		fmt.Fprintln(os.Stderr, "asabiya-snapshot:", err)
		os.Exit(1)
	}
}
