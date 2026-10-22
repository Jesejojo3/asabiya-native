// Generate the same real Go scenario for both static renderer probes.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"github.com/Jesejojo3/asabiya-native/internal/interop"
	"github.com/Jesejojo3/asabiya-native/internal/presentation/terrain"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
)

func main() {
	out := flag.String("out", "build/atlas2d/fixture", "generated fixture directory")
	years := flag.Int("years", 1000, "complete causal years")
	small := flag.Bool("small", false, "48x24 integration scenario")
	flag.Parse()
	must(os.MkdirAll(*out, 0755))
	config := sim.DefaultWorldConfig("Asabiya")
	if *small {
		config.Width = 48
		config.Height = 24
	}
	w, s, err := sim.GenerateWorldWithSurface(config)
	must(err)
	history, err := sim.NewSimulation(w, "1")
	must(err)
	for i := 0; i < *years; i++ {
		history.AdvanceYear()
	}
	must(interop.WriteBundle(*out, w, s, history))
	must(terrain.WriteSurfacePNG(filepath.Join(*out, "terrain.png"), s))
	snapshot := history.MapSnapshot()
	political := image.NewNRGBA(image.Rect(0, 0, w.Config().Width, w.Config().Height))
	for _, p := range snapshot.Provinces {
		if p.Owner == 0 {
			continue
		}
		// Colors from engine-owned polity fields, never generated states.
		entity, ok := history.Entity("polity", p.Owner)
		if !ok {
			continue
		}
		raw, _ := json.Marshal(entity.Fields["rgb"])
		var rgb []float64
		must(json.Unmarshal(raw, &rgb))
		if len(rgb) != 3 {
			panic("missing Go RGB")
		}
		id := int(p.ID)
		political.SetNRGBA(id%w.Config().Width, id/w.Config().Width, color.NRGBA{uint8(rgb[0]), uint8(rgb[1]), uint8(rgb[2]), 180})
	}
	f, err := os.Create(filepath.Join(*out, "political.png"))
	must(err)
	must(png.Encode(f, political))
	must(f.Close())
	metadata := map[string]any{"worldSHA256": w.Digest(), "stateSHA256": history.StateDigest(), "year": snapshot.Year, "width": w.Config().Width, "height": w.Config().Height, "symbols": 0, "source": "real Go procedural", "note": "Static renderer probe; history controls are assessed separately"}
	b, err := json.MarshalIndent(metadata, "", "  ")
	must(err)
	must(os.WriteFile(filepath.Join(*out, "probe.json"), append(b, '\n'), 0644))
	fmt.Println(string(b))
}
func must(err error) {
	if err != nil {
		panic(err)
	}
}
