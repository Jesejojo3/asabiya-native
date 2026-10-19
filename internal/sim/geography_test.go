package sim

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
)

type geographyFixture struct {
	Heap struct {
		Operations [][]json.RawMessage
		Pops       []CellID
	}
	Input struct {
		Width, Height                                                     int
		Elevation, Land, Temperature, Precipitation, Amplitude, Roughness []float32
	}
	Output map[string][]float64
}

func loadGeographyFixture(t *testing.T) geographyFixture {
	t.Helper()
	b, err := os.ReadFile("../../tests/native/geography-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var f geographyFixture
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestLegacyHeapTiesAndInterleavedPushes(t *testing.T) {
	f := loadGeographyFixture(t)
	h := drainHeap{}
	var pops []CellID
	for _, op := range f.Heap.Operations {
		var kind string
		if err := json.Unmarshal(op[0], &kind); err != nil {
			t.Fatal(err)
		}
		if kind == "push" {
			var id CellID
			var key float64
			json.Unmarshal(op[1], &id)
			json.Unmarshal(op[2], &key)
			h.push(id, key)
		} else {
			pops = append(pops, h.pop())
		}
	}
	if !reflect.DeepEqual(pops, f.Heap.Pops) {
		t.Fatalf("heap tie order differs from JS: %v, want %v", pops, f.Heap.Pops)
	}
}

func TestOriginalGeographyContract(t *testing.T) {
	f := loadGeographyFixture(t)
	c := WorldConfig{Width: f.Input.Width, Height: f.Input.Height}
	n := c.Width * c.Height
	w := &World{config: c, elevation: f.Input.Elevation, temperature: f.Input.Temperature, precipitation: f.Input.Precipitation, amplitude: f.Input.Amplitude, roughness: f.Input.Roughness,
		land: make([]bool, n), coast: make([]bool, n), latitude: make([]float32, n), area: make([]float32, n), neighbors: make([][4]CellID, n), landmass: make([]int32, n)}
	for i := 0; i < n; i++ {
		x, y := i%c.Width, i/c.Width
		w.land[i] = f.Input.Land[i] != 0
		lat := (90 - (float64(y)+.5)/float64(c.Height)*180) * math.Pi / 180
		w.latitude[i] = float32(lat)
		w.area[i] = float32((40075.0 / float64(c.Width)) * (20004.0 / float64(c.Height)) * math.Cos(lat))
		w.neighbors[i] = [4]CellID{CellID(y*c.Width + (x+c.Width-1)%c.Width), CellID(y*c.Width + (x+1)%c.Width), NoCell, NoCell}
		if y > 0 {
			w.neighbors[i][2] = CellID(i - c.Width)
		}
		if y < c.Height-1 {
			w.neighbors[i][3] = CellID(i + c.Width)
		}
	}
	w.indexLand()
	w.prepareGeometry()
	w.prepareDrainage()
	w.prepareSuitability()
	w.prepareTravel()
	w.prepareWeatherGrid()
	w.prepareSeaLinks()
	w.prepareEcology()
	floats := map[string][]float32{"lat": w.latitude, "area": w.area, "x3": w.x3, "y3": w.y3, "z3": w.z3, "cosLon": w.cosLon, "sinLon": w.sinLon, "cosLat": w.cosLat, "filled": w.filled, "acc": w.accumulation, "rv": w.river, "sF": w.farmSuitability, "sH": w.herdSuitability, "gs": w.growingSeason, "leach": w.leach, "trop": w.tropical, "monZone": w.monsoonZone, "forest0": w.forest, "heavy": w.heavySoil, "mal": w.malaria, "oncho": w.oncho, "circ": w.circumscription, "nT": w.nicheTemperature, "nM": w.nicheMoisture, "nN": w.nicheLifestyle, "nD": w.nicheDisease}
	var wf []float32
	for _, v := range w.weatherFractions {
		wf = append(wf, v[:]...)
	}
	floats["wf"] = wf
	for name, values := range floats {
		want := f.Output[name]
		if len(values) != len(want) {
			t.Fatalf("%s length differs", name)
		}
		for i, v := range values {
			if math.Abs(float64(v)-want[i]) > math.Max(2e-6, math.Abs(want[i])*3e-7) {
				t.Fatalf("%s[%d]=%g, JS=%g", name, i, v, want[i])
			}
		}
	}
	ints := map[string][]int64{}
	for i := 0; i < n; i++ {
		for _, j := range w.neighbors[i] {
			ints["nb"] = append(ints["nb"], int64(j))
		}
		for _, j := range w.weatherIndices[i] {
			ints["wi"] = append(ints["wi"], int64(j))
		}
		for k, v := range map[string]int64{"lm": int64(w.landmass[i]), "down": int64(w.down[i]), "biome": int64(w.biome[i]), "tcost": int64(w.travelCost[i])} {
			ints[k] = append(ints[k], v)
		}
		for k, v := range map[string]bool{"coast": w.coast[i], "nomad": w.nomad[i], "tsetse": w.tsetse[i], "desert": w.desert[i]} {
			b := int64(0)
			if v {
				b = 1
			}
			ints[k] = append(ints[k], b)
		}
	}
	for _, v := range w.landmassSizes {
		ints["lmSize"] = append(ints["lmSize"], int64(v))
	}
	for _, v := range w.drainageOrder {
		ints["order"] = append(ints["order"], int64(v))
	}
	for _, v := range w.seaOffsets {
		ints["ls"] = append(ints["ls"], int64(v))
	}
	for k, v := range w.seaTargets {
		ints["lt"] = append(ints["lt"], int64(v))
		ints["ld"] = append(ints["ld"], int64(w.seaDistances[k]))
	}
	for name, values := range ints {
		want := f.Output[name]
		if len(values) != len(want) {
			t.Fatalf("%s length %d, want %d", name, len(values), len(want))
		}
		for i, v := range values {
			if float64(v) != want[i] {
				t.Fatalf("%s[%d]=%d, JS=%g", name, i, v, want[i])
			}
		}
	}
	// prepEco idempotence and an explicit n8 corner/seam order.
	before := w.Digest()
	w.prepareEcology()
	if w.Digest() != before {
		t.Fatal("prepEco ran twice")
	}
	var corner []CellID
	w.visit8(0, func(j CellID) { corner = append(corner, j) })
	if !reflect.DeepEqual(corner, []CellID{15, 1, 31, 16, 17}) {
		t.Fatalf("corner n8 order: %v", corner)
	}
}

func TestGeographyAndEcologyInvariants(t *testing.T) {
	for _, seed := range []string{"Asabiya", "rivers", "🌍"} {
		w, err := GenerateWorld(smallConfig(seed))
		if err != nil {
			t.Fatal(err)
		}
		assertGeographyInvariants(t, w)
	}
}

func assertGeographyInvariants(t *testing.T, w *World) {
	t.Helper()
	rank := make([]int, w.Len())
	for i := range rank {
		rank[i] = -1
	}
	for k, id := range w.drainageOrder {
		if id < 0 || int(id) >= w.Len() || !w.land[id] || rank[id] >= 0 {
			t.Fatal("invalid drainage order")
		}
		rank[id] = k
	}
	if len(w.drainageOrder) != w.landCells || !w.ecoReady {
		t.Fatal("incomplete geography/ecology")
	}
	for i := 0; i < w.Len(); i++ {
		c, _ := w.Cell(CellID(i))
		e := c.Ecology
		d := c.Drainage
		g := c.Geometry
		for _, f := range []float32{g.X3, g.Y3, g.Z3, g.CosLongitude, g.SinLongitude, g.CosLatitude, d.FilledElevation, d.Accumulation, d.River, e.Farming, e.Herding, e.GrowingSeason, e.Leaching, e.Tropical, e.MonsoonZone, e.InitialForest, e.HeavySoil, e.Malaria, e.Onchocerciasis, e.Circumscription, e.Niche[0], e.Niche[1], e.Niche[2], e.Niche[3]} {
			if math.IsNaN(float64(f)) || math.IsInf(float64(f), 0) {
				t.Fatalf("nonfinite cell %d", i)
			}
		}
		for _, f := range []float32{d.River, e.Farming, e.Herding, e.Leaching, e.Tropical, e.MonsoonZone, e.InitialForest, e.HeavySoil, e.Malaria, e.Onchocerciasis, e.Circumscription} {
			if f < 0 || f > 1 {
				t.Fatalf("fraction out of range in cell %d: %g", i, f)
			}
		}
		if e.GrowingSeason < 0 || e.GrowingSeason > 12 || g.CosLatitude < .2 || g.CosLatitude > 1 || int(g.GridX) != c.X || int(g.GridY) != c.Y {
			t.Fatal("invalid geometry/season")
		}
		norm := float64(g.X3)*float64(g.X3) + float64(g.Y3)*float64(g.Y3) + float64(g.Z3)*float64(g.Z3)
		if math.Abs(norm-1) > 2e-6 {
			t.Fatal("nonunit sphere coordinate")
		}
		if c.Land {
			if e.Biome < 1 || e.Biome > 9 || e.TravelCost < 1 || e.TravelCost > 20 || d.Downstream < 0 || int(d.Downstream) >= w.Len() || d.FilledElevation < c.Elevation {
				t.Fatalf("invalid land drainage/ecology: %+v", c)
			}
			adjacent := false
			w.visit8(c.ID, func(j CellID) {
				if j == d.Downstream {
					adjacent = true
				}
			})
			if !adjacent {
				t.Fatal("downstream not n8 adjacent")
			}
			if w.land[d.Downstream] {
				if rank[d.Downstream] >= rank[i] || w.filled[d.Downstream] >= w.filled[i] || w.accumulation[d.Downstream] < w.accumulation[i] {
					t.Fatal("drainage cycle or lost accumulation")
				}
			} else if !c.Coast {
				t.Fatal("noncoast outlet")
			}
			if e.Desert != (e.Biome == Desert) {
				t.Fatal("desert/biome mismatch")
			}
		} else if e.Biome != Ocean || e.TravelCost != 0 || d.Downstream != NoCell || d.River != 0 || e.InitialForest != 0 || e.Malaria != 0 {
			t.Fatal("ocean has land mechanics")
		}
		for _, index := range c.Weather.Indices {
			if index < 0 || index >= WeatherGridWidth*WeatherGridHeight {
				t.Fatal("weather index invalid")
			}
		}
		for _, fraction := range c.Weather.Fractions {
			if fraction < 0 || fraction >= 1 {
				t.Fatal("invalid weather fraction")
			}
		}
		links, ok := w.SeaLinks(c.ID)
		if !ok || len(links) > 10 || (!c.Coast && len(links) > 0) {
			t.Fatal("invalid sea links")
		}
		seen := map[CellID]bool{}
		lastOther, lastDist := true, uint8(0)
		for _, l := range links {
			if l.Target == c.ID || l.Target < 0 || int(l.Target) >= w.Len() || !w.coast[l.Target] || seen[l.Target] || l.Distance < 2 || l.Distance > 6 {
				t.Fatal("invalid sea link target/distance")
			}
			seen[l.Target] = true
			other := w.landmass[l.Target] != w.landmass[i]
			if (!lastOther && other) || (other == lastOther && l.Distance < lastDist) {
				t.Fatal("sea link priority changed")
			}
			lastOther, lastDist = other, l.Distance
			if w.Len() <= 1152 && !reachableBySea(w, c.ID, l) {
				t.Fatal("sea link has no water path at recorded depth")
			}
		}
	}
	if _, ok := w.SeaLinks(NoCell); ok {
		t.Fatal("accepted negative sea source")
	}
	order := w.DrainageOrder()
	if len(order) > 0 {
		order[0] = NoCell
		if w.drainageOrder[0] == NoCell {
			t.Fatal("drainage order mutable")
		}
	}
}

func TestDefaultGoldenAndGeography(t *testing.T) {
	w, err := GenerateWorld(DefaultWorldConfig("Asabiya"))
	if err != nil {
		t.Fatal(err)
	}
	assertGeographyInvariants(t, w)
	data, err := os.ReadFile("../../tests/native/world-v1.windows-go1.27.2.json")
	if err != nil {
		t.Fatal(err)
	}
	var base BaseWorldSummary
	if err := json.Unmarshal(data, &base); err != nil {
		t.Fatal(err)
	}
	if got := w.BaseSummary(); got != base {
		t.Fatalf("previous golden changed: %+v", got)
	}
	data, err = os.ReadFile("../../tests/native/world-v2.windows-go1.27.2.json")
	if err != nil {
		t.Fatal(err)
	}
	var want WorldSummary
	if err := json.Unmarshal(data, &want); err != nil {
		t.Fatal(err)
	}
	if got := w.Summary(); got != want {
		t.Fatalf("geography golden changed: %+v", got)
	}
}

func TestFineSurfaceDoesNotChangeSimulation(t *testing.T) {
	c := smallConfig("detail")
	w, surface, err := GenerateWorldWithSurface(c)
	if err != nil {
		t.Fatal(err)
	}
	coarse, err := GenerateWorld(c)
	if err != nil {
		t.Fatal(err)
	}
	if w.Digest() != coarse.Digest() || w.RNGPosition() != coarse.RNGPosition() {
		t.Fatal("visual retention changed simulation/RNG")
	}
	width, height := surface.Size()
	if width != c.Width*c.Detail || height != c.Height*c.Detail || surface.Bytes() != width*height*16 {
		t.Fatal("wrong fine layer dimensions/memory")
	}
	if _, ok := surface.At(-1, 0); ok {
		t.Fatal("accepted negative fine coordinates")
	}
	if _, ok := surface.At(width, 0); ok {
		t.Fatal("accepted past-end fine coordinates")
	}
	for y := 0; y < c.Height; y++ {
		for x := 0; x < c.Width; x++ {
			temp, prec, amp := 0.0, 0.0, 0.0
			for dy := 0; dy < c.Detail; dy++ {
				for dx := 0; dx < c.Detail; dx++ {
					s, ok := surface.At(x*c.Detail+dx, y*c.Detail+dy)
					if !ok {
						t.Fatal("missing fine sample")
					}
					temp += float64(s.Temperature)
					prec += float64(s.Precipitation)
					amp += float64(s.SeasonalAmplitude)
				}
			}
			cell, _ := w.Cell(CellID(y*c.Width + x))
			count := float64(c.Detail * c.Detail)
			if float32(temp/count) != cell.Temperature || float32(prec/count) != cell.Precipitation || float32(amp/count) != cell.SeasonalAmplitude {
				t.Fatal("fine/coarse climate mismatch")
			}
		}
	}
	first, _ := surface.At(0, 0)
	first.Elevation = 99999
	again, _ := surface.At(0, 0)
	if again.Elevation == 99999 {
		t.Fatal("fine surface mutable")
	}
}

// Independent layered water traversal checks that each selected link really
// has a legacy path (four first steps, then n8, two..six water cells).
func reachableBySea(w *World, source CellID, link SeaLink) bool {
	front := map[CellID]bool{}
	for _, j := range w.neighbors[source] {
		if j >= 0 && !w.land[j] {
			front[j] = true
		}
	}
	for depth := uint8(1); depth <= link.Distance; depth++ {
		next := map[CellID]bool{}
		found := false
		for id := range front {
			w.visit8(id, func(j CellID) {
				if j == link.Target && depth == link.Distance {
					found = true
				}
				if !w.land[j] {
					next[j] = true
				}
			})
		}
		if found {
			return true
		}
		front = next
	}
	return false
}

func TestBiomeThresholds(t *testing.T) {
	for _, c := range []struct {
		t, p float64
		want Biome
	}{{-9.01, 1000, Ice}, {-9, 1000, Tundra}, {-1, 249, Tundra}, {-1, 250, BorealForest}, {5, 189, Desert}, {5, 190, Steppe}, {10, 459, Steppe}, {10, 460, Grassland}, {10, 700, TemperateForest}, {20, 1299, Savanna}, {20, 1300, TropicalForest}} {
		if got := biomeOf(c.t, c.p); got != c.want {
			t.Fatalf("biome(%g,%g)=%d want %d", c.t, c.p, got, c.want)
		}
	}
}
