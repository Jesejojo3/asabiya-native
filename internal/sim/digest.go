package sim

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"github.com/Jesejojo3/asabiya-native/internal/rng"
	"hash"
	"math"
)

type WorldSummary struct {
	Version       string       `json:"version"`
	Config        WorldConfig  `json:"config"`
	Cells         int          `json:"cells"`
	LandCells     int          `json:"landCells"`
	CoastCells    int          `json:"coastCells"`
	Landmasses    int          `json:"landmasses"`
	MinElevation  float32      `json:"minElevationMeters"`
	MaxElevation  float32      `json:"maxElevationMeters"`
	GenerationRNG rng.Position `json:"generationRNG"`
	SHA256        string       `json:"sha256"`
}

func (w *World) Summary() WorldSummary {
	lo, hi := w.elevation[0], w.elevation[0]
	for _, e := range w.elevation {
		lo = min(lo, e)
		hi = max(hi, e)
	}
	return WorldSummary{Version: WorldVersion, Config: w.config, Cells: w.Len(), LandCells: w.landCells, CoastCells: w.coastCells, Landmasses: len(w.landmassSizes), MinElevation: lo, MaxElevation: hi, GenerationRNG: w.position, SHA256: w.Digest()}
}

// Digest v1 is a native regression fingerprint, not a save format or the legacy
// oracle hash. Integers/floats are little-endian, including signed zero bits.
// Seed lengths are explicit; arrays use row-major order, never Go map order.
func (w *World) Digest() string {
	h := sha256.New()
	writeString(h, WorldVersion)
	writeString(h, w.config.Seed)
	for _, v := range []uint64{uint64(w.config.Width), uint64(w.config.Height), uint64(w.config.Detail), math.Float64bits(w.config.LandFraction), uint64(w.position.Seed), w.position.Calls} {
		writeU64(h, v)
	}
	for i := range w.land {
		for _, a := range [][]float32{w.elevation, w.temperature, w.precipitation, w.amplitude, w.roughness, w.latitude, w.area} {
			writeU32(h, math.Float32bits(a[i]))
		}
		flags := uint32(0)
		if w.land[i] {
			flags |= 1
		}
		if w.coast[i] {
			flags |= 2
		}
		writeU32(h, flags)
		for _, j := range w.neighbors[i] {
			writeU32(h, uint32(j))
		}
		writeU32(h, uint32(w.landmass[i]))
	}
	writeU64(h, uint64(len(w.landmassSizes)))
	for _, n := range w.landmassSizes {
		writeU64(h, uint64(n))
	}
	return hex.EncodeToString(h.Sum(nil))
}

func writeU32(h hash.Hash, v uint32) {
	var b [4]byte
	binary.LittleEndian.PutUint32(b[:], v)
	h.Write(b[:])
}
func writeU64(h hash.Hash, v uint64) {
	var b [8]byte
	binary.LittleEndian.PutUint64(b[:], v)
	h.Write(b[:])
}
func writeString(h hash.Hash, s string) { writeU64(h, uint64(len(s))); h.Write([]byte(s)) }
