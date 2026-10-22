// Static renderer microprobe only. It does not implement a second simulation.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"github.com/hajimehoshi/ebiten/v2"
	"image"
	_ "image/png"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

type game struct {
	terrain, political *ebiten.Image
	log                *os.File
	start, last        time.Time
	duration           time.Duration
	zoom               float64
	frames             int
}

func (g *game) Update() error {
	if time.Since(g.start) > g.duration+3*time.Second {
		return ebiten.Termination
	}
	return nil
}
func (g *game) Draw(screen *ebiten.Image) {
	now := time.Now()
	elapsed := now.Sub(g.start).Seconds()
	if !g.last.IsZero() && elapsed >= 3 {
		b, _ := json.Marshal(map[string]any{"kind": "frame", "frame_ms": float64(now.Sub(g.last)) / float64(time.Millisecond)})
		fmt.Fprintln(g.log, string(b))
		g.frames++
	}
	g.last = now
	cx := 400 * (0.5 + math.Sin(elapsed*0.2)*0.15)
	cy := 200 * (0.5 + math.Sin(elapsed*0.12)*0.08)
	scale := math.Min(1920.0/400, 1080.0/200) * g.zoom
	for wrap := -2; wrap <= 2; wrap++ {
		op := &ebiten.DrawImageOptions{}
		op.Filter = ebiten.FilterLinear
		op.GeoM.Scale(scale/4, scale/4)
		op.GeoM.Translate(960-cx*scale+float64(wrap)*400*scale, 540-cy*scale)
		screen.DrawImage(g.terrain, op)
		op = &ebiten.DrawImageOptions{}
		op.Filter = ebiten.FilterLinear
		op.GeoM.Scale(scale, scale)
		op.GeoM.Translate(960-cx*scale+float64(wrap)*400*scale, 540-cy*scale)
		screen.DrawImage(g.political, op)
	}
}
func (g *game) Layout(w, h int) (int, int) { return 1920, 1080 }
func load(path string) *ebiten.Image {
	f, e := os.Open(path)
	if e != nil {
		panic(e)
	}
	defer f.Close()
	im, _, e := image.Decode(f)
	if e != nil {
		panic(e)
	}
	return ebiten.NewImageFromImage(im)
}
func main() {
	fixture := flag.String("fixture", "build/atlas2d/fixture", "Go fixture")
	output := flag.String("out", "ebiten.jsonl", "measurement")
	seconds := flag.Float64("seconds", 10, "seconds after 3s warmup")
	zoom := flag.Float64("zoom", 4, "world scale multiplier")
	flag.Parse()
	f, e := os.Create(*output)
	if e != nil {
		panic(e)
	}
	defer f.Close()
	meta, e := os.ReadFile(filepath.Join(*fixture, "probe.json"))
	if e != nil {
		panic(e)
	}
	b, _ := json.Marshal(map[string]any{"kind": "environment", "engine": "Ebitengine 2.10.5", "os": runtime.GOOS, "go": runtime.Version(), "measurement": "Draw callback intervals, not photons", "fixture": json.RawMessage(meta), "size": "1920x1080", "target_hardware_verified": false, "zoom": *zoom})
	fmt.Fprintln(f, string(b))
	ebiten.SetWindowSize(1920, 1080)
	ebiten.SetWindowTitle("Atlas2D static microprobe — Ebitengine")
	ebiten.SetVsyncEnabled(false)
	ebiten.SetTPS(ebiten.SyncWithFPS)
	g := &game{terrain: load(filepath.Join(*fixture, "terrain.png")), political: load(filepath.Join(*fixture, "political.png")), log: f, start: time.Now(), duration: time.Duration(*seconds * float64(time.Second)), zoom: *zoom}
	if e := ebiten.RunGame(g); e != nil {
		panic(e)
	}
}
