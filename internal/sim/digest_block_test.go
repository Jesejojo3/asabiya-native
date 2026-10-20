package sim

import (
	"bytes"
	"math"
	"math/rand/v2"
	"reflect"
	"testing"
)

type byteHash struct{ bytes.Buffer }

func (b *byteHash) Sum(p []byte) []byte { return append(p, b.Bytes()...) }
func (b *byteHash) Reset()              { b.Buffer.Reset() }
func (b *byteHash) Size() int           { return b.Len() }
func (b *byteHash) BlockSize() int      { return 64 }

func TestCanonicalBlocksMatchOriginalBytes(t *testing.T) {
	type namedInt32 int32
	r := rand.New(rand.NewPCG(7, 19))
	f32, f64 := make([]float32, 10003), make([]float64, 10003)
	for i := range f32 {
		f32[i] = math.Float32frombits(r.Uint32())
		f64[i] = math.Float64frombits(r.Uint64())
	}
	values := []any{f32, f64, []int{0, -1, math.MaxInt, math.MinInt}, []int8{-128, 127}, []int16{-32768, 32767}, []int32{math.MinInt32, math.MaxInt32}, []int64{math.MinInt64, math.MaxInt64}, []uint{0, math.MaxUint}, []uint8{0, 255}, []uint16{0, 65535}, []uint32{0, math.MaxUint32}, []uint64{0, math.MaxUint64}, []namedInt32{-1, 2}, [3]int16{-1, 0, 1}, [][]float32{nil, {}, f32}, []float32{0, math.Float32frombits(1 << 31), math.Float32frombits(0x7f800001), math.Float32frombits(0xffc01234)}, []float64{0, math.Copysign(0, -1), math.Float64frombits(0x7ff0000000000001)}}
	for _, capacity := range []int{16, 31, 64, 65536} {
		for _, v := range values {
			a, b := &byteHash{}, &byteHash{}
			x, y := canonicalState{hash: a, buffer: make([]byte, 0, capacity)}, legacyState{hash: b, buffer: make([]byte, 0, capacity)}
			// A string leaves a nonaligned prefix; blocks must flush at any offset.
			x.text("prefix!")
			y.text("prefix!")
			x.value(reflect.ValueOf(v))
			y.value(reflect.ValueOf(v))
			x.text("suffix")
			y.text("suffix")
			x.flush()
			y.flush()
			if !bytes.Equal(a.Bytes(), b.Bytes()) {
				t.Fatalf("canonical bytes differ for %T with capacity %d", v, capacity)
			}
		}
	}
}
