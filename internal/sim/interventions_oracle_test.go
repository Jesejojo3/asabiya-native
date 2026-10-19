package sim

import (
	"encoding/json"
	"os"
	"testing"
)

func TestOriginalAllOmensAndCataclysms(t *testing.T) {
	data, err := os.ReadFile("../../tests/native/interventions-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var want struct {
		Origin    CellID
		Invalid   []string
		Snapshots []map[string]any
		Volcanoes []map[string]any
	}
	if err = json.Unmarshal(data, &want); err != nil {
		t.Fatal(err)
	}
	w := historyContractWorld(t)
	s, _ := NewSimulation(w, "1")
	h := s.h
	h.prepareAnnualState()
	h.year = -1000
	h.rules.Sandbox = true
	h.rules.Values["cataclysms"] = 0
	origin := NoCell
	for _, i := range w.landList {
		w.roughness[i] = .4
		w.elevation[i] = 300
		h.pop[i] = 500000
		h.K[i] = 600000
		h.eth[i] = 0
		h.tech[TechFarm][i] = .9
		h.tech[TechHerd][i] = .7
		h.tech[TechCopper][i] = .8
		h.tech[TechWriting][i] = .8
		h.cohesion[i] = .6
		h.integ[i] = .7
		h.fort[i] = .5
		if origin < 0 && w.temperature[i] > 5 {
			origin = i
		}
	}
	if origin != want.Origin {
		t.Fatal("origin differs")
	}
	h.newPolity(origin, nil, polityOptions{})
	o := h.polities[1]
	for _, i := range w.landList {
		h.pol[i] = 1
	}
	o.Cells = len(w.landList)
	o.Pop = float64(len(w.landList)) * 500000
	o.MaxCells = o.Cells
	o.Tier = h.tierOf(o)
	o.Full = fullName(o)
	steps := []func(){func() {
		for _, def := range interventions.Omens {
			if om, message := h.castOmen(def.Key, origin); om == nil {
				t.Fatalf("%s: %s", def.Key, message)
			}
		}
	}, func() {
		for _, a := range h.tech {
			for _, i := range w.landList {
				a[i] = 1
			}
		}
		if om, message := h.castOmen("spark", origin); om == nil {
			t.Fatal(message)
		}
	}, func() {
		for _, def := range interventions.Cataclysms {
			if h.cataclysm(def.Key, origin, false) == nil {
				t.Fatal(def.Key)
			}
		}
	}, func() { h.year += 50; h.omenPass() }}
	for k, step := range steps {
		step()
		v := want.Snapshots[k]
		p := h.r.Position()
		rng := v["rng"].(map[string]any)
		if float64(p.Seed) != rng["seed"] || float64(p.Calls) != rng["calls"] {
			t.Fatalf("%s RNG Go=%+v JS=%v", v["phase"], p, rng)
		}
		raw, err := json.Marshal(interventionsProjection(h, v["phase"].(string)))
		if err != nil {
			t.Fatal(err)
		}
		var got any
		json.Unmarshal(raw, &got)
		compareOracleJSON(t, v["phase"].(string), v, got)
	}
	before := h.r.Position()
	invalid := []string{h.omenCheck("unknown", origin), h.omenCheck("kindle", NoCell), h.omenCheck("plague", origin)}
	for k, message := range invalid {
		if message != want.Invalid[k] {
			t.Fatalf("validation differs: %v / %v", invalid, want.Invalid)
		}
	}
	if h.r.Position() != before {
		t.Fatal("validation consumed RNG")
	}
	for _, v := range want.Volcanoes {
		h.volcano()
		p := h.r.Position()
		outbreaks := []any{}
		for _, o := range h.outbreaks {
			outbreaks = append(outbreaks, map[string]any{"name": o.Name, "origin": o.Origin, "vir": o.Virulence})
		}
		raw, _ := json.Marshal(map[string]any{"rng": map[string]any{"seed": p.Seed, "calls": p.Calls}, "dT": h.dT, "years": h.volcanoYears, "mandate": h.polities[1].Mandate, "shock": h.polities[1].Shock, "outbreaks": outbreaks})
		var got any
		json.Unmarshal(raw, &got)
		compareOracleJSON(t, "volcano", v, got)
	}
	h.rules.Sandbox = false
	h.favor = 0
	before = h.r.Position()
	if om, _ := h.castOmen("kindle", origin); om != nil || h.r.Position() != before || h.favor != 0 {
		t.Fatal("unaffordable omen changed state or RNG")
	}
}
func interventionsProjection(h *history, phase string) map[string]any {
	cells := [][9]float64{}
	for _, i := range h.world.landList {
		cells = append(cells, [9]float64{float64(h.pop[i]), float64(h.cohesion[i]), float64(h.integ[i]), float64(h.fort[i]), float64(h.kMod[i]), float64(h.kModUntil[i]), float64(h.religion[i]), float64(h.infection[i]), float64(h.outbreakAt[i])})
	}
	tech := make([][]float32, techCount)
	for k := range h.tech {
		for _, i := range h.world.landList {
			tech[k] = append(tech[k], h.tech[k][i])
		}
	}
	omens := []any{}
	for _, om := range h.omens {
		omens = append(omens, map[string]any{"id": om.ID, "type": om.Type, "cell": om.Cell, "year": om.Year, "owner": om.Owner, "place": om.Place, "populationBefore": om.PopulationBefore, "followed": om.Followed, "cells": om.Cells, "km": om.KM, "religion": om.Religion, "plague": om.Plague, "cataclysm": om.Cataclysm})
	}
	cats := []any{}
	for _, c := range h.cataclysms {
		hit := c.Hit
		if hit == nil {
			hit = []int{}
		}
		cats = append(cats, map[string]any{"id": c.ID, "kind": c.Kind, "name": c.Name, "year": c.Year, "cell": c.Cell, "km": c.KM, "scope": c.Scope, "deaths": c.Deaths, "omen": c.Omen, "hit": hit, "eraFrom": c.EraFrom, "eraTo": c.EraTo})
	}
	religions := []any{}
	for _, r := range h.religions {
		states := r.States
		if states == nil {
			states = []int{}
		}
		religions = append(religions, map[string]any{"id": r.ID, "name": r.Name, "founder": r.Founder, "kind": r.Kind, "miss": r.Missionary, "cent": r.Centralization, "states": states})
	}
	outbreaks := []any{}
	for _, p := range h.outbreaks {
		outbreaks = append(outbreaks, map[string]any{"name": p.Name, "vir": p.Virulence, "origin": p.Origin})
	}
	figures := []any{}
	for _, f := range h.figures {
		figures = append(figures, map[string]any{"name": f.Name, "kind": f.Kind, "born": f.Born, "died": f.Died})
	}
	o, p := h.polities[1], h.r.Position()
	return map[string]any{"phase": phase, "rng": map[string]any{"seed": p.Seed, "calls": p.Calls}, "favor": h.favor, "cells": cells, "tech": tech, "state": map[string]any{"mandate": o.Mandate, "shock": o.Shock, "E": o.E, "culture": nullableNumber(o.Culture), "rel": o.Religion}, "omens": omens, "cataclysms": cats, "religions": religions, "outbreaks": outbreaks, "figures": figures}
}
