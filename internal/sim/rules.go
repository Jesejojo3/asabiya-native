package sim

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
)

const RulesVersion = "native/rules-v06-v1"

// Rules are the v0.6 P parameters (PDEF 319–358 plus the four extra defaults).
// They are an explicit value passed to the history, never a process global.
// Values keep the original defaults and slider ranges. Changing them mid-year is
// not supported: future ChangeRules commands apply at year boundaries (ADR-0003).
type Rules struct {
	Version string             `json:"version"`
	Values  map[string]float64 `json:"values"`
	// HearthMode is "historical" or "random". Procedural worlds always use
	// random hearths in v0.6; the historical list exists only for Earth.
	HearthMode   string `json:"hearthMode"`
	ShuffleNames bool   `json:"shuffleNames"`
	Sandbox      bool   `json:"sandbox"`
}

func DefaultRules() Rules {
	r := Rules{Version: RulesVersion, Values: make(map[string]float64, len(v06.Parameters)),
		HearthMode: v06.AdditionalDefaults.HearthMode, ShuffleNames: v06.AdditionalDefaults.ShuffleNames,
		Sandbox: v06.AdditionalDefaults.Sandbox}
	for _, d := range v06.Parameters {
		r.Values[d.Key] = d.Default
	}
	return r
}

// ParameterDefs returns the ordered v0.6 parameter catalog.
func ParameterDefs() []ParameterDef { return append([]ParameterDef(nil), v06.Parameters...) }

// Validate checks every value against the original slider range. Integer
// parameters (step 1 or 500) must be integral, because v0.6 uses them as counts
// or years.
func (r Rules) Validate() error {
	if r.Version != RulesVersion {
		return fmt.Errorf("unsupported rules version %q", r.Version)
	}
	if r.HearthMode != "historical" && r.HearthMode != "random" {
		return errors.New("hearthMode must be historical or random")
	}
	var unknown []string
	for k := range r.Values {
		found := false
		for _, d := range v06.Parameters {
			if d.Key == k {
				found = true
				break
			}
		}
		if !found {
			unknown = append(unknown, k)
		}
	}
	if len(unknown) > 0 {
		sort.Strings(unknown)
		return fmt.Errorf("unknown rule parameters: %s", strings.Join(unknown, ", "))
	}
	for _, d := range v06.Parameters {
		v, ok := r.Values[d.Key]
		if !ok {
			return fmt.Errorf("missing rule parameter %s", d.Key)
		}
		if math.IsNaN(v) || v < d.Min || v > d.Max {
			return fmt.Errorf("%s=%v outside %v..%v", d.Key, v, d.Min, d.Max)
		}
		if d.Step >= 1 && v != math.Trunc(v) {
			return fmt.Errorf("%s must be an integer", d.Key)
		}
	}
	return nil
}

func (r Rules) clone() Rules {
	c := r
	c.Values = make(map[string]float64, len(r.Values))
	for k, v := range r.Values {
		c.Values[k] = v
	}
	return c
}

// get panics on an unknown key: a typo must fail tests, not silently read 0.
func (r Rules) get(key string) float64 {
	v, ok := r.Values[key]
	if !ok {
		panic("rule parameter not set: " + key)
	}
	return v
}
