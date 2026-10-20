package sim
import ("testing";"reflect")
func TestWorkProfileNeutral(t *testing.T) {
 cfg:=DefaultWorldConfig("throughput-integrity");cfg.Width=24;cfg.Height=16
 w,e:=GenerateWorld(cfg);if e!=nil {t.Fatal(e)}
 a,_:=NewSimulation(w,"1");b,_:=NewSimulation(w,"1");b.EnableWorkProfile()
 for i:=0;i<40;i++ {a.AdvanceYear();b.AdvanceYear();if a.StateDigest()!=b.StateDigest()||a.Status()!=b.Status(){t.Fatalf("profiling changed year %d",i)}}
 if !reflect.DeepEqual(a.Replay(),b.Replay()){t.Fatal("profiling changed replay")}
 if !reflect.DeepEqual(a.MapSnapshot(),b.MapSnapshot()){t.Fatal("profiling changed publication")}
 p:=b.WorkProfile();var total int64;for _,n:=range p.Nanoseconds {total+=n};if p.Years!=40 || total<=0 {t.Fatalf("missing observations: %+v",p)}
}
