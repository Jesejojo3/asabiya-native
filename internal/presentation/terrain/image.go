// Package terrain produces a terrain preview. Colors are presentation only;
// they never consume RNG or mutate the simulation.
package terrain

import (
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"image"
	"image/color"
	"image/png"
	"os"
)

func Image(w *sim.World) *image.RGBA {
	c := w.Config()
	im := image.NewRGBA(image.Rect(0, 0, c.Width, c.Height))
	for i := 0; i < w.Len(); i++ {
		cell, _ := w.Cell(sim.CellID(i))
		im.SetRGBA(cell.X, cell.Y, terrainColor(cell.Elevation, cell.Temperature, cell.Precipitation, cell.Land))
	}
	return im
}

// SurfaceImage uses the actual fine layers, not an upscaled coarse map.
// River/biome overlays and the final relief renderer remain future work.
func SurfaceImage(surface *sim.Surface) *image.RGBA {
	w, h := surface.Size()
	im := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			s, _ := surface.At(x, y)
			im.SetRGBA(x, y, terrainColor(s.Elevation, s.Temperature, s.Precipitation, s.Elevation > 0))
		}
	}
	return im
}

func terrainColor(elevation, temperature, precipitation float32, land bool) color.RGBA {
	var col color.RGBA
	switch {
	case !land:
		depth := min(1.0, float64(-elevation)/6000)
		col = color.RGBA{R: 12, G: uint8(85 - 45*depth), B: uint8(140 - 65*depth), A: 255}
	case elevation > 3500:
		col = color.RGBA{220, 218, 205, 255}
	case elevation > 1800:
		col = color.RGBA{137, 123, 95, 255}
	case temperature < 0:
		col = color.RGBA{182, 198, 185, 255}
	case precipitation < 350:
		col = color.RGBA{192, 171, 109, 255}
	case precipitation > 1600:
		col = color.RGBA{48, 109, 72, 255}
	default:
		col = color.RGBA{110, 150, 83, 255}
	}
	return col
}

func WritePNG(path string, w *sim.World) error {
	return writePNG(path, Image(w))
}

func WriteSurfacePNG(path string, surface *sim.Surface) error {
	return writePNG(path, SurfaceImage(surface))
}

func writePNG(path string, im image.Image) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	if err := png.Encode(f, im); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}
