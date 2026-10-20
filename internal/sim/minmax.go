package sim

import "math"

// Typed wrappers retain math.Min/Max's float64 argument conversions. The Go
// intrinsics avoid out-of-line calls in normal per-province numeric loops.
// NaN uses the original functions: math.Min(-Inf,NaN) and Max(+Inf,NaN)
// deliberately prioritize the infinity, unlike the language builtins.
func min64(a, b float64) float64 {
	v := min(a, b)
	if v != v {
		return math.Min(a, b)
	}
	return v
}
func max64(a, b float64) float64 {
	v := max(a, b)
	if v != v {
		return math.Max(a, b)
	}
	return v
}
