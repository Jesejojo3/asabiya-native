package sim

import (
	_ "embed"
	"encoding/json"
)

// Ordered lists, not a map iteration: CATA order determines weighted RNG.
//
//go:embed interventions_v06.json
var interventionData []byte

type OmenDef struct {
	Key, Name   string
	Cost        int
	KM          float64
	Needs       string
	Description string `json:"desc"`
}
type CataclysmDef struct {
	Key                          string
	Eras                         []int
	Weight                       float64 `json:"w"`
	Scope                        string
	KM                           float64
	Population                   float64 `json:"pop"`
	Technology                   float64 `json:"tech"`
	Infrastructure               float64 `json:"infra"`
	KMod                         float64
	KYears                       int     `json:"kyrs"`
	Cohesion                     float64 `json:"s"`
	Site, Kind, Title, Text, Why string
	World                        *struct {
		KMod   float64
		KYears int `json:"kyrs"`
	}
}

var interventions = func() *struct {
	Schema, ReferenceSHA256 string
	Omens                   []OmenDef
	Cataclysms              []CataclysmDef
} {
	var c struct {
		Schema, ReferenceSHA256 string
		Omens                   []OmenDef
		Cataclysms              []CataclysmDef
	}
	if err := json.Unmarshal(interventionData, &c); err != nil {
		panic(err)
	}
	if c.Schema != "asabiya/v06-interventions-v1" || len(c.Omens) != 8 || len(c.Cataclysms) != 7 {
		panic("invalid intervention catalog")
	}
	return &c
}()

func omenDef(key string) *OmenDef {
	for i := range interventions.Omens {
		if interventions.Omens[i].Key == key {
			return &interventions.Omens[i]
		}
	}
	return nil
}
func cataclysmDef(key string) *CataclysmDef {
	for i := range interventions.Cataclysms {
		if interventions.Cataclysms[i].Key == key {
			return &interventions.Cataclysms[i]
		}
	}
	return nil
}
