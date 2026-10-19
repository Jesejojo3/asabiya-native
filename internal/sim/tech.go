package sim

// Technology storage indices of v0.6 TECH (762–795). Several original state
// aliases use other names: S.metal is TechCopper and S.admin is TechWriting.
// Keep the storage index, not the name, as identity.
const (
	TechFarm = iota
	TechHerd
	TechIrrigation
	TechCopper // S.metal
	TechHorse
	TechSail
	TechWriting // S.admin
	TechWheel
	TechIron
	TechCoin
	TechLaw
	TechRoads
	TechNavigation
	TechCavalry
	TechPaper
	TechCrops
	TechGunpowder
	TechOcean
	TechCamel
	TechGrain
	TechArd
	TechPlough
	TechManure
	TechXCrops
	TechKiteSignal
	TechWindCart
	TechFungal
	TechLedger
	TechTidemill
	TechFeverbark
	TechSaltFlush
	TechPigeon
	techCount
)

var techKeys = [techCount]string{"farm", "herd", "irrig", "copper", "horse", "sail", "writing", "wheel", "iron", "coin", "law",
	"roads", "nav", "caval", "paper", "crops", "gun", "ocean", "camel", "grain", "ard", "plough", "manure", "xcrops",
	"kitesig", "windcart", "fungal", "ledger", "tidemill", "feverbark", "saltflush", "pigeon"}

func init() {
	for i, k := range techKeys {
		if v06.Tech[i].Key != k {
			panic("tech index mismatch at " + k)
		}
	}
}

// eraOf is v0.6 lines 801–809: the technological era of a province.
func (h *history) eraOf(i int) int {
	v := func(k int) bool { return h.tech[k][i] > .5 }
	b := func(x bool) int {
		if x {
			return 1
		}
		return 0
	}
	switch {
	case v(TechOcean):
		return 7
	case v(TechGunpowder):
		return 6
	case b(v(TechCavalry))+b(v(TechPaper))+b(v(TechCrops)) >= 2:
		return 5
	case v(TechIron) && (v(TechCoin) || v(TechLaw)):
		return 4
	case v(TechIron):
		return 3
	case v(TechCopper):
		return 2
	case (v(TechFarm) && float64(h.world.farmSuitability[i]) > .1) || (v(TechHerd) && float64(h.world.herdSuitability[i]) > .1):
		return 1
	}
	return 0
}
