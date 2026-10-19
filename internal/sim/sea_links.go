package sim

import "sort"

type SeaLink struct {
	Target   CellID `json:"target"`
	Distance uint8  `json:"distance"` // legacy dc, not a geometric distance
}

func (w *World) prepareSeaLinks() {
	n := w.Len()
	w.seaOffsets = make([]int32, n+1)
	seen := make([]CellID, n)
	for i := range seen {
		seen[i] = NoCell
	}
	depth := make([]uint8, n)
	q := make([]CellID, n)
	for i := 0; i < n; i++ {
		w.seaOffsets[i] = int32(len(w.seaTargets))
		if !w.coast[i] {
			continue
		}
		source := CellID(i)
		head, tail := 0, 0
		found := make([]SeaLink, 0)
		for _, j := range w.neighbors[i] {
			if j >= 0 && !w.land[j] && seen[j] != source {
				seen[j] = source
				q[tail] = j
				tail++
				depth[j] = 1
			}
		}
		for head < tail {
			cell := q[head]
			head++
			dc := depth[cell]
			w.visit8(cell, func(j CellID) {
				if seen[j] == source {
					return
				}
				seen[j] = source
				if w.land[j] {
					if j != source && dc >= 2 && w.coast[j] {
						found = append(found, SeaLink{Target: j, Distance: dc})
					}
				} else if dc < 6 {
					depth[j] = dc + 1
					q[tail] = j
					tail++
				}
			})
		}
		// ECMAScript sort is stable. Different landmasses first, then dc;
		// equal keys retain discovery order from the original queue/n8.
		sort.SliceStable(found, func(a, b int) bool {
			da, db := w.landmass[found[a].Target] != w.landmass[i], w.landmass[found[b].Target] != w.landmass[i]
			if da != db {
				return da
			}
			return found[a].Distance < found[b].Distance
		})
		for _, link := range found[:min(10, len(found))] {
			w.seaTargets = append(w.seaTargets, link.Target)
			w.seaDistances = append(w.seaDistances, link.Distance)
		}
	}
	w.seaOffsets[n] = int32(len(w.seaTargets))
}

// SeaLinks returns a copy; a valid noncoastal cell has an empty list. Legacy
// links need not be reciprocal because each source selects at most ten.
func (w *World) SeaLinks(id CellID) ([]SeaLink, bool) {
	i := int(id)
	if i < 0 || i >= w.Len() {
		return nil, false
	}
	start, end := w.seaOffsets[i], w.seaOffsets[i+1]
	links := make([]SeaLink, end-start)
	for k := start; k < end; k++ {
		links[k-start] = SeaLink{Target: w.seaTargets[k], Distance: w.seaDistances[k]}
	}
	return links, true
}
