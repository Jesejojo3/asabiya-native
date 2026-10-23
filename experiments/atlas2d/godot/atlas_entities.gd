class_name AtlasEntities
extends RefCounted
## Read-only presentation of Go entity records carried by a HistoryFrame.
## Field names and relations follow the Go catalog (internal/sim/queries.go);
## nothing here derives, fills in or simulates historical values. Links use
## BBCode meta "kind:id" (entities) and "cell:id" (provinces).

const NAMES := {"polity":"Estado","people":"Pueblo","ruler":"Gobernante","figure":"Figura histórica",
	"city":"Ciudad","religion":"Religión","war":"Guerra","route":"Ruta comercial","migration":"Migración",
	"outbreak":"Epidemia","omen":"Presagio","cataclysm":"Cataclismo"}
const SEARCH_KINDS := ["polity","people","religion","city","ruler","figure","war","migration","outbreak","cataclysm","omen","route"]
const COMMON := [["born","Fundación","year"],["died","Desaparición","year"],["alive","Activa","bool"]]
const LAYOUTS := {
	"polity":[["kind","Tipo","text"],["tier","Rango","text"],["cellsAtLastCensus","Provincias (último censo)","count"],["peakCells","Extensión máxima","count"],["peakPopulation","Población máxima","count"],["dynastyLabel","Dinastía","text"],["dynastyGeneration","Generaciones","count"]],
	"people":[["languageStyle","Lengua","text"],["languageMacro","Familia lingüística","text"],["placeName","Topónimo","text"],["populationAtLastCensus","Población (último censo)","count"],["cellsAtLastCensus","Provincias (último censo)","count"],["peakCells","Mayor extensión","count"]],
	"ruler":[["since","Gobierna desde","year"],["competence","Competencia","number"],["charisma","Carisma","number"],["piety","Piedad","number"],["aggression","Agresividad","number"],["conquests","Conquistas","count"]],
	"figure":[["title","Título","text"],["conquests","Conquistas","count"],["realmCells","Mayor dominio (provincias)","count"],["works","Obras","count"]],
	"city":[["holy","Lugar sagrado","bool"]],
	"religion":[["populationAtLastCensus","Población (último censo)","count"],["cellsAtLastCensus","Provincias (último censo)","count"],["peakCells","Máxima extensión","count"],["centralization","Centralización","number"],["missionary","Ímpetu misionero","number"],["councils","Concilios","count"]],
	"war":[["start","Inicio","year"],["end","Final","year"],["active","Activa","bool"],["civil","Guerra civil","bool"],["holy","Guerra religiosa","bool"],["gainsAttackers","Ganancias atacantes","count"],["gainsDefenders","Ganancias defensores","count"]],
	"route":[["last","Última actividad","year"],["active","Activa","bool"]],
	"migration":[["start","Inicio","year"],["population","Población","count"],["done","Concluida","bool"]],
	"outbreak":[["start","Inicio","year"],["deaths","Muertes","count"],["done","Concluida","bool"]],
	"omen":[["year","Año","year"],["place","Lugar","text"],["radiusKM","Radio (km)","number"]],
	"cataclysm":[["year","Año","year"],["place","Lugar","text"],["deaths","Muertes","count"],["radiusKM","Radio (km)","number"]],
}
const RELATIONS := [["capitalId","Capital","cell"],["cellId","Provincia","cell"],["originCellId","Origen","cell"],
	["holyCellId","Lugar sagrado","cell"],["fromCellId","Origen","cell"],["toCellId","Destino","cell"],
	["rulerId","Gobernante","ruler"],["peopleId","Pueblo","people"],["religionId","Religión","religion"],
	["ownerPolityId","Estado","polity"],["polityId","Estado","polity"],["founderFigureId","Fundador","figure"],
	["attackers","Atacantes","polity"],["defenders","Defensores","polity"]]
const KIND_RELATIONS := {
	"polity":[["founderRulerId","Gobernante fundador","ruler"],["fromPolityId","Estado originario","polity"],["overlordId","Señor superior","polity"],["allies","Aliados","polity"],["enemies","Rivales","polity"],["children","Estados sucesores","polity"],["warIds","Guerras","war"]],
	"people":[["parentId","Pueblo ancestral","people"],["secondParentId","Otro pueblo ancestral","people"],["children","Pueblos descendientes","people"]],
	"religion":[["parentId","Tradición anterior","religion"],["children","Cismas y ramas","religion"],["stateIds","Estados que la adoptaron","polity"],["holderPolityId","Estado custodio","polity"]],
	"ruler":[["figureId","Figura histórica","figure"]],
	"migration":[["originPolityId","Estado de origen","polity"],["previousMigrationId","Migración anterior","migration"],["settledPolityId","Estado fundado","polity"]],
	"outbreak":[["fromPeopleId","Pueblo de origen","people"],["hitPolityIds","Estados afectados","polity"]],
	"cataclysm":[["hitPolityIds","Estados afectados","polity"]],
	"omen":[["outbreakId","Epidemia desatada","outbreak"],["cataclysmId","Cataclismo provocado","cataclysm"]],
}
const POLITY_METRICS := [["population","Población (censo)"],["cohesion","Cohesión"],["pressure","Presión social"],["eliteShare","Proporción de élites"],["crisisPressure","Inestabilidad"],["integration","Integración"],["treasury","Tesoro"]]
const LEXICON := ["Raíz","Río","Dios","Sol","Mar","Montaña","Madre","Grano"]


## Astronomical engine year with the v0.6 convention (year 0 is 1 a. C.).
static func fmt_year(y: Variant) -> String:
	if not (y is int or y is float): return "—"
	var value := int(y)
	return ("%d a. C." % (1 - value) if value <= 0 else "%d d. C." % value) + " [%d]" % value


static func record(frame: HistoryFrame, kind: String, id: int) -> Dictionary:
	if frame == null: return {}
	return frame.entity_records.get(kind, {}).get(id, {})


static func label(frame: HistoryFrame, kind: String, id: int) -> String:
	var value := record(frame, kind, id)
	var name := str(value.get("name", ""))
	return name if name != "" else "%s #%d" % [NAMES.get(kind, kind), id]


static func link(kind: String, id: int, text: String) -> String:
	return "[url=%s:%d]%s[/url]" % [kind, id, escape(text)]


static func cell_link(w: WorldData, id: int) -> String:
	if w == null or id < 0 or id >= w.cell_count(): return "—"
	return "[url=cell:%d]provincia #%d (%d, %d)[/url]" % [id, id, id % w.width, id / w.width]


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _value(field: Variant, format: String) -> String:
	match format:
		"year": return fmt_year(field)
		"bool": return "Sí" if field else "No"
		"count": return "%d" % int(float(field))
		"number": return "%.2f" % float(field)
	return escape(str(field))


## BBCode sheet for one record of the frame, or an explicit unavailability note.
static func render(frame: HistoryFrame, w: WorldData, kind: String, id: int) -> String:
	var title: String = NAMES.get(kind, kind)
	var value := record(frame, kind, id)
	if value.is_empty():
		return "[b]%s #%d[/b]\nEsta entidad no figura en la publicación Go del año %s. No se completa con datos inventados." % [title, id, fmt_year(frame.year if frame != null else null)]
	var lines := PackedStringArray()
	lines.append("[b]%s[/b] · %s Go #%d" % [escape(label(frame, kind, id)), title, id])
	lines.append("Publicación del año %s" % fmt_year(frame.year))
	for spec: Array in COMMON + LAYOUTS.get(kind, []):
		var field: Variant = value.get(spec[0])
		if field == null: continue
		lines.append("%s: %s" % [spec[1], _value(field, spec[2])])
	if kind == "polity" and value.get("metrics") is Dictionary:
		for spec: Array in POLITY_METRICS:
			var metric: Variant = value["metrics"].get(spec[0])
			if metric is float or metric is int:
				lines.append("%s: %s" % [spec[1], ("%d" % int(metric)) if spec[0] == "population" else "%.2f" % float(metric)])
	if kind == "people":
		var culture: Variant = value.get("culture")
		if culture is Array:
			var parts := PackedStringArray()
			for component: Variant in culture: parts.append("%.2f" % float(component) if component is float or component is int else "—")
			lines.append("Cultura (6 componentes Go): " + ", ".join(parts))
		var lexicon: Variant = value.get("lexicon")
		if lexicon is Array:
			for k in mini(LEXICON.size(), lexicon.size()):
				if str(lexicon[k]) != "": lines.append("%s: %s" % [LEXICON[k], escape(str(lexicon[k]))])
		var changes: Variant = value.get("soundChanges")
		if changes is Array and not changes.is_empty():
			lines.append("Cambios fonéticos: " + escape(", ".join(PackedStringArray(changes.slice(maxi(0, changes.size() - 8))))))
	for relation: Array in RELATIONS + KIND_RELATIONS.get(kind, []):
		var raw: Variant = value.get(relation[0])
		if raw == null: continue
		var targets: Array = raw if raw is Array else [raw]
		var links := PackedStringArray()
		for target: Variant in targets.slice(0, 20):
			if not (target is int or target is float): continue
			var ident := int(target)
			var target_kind: String = relation[2]
			if ident < 0 or (target_kind == "polity" and ident == 0): continue
			links.append(cell_link(w, ident) if target_kind == "cell" else link(target_kind, ident, label(frame, target_kind, ident)))
		if not links.is_empty():
			lines.append("%s: %s%s" % [relation[1], ", ".join(links), " …" if targets.size() > 20 else ""])
	if kind == "figure" and value.get("deeds") is Array:
		var deeds: Array = value["deeds"]
		if not deeds.is_empty(): lines.append("\n[b]Hazañas[/b]")
		for deed: Variant in deeds.slice(maxi(0, deeds.size() - 24)):
			if deed is Dictionary and deed.has("Year") and deed.has("Text"):
				lines.append("%s · %s" % [fmt_year(deed["Year"]), escape(str(deed["Text"]))])
	for spec: Array in [["text","Crónica"],["why","Contexto"],["outcome","Resultado"],["followText","Consecuencias"]]:
		if value.get(spec[0]) is String and value[spec[0]] != "":
			lines.append("\n[b]%s[/b]\n%s" % [spec[1], escape(str(value[spec[0]]))])
	return "\n".join(lines)


## One chronicle line with links to the event province and referenced entities.
static func event_line(frame: HistoryFrame, w: WorldData, event: Dictionary) -> String:
	var text := str(event.get("text", ""))
	if text == "": text = str(event.get("kind", "evento"))
	var line := "%s · [i]%s[/i] · %s" % [fmt_year(event.get("year")), escape(str(event.get("kind", ""))), escape(text)]
	var cell := int(event.get("cell", -1))
	if cell >= 0: line += " · " + cell_link(w, cell)
	for ref: Variant in event.get("refs", []):
		if ref is Dictionary and NAMES.has(str(ref.get("kind", ""))):
			var kind := str(ref["kind"])
			line += " · " + link(kind, int(ref.get("id", -1)), label(frame, kind, int(ref.get("id", -1))))
	return line


## Name search over the records already published by Go (no engine query).
static func search(frame: HistoryFrame, query: String, kind: String, limit := 60) -> Array:
	var out := []
	if frame == null: return out
	var needle := query.strip_edges().to_lower()
	for k: String in ([kind] if kind != "" else SEARCH_KINDS):
		var records: Dictionary = frame.entity_records.get(k, {})
		var ids := records.keys()
		ids.sort()
		for id: int in ids:
			var name := label(frame, k, id)
			if needle == "" or name.to_lower().contains(needle) or str(id) == needle:
				out.append([k, id, name])
				if out.size() >= limit: return out
	return out
