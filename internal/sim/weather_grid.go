package sim

import "math"

const WeatherGridWidth = 40
const WeatherGridHeight = 20

// WeatherInterpolation describes how a cell samples a future 40x20 anomaly
// field. It does not initialize that field (gauss and historical RNG belong to
// newHistory), nor advance weather. Fractions are float32 as in wi/wf.
type WeatherInterpolation struct {
	Indices   [4]int32   `json:"indices"`
	Fractions [2]float32 `json:"fractions"`
}

func (w *World) prepareWeatherGrid() {
	w.weatherIndices = make([][4]int32, w.Len())
	w.weatherFractions = make([][2]float32, w.Len())
	for i := 0; i < w.Len(); i++ {
		x, y := i%w.config.Width, i/w.config.Width
		gx := (float64(x)+.5)/float64(w.config.Width)*WeatherGridWidth - .5
		gy := clamp((float64(y)+.5)/float64(w.config.Height)*WeatherGridHeight-.5, 0, WeatherGridHeight-1.001)
		x0, y0 := int(math.Floor(gx)), int(math.Floor(gy))
		xa, xb := (x0+WeatherGridWidth)%WeatherGridWidth, (x0+1)%WeatherGridWidth
		y1 := min(y0+1, WeatherGridHeight-1)
		w.weatherIndices[i] = [4]int32{int32(y0*WeatherGridWidth + xa), int32(y0*WeatherGridWidth + xb), int32(y1*WeatherGridWidth + xa), int32(y1*WeatherGridWidth + xb)}
		w.weatherFractions[i] = [2]float32{float32(gx - float64(x0)), float32(gy - float64(y0))}
	}
}
