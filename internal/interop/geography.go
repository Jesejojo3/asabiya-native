// Package interop writes renderer-neutral local artifacts. It owns no history
// rules and imports no rendering library or Godot project code.
package interop

import (
	"bufio"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

const GeographySchema = "asabiya/geography-v1"

var geographyMagic = [16]byte{'A', 'S', 'A', 'B', 'G', 'E', 'O', 0, 1, 0, 0, 0, 0, 0, 0, 0}

type Grid struct {
	Width  int `json:"width"`
	Height int `json:"height"`
}
type Layer struct {
	Name       string `json:"name"`
	Type       string `json:"type"`
	Components int    `json:"components"`
	Count      int    `json:"count"`
	Offset     int64  `json:"offset"`
	Bytes      int64  `json:"bytes"`
	Grid       string `json:"grid"`
	Units      string `json:"units,omitempty"`
}
type GeographyManifest struct {
	Schema         string          `json:"schema"`
	Engine         string          `json:"engine"`
	WorldVersion   string          `json:"worldVersion"`
	WorldSHA256    string          `json:"worldSHA256"`
	World          sim.WorldConfig `json:"world"`
	Logical        Grid            `json:"logical"`
	Fine           *Grid           `json:"fine"`
	Projection     string          `json:"projection"`
	LongitudeWrap  bool            `json:"longitudeWrap"`
	PolarWrap      bool            `json:"polarWrap"`
	NeighborOrder  [4]string       `json:"neighborOrder"`
	ProvinceID     string          `json:"provinceId"`
	FineProvinceID string          `json:"fineProvinceId"`
	File           string          `json:"file"`
	ByteOrder      string          `json:"byteOrder"`
	Bytes          int64           `json:"bytes"`
	SHA256         string          `json:"sha256"`
	Layers         []Layer         `json:"layers"`
}
type geoWriter struct {
	out    io.Writer
	offset int64
	layers []Layer
	err    error
}

func (g *geoWriter) layer(name, kind, grid, units string, count, components int, values func(int, int) uint32) {
	size := 4
	if kind == "u8" {
		size = 1
	}
	layer := Layer{Name: name, Type: kind, Components: components, Count: count, Offset: g.offset, Bytes: int64(count * components * size), Grid: grid, Units: units}
	var b [4]byte
	for i := 0; i < count && g.err == nil; i++ {
		for c := 0; c < components; c++ {
			binary.LittleEndian.PutUint32(b[:], values(i, c))
			_, g.err = g.out.Write(b[:size])
			if g.err != nil {
				break
			}
		}
	}
	g.offset += layer.Bytes
	g.layers = append(g.layers, layer)
}
func WriteGeography(dir string, w *sim.World, surface *sim.Surface) (GeographyManifest, error) {
	if w == nil {
		return GeographyManifest{}, fmt.Errorf("world is required")
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return GeographyManifest{}, err
	}
	file, err := os.Create(filepath.Join(dir, "geography.bin"))
	if err != nil {
		return GeographyManifest{}, err
	}
	defer file.Close()
	hash := sha256.New()
	buffer := bufio.NewWriterSize(io.MultiWriter(file, hash), 65536)
	if _, err = buffer.Write(geographyMagic[:]); err != nil {
		return GeographyManifest{}, err
	}
	g := geoWriter{out: buffer, offset: 16}
	cells := make([]sim.Cell, w.Len())
	for i := range cells {
		cells[i], _ = w.Cell(sim.CellID(i))
	}
	floats := func(name, units string, selectValue func(sim.Cell) float32) {
		g.layer(name, "f32", "logical", units, len(cells), 1, func(i, _ int) uint32 { return math.Float32bits(selectValue(cells[i])) })
	}
	integers := func(name, kind string, selectValue func(sim.Cell) int32) {
		g.layer(name, kind, "logical", "", len(cells), 1, func(i, _ int) uint32 { return uint32(selectValue(cells[i])) })
	}
	floats("elevation", "meters", func(c sim.Cell) float32 { return c.Elevation })
	floats("temperature", "celsius", func(c sim.Cell) float32 { return c.Temperature })
	floats("precipitation", "millimeters/year", func(c sim.Cell) float32 { return c.Precipitation })
	floats("seasonalAmplitude", "celsius", func(c sim.Cell) float32 { return c.SeasonalAmplitude })
	floats("roughness", "fraction", func(c sim.Cell) float32 { return c.Roughness })
	floats("latitude", "radians", func(c sim.Cell) float32 { return c.Latitude })
	width := w.Config().Width
	floats("longitude", "radians", func(c sim.Cell) float32 { return float32(((float64(c.X)+.5)/float64(width)*360 - 180) * math.Pi / 180) })
	floats("area", "square kilometers", func(c sim.Cell) float32 { return c.Area })
	integers("land", "u8", func(c sim.Cell) int32 {
		if c.Land {
			return 1
		}
		return 0
	})
	integers("coast", "u8", func(c sim.Cell) int32 {
		if c.Coast {
			return 1
		}
		return 0
	})
	integers("biome", "u8", func(c sim.Cell) int32 { return int32(c.Ecology.Biome) })
	integers("landmass", "i32", func(c sim.Cell) int32 { return c.Landmass })
	g.layer("neighbors", "i32", "logical", "province ID", len(cells), 4, func(i, c int) uint32 { return uint32(cells[i].Neighbors[c]) })
	integers("downstream", "i32", func(c sim.Cell) int32 { return int32(c.Drainage.Downstream) })
	floats("filledElevation", "meters", func(c sim.Cell) float32 { return c.Drainage.FilledElevation })
	floats("flowAccumulation", "legacy flow proxy", func(c sim.Cell) float32 { return c.Drainage.Accumulation })
	floats("river", "legacy river strength", func(c sim.Cell) float32 { return c.Drainage.River })
	floats("farmingSuitability", "fraction", func(c sim.Cell) float32 { return c.Ecology.Farming })
	floats("herdingSuitability", "fraction", func(c sim.Cell) float32 { return c.Ecology.Herding })
	floats("growingSeason", "months", func(c sim.Cell) float32 { return c.Ecology.GrowingSeason })
	floats("leaching", "fraction", func(c sim.Cell) float32 { return c.Ecology.Leaching })
	floats("tropical", "fraction", func(c sim.Cell) float32 { return c.Ecology.Tropical })
	floats("forest0", "fraction", func(c sim.Cell) float32 { return c.Ecology.InitialForest })
	floats("heavySoil", "fraction", func(c sim.Cell) float32 { return c.Ecology.HeavySoil })
	floats("malaria", "fraction", func(c sim.Cell) float32 { return c.Ecology.Malaria })
	floats("onchocerciasis", "fraction", func(c sim.Cell) float32 { return c.Ecology.Onchocerciasis })
	floats("circumscription", "fraction", func(c sim.Cell) float32 { return c.Ecology.Circumscription })
	floats("monsoonZone", "fraction", func(c sim.Cell) float32 { return c.Ecology.MonsoonZone })
	integers("travelCost", "u8", func(c sim.Cell) int32 { return int32(c.Ecology.TravelCost) })
	integers("nomad", "u8", func(c sim.Cell) int32 {
		if c.Ecology.Nomad {
			return 1
		}
		return 0
	})
	integers("tsetse", "u8", func(c sim.Cell) int32 {
		if c.Ecology.Tsetse {
			return 1
		}
		return 0
	})
	integers("desert", "u8", func(c sim.Cell) int32 {
		if c.Ecology.Desert {
			return 1
		}
		return 0
	})
	g.layer("niche", "f32", "logical", "legacy niche coordinates", len(cells), 4, func(i, c int) uint32 { return math.Float32bits(cells[i].Ecology.Niche[c]) })
	g.layer("sphereXYZ", "f32", "logical", "unit sphere", len(cells), 3, func(i, c int) uint32 {
		v := [3]float32{cells[i].Geometry.X3, cells[i].Geometry.Y3, cells[i].Geometry.Z3}
		return math.Float32bits(v[c])
	})
	links := []sim.SeaLink{}
	offsets := make([]int32, len(cells)+1)
	for i := range cells {
		offsets[i] = int32(len(links))
		current, _ := w.SeaLinks(sim.CellID(i))
		links = append(links, current...)
	}
	offsets[len(cells)] = int32(len(links))
	g.layer("seaOffsets", "i32", "connectivity", "CSR offsets", len(offsets), 1, func(i, _ int) uint32 { return uint32(offsets[i]) })
	g.layer("seaTargets", "i32", "connectivity", "province ID", len(links), 1, func(i, _ int) uint32 { return uint32(links[i].Target) })
	g.layer("seaDistances", "u8", "connectivity", "legacy sea steps", len(links), 1, func(i, _ int) uint32 { return uint32(links[i].Distance) })
	config := w.Config()
	manifest := GeographyManifest{Schema: GeographySchema, Engine: sim.EngineVersion, WorldVersion: sim.WorldVersion, WorldSHA256: w.Digest(), World: config, Logical: Grid{config.Width, config.Height}, Projection: "equirectangular cell centers", LongitudeWrap: true, PolarWrap: false, NeighborOrder: [4]string{"west", "east", "north", "south"}, ProvinceID: "y * logical.width + x", FineProvinceID: "floor(fineY / detail) * logical.width + floor(fineX / detail)", File: "geography.bin", ByteOrder: "little-endian"}
	if surface != nil {
		sw, sh := surface.Size()
		if sw != config.Width*config.Detail || sh != config.Height*config.Detail {
			return GeographyManifest{}, fmt.Errorf("fine surface dimensions do not match world")
		}
		manifest.Fine = &Grid{sw, sh}
		for channel, name := range []string{"fineElevation", "fineTemperature", "finePrecipitation", "fineSeasonalAmplitude"} {
			units := []string{"meters", "celsius", "millimeters/year", "celsius"}[channel]
			g.layer(name, "f32", "fine", units, sw*sh, 1, func(i, _ int) uint32 {
				v, _ := surface.At(i%sw, i/sw)
				return math.Float32bits([4]float32{v.Elevation, v.Temperature, v.Precipitation, v.SeasonalAmplitude}[channel])
			})
		}
	}
	if g.err != nil {
		return GeographyManifest{}, g.err
	}
	if err = buffer.Flush(); err != nil {
		return GeographyManifest{}, err
	}
	if err = file.Close(); err != nil {
		return GeographyManifest{}, err
	}
	manifest.Bytes = g.offset
	manifest.Layers = g.layers
	manifest.SHA256 = hex.EncodeToString(hash.Sum(nil))
	if err = writeJSON(filepath.Join(dir, "manifest.json"), manifest); err != nil {
		return GeographyManifest{}, err
	}
	return manifest, nil
}
func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0644)
}
func WriteBundle(dir string, w *sim.World, surface *sim.Surface, s *sim.Simulation) error {
	if w == nil || s == nil || w.Digest() != s.World().Digest() {
		return fmt.Errorf("simulation and geography must refer to the same world")
	}
	if _, err := WriteGeography(dir, w, surface); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(dir, "state.json"), s.Snapshot()); err != nil {
		return err
	}
	replay := s.Replay()
	initial, err := sim.NewSimulationWithRules(w, replay.HistorySeed, replay.InitialRules)
	if err != nil {
		return err
	}
	if err = writeJSON(filepath.Join(dir, "initial-state.json"), initial.Snapshot()); err != nil {
		return err
	}
	if err = writeJSON(filepath.Join(dir, "replay.json"), replay); err != nil {
		return err
	}
	samples := []sim.Cell{}
	for _, id := range []sim.CellID{0, sim.CellID(w.Config().Width - 1), sim.CellID(w.Len() / 2), sim.CellID(w.Len() - 1)} {
		c, _ := w.Cell(id)
		samples = append(samples, c)
	}
	return writeJSON(filepath.Join(dir, "control-samples.json"), samples)
}
