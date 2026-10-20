package sim

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"reflect"
	"sort"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

const CommandSchema = "asabiya/command-v1"
const NativeProfile = "native"

type Command struct {
	Schema              string             `json:"schema"`
	Profile             string             `json:"profile"`
	Sequence            uint64             `json:"sequence"`
	TargetYear          int                `json:"targetYear"`
	Kind                string             `json:"kind"`
	ExpectedRulesSHA256 string             `json:"expectedRulesSHA256,omitempty"`
	Values              map[string]float64 `json:"values,omitempty"`
	Sandbox             *bool              `json:"sandbox,omitempty"`
	Omen                string             `json:"omen,omitempty"`
	Cell                CellID             `json:"cell,omitempty"`
}
type CommandResult struct {
	Command   Command      `json:"command"`
	Accepted  bool         `json:"accepted"`
	Error     string       `json:"error,omitempty"`
	Message   string       `json:"message,omitempty"`
	Year      int          `json:"year"`
	RNGBefore rng.Position `json:"rngBefore"`
	RNGAfter  rng.Position `json:"rngAfter"`
	OmenID    *int         `json:"omenId,omitempty"`
}
type Replay struct {
	WorldSource   *WorldSource    `json:"worldSource,omitempty"`
	FinalSHA256   string          `json:"finalSHA256"`
	FinalYear     int             `json:"finalYear"`
	Schema        string          `json:"schema"`
	Engine        string          `json:"engine"`
	Profile       string          `json:"profile"`
	World         WorldConfig     `json:"world"`
	WorldSHA256   string          `json:"worldSHA256"`
	HistorySeed   string          `json:"historySeed"`
	InitialRules  Rules           `json:"initialRules"`
	InitialSHA256 string          `json:"initialSHA256"`
	Commands      []CommandResult `json:"commands"`
}

func cloneCommand(c Command) Command {
	if c.Values != nil {
		v := make(map[string]float64, len(c.Values))
		for k, x := range c.Values {
			v[k] = x
		}
		c.Values = v
	}
	if c.Sandbox != nil {
		v := *c.Sandbox
		c.Sandbox = &v
	}
	return c
}
func (s *Simulation) NextSequence() uint64 {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.commandSequence + 1
}
func (s *Simulation) nextCommandLocked(kind string) Command {
	return Command{Schema: CommandSchema, Profile: NativeProfile, Sequence: s.commandSequence + 1, TargetYear: s.h.year, Kind: kind}
}
func (s *Simulation) RulesDigest() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.rulesDigestLocked()
}
func (s *Simulation) rulesDigestLocked() string {
	d := sha256.New()
	e := canonicalState{hash: d, buffer: make([]byte, 0, 4096)}
	e.text("native/rules-hash-v1")
	e.value(reflect.ValueOf(s.h.rules))
	e.flush()
	return hex.EncodeToString(d.Sum(nil))
}
func (s *Simulation) ApplyCommand(c Command) CommandResult {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.applyCommandLocked(c)
}
func (s *Simulation) applyCommandLocked(input Command) CommandResult {
	c := cloneCommand(input)
	h := s.h
	result := CommandResult{Command: c, Year: h.year, RNGBefore: h.r.Position()}
	reject := func(message string) { result.Error = message }
	switch {
	case c.Schema != CommandSchema:
		reject("unsupported command schema")
	case c.Profile != NativeProfile:
		reject("only the native profile is implemented; V8 bit parity is not promised")
	case c.Sequence != s.commandSequence+1:
		reject(fmt.Sprintf("expected sequence %d", s.commandSequence+1))
	case c.TargetYear != h.year:
		reject("targetYear must be the current complete year")
	case c.ExpectedRulesSHA256 != "" && c.ExpectedRulesSHA256 != s.rulesDigestLocked():
		reject("rules hash mismatch")
	default:
		switch c.Kind {
		case "advance_year":
			h.advanceYearProfiled(s.workProfile)
			result.Accepted = true
		case "set_sandbox":
			if c.Sandbox == nil {
				reject("sandbox boolean is required")
			} else {
				h.rules.Sandbox = *c.Sandbox
				if *c.Sandbox {
					h.favor = 9
				} else if h.favor > 5 {
					h.favor = 5
				}
				result.Accepted = true
			}
		case "change_rules":
			rules := h.rules.clone()
			keys := make([]string, 0, len(c.Values))
			for k := range c.Values {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, key := range keys {
				for _, def := range v06.Parameters {
					if def.Key == key && def.NewWorld && c.Values[key] != rules.Values[key] {
						reject(key + " requires a new world/history")
						break
					}
				}
				if result.Error != "" {
					break
				}
				rules.Values[key] = c.Values[key]
			}
			if result.Error == "" {
				if err := rules.Validate(); err != nil {
					reject(err.Error())
				} else {
					h.rules = rules
					result.Accepted = true
				}
			}
		case "cast_omen":
			if omen, message := h.castOmen(c.Omen, c.Cell); omen == nil {
				reject(message)
			} else {
				result.Accepted = true
				result.Message = message
				id := omen.ID
				result.OmenID = &id
			}
		default:
			reject("unknown command kind")
		}
	}
	if result.Accepted {
		s.commandSequence = c.Sequence
	}
	result.Year = h.year
	result.RNGAfter = h.r.Position()
	s.commandLog = append(s.commandLog, result)
	return cloneCommandResult(result)
}
func cloneCommandResult(r CommandResult) CommandResult {
	r.Command = cloneCommand(r.Command)
	if r.OmenID != nil {
		id := *r.OmenID
		r.OmenID = &id
	}
	return r
}
func (s *Simulation) Replay() Replay {
	s.mu.RLock()
	defer s.mu.RUnlock()
	r := Replay{Schema: "asabiya/replay-v1", Engine: EngineVersion, Profile: NativeProfile, World: s.world.Config(), WorldSHA256: s.worldDigestLocked(), HistorySeed: s.h.seed, InitialRules: s.initialRules.clone(), InitialSHA256: s.initialHistory.SHA256, Commands: make([]CommandResult, len(s.commandLog))}
	if s.world.extended {
		source := s.world.Source()
		r.WorldSource = &source
	}
	r.FinalSHA256 = s.stateDigestLocked()
	r.FinalYear = s.h.year
	for k, c := range s.commandLog {
		r.Commands[k] = cloneCommandResult(c)
	}
	return r
}

// ReplayOnWorld reconstructs by executing the recorded commands. It is not a
// fast save restoration; a 10,000-year replay simulates those 10,000 years again.
func ReplayOnWorld(world *World, replay Replay) (*Simulation, error) {
	if replay.Schema != "asabiya/replay-v1" || replay.Engine != EngineVersion || replay.Profile != NativeProfile {
		return nil, fmt.Errorf("unsupported replay schema/engine/profile")
	}
	if world == nil || world.Digest() != replay.WorldSHA256 {
		return nil, fmt.Errorf("replay world digest differs")
	}
	s, err := NewSimulationWithRules(world, replay.HistorySeed, replay.InitialRules)
	if err != nil {
		return nil, err
	}
	if s.InitialSummary().SHA256 != replay.InitialSHA256 {
		return nil, fmt.Errorf("replay initialization digest differs")
	}
	for k, record := range replay.Commands {
		result := s.ApplyCommand(record.Command)
		if result.Accepted != record.Accepted || result.Error != record.Error || result.RNGBefore != record.RNGBefore || result.RNGAfter != record.RNGAfter {
			return nil, fmt.Errorf("replay command %d diverged (sequence %d)", k, record.Command.Sequence)
		}
	}
	if s.Status().Year != replay.FinalYear || s.StateDigest() != replay.FinalSHA256 {
		return nil, fmt.Errorf("replay final year/state digest differs")
	}
	return s, nil
}
