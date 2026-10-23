package sim

import (
	"fmt"
	"math"
	"slices"
)

func (h *history) migStep(m *Migration) {
	if m.Done {
		return
	}
	w, r := h.world, h.r
	best, score := NoCell, -1e9
	c := m.Cell
	cx, cy := int(c)%w.config.Width, int(c)/w.config.Width
	for dy := -1; dy <= 1; dy++ {
		yy := cy + dy
		if yy < 0 || yy >= w.config.Height {
			continue
		}
		for dx := -1; dx <= 1; dx++ {
			j := CellID(yy*w.config.Width + (cx+dx+w.config.Width)%w.config.Width)
			if j == c || !w.land[j] || w.temperature[j] < -9 {
				continue
			}
			capacity, pop := float64(h.K[j]), float64(h.pop[j])
			room := -1.
			if capacity > 1 {
				room = clamp((capacity-pop)/(capacity+1), -1, 1)
			}
			value := 2.2*(float64(dx)*m.DX+float64(dy)*m.DY)/math.Hypot(float64(dx), float64(dy)) - .15*(float64(w.travelCost[j])-2)*h.rules.get("terrain") + .8*room + r.Float64()*.7
			if slices.Contains(m.Path, j) {
				value -= 3
			}
			if w.desert[j] && m.Kind != "horde" {
				value -= 1
			}
			if value > score {
				score = value
				best = j
			}
		}
	}
	if best < 0 {
		h.disperse(m, "trapped")
		return
	}
	j := best
	m.Cell = j
	m.Steps++
	m.Population *= .985
	if len(m.Path) < 240 {
		m.Path = append(m.Path, j)
	}
	q := h.pol[j]
	if q != 0 && int(q) != m.Polity {
		t := h.polities[q]
		attack := math.Pow(m.Population, .75) * m.Cohesion * m.Military
		defense := h.defense(j)
		if t.Kind == "horde" {
			defense *= .8
		}
		if r.Float64() < clamp((attack-defense)/(attack+defense)*1.6+.12, .04, .92) {
			m.Population *= .94
			h.displace(j, .25, 0)
			if p := h.pressure.Value(int(h.eth[j])); p != nil {
				p.Migration = m.ID
			}
			if t.Cells >= 20 {
				t.Shock += .08
			} else {
				t.Shock += .02
			}
			if !slices.Contains(m.Broke, int(q)) {
				m.Broke = append(m.Broke, int(q))
				if t.Cells >= 20 {
					if !m.Logged {
						m.Logged = true
						h.chron("migration", m.StartText, m.Path[0])
					}
					h.chron("migration", "The "+m.Name+" break through the frontier of the "+t.Full+".", j)
					t.Invaded++
				}
			}
			if (m.Steps >= 3 && r.Float64() < .12) || m.Steps > m.Max {
				h.settle(m, j, t)
			}
		} else {
			m.Population *= .8
			m.Fails++
			sign := -1.
			if r.Float64() < .5 {
				sign = 1
			}
			angle := sign * (.8 + r.Float64()*.9)
			cos, sin := math.Cos(angle), math.Sin(angle)
			x, y := m.DX*cos-m.DY*sin, m.DX*sin+m.DY*cos
			m.DX = x
			m.DY = y
			if m.Fails > 5 {
				h.settle(m, m.Path[max(0, len(m.Path)-2)], nil)
			}
		}
	} else {
		if h.pop[j] > 1000 && h.eth[j] >= 0 && int(h.eth[j]) != m.People {
			h.displace(j, .15, 0)
			if p := h.pressure.Value(int(h.eth[j])); p != nil {
				p.Migration = m.ID
			}
		}
		room := float64(h.K[j]) - float64(h.pop[j])
		if (room > m.Population*.15 && m.Steps > 4 && r.Float64() < .25) || m.Steps > m.Max {
			h.settle(m, j, nil)
		}
	}
	if !m.Done && m.Population < 15000 {
		h.disperse(m, "dwindled")
	}
}
func (h *history) disperse(m *Migration, why string) {
	m.Done = true
	m.End = h.year
	m.Result = "dwindled and scattered"
	if why == "trapped" {
		m.Result = "trapped and scattered"
	}
	if m.Population > 0 && m.Cell >= 0 {
		h.pop[m.Cell] = float32(float64(h.pop[m.Cell]) + m.Population*.5)
	}
	h.activeMigrations = slices.DeleteFunc(h.activeMigrations, func(k int) bool { return k == m.ID })
	if m.Logged && len(m.Path) > 8 {
		h.chron("migration", fmt.Sprintf("The %s %s after %d years of wandering.", m.Name, m.Result, h.year-m.Start), m.Cell)
	}
}
func (h *history) settle(m *Migration, j CellID, t *Polity) {
	m.Done = true
	m.End = h.year
	h.activeMigrations = slices.DeleteFunc(h.activeMigrations, func(k int) bool { return k == m.ID })
	w := h.world
	cells := []CellID{}
	w.ring(j, 2, func(c CellID) {
		if w.land[c] && w.temperature[c] > -9 && len(cells) < 9 {
			cells = append(cells, c)
		}
	})
	per := m.Population / float64(len(cells))
	for _, c := range cells {
		old, people := float64(h.pop[c]), h.eth[c]
		h.pop[c] = float32(float64(h.pop[c]) + per)
		if people < 0 || old < 1 {
			h.eth[c] = int32(m.People)
			h.eth2[c] = -1
		} else if int(people) != m.People {
			if per > old {
				h.eth[c] = int32(m.People)
				h.eth2[c] = people
				h.mix[c] = float32(old / (old + per))
			} else {
				h.eth2[c] = int32(m.People)
				h.mix[c] = float32(per / (old + per))
			}
			h.mixTime[c] = 0
		}
		if m.Religion >= 0 && per > old {
			h.religion[c] = int32(m.Religion)
		}
		for k := range h.tech {
			h.tech[k][c] = float32(math.Max(float64(h.tech[k][c]), float64(m.Techs[k])*.8))
		}
	}
	var o *Polity
	farmland := float64(w.farmSuitability[j]) > .3 && m.Farm > .5
	if m.Population > 100000 {
		kind := "horde"
		if farmland {
			kind = "state"
		}
		from := 0
		if t != nil {
			from = t.ID
		}
		id := h.newPolity(j, nil, polityOptions{Kind: kind, Origin: &PolityOrigin{Type: "migration", Migration: m.ID, People: m.People, From: from}, ConquestDynasty: t != nil})
		o = h.polities[id]
		o.S = .7
		for _, c := range cells {
			h.pol[c] = int32(id)
			h.cohesion[c] = float32(math.Max(float64(h.cohesion[c]), .65))
		}
	}
	m.SettledPolity = 0
	m.Result = "settled among the locals"
	if o != nil {
		m.SettledPolity = o.ID
		m.Result = "settled and founded the " + o.Full
	}
	if m.Logged || o != nil {
		lands := ""
		if t != nil {
			lands = " in the lands of the " + t.Full
		}
		founded := " and mingle with the people there"
		if o != nil {
			founded = " and found the " + o.Full
		}
		h.chron("migration", fmt.Sprintf("After %d years on the move, the %s settle%s%s.", h.year-m.Start, m.Name, lands, founded), j)
	}
	if o != nil && t != nil && t.Cells >= 30 {
		h.spot("The "+m.Name+" found the "+o.Full+" inside the "+t.Full, j)
	}
}
func (h *history) hordeMigration(o *Polity) {
	cells := h.polCells(o.ID)
	if len(cells) == 0 {
		return
	}
	var best *Polity
	population := 0.
	o.NB.Each(func(q, _ int) {
		t := h.polities[q]
		if t != nil && t.Alive && t.Kind == "state" && t.Pop > population {
			population = t.Pop
			best = t
		}
	})
	total := 0.
	for _, c := range cells {
		taken := float64(h.pop[c]) * .6
		h.pop[c] = float32(float64(h.pop[c]) - taken)
		total += taken
	}
	dx, dy := 0., 0.
	if best != nil {
		dx = float64(h.world.dxWrap(o.Capital, best.Capital))
		dy = float64(int(best.Capital)/h.world.config.Width - int(o.Capital)/h.world.config.Width)
	} else {
		angle := h.r.Float64() * 6.28
		dx = math.Cos(angle)
		dy = math.Sin(angle)
	}
	o.Shock += .4
	cause := "riches"
	if o.Wet < -.4 {
		cause = "drought"
	}
	h.startMigration(o.Core, total, o.Capital, dx, dy, "horde", o, nil, -1, cause)
}
