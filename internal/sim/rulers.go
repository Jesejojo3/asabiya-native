package sim

import "math"

func (h *history) titleOf(o *Polity, r *Ruler) string {
	style := v06.styleByName["romance"]
	fam := -1
	if o.Core >= 0 && o.Core < len(h.peoples) {
		e := h.peoples[o.Core]
		style = e.Language.style()
		fam = e.Family
	}
	st := style.Titles
	switch o.Tier {
	case "Chiefdom", "Clans":
		return st["c"]
	case "Horde", "Confederation", "Khanate":
		return st["h"]
	case "Kingdom":
		if st["k"] == "king" && r.Female {
			return "queen"
		}
		return st["k"]
	default:
		if t, ok := h.familyTitles[fam]; ok {
			return t.Word
		}
		if st["e"] == "emperor" && r.Female {
			return "empress"
		}
		if st["k"] == "khan" {
			return "khagan"
		}
		return st["e"]
	}
}
func (h *history) rulerName(o *Polity) string {
	text := h.titleOf(o, o.Ruler) + " " + o.Ruler.Name
	if o.Ruler.Epithet != "" {
		text += " " + o.Ruler.Epithet
	}
	return text
}
func (h *history) newRuler(l *Language, o *Polity) *Ruler {
	r := h.r
	tri := func() float64 { return (r.Float64() + r.Float64() + r.Float64()) / 3 }
	base, num := personName(l, r), 0
	if o != nil && len(o.Rulers) > 0 && r.Float64() < .4 {
		famous := make([]RulerRecord, 0)
		for _, x := range o.Rulers {
			if x.Figure >= 0 {
				famous = append(famous, x)
			}
		}
		pool := o.Rulers
		if len(famous) > 0 && r.Float64() < .7 {
			pool = famous
		}
		b := pick(r, pool).Base
		if b != "" {
			base = b
		}
	}
	if o != nil {
		if o.NameUse == nil {
			o.NameUse = make(map[string]int)
		}
		num = o.NameUse[base] + 1
		o.NameUse[base] = num
	}
	name := base
	if num > 1 {
		name += " " + roman(num)
	}
	ruler := &Ruler{ID: len(h.rulers), Base: base, Name: name, Female: r.Float64() < .15, Aggression: tri(), Competence: tri(), Charisma: tri(), Piety: tri(), Since: h.year, Figure: -1}
	accession := 16 + r.Float64()*28
	ruler.Birth = h.year - int(math.Floor(accession))
	ruler.Death = int(math.Floor(clamp(50+gauss(r)*14, accession+1, 88)))
	if r.Float64() < h.rules.get("leaderFlair") {
		kind := pick(r, []string{"aggr", "comp", "char", "piety"})
		value := .93 + .07*r.Float64()
		ruler.Exceptional = kind
		var epithets []string
		switch kind {
		case "aggr":
			ruler.Aggression = value
			epithets = []string{"the Great", "the Conqueror", "the Terrible"}
		case "comp":
			ruler.Competence = value
			epithets = []string{"the Wise", "the Lawgiver", "the Builder"}
		case "char":
			ruler.Charisma = value
			epithets = []string{"the Beloved", "the Radiant", "the Lion"}
		default:
			ruler.Piety = value
			epithets = []string{"the Pious", "the Saint", "the Devout"}
		}
		ruler.Epithet = pick(r, epithets)
	}
	h.rulers = append(h.rulers, ruler)
	return ruler
}
func (h *history) figFor(o *Polity, r *Ruler, kind string) *Figure {
	if r.Figure >= 0 {
		return h.figures[r.Figure]
	}
	name := r.Name
	if r.Epithet != "" {
		name += " " + r.Epithet
	}
	f := &Figure{ID: len(h.figures), Name: name, Kind: kind, People: -1, Born: r.Birth, Religion: -1, Exceptional: r.Exceptional}
	if o != nil {
		f.Polity = o.ID
		f.People = o.Core
		f.Title = capFirst(h.titleOf(o, r)) + " of the " + o.Full
	}
	h.figures = append(h.figures, f)
	r.Figure = f.ID
	return f
}
func (h *history) deed(f *Figure, text string) {
	f.Deeds = append(f.Deeds, Deed{Year: h.year, Text: text})
}
func (h *history) figScore(f *Figure) float64 {
	score := float64(f.Conquests)*1.5 + float64(f.Realm+len(f.Deeds)*4+f.Works*12)
	if f.Exceptional != "" {
		score += 5
	}
	if f.Religion >= 0 {
		r := h.religions[f.Religion]
		score += 10*math.Sqrt(float64(r.Peak)) + math.Min(100, float64(len(r.States)))*.5
	}
	return score
}
