package sim

import (
	"math"
	"slices"
	"sort"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

const StateViewSchema = "asabiya/state-v1"

type ProvinceView struct {
	Era         int    `json:"era"`
	ID          CellID `json:"id"`
	Land        bool   `json:"land"`
	OwnerPolity int    `json:"ownerPolityId"`
	// v0.6 has one territorial affiliation; separate military control is absent.
	MilitaryController    *int               `json:"militaryControllerPolityId"`
	People                int                `json:"peopleId"`
	SecondaryPeople       int                `json:"secondaryPeopleId"`
	Mixture               float32            `json:"mixture"`
	Population            float32            `json:"population"`
	Capacity              float32            `json:"carryingCapacity"`
	Religion              int                `json:"religionId"`
	City                  int                `json:"cityId"`
	Technology            [techCount]float32 `json:"technology"`
	Cohesion              float32            `json:"cohesion"`
	Integration           float32            `json:"integration"`
	Fortification         float32            `json:"fortification"`
	Forest                float32            `json:"forest"`
	Fertility             float32            `json:"fertility"`
	Salinity              float32            `json:"salinity"`
	MalariaAdaptation     float32            `json:"malariaAdaptation"`
	DiseasePool           float32            `json:"diseasePool"`
	Immunity              float32            `json:"immunity"`
	Infection             uint8              `json:"infection"`
	Outbreak              int                `json:"outbreakId"`
	CaravanActivity       float32            `json:"caravanActivity"`
	PastureDisease        float32            `json:"pastureDisease"`
	CapacityModifier      float32            `json:"capacityModifier"`
	CapacityModifierUntil float32            `json:"capacityModifierUntil"`
	EcologicalExit        float32            `json:"exitOpportunity"`
	Circumscription       float32            `json:"circumscription"`
	WeatherAnomaly        float32            `json:"weatherAnomaly"`
	RainMultiplier        float32            `json:"rainMultiplier"`
	DistanceToCapital     uint16             `json:"distanceToCapital"`
}
type EntityRecord struct {
	Kind   string         `json:"kind"`
	ID     int            `json:"id"`
	Fields map[string]any `json:"fields"`
}
type StateView struct {
	Earth       *EarthHistory             `json:"earth,omitempty"`
	Schema      string                    `json:"schema"`
	Engine      string                    `json:"engine"`
	WorldSHA256 string                    `json:"worldSHA256"`
	StateSHA256 string                    `json:"stateSHA256"`
	Year        int                       `json:"year"`
	StartYear   int                       `json:"startYear"`
	RNG         rng.Position              `json:"rng"`
	Rules       Rules                     `json:"rules"`
	Favor       float64                   `json:"favor"`
	Provinces   []ProvinceView            `json:"provinces"`
	Entities    map[string][]EntityRecord `json:"entities"`
	Events      []Event                   `json:"events"`
	Narrative   []EventText               `json:"narrative"`
	Stats       []StatsEntry              `json:"stats"`
}

func (s *Simulation) Province(id CellID) (ProvinceView, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if id < 0 || int(id) >= s.world.Len() {
		return ProvinceView{}, false
	}
	return s.provinceLocked(id), true
}
func (s *Simulation) provinceLocked(i CellID) ProvinceView {
	h := s.h
	p := ProvinceView{ID: i, Land: s.world.land[i], OwnerPolity: int(h.pol[i]), People: int(h.eth[i]), SecondaryPeople: int(h.eth2[i]), Mixture: h.mix[i], Population: h.pop[i], Capacity: h.K[i], Religion: int(h.religion[i]), City: int(h.city[i]), Cohesion: h.cohesion[i], Integration: h.integ[i], Fortification: h.fort[i], Forest: h.forest[i], Fertility: h.fert[i], Salinity: h.salt[i], MalariaAdaptation: h.adapt[i], DiseasePool: h.plaguePool[i], Immunity: h.immunity[i], Infection: h.infection[i], Outbreak: int(h.outbreakAt[i]), CaravanActivity: h.caravan[i], PastureDisease: h.rp[i], CapacityModifier: h.kMod[i], CapacityModifierUntil: h.kModUntil[i], EcologicalExit: h.exit[i], Circumscription: h.circE[i], WeatherAnomaly: h.anom[i], RainMultiplier: h.wm[i], DistanceToCapital: h.dist[i]}
	p.Era = h.eraOf(int(i))
	for k := range h.tech {
		p.Technology[k] = h.tech[k][i]
	}
	return p
}
func (s *Simulation) Snapshot() StateView {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.snapshotLocked()
}
func (s *Simulation) snapshotLocked() StateView {
	h := s.h
	v := StateView{Schema: StateViewSchema, Engine: EngineVersion, WorldSHA256: s.world.Digest(), StateSHA256: s.stateDigestLocked(), Year: h.year, StartYear: h.start, RNG: h.r.Position(), Rules: h.rules.clone(), Favor: h.favor, Entities: make(map[string][]EntityRecord), Provinces: make([]ProvinceView, s.world.Len()), Events: cloneEvents(h.events), Narrative: slices.Clone(h.eventText), Stats: slices.Clone(h.stats)}
	v.Earth = h.earthView()
	for k := range v.Stats {
		v.Stats[k].EraShare = slices.Clone(h.stats[k].EraShare)
	}
	for i := range v.Provinces {
		v.Provinces[i] = s.provinceLocked(CellID(i))
	}
	for _, kind := range entityKinds {
		v.Entities[kind] = s.entitiesLocked(kind)
	}
	return v
}
func cloneEvents(events []Event) []Event {
	out := slices.Clone(events)
	for k := range out {
		out[k].Entities = slices.Clone(events[k].Entities)
	}
	return out
}

var entityKinds = []string{"people", "polity", "ruler", "figure", "city", "religion", "war", "migration", "outbreak", "omen", "cataclysm", "route"}

func EntityKinds() []string { return slices.Clone(entityKinds) }
func (s *Simulation) Entity(kind string, id int) (EntityRecord, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.entityLocked(kind, id)
}
func (s *Simulation) Entities(kind string) []EntityRecord {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.entitiesLocked(kind)
}
func (s *Simulation) entitiesLocked(kind string) []EntityRecord {
	count := 0
	switch kind {
	case "people":
		count = len(s.h.peoples)
	case "polity":
		count = len(s.h.polities)
	case "ruler":
		count = len(s.h.rulers)
	case "figure":
		count = len(s.h.figures)
	case "city":
		count = len(s.h.cities)
	case "religion":
		count = len(s.h.religions)
	case "war":
		count = len(s.h.wars)
	case "migration":
		count = len(s.h.migrations)
	case "outbreak":
		count = len(s.h.outbreaks)
	case "omen":
		count = len(s.h.omens)
	case "cataclysm":
		count = len(s.h.cataclysms)
	case "route":
		count = len(s.h.routeArchive)
	}
	out := make([]EntityRecord, 0, count)
	for id := 0; id < count; id++ {
		if record, ok := s.entityLocked(kind, id); ok {
			out = append(out, record)
		}
	}
	return out
}
func finiteNumber(n float64) any {
	if math.IsNaN(n) || math.IsInf(n, 0) {
		return nil
	}
	return n
}
func finiteVector(values []float64) []any {
	out := make([]any, len(values))
	for k, v := range values {
		out[k] = finiteNumber(v)
	}
	return out
}
func (s *Simulation) entityLocked(kind string, id int) (EntityRecord, bool) {
	h := s.h
	if id < 0 {
		return EntityRecord{}, false
	}
	var f map[string]any
	switch kind {
	case "people":
		if id >= len(h.peoples) {
			break
		}
		e := h.peoples[id]
		l := e.Language
		f = map[string]any{"name": e.Name, "alive": e.Alive, "born": e.Born, "familyId": e.Family, "parentId": e.Parent, "secondParentId": e.Parent2, "children": slices.Clone(e.Kids), "depth": e.Depth, "rgb": e.RGB, "culture": e.Culture, "cellsAtLastCensus": e.Cells, "populationAtLastCensus": e.Pop, "peakCells": e.Peak, "languageStyle": l.Style, "languageMacro": l.Macro, "lexicon": l.Lex, "soundChanges": l.SoundChanges(), "placeName": l.Place, "longitudeRadians": e.Lon, "latitudeRadians": e.Lat, "stillborn": e.Stillborn}
		if e.Died != nil {
			f["died"] = *e.Died
		} else {
			f["died"] = nil
		}
	case "polity":
		if id == 0 || id >= len(h.polities) {
			break
		}
		o := h.polities[id]
		enemies := []int{}
		o.Enemies.Each(func(k, _ int) { enemies = append(enemies, k) })
		var niche, fac, shape any
		if o.Niche != nil {
			niche = *o.Niche
		}
		if o.Fac != nil {
			fac = finiteVector(o.Fac[:])
		}
		if o.Shape != nil {
			shape = *o.Shape
		}
		metrics := map[string]any{"population": o.Pop, "capacity": o.K, "cohesion": o.S, "pressure": finiteNumber(o.Press), "eliteShare": finiteNumber(o.E), "crisisPressure": finiteNumber(o.Psi), "culture": finiteNumber(o.Culture), "reach": finiteNumber(o.Reach), "gate": finiteNumber(o.Gate), "mandate": finiteNumber(o.Mandate), "shock": finiteNumber(o.Shock), "integration": finiteNumber(o.Integration), "tax": finiteNumber(o.Tax), "burden": finiteNumber(o.Burden), "inequality": finiteNumber(o.Inequality), "complexity": finiteNumber(o.Complexity), "treasury": finiteNumber(o.Treasury), "cityPopulationAtLastCensus": o.CityPopulation, "trade": o.Trade, "nomadShare": o.NomF, "foreignNicheShare": o.ForeignShare}
		if !o.ComplexitySet {
			metrics["complexity"] = nil
			metrics["treasury"] = nil
			metrics["inequality"] = nil
		}
		f = map[string]any{"name": o.Full, "base": o.Base, "peakName": o.PeakName, "kind": o.Kind, "tier": o.Tier, "capitalId": o.Capital, "peopleId": o.Core, "religionId": o.Religion, "rulerId": o.Ruler.ID, "founderRulerId": o.FounderR.ID, "dynastyLabel": o.Dynasty, "dynastyGeneration": o.Generation, "born": o.Born, "alive": o.Alive, "cellsAtLastCensus": o.Cells, "peakCells": o.MaxCells, "peakPopulation": o.MaxPop, "rgb": o.RGB, "fromPolityId": o.From, "children": slices.Clone(o.Kids), "restoresPolityId": o.Restores, "restoredByPolityId": o.RestoredBy, "overlordId": o.Over, "tributaries": o.Tributaries, "allies": slices.Clone(o.Allies), "enemies": enemies, "warIds": slices.Clone(o.WarsF), "rulerHistory": slices.Clone(o.Rulers), "censusHistory": slices.Clone(o.Hist), "metrics": metrics, "niche": niche, "inventionContext": fac, "works": slices.Clone(o.Works), "goldenPeriods": slices.Clone(o.Golds), "shape": shape, "conquestDynasty": o.ConquestDynasty, "origin": o.Origin}
		if o.Alive {
			f["died"] = nil
		} else {
			f["died"] = o.Died
		}
	case "ruler":
		if id >= len(h.rulers) {
			break
		}
		r := h.rulers[id]
		f = map[string]any{"name": r.Name, "base": r.Base, "epithet": r.Epithet, "female": r.Female, "aggression": r.Aggression, "competence": r.Competence, "charisma": r.Charisma, "piety": r.Piety, "exceptional": r.Exceptional, "born": r.Birth, "legacyDeathValue": r.Death, "since": r.Since, "figureId": r.Figure, "conquests": r.Conquests}
	case "figure":
		if id >= len(h.figures) {
			break
		}
		r := h.figures[id]
		f = map[string]any{"name": r.Name, "kind": r.Kind, "title": r.Title, "polityId": r.Polity, "peopleId": r.People, "born": r.Born, "died": r.Died, "religionId": r.Religion, "conquests": r.Conquests, "realmCells": r.Realm, "works": r.Works, "exceptional": r.Exceptional, "deeds": slices.Clone(r.Deeds)}
	case "city":
		if id >= len(h.cities) {
			break
		}
		c := h.cities[id]
		f = map[string]any{"name": c.Name, "cellId": c.Cell, "born": c.Born, "peopleId": c.People, "peakProvincePopulation": c.Peak, "holy": c.Holy, "ownerPolityId": int(h.pol[c.Cell]), "population": h.pop[c.Cell]}
	case "religion":
		if id >= len(h.religions) {
			break
		}
		r := h.religions[id]
		f = map[string]any{"name": r.Name, "kind": r.Kind, "founderFigureId": r.Founder, "born": r.Born, "originCellId": r.Origin, "holyCellId": r.Holy, "originPolityId": r.Polity, "peopleId": r.People, "familyId": r.Family, "holderPolityId": r.Holder, "parentId": r.Parent, "children": slices.Clone(r.Kids), "stateIds": slices.Clone(r.States), "missionary": r.Missionary, "centralization": r.Centralization, "alive": r.Alive, "died": r.Died, "rgb": r.RGB, "cellsAtLastCensus": r.Cells, "populationAtLastCensus": r.Population, "peakCells": r.Peak, "councils": r.Councils, "longitudeRadians": r.Lon, "latitudeRadians": r.Lat}
	case "war":
		if id >= len(h.wars) {
			break
		}
		w := h.wars[id]
		f = map[string]any{"name": w.Name, "attackers": slices.Clone(w.Attackers), "defenders": slices.Clone(w.Defenders), "start": w.Start, "end": w.End, "active": slices.Contains(h.activeWars, id), "gainsAttackers": w.GainA, "gainsDefenders": w.GainD, "lastGain": w.LastGain, "civil": w.Civil, "holy": w.Holy, "notable": w.Notable, "why": w.Why, "outcome": w.Outcome}
	case "migration":
		if id >= len(h.migrations) {
			break
		}
		m := h.migrations[id]
		f = map[string]any{"name": m.Name, "kind": m.Kind, "peopleId": m.People, "religionId": m.Religion, "population": m.Population, "cellId": m.Cell, "direction": [2]float64{m.DX, m.DY}, "path": slices.Clone(m.Path), "start": m.Start, "end": m.End, "steps": m.Steps, "maxSteps": m.Max, "fails": m.Fails, "cohesion": m.Cohesion, "military": m.Military, "technology": m.Techs, "originPolityId": m.Polity, "previousMigrationId": m.Previous, "displacingPolityId": m.By, "settledPolityId": m.SettledPolity, "done": m.Done, "result": m.Result, "cause": m.Cause, "brokenPolityIds": slices.Clone(m.Broke)}
	case "outbreak":
		if id >= len(h.outbreaks) {
			break
		}
		o := h.outbreaks[id]
		f = map[string]any{"name": o.Name, "originCellId": o.Origin, "start": o.Year, "end": o.End, "deaths": o.Deaths, "virulence": o.Virulence, "sourceDiseasePool": o.Pool, "cells": o.Cells, "activeCells": o.Active, "done": o.Done, "virginSoil": o.Virgin, "fromPeopleId": o.From, "spread": slices.Clone(o.Spread), "hitPolityIds": o.Hit.Keys()}
	case "omen":
		if id >= len(h.omens) {
			break
		}
		o := h.omens[id]
		f = map[string]any{"type": o.Type, "cellId": o.Cell, "year": o.Year, "ownerPolityId": o.Owner, "place": o.Place, "populationBefore": o.PopulationBefore, "followed": o.Followed, "cells": o.Cells, "radiusKM": o.KM, "religionId": o.Religion, "outbreakId": o.Plague, "cataclysmId": o.Cataclysm, "text": o.Text, "why": o.Why, "followText": o.FollowText, "followWhy": o.FollowWhy}
	case "cataclysm":
		if id >= len(h.cataclysms) {
			break
		}
		c := h.cataclysms[id]
		f = map[string]any{"kind": c.Kind, "name": c.Name, "place": c.Place, "year": c.Year, "cellId": c.Cell, "radiusKM": c.KM, "scope": c.Scope, "deaths": c.Deaths, "omen": c.Omen, "hitPolityIds": slices.Clone(c.Hit), "eraFrom": c.EraFrom, "eraTo": c.EraTo, "text": c.Text, "why": c.Why}
	case "route":
		if id >= len(h.routeArchive) {
			break
		}
		r := h.routeArchive[id]
		active := false
		for _, a := range h.routes {
			if a.NativeID == id {
				active = true
				break
			}
		}
		f = map[string]any{"legacyId": r.ID, "key": r.Key, "born": r.Born, "last": r.Last, "fromCellId": r.A, "toCellId": r.B, "path": slices.Clone(r.Path), "active": active}
	}
	if f == nil {
		return EntityRecord{}, false
	}
	return EntityRecord{Kind: kind, ID: id, Fields: f}, true
}

type OwnershipRecord struct {
	Year        int `json:"year"`
	OwnerPolity int `json:"ownerPolityId"`
}

func (s *Simulation) OwnershipHistory(id CellID) []OwnershipRecord {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if id < 0 || int(id) >= s.world.Len() || !s.world.land[id] {
		return nil
	}
	position := sort.Search(len(s.world.landList), func(k int) bool { return s.world.landList[k] >= id })
	if position >= len(s.world.landList) || s.world.landList[position] != id {
		return nil
	}
	years := []int{}
	s.h.snapshots.keys.Each(func(y int, _ []int32) { years = append(years, y) })
	s.h.snapshots.diffs.Each(func(y int, _ []int32) { years = append(years, y) })
	sort.Ints(years)
	out := []OwnershipRecord{}
	last := -1
	for _, year := range years {
		owners := s.h.polAt(year)
		if owners == nil {
			continue
		}
		owner := int(owners[position])
		if owner != last {
			out = append(out, OwnershipRecord{Year: year, OwnerPolity: owner})
			last = owner
		}
	}
	return out
}
