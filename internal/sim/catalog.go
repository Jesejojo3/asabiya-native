package sim

import (
	_ "embed"
	"encoding/json"
	"fmt"
)

// catalog_v06.json is extracted from the immutable v0.6 HTML by
// tools/extract-history-catalog.mjs (verified in CI with the pinned Node/V8).
// Order is preserved exactly: several tables are sampled by index with RNG.
//
//go:embed catalog_v06.json
var catalogV06 []byte

type languageStyle struct {
	Name   string   `json:"name"`
	Cons   []string `json:"cons"`
	Clust  []string `json:"cl"`
	Vowels []string `json:"vow"`
	Pat    []string `json:"pat"`
	Coda   []string `json:"coda"`
	Place  []string `json:"place"`
	People []string `json:"ppl"`
	Person []string `json:"pers"`
	City   []string `json:"city"`
	Mono   bool     `json:"mono"`
	Pre    *struct {
		People []string `json:"ppl"`
		Place  []string `json:"place"`
	} `json:"pre"`
	Titles map[string]string `json:"titles"`
}

type macroFamily struct {
	Key    string   `json:"key"`
	Styles []string `json:"styles"`
}

// soundRule is either a literal substitution (From/To) or a named rule.
type soundRule struct {
	From string `json:"from,omitempty"`
	To   string `json:"to,omitempty"`
	Kind string `json:"kind,omitempty"`
}

type TechDef struct {
	Key         string             `json:"key"`
	Name        string             `json:"name"`
	Era         int                `json:"era"`
	Pre         []int              `json:"pre"`
	Emergence   map[string]float64 `json:"emergence"`
	Pos         []float64          `json:"pos"`
	Synthetic   bool               `json:"synthetic"`
	Description string             `json:"description"`
}

type epochKind struct {
	Kind     string     `json:"kind"`
	Weight   float64    `json:"weight"`
	Amp      [2]float64 `json:"amp"`
	Duration [2]float64 `json:"duration"`
	Start    string     `json:"start"`
	End      string     `json:"end"`
}

type ParameterDef struct {
	Group    string  `json:"group"`
	Key      string  `json:"key"`
	Label    string  `json:"label"`
	Min      float64 `json:"min"`
	Max      float64 `json:"max"`
	Step     float64 `json:"step"`
	Default  float64 `json:"default"`
	NewWorld bool    `json:"newWorld"`
}

type legacyCatalog struct {
	Schema             string          `json:"schema"`
	ReferenceSHA256    string          `json:"referenceSha256"`
	Styles             []languageStyle `json:"styles"`
	Macros             []macroFamily   `json:"macros"`
	Lex                []string        `json:"lex"`
	SoundRules         []soundRule     `json:"soundRules"`
	Tech               []TechDef       `json:"tech"`
	Eras               []string        `json:"eras"`
	EpochKinds         []epochKind     `json:"epochKinds"`
	Parameters         []ParameterDef  `json:"parameters"`
	AdditionalDefaults struct {
		HearthMode   string `json:"hearthMode"`
		FitClimate   bool   `json:"fitClimate"`
		ShuffleNames bool   `json:"shuffleNames"`
		Sandbox      bool   `json:"sandbox"`
	} `json:"additionalDefaults"`
	styleByName map[string]*languageStyle
	macroByKey  map[string]*macroFamily
}

var v06 = mustLoadCatalog()

func mustLoadCatalog() *legacyCatalog {
	var c legacyCatalog
	if err := json.Unmarshal(catalogV06, &c); err != nil {
		panic(fmt.Sprintf("invalid v0.6 catalog: %v", err))
	}
	if c.Schema != "asabiya/v06-history-catalog-v1" || len(c.Lex) != lexCount || len(c.Tech) != techCount || len(c.Macros) == 0 {
		panic("unexpected v0.6 catalog shape")
	}
	c.styleByName = make(map[string]*languageStyle, len(c.Styles))
	for i := range c.Styles {
		c.styleByName[c.Styles[i].Name] = &c.Styles[i]
	}
	c.macroByKey = make(map[string]*macroFamily, len(c.Macros))
	for i := range c.Macros {
		m := &c.Macros[i]
		for _, s := range m.Styles {
			if c.styleByName[s] == nil {
				panic("macro references unknown style " + s)
			}
		}
		c.macroByKey[m.Key] = m
	}
	for _, r := range c.SoundRules {
		if r.Kind == "" && r.From == "" {
			panic("empty sound rule")
		}
	}
	return &c
}

// TechCatalog returns a copy of the v0.6 technology table, in its storage order.
func TechCatalog() []TechDef { return append([]TechDef(nil), v06.Tech...) }

// Eras returns the v0.6 era names.
func Eras() []string { return append([]string(nil), v06.Eras...) }
