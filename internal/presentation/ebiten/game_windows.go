// Package ebiten provides the initial Windows map viewport. The core does not
// import this package. Generation finishes before the window starts; there are
// no annual systems or simulation goroutines yet.
package ebiten

import (
	"github.com/Jesejojo3/asabiya-native/internal/presentation/terrain"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
	"github.com/hajimehoshi/ebiten/v2"
	"math"
)

type Game struct {
	texture *ebiten.Image
	world   *sim.World
	surface *sim.Surface // retained for future map inspection; immutable CPU data
}

func New(w *sim.World, surface *sim.Surface) *Game {
	if surface != nil {
		return &Game{texture: ebiten.NewImageFromImage(terrain.SurfaceImage(surface)), world: w, surface: surface}
	}
	return &Game{texture: ebiten.NewImageFromImage(terrain.Image(w)), world: w}
}
func (g *Game) Update() error {
	if ebiten.IsKeyPressed(ebiten.KeyEscape) {
		return ebiten.Termination
	}
	return nil
}
func (g *Game) Draw(screen *ebiten.Image) {
	sw, sh := screen.Bounds().Dx(), screen.Bounds().Dy()
	tw, th := g.texture.Bounds().Dx(), g.texture.Bounds().Dy()
	scale := math.Min(float64(sw)/float64(tw), float64(sh)/float64(th))
	op := &ebiten.DrawImageOptions{}
	op.GeoM.Scale(scale, scale)
	op.GeoM.Translate((float64(sw)-float64(tw)*scale)/2, (float64(sh)-float64(th)*scale)/2)
	screen.DrawImage(g.texture, op)
}
func (g *Game) Layout(outsideWidth, outsideHeight int) (int, int) { return outsideWidth, outsideHeight }
