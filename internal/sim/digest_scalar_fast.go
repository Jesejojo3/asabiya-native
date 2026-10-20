package sim

import (
	"encoding/binary"
	"math"
	"reflect"
	"unsafe"
)

// fastScalarSequence hashes the same [kind u64][bits u64] stream as
// canonicalState.scalarSequence. It only reads contiguous primitive slices
// protected by Simulation's lock. No bytes are retained past this call.
// Other kinds (and arrays) use the unchanged reflection fallback.
func (e *canonicalState) fastScalarSequence(v reflect.Value, kind reflect.Kind) bool {
	if v.Kind() != reflect.Slice || v.Len() == 0 {
		return false
	}
	n := v.Len()
	data := v.UnsafePointer()
	switch kind {
	case reflect.Float32:
		for _, value := range unsafe.Slice((*float32)(data), n) {
			bits := math.Float32bits(value)
			if bits&0x7f800000 == 0x7f800000 && bits&0x007fffff != 0 {
				bits = 0x7fc00000
			}
			e.appendScalarBits(kind, uint64(bits))
		}
	case reflect.Float64:
		for _, value := range unsafe.Slice((*float64)(data), n) {
			bits := math.Float64bits(value)
			if bits&0x7ff0000000000000 == 0x7ff0000000000000 && bits&0x000fffffffffffff != 0 {
				bits = 0x7ff8000000000000
			}
			e.appendScalarBits(kind, bits)
		}
	case reflect.Int32:
		for _, value := range unsafe.Slice((*int32)(data), n) {
			e.appendScalarBits(kind, uint64(int64(value)))
		}
	case reflect.Int:
		for _, value := range unsafe.Slice((*int)(data), n) {
			e.appendScalarBits(kind, uint64(int64(value)))
		}
	case reflect.Uint8:
		for _, value := range unsafe.Slice((*uint8)(data), n) {
			e.appendScalarBits(kind, uint64(value))
		}
	default:
		return false
	}
	return true
}

func (e *canonicalState) appendScalarBits(kind reflect.Kind, bits uint64) {
	if cap(e.buffer)-len(e.buffer) < 16 {
		e.flush()
	}
	start := len(e.buffer)
	e.buffer = e.buffer[:start+16]
	binary.LittleEndian.PutUint64(e.buffer[start:], uint64(kind))
	binary.LittleEndian.PutUint64(e.buffer[start+8:], bits)
}
