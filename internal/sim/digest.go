package sim

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"github.com/Jesejojo3/asabiya-native/internal/rng"
	"hash"
	"math"
)

const BaseWorldVersion = "native/world-v1"

// BaseWorldSummary is the frozen Block 1 projection. Its data/digest and the
// previous golden remain checked independently of added Block 2 layers.
type BaseWorldSummary struct {
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

func (w *World) BaseSummary() BaseWorldSummary {
	lo, hi := w.elevation[0], w.elevation[0]
	for _, e := range w.elevation {
		lo = min(lo, e)
		hi = max(hi, e)
	}
	return BaseWorldSummary{Version: BaseWorldVersion, Config: w.config, Cells: w.Len(), LandCells: w.landCells, CoastCells: w.coastCells, Landmasses: len(w.landmassSizes), MinElevation: lo, MaxElevation: hi, GenerationRNG: w.position, SHA256: w.BaseDigest()}
}

// Digest v1 is a native regression fingerprint, not a save format or the legacy
// oracle hash. Integers/floats are little-endian, including signed zero bits.
// Seed lengths are explicit; arrays use row-major order, never Go map order.
func (w *World) BaseDigest() string {
	h := sha256.New()
	writeString(h, BaseWorldVersion)
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

type WorldSummary struct {
	BaseWorldSummary
	BaseSHA256   string  `json:"baseSHA256"`
	RiverCells   int     `json:"riverCells"`
	SeaLinkCount int     `json:"seaLinks"`
	BiomeCounts  [10]int `json:"biomeCounts"`
	EcoReady     bool    `json:"ecoReady"`
	AnomalyGrid  [2]int  `json:"anomalyGrid"`
}

func (w *World) Summary() WorldSummary {
	b := w.BaseSummary()
	baseHash := b.SHA256
	b.Version = WorldVersion
	b.SHA256 = w.Digest()
	s := WorldSummary{BaseWorldSummary: b, BaseSHA256: baseHash, SeaLinkCount: len(w.seaTargets), EcoReady: w.ecoReady, AnomalyGrid: [2]int{WeatherGridWidth, WeatherGridHeight}}
	for i := 0; i < w.Len(); i++ {
		s.BiomeCounts[w.biome[i]]++
		if w.river[i] > 0 {
			s.RiverCells++
		}
	}
	return s
}

// Digest v2 extends the frozen base fingerprint, not its fixtures. It covers all
// persisted new simulation arrays, the heap traversal order and CSR link order.
// Optional Surface belongs to presentation, so retaining it cannot change this.
func (w *World) Digest() string {
	h := sha256.New()
	writeString(h, WorldVersion)
	writeString(h, w.BaseDigest())
	for i := 0; i < w.Len(); i++ {
		for _, a := range [][]float32{w.x3, w.y3, w.z3, w.cosLon, w.sinLon, w.cosLat, w.filled, w.accumulation, w.river, w.farmSuitability, w.herdSuitability, w.growingSeason, w.leach, w.tropical, w.monsoonZone, w.forest, w.heavySoil, w.malaria, w.oncho, w.circumscription, w.nicheTemperature, w.nicheMoisture, w.nicheLifestyle, w.nicheDisease} {
			writeU32(h, math.Float32bits(a[i]))
		}
		writeU32(h, uint32(w.down[i]))
		writeU32(h, uint32(w.biome[i]))
		writeU32(h, uint32(w.travelCost[i]))
		flags := uint32(0)
		if w.nomad[i] {
			flags |= 1
		}
		if w.tsetse[i] {
			flags |= 2
		}
		if w.desert[i] {
			flags |= 4
		}
		writeU32(h, flags)
		for _, idx := range w.weatherIndices[i] {
			writeU32(h, uint32(idx))
		}
		for _, f := range w.weatherFractions[i] {
			writeU32(h, math.Float32bits(f))
		}
	}
	writeU64(h, uint64(len(w.drainageOrder)))
	for _, id := range w.drainageOrder {
		writeU32(h, uint32(id))
	}
	for _, offset := range w.seaOffsets {
		writeU32(h, uint32(offset))
	}
	writeU64(h, uint64(len(w.seaTargets)))
	for k, id := range w.seaTargets {
		writeU32(h, uint32(id))
		writeU32(h, uint32(w.seaDistances[k]))
	}
	writeU32(h, WeatherGridWidth)
	writeU32(h, WeatherGridHeight)
	if w.ecoReady {
		writeU32(h, 1)
	} else {
		writeU32(h, 0)
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
