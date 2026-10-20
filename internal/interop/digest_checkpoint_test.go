package interop

import (
 "encoding/json"
 "fmt"
 "reflect"
 "testing"
)

func TestCheckpointAnnualEquivalence(t *testing.T) {
 for _, size := range [][2]int{{24,16},{400,200}} {
  t.Run(fmt.Sprintf("%dx%d",size[0],size[1]),func(t *testing.T) {
   a,b:=throughputSession(t,size[0],size[1]),throughputSession(t,size[0],size[1])
   for i:=1;i<=27;i++ {
    x:=a.Handle(Request{Schema:LocalSchema,ID:"original",Op:"advance",Payload:json.RawMessage(`{"view":"map-columns-v1"}`)})
    y:=b.Handle(Request{Schema:LocalSchema,ID:"checkpoint",Op:"advance",Payload:json.RawMessage(`{"view":"map-columns-v1","digestMode":"checkpoint-v1"}`)})
    if !x.OK||!y.OK {t.Fatalf("advance %d failed",i)}
    expected,actual:=x.Data.(columnDelta),y.Data.(columnDelta)
    if i%25==0 {
     if expected.StateSHA256!=actual.StateSHA256||actual.DigestMode!="" {t.Fatal("checkpoint SHA differs")}
    } else if actual.StateSHA256!=""||actual.DigestMode!="deferred-v1" {
     t.Fatal("deferred SHA missing its explicit marker")
    }
    actual.StateSHA256=expected.StateSHA256
    actual.DigestMode=expected.DigestMode
    if !reflect.DeepEqual(expected,actual) {t.Fatalf("publication differs at year %d",i)}
    if b.simulation.StateDigest()!=expected.StateSHA256 {t.Fatal("on-demand SHA differs")}
   }
   if !reflect.DeepEqual(a.simulation.Replay(),b.simulation.Replay()) {t.Fatal("history replay differs")}
  })
 }
}

func BenchmarkCheckpointAnnualPublication(b *testing.B) {
 for _,mode:=range []string{"exact-every-year","checkpoint-25"} {
  b.Run(mode,func(b *testing.B){
   s:=throughputSession(b,400,200)
   payload:=json.RawMessage(`{"view":"map-columns-v1"}`)
   if mode=="checkpoint-25" {payload=json.RawMessage(`{"view":"map-columns-v1","digestMode":"checkpoint-v1"}`)}
   b.ReportAllocs();b.ResetTimer()
   for i:=0;i<b.N;i++ {
    r:=s.Handle(Request{Schema:LocalSchema,ID:"perf",Op:"advance",Payload:payload})
    if !r.OK {b.Fatal(r.Error)}
   }
   b.StopTimer()
   b.ReportMetric(float64(b.N)/b.Elapsed().Seconds(),"years/s")
  })
 }
}
