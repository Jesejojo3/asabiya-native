package sim
import ("testing";"reflect")
func TestWorkProfileNeutral(t *testing.T) {
 cfg:=DefaultWorldConfig("throughput-integrity");cfg.Width=24;cfg.Height=16
 w,e:=GenerateWorld(cfg);if e!=nil {t.Fatal(e)}
 a,_:=NewSimulation(w,"1");b,_:=NewSimulation(w,"1");b.EnableWorkProfile()
 for i:=0;i<40;i++ {a.AdvanceYear();b.AdvanceYear();if a.StateDigest()!=b.StateDigest()||a.Status()!=b.Status(){t.Fatalf("profiling changed year %d",i)}}
 if !reflect.DeepEqual(a.Replay(),b.Replay()){t.Fatal("profiling changed replay")}
 if !reflect.DeepEqual(a.MapSnapshot(),b.MapSnapshot()){t.Fatal("profiling changed publication")}
 if b.WorkProfile().Years!=40 || b.WorkProfile().Nanoseconds[1]<=0 {t.Fatal("missing observations")}
}
