package sim

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"math"
	"reflect"
	"sync"
	"testing"
)

func TestDigestPipelinePreservesCanonicalBytes(t *testing.T) {
	values := make([]float32, 10003)
	for i := range values {
		values[i] = math.Float32frombits(uint32(i)*7919 + 0x7f800001)
	}
	for _, capacity := range []int{16, 31, 64, 65536} {
		want, got := &byteHash{}, &byteHash{}
		original := legacyState{hash: want, buffer: make([]byte, 0, capacity)}
		encoded := canonicalState{hash: got, buffer: make([]byte, 0, capacity), pipeline: newDigestPipeline(got, capacity)}
		for _, value := range []any{"unaligned-prefix!", values, []int32{-1, 0, 1}, []float64{math.Copysign(0, -1), math.NaN()}, "suffix"} {
			original.value(reflect.ValueOf(value))
			encoded.value(reflect.ValueOf(value))
		}
		original.flush()
		encoded.flush()
		encoded.pipeline.finish()
		encoded.pipeline.finish() // also called by the production cleanup defer
		if !bytes.Equal(want.Bytes(), got.Bytes()) {
			t.Fatalf("canonical stream changed with buffer capacity %d", capacity)
		}
	}
}

func TestConcurrentDigestPipelines(t *testing.T) {
	w, err := GenerateWorld(DefaultWorldConfig("Asabiya"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	s.AdvanceYear()
	want := legacyDigest(s)
	var group sync.WaitGroup
	for i := 0; i < 3; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			if got := s.StateDigest(); got != want {
				t.Errorf("concurrent SHA differs: %s != %s", got, want)
			}
		}()
	}
	group.Wait()
}

// Fixed-state digest work excludes startup and advancing the historical clock.
// The paired modes encode exactly the same state and bytes on the same CPU.
func BenchmarkStateDigestPipeline(b *testing.B) {
	w, err := GenerateWorld(DefaultWorldConfig("Asabiya"))
	if err != nil {
		b.Fatal(err)
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		b.Fatal(err)
	}
	s.AdvanceYear()
	want := s.StateDigest()
	for _, pipelined := range []bool{false, true} {
		name := "serial"
		if pipelined {
			name = "pipelined"
		}
		b.Run(name, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				d := sha256.New()
				e := canonicalState{hash: d}
				if pipelined {
					e.pipeline, e.buffer = newPooledDigestPipeline(d)
				} else {
					e.buffer = make([]byte, 0, 65536)
				}
				e.text(StateDigestVersion)
				e.text(s.worldDigestLocked())
				p := s.h.r.Position()
				e.u64(uint64(p.Seed))
				e.u64(p.Calls)
				e.u64(s.commandSequence)
				e.history(reflect.ValueOf(s.h).Elem())
				e.flush()
				if e.pipeline != nil {
					e.pipeline.finish()
				}
				if hex.EncodeToString(d.Sum(nil)) != want {
					b.Fatal("digest changed")
				}
			}
		})
	}
}
