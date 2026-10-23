package sim

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

type languageFixtureLang struct {
	Style, Macro                                   string
	Rules                                          []string
	Lex                                            [lexCount]string
	Place, People, Land                            string
	PlaceSuffix, PeopleSuffix, PrePeople, PrePlace string
}

type languageFixture struct {
	ReferenceSHA256 string `json:"referenceSha256"`
	RuleCases       []struct {
		Word string
		Rule int
		Out  string
	} `json:"ruleCases"`
	TidyCases []struct{ Word, Out string } `json:"tidyCases"`
	JoinCases []struct{ A, B, Out string } `json:"joinCases"`
	Cases     []struct {
		Seed, Macro, Style                     string
		Lang, Child, Grandchild, Other, Hybrid languageFixtureLang
		Names                                  struct{ Person, Place, City [2]string }
		Calls                                  uint64
	} `json:"cases"`
}

func loadLanguageFixture(t *testing.T) languageFixture {
	t.Helper()
	b, err := os.ReadFile("../../tests/native/language-contract.v06.json")
	if err != nil {
		t.Fatal(err)
	}
	var f languageFixture
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatal(err)
	}
	if f.ReferenceSHA256 != "988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9" || len(f.Cases) == 0 {
		t.Fatal("unexpected language fixture provenance")
	}
	return f
}

func toFixture(l *Language) languageFixtureLang {
	return languageFixtureLang{Style: l.Style, Macro: l.Macro, Rules: l.SoundChanges(), Lex: l.Lex, Place: l.Place, People: l.People,
		Land: l.Land, PlaceSuffix: l.PlaceSuffix, PeopleSuffix: l.PeopleSuffix, PrePeople: l.PrePeople, PrePlace: l.PrePlace}
}

func sameLang(a, b languageFixtureLang) bool {
	if len(a.Rules) != len(b.Rules) {
		return false
	}
	for i := range a.Rules {
		if a.Rules[i] != b.Rules[i] {
			return false
		}
	}
	a.Rules, b.Rules = nil, nil
	return a.Style == b.Style && a.Macro == b.Macro && a.Lex == b.Lex && a.Place == b.Place && a.People == b.People && a.Land == b.Land &&
		a.PlaceSuffix == b.PlaceSuffix && a.PeopleSuffix == b.PeopleSuffix && a.PrePeople == b.PrePeople && a.PrePlace == b.PrePlace
}

func TestOriginalLanguageContract(t *testing.T) {
	f := loadLanguageFixture(t)
	for _, c := range f.RuleCases {
		if got := applySoundRule(c.Word, v06.SoundRules[c.Rule]); got != c.Out {
			t.Fatalf("rule %d on %q: got %q want %q", c.Rule, c.Word, got, c.Out)
		}
	}
	for _, c := range f.TidyCases {
		if got := tidy(c.Word); got != c.Out {
			t.Fatalf("tidy %q: got %q want %q", c.Word, got, c.Out)
		}
	}
	for _, c := range f.JoinCases {
		if got := joinWord(c.A, c.B); got != c.Out {
			t.Fatalf("join %q+%q: got %q want %q", c.A, c.B, got, c.Out)
		}
	}
	for _, c := range f.Cases {
		r := rng.New(rng.HashStr(c.Seed))
		l := makeLanguage(r, c.Style, c.Macro)
		ch := childLanguage(l, r)
		g := childLanguage(ch, r)
		other := makeLanguage(r, v06.macroByKey[c.Macro].Styles[0], c.Macro)
		hy := hybridLanguage(g, other, r)
		person := [2]string{personName(l, r), personName(g, r)}
		place := [2]string{placeWord(l, r), placeWord(hy, r)}
		city := [2]string{cityWord(l, r), cityWord(ch, r)}
		for _, x := range []struct {
			name      string
			got, want languageFixtureLang
		}{{"lang", toFixture(l), c.Lang}, {"child", toFixture(ch), c.Child}, {"grandchild", toFixture(g), c.Grandchild},
			{"other", toFixture(other), c.Other}, {"hybrid", toFixture(hy), c.Hybrid}} {
			if !sameLang(x.got, x.want) {
				t.Fatalf("%s %s differs:\n got %+v\nwant %+v", c.Seed, x.name, x.got, x.want)
			}
		}
		if person != c.Names.Person || place != c.Names.Place || city != c.Names.City {
			t.Fatalf("%s names differ: %v %v %v want %+v", c.Seed, person, place, city, c.Names)
		}
		if r.Position().Calls != c.Calls {
			t.Fatalf("%s consumed %d draws, original %d", c.Seed, r.Position().Calls, c.Calls)
		}
	}
}

func TestRomanAndPlaceSeed(t *testing.T) {
	for n, want := range map[int]string{1: "I", 4: "IV", 9: "IX", 14: "XIV", 39: "XXXIX"} {
		if roman(n) != want {
			t.Fatalf("roman(%d)", n)
		}
	}
	if placeNameSeed("1", "Asabiya", 42) != rng.HashStr("1:place:Asabiya:42") {
		t.Fatal("place seed format changed")
	}
}
