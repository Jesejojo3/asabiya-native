package sim

import (
	"fmt"
	"math"
	"strings"
)

func (h *history) foundReligion(o *Polity) {
	cells := h.polCells(o.ID)
	if len(cells) == 0 {
		return
	}
	r := h.r
	c := pick(r, cells)
	l := h.langAt(c)
	var e *People
	if h.eth[c] >= 0 {
		e = h.peoples[h.eth[c]]
	}
	prophet := h.newRuler(l, nil)
	prophet.Epithet = ""
	prophet.Birth = h.year - (25 + int(r.Float64()*15))
	prophet.Death = prophet.Birth + 55 + int(r.Float64()*25)
	f := h.figFor(nil, prophet, "prophet")
	f.Polity = o.ID
	f.People = int(h.eth[c])
	people := "people"
	family := -1
	if e != nil {
		people = e.Name
		family = e.Family
	}
	f.Title = "Prophet of the " + people
	f.Died = prophet.Death
	god, base := capFirst(l.Lex[LexGod]), prophet.Base
	name := pick(r, []string{god + "ism", "the Way of " + base, "the " + god + " Covenant", "the Faith of " + god, base + "ism", "the " + capFirst(l.Lex[LexSun]) + " Path"})
	universal := r.Float64() < .65
	if h.city[c] < 0 {
		h.newCity(c, true)
	}
	kind, miss, cent := "ethnic", .15, .1
	if universal {
		kind = "universal"
		miss = .35 + .65*r.Float64()
		cent = .3 + .4*r.Float64()
	}
	religion := &Religion{ID: len(h.religions), Name: name, Founder: f.ID, Born: h.year, Origin: c, Holy: c, Polity: o.ID, People: int(h.eth[c]), Family: family, Kind: kind, Missionary: miss, Centralization: cent, Holder: o.ID, RGB: hsl(r.Float64()*360, .55, .48), Parent: -1, Alive: true}
	h.religions = append(h.religions, religion)
	f.Religion = religion.ID
	h.religion[c] = int32(religion.ID)
	for _, j := range h.world.neighbors[c] {
		if j >= 0 && h.pop[j] >= 1 && h.pol[j] == int32(o.ID) {
			h.religion[j] = int32(religion.ID)
		}
	}
	h.deed(f, "Began to preach "+name+" in the "+o.Full)
	extra := ""
	if universal {
		extra = ", a faith open to every people"
	}
	h.chron("faith", fmt.Sprintf("The prophet %s begins to preach %s in the %s%s.", f.Name, name, o.Full, extra), c)
	h.spot("The prophet "+f.Name+" begins to preach "+name, c)
}
func (h *history) holyName(r *Religion) string {
	c := h.city[r.Holy]
	if c >= 0 {
		return h.cities[c].Name
	}
	return "its holy city"
}

func (h *history) relPass() {
	h.prepareAnnualState()
	w := h.world
	n := len(h.religions)
	if n == 0 {
		return
	}
	sx, sy, sz, pop := make([]float64, n), make([]float64, n), make([]float64, n), make([]float64, n)
	counts := make([]int, n)
	for _, i := range w.landList {
		e := h.religion[i]
		if e < 0 || h.pop[i] < 1 {
			continue
		}
		sx[e] += float64(w.x3[i])
		sy[e] += float64(w.y3[i])
		sz[e] += float64(w.z3[i])
		counts[e]++
		pop[e] += float64(h.pop[i])
	}
	for e := 0; e < n; e++ {
		r := h.religions[e]
		r.Cells = counts[e]
		r.Population = pop[e]
		if counts[e] > r.Peak {
			r.Peak = counts[e]
		}
		if r.Alive && counts[e] == 0 {
			r.Alive = false
			r.Died = h.year
			if r.Peak >= 30 {
				h.chron("faith", fmt.Sprintf("The last followers of %s are gone; at its height it held %d provinces.", r.Name, r.Peak), r.Origin)
			}
		}
		if counts[e] > 0 {
			norm := math.Sqrt(sx[e]*sx[e] + sy[e]*sy[e] + sz[e]*sz[e])
			if norm == 0 {
				norm = 1
			}
			sx[e] /= norm
			sy[e] /= norm
			sz[e] /= norm
			r.Lon = math.Atan2(sy[e], sx[e])
			r.Lat = math.Asin(clamp(sz[e], -1, 1))
		}
		if !r.Alive {
			continue
		}
		hp := h.pol[r.Holy]
		var holder *Polity
		if hp != 0 {
			holder = h.polities[hp]
		}
		faithful := holder != nil && holder.Religion == r.ID
		if faithful {
			r.Centralization = clamp(r.Centralization+.04*(.3+float64(h.tech[TechWriting][r.Holy])), 0, 1)
		} else {
			r.Centralization = clamp(r.Centralization-.05, 0, 1)
		}
		if holder != nil && holder.ID != r.Holder && r.Peak >= 20 {
			if !faithful && holder.Religion >= 0 {
				h.chron("faith", fmt.Sprintf("The holy city of %s falls to the %s, who follow %s; the faithful of %s lose their centre.", h.holyName(r), holder.Full, h.religions[holder.Religion].Name, r.Name), r.Holy)
			} else if faithful && r.Holder != 0 && h.polities[r.Holder] != nil && h.polities[r.Holder].Religion != r.ID {
				h.chron("faith", fmt.Sprintf("The faithful of %s recover their holy city of %s under the %s.", r.Name, h.holyName(r), holder.Full), r.Holy)
			}
		}
		r.Holder = 0
		if holder != nil {
			r.Holder = holder.ID
		}
	}
	md, far := make([]float64, n), make([]CellID, n)
	for e := 0; e < n; e++ {
		md[e] = 2
		far[e] = NoCell
	}
	for _, i := range w.landList {
		e := h.religion[i]
		if e < 0 || h.pop[i] < 1 {
			continue
		}
		d := float64(w.x3[i])*sx[e] + float64(w.y3[i])*sy[e] + float64(w.z3[i])*sz[e]
		if d < md[e] {
			md[e] = d
			far[e] = i
		}
	}
	threshold, made := 14*2*math.Pi/float64(w.config.Width), 0
	for e := 0; e < n && made < 3; e++ {
		r := h.religions[e]
		if !r.Alive || counts[e] < 40 || far[e] < 0 || math.Acos(clamp(md[e], -1, 1)) < threshold {
			continue
		}
		cell := far[e]
		age := float64(h.year-r.Born) / 1000
		chance := .12 * h.rules.get("faith") * (1 - .7*r.Centralization) * (1 + 1.5*float64(h.tech[TechPaper][cell])) * (1 + .5*math.Min(2, age))
		if h.r.Float64() > chance {
			continue
		}
		if r.Centralization > .55 && h.r.Float64() < r.Centralization*.7 {
			r.Councils++
			if r.Peak >= 30 {
				h.chron("faith", "A council at "+h.holyName(r)+" settles a dispute that threatened to split "+r.Name+".", r.Holy)
			}
			continue
		}
		l := h.langAt(cell)
		prophet := h.newRuler(l, nil)
		prophet.Epithet = ""
		prophet.Birth = h.year - 30
		prophet.Death = h.year + 20 + int(h.r.Float64()*25)
		f := h.figFor(nil, prophet, "reformer")
		f.Polity = int(h.pol[cell])
		f.People = int(h.eth[cell])
		f.Title = "Reformer"
		f.Died = prophet.Death
		core := strings.TrimPrefix(r.Name, "the ")
		// All array elements are evaluated before pick; the unused word still draws.
		names := []string{"Reformed " + core, capFirst(word(l, h.r, 0)) + "ism", "the New " + core, "the " + prophet.Base + " Church"}
		name := pick(h.r, names)
		if h.city[cell] < 0 {
			h.newCity(cell, true)
		}
		child := &Religion{ID: len(h.religions), Name: name, Founder: f.ID, Born: h.year, Origin: cell, Holy: cell, Polity: int(h.pol[cell]), People: int(h.eth[cell]), Family: r.Family, Kind: r.Kind, Missionary: clamp(r.Missionary+gauss(h.r)*.15, .1, 1), Centralization: .25, Holder: int(h.pol[cell]), RGB: hsl(h.r.Float64()*360, .5, .5), Parent: e, Alive: true}
		h.religions = append(h.religions, child)
		r.Kids = append(r.Kids, child.ID)
		f.Religion = child.ID
		made++
		for _, i := range w.landList {
			if h.religion[i] != int32(e) {
				continue
			}
			if float64(w.x3[i])*float64(w.x3[cell])+float64(w.y3[i])*float64(w.y3[cell])+float64(w.z3[i])*float64(w.z3[cell]) > float64(w.x3[i])*sx[e]+float64(w.y3[i])*sy[e]+float64(w.z3[i])*sz[e] {
				h.religion[i] = int32(child.ID)
			}
		}
		h.deed(f, "Broke with "+r.Name+" and founded "+name)
		h.chron("faith", fmt.Sprintf("A schism splits %s: followers of the reformer %s form %s.", r.Name, f.Name, name), cell)
	}
}
