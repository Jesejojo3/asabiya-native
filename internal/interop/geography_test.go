package interop

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func TestBinaryGeographyReconstructionAndReadOnlyBundle(t *testing.T) {
	c := sim.DefaultWorldConfig("interop-test")
	c.Width, c.Height = 24, 16
	w, surface, err := sim.GenerateWorldWithSurface(c)
	if err != nil {
		t.Fatal(err)
	}
	s, _ := sim.NewSimulation(w, "1")
	s.AdvanceYear()
	before, pos := s.StateDigest(), s.Status().HistoryRNG
	dir := t.TempDir()
	if err = WriteBundle(dir, w, surface, s); err != nil {
		t.Fatal(err)
	}
	if s.StateDigest() != before || s.Status().HistoryRNG != pos {
		t.Fatal("export changed simulation or RNG")
	}
	manifestData, _ := os.ReadFile(filepath.Join(dir, "manifest.json"))
	var manifest GeographyManifest
	if err = json.Unmarshal(manifestData, &manifest); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, manifest.File))
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(data)
	if manifest.Bytes != int64(len(data)) || manifest.SHA256 != hex.EncodeToString(hash[:]) || string(data[:8]) != "ASABGEO\x00" || binary.LittleEndian.Uint32(data[8:]) != 1 {
		t.Fatal("binary identity mismatch")
	}
	layers := map[string]Layer{}
	end := int64(16)
	for _, layer := range manifest.Layers {
		if layer.Offset != end || layer.Offset+layer.Bytes > int64(len(data)) {
			t.Fatal("invalid layer extent")
		}
		layers[layer.Name] = layer
		end += layer.Bytes
	}
	if end != int64(len(data)) {
		t.Fatal("unaccounted bytes")
	}
	f32 := func(name string, id int) float32 {
		l := layers[name]
		return math.Float32frombits(binary.LittleEndian.Uint32(data[l.Offset+int64(id*4):]))
	}
	i32 := func(name string, id int) int32 {
		l := layers[name]
		return int32(binary.LittleEndian.Uint32(data[l.Offset+int64(id*4):]))
	}
	for id := 0; id < w.Len(); id++ {
		cell, _ := w.Cell(sim.CellID(id))
		if f32("elevation", id) != cell.Elevation || f32("river", id) != cell.Drainage.River || f32("latitude", id) != cell.Latitude || i32("landmass", id) != cell.Landmass {
			t.Fatalf("cell %d reconstruction differs", id)
		}
		for d := 0; d < 4; d++ {
			if i32("neighbors", id*4+d) != int32(cell.Neighbors[d]) {
				t.Fatal("adjacency changed")
			}
		}
	}
	sw, sh := surface.Size()
	for y := 0; y < sh; y++ {
		for x := 0; x < sw; x++ {
			sample, _ := surface.At(x, y)
			if f32("fineElevation", y*sw+x) != sample.Elevation || f32("finePrecipitation", y*sw+x) != sample.Precipitation {
				t.Fatal("fine geography differs")
			}
		}
	}
	var initial, current sim.StateView
	raw, _ := os.ReadFile(filepath.Join(dir, "initial-state.json"))
	if err = json.Unmarshal(raw, &initial); err != nil {
		t.Fatal(err)
	}
	raw, _ = os.ReadFile(filepath.Join(dir, "state.json"))
	if err = json.Unmarshal(raw, &current); err != nil {
		t.Fatal(err)
	}
	if initial.Year+1 != current.Year || initial.WorldSHA256 != manifest.WorldSHA256 || current.StateSHA256 != before {
		t.Fatal("state and geography contracts disagree")
	}
}
