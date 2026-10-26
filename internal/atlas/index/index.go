// Package index answers "which atlas unit is under this lon/lat" without
// scanning every unit: a 1-degree bucket grid narrows candidates by bounding
// box and an even-odd ray test decides. It reads the files written by
// tools/atlas/units.py and is renderer-neutral.
package index

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"

	"github.com/Jesejojo3/asabiya-native/internal/atlas/geo"
)

// Unit is a stable geographic unit. It carries no political meaning.
type Unit struct {
	ID         string
	BBox       geo.BBox
	AreaKm2    float64
	Coastal    bool
	Island     bool
	Neighbours []string
	DrainsTo   []string
	Rings      [][]geo.LonLat // outer rings and holes, even-odd
}

// Index is immutable after Load and safe for concurrent reads.
type Index struct {
	Schema  string
	units   map[string]*Unit
	ids     []string
	buckets map[[2]int][]*Unit
}

type unitsFile struct {
	Meta  struct{ Schema string } `json:"meta"`
	Units []struct {
		ID         string    `json:"id"`
		AreaKm2    float64   `json:"areaKm2"`
		BBox       []float64 `json:"bbox"`
		Coastal    bool      `json:"coastal"`
		Island     bool      `json:"island"`
		Neighbours []struct {
			Unit string `json:"unit"`
		} `json:"neighbours"`
		DrainsTo []string `json:"drainsTo"`
	} `json:"units"`
}

type geomFile struct {
	Scale float64                 `json:"scale"`
	Rings map[string][][][2]int64 `json:"rings"`
}

// Load reads units.json and units_geom.json from dir.
func Load(dir string) (*Index, error) {
	var uf unitsFile
	var gf geomFile
	for name, dst := range map[string]any{"units.json": &uf, "units_geom.json": &gf} {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(b, dst); err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
	}
	if gf.Scale <= 0 {
		return nil, fmt.Errorf("units_geom.json: missing scale")
	}
	ix := &Index{Schema: uf.Meta.Schema, units: map[string]*Unit{}, buckets: map[[2]int][]*Unit{}}
	for _, u := range uf.Units {
		if len(u.BBox) != 4 {
			return nil, fmt.Errorf("unit %s: bad bbox", u.ID)
		}
		if _, dup := ix.units[u.ID]; dup {
			return nil, fmt.Errorf("duplicate unit %s", u.ID)
		}
		rings, ok := gf.Rings[u.ID]
		if !ok || len(rings) == 0 {
			return nil, fmt.Errorf("unit %s has no geometry", u.ID)
		}
		x := &Unit{ID: u.ID, AreaKm2: u.AreaKm2, Coastal: u.Coastal, Island: u.Island, DrainsTo: u.DrainsTo,
			BBox: geo.BBox{West: u.BBox[0], South: u.BBox[1], East: u.BBox[2], North: u.BBox[3]}}
		for _, n := range u.Neighbours {
			x.Neighbours = append(x.Neighbours, n.Unit)
		}
		for _, r := range rings {
			if len(r) < 4 || r[0] != r[len(r)-1] {
				return nil, fmt.Errorf("unit %s: ring not closed", u.ID)
			}
			ring := make([]geo.LonLat, len(r))
			for i, p := range r {
				ring[i] = geo.LonLat{Lon: float64(p[0]) / gf.Scale, Lat: float64(p[1]) / gf.Scale}
			}
			x.Rings = append(x.Rings, ring)
		}
		ix.units[u.ID] = x
		ix.ids = append(ix.ids, u.ID)
	}
	sort.Strings(ix.ids)
	for _, id := range ix.ids {
		u := ix.units[id]
		for bx := int(math.Floor(u.BBox.West)); bx <= int(math.Floor(u.BBox.East)); bx++ {
			for by := int(math.Floor(u.BBox.South)); by <= int(math.Floor(u.BBox.North)); by++ {
				k := [2]int{bx, by}
				ix.buckets[k] = append(ix.buckets[k], u)
			}
		}
	}
	return ix, nil
}

func (ix *Index) Len() int { return len(ix.ids) }

// IDs returns all unit ids in ascending order.
func (ix *Index) IDs() []string { return ix.ids }

func (ix *Index) Unit(id string) (*Unit, bool) { u, ok := ix.units[id]; return u, ok }

// Contains reports whether p is inside u (even-odd over all rings).
func (u *Unit) Contains(p geo.LonLat) bool {
	if p.Lat < u.BBox.South || p.Lat > u.BBox.North || p.Lon < u.BBox.West || p.Lon > u.BBox.East {
		return false
	}
	in := false
	for _, r := range u.Rings {
		for i, j := 0, len(r)-1; i < len(r); j, i = i, i+1 {
			a, b := r[i], r[j]
			if (a.Lat > p.Lat) != (b.Lat > p.Lat) &&
				p.Lon < (b.Lon-a.Lon)*(p.Lat-a.Lat)/(b.Lat-a.Lat)+a.Lon {
				in = !in
			}
		}
	}
	return in
}

// AtAll returns every unit containing p, ascending by id. A valid atlas
// returns at most one; more than one means overlapping geometry.
func (ix *Index) AtAll(p geo.LonLat) []string {
	if !p.Valid() {
		return nil
	}
	p.Lon = geo.NormLon(p.Lon)
	var out []string
	for _, u := range ix.buckets[[2]int{int(math.Floor(p.Lon)), int(math.Floor(p.Lat))}] {
		if u.Contains(p) {
			out = append(out, u.ID)
		}
	}
	sort.Strings(out)
	return out
}

// At returns the unit under p. Ties on a shared boundary resolve to the
// smallest id so the answer never depends on iteration order.
func (ix *Index) At(p geo.LonLat) (string, bool) {
	all := ix.AtAll(p)
	if len(all) == 0 {
		return "", false
	}
	return all[0], true
}
