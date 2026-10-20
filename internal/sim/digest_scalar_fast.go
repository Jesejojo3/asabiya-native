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
		values := unsafe.Slice((*float32)(data), n)
		for len(values) > 0 {
			block, count := e.scalarBlock(len(values))
			for i, value := range values[:count] {
				bits := math.Float32bits(value)
				if bits&0x7f800000 == 0x7f800000 && bits&0x007fffff != 0 {
					bits = 0x7fc00000
				}
				binary.LittleEndian.PutUint64(block[i*16:], uint64(kind))
				binary.LittleEndian.PutUint64(block[i*16+8:], uint64(bits))
			}
			values = values[count:]
		}
	case reflect.Float64:
		values := unsafe.Slice((*float64)(data), n)
		for len(values) > 0 {
			block, count := e.scalarBlock(len(values))
			for i, value := range values[:count] {
				bits := math.Float64bits(value)
				if bits&0x7ff0000000000000 == 0x7ff0000000000000 && bits&0x000fffffffffffff != 0 {
					bits = 0x7ff8000000000000
				}
				binary.LittleEndian.PutUint64(block[i*16:], uint64(kind))
				binary.LittleEndian.PutUint64(block[i*16+8:], bits)
			}
			values = values[count:]
		}
	case reflect.Int:
		appendIntegerScalars(e, kind, unsafe.Slice((*int)(data), n))
	case reflect.Int8:
		appendIntegerScalars(e, kind, unsafe.Slice((*int8)(data), n))
	case reflect.Int16:
		appendIntegerScalars(e, kind, unsafe.Slice((*int16)(data), n))
	case reflect.Int32:
		appendIntegerScalars(e, kind, unsafe.Slice((*int32)(data), n))
	case reflect.Int64:
		appendIntegerScalars(e, kind, unsafe.Slice((*int64)(data), n))
	case reflect.Uint:
		appendIntegerScalars(e, kind, unsafe.Slice((*uint)(data), n))
	case reflect.Uint8:
		appendIntegerScalars(e, kind, unsafe.Slice((*uint8)(data), n))
	case reflect.Uint16:
		appendIntegerScalars(e, kind, unsafe.Slice((*uint16)(data), n))
	case reflect.Uint32:
		appendIntegerScalars(e, kind, unsafe.Slice((*uint32)(data), n))
	case reflect.Uint64:
		appendIntegerScalars(e, kind, unsafe.Slice((*uint64)(data), n))
	default:
		return false
	}
	return true
}

// Reserve many canonical pairs at once. Capacity/flush checks run once per
// block rather than once per scalar; kind tags and numeric bits stay unchanged.
func (e *canonicalState) scalarBlock(remaining int) ([]byte, int) {
	if cap(e.buffer)-len(e.buffer) < 16 {
		e.flush()
	}
	count := min(remaining, (cap(e.buffer)-len(e.buffer))/16)
	start := len(e.buffer)
	e.buffer = e.buffer[:start+count*16]
	block := e.buffer[start:]
	return block, count
}

type digestInteger interface {
	~int | ~int8 | ~int16 | ~int32 | ~int64 | ~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64
}

func appendIntegerScalars[T digestInteger](e *canonicalState, kind reflect.Kind, values []T) {
	for len(values) > 0 {
		block, count := e.scalarBlock(len(values))
		for i, value := range values[:count] {
			binary.LittleEndian.PutUint64(block[i*16:], uint64(kind))
			binary.LittleEndian.PutUint64(block[i*16+8:], uint64(value))
		}
		values = values[count:]
	}
}
