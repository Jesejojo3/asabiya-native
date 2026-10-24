package mapsource

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func earthImport() (sim.WorldConfig, sim.WorldSource) {
	c := sim.DefaultWorldConfig("Asabiya-Earth-v1")
	s := sim.DefaultWorldSource()
	s.Kind, s.FitClimate = "imported", true
	s.Assets = []sim.SourceAsset{{Role: "earth-html", Path: "../../reference/v0.6/Asabiya History Engine (Copy).html", SHA256: legacyHTMLSHA256, Bytes: 1553001}}
	return c, s
}

func TestEarthImportGeographyAndEmergentHistory(t *testing.T) {
	c, source := earthImport()
	s, in, err := Load(c, source)
	if err != nil {
		t.Fatal(err)
	}
	legacy := source
	legacy.Kind = "earth"
	_, original, err := Load(c, legacy)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(in, original) {
		t.Fatal("import changed preserved Earth rasters")
	}
	w, surface, err := sim.GenerateWorldWithInputs(c, s, in, true)
	if err != nil {
		t.Fatal(err)
	}
	if w.Source().Kind != "imported" || len(w.Regions()) != 0 {
		t.Fatal("legacy Earth history was activated")
	}
	if fw, fh := surface.Size(); fw != 1600 || fh != 800 {
		t.Fatalf("fine raster %dx%d", fw, fh)
	}
	for _, p := range []struct {
		name     string
		lat, lon float64
		land     bool
	}{
		{"Europe", 48, 10, true}, {"Africa", 0, 25, true}, {"Asia", 40, 100, true},
		{"North America", 40, -100, true}, {"South America", -10, -60, true},
		{"Australia", -25, 134, true}, {"Pacific", 0, -140, false}, {"Atlantic", 0, -30, false},
	} {
		x, y := int((p.lon+180)/360*float64(c.Width)), int((90-p.lat)/180*float64(c.Height))
		cell, ok := w.Cell(sim.CellID(y*c.Width + x))
		if !ok || cell.Land != p.land {
			t.Errorf("%s land=%v, want %v", p.name, cell.Land, p.land)
		}
	}
	a, err := sim.NewSimulation(w, "earth-test-1")
	if err != nil {
		t.Fatal(err)
	}
	b, err := sim.NewSimulation(w, "earth-test-1")
	if err != nil {
		t.Fatal(err)
	}
	other, err := sim.NewSimulation(w, "earth-test-2")
	if err != nil {
		t.Fatal(err)
	}
	if a.Summary().SHA256 != b.Summary().SHA256 {
		t.Fatal("same history seed is not reproducible")
	}
	if a.Summary().SHA256 == other.Summary().SHA256 || reflect.DeepEqual(a.Summary().Hearths, other.Summary().Hearths) {
		t.Fatal("history seeds did not change emergent history")
	}
	for _, hearth := range a.Summary().Hearths {
		if hearth.Fixed {
			t.Fatal("import activated a fixed historical hearth")
		}
	}
	a.AdvanceYear()
	b.AdvanceYear()
	if a.Summary().SHA256 != b.Summary().SHA256 {
		t.Fatal("annual history is not reproducible")
	}
	// Input paths are locators, not world identity.
	relocated := s
	relocated.Assets = append([]sim.SourceAsset(nil), s.Assets...)
	relocated.Assets[0].Path = filepath.Join(t.TempDir(), "earth.html")
	w2, _, err := sim.GenerateWorldWithInputs(c, relocated, in, false)
	if err != nil {
		t.Fatal(err)
	}
	if w.Digest() != w2.Digest() {
		t.Fatal("relocating the Earth asset changed world identity")
	}
}

func TestEarthImportRejectsInvalidInputs(t *testing.T) {
	for _, tc := range []struct {
		name string
		edit func(*sim.WorldConfig, *sim.WorldSource)
	}{
		{"dimensions", func(c *sim.WorldConfig, s *sim.WorldSource) { c.Width = 48 }},
		{"hash", func(c *sim.WorldConfig, s *sim.WorldSource) { s.Assets[0].SHA256 = "wrong" }},
		{"bytes", func(c *sim.WorldConfig, s *sim.WorldSource) { s.Assets[0].Bytes = 1 }},
		{"procedural", func(c *sim.WorldConfig, s *sim.WorldSource) { s.Kind = "procedural" }},
		{"duplicate", func(c *sim.WorldConfig, s *sim.WorldSource) { s.Assets = append(s.Assets, s.Assets[0]) }},
		{"conflict", func(c *sim.WorldConfig, s *sim.WorldSource) {
			p := filepath.Join(t.TempDir(), "koppen.bin")
			if err := os.WriteFile(p, make([]byte, 1600*800), 0600); err != nil {
				t.Fatal(err)
			}
			s.Assets = append(s.Assets, sim.SourceAsset{Role: "koppen", Path: p})
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, s := earthImport()
			tc.edit(&c, &s)
			if _, _, err := Load(c, s); err == nil {
				t.Fatal("accepted invalid Earth import")
			}
		})
	}
}
