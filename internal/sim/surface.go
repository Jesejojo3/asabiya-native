package sim

// Surface is optional, immutable fine-grid data for presentation/export. It is
// separate from World and contains no renderer, texture, GPU or window objects.
// Keeping it costs 4*width*height*4 bytes (~19.53 MiB for 1600x800), without
// duplicate copies of the already-computed generation arrays.
type Surface struct {
	width, height                                    int
	elevation, temperature, precipitation, amplitude []float32
}

type SurfaceSample struct {
	Elevation         float32
	Temperature       float32
	Precipitation     float32
	SeasonalAmplitude float32
}

func (s *Surface) Size() (int, int) { return s.width, s.height }
func (s *Surface) Bytes() int       { return 4 * 4 * s.width * s.height }
func (s *Surface) At(x, y int) (SurfaceSample, bool) {
	if x < 0 || y < 0 || x >= s.width || y >= s.height {
		return SurfaceSample{}, false
	}
	i := y*s.width + x
	return SurfaceSample{Elevation: s.elevation[i], Temperature: s.temperature[i], Precipitation: s.precipitation[i], SeasonalAmplitude: s.amplitude[i]}, true
}
