// Package rng ports the v0.6 seed hash and Mulberry32 without a global generator.
package rng

import "unicode/utf16"

const increment uint32 = 0x6d2b79f5

// HashStr hashes UTF-16 code units, as JavaScript charCodeAt does. Input strings
// are well-formed UTF-8; supplementary characters produce two UTF-16 units.
func HashStr(s string) uint32 {
	h := uint32(2166136261)
	for _, c := range utf16.Encode([]rune(s)) {
		h = (h ^ uint32(c)) * 16777619
	}
	return h
}

// Position records the original seed and number of draws, not the last output.
type Position struct {
	Seed  uint32 `json:"seed"`
	Calls uint64 `json:"calls"`
}

type Mulberry32 struct {
	position Position
	state    uint32
}

func New(seed uint32) *Mulberry32 { return Restore(Position{Seed: seed}) }

// Restore jumps directly to a draw boundary with modulo-2^32 arithmetic.
func Restore(p Position) *Mulberry32 {
	return &Mulberry32{position: p, state: p.Seed + uint32(p.Calls)*increment}
}

func (r *Mulberry32) Position() Position { return r.position }

func (r *Mulberry32) Uint32() uint32 {
	r.state += increment
	t := (r.state ^ (r.state >> 15)) * (1 | r.state)
	t = (t + (t^(t>>7))*(61|t)) ^ t
	r.position.Calls++
	return t ^ (t >> 14)
}

func (r *Mulberry32) Float64() float64 { return float64(r.Uint32()) / 4294967296 }

func WorldSeed(seed string) uint32             { return HashStr("world:" + seed) }
func HistorySeed(history, world string) uint32 { return HashStr("hist:" + history + ":" + world) }
