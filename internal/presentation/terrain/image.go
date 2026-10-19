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
		var col color.RGBA
		switch {
		case !cell.Land:
			depth := min(1.0, float64(-cell.Elevation)/6000)
			col = color.RGBA{R: 12, G: uint8(85 - 45*depth), B: uint8(140 - 65*depth), A: 255}
		case cell.Elevation > 3500:
			col = color.RGBA{220, 218, 205, 255}
		case cell.Elevation > 1800:
			col = color.RGBA{137, 123, 95, 255}
		case cell.Temperature < 0:
			col = color.RGBA{182, 198, 185, 255}
		case cell.Precipitation < 350:
			col = color.RGBA{192, 171, 109, 255}
		case cell.Precipitation > 1600:
			col = color.RGBA{48, 109, 72, 255}
		default:
			col = color.RGBA{110, 150, 83, 255}
		}
		im.SetRGBA(cell.X, cell.Y, col)
	}
	return im
}

func WritePNG(path string, w *sim.World) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	if err := png.Encode(f, Image(w)); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}
