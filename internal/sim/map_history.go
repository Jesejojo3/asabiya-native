package sim

import "math"

// A compressed map record, not a full simulation save/restore format.
type mapHistory struct {
	keys, diffs orderedMap[int, []int32]
	layers      orderedMap[int, *MapLayer]
	last        []int32
}
type MapLayer struct {
	Year                   int
	People                 []int32
	Religion               []int16
	Density, Cohesion, Era []uint8
}

func (h *history) snapshot() {
	land, year := h.world.landList, h.year
	cur := make([]int32, len(land))
	for k, i := range land {
		cur[k] = h.pol[i]
	}
	record := &h.snapshots
	if record.last == nil || (year-h.start)%500 == 0 {
		record.keys.Set(year, cur)
	} else {
		changes := []int32{}
		for k, v := range cur {
			if record.last[k] != v {
				changes = append(changes, int32(k), v)
			}
		}
		record.diffs.Set(year, changes)
	}
	record.last = cur
	if (year-h.start)%50 != 0 {
		return
	}
	layer := &MapLayer{Year: year, People: make([]int32, len(land)), Religion: make([]int16, len(land)), Density: make([]uint8, len(land)), Cohesion: make([]uint8, len(land)), Era: make([]uint8, len(land))}
	for k, i := range land {
		p := float64(h.pop[i])
		on := p >= 1
		layer.Religion[k] = -1
		layer.Era[k] = 255
		if on {
			if h.eth[i] >= 0 {
				layer.People[k] = h.eth[i] + 1
			}
			layer.Religion[k] = int16(h.religion[i])
			layer.Density[k] = uint8(clamp(jsRound((math.Log10(p/float64(h.world.area[i]))+2)*63), 1, 255))
			layer.Era[k] = uint8(h.eraOf(int(i)))
		}
		layer.Cohesion[k] = uint8(jsRound(float64(h.cohesion[i]) * 255))
	}
	record.layers.Set(year, layer)
	old := year - 1500
	if record.layers.Has(old) && (old-h.start)%250 != 0 {
		record.layers.Delete(old)
	}
}
func (h *history) polAt(year int) []int32 {
	target := h.start + int(math.Floor(float64(year-h.start)/10))*10
	if target < h.start {
		target = h.start
	}
	key := target
	for key >= h.start && !h.snapshots.keys.Has(key) {
		key -= 10
	}
	if key < h.start {
		return nil
	}
	out := append([]int32(nil), h.snapshots.keys.Value(key)...)
	for y := key + 10; y <= target; y += 10 {
		if values, ok := h.snapshots.keys.Get(y); ok {
			copy(out, values)
			continue
		}
		changes := h.snapshots.diffs.Value(y)
		for k := 0; k < len(changes); k += 2 {
			out[changes[k]] = changes[k+1]
		}
	}
	return out
}

// layerAt is private and returns the owned record. The query layer must clone
// slices before exposing it to a frontend or caller.
func (h *history) layerAt(year int) *MapLayer {
	var best *MapLayer
	h.snapshots.layers.Each(func(y int, layer *MapLayer) {
		if y <= year && (best == nil || y > best.Year) {
			best = layer
		}
	})
	return best
}
