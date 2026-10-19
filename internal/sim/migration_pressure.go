package sim

import (
	"fmt"
	"math"
	"strconv"
)

func (w *World) dxWrap(a, b CellID) int {
	d := int(b)%w.config.Width - int(a)%w.config.Width
	if float64(d) > float64(w.config.Width)/2 {
		d -= w.config.Width
	}
	if float64(d) < -float64(w.config.Width)/2 {
		d += w.config.Width
	}
	return d
}
func dirWord(dx, dy float64) string {
	a := math.Atan2(-dy, dx) * 180 / math.Pi
	k := int(jsRound(math.Mod(a+360, 360)/45)) % 8
	return [...]string{"east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east"}[k]
}
func fmtK(n float64) string {
	if n >= 1e6 {
		return strconv.FormatFloat(n/1e6, 'f', 1, 64) + " million"
	}
	if jsRound(n/1000)*1000 >= 1000 {
		return strconv.FormatFloat(jsRound(n/1000), 'f', 0, 64) + " thousand"
	}
	return strconv.FormatFloat(jsRound(n), 'f', 0, 64)
}

func (h *history) milAt(c CellID) float64 {
	w := h.world
	t := func(k int) float64 { return float64(h.tech[k][c]) }
	ts, nom, des := 1.0, 0.0, 0.0
	if w.tsetse[c] {
		ts = .15
	}
	if w.nomad[c] {
		nom = 1
	}
	if w.desert[c] {
		des = 1
	}
	return 1 + .4*t(TechCopper) + .3*t(TechWheel)*ts + .5*t(TechIron) + ts*(t(TechHorse)*(.3+nom*.9)+.6*t(TechCavalry)*(.5+nom*.5)) + 1.2*t(TechGunpowder) + .2*t(TechWriting) + .3*t(TechCamel)*des
}

func (h *history) pushPressure(people int, amount float64, cell CellID, byPol, fromMigration int) {
	if people < 0 || amount < 1 {
		return
	}
	h.prepareAnnualState()
	m := h.pressure.Value(people)
	if m == nil || h.year-m.Year > 40 {
		m = &migrationPressure{Year: h.year, Cell: cell, By: byPol, Migration: fromMigration}
		h.pressure.Set(people, m)
	}
	m.Population += amount
	m.Cell = cell
	if byPol != 0 {
		m.By = byPol
	}
	if fromMigration >= 0 {
		m.Migration = fromMigration
	}
	e := h.peoples[people]
	if m.Population > 80000 && len(h.activeMigrations) < 10 && h.r.Float64() < .35*h.rules.get("wander") && !(e.LastMigration != 0 && h.year-e.LastMigration < 150) {
		h.pressure.Delete(people)
		e.LastMigration = h.year
		dx, dy := 0.0, 0.0
		var by *Polity
		if m.By > 0 {
			by = h.polities[m.By]
		}
		if by != nil && by.Alive {
			dx = -float64(h.world.dxWrap(cell, by.Capital))
			dy = -float64(int(by.Capital)/h.world.config.Width - int(cell)/h.world.config.Width)
		}
		if m.Migration >= 0 && m.Migration < len(h.migrations) {
			old := h.migrations[m.Migration]
			dx, dy = old.DX, old.DY
		}
		if dx == 0 && dy == 0 {
			a := h.r.Float64() * 6.28
			dx, dy = math.Cos(a), math.Sin(a)
		}
		h.startMigration(people, m.Population, cell, dx, dy, "people", nil, by, m.Migration, "")
	}
}

func (h *history) startMigration(people int, pop float64, cell CellID, dx, dy float64, kind string, pol, by *Polity, previous int, cause string) *Migration {
	e := h.peoples[people]
	norm := math.Hypot(dx, dy)
	if norm == 0 {
		norm = 1
	}
	m := &Migration{ID: len(h.migrations), People: people, Religion: int(h.religion[cell]), Name: e.Name, Population: pop, Cell: cell, DX: dx / norm, DY: dy / norm, Path: []CellID{cell}, Kind: kind, Start: h.year, Max: 20 + int(h.r.Float64()*25), Cohesion: .75, Military: h.milAt(cell), Farm: float64(h.tech[TechFarm][cell]), Herd: float64(h.tech[TechHerd][cell]), Previous: previous, Cause: cause}
	if pol != nil {
		m.Polity = pol.ID
		if kind == "horde" {
			m.Name = pol.Full
		}
	}
	if by != nil {
		m.By = by.ID
	}
	for k := range h.tech {
		m.Techs[k] = h.tech[k][cell]
	}
	h.migrations = append(h.migrations, m)
	h.activeMigrations = append(h.activeMigrations, m.ID)
	dir := dirWord(m.DX, m.DY)
	text := ""
	switch {
	case kind == "horde":
		intro := "Hungry for richer lands"
		if cause == "drought" {
			intro = "Driven from parched pastures"
		}
		text = fmt.Sprintf("%s, the %s sets out %sward, some %s strong.", intro, m.Name, dir, fmtK(m.Population))
	case previous >= 0:
		old := h.migrations[previous]
		text = fmt.Sprintf("Fleeing the %s, the %s take to the roads and head %s, %s people in all.", old.Name, e.Name, dir, fmtK(m.Population))
	case by != nil:
		text = fmt.Sprintf("Driven out by the %s, the %s take to the roads and head %s, %s people in all.", by.Full, e.Name, dir, fmtK(m.Population))
	default:
		text = fmt.Sprintf("The %s take to the roads and head %s, %s people in all.", e.Name, dir, fmtK(m.Population))
	}
	m.StartText = text
	m.Logged = m.Population >= 100000 || kind == "horde" || previous >= 0
	if m.Logged {
		h.chron("migration", text, cell)
	}
	if m.Population > 400000 {
		verb := "are"
		if kind == "horde" {
			verb = "is"
		}
		h.spot(fmt.Sprintf("The %s %s on the move", m.Name, verb), cell)
	}
	return m
}
