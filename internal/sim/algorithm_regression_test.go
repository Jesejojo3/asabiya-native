package sim

import (
	"math"
	"math/rand/v2"
	"sync"
	"testing"
)

func TestMinMaxFloat64Contract(t *testing.T) {
	values := []float64{0, math.Copysign(0, -1), 1, -1, math.Inf(1), math.Inf(-1), math.NaN(), math.SmallestNonzeroFloat64, math.MaxFloat64}
	check := func(a, b float64) {
		t.Helper()
		for _, pair := range [][2]float64{{min64(a, b), math.Min(a, b)}, {max64(a, b), math.Max(a, b)}} {
			if math.IsNaN(pair[0]) && math.IsNaN(pair[1]) {
				continue
			}
			if math.Float64bits(pair[0]) != math.Float64bits(pair[1]) {
				t.Fatalf("numeric intrinsic changed bits for %x, %x", math.Float64bits(a), math.Float64bits(b))
			}
		}
	}
	for _, a := range values {
		for _, b := range values {
			check(a, b)
		}
	}
	r := rand.New(rand.NewPCG(17, 61))
	for i := 0; i < 100000; i++ {
		check(math.Float64frombits(r.Uint64()), math.Float64frombits(r.Uint64()))
	}
}

func TestExitFieldMatchesOriginalNeighborhoods(t *testing.T) {
	for _, size := range [][2]int{{24, 16}, {48, 24}, {400, 200}} {
		for seed := uint64(1); seed <= 3; seed++ {
			r := rand.New(rand.NewPCG(seed, 11))
			n := size[0] * size[1]
			w := &World{config: WorldConfig{Width: size[0], Height: size[1]}, land: make([]bool, n), temperature: make([]float32, n), farmSuitability: make([]float32, n), herdSuitability: make([]float32, n), forest: make([]float32, n), area: make([]float32, n), circumscription: make([]float32, n)}
			h := &history{world: w, annualState: annualState{annualReady: true, pol: make([]int32, n), exit: make([]float32, n)}, pop: make([]float32, n), circE: make([]float32, n)}
			for i := 0; i < n; i++ {
				w.land[i] = r.IntN(3) != 0 || i == 0 || i == size[0]-1 || i == n-1
				if w.land[i] {
					w.landList = append(w.landList, CellID(i))
				}
				w.temperature[i] = float32(r.Float64()*70 - 30)
				w.farmSuitability[i] = float32(r.Float64())
				w.herdSuitability[i] = float32(r.Float64())
				w.forest[i] = float32(r.Float64())
				w.area[i] = float32(1 + r.Float64()*10000)
				w.circumscription[i] = float32(r.Float64())
				h.pop[i] = float32(r.Float64() * 200000)
				if i%7 == 0 {
					h.pop[i] = 0
				}
				if i%113 == 0 {
					h.pop[i] = float32(math.NaN())
				}
				if i%127 == 0 {
					h.pop[i] = float32(math.Inf(1))
				}
				h.pol[i] = int32(r.IntN(4))
				h.exit[i] = -7 // skipped recipients must retain their previous value
			}
			original := *h
			original.exit = append([]float32(nil), h.exit...)
			original.circE = append([]float32(nil), h.circE...)
			field := h.exitField()
			for _, band := range [][2]float64{{0, .25}, {.25, .5}, {.5, .75}, {.75, 1}} {
				h.exitPassWithField(band[0], band[1], field)
				original.originalExitPass(band[0], band[1])
			}
			releaseExitField(field)
			for _, pair := range [][2][]float32{{h.exit, original.exit}, {h.circE, original.circE}} {
				for i, got := range pair[0] {
					want := pair[1][i]
					if math.IsNaN(float64(got)) && math.IsNaN(float64(want)) {
						continue
					}
					if math.Float32bits(got) != math.Float32bits(want) {
						t.Fatalf("neighborhood changed at cell %d, size %v, seed %d: %v != %v", i, size, seed, got, want)
					}
				}
			}
		}
	}
}

func TestConcurrentAlgorithmWorkspaces(t *testing.T) {
	w, err := GenerateWorld(smallConfig("algorithm-workspace"))
	if err != nil {
		t.Fatal(err)
	}
	baseline, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 60; i++ {
		baseline.AdvanceYear()
	}
	want := baseline.StateDigest()
	var group sync.WaitGroup
	for i := 0; i < 3; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			s, err := NewSimulation(w, "1")
			if err != nil {
				t.Error(err)
				return
			}
			for year := 0; year < 60; year++ {
				s.AdvanceYear()
			}
			if got := s.StateDigest(); got != want {
				t.Errorf("concurrent scratch changed history: %s != %s", got, want)
			}
		}()
	}
	group.Wait()
}

// Original Go neighborhood algorithm, preserved independently as a test oracle.
func (h *history) originalExitPass(start, end float64) {
	h.prepareAnnualState()
	w := h.world
	for k, stop := int(math.Floor(start*float64(len(w.landList)))), int(math.Floor(end*float64(len(w.landList)))); k < stop; k++ {
		i := w.landList[k]
		if h.pop[i] < 1 || float64(w.farmSuitability[i]) < .1 {
			h.circE[i] = w.circumscription[i]
			continue
		}
		cx, cy := int(i)%w.config.Width, int(i)/w.config.Width
		total, n := 0., 0
		for dy := -3; dy <= 3; dy++ {
			yy := cy + dy
			if yy < 0 || yy >= w.config.Height {
				continue
			}
			for dx := -3; dx <= 3; dx++ {
				if dx == 0 && dy == 0 {
					continue
				}
				j := CellID(yy*w.config.Width + (cx+dx+w.config.Width)%w.config.Width)
				n++
				if !w.land[j] {
					continue
				}
				warm := .3
				if w.temperature[j] > 10 {
					warm = 1
				}
				quality := math.Max(float64(w.farmSuitability[j]), math.Max(.5*float64(w.forest[j])*warm, .4*float64(w.herdSuitability[j])))
				density := math.Max(.3, 7*quality)
				political := 1.
				if h.pol[j] != 0 {
					political = .4
				}
				total += quality * math.Max(0, 1-float64(h.pop[j])/float64(w.area[j])/density) * political
			}
		}
		ex, own := total/float64(n), float64(w.farmSuitability[i])+.1
		h.exit[i] = float32(ex)
		h.circE[i] = float32(math.Max(0, math.Min(1, math.Max(float64(w.circumscription[i]), 1-1.6*ex/own))))
	}
}
