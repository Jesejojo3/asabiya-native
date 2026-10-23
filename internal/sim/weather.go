package sim

import "math"

// weather is the complete v0.6 process (948–957), including the unrounded
// interpolation value in exp(), stored AG/anom/wm float32 and dry epochs.
func (h *history) weather() {
	h.prepareAnnualState()
	w := h.world
	phi := h.rules.get("climPersist")
	sd := math.Sqrt(1 - phi*phi)
	cv := .28 * h.rules.get("climVar")
	for k := range h.ag {
		h.ag[k] = float32(phi*float64(h.ag[k]) + sd*gauss(h.r))
	}
	e := h.epoch
	ramp := 0.0
	if e != nil && e.Kind == "dry" {
		ramp = max64(0, min64(1, min64(float64(h.year-e.Start)/20, float64(e.End-h.year)/20)))
	} else {
		e = nil
	}
	for _, i := range w.landList {
		ids, f := w.weatherIndices[i], w.weatherFractions[i]
		fx, fy := float64(f[0]), float64(f[1])
		a := (float64(h.ag[ids[0]])*(1-fx)+float64(h.ag[ids[1]])*fx)*(1-fy) + (float64(h.ag[ids[2]])*(1-fx)+float64(h.ag[ids[3]])*fx)*fy
		if e != nil {
			dx := math.Abs(float64(int(i)%w.config.Width - e.CX))
			if dx > float64(w.config.Width)/2 {
				dx = float64(w.config.Width) - dx
			}
			dy := float64(int(i)/w.config.Width - e.CY)
			d2 := (dx*dx + dy*dy) / (e.Radius * e.Radius)
			if d2 < 1 {
				a += e.Amp * ramp * (1 - d2)
			}
		}
		h.anom[i] = float32(a)
		h.wm[i] = float32(math.Exp(cv * a))
	}
}
