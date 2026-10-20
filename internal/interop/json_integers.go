package interop

import (
	"encoding/json"
	"strconv"
	"strings"
)

// normalizeJSONIntegers changes only the spelling of exact integral JSON
// numbers, e.g. 4.0 or 40e-1 to 4. Godot can emit these spellings for integers.
// It never parses through float64: 4.0000000000000001 must remain fractional.
// The normal JSON decoder still enforces the destination's signedness/range,
// field types and unknown-field policy. This is only a transport adaptation;
// simulation types, saved files and engine validation are unchanged.
func normalizeJSONIntegers(raw []byte) []byte {
	if !json.Valid(raw) {
		return raw // Let encoding/json report the original syntax error.
	}
	out := make([]byte, 0, len(raw))
	for i := 0; i < len(raw); {
		start := i
		switch {
		case raw[i] == '"':
			i++
			for i < len(raw) {
				if raw[i] == '\\' {
					i += 2
				} else if raw[i] == '"' {
					i++
					break
				} else {
					i++
				}
			}
			out = append(out, raw[start:i]...)
		case raw[i] == '-' || (raw[i] >= '0' && raw[i] <= '9'):
			i++
			for i < len(raw) && strings.ContainsRune("0123456789.eE+-", rune(raw[i])) {
				i++
			}
			out = append(out, integralSpelling(string(raw[start:i]))...)
		default:
			out = append(out, raw[i])
			i++
		}
	}
	return out
}

// integralSpelling requires a valid JSON number. At most 20 decimal digits are
// needed for any Go integer type. Larger results retain their original spelling
// and are rejected by encoding/json when decoded into an integer. In particular,
// a huge exponent cannot cause an allocation proportional to its numeric value.
func integralSpelling(number string) string {
	mantissa, exponent, hasExponent := strings.Cut(strings.ToLower(number), "e")
	negative := strings.HasPrefix(mantissa, "-")
	mantissa = strings.TrimPrefix(mantissa, "-")
	whole, fraction, _ := strings.Cut(mantissa, ".")
	digits := strings.TrimLeft(whole+fraction, "0")
	if digits == "" {
		if negative {
			return "-0" // Preserve the sign of floating-point zero.
		}
		return "0"
	}
	var exp int64
	if hasExponent {
		var err error
		exp, err = strconv.ParseInt(exponent, 10, 32)
		if err != nil {
			return number
		}
	}
	scale := exp - int64(len(fraction))
	if scale < 0 {
		remove := -scale
		if remove >= int64(len(digits)) {
			return number
		}
		cut := len(digits) - int(remove)
		if strings.Trim(digits[cut:], "0") != "" {
			return number
		}
		digits = digits[:cut]
	} else {
		if int64(len(digits))+scale > 20 {
			return number
		}
		digits += strings.Repeat("0", int(scale))
	}
	if len(digits) > 20 {
		return number
	}
	if negative {
		return "-" + digits
	}
	return digits
}

// UnmarshalJSON covers the envelope as well as payloads: session is uint64 and
// is also sent back by Godot after passing through its JSON number handling.
func (r *Request) UnmarshalJSON(raw []byte) error {
	type requestFields Request
	return json.Unmarshal(normalizeJSONIntegers(raw), (*requestFields)(r))
}
