package interop
import "github.com/Jesejojo3/asabiya-native/internal/sim"
// MapColumns is a versioned, lossless wire layout of the existing eight map
// fields. Metadata/events retain their contracts. Legacy row views stay valid.
type MapColumns struct {
 ID []sim.CellID `json:"id"`
 Owner []int `json:"ownerPolityId"`
 People []int `json:"peopleId"`
 Religion []int `json:"religionId"`
 Population []float32 `json:"population"`
 Capacity []float32 `json:"carryingCapacity"`
 Fortification []float32 `json:"fortification"`
 Era []int `json:"era"`
}
type columnState struct {sim.StateView;Provinces MapColumns `json:"provinces"`}
type columnDelta struct {sim.AnnualDelta;Provinces MapColumns `json:"provinces"`}
func columns(rows []mapProvince) MapColumns {
 n:=len(rows);c:=MapColumns{make([]sim.CellID,n),make([]int,n),make([]int,n),make([]int,n),make([]float32,n),make([]float32,n),make([]float32,n),make([]int,n)}
 for i,p:=range rows {c.ID[i]=p.ID;c.Owner[i]=p.Owner;c.People[i]=p.People;c.Religion[i]=p.Religion;c.Population[i]=p.Population;c.Capacity[i]=p.Capacity;c.Fortification[i]=p.Fortification;c.Era[i]=p.Era}
 return c
}
func packState(v mapState) columnState {v.Schema="asabiya/map-columns-state-v1";return columnState{v.StateView,columns(v.Provinces)}}
func packDelta(v mapDelta) columnDelta {v.Schema="asabiya/map-columns-delta-v1";return columnDelta{v.AnnualDelta,columns(v.Provinces)}}
