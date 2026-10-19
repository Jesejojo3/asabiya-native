package sim

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

func TestOriginalWeatherAndHearthContract(t *testing.T) {
	b, err := os.ReadFile("../../tests/native/weather-hearth-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var want struct {
		RNG struct {
			Seed  uint32
			Calls uint64
		}
		AG          []float64
		Weather     [][3]float64
		Hearths     []Hearth
		Discoveries []*Discovery
		Tech        [][][2]float64
		Chronicle   []ChronicleEntry
	}
	if err := json.Unmarshal(b, &want); err != nil {
		t.Fatal(err)
	}
	w := historyContractWorld(t)
	for i := range w.roughness {
		w.roughness[i] = .4
	}
	s, err := NewSimulation(w, "1")
	if err != nil {
		t.Fatal(err)
	}
	h := s.h
	h.year++
	for i := range h.hearths {
		h.hearths[i].Year = h.year
	}
	h.epoch = &Epoch{Kind: "dry", Start: h.year - 10, End: h.year + 20, Amp: -1.2, CX: 0, CY: w.config.Height / 2, Radius: 10}
	before := len(h.chronicle)
	h.weather()
	h.hearthCheck()
	if p := h.r.Position(); p.Seed != want.RNG.Seed || p.Calls != want.RNG.Calls {
		t.Fatalf("RNG differs: %+v, JS=%+v", p, want.RNG)
	}
	for i, v := range h.ag {
		if !near(float64(v), want.AG[i]) {
			t.Fatalf("AG[%d] differs", i)
		}
	}
	for _, v := range want.Weather {
		i := int(v[0])
		if !near(float64(h.anom[i]), v[1]) || !near(float64(h.wm[i]), v[2]) {
			t.Fatalf("weather cell %d differs", i)
		}
	}
	if !reflect.DeepEqual(h.hearths, want.Hearths) {
		t.Fatalf("hearths differ:\nGo=%+v\nJS=%+v", h.hearths, want.Hearths)
	}
	for k, d := range want.Discoveries {
		if !reflect.DeepEqual(h.firstDiscoveries[k], d) {
			t.Fatalf("discovery %d differs: %+v / %+v", k, h.firstDiscoveries[k], d)
		}
	}
	for k, values := range want.Tech {
		index := 0
		for i, v := range h.tech[k] {
			if v == 0 {
				continue
			}
			if index >= len(values) || i != int(values[index][0]) || !near(float64(v), values[index][1]) {
				t.Fatalf("tech %d cell %d differs", k, i)
			}
			index++
		}
		if index != len(values) {
			t.Fatalf("tech %d nonzero count differs", k)
		}
	}
	if !reflect.DeepEqual(h.chronicle[before:], want.Chronicle) {
		t.Fatal("hearth chronicle differs")
	}
}
