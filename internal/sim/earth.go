package sim

import "math"

type WorldRegion struct {
	Key           string     `json:"key"`
	Name          string     `json:"name"`
	Box           [4]float64 `json:"box"`
	ReferenceYear int        `json:"referenceYear"`
	Cells         []CellID   `json:"cells"`
}

var earthRegions = []WorldRegion{
	{Key: "meso", Name: "Mesopotamia", Box: [4]float64{29, 37, 39, 49}, ReferenceYear: -3099},
	{Key: "egypt", Name: "Egypt", Box: [4]float64{22, 31.5, 29, 34}, ReferenceYear: -3099},
	{Key: "indus", Name: "Indus valley", Box: [4]float64{23, 33, 66, 76}, ReferenceYear: -2599},
	{Key: "nchina", Name: "Yellow River", Box: [4]float64{32, 41, 105, 120}, ReferenceYear: -1899},
	{Key: "mesoam", Name: "Mesoamerica", Box: [4]float64{14, 22, -100, -86}, ReferenceYear: -499},
	{Key: "andes", Name: "Central Andes", Box: [4]float64{-20, -5, -80, -68}, ReferenceYear: -199},
	{Key: "europe", Name: "Western Europe", Box: [4]float64{42, 55, -6, 15}, ReferenceYear: -49},
	{Key: "wafrica", Name: "West Africa", Box: [4]float64{8, 18, -12, 8}, ReferenceYear: 700},
}
var earthNoState = []WorldRegion{
	{Name: "New Guinea", Box: [4]float64{-10, -1, 131, 151}},
	{Name: "Congo interior", Box: [4]float64{-5, 4, 15, 28}},
	{Name: "Amazon interior", Box: [4]float64{-10, 0, -72, -52}},
}
var earthNoFarm = []WorldRegion{
	{Name: "Siberia", Box: [4]float64{55, 75, 60, 180}},
	{Name: "Australia", Box: [4]float64{-40, -11, 113, 154}},
	{Name: "Northern North America", Box: [4]float64{52, 72, -170, -55}},
	{Name: "Southern Africa", Box: [4]float64{-35, -25, 15, 32}},
}

func (w *World) cellAt(latitude, longitude float64) CellID {
	y := int(clamp(math.Floor((90-latitude)/180*float64(w.config.Height)), 0, float64(w.config.Height-1)))
	x := int(math.Floor((longitude+180)/360*float64(w.config.Width))) % w.config.Width
	if x < 0 {
		x += w.config.Width
	}
	return CellID(y*w.config.Width + x)
}
func (w *World) latLon(i CellID) (float64, float64) {
	return float64(w.latitude[i]) * 180 / math.Pi, (float64(int(i)%w.config.Width)+.5)/float64(w.config.Width)*360 - 180
}
func insideBox(lat, lon float64, box [4]float64) bool {
	return lat >= box[0] && lat <= box[1] && lon >= box[2] && lon <= box[3]
}
func (w *World) prepareEarthRegions() {
	for _, r := range earthRegions {
		for _, i := range w.landList {
			lat, lon := w.latLon(i)
			if insideBox(lat, lon, r.Box) {
				r.Cells = append(r.Cells, i)
			}
		}
		w.regions = append(w.regions, r)
	}
	for _, i := range w.landList {
		lat, lon := w.latLon(i)
		if lat >= 21 && lat <= 41 && lon >= 100 && lon <= 122 {
			w.chinaCells = append(w.chinaCells, i)
		}
		if lat < 30 || lat > 46.5 || lon < -10 || lon > 37 {
			continue
		}
		near := false
		w.ring(i, 2, func(j CellID) {
			if near || w.land[j] {
				return
			}
			la, lo := w.latLon(j)
			if lo > -5.6 && !(la > 40.8 && lo > 26.5) && la < 46 && lo < 37 {
				near = true
			}
		})
		if near {
			w.medCells = append(w.medCells, i)
		}
	}
}
func (w *World) Regions() []WorldRegion {
	out := append([]WorldRegion(nil), w.regions...)
	for k := range out {
		out[k].Cells = append([]CellID(nil), out[k].Cells...)
	}
	return out
}

func (h *history) earthFounders() ([]CellID, []string) {
	w, r := h.world, h.r
	pool := make([]string, len(v06.Macros))
	for k, m := range v06.Macros {
		pool[k] = m.Key
	}
	for i := len(pool) - 1; i > 0; i-- {
		j := int(r.Float64() * float64(i+1))
		pool[i], pool[j] = pool[j], pool[i]
	}
	seeds, macros := []CellID{}, []string{}
	for k, s := range []struct {
		lat, lon float64
		macro    string
	}{{5, 25, "afr"}, {33, 40, "afro"}, {48, 10, "ie"}, {22, 78, "indo"}, {35, 110, "sino"}, {5, 105, "aus"}, {-25, 134, "pama"}, {60, 100, "alt"}, {40, -100, "nam"}, {-10, -60, "sam"}} {
		c := w.cellAt(s.lat, s.lon)
		for n := 1; n < 15 && !w.land[c]; n++ {
			c = w.cellAt(s.lat, s.lon+float64(n)*.9)
		}
		if w.land[c] {
			seeds = append(seeds, c)
			mac := s.macro
			if h.rules.ShuffleNames {
				mac = pool[k%len(pool)]
			}
			macros = append(macros, mac)
		}
	}
	return seeds, macros
}
func (h *history) earthHearths() {
	for _, s := range []struct {
		kind         string
		lat, lon     float64
		year         int
		crop, animal string
		grain        float64
	}{
		{"farm", 36.5, 40, -9000, "wheat and barley", "sheep and goats", 1},
		{"farm", 30.5, 112, -7500, "rice", "pigs", 1}, {"farm", 35, 109, -7000, "millet", "pigs and dogs", 1},
		{"farm", -6, 145, -7000, "taro and bananas", "pigs", 0},
		{"farm", 18, -97, -5000, "maize, beans and squash", "turkeys and dogs", 1},
		{"farm", -13, -72, -5000, "potatoes and quinoa", "llamas and guinea pigs", .6},
		{"farm", 14, 2, -3000, "sorghum and pearl millet", "cattle", 1}, {"farm", 37, -88, -2500, "sunflowers and squash", "dogs", .6},
		{"copper", 39, 35, -4700, "", "", 0}, {"copper", 36, 104, -2600, "", "", 0}, {"copper", -14, -72, -1200, "", "", 0},
		{"horse", 48, 50, -3700, "", "", 0}, {"sail", 37, 25, -3500, "", "", 0}, {"sail", 23.5, 120.5, -3000, "", "", 0},
		{"camel", 22, 50, -1200, "", "", 0}, {"ard", 33, 44, -4300, "", "", 0},
	} {
		if s.year < h.start {
			continue
		}
		h.hearths = append(h.hearths, Hearth{Kind: s.kind, Cell: h.world.cellAt(s.lat, s.lon), Year: s.year, Fixed: true, Crop: s.crop, Animal: s.animal, Grain: s.grain, GrainSet: s.kind == "farm"})
	}
}

type RegionalFirst struct {
	Year   int    `json:"year"`
	Polity int    `json:"polityId"`
	Name   string `json:"name"`
}
type RegionalShare struct {
	Year   int     `json:"year"`
	Share  float64 `json:"share"`
	Polity int     `json:"polityId"`
}
type RegionalBest struct {
	RegionalShare
	Name string `json:"name"`
}
type RegionalSurveyEntry struct {
	Name           string  `json:"name"`
	Share          float64 `json:"share"`
	PopulatedCells *int    `json:"populatedCells,omitempty"`
}
type RegionalSurvey struct {
	Year    int                   `json:"year"`
	Results []RegionalSurveyEntry `json:"results"`
}
type EarthHistory struct {
	First             map[string]RegionalFirst `json:"firstStates"`
	China             []RegionalShare          `json:"china"`
	Mediterranean     []RegionalShare          `json:"mediterranean"`
	MediterraneanBest RegionalBest             `json:"mediterraneanBest"`
	StateNow          *RegionalSurvey          `json:"stateNow"`
	FarmNow           *RegionalSurvey          `json:"farmNow"`
	FarmCheck         *RegionalSurvey          `json:"farmCheck"`
}

func (h *history) earthRegionPass() {
	w := h.world
	if w.source.Kind != "earth" {
		return
	}
	if h.earth == nil {
		h.earth = &EarthHistory{First: make(map[string]RegionalFirst)}
	}
	e := h.earth
	var counts orderedMap[int, float64]
	best := func() (float64, int) {
		v, id := 0., 0
		counts.Each(func(p int, n float64) {
			if n > v {
				v, id = n, p
			}
		})
		return v, id
	}
	for _, region := range w.regions {
		if _, ok := e.First[region.Key]; ok {
			continue
		}
		counts.Clear()
		total := 0.
		for _, i := range region.Cells {
			pop := float64(h.pop[i])
			total += pop
			p := int(h.pol[i])
			if p != 0 {
				pol := h.polities[p]
				if pol.Kind == "state" && pol.Tier != "Chiefdom" {
					counts.Set(p, counts.Value(p)+pop)
				}
			}
		}
		v, id := best()
		if total > 0 && v >= .3*total {
			e.First[region.Key] = RegionalFirst{Year: h.year, Polity: id, Name: h.polities[id].Full}
		}
	}
	share := func(cells []CellID) RegionalShare {
		counts.Clear()
		for _, i := range cells {
			p := int(h.pol[i])
			if p == 0 {
				continue
			}
			wt := 1.
			o := h.polities[p]
			if o.Over != 0 && h.polities[o.Over] != nil && h.polities[o.Over].Alive {
				p = o.Over
				wt = .6
			}
			counts.Set(p, counts.Value(p)+wt)
		}
		v, id := best()
		if len(cells) > 0 {
			v /= float64(len(cells))
		}
		return RegionalShare{Year: h.year, Share: v, Polity: id}
	}
	e.China = append(e.China, share(w.chinaCells))
	med := share(w.medCells)
	e.Mediterranean = append(e.Mediterranean, med)
	if med.Share > e.MediterraneanBest.Share {
		name := ""
		if med.Polity != 0 {
			name = h.polities[med.Polity].Full
		}
		e.MediterraneanBest = RegionalBest{RegionalShare: med, Name: name}
	}
	if h.year%100 != 0 && !(h.year >= 0 && e.FarmCheck == nil) {
		return
	}
	survey := func(regions []WorldRegion, farm bool) *RegionalSurvey {
		out := &RegionalSurvey{Year: h.year}
		for _, region := range regions {
			pc, count := 0, 0
			for _, i := range w.landList {
				lat, lon := w.latLon(i)
				if !insideBox(lat, lon, region.Box) || h.pop[i] < 1 {
					continue
				}
				pc++
				if farm {
					if float64(h.tech[TechFarm][i]) > .5 && float64(w.farmSuitability[i]) > .15 {
						count++
					}
				} else {
					p := int(h.pol[i])
					if p != 0 && h.polities[p].Kind == "state" && h.polities[p].Tier != "Chiefdom" {
						count++
					}
				}
			}
			entry := RegionalSurveyEntry{Name: region.Name}
			if pc > 0 {
				entry.Share = float64(count) / float64(pc)
			}
			if !farm {
				n := pc
				entry.PopulatedCells = &n
			}
			out.Results = append(out.Results, entry)
		}
		return out
	}
	e.StateNow = survey(earthNoState, false)
	e.FarmNow = survey(earthNoFarm, true)
	if h.year >= 0 && e.FarmCheck == nil {
		e.FarmCheck = e.FarmNow
	}
}

func (h *history) earthView() *EarthHistory {
	if h.earth == nil {
		return nil
	}
	out := *h.earth
	out.First = make(map[string]RegionalFirst, len(h.earth.First))
	for k, v := range h.earth.First {
		out.First[k] = v
	}
	out.China = append([]RegionalShare(nil), out.China...)
	out.Mediterranean = append([]RegionalShare(nil), out.Mediterranean...)
	clone := func(s *RegionalSurvey) *RegionalSurvey {
		if s == nil {
			return nil
		}
		v := *s
		v.Results = append([]RegionalSurveyEntry(nil), s.Results...)
		for k := range v.Results {
			if p := v.Results[k].PopulatedCells; p != nil {
				n := *p
				v.Results[k].PopulatedCells = &n
			}
		}
		return &v
	}
	out.StateNow = clone(out.StateNow)
	out.FarmNow = clone(out.FarmNow)
	out.FarmCheck = clone(out.FarmCheck)
	return &out
}
