package sim

import "strconv"

// fy's BCE offset and en-US integer grouping; presentation only, no ICU.
func formatYear(y int) string {
	if y > 0 {
		return strconv.Itoa(y) + " CE"
	}
	text := strconv.Itoa(1 - y)
	for p := len(text) - 3; p > 0; p -= 3 {
		text = text[:p] + "," + text[p:]
	}
	return text + " BCE"
}
