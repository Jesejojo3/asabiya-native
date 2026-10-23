package main

import (
	"bytes"
	"encoding/binary"
	"math"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func smallWorld(t *testing.T) (*sim.World, *sim.Surface) {
	t.Helper()
	c := sim.DefaultWorldConfig("snapshot-test")
	c.Width, c.Height = 48, 24
	w, s, err := sim.GenerateWorldWithSurface(c)
	if err != nil {
		t.Fatal(err)
	}
	return w, s
}

func TestRoundTrip(t *testing.T) {
	w, surface := smallWorld(t)
	before := w.Digest()
	sm, _ := sim.NewSimulation(w, "1")
	raw, err := Build(w, surface, sm.Status(), map[string]string{"tool": "test"})
	if err != nil {
		t.Fatal(err)
	}
	if w.Digest() != before {
		t.Fatal("export changed the world digest")
	}
	h, data, err := Read(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if (12+len(raw)-len(data)-12)%16 != 0 || (len(raw)-len(data))%16 != 0 {
		t.Fatalf("data blob not 16-byte aligned: header %d", len(raw)-len(data))
	}
	if h.World.Width != 48 || h.World.FineWidth != 192 || h.Session.Kind != "real" {
		t.Fatalf("unexpected header %+v", h.World)
	}
	layers := map[string]Layer{}
	for _, l := range h.Layers {
		if l.Offset%16 != 0 {
			t.Fatalf("layer %s unaligned", l.Name)
		}
		layers[l.Name] = l
	}
	n := w.Len()
	for _, name := range []string{"land", "biome", "elevation", "down", "river", "elevationFine"} {
		if _, ok := layers[name]; !ok {
			t.Fatalf("missing layer %s", name)
		}
	}
	f32 := func(l Layer, i int) float32 {
		return math.Float32frombits(binary.LittleEndian.Uint32(data[l.Offset+4*i:]))
	}
	for i := 0; i < n; i++ {
		c, _ := w.Cell(sim.CellID(i))
		if (data[layers["land"].Offset+i] == 1) != c.Land || data[layers["biome"].Offset+i] != uint8(c.Ecology.Biome) {
			t.Fatalf("cell %d flags differ", i)
		}
		if f32(layers["elevation"], i) != c.Elevation || f32(layers["river"], i) != c.Drainage.River {
			t.Fatalf("cell %d values differ", i)
		}
		d := int32(binary.LittleEndian.Uint32(data[layers["down"].Offset+4*i:]))
		if d != int32(c.Drainage.Downstream) {
			t.Fatalf("cell %d down differs", i)
		}
	}
	fw, fh := surface.Size()
	if layers["elevationFine"].Bytes != 4*fw*fh {
		t.Fatal("fine layer size")
	}
	s, _ := surface.At(fw-1, fh-1)
	if f32(layers["elevationFine"], fw*fh-1) != s.Elevation {
		t.Fatal("fine layer value")
	}
}

func TestCorruptionDetected(t *testing.T) {
	w, surface := smallWorld(t)
	sm, _ := sim.NewSimulation(w, "1")
	raw, err := Build(w, surface, sm.Status(), nil)
	if err != nil {
		t.Fatal(err)
	}
	raw[len(raw)-1] ^= 0xff
	if _, _, err := Read(bytes.NewReader(raw)); err == nil {
		t.Fatal("corruption not detected")
	}
}

func TestCoarseOnly(t *testing.T) {
	w, _ := smallWorld(t)
	sm, _ := sim.NewSimulation(w, "1")
	raw, err := Build(w, nil, sm.Status(), nil)
	if err != nil {
		t.Fatal(err)
	}
	h, _, err := Read(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if h.World.FineWidth != 0 {
		t.Fatal("coarse snapshot must not declare fine layers")
	}
}
