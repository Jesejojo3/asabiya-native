package sim

import (
	"fmt"
	"math"
)

// Validate checks actual storage/ID invariants, not assumed social outcomes.
// Census fields lag the annual border pass in v0.6; extinct flags and disease
// pools are not silently normalized into stronger native-only invariants.
func (s *Simulation) Validate() error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	h, w := s.h, s.world
	finite := func(x float64) bool { return !math.IsNaN(x) && !math.IsInf(x, 0) }
	for i := 0; i < w.Len(); i++ {
		if !finite(float64(h.pop[i])) || h.pop[i] < 0 {
			return fmt.Errorf("invalid population at cell %d", i)
		}
		if !finite(float64(h.K[i])) || (w.land[i] && h.K[i] < 1) {
			return fmt.Errorf("invalid carrying capacity at cell %d", i)
		}
		if !w.land[i] && (h.pop[i] != 0 || h.pol[i] != 0) {
			return fmt.Errorf("ocean cell %d has population/territory", i)
		}
		if h.eth[i] < -1 || int(h.eth[i]) >= len(h.peoples) || h.eth2[i] < -1 || int(h.eth2[i]) >= len(h.peoples) {
			return fmt.Errorf("invalid people ID at cell %d", i)
		}
		if h.pol[i] < 0 || int(h.pol[i]) >= len(h.polities) {
			return fmt.Errorf("invalid polity ID at cell %d", i)
		}
		if h.religion[i] < -1 || int(h.religion[i]) >= len(h.religions) {
			return fmt.Errorf("invalid religion ID at cell %d", i)
		}
		if h.city[i] < -1 || int(h.city[i]) >= len(h.cities) {
			return fmt.Errorf("invalid city ID at cell %d", i)
		}
		if h.outbreakAt[i] < -1 || int(h.outbreakAt[i]) >= len(h.outbreaks) || (h.infection[i] > 0 && h.outbreakAt[i] < 0) {
			return fmt.Errorf("invalid outbreak ID at cell %d", i)
		}
		if !finite(float64(h.cohesion[i])) || h.cohesion[i] < 0 || h.cohesion[i] > 1 || !finite(float64(h.integ[i])) || h.integ[i] < 0 || h.integ[i] > 1 {
			return fmt.Errorf("invalid provincial cohesion/integration at cell %d", i)
		}
		for k, a := range h.tech {
			if !finite(float64(a[i])) || a[i] < 0 || float64(a[i]) > 1.000001 {
				return fmt.Errorf("invalid technology %d at cell %d", k, i)
			}
		}
	}
	for id, e := range h.peoples {
		if e.ID != id || e.Parent >= id || e.Parent2 >= id {
			return fmt.Errorf("invalid people lineage %d", id)
		}
	}
	for id, o := range h.polities {
		if id == 0 {
			continue
		}
		if o == nil || o.ID != id || o.Core < 0 || o.Core >= len(h.peoples) || o.Capital < 0 || int(o.Capital) >= w.Len() || o.Ruler == nil || o.Ruler.ID < 0 || o.Ruler.ID >= len(h.rulers) {
			return fmt.Errorf("invalid polity %d", id)
		}
	}
	for id, r := range h.religions {
		if r.ID != id || r.Founder < 0 || r.Founder >= len(h.figures) {
			return fmt.Errorf("invalid religion %d", id)
		}
	}
	for id, c := range h.cities {
		if c.ID != id || c.Cell < 0 || int(c.Cell) >= w.Len() || h.city[c.Cell] != int32(id) {
			return fmt.Errorf("invalid city %d", id)
		}
	}
	for id, war := range h.wars {
		if war.ID != id || len(war.Attackers) == 0 || len(war.Defenders) == 0 {
			return fmt.Errorf("invalid war %d", id)
		}
		for _, side := range [][]int{war.Attackers, war.Defenders} {
			for _, p := range side {
				if p <= 0 || p >= len(h.polities) {
					return fmt.Errorf("invalid participant of war %d", id)
				}
			}
		}
	}
	for id, m := range h.migrations {
		if m.ID != id || m.People < 0 || m.People >= len(h.peoples) || !finite(m.Population) || m.Population < 0 {
			return fmt.Errorf("invalid migration %d", id)
		}
	}
	for k, e := range h.events {
		if k > 0 && e.ID != h.events[k-1].ID+1 {
			return fmt.Errorf("event ID gap at %d", k)
		}
		if k >= len(h.eventText) || h.eventText[k].EventID != e.ID {
			return fmt.Errorf("event/narrative mismatch at %d", k)
		}
	}
	return nil
}
