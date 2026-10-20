package interop
import ("testing";"reflect";"encoding/json";"fmt")
func rowsFromColumns(c MapColumns) []mapProvince {
 var out []mapProvince
 for i,id:=range c.ID {out=append(out,mapProvince{ID:id,Owner:c.Owner[i],People:c.People[i],Religion:c.Religion[i],Population:c.Population[i],Capacity:c.Capacity[i],Fortification:c.Fortification[i],Era:c.Era[i]})}
 return out
}
func TestMapColumnsLossless(t *testing.T) {
 for _,size:=range [][2]int{{24,16},{400,200}} {
  a,b:=throughputSession(t,size[0],size[1]),throughputSession(t,size[0],size[1])
  initial:=a.simulation.MapSnapshot();packed:=packState(b.simulation.MapSnapshot())
  if !reflect.DeepEqual(initial.Provinces,rowsFromColumns(packed.Provinces)){t.Fatal("column snapshot changed province bits")}
  packed.Schema=initial.Schema
  if !reflect.DeepEqual(initial.StateView,packed.StateView){t.Fatal("column snapshot changed metadata")}
  for i:=0;i<6;i++{
   normal:=a.Handle(Request{Schema:LocalSchema,ID:fmt.Sprint(i),Op:"advance",Payload:json.RawMessage(`{"view":"map"}`)})
   columns:=b.Handle(Request{Schema:LocalSchema,ID:fmt.Sprint(i),Op:"advance",Payload:json.RawMessage(`{"view":"map-columns-v1"}`)})
   if !normal.OK||!columns.OK{t.Fatal(normal.Error,columns.Error)}
   x:=normal.Data.(mapDelta);y:=columns.Data.(columnDelta)
   if !reflect.DeepEqual(x.Provinces,rowsFromColumns(y.Provinces)){t.Fatal("delta province order/bits changed")}
   y.Schema=x.Schema
   if !reflect.DeepEqual(x.AnnualDelta,y.AnnualDelta){t.Fatal("delta metadata/events changed")}
  }
  if !reflect.DeepEqual(a.simulation.Replay(),b.simulation.Replay()){t.Fatal("wire view changed replay/RNG")}
 }
}
func TestStatusYearsPreserveHistory(t *testing.T){
 a,b:=throughputSession(t,24,16),throughputSession(t,24,16)
 for i:=0;i<120;i++ {
  x:=a.Handle(Request{Schema:LocalSchema,ID:fmt.Sprint(i),Op:"advance",Payload:json.RawMessage(`{"view":"map"}`)})
  y:=b.Handle(Request{Schema:LocalSchema,ID:fmt.Sprint(i),Op:"advance",Payload:json.RawMessage(`{"publication":"status"}`)})
  if !x.OK||!y.OK||*x.Year!=*y.Year{t.Fatal("atomic year lost")}
 }
 if !reflect.DeepEqual(a.simulation.Replay(),b.simulation.Replay()) {t.Fatal("fast status path changed RNG/replay")}
 if !reflect.DeepEqual(a.simulation.Snapshot(),b.simulation.Snapshot()) {t.Fatal("fast status path lost causal state, events, statistics or map archive")}
}
