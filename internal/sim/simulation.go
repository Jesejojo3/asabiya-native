package sim

import (
	"errors"
	"unicode/utf8"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

const SimulationVersion = "native/history-init-v1"

// Simulation owns one history over an immutable World. It is initialized by
// newHistory (founding peoples and initial population). There is still no
// AdvanceYear: the annual calendar needs weather, growth, migration, technology
// and the other stepG systems before a year can be advanced honestly.
type Simulation struct {
	world *World
	h     *history
}

// NewSimulation initializes a history with the default v0.6 rules.
func NewSimulation(world *World, historySeed string) (*Simulation, error) {
	return NewSimulationWithRules(world, historySeed, DefaultRules())
}

func NewSimulationWithRules(world *World, historySeed string, rules Rules) (*Simulation, error) {
	if world == nil {
		return nil, errors.New("world is required")
	}
	if !utf8.ValidString(historySeed) || len(historySeed) > 1024 {
		return nil, errors.New("history seed must be valid UTF-8, at most 1024 bytes")
	}
	if err := rules.Validate(); err != nil {
		return nil, err
	}
	return &Simulation{world: world, h: newHistory(world, historySeed, rules.clone())}, nil
}

type SimulationStatus struct {
	Version      string       `json:"version"`
	RulesVersion string       `json:"rulesVersion"`
	HistorySeed  string       `json:"historySeed"`
	StartYear    int          `json:"startYear"`
	Year         int          `json:"year"`
	Stage        string       `json:"stage"`
	HistoryRNG   rng.Position `json:"historyRNG"`
}

func (s *Simulation) World() *World { return s.world }
func (s *Simulation) Rules() Rules  { return s.h.rules.clone() }
func (s *Simulation) Status() SimulationStatus {
	return SimulationStatus{Version: SimulationVersion, RulesVersion: s.h.rules.Version, HistorySeed: s.h.seed, StartYear: s.h.start,
		Year: s.h.year, Stage: "founded", HistoryRNG: s.h.r.Position()}
}
