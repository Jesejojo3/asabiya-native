package sim
import ("testing";"crypto/sha256";"encoding/binary";"encoding/hex";"hash";"math";"reflect";"sort")
type legacyState struct {
	hash   hash.Hash
	buffer []byte
}

func (e *legacyState) flush() {
	if len(e.buffer) > 0 {
		e.hash.Write(e.buffer)
		e.buffer = e.buffer[:0]
	}
}
func (e *legacyState) u64(n uint64) {
	if len(e.buffer)+8 > cap(e.buffer) {
		e.flush()
	}
	e.buffer = binary.LittleEndian.AppendUint64(e.buffer, n)
}
func (e *legacyState) text(s string) {
	e.u64(uint64(len(s)))
	for len(s) > 0 {
		space := cap(e.buffer) - len(e.buffer)
		if space == 0 {
			e.flush()
			space = cap(e.buffer)
		}
		n := min(space, len(s))
		e.buffer = append(e.buffer, s[:n]...)
		s = s[n:]
	}
}
func (e *legacyState) history(v reflect.Value) {
	typ := v.Type()
	for k := 0; k < v.NumField(); k++ {
		name := typ.Field(k).Name
		if name == "earth" && v.Field(k).IsNil() {
			continue
		}
		if name == "world" || name == "r" {
			continue
		}
		e.text(name)
		if name == "annualState" {
			e.annual(v.Field(k))
		} else {
			e.value(v.Field(k))
		}
	}
}
func (e *legacyState) annual(v reflect.Value) {
	typ := v.Type()
	for k := 0; k < v.NumField(); k++ {
		name := typ.Field(k).Name
		switch name {
		case "snapshots", "withinMark", "withinStamp", "bfsMark", "bfsStamp":
			continue
		}
		e.text(name)
		e.value(v.Field(k))
	}
}
func (e *legacyState) value(v reflect.Value) {
	e.u64(uint64(v.Kind()))
	switch v.Kind() {
	case reflect.Bool:
		if v.Bool() {
			e.u64(1)
		} else {
			e.u64(0)
		}
	case reflect.String:
		e.text(v.String())
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		e.u64(uint64(v.Int()))
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		e.u64(v.Uint())
	case reflect.Float32:
		n := float32(v.Float())
		bits := math.Float32bits(n)
		if math.IsNaN(float64(n)) {
			bits = 0x7fc00000
		}
		e.u64(uint64(bits))
	case reflect.Float64:
		n := v.Float()
		bits := math.Float64bits(n)
		if math.IsNaN(n) {
			bits = 0x7ff8000000000000
		}
		e.u64(bits)
	case reflect.Pointer:
		if v.IsNil() {
			e.u64(0)
		} else {
			e.u64(1)
			e.value(v.Elem())
		}
	case reflect.Array, reflect.Slice:
		e.u64(uint64(v.Len()))
		for k := 0; k < v.Len(); k++ {
			e.value(v.Index(k))
		}
	case reflect.Struct:
		typ := v.Type()
		e.u64(uint64(v.NumField()))
		for k := 0; k < v.NumField(); k++ {
			e.text(typ.Field(k).Name)
			e.value(v.Field(k))
		}
	case reflect.Map:
		keys := v.MapKeys()
		sort.Slice(keys, func(i, j int) bool {
			switch keys[i].Kind() {
			case reflect.String:
				return keys[i].String() < keys[j].String()
			case reflect.Int, reflect.Int32, reflect.Int64:
				return keys[i].Int() < keys[j].Int()
			default:
				panic("unsupported digest map key")
			}
		})
		e.u64(uint64(len(keys)))
		for _, k := range keys {
			e.value(k)
			e.value(v.MapIndex(k))
		}
	default:
		panic("unsupported causal digest kind: " + v.Kind().String())
	}
}

func legacyDigest(s *Simulation) string {
 s.mu.RLock();defer s.mu.RUnlock()
 h:=sha256.New();e:=legacyState{hash:h,buffer:make([]byte,0,65536)}
 e.text(StateDigestVersion);e.text(s.worldDigestLocked());p:=s.h.r.Position();e.u64(uint64(p.Seed));e.u64(p.Calls);e.u64(s.commandSequence);e.history(reflect.ValueOf(s.h).Elem());e.flush();return hex.EncodeToString(h.Sum(nil))
}
func TestCanonicalScalarEncodingParity(t *testing.T) {
 values:=[]any{[]float32{0,float32(math.Copysign(0,-1)),1,-3,float32(math.Inf(1)),float32(math.NaN())},[]float64{0,math.Copysign(0,-1),math.NaN(),math.Inf(-1)},[]int32{0,-1,2147483647},[]uint8{0,255},[][2]int16{{-1,2}},[]float32(nil),[]float32{}}
 for _,v:=range values {a,b:=sha256.New(),sha256.New();x:=canonicalState{hash:a,buffer:make([]byte,0,64)};y:=legacyState{hash:b,buffer:make([]byte,0,64)};x.value(reflect.ValueOf(v));y.value(reflect.ValueOf(v));x.flush();y.flush();if string(a.Sum(nil))!=string(b.Sum(nil)){t.Fatalf("encoding changed: %T",v)}}
 cfg:=DefaultWorldConfig("canonical-throughput");cfg.Width=24;cfg.Height=16;w,_:=GenerateWorld(cfg);s,_:=NewSimulation(w,"1")
 for i:=0;i<60;i++{if s.StateDigest()!=legacyDigest(s){t.Fatalf("state digest changed at %d",i)};s.AdvanceYear()}
}
