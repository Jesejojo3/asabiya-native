package sim

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"testing"
)

func TestOriginalPolityFoundationsContract(t *testing.T) {
	data, err := os.ReadFile("../../tests/native/polity-contract.v06.json")
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
	h.year = -4000
	a, b := NoCell, NoCell
	for _, i := range w.landList {
		w.roughness[i] = .4
		w.travelCost[i] = 2
		h.pop[i] = 20000
		h.K[i] = 18000
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
	for _, id := range h.alive {
		o := h.polities[id]
		cells := h.polCells(id)
		o.Cells = len(cells)
		o.Pop = float64(len(cells)) * 20000
		o.K = float64(len(cells)) * 18000
		o.S = .75
		o.Press = o.Pop / o.K
		o.ADM = .8
		o.NomF = .1
		o.Tax = o.Pop * .1
		o.MaxCells = o.Cells
		o.CityPopulation = o.Pop * .3
		o.E = .3
		o.Culture = .8
		o.Psi = .3
		other := 1
		if id == 1 {
			other = 2
		}
		o.NB.Set(other, 10)
		o.Tier = h.tierOf(o)
		o.Full = fullName(o)
	}
	steps := []func(){h.distBFS, func() {
		for year := 0; year < 12; year++ {
			h.year++
			for _, id := range h.alive {
				o := h.polities[id]
				h.statecraft(o, o.Capital, h.year)
				h.culture(o)
			}
		}
	}, func() {
		for _, id := range h.alive {
			h.succession(h.polities[id])
		}
	}, func() {
		h.declareWar([]*Polity{h.polities[1]}, []*Polity{h.polities[2]}, "", true, false, false)
		for n := 0; n < 2; n++ {
			for _, i := range w.landList {
				if h.pol[i] != 1 {
					continue
				}
				for _, j := range w.neighbors[i] {
					if j >= 0 && w.land[j] && h.pol[j] == 2 {
						h.attack(h.polities[1], i, j, false)
					}
				}
			}
		}
	}, func() { h.civilWar(h.polities[1], false) }, func() {
		for _, war := range h.wars {
			h.endWar(war)
		}
		h.distBFS()
	}}
	steps = append(steps, func() {
		origin := NoCell
		for _, i := range w.landList {
			if w.temperature[i] > 5 && h.eth[i] == 0 {
				origin = i
				break
			}
		}
		m := h.startMigration(0, 450000, origin, 1, .2, "people", nil, nil, -1, "")
		for year := 0; year < 25 && !m.Done; year++ {
			h.year++
			h.migStep(m)
		}
	}, func() {
		for year := 0; year < 8; year++ {
			h.year += 5
			h.diplomacy()
		}
	})
	for index, step := range steps {
		step()
		want := fixture.Snapshots[index]
		got := polityOracleProjection(h, want["phase"].(string))
		raw, _ := json.Marshal(got)
		var normalized any
		if err = json.Unmarshal(raw, &normalized); err != nil {
			t.Fatal(err)
		}
		rngWant := want["rng"].(map[string]any)
		position := h.r.Position()
		if float64(position.Seed) != rngWant["seed"] || float64(position.Calls) != rngWant["calls"] {
			t.Fatalf("%s RNG differs: %+v / %v", want["phase"], position, rngWant)
		}
		compareOracleJSON(t, want["phase"].(string), want, normalized)
	}
}

func polityOracleProjection(h *history, phase string) map[string]any {
	polities := []any{}
	for _, o := range h.polities[1:] {
		enemies, truce := [][2]int{}, [][2]int{}
		o.Enemies.Each(func(k, v int) { enemies = append(enemies, [2]int{k, v}) })
		o.Truce.Each(func(k, v int) { truce = append(truce, [2]int{k, v}) })
		r := o.Ruler
		kids := o.Kids
		if kids == nil {
			kids = []int{}
		}
		polities = append(polities, map[string]any{"id": o.ID, "base": o.Base, "full": o.Full, "peak": o.PeakName, "core": o.Core, "capital": o.Capital, "born": o.Born, "dynasty": o.Dynasty, "generation": o.Generation, "kind": o.Kind, "tier": o.Tier, "from": o.From, "kids": kids, "rgb": o.RGB, "E": o.E, "S": o.S, "pop": o.Pop, "K": o.K, "cells": o.Cells, "inequality": o.Inequality, "complexity": o.Complexity, "treasury": o.Treasury, "burden": o.Burden, "PT": o.PT, "PF": o.PF, "PQ": o.PQ, "mandate": o.Mandate, "shock": o.Shock, "culture": o.Culture, "goldStart": o.GoldStart, "fac": o.Fac, "conquests": o.Conquests, "over": o.Over, "tributaries": o.Tributaries, "crises": o.Crises, "ruler": map[string]any{"name": r.Name, "base": r.Base, "birth": r.Birth, "death": r.Death, "exceptional": r.Exceptional, "figure": r.Figure}, "enemies": enemies, "truce": truce})
	}
	cells := [][6]float64{}
	for _, i := range h.world.landList {
		cells = append(cells, [6]float64{float64(h.pol[i]), float64(h.pop[i]), float64(h.cohesion[i]), float64(h.integ[i]), float64(h.dist[i]), float64(h.taken[i])})
	}
	wars := []any{}
	for _, w := range h.wars {
		wars = append(wars, map[string]any{"id": w.ID, "name": w.Name, "attackers": w.Attackers, "defenders": w.Defenders, "start": w.Start, "end": w.End, "gainA": w.GainA, "gainD": w.GainD, "lastGain": w.LastGain, "civil": w.Civil, "holy": w.Holy, "notable": w.Notable, "outcome": w.Outcome, "why": w.Why})
	}
	figures := []any{}
	for _, f := range h.figures {
		figures = append(figures, map[string]any{"name": f.Name, "kind": f.Kind, "born": f.Born, "died": f.Died, "conquests": f.Conquests, "realm": f.Realm, "works": f.Works})
	}
	migrations := []any{}
	for _, m := range h.migrations {
		broke := m.Broke
		if broke == nil {
			broke = []int{}
		}
		migrations = append(migrations, map[string]any{"id": m.ID, "people": m.People, "population": m.Population, "cell": m.Cell, "dx": m.DX, "dy": m.DY, "path": m.Path, "steps": m.Steps, "max": m.Max, "fails": m.Fails, "start": m.Start, "end": m.End, "done": m.Done, "result": m.Result, "settledPolity": m.SettledPolity, "broke": broke})
	}
	p := h.r.Position()
	return map[string]any{"phase": phase, "rng": map[string]any{"seed": p.Seed, "calls": p.Calls}, "polities": polities, "cells": cells, "wars": wars, "figures": figures, "alive": h.alive, "migrations": migrations}
}

func compareOracleJSON(t *testing.T, path string, want, got any) {
	t.Helper()
	switch w := want.(type) {
	case map[string]any:
		g, ok := got.(map[string]any)
		if !ok || len(g) != len(w) {
			t.Fatalf("%s object shape differs", path)
		}
		for k, v := range w {
			compareOracleJSON(t, path+"/"+k, v, g[k])
		}
	case []any:
		g, ok := got.([]any)
		if !ok || len(g) != len(w) {
			t.Fatalf("%s array size differs: Go=%v / JS=%d", path, len(g), len(w))
		}
		for k, v := range w {
			compareOracleJSON(t, fmt.Sprintf("%s/%d", path, k), v, g[k])
		}
	case float64:
		g, ok := got.(float64)
		// Large integer metadata (RNG seed, sentinels) must not pass on a
		// relative float tolerance. Fractional numerical state uses native math.
		if !ok || (math.Trunc(w) == w && math.Trunc(g) == g && w != g) || !near(w, g) {
			t.Fatalf("%s number Go=%.17g / JS=%.17g", path, g, w)
		}
	default:
		if want != got {
			t.Fatalf("%s Go=%v / JS=%v", path, got, want)
		}
	}
}
