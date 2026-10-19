package sim

import (
	"errors"
	"github.com/Jesejojo3/asabiya-native/internal/rng"
	"unicode/utf8"
)

const SimulationVersion = "native/initialization-v1"

type Simulation struct {
	world       *World
	historySeed string
	year        int
	random      *rng.Mulberry32
}

// NewSimulation creates an explicitly unpopulated session. newHistory,
// carrying capacity and annual systems have not yet been ported; there is no
// AdvanceYear operation until they exist. A generation RNG is never reused as
// the historical RNG.
func NewSimulation(world *World, historySeed string) (*Simulation, error) {
	if world == nil {
		return nil, errors.New("world is required")
	}
	if !utf8.ValidString(historySeed) || len(historySeed) > 1024 {
		return nil, errors.New("history seed must be valid UTF-8, at most 1024 bytes")
	}
	return &Simulation{world: world, historySeed: historySeed, year: -9000, random: rng.New(rng.HistorySeed(historySeed, world.config.Seed))}, nil
}

type SimulationStatus struct {
	Version     string       `json:"version"`
	HistorySeed string       `json:"historySeed"`
	Year        int          `json:"year"`
	Stage       string       `json:"stage"`
	HistoryRNG  rng.Position `json:"historyRNG"`
}

func (s *Simulation) World() *World { return s.world }
func (s *Simulation) Status() SimulationStatus {
	return SimulationStatus{Version: SimulationVersion, HistorySeed: s.historySeed, Year: s.year, Stage: "unpopulated-world", HistoryRNG: s.random.Position()}
}
