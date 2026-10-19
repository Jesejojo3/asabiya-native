package sim

import (
	"strconv"
	"strings"

	"github.com/Jesejojo3/asabiya-native/internal/rng"
)

// Languages port v0.6 lines 693–760 (applyRule…roman). Every RNG draw is in
// the original order: names consume the historical stream, so an extra or
// missing draw changes later history. JavaScript regular expressions with
// lookahead/backreferences are implemented as explicit scans (RE2 has neither);
// all generated words are ASCII.

const lexCount = 8

// Lexicon indices follow LEX: root, river, god, sun, sea, mountain, mother, grain.
const (
	LexRoot = iota
	LexRiver
	LexGod
	LexSun
	LexSea
	LexMountain
	LexMother
	LexGrain
)

type Language struct {
	Style        string           `json:"style"`
	Macro        string           `json:"macro"`
	Rules        []soundRule      `json:"-"`
	Lex          [lexCount]string `json:"lex"`
	Place        string           `json:"place"`
	People       string           `json:"people"`
	Land         string           `json:"land"`
	PlaceSuffix  string           `json:"placeSuffix"`
	PeopleSuffix string           `json:"peopleSuffix"`
	PrePeople    string           `json:"prePeople"`
	PrePlace     string           `json:"prePlace"`
}

func (l *Language) style() *languageStyle { return v06.styleByName[l.Style] }

// SoundChanges returns the accumulated rules in their original notation.
func (l *Language) SoundChanges() []string {
	out := make([]string, len(l.Rules))
	for i, r := range l.Rules {
		if r.Kind != "" {
			out[i] = r.Kind
		} else {
			out[i] = r.From + ">" + r.To
		}
	}
	return out
}

func pick[T any](r *rng.Mulberry32, a []T) T { return a[int(r.Float64()*float64(len(a)))] }

func isVowel(c byte) bool  { return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' }
func isVowelY(c byte) bool { return isVowel(c) || c == 'y' }
func capFirst(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func applySoundRule(w string, r soundRule) string {
	switch r.Kind {
	case "":
		return strings.ReplaceAll(w, r.From, r.To)
	case "drop": // w.length>4 && /[aeiou]$/ && !/[aeiou]{2}$/ ? w.slice(0,-1) : w
		n := len(w)
		if n > 4 && isVowel(w[n-1]) && !isVowel(w[n-2]) {
			return w[:n-1]
		}
		return w
	case "voice": // three global passes: V p(?=V) -> V b, then t->d, then k->g
		w = voiceBetweenVowels(w, 'p', 'b')
		w = voiceBetweenVowels(w, 't', 'd')
		return voiceBetweenVowels(w, 'k', 'g')
	case "palatal": // k(?=[ie]) -> ch; c(?=[ie]) -> ch; t(?=i) -> ch
		w = palatalize(w, 'k', "ie")
		w = palatalize(w, 'c', "ie")
		return palatalize(w, 't', "i")
	case "nasal": // length>4: drop one final m/n
		if n := len(w); n > 4 && (w[n-1] == 'm' || w[n-1] == 'n') {
			return w[:n-1]
		}
		return w
	case "prothesis": // ^s(?=[ptkm]) -> es
		if len(w) >= 2 && w[0] == 's' && strings.IndexByte("ptkm", w[1]) >= 0 {
			return "e" + w
		}
		return w
	case "geminate": // first ([aeiou])([ptk])(?=[aeiou]) -> $1$2$2 (no g flag)
		for i := 0; i+2 < len(w); i++ {
			if isVowel(w[i]) && strings.IndexByte("ptk", w[i+1]) >= 0 && isVowel(w[i+2]) {
				return w[:i+2] + w[i+1:i+2] + w[i+2:]
			}
		}
		return w
	}
	return w
}

// voiceBetweenVowels is /([aeiou])X(?=[aeiou])/g -> '$1Y': each match consumes
// the vowel and X; the lookahead vowel may start the next match.
func voiceBetweenVowels(w string, from, to byte) string {
	var b strings.Builder
	for i := 0; i < len(w); {
		if i+2 < len(w) && isVowel(w[i]) && w[i+1] == from && isVowel(w[i+2]) {
			b.WriteByte(w[i])
			b.WriteByte(to)
			i += 2
			continue
		}
		b.WriteByte(w[i])
		i++
	}
	return b.String()
}

func palatalize(w string, c byte, before string) string {
	var b strings.Builder
	for i := 0; i < len(w); i++ {
		if w[i] == c && i+1 < len(w) && strings.IndexByte(before, w[i+1]) >= 0 {
			b.WriteString("ch")
			continue
		}
		b.WriteByte(w[i])
	}
	return b.String()
}

func applySoundRules(w string, rules []soundRule) string {
	for _, r := range rules {
		w = applySoundRule(w, r)
	}
	return tidy(w)
}

// tidy reproduces four sequential JS replacements:
//
//	/(.)\1\1+/g -> '$1$1', /([wyhjvqx])\1/g -> '$1', /^([^aeiouy])\1/ -> '$1',
//	/[aeiou]{3,}/g -> first two.
func tidy(w string) string {
	var b strings.Builder
	for i := 0; i < len(w); {
		j := i + 1
		for j < len(w) && w[j] == w[i] {
			j++
		}
		if j-i >= 3 {
			b.WriteByte(w[i])
			b.WriteByte(w[i])
		} else {
			b.WriteString(w[i:j])
		}
		i = j
	}
	w = b.String()
	b.Reset()
	for i := 0; i < len(w); {
		if i+1 < len(w) && w[i] == w[i+1] && strings.IndexByte("wyhjvqx", w[i]) >= 0 {
			b.WriteByte(w[i])
			i += 2
			continue
		}
		b.WriteByte(w[i])
		i++
	}
	w = b.String()
	if len(w) >= 2 && w[0] == w[1] && !isVowelY(w[0]) {
		w = w[1:]
	}
	b.Reset()
	for i := 0; i < len(w); {
		if !isVowel(w[i]) {
			b.WriteByte(w[i])
			i++
			continue
		}
		j := i
		for j < len(w) && isVowel(w[j]) {
			j++
		}
		if j-i >= 3 {
			b.WriteString(w[i : i+2])
		} else {
			b.WriteString(w[i:j])
		}
		i = j
	}
	return b.String()
}

// collapseDoubleVowels is /([aeiou])\1/g -> '$1'.
func collapseDoubleVowels(w string) string {
	var b strings.Builder
	for i := 0; i < len(w); {
		if i+1 < len(w) && isVowel(w[i]) && w[i+1] == w[i] {
			b.WriteByte(w[i])
			i += 2
			continue
		}
		b.WriteByte(w[i])
		i++
	}
	return b.String()
}

func syllable(s *languageStyle, r *rng.Mulberry32) string {
	pat := pick(r, s.Pat)
	var w strings.Builder
	for i := 0; i < len(pat); i++ {
		switch pat[i] {
		case 'V':
			w.WriteString(pick(r, s.Vowels))
		case 'K':
			if len(s.Clust) > 0 {
				w.WriteString(pick(r, s.Clust))
			} else {
				w.WriteString(pick(r, s.Cons))
			}
		case 'C':
			w.WriteString(pick(r, s.Cons))
		case 'F':
			if len(s.Coda) > 0 {
				w.WriteString(pick(r, s.Coda))
			}
		}
	}
	return w.String()
}

func contains(a []string, v string) bool {
	for _, x := range a {
		if x == v {
			return true
		}
	}
	return false
}

// rawWord: n <= 0 stands for JavaScript's falsy/undefined n, which draws.
func rawWord(l *Language, r *rng.Mulberry32, n int) string {
	s := l.style()
	if n <= 0 {
		n = 1
		if r.Float64() < .55 {
			n = 2
		}
	}
	if s.Mono {
		n = min(n, 2)
	}
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteString(syllable(s, r))
	}
	w := b.String()
	if !s.Mono && len(s.Coda) > 0 && r.Float64() < .3 && w != "" && isVowel(w[len(w)-1]) {
		w += pick(r, s.Coda)
	}
	if !contains(s.Vowels, "aa") {
		w = collapseDoubleVowels(w)
	}
	w = tidy(w)
	if len(w) > 10 {
		w = w[:10]
	}
	return w
}

func joinWord(a, b string) string {
	if b == "" {
		return a
	}
	if b == "s" && a != "" && strings.IndexByte("aeiounrlk", a[len(a)-1]) < 0 {
		b = "ians"
	}
	if isVowelY(b[0]) && a != "" && isVowelY(a[len(a)-1]) {
		t := strings.TrimRight(a, "aeiouy")
		if t != "" {
			a = t
		}
	}
	if a != "" && a[len(a)-1] == b[0] && !isVowel(b[0]) {
		b = b[1:]
	}
	return a + b
}

func word(l *Language, r *rng.Mulberry32, n int) string {
	var w string
	for t := 0; t < 8; t++ {
		w = applySoundRules(rawWord(l, r, n), l.Rules)
		if len(w) >= 2 && len(w) <= 10 {
			break
		}
	}
	return w
}

func makeLanguage(r *rng.Mulberry32, style, macro string) *Language {
	s := v06.styleByName[style]
	l := &Language{Style: style, Macro: macro}
	if len(s.Place) > 0 {
		l.PlaceSuffix = pick(r, s.Place)
	}
	if len(s.People) > 0 {
		l.PeopleSuffix = pick(r, s.People)
	}
	if s.Pre != nil {
		l.PrePeople = pick(r, s.Pre.People)
		l.PrePlace = pick(r, s.Pre.Place)
	}
	for k := 0; k < lexCount; k++ {
		n := 0
		if k == LexRoot {
			n = 1
			if !s.Mono && r.Float64() < .5 {
				n = 2
			}
		}
		l.Lex[k] = word(l, r, n)
	}
	for t := 0; t < 6 && !s.Mono && len(l.Lex[LexRoot]) < 3; t++ {
		l.Lex[LexRoot] = word(l, r, 2)
	}
	l.names()
	return l
}

func (l *Language) names() {
	root := l.Lex[LexRoot]
	if l.PrePlace != "" {
		l.Place = capFirst(l.PrePlace + root)
	} else {
		l.Place = capFirst(joinWord(root, l.PlaceSuffix))
	}
	if l.PrePeople != "" {
		l.People = capFirst(l.PrePeople + root)
	} else {
		l.People = capFirst(joinWord(root, l.PeopleSuffix))
	}
	l.Land = l.Place
}

func childLanguage(parent *Language, r *rng.Mulberry32) *Language {
	ps := parent.style()
	n := 0
	if !ps.Mono {
		n = 1
		if r.Float64() < .5 {
			n = 2
		}
	}
	nr := make([]soundRule, 0, n)
	for i := 0; i < n; i++ {
		nr = append(nr, pick(r, v06.SoundRules))
	}
	style := parent.Style
	if r.Float64() < .22 {
		if m := v06.macroByKey[parent.Macro]; m != nil && len(m.Styles) > 1 {
			style = pick(r, m.Styles)
		}
	}
	s := v06.styleByName[style]
	rules := append(append([]soundRule(nil), parent.Rules...), nr...)
	if len(rules) > 6 {
		rules = rules[len(rules)-6:]
	}
	c := &Language{Style: style, Macro: parent.Macro, Rules: rules}
	if style != parent.Style || r.Float64() < .3 {
		if len(s.Place) > 0 {
			c.PlaceSuffix = pick(r, s.Place)
		}
	} else {
		c.PlaceSuffix = parent.PlaceSuffix
	}
	if style != parent.Style || r.Float64() < .3 {
		if len(s.People) > 0 {
			c.PeopleSuffix = pick(r, s.People)
		}
	} else {
		c.PeopleSuffix = parent.PeopleSuffix
	}
	if s.Pre != nil {
		c.PrePeople = pick(r, s.Pre.People)
		c.PrePlace = pick(r, s.Pre.Place)
	}
	for k := 0; k < lexCount; k++ {
		if r.Float64() < .12 {
			c.Lex[k] = word(c, r, 0)
		} else {
			c.Lex[k] = applySoundRules(parent.Lex[k], nr)
		}
	}
	if c.Lex[LexRoot] == parent.Lex[LexRoot] || len(c.Lex[LexRoot]) < 3 {
		if r.Float64() < .5 {
			c.Lex[LexRoot] = applySoundRules(parent.Lex[LexRoot], []soundRule{pick(r, v06.SoundRules)})
		} else {
			n := 2
			if s.Mono {
				n = 1
			}
			c.Lex[LexRoot] = word(c, r, n)
		}
	}
	c.names()
	if c.People == parent.People {
		c.Lex[LexRoot] = word(c, r, 0)
		c.names()
	}
	return c
}

func hybridLanguage(a, b *Language, r *rng.Mulberry32) *Language {
	keep := a.Rules
	if len(keep) > 2 {
		keep = keep[len(keep)-2:]
	}
	c := &Language{Style: a.Style, Macro: a.Macro, Rules: append([]soundRule(nil), keep...), PeopleSuffix: a.PeopleSuffix, PrePeople: a.PrePeople, PrePlace: a.PrePlace}
	if r.Float64() < .5 {
		c.PlaceSuffix = a.PlaceSuffix
	} else {
		c.PlaceSuffix = b.PlaceSuffix
	}
	for k := 0; k < lexCount; k++ {
		if r.Float64() < .5 {
			c.Lex[k] = a.Lex[k]
		} else {
			c.Lex[k] = b.Lex[k]
		}
	}
	ra, rb := a.Lex[LexRoot], b.Lex[LexRoot]
	c.Lex[LexRoot] = tidy(ra[:(len(ra)+1)/2] + rb[len(rb)/2:])
	if len(c.Lex[LexRoot]) < 3 {
		tail := rb
		if len(tail) > 2 {
			tail = tail[len(tail)-2:]
		}
		c.Lex[LexRoot] = ra + tail
	}
	c.names()
	return c
}

func personName(l *Language, r *rng.Mulberry32) string {
	s := l.style()
	if s.Mono {
		a := capFirst(rawWord(l, r, 1))
		b := rawWord(l, r, 1)
		if r.Float64() < .5 {
			return a + " " + capFirst(b)
		}
		return a + b
	}
	w := ""
	for t := 0; t < 8 && len(w) < 4; t++ {
		n := 1
		if r.Float64() < .6 {
			n = 2
		}
		w = rawWord(l, r, n)
		if len(s.Person) > 0 && r.Float64() < .75 {
			w = joinWord(w, pick(r, s.Person))
		}
		w = applySoundRules(w, l.Rules)
		if len(w) > 12 {
			w = w[:12]
		}
	}
	return capFirst(w)
}

func placeWord(l *Language, r *rng.Mulberry32) string {
	s := l.style()
	n := 1
	if !s.Mono && r.Float64() < .4 {
		n = 2
	}
	root := word(l, r, n)
	if l.PrePlace != "" {
		return capFirst(l.PrePlace + root)
	}
	suffix := ""
	if len(s.Place) > 0 {
		if r.Float64() < .6 {
			suffix = l.PlaceSuffix
		} else {
			suffix = pick(r, s.Place)
		}
	}
	return capFirst(joinWord(root, suffix))
}

func cityWord(l *Language, r *rng.Mulberry32) string {
	s := l.style()
	if s.Mono {
		w := capFirst(rawWord(l, r, 1))
		if r.Float64() < .5 {
			w += pick(r, s.City)
		}
		return w
	}
	n := 1
	if r.Float64() < .4 {
		n = 2
	}
	root := word(l, r, n)
	if len(s.City) > 0 && r.Float64() < .7 {
		return capFirst(joinWord(root, pick(r, s.City)))
	}
	return capFirst(root)
}

func roman(n int) string {
	var b strings.Builder
	for _, v := range []struct {
		n int
		s string
	}{{10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}} {
		for n >= v.n {
			b.WriteString(v.s)
			n -= v.n
		}
	}
	return b.String()
}

// placeNameSeed is hashStr(s.seed+':place:'+w.seed+':'+k): a derived stream that
// never touches the historical RNG.
func placeNameSeed(historySeed, worldSeed string, cell CellID) uint32 {
	return rng.HashStr(historySeed + ":place:" + worldSeed + ":" + strconv.Itoa(int(cell)))
}
