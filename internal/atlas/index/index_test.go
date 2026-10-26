package index

import (
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/atlas/geo"
)

const dir = "../../../data/atlas/europe-pilot/units-l6"

func load(t testing.TB) *Index {
	t.Helper()
	ix, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	return ix
}

func TestLoadAndCities(t *testing.T) {
	ix := load(t)
	if ix.Len() != 1348 {
		t.Fatalf("units = %d, want 1348", ix.Len())
	}
	// ids from the Python point-in-polygon check done when the units were built
	want := map[string]struct {
		p  geo.LonLat
		id string
	}{
		"Paris":   {geo.LonLat{Lon: 2.35, Lat: 48.85}, "u2060455290"},
		"Madrid":  {geo.LonLat{Lon: -3.7, Lat: 40.4}, "u2060642980"},
		"Roma":    {geo.LonLat{Lon: 12.5, Lat: 41.9}, "u2060015610"},
		"Berlin":  {geo.LonLat{Lon: 13.4, Lat: 52.5}, "u2060355620"},
		"Londres": {geo.LonLat{Lon: -0.12, Lat: 51.5}, "u2060053790"},
		"Viena":   {geo.LonLat{Lon: 16.37, Lat: 48.2}, "u2060477000"},
		"Zurich":  {geo.LonLat{Lon: 8.54, Lat: 47.37}, "u2060491750"},
	}
	for name, c := range want {
		if id, ok := ix.At(c.p); !ok || id != c.id {
			t.Errorf("%s: got %q ok=%v, want %q", name, id, ok, c.id)
		}
	}
	if _, ok := ix.At(geo.LonLat{Lon: 3, Lat: 56}); ok { // North Sea
		t.Error("open sea must not belong to a unit")
	}
	if _, ok := ix.At(geo.LonLat{Lon: 2.35 + 360, Lat: 48.85}); !ok {
		t.Error("longitude must wrap")
	}
}

func TestNoOverlapAndGeometryAgreesWithBBox(t *testing.T) {
	ix := load(t)
	// deterministic pseudo-random points over the pilot box
	s := uint64(88172645463325252)
	next := func() float64 {
		s ^= s << 13
		s ^= s >> 7
		s ^= s << 17
		return float64(s>>11) / (1 << 53)
	}
	inside, multi := 0, 0
	for i := 0; i < 60000; i++ {
		p := geo.LonLat{Lon: -12 + 57*next(), Lat: 29 + 43*next()}
		all := ix.AtAll(p)
		if len(all) > 1 {
			multi++
		}
		if len(all) == 1 {
			inside++
			u, _ := ix.Unit(all[0])
			if !u.BBox.Contains(p) {
				t.Fatalf("%v assigned to %s outside its bbox", p, all[0])
			}
		}
	}
	if multi != 0 {
		t.Fatalf("%d of 60000 points fall in more than one unit", multi)
	}
	if inside < 15000 {
		t.Fatalf("only %d points hit a unit; coverage looks broken", inside)
	}
	t.Logf("%d/60000 sample points in a unit, 0 overlaps", inside)
}

func TestNeighbourSymmetry(t *testing.T) {
	ix := load(t)
	for _, id := range ix.IDs() {
		u, _ := ix.Unit(id)
		for _, n := range u.Neighbours {
			v, ok := ix.Unit(n)
			if !ok {
				t.Fatalf("%s lists unknown neighbour %s", id, n)
			}
			found := false
			for _, b := range v.Neighbours {
				found = found || b == id
			}
			if !found {
				t.Fatalf("%s -> %s is not symmetric", id, n)
			}
		}
	}
}

func BenchmarkAt(b *testing.B) {
	ix := load(b)
	p := geo.LonLat{Lon: 13.4, Lat: 52.5}
	for i := 0; i < b.N; i++ {
		ix.At(p)
	}
}
