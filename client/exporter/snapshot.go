package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

// Snapshot format "asabiya/snapshot-v1" (little endian):
//
//	[0:8)   magic "ASBYSNP1"
//	[8:12)  uint32 header length H
//	[12:12+H) UTF-8 JSON header, padded with spaces so the data blob starts at a
//	        multiple of 16
//	data    concatenated raw layers, each described by header.layers[].offset
//	        (relative to the data blob start) and bytes
//
// The exporter only reads the public, immutable sim API (World.Cell and
// Surface.At). It never mutates the world, advances the simulation or consumes
// RNG, so exporting cannot change any causal result.
const (
	Magic  = "ASBYSNP1"
	Schema = "asabiya/snapshot-v1"
)

var BiomeNames = []string{"Ocean", "Ice", "Tundra", "Boreal forest", "Temperate forest", "Grassland", "Steppe", "Desert", "Savanna", "Tropical forest"}

type Layer struct {
	Name   string `json:"name"`
	Grid   string `json:"grid"` // "cell" (width×height) or "fine" (fineWidth×fineHeight)
	Type   string `json:"type"` // "u8", "i32" or "f32"
	Offset int    `json:"offset"`
	Bytes  int    `json:"bytes"`
	Units  string `json:"units,omitempty"`
}

type WorldInfo struct {
	Seed         string  `json:"seed"`
	Width        int     `json:"width"`
	Height       int     `json:"height"`
	Detail       int     `json:"detail"`
	FineWidth    int     `json:"fineWidth"`
	FineHeight   int     `json:"fineHeight"`
	LandFraction float64 `json:"landFraction"`
	Version      string  `json:"version"`
	Digest       string  `json:"digest"`
	LandCells    int     `json:"landCells"`
	CoastCells   int     `json:"coastCells"`
	Landmasses   int     `json:"landmasses"`
}

type Session struct {
	// Kind is "real" for engine output. The Godot client labels anything else
	// (its own synthetic demo source) as a demonstration.
	Kind        string `json:"kind"`
	Stage       string `json:"stage"`
	Year        int    `json:"year"`
	HistorySeed string `json:"historySeed"`
	Simulation  string `json:"simulationVersion"`
}

type Header struct {
	Schema     string            `json:"schema"`
	Producer   map[string]string `json:"producer"`
	Session    Session           `json:"session"`
	World      WorldInfo         `json:"world"`
	Biomes     []string          `json:"biomes"`
	Layers     []Layer           `json:"layers"`
	DataSHA256 string            `json:"dataSHA256"`
	// Available lists engine systems present in this snapshot. The client shows
	// "not yet available" for anything absent instead of inventing values.
	Available []string `json:"available"`
}

type builder struct {
	data   bytes.Buffer
	layers []Layer
}

func (b *builder) add(name, grid, typ, units string, payload any) {
	for b.data.Len()%16 != 0 {
		b.data.WriteByte(0)
	}
	start := b.data.Len()
	if err := binary.Write(&b.data, binary.LittleEndian, payload); err != nil {
		panic(err) // only fixed-size slices are passed
	}
	b.layers = append(b.layers, Layer{Name: name, Grid: grid, Type: typ, Offset: start, Bytes: b.data.Len() - start, Units: units})
}

func boolByte(v bool) uint8 {
	if v {
		return 1
	}
	return 0
}

// Build serialises the world. surface may be nil, in which case the fine
// layers are omitted and the client falls back to the logical grid.
func Build(w *sim.World, surface *sim.Surface, status sim.SimulationStatus, producer map[string]string) ([]byte, error) {
	if w == nil {
		return nil, errors.New("world is required")
	}
	c := w.Config()
	n := w.Len()
	if n != c.Width*c.Height {
		return nil, fmt.Errorf("world length %d does not match %dx%d", n, c.Width, c.Height)
	}
	u8 := func() []uint8 { return make([]uint8, n) }
	f32 := func() []float32 { return make([]float32, n) }
	land, coast, biome, nomad, desert, tsetse, travel := u8(), u8(), u8(), u8(), u8(), u8(), u8()
	elev, temp, prec, ampl, rough, area := f32(), f32(), f32(), f32(), f32(), f32()
	acc, river, farm, herd, season, forest, heavy, malaria, circ, monsoon := f32(), f32(), f32(), f32(), f32(), f32(), f32(), f32(), f32(), f32()
	landmass, down := make([]int32, n), make([]int32, n)
	info := WorldInfo{Seed: c.Seed, Width: c.Width, Height: c.Height, Detail: c.Detail, LandFraction: c.LandFraction, Version: sim.WorldVersion, Digest: w.Digest()}
	maxLandmass := int32(-1)
	for i := 0; i < n; i++ {
		cell, ok := w.Cell(sim.CellID(i))
		if !ok {
			return nil, fmt.Errorf("cell %d unavailable", i)
		}
		land[i], coast[i] = boolByte(cell.Land), boolByte(cell.Coast)
		biome[i] = uint8(cell.Ecology.Biome)
		nomad[i], desert[i], tsetse[i] = boolByte(cell.Ecology.Nomad), boolByte(cell.Ecology.Desert), boolByte(cell.Ecology.Tsetse)
		travel[i] = cell.Ecology.TravelCost
		elev[i], temp[i], prec[i], ampl[i] = cell.Elevation, cell.Temperature, cell.Precipitation, cell.SeasonalAmplitude
		rough[i], area[i] = cell.Roughness, cell.Area
		acc[i], river[i] = cell.Drainage.Accumulation, cell.Drainage.River
		farm[i], herd[i], season[i] = cell.Ecology.Farming, cell.Ecology.Herding, cell.Ecology.GrowingSeason
		forest[i], heavy[i], malaria[i] = cell.Ecology.InitialForest, cell.Ecology.HeavySoil, cell.Ecology.Malaria
		circ[i], monsoon[i] = cell.Ecology.Circumscription, cell.Ecology.MonsoonZone
		landmass[i], down[i] = cell.Landmass, int32(cell.Drainage.Downstream)
		if cell.Land {
			info.LandCells++
		}
		if cell.Coast {
			info.CoastCells++
		}
		if cell.Landmass > maxLandmass {
			maxLandmass = cell.Landmass
		}
	}
	info.Landmasses = int(maxLandmass) + 1
	b := &builder{}
	b.add("land", "cell", "u8", "bool", land)
	b.add("coast", "cell", "u8", "bool", coast)
	b.add("biome", "cell", "u8", "biome id", biome)
	b.add("nomad", "cell", "u8", "bool", nomad)
	b.add("desert", "cell", "u8", "bool", desert)
	b.add("tsetse", "cell", "u8", "bool", tsetse)
	b.add("travelCost", "cell", "u8", "legacy tcost", travel)
	b.add("elevation", "cell", "f32", "m", elev)
	b.add("temperature", "cell", "f32", "°C", temp)
	b.add("precipitation", "cell", "f32", "mm/yr", prec)
	b.add("seasonalAmplitude", "cell", "f32", "°C", ampl)
	b.add("roughness", "cell", "f32", "0..1", rough)
	b.add("area", "cell", "f32", "km²", area)
	b.add("landmass", "cell", "i32", "id, -1 ocean", landmass)
	b.add("down", "cell", "i32", "CellID, -1 none", down)
	b.add("accumulation", "cell", "f32", "legacy index", acc)
	b.add("river", "cell", "f32", "0..1", river)
	b.add("farming", "cell", "f32", "sF", farm)
	b.add("herding", "cell", "f32", "sH", herd)
	b.add("growingSeason", "cell", "f32", "months", season)
	b.add("forest0", "cell", "f32", "0..1", forest)
	b.add("heavySoil", "cell", "f32", "0..1", heavy)
	b.add("malaria", "cell", "f32", "0..1", malaria)
	b.add("circumscription", "cell", "f32", "0..1", circ)
	b.add("monsoonZone", "cell", "f32", "0..1", monsoon)
	if surface != nil {
		fw, fh := surface.Size()
		if fw != c.Width*c.Detail || fh != c.Height*c.Detail {
			return nil, fmt.Errorf("surface %dx%d does not match world detail", fw, fh)
		}
		info.FineWidth, info.FineHeight = fw, fh
		fe, ft, fp := make([]float32, fw*fh), make([]float32, fw*fh), make([]float32, fw*fh)
		for y := 0; y < fh; y++ {
			for x := 0; x < fw; x++ {
				s, _ := surface.At(x, y)
				k := y*fw + x
				fe[k], ft[k], fp[k] = s.Elevation, s.Temperature, s.Precipitation
			}
		}
		b.add("elevationFine", "fine", "f32", "m", fe)
		b.add("temperatureFine", "fine", "f32", "°C", ft)
		b.add("precipitationFine", "fine", "f32", "mm/yr", fp)
	}
	for name, v := range map[string][]float32{"elevation": elev, "temperature": temp, "precipitation": prec} {
		for _, f := range v {
			if math.IsNaN(float64(f)) || math.IsInf(float64(f), 0) {
				return nil, fmt.Errorf("non-finite value in %s", name)
			}
		}
	}
	sum := sha256.Sum256(b.data.Bytes())
	h := Header{Schema: Schema, Producer: producer, World: info, Biomes: BiomeNames, Layers: b.layers, DataSHA256: hex.EncodeToString(sum[:]),
		Session:   Session{Kind: "real", Stage: status.Stage, Year: status.Year, HistorySeed: status.HistorySeed, Simulation: status.Version},
		Available: []string{"geography", "climate", "drainage", "ecology"}}
	js, err := json.Marshal(h)
	if err != nil {
		return nil, err
	}
	for (12+len(js))%16 != 0 {
		js = append(js, ' ')
	}
	var out bytes.Buffer
	out.WriteString(Magic)
	_ = binary.Write(&out, binary.LittleEndian, uint32(len(js)))
	out.Write(js)
	out.Write(b.data.Bytes())
	return out.Bytes(), nil
}

// Read parses and verifies a snapshot. It is used by tests and by tooling that
// wants to inspect a file without Godot.
func Read(r io.Reader) (Header, []byte, error) {
	var h Header
	all, err := io.ReadAll(r)
	if err != nil {
		return h, nil, err
	}
	if len(all) < 12 || string(all[:8]) != Magic {
		return h, nil, errors.New("not an Asabiya snapshot")
	}
	hl := int(binary.LittleEndian.Uint32(all[8:12]))
	if hl <= 0 || 12+hl > len(all) {
		return h, nil, errors.New("truncated header")
	}
	if err := json.Unmarshal(all[12:12+hl], &h); err != nil {
		return h, nil, err
	}
	if h.Schema != Schema {
		return h, nil, fmt.Errorf("unsupported schema %q", h.Schema)
	}
	data := all[12+hl:]
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != h.DataSHA256 {
		return h, nil, errors.New("data checksum mismatch")
	}
	for _, l := range h.Layers {
		if l.Offset < 0 || l.Offset+l.Bytes > len(data) {
			return h, nil, fmt.Errorf("layer %s out of range", l.Name)
		}
	}
	return h, data, nil
}
