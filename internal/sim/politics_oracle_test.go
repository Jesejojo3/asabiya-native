package sim

import (
	"encoding/json"
	"math"
	"os"
	"slices"
	"testing"
)

func TestOriginalPoliticalYearAndLiveRebels(t *testing.T) {
	data, err := os.ReadFile("../../tests/native/politics-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct{ Snapshots []map[string]any }
	if err = json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	w := historyContractWorld(t)
	s, _ := NewSimulation(w, "1")
	h := s.h
	h.prepareAnnualState()
	h.year = -4001
	h.rules.Values["crisis"] = 20
	a, b := NoCell, NoCell
	for _, i := range w.landList {
		w.roughness[i] = .4
		w.travelCost[i] = 2
		h.pop[i] = 20000
		h.K[i] = 5000
		h.eth[i] = 0
		if int(i)%w.config.Width >= w.config.Width/2 {
			h.eth[i] = 1
			if b < 0 {
				b = i
			}
		} else if a < 0 {
			a = i
		}
		h.tech[TechFarm][i] = .9
		h.tech[TechGrain][i] = .9
		h.tech[TechWriting][i] = .8
		h.tech[TechIron][i] = .7
		h.tech[TechLaw][i] = .8
		h.tech[TechRoads][i] = .6
		h.cohesion[i] = .75
		h.integ[i] = .7
	}
	h.newPolity(a, nil, polityOptions{})
	h.newPolity(b, nil, polityOptions{})
	for _, i := range w.landList {
		h.pol[i] = 1
		if int(i)%w.config.Width >= w.config.Width/2 {
			h.pol[i] = 2
		}
	}
	for _, want := range fixture.Snapshots {
		h.year++
		stages := want["stages"].([]any)
		h.politicalCensus()
		if float64(h.r.Position().Calls) != stages[0] {
			t.Fatalf("year %d census RNG Go=%d / JS=%v", h.year, h.r.Position().Calls, stages[0])
		}
		h.politicalLeaders()
		if float64(h.r.Position().Calls) != stages[1] {
			for _, o := range h.polities[1:] {
				t.Logf("id=%d name=%s psi=%g culture=%g", o.ID, o.Full, o.Psi, o.Culture)
			}
			t.Fatalf("year %d leaders RNG Go=%d / JS=%v", h.year, h.r.Position().Calls, stages[1])
		}
		h.politicalBorders(h.rules.get("leaderInfl"))
		for _, id := range slices.Clone(h.activeMigrations) {
			h.migStep(h.migrations[id])
		}
		if h.year%5 == 0 {
			h.politicalTerritory()
		}
		delete(want, "stages")
		p := h.r.Position()
		rng := want["rng"].(map[string]any)
		if float64(p.Seed) != rng["seed"] || float64(p.Calls) != rng["calls"] {
			t.Fatalf("year %d RNG differs Go=%+v JS=%v", h.year, p, rng)
		}
		raw, err := json.Marshal(politicsProjection(h))
		if err != nil {
			t.Fatal(err)
		}
		var got any
		json.Unmarshal(raw, &got)
		compareOracleJSON(t, "politics", want, got)
	}
}
func nullableNumber(n float64) any {
	if math.IsNaN(n) || math.IsInf(n, 0) {
		return nil
	}
	return n
}
func politicsProjection(h *history) map[string]any {
	polities := []any{}
	for _, o := range h.polities[1:] {
		kids := o.Kids
		if kids == nil {
			kids = []int{}
		}
		enemies, neighbors := [][2]int{}, [][2]int{}
		o.Enemies.Each(func(k, v int) { enemies = append(enemies, [2]int{k, v}) })
		o.NB.Each(func(k, v int) { neighbors = append(neighbors, [2]int{k, v}) })
		var fac any
		if o.Fac != nil {
			fac = []any{nullableNumber(o.Fac[0]), nullableNumber(o.Fac[1])}
		}
		var coast any
		if o.CensusReady {
			coast = o.CoastN
		}
		record := map[string]any{"id": o.ID, "name": o.Full, "capital": o.Capital, "core": o.Core, "kind": o.Kind, "alive": o.Alive, "cells": o.Cells, "pop": nullableNumber(o.Pop), "K": nullableNumber(o.K), "E": nullableNumber(o.E), "S": nullableNumber(o.S), "psi": nullableNumber(o.Psi), "culture": nullableNumber(o.Culture), "reach": nullableNumber(o.Reach), "gate": nullableNumber(o.Gate), "mandate": nullableNumber(o.Mandate), "integrated": nullableNumber(o.Integration), "niche": o.Niche, "fac": fac, "coastN": coast, "kids": kids, "enemies": enemies, "nb": neighbors}
		if o.ComplexitySet {
			record["inequality"] = nullableNumber(o.Inequality)
			record["complexity"] = nullableNumber(o.Complexity)
			record["treasury"] = nullableNumber(o.Treasury)
		}
		polities = append(polities, record)
	}
	cells := [][11]float64{}
	for _, i := range h.world.landList {
		cells = append(cells, [11]float64{float64(h.pol[i]), float64(h.pop[i]), float64(h.cohesion[i]), float64(h.integ[i]), float64(h.dist[i]), float64(h.taken[i]), float64(h.fort[i]), float64(h.eth[i]), float64(h.religion[i]), float64(h.uni[i]), float64(h.uniFamily[i])})
	}
	wars := []any{}
	for _, w := range h.wars {
		wars = append(wars, map[string]any{"id": w.ID, "a": w.Attackers, "d": w.Defenders, "start": w.Start, "end": w.End, "gainA": w.GainA, "gainD": w.GainD, "lastGain": w.LastGain, "civil": w.Civil, "holy": w.Holy, "outcome": w.Outcome})
	}
	active := h.activeWars
	if active == nil {
		active = []int{}
	}
	p := h.r.Position()
	return map[string]any{"year": h.year, "rng": map[string]any{"seed": p.Seed, "calls": p.Calls}, "alive": h.alive, "polities": polities, "cells": cells, "wars": wars, "activeWars": active, "figures": len(h.figures)}
}
