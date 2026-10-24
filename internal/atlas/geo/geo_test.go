package geo

import (
	"math"
	"testing"
)

func near(t *testing.T, name string, got, want, tol float64) {
	t.Helper()
	if math.Abs(got-want) > tol {
		t.Fatalf("%s = %v, want %v ± %v", name, got, want, tol)
	}
}

func TestProjectRoundTripAndWrap(t *testing.T) {
	for _, p := range []LonLat{{2.35, 48.85}, {-179.9, 10}, {179.99, -80}, {0, 0}, {-12, 72}} {
		q := Unproject(Project(p))
		near(t, "lon", q.Lon, p.Lon, 1e-9)
		near(t, "lat", q.Lat, p.Lat, 1e-9)
	}
	near(t, "lon 190", NormLon(190), -170, 1e-12)
	near(t, "lon -540", NormLon(-540), -180, 1e-12)
	if Project(LonLat{180, 0}).X != Project(LonLat{-180, 0}).X {
		t.Fatal("±180 must project to the same X")
	}
}

func TestDistanceKnown(t *testing.T) {
	paris, rome := LonLat{2.3522, 48.8566}, LonLat{12.4964, 41.9028}
	near(t, "Paris-Rome km", DistanceKm(paris, rome), 1105, 10)
	near(t, "antimeridian", DistanceKm(LonLat{179.5, 0}, LonLat{-179.5, 0}), 111.19, 0.1)
	near(t, "quarter meridian", DistanceKm(LonLat{0, 0}, LonLat{0, 90}), math.Pi*EarthRadiusKm/2, 1e-6)
}

func TestRingArea(t *testing.T) {
	// 1°x1° at the equator on the sphere: (π/180)²·R²·cos(0.5°) ≈ 12364 km²; unaffected by crossing 180°.
	a := RingAreaKm2([]LonLat{{0, 0}, {1, 0}, {1, 1}, {0, 1}})
	b := RingAreaKm2([]LonLat{{179.5, 0}, {-179.5, 0}, {-179.5, 1}, {179.5, 1}})
	near(t, "1deg cell", a, math.Pow(math.Pi/180, 2)*EarthRadiusKm*EarthRadiusKm*math.Cos(0.5*math.Pi/180), 1)
	near(t, "crossing", b, a, 1e-6)
}

func TestCameraRoundTripAndZoomAnchor(t *testing.T) {
	c := Camera{Center: Project(LonLat{10, 50}), Scale: 4000, ViewW: 1280, ViewH: 720}
	m := Project(LonLat{2.35, 48.85})
	x, y := c.ToScreen(m)
	back := c.ToMap(x, y)
	near(t, "x", back.X, m.X, 1e-9)
	near(t, "y", back.Y, m.Y, 1e-9)
	// zoom keeps the point under the cursor
	under := c.ToMap(300, 200)
	z := c.ZoomAt(300, 200, 3.7)
	after := z.ToMap(300, 200)
	near(t, "anchor x", after.X, under.X, 1e-9)
	near(t, "anchor y", after.Y, under.Y, 1e-9)
	// camera near the antimeridian: both sides land on screen without a jump
	e := Camera{Center: Project(LonLat{179.9, 0}), Scale: 4000, ViewW: 1280, ViewH: 720}
	x1, _ := e.ToScreen(Project(LonLat{179.8, 0}))
	x2, _ := e.ToScreen(Project(LonLat{-179.8, 0}))
	if math.Abs(x2-x1) > 100 {
		t.Fatalf("antimeridian jump: %v vs %v", x1, x2)
	}
}

func TestBBox(t *testing.T) {
	eu := BBox{-12, 29, 45, 72}
	if !eu.Contains(LonLat{2.35, 48.85}) || eu.Contains(LonLat{-18, 65}) || eu.Contains(LonLat{10, 20}) {
		t.Fatal("europe bbox")
	}
	pac := BBox{170, -20, -170, 20}
	if !pac.Contains(LonLat{179, 0}) || !pac.Contains(LonLat{-179, 0}) || pac.Contains(LonLat{0, 0}) {
		t.Fatal("antimeridian bbox")
	}
}
