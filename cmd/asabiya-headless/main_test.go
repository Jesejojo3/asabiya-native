package main

import (
	"bytes"
	"encoding/json"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestGenerateQueryAndExport(t *testing.T) {
	dir := t.TempDir()
	outPath := filepath.Join(dir, "world.json")
	imagePath := filepath.Join(dir, "world.png")
	args := []string{"--seed", "🌍", "--width", "48", "--height", "24", "--cell", "0,0", "--out", outPath, "--png", imagePath}
	var out, errOut bytes.Buffer
	if err := run(args, &out, &errOut); err != nil {
		t.Fatal(err)
	}
	var r report
	if err := json.Unmarshal(out.Bytes(), &r); err != nil {
		t.Fatal(err)
	}
	if r.Cell == nil || r.Cell.ID != 0 || r.World.Cells != 1152 || r.Simulation.Stage != "unpopulated-world" {
		t.Fatalf("incorrect report: %+v", r)
	}
	data, err := os.ReadFile(outPath)
	if err != nil || !bytes.Equal(data, out.Bytes()) {
		t.Fatal("output file differs")
	}
	f, err := os.Open(imagePath)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	im, err := png.Decode(f)
	if err != nil {
		t.Fatal(err)
	}
	if im.Bounds().Dx() != 48 || im.Bounds().Dy() != 24 {
		t.Fatal("wrong PNG size")
	}
	var second bytes.Buffer
	if err := run(args, &second, &errOut); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(out.Bytes(), second.Bytes()) {
		t.Fatal("report not reproducible")
	}
}

func TestFinePNGExport(t *testing.T) {
	path := filepath.Join(t.TempDir(), "fine.png")
	if err := run([]string{"--width", "48", "--height", "24", "--png", path, "--high-res"}, &bytes.Buffer{}, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	config, err := png.DecodeConfig(f)
	if err != nil {
		t.Fatal(err)
	}
	if config.Width != 192 || config.Height != 96 {
		t.Fatal("fine PNG is not the detail grid")
	}
}

func TestInvalidInput(t *testing.T) {
	for _, args := range [][]string{
		{"--unknown"}, {"unexpected"}, {"--width", "-1"}, {"--land", "NaN"}, {"--high-res"},
		{"--width", "48", "--height", "24", "--cell", "-1,0"},
		{"--width", "48", "--height", "24", "--cell", "1"},
	} {
		if err := run(args, &bytes.Buffer{}, &bytes.Buffer{}); err == nil {
			t.Fatalf("accepted %v", args)
		}
	}
}
