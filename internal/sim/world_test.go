package sim

import (
	"math"
	"testing"
)

func smallConfig(seed string) WorldConfig {
	c := DefaultWorldConfig(seed)
	c.Width = 48
	c.Height = 24
	c.Detail = 4
	return c
}

func TestWorldReproducibilityAndInvariants(t *testing.T) {
	c := smallConfig("México 🌍")
	a, err := GenerateWorld(c)
	if err != nil {
		t.Fatal(err)
	}
	b, err := GenerateWorld(c)
	if err != nil {
		t.Fatal(err)
	}
	if a.Digest() != b.Digest() || a.RNGPosition() != b.RNGPosition() {
		t.Fatal("same seed/config changed world")
	}
	// Four makeNoise calls (255 shuffle + 256 values each), then one
	// latitude-weighted sampling draw at each third column/every second row.
	if a.RNGPosition().Calls != 5116 {
		t.Fatalf("unexpected generation draw count: %d", a.RNGPosition().Calls)
	}
	c.Seed = "different"
	other, err := GenerateWorld(c)
	if err != nil {
		t.Fatal(err)
	}
	if a.Digest() == other.Digest() {
		t.Fatal("seed has no effect")
	}
	land, coast := 0, 0
	totalArea := 0.0
	massCount := make([]int, len(a.landmassSizes))
	for i := 0; i < a.Len(); i++ {
		cell, ok := a.Cell(CellID(i))
		if !ok {
			t.Fatal("missing cell")
		}
		for _, v := range []float32{cell.Elevation, cell.Temperature, cell.Precipitation, cell.SeasonalAmplitude, cell.Roughness, cell.Latitude, cell.Area} {
			if math.IsNaN(float64(v)) || math.IsInf(float64(v), 0) {
				t.Fatalf("nonfinite cell %d: %+v", i, cell)
			}
		}
		if cell.Precipitation < 0 || cell.SeasonalAmplitude < 0 || cell.Roughness < 0 || cell.Roughness > 1 || cell.Area <= 0 {
			t.Fatalf("invalid ranges: %+v", cell)
		}
		totalArea += float64(cell.Area)
		if cell.Land {
			land++
			if cell.Elevation < 5 || cell.Landmass < 0 || int(cell.Landmass) >= len(massCount) {
				t.Fatal("invalid land")
			}
			massCount[cell.Landmass]++
		} else if cell.Elevation > -5 || cell.Coast || cell.Landmass != -1 || cell.Roughness != 0 {
			t.Fatal("invalid ocean")
		}
		isCoast := false
		for d, j := range cell.Neighbors {
			if j == NoCell {
				if d < 2 || (d == 2 && cell.Y != 0) || (d == 3 && cell.Y != a.config.Height-1) {
					t.Fatal("unexpected missing neighbor")
				}
				continue
			}
			nb, ok := a.Cell(j)
			if !ok {
				t.Fatal("neighbor out of bounds")
			}
			opposite := [4]int{1, 0, 3, 2}
			if nb.Neighbors[opposite[d]] != cell.ID {
				t.Fatal("nonreciprocal neighbor")
			}
			if !nb.Land {
				isCoast = true
			}
			if cell.Land && nb.Land && nb.Landmass != cell.Landmass {
				t.Fatal("adjacent land split across masses")
			}
		}
		if cell.Coast != (cell.Land && isCoast) {
			t.Fatal("coast differs from adjacent water")
		}
		if cell.Coast {
			coast++
		}
		if cell.X == 0 && cell.Neighbors[0] != CellID(cell.Y*a.config.Width+a.config.Width-1) {
			t.Fatal("seam does not wrap")
		}
	}
	for i, n := range massCount {
		if n != a.landmassSizes[i] {
			t.Fatal("incorrect mass size")
		}
	}
	if land == 0 || land == a.Len() || coast == 0 || land != a.landCells || coast != a.coastCells {
		t.Fatal("invalid land/coast counts")
	}
	// Sum of latitude strips approximates Earth's surface area, independently of seed.
	if totalArea < 5.05e8 || totalArea > 5.15e8 {
		t.Fatalf("invalid total area: %g", totalArea)
	}
	if _, ok := a.Cell(NoCell); ok {
		t.Fatal("accepted negative ID")
	}
	if _, ok := a.Cell(CellID(a.Len())); ok {
		t.Fatal("accepted past-end ID")
	}
	cell, _ := a.Cell(0)
	cell.Neighbors[0] = NoCell
	again, _ := a.Cell(0)
	if again.Neighbors[0] == NoCell {
		t.Fatal("view mutated the world")
	}
}

func TestRejectInvalidWorldConfig(t *testing.T) {
	for _, edit := range []func(*WorldConfig){
		func(c *WorldConfig) { c.Width = 0 }, func(c *WorldConfig) { c.Height = 201 },
		func(c *WorldConfig) { c.Detail = 0 }, func(c *WorldConfig) { c.LandFraction = math.NaN() },
		func(c *WorldConfig) { c.LandFraction = math.Inf(1) }, func(c *WorldConfig) { c.LandFraction = .1 },
		func(c *WorldConfig) { c.Seed = string([]byte{0xff}) }, func(c *WorldConfig) { c.Width = 24; c.Height = 16; c.Detail = 1 },
	} {
		c := smallConfig("test")
		edit(&c)
		if _, err := GenerateWorld(c); err == nil {
			t.Fatalf("accepted invalid config %+v", c)
		}
	}
}

func TestSimulationInitialization(t *testing.T) {
	w, err := GenerateWorld(smallConfig("world"))
	if err != nil {
		t.Fatal(err)
	}
	a, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := NewSimulation(w, "1")
	other, _ := NewSimulation(w, "2")
	if a.Status() != b.Status() || a.Status() == other.Status() {
		t.Fatal("history seed not reproduced")
	}
	if a.Status().Year != -9000 || a.Status().HistoryRNG.Calls != 0 || a.World() != w {
		t.Fatal("unexpected initialization")
	}
	if _, err := NewSimulation(nil, "1"); err == nil {
		t.Fatal("accepted absent world")
	}
}

func BenchmarkGenerateWorldSmall(b *testing.B) {
	c := smallConfig("benchmark")
	b.ReportAllocs()
	for b.Loop() {
		if _, err := GenerateWorld(c); err != nil {
			b.Fatal(err)
		}
	}
}
