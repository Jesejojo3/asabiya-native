package interop

import (
 "encoding/json"
 "fmt"
 "os"
 "runtime"
 "testing"
 "time"
 "github.com/Jesejojo3/asabiya-native/internal/sim"
)
func throughputSession(t testing.TB, width, height int) *Session {
 t.Helper()
 s:= &Session{}
 raw:=fmt.Sprintf(`{"world":{"seed":"Asabiya","width":%d,"height":%d,"detail":4,"landFraction":0.33},"fine":false}`,width,height)
 r:=s.Handle(Request{Schema:LocalSchema,ID:"world",Op:"create_world",Payload:json.RawMessage(raw)})
 if !r.OK { t.Fatal(r.Error) }
 r=s.Handle(Request{Schema:LocalSchema,ID:"start",Op:"start_history",Payload:json.RawMessage(`{"historySeed":"1","view":"map"}`)})
 if !r.OK { t.Fatal(r.Error) }
 return s
}
func BenchmarkAnnualThroughput(b *testing.B) {
 for _, size:=range [][2]int{{24,16},{400,200}} {
  for _, mode:= range []string{"core","compact","json","columns"} {
   b.Run(fmt.Sprintf("%dx%d/%s",size[0],size[1],mode),func(b *testing.B){
    s:=throughputSession(b,size[0],size[1])
    s.simulation.EnableWorkProfile()
    b.ReportAllocs(); b.ResetTimer()
    var wire int
    for i:=0;i<b.N;i++ {
     if mode=="core" { s.simulation.AdvanceYear(); continue }
     v:=s.filterMapDelta(s.simulation.AdvanceYearWithMapDelta())
     if mode=="json" || mode=="columns" { var data any=v;if mode=="columns" {data=packDelta(v)}; p,e:=json.Marshal(data); if e!=nil {b.Fatal(e)}; wire+=len(p);runtime.KeepAlive(p) }
    }
    b.StopTimer()
    b.ReportMetric(float64(wire)/float64(b.N),"wire-B/year")
    b.ReportMetric(b.Elapsed().Seconds()*1000/float64(b.N),"ms/year")
    b.ReportMetric(float64(b.N)/b.Elapsed().Seconds(),"years/s")
    p:=s.simulation.WorkProfile();encoded,_:=json.Marshal(p)
    b.Logf("PROFILE stages=%v data=%s digest=%s rng=%+v",sim.ProfileStages,encoded,s.simulation.StateDigest(),s.simulation.Status().HistoryRNG)
   })
  }
 }
}
func TestAnnualFirstStateWindow(t *testing.T) {
 if os.Getenv("ASABIYA_FIRST_STATE")!="1" {t.Skip("bounded first-state measurement is opt-in")}
 for _,size:=range [][2]int{{24,16},{400,200}} {
  s:=throughputSession(t,size[0],size[1]); start:=time.Now(); firstYear:=0; years:=0
  for years<6000 && time.Since(start)<60*time.Second {
   s.simulation.AdvanceYear(); years++
   if s.simulation.LivingStates()>0 {firstYear=s.simulation.Status().Year;break}
  }
  t.Logf("FIRST_STATE size=%dx%d sampledEvery=1 years=%d year=%d elapsedMs=%.3f found=%t digest=%s",size[0],size[1],years,s.simulation.Status().Year,float64(time.Since(start).Microseconds())/1000,firstYear!=0,s.simulation.StateDigest())
 }
}
