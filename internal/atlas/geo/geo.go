// Package geo is the renderer-neutral geodesy and projection layer of the
// Atlas. It imports nothing from the simulation: positions are persistent
// lon/lat in degrees (WGS84 sphere approximation); map space and screen space
// are derived and never stored as identity.
package geo

import "math"

// EarthRadiusKm is the mean radius used by the spherical models below.
// Distances and areas are spherical (error vs. the ellipsoid up to ~0.5%).
const EarthRadiusKm = 6371.0088

// LonLat is a persistent geographic position in degrees.
type LonLat struct{ Lon, Lat float64 }

// MapPoint is projected map space: X in [0,1) wrapping east-west, Y in [0,1]
// with 0 at the north pole. Equirectangular, so X,Y are linear in lon/lat.
type MapPoint struct{ X, Y float64 }

// NormLon wraps a longitude into [-180, 180).
func NormLon(lon float64) float64 {
	l := math.Mod(lon+180, 360)
	if l < 0 {
		l += 360
	}
	return l - 180
}

// Valid reports whether p is finite and its latitude is within [-90, 90].
func (p LonLat) Valid() bool {
	return !math.IsNaN(p.Lon) && !math.IsInf(p.Lon, 0) && p.Lat >= -90 && p.Lat <= 90
}

// Project maps lon/lat to map space. The antimeridian maps to X=0.
func Project(p LonLat) MapPoint {
	return MapPoint{X: (NormLon(p.Lon) + 180) / 360, Y: (90 - p.Lat) / 180}
}

// Unproject is the inverse of Project (X wraps, Y is clamped to the poles).
func Unproject(m MapPoint) LonLat {
	x := m.X - math.Floor(m.X)
	y := math.Min(1, math.Max(0, m.Y))
	return LonLat{Lon: x*360 - 180, Lat: 90 - y*180}
}

// Camera is a view onto map space. Center is a MapPoint; Scale is screen
// pixels per full map width (so zoom is independent of resolution choices).
type Camera struct {
	Center       MapPoint
	Scale        float64
	ViewW, ViewH float64
}

// ToScreen returns the screen position of m, choosing the east-west copy
// nearest to the camera centre so wrapped geometry never jumps.
func (c Camera) ToScreen(m MapPoint) (x, y float64) {
	dx := m.X - c.Center.X
	dx -= math.Round(dx)
	return c.ViewW/2 + dx*c.Scale, c.ViewH/2 + (m.Y-c.Center.Y)*c.Scale
}

// ToMap is the inverse of ToScreen. X is wrapped into [0,1).
func (c Camera) ToMap(x, y float64) MapPoint {
	m := MapPoint{X: c.Center.X + (x-c.ViewW/2)/c.Scale, Y: c.Center.Y + (y-c.ViewH/2)/c.Scale}
	m.X -= math.Floor(m.X)
	return m
}

// ZoomAt scales by factor keeping the geographic point under (x,y) fixed.
func (c Camera) ZoomAt(x, y, factor float64) Camera {
	before := c.ToMap(x, y)
	c.Scale *= factor
	// choose the centre so that `before` lands again on (x,y)
	c.Center.X = before.X - (x-c.ViewW/2)/c.Scale
	c.Center.X -= math.Floor(c.Center.X)
	c.Center.Y = before.Y - (y-c.ViewH/2)/c.Scale
	return c
}

// DistanceKm is the great-circle (haversine) distance.
func DistanceKm(a, b LonLat) float64 {
	r := math.Pi / 180
	dlat, dlon := (b.Lat-a.Lat)*r, (b.Lon-a.Lon)*r
	h := math.Sin(dlat/2)*math.Sin(dlat/2) +
		math.Cos(a.Lat*r)*math.Cos(b.Lat*r)*math.Sin(dlon/2)*math.Sin(dlon/2)
	return 2 * EarthRadiusKm * math.Asin(math.Min(1, math.Sqrt(h)))
}

// RingAreaKm2 is the absolute spherical area of a closed ring (first point
// need not be repeated). Edges are treated as lon/lat-linear segments, which
// is the same convention the atlas uses for stored geometry. Longitude steps
// are unwrapped so rings crossing 180° are handled.
func RingAreaKm2(ring []LonLat) float64 {
	n := len(ring)
	if n < 3 {
		return 0
	}
	r := math.Pi / 180
	sum := 0.0
	for i := 0; i < n; i++ {
		a, b := ring[i], ring[(i+1)%n]
		dl := b.Lon - a.Lon
		dl -= 360 * math.Round(dl/360)
		sum += dl * r * (math.Sin(a.Lat*r) + math.Sin(b.Lat*r)) / 2
	}
	return math.Abs(sum) * EarthRadiusKm * EarthRadiusKm
}

// BBox is a longitude/latitude box. West > East denotes a box crossing 180°.
type BBox struct{ West, South, East, North float64 }

// Contains reports whether p lies in b (inclusive), antimeridian-aware.
func (b BBox) Contains(p LonLat) bool {
	if p.Lat < b.South || p.Lat > b.North {
		return false
	}
	l := NormLon(p.Lon)
	if b.West <= b.East {
		return l >= b.West && l <= b.East
	}
	return l >= b.West || l <= b.East
}
