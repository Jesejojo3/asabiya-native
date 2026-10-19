package sim

import (
	"errors"
	"sync"
	"unicode/utf8"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

const SimulationVersion = "native/history-init-v1"

// Simulation owns one history over an immutable World. It is initialized by
// newHistory. The mutex serializes complete years, commands and read-only
// copies. Rendering and transport never access mutable history directly.
type Simulation struct {
	commandSequence uint64
	commandLog      []CommandResult
	initialRules    Rules
	mu              sync.RWMutex
	initialHistory  HistorySummary
	world           *World
	h               *history
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
	s := &Simulation{world: world, h: newHistory(world, historySeed, rules.clone())}
	s.initialHistory = s.summaryLocked()
	s.initialRules = rules.clone()
	s.h.prepareAnnualState()
	s.h.snapshot()
	return s, nil
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
func (s *Simulation) Rules() Rules  { s.mu.RLock(); defer s.mu.RUnlock(); return s.h.rules.clone() }
func (s *Simulation) Status() SimulationStatus {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.statusLocked()
}
func (s *Simulation) statusLocked() SimulationStatus {
	version, stage := SimulationVersion, "founded"
	if s.h.advanced {
		version = EngineVersion
		stage = "running"
	}
	return SimulationStatus{Version: version, RulesVersion: s.h.rules.Version, HistorySeed: s.h.seed, StartYear: s.h.start, Year: s.h.year, Stage: stage, HistoryRNG: s.h.r.Position()}
}

const EngineVersion = "native/v06-core-v1"

// AdvanceYear executes the entire original calendar synchronously. No partial
// year, UI scheduling yield or background writer escapes this operation.
func (s *Simulation) AdvanceYear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.applyCommandLocked(s.nextCommandLocked("advance_year"))
}
func (s *Simulation) InitialSummary() HistorySummary {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return cloneHistorySummary(s.initialHistory)
}
