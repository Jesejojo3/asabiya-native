package sim

import "slices"

// Event carries structured identity independently of the English legacy text.
// A client may localize known event kinds; prose is never parsed by simulation.
type EntityRef struct {
	Kind string `json:"kind"`
	ID   int    `json:"id"`
}
type Event struct {
	ID       int         `json:"id"`
	Year     int         `json:"year"`
	Kind     string      `json:"kind"`
	Cell     CellID      `json:"cell"`
	Entities []EntityRef `json:"entities"`
}
type EventText struct {
	EventID int    `json:"eventId"`
	Text    string `json:"text"`
	Why     string `json:"why,omitempty"`
}

func (h *history) recordEvent(kind, text string, cell CellID) {
	id := h.nextEventID
	h.nextEventID++
	h.events = append(h.events, Event{ID: id, Year: h.year, Kind: kind, Cell: cell})
	h.eventText = append(h.eventText, EventText{EventID: id, Text: text})
	if len(h.events) > maxChronicle {
		h.events = slices.Clone(h.events[chronicleTrim:])
		h.eventText = slices.Clone(h.eventText[chronicleTrim:])
	}
}
func (h *history) annotateEvent(why string, refs ...EntityRef) {
	if len(h.events) == 0 {
		return
	}
	k := len(h.events) - 1
	h.events[k].Entities = slices.Clone(refs)
	h.eventText[k].Why = why
}
