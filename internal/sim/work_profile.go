package sim

import ("time"; "sync")

// WorkProfile is observational state, deliberately owned by Simulation rather
// than history: profiling cannot enter the causal digest, RNG or replay.
type WorkProfile struct { Years uint64 `json:"years"`; Nanoseconds [13]int64 `json:"nanoseconds"` }
var ProfileStages = []string{"climate-weather-hearth","carrying","demography","migration","technology","disease-contact","politics-omens","people-religion","events-statistics-snapshots","map-before","digest","map-after","entities-metadata"}
type workAccumulator struct { mu sync.Mutex; data WorkProfile }
func (s *Simulation) EnableWorkProfile() { s.mu.Lock(); defer s.mu.Unlock(); s.workProfile = &workAccumulator{} }
func (s *Simulation) WorkProfile() WorkProfile { s.mu.RLock(); defer s.mu.RUnlock(); if s.workProfile == nil { return WorkProfile{} }; s.workProfile.mu.Lock(); defer s.workProfile.mu.Unlock(); return s.workProfile.data }
type workClock struct { profile *workAccumulator; start time.Time }
func startWork(p *workAccumulator) workClock { c := workClock{profile:p}; if p != nil { c.start=time.Now() }; return c }
func (c *workClock) mark(stage int) { if c.profile != nil { now:=time.Now(); c.profile.mu.Lock(); c.profile.data.Nanoseconds[stage] += now.Sub(c.start).Nanoseconds(); c.profile.mu.Unlock(); c.start=now } }

func (s *Simulation) LivingStates() int { s.mu.RLock();defer s.mu.RUnlock();n:=0;for _,id:=range s.h.alive {p:=s.h.polities[id];if p!=nil && p.Alive && p.Kind!="horde" && p.Cells>=2 {n++}};return n }
