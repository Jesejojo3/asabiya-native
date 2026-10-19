package sim

import "math"

// drainHeap is a direct port of hpush/hpop, including tie behavior. It is NOT
// a stable priority queue: equal keys do not bubble; pop replaces the root with
// the last entry, then only strictly smaller children can swap. Adding an ID
// tie breaker, or using container/heap, would change the river network.
type drainHeap struct {
	keys []float64
	ids  []CellID
}

func (h *drainHeap) push(id CellID, key float64) {
	n := len(h.keys)
	h.keys = append(h.keys, key)
	h.ids = append(h.ids, id)
	for n > 0 {
		p := (n - 1) >> 1
		if h.keys[p] <= h.keys[n] {
			break
		}
		h.keys[p], h.keys[n] = h.keys[n], h.keys[p]
		h.ids[p], h.ids[n] = h.ids[n], h.ids[p]
		n = p
	}
}
func (h *drainHeap) pop() CellID {
	top := h.ids[0]
	last := len(h.keys) - 1
	key, id := h.keys[last], h.ids[last]
	h.keys = h.keys[:last]
	h.ids = h.ids[:last]
	if last > 0 {
		h.keys[0] = key
		h.ids[0] = id
		n := 0
		for {
			left, right, m := 2*n+1, 2*n+2, n
			if left < len(h.keys) && h.keys[left] < h.keys[m] {
				m = left
			}
			if right < len(h.keys) && h.keys[right] < h.keys[m] {
				m = right
			}
			if m == n {
				break
			}
			h.keys[m], h.keys[n] = h.keys[n], h.keys[m]
			h.ids[m], h.ids[n] = h.ids[n], h.ids[m]
			n = m
		}
	}
	return top
}

type Drainage struct {
	Downstream      CellID  `json:"down"`
	FilledElevation float32 `json:"filledElevationMeters"`
	Accumulation    float32 `json:"accumulation"`
	River           float32 `json:"river"`
}

func (w *World) prepareDrainage() {
	n := w.Len()
	w.filled = make([]float32, n)
	w.down = make([]CellID, n)
	visited := make([]bool, n)
	h := drainHeap{}
	w.drainageOrder = make([]CellID, 0, w.landCells)
	for i := 0; i < n; i++ {
		w.down[i] = NoCell
		visited[i] = !w.land[i]
	}
	// coastList and landList in the original are row-major, as these loops are.
	for i := 0; i < n; i++ {
		if !w.coast[i] {
			continue
		}
		w.filled[i] = w.elevation[i]
		visited[i] = true
		outlet := NoCell
		w.visit8(CellID(i), func(j CellID) {
			if !w.land[j] && outlet < 0 {
				outlet = j
			}
		})
		w.down[i] = outlet
		h.push(CellID(i), float64(w.elevation[i]))
	}
	for len(h.keys) > 0 {
		i := h.pop()
		w.drainageOrder = append(w.drainageOrder, i)
		w.visit8(i, func(j CellID) {
			if !visited[j] {
				visited[j] = true
				w.filled[j] = float32(math.Max(float64(w.elevation[j]), float64(w.filled[i])+.01))
				w.down[j] = i
				h.push(j, float64(w.filled[j]))
			}
		})
	}
	w.accumulation = make([]float32, n)
	w.river = make([]float32, n)
	for i := 0; i < n; i++ {
		if !w.land[i] {
			continue
		}
		cold := 1.0
		if w.temperature[i] < -9 {
			cold = .2
		}
		w.accumulation[i] = float32(math.Max(0, float64(w.precipitation[i])-200) * float64(w.area[i]) * 1e-4 * cold)
	}
	for k := len(w.drainageOrder) - 1; k >= 0; k-- {
		i := w.drainageOrder[k]
		d := w.down[i]
		if d >= 0 && w.land[d] {
			w.accumulation[d] = float32(float64(w.accumulation[d]) + float64(w.accumulation[i]))
		}
	}
	for i := 0; i < n; i++ {
		if w.land[i] && w.accumulation[i] > 2500 {
			w.river[i] = float32(clamp(math.Log(float64(w.accumulation[i])/2500)/math.Log(100)+.2, 0, 1))
		}
	}
}

func (w *World) drainage(i int) Drainage {
	return Drainage{Downstream: w.down[i], FilledElevation: w.filled[i], Accumulation: w.accumulation[i], River: w.river[i]}
}

// DrainageOrder returns a copy, preserving construction order without exposing
// mutable backing storage. It includes land only, including coastal outlets.
func (w *World) DrainageOrder() []CellID { return append([]CellID(nil), w.drainageOrder...) }
