package sim

import (
	"encoding/json"
	"os"
	"testing"
)

func TestOriginalCompleteCalendarAndMapHistory(t *testing.T) {
	data, err := os.ReadFile("../../tests/native/calendar-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Scenarios []struct {
			Late      bool
			Snapshots []map[string]any
		}
	}
	if err = json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	for _, scenario := range fixture.Scenarios {
		w := historyContractWorld(t)
		s, _ := NewSimulation(w, "1")
		h := s.h
		h.prepareAnnualState()
		for _, i := range w.landList {
			w.roughness[i] = .4
			w.elevation[i] = 300
			w.travelCost[i] = 2
		}
		if scenario.Late {
			h.year = -40
			h.start = -40
			h.rules.Values["formRate"] = 30
			h.rules.Values["warRate"] = 4
			h.hearths = nil
			h.stats = nil
			for _, i := range w.landList {
				h.pop[i] = 500000
				h.eth[i] = 0
				if int(i)%w.config.Width >= w.config.Width/2 {
					h.eth[i] = 1
				}
				for _, a := range h.tech {
					a[i] = .9
				}
				h.cohesion[i] = .6
				h.integ[i] = .7
			}
			for k := range h.firstDiscoveries {
				h.firstDiscoveries[k] = &Discovery{Year: h.year, Cell: w.landList[0], People: 0}
			}
			h.recordStats()
		}
		h.snapshot()
		for _, want := range scenario.Snapshots {
			target := int(want["year"].(float64))
			for h.year < target {
				h.advanceYear()
			}
			p := h.r.Position()
			rng := want["rng"].(map[string]any)
			if float64(p.Seed) != rng["seed"] || float64(p.Calls) != rng["calls"] {
				t.Fatalf("late=%v year %d RNG Go=%+v JS=%v", scenario.Late, h.year, p, rng)
			}
			raw, err := json.Marshal(calendarProjection(h))
			if err != nil {
				t.Fatal(err)
			}
			var got any
			json.Unmarshal(raw, &got)
			compareOracleJSON(t, "calendar", want, got)
		}
	}
}
func calendarProjection(h *history) map[string]any {
	arrays := [][]float32{h.pop, h.K, h.cohesion, h.integ, h.fert, h.forest, h.salt, h.adapt, h.plaguePool, h.caravan}
	arrays = append(arrays, h.tech[:]...)
	sums := make([]float64, len(arrays))
	samples := [][]float64{}
	ids := [][7]int32{}
	for k, i := range h.world.landList {
		for f, a := range arrays {
			sums[f] += float64(a[i])
		}
		if k%31 == 0 {
			sample := []float64{float64(i)}
			for _, a := range arrays {
				sample = append(sample, float64(a[i]))
			}
			samples = append(samples, sample)
		}
		ids = append(ids, [7]int32{h.pol[i], h.eth[i], h.eth2[i], h.religion[i], h.city[i], int32(h.infection[i]), h.outbreakAt[i]})
	}
	polities := []any{}
	for _, o := range h.polities[1:] {
		polities = append(polities, map[string]any{"id": o.ID, "name": o.Full, "alive": o.Alive, "cells": o.Cells, "pop": o.Pop, "core": o.Core, "capital": o.Capital, "culture": nullableNumber(o.Culture)})
	}
	wars := []any{}
	for _, w := range h.wars {
		wars = append(wars, map[string]any{"id": w.ID, "a": w.Attackers, "d": w.Defenders, "start": w.Start, "end": w.End, "gainA": w.GainA, "gainD": w.GainD})
	}
	stats := []any{}
	for _, st := range h.stats {
		stats = append(stats, map[string]any{"year": st.Year, "population": st.Population, "polities": st.Polities, "hordes": st.Hordes, "people": st.LivingPeoples, "leadingEra": st.LeadingEra, "eraShare": st.EraShare})
	}
	var layer any
	if l := h.layerAt(h.year); l != nil {
		layer = map[string]any{"year": l.Year, "people": l.People, "religion": l.Religion, "density": integerBytes(l.Density), "cohesion": integerBytes(l.Cohesion), "era": integerBytes(l.Era)}
	}
	p := h.r.Position()
	return map[string]any{"year": h.year, "rng": map[string]any{"seed": p.Seed, "calls": p.Calls}, "favor": h.favor, "sums": sums, "samples": samples, "ids": ids, "polities": polities, "wars": wars, "stats": stats, "ownership": h.polAt(h.year), "layer": layer}
}
func integerBytes(a []uint8) []int {
	out := make([]int, len(a))
	for k, v := range a {
		out[k] = int(v)
	}
	return out
}
