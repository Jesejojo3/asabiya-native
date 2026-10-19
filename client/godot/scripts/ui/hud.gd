class_name Hud
extends Control
## Observer interface: top bar, map modes, legend, contextual panel, timeline,
## chronicle and search. Purely presentation: it reads the App's current world,
## source and frame and emits intents; it never mutates history.

signal layer_selected(id: String)
signal opacity_changed(v: float)
signal toggle_changed(name: String, on: bool)
signal year_requested(year: int)
signal advance_requested(years: int)
signal play_toggled(on: bool)
signal fly_to(cell: int)
signal entity_requested(kind: String, id: int)
signal world_requested(seed_text: String)
signal deselect_requested
signal setting_changed(key: String, value: Variant)

var app: Node
var top_year: Label
var top_seed: Label
var top_stats: Dictionary = {}
var session_badge_box: HBoxContainer
var sim_buttons: Dictionary = {}
var speed_option: OptionButton
var layer_buttons: Dictionary = {}
var layer_group := ButtonGroup.new()
var legend_box: VBoxContainer
var info_panel: PanelContainer
var info_body: VBoxContainer
var info_title: Label
var info_subtitle: Label
var timeline_panel: PanelContainer
var timeline_slider: HSlider
var timeline_label: Label
var timeline_hint: Label
var chronicle_panel: PanelContainer
var chronicle_list: ItemList
var chronicle_filter: OptionButton
var search_edit: LineEdit
var search_results: ItemList
var hover_tip: PanelContainer
var hover_label: Label
var status_label: Label
var help_panel: PanelContainer
var world_dialog: ConfirmationDialog
var world_seed_edit: LineEdit
var stats_panel: PanelContainer
var stats_body: VBoxContainer
var _search_targets: Array = []
var _chronicle_events: Array = []
var _playing := false


func build(application: Node) -> void:
	app = application
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build_top_bar()
	_build_layer_panel()
	_build_info_panel()
	_build_timeline()
	_build_chronicle()
	_build_search()
	_build_hover_tip()
	_build_help()
	_build_world_dialog()
	_build_stats()


# ---------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG, 0, false))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 46
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)
	var logo := UiTheme.heading("ASABIYA", 18)
	h.add_child(logo)
	h.add_child(VSeparator.new())
	top_year = Label.new()
	top_year.add_theme_font_size_override("font_size", 18)
	top_year.tooltip_text = "Año de la sesión"
	h.add_child(top_year)
	top_seed = Label.new()
	top_seed.add_theme_color_override("font_color", UiTheme.MUTED)
	h.add_child(top_seed)
	h.add_child(VSeparator.new())
	for k in [["population", "Población"], ["states", "Estados"], ["peoples", "Pueblos"], ["land", "Celdas de tierra"]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		var cap := UiTheme.muted(k[1], 10)
		cap.autowrap_mode = TextServer.AUTOWRAP_OFF
		var val := Label.new()
		val.add_theme_font_size_override("font_size", 14)
		v.add_child(cap)
		v.add_child(val)
		h.add_child(v)
		top_stats[k[0]] = val
	session_badge_box = HBoxContainer.new()
	h.add_child(session_badge_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	status_label = UiTheme.muted("", 12)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(status_label)
	var sim := HBoxContainer.new()
	sim.add_theme_constant_override("separation", 4)
	h.add_child(sim)
	for spec in [["back", "⏮", "Ir al primer año disponible"], ["prev", "◀", "Fotograma anterior"], ["play", "▶", "Reproducir / pausar la historia"], ["next", "▶|", "Fotograma siguiente"], ["advance", "+10 años", "Pedir al motor Go que simule 10 años"]]:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE
		sim.add_child(b)
		sim_buttons[spec[0]] = b
	speed_option = OptionButton.new()
	for s in ["×1", "×2", "×5", "×10"]:
		speed_option.add_item(s)
	speed_option.tooltip_text = "Velocidad de reproducción"
	speed_option.focus_mode = Control.FOCUS_NONE
	sim.add_child(speed_option)
	sim_buttons["back"].pressed.connect(func(): _step_frames(-100000))
	sim_buttons["prev"].pressed.connect(func(): _step_frames(-1))
	sim_buttons["next"].pressed.connect(func(): _step_frames(1))
	sim_buttons["play"].pressed.connect(func():
		_playing = not _playing
		sim_buttons["play"].text = "⏸" if _playing else "▶"
		play_toggled.emit(_playing))
	sim_buttons["advance"].pressed.connect(func(): advance_requested.emit(10))
	h.add_child(VSeparator.new())
	var menu := MenuButton.new()
	menu.text = "Mundo"
	menu.flat = false
	var pm := menu.get_popup()
	pm.add_item("Generar mundo…", 0)
	pm.add_item("Estadísticas", 1)
	pm.add_item("Centrar mapa (Inicio)", 2)
	pm.add_separator("Calidad gráfica")
	pm.add_radio_check_item("Alta", 10)
	pm.add_radio_check_item("Media", 11)
	pm.add_radio_check_item("Baja", 12)
	pm.add_separator("Relieve (sólo visual)")
	pm.add_radio_check_item("Suave", 20)
	pm.add_radio_check_item("Normal", 21)
	pm.add_radio_check_item("Dramático", 22)
	pm.add_separator()
	pm.add_item("Ayuda (F1)", 3)
	pm.add_item("Salir (Ctrl+Q)", 4)
	pm.id_pressed.connect(_on_menu)
	pm.hide_on_checkable_item_selection = true
	sim_buttons["menu"] = menu
	h.add_child(menu)


func set_menu_checks(quality: int, relief: int) -> void:
	var pm := (sim_buttons["menu"] as MenuButton).get_popup()
	for i in pm.item_count:
		var id := pm.get_item_id(i)
		if id >= 10 and id <= 12:
			pm.set_item_checked(i, id - 10 == quality)
		if id >= 20 and id <= 22:
			pm.set_item_checked(i, id - 20 == relief)


func _on_menu(id: int) -> void:
	if id >= 10 and id <= 12:
		setting_changed.emit("quality", id - 10)
		return
	if id >= 20 and id <= 22:
		setting_changed.emit("relief", id - 20)
		return
	match id:
		0: world_dialog.popup_centered(Vector2i(420, 160))
		1: toggle_stats()
		2: app.map_view.camera.reset_view()
		3: help_panel.visible = not help_panel.visible
		4: get_tree().quit()


func _step_frames(delta: int) -> void:
	var ys: PackedInt32Array = app.source.years()
	if ys.is_empty():
		return
	var idx := ys.bsearch(app.current_year)
	if delta < -1000:
		idx = 0
	else:
		idx = clampi(idx + delta, 0, ys.size() - 1)
	year_requested.emit(ys[idx])


func playing() -> bool:
	return _playing


func speed() -> int:
	return [1, 2, 5, 10][speed_option.selected]


func stop_playing() -> void:
	_playing = false
	sim_buttons["play"].text = "▶"


# ---------------------------------------------------------------- layers

func _build_layer_panel() -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 10
	p.offset_right = 210
	p.offset_top = 56
	p.offset_bottom = -10
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	scroll.add_child(v)
	v.add_child(UiTheme.heading("Mapas", 15))
	var group := ""
	for d in MapLayers.DEFS:
		if d["group"] != group:
			group = d["group"]
			var g := UiTheme.muted(group.to_upper(), 10)
			g.add_theme_color_override("font_color", UiTheme.GOLD.darkened(0.25))
			v.add_child(g)
		var b := Button.new()
		b.text = d["name"]
		b.toggle_mode = true
		b.button_group = layer_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_constant_override("h_separation", 2)
		b.custom_minimum_size = Vector2(0, 24)
		var id: String = d["id"]
		b.pressed.connect(func(): layer_selected.emit(id))
		v.add_child(b)
		layer_buttons[id] = b
	v.add_child(HSeparator.new())
	v.add_child(UiTheme.muted("Opacidad de la capa", 11))
	var op := HSlider.new()
	op.min_value = 0.0
	op.max_value = 1.0
	op.step = 0.01
	op.value = 0.85
	op.focus_mode = Control.FOCUS_NONE
	op.value_changed.connect(func(x: float): opacity_changed.emit(x))
	v.add_child(op)
	for spec in [["borders", "Fronteras provinciales", true], ["labels", "Nombres", true], ["settlements", "Asentamientos", true], ["events", "Acontecimientos", true], ["vegetation", "Vegetación decorativa", true]]:
		var cb := CheckBox.new()
		cb.text = spec[1]
		cb.button_pressed = spec[2]
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 12)
		var key: String = spec[0]
		cb.toggled.connect(func(on: bool): toggle_changed.emit(key, on))
		if key == "vegetation":
			cb.tooltip_text = "Árboles y rocas derivados del bioma y del bosque inicial del motor.\nSon decoración: no representan entidades ni cambios históricos."
		v.add_child(cb)
	legend_box = VBoxContainer.new()
	legend_box.add_theme_constant_override("separation", 2)
	v.add_child(HSeparator.new())
	v.add_child(legend_box)


func refresh_layers(source: HistorySource, frame: HistoryFrame, current: String) -> void:
	for id in layer_buttons:
		var b: Button = layer_buttons[id]
		var ok := MapLayers.available(id, source, frame)
		b.disabled = not ok
		var d := MapLayers.def(id)
		if ok:
			b.tooltip_text = ""
		else:
			b.tooltip_text = "Requiere el sistema «%s» del motor Go.\nTodavía no está disponible en esta sesión." % d["requires"]
		b.set_pressed_no_signal(id == current)


func set_legend(title: String, legend: Dictionary) -> void:
	for c in legend_box.get_children():
		c.queue_free()
	legend_box.add_child(UiTheme.heading(title, 13))
	match legend.get("kind", "none"):
		"ramp":
			var r := TextureRect.new()
			var g := Gradient.new()
			var offs := PackedFloat32Array()
			for k in MapLayers.RAMP.size():
				offs.append(float(k) / (MapLayers.RAMP.size() - 1))
			g.offsets = offs
			g.colors = PackedColorArray(MapLayers.RAMP)
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.width = 160
			gt.height = 10
			r.texture = gt
			r.custom_minimum_size = Vector2(170, 10)
			r.stretch_mode = TextureRect.STRETCH_SCALE
			legend_box.add_child(r)
			var hb := HBoxContainer.new()
			var a := UiTheme.muted(str(legend.get("min", "")), 11)
			var b := UiTheme.muted(str(legend.get("max", "")), 11)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hb.add_child(a)
			hb.add_child(b)
			legend_box.add_child(hb)
		"swatches":
			for it in legend.get("items", []):
				var hb2 := HBoxContainer.new()
				var sw := ColorRect.new()
				sw.color = it[0]
				sw.custom_minimum_size = Vector2(12, 12)
				hb2.add_child(sw)
				hb2.add_child(UiTheme.muted(str(it[1]), 11))
				legend_box.add_child(hb2)
		"text":
			legend_box.add_child(UiTheme.muted(str(legend.get("text", "")), 11))
		_:
			legend_box.add_child(UiTheme.muted("Relieve, biomas y ríos del motor.", 11))


# ---------------------------------------------------------------- info panel

func _build_info_panel() -> void:
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -380
	info_panel.offset_right = -10
	info_panel.offset_top = 100
	info_panel.offset_bottom = 640
	info_panel.visible = false
	add_child(info_panel)
	var v := VBoxContainer.new()
	info_panel.add_child(v)
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	info_title = UiTheme.heading("", 18)
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_subtitle = UiTheme.muted("", 12)
	tv.add_child(info_title)
	tv.add_child(info_subtitle)
	head.add_child(tv)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): deselect_requested.emit())
	head.add_child(close)
	v.add_child(head)
	v.add_child(HSeparator.new())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	info_body = VBoxContainer.new()
	info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(info_body)


func hide_info() -> void:
	info_panel.visible = false


## sections: Array of [title, rows]; rows: Array of [key, value-or-null, opts]
## A null value is rendered as "No disponible todavía" with the reason.
func show_info(title: String, subtitle: String, sections: Array) -> void:
	info_title.text = title
	info_subtitle.text = subtitle
	for c in info_body.get_children():
		c.queue_free()
	for sec in sections:
		info_body.add_child(UiTheme.heading(str(sec[0]), 13))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 3)
		info_body.add_child(grid)
		for row in sec[1]:
			if row is Control:
				info_body.add_child(row)
				continue
			var k := UiTheme.muted(str(row[0]), 12)
			k.autowrap_mode = TextServer.AUTOWRAP_OFF
			grid.add_child(k)
			var val: Variant = row[1]
			var l := Label.new()
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(200, 0)
			l.add_theme_font_size_override("font_size", 13)
			if val == null:
				l.text = "No disponible todavía" + (" · " + str(row[2]) if row.size() > 2 else "")
				l.add_theme_color_override("font_color", UiTheme.MISSING)
				l.add_theme_font_size_override("font_size", 12)
			elif val is Callable:
				var b := LinkButton.new()
				b.text = str(row[2]) if row.size() > 2 else "Ver"
				b.pressed.connect(val)
				grid.add_child(b)
				continue
			else:
				l.text = str(val)
			grid.add_child(l)
	info_panel.visible = true


# ---------------------------------------------------------------- timeline

func _build_timeline() -> void:
	timeline_panel = PanelContainer.new()
	timeline_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	timeline_panel.offset_left = 220
	timeline_panel.offset_right = -400
	timeline_panel.offset_top = -64
	timeline_panel.offset_bottom = -10
	add_child(timeline_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	timeline_panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UiTheme.heading("Línea del tiempo", 13))
	timeline_label = Label.new()
	timeline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(timeline_label)
	var chron := Button.new()
	chron.text = "Crónica"
	chron.toggle_mode = true
	chron.focus_mode = Control.FOCUS_NONE
	chron.toggled.connect(func(on: bool): chronicle_panel.visible = on)
	h.add_child(chron)
	timeline_slider = HSlider.new()
	timeline_slider.focus_mode = Control.FOCUS_NONE
	timeline_slider.value_changed.connect(func(x: float):
		var ys: PackedInt32Array = app.source.years()
		if not ys.is_empty():
			year_requested.emit(ys[clampi(int(x), 0, ys.size() - 1)]))
	v.add_child(timeline_slider)
	timeline_hint = UiTheme.muted("", 11)
	v.add_child(timeline_hint)


func refresh_timeline(source: HistorySource, year: int) -> void:
	var ys := source.years()
	timeline_slider.visible = ys.size() > 1
	timeline_slider.editable = ys.size() > 1
	if ys.is_empty():
		timeline_label.text = ""
		if source.kind() == "bridge" and source.has_method("start"):
			timeline_hint.text = "Esperando fotogramas del motor Go…"
		else:
			timeline_hint.text = "Sin historia en esta sesión: el motor todavía no simula población ni años. Los cambios aparecerán cuando el motor Go los envíe."
		timeline_hint.visible = true
	else:
		timeline_slider.min_value = 0
		timeline_slider.max_value = ys.size() - 1
		timeline_slider.step = 1
		timeline_slider.set_value_no_signal(maxi(0, ys.bsearch(year) if ys.has(year) else ys.bsearch(year) - 1))
		timeline_label.text = "%s · %d fotogramas (%s – %s)" % [fmt_year(year), ys.size(), fmt_year(ys[0]), fmt_year(ys[ys.size() - 1])]
		timeline_hint.visible = false
	var can := source.can_advance()
	sim_buttons["advance"].disabled = not can
	sim_buttons["advance"].tooltip_text = "Pedir al motor Go que simule 10 años" if can else "El motor Go aún no expone el avance anual (AdvanceYear) a este cliente."
	for k in ["back", "prev", "play", "next"]:
		sim_buttons[k].disabled = ys.size() < 2 and not can


static func fmt_year(y: int) -> String:
	return "%d a. C." % (-y) if y < 0 else "%d d. C." % y


# ---------------------------------------------------------------- chronicle

func _build_chronicle() -> void:
	chronicle_panel = PanelContainer.new()
	chronicle_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chronicle_panel.offset_left = 220
	chronicle_panel.offset_right = 700
	chronicle_panel.offset_top = -340
	chronicle_panel.offset_bottom = -74
	chronicle_panel.visible = false
	add_child(chronicle_panel)
	var v := VBoxContainer.new()
	chronicle_panel.add_child(v)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.heading("Crónica", 15))
	chronicle_filter = OptionButton.new()
	chronicle_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chronicle_filter.item_selected.connect(func(_i: int): _fill_chronicle())
	h.add_child(chronicle_filter)
	v.add_child(h)
	chronicle_list = ItemList.new()
	chronicle_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chronicle_list.item_activated.connect(_on_chronicle_activated)
	chronicle_list.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _on_chronicle_activated(i))
	v.add_child(chronicle_list)


func set_chronicle(events: Array) -> void:
	_chronicle_events = events
	var kinds := {}
	for e in events:
		kinds[str(e.get("kind", "otros"))] = true
	var prev := chronicle_filter.get_item_text(chronicle_filter.selected) if chronicle_filter.item_count > 0 else "Todos"
	chronicle_filter.clear()
	chronicle_filter.add_item("Todos")
	for k in kinds.keys():
		chronicle_filter.add_item(str(k))
	for i in chronicle_filter.item_count:
		if chronicle_filter.get_item_text(i) == prev:
			chronicle_filter.select(i)
	_fill_chronicle()


func _fill_chronicle() -> void:
	chronicle_list.clear()
	var f := chronicle_filter.get_item_text(chronicle_filter.selected) if chronicle_filter.item_count > 0 else "Todos"
	if _chronicle_events.is_empty():
		chronicle_list.add_item("El motor no ha registrado acontecimientos en esta sesión.", null, false)
		return
	for k in range(_chronicle_events.size() - 1, -1, -1):
		var e: Dictionary = _chronicle_events[k]
		if f != "Todos" and str(e.get("kind", "otros")) != f:
			continue
		var idx := chronicle_list.add_item("%s — %s" % [fmt_year(int(e.get("year", 0))), str(e.get("text", ""))])
		chronicle_list.set_item_metadata(idx, int(e.get("cell", -1)))


func _on_chronicle_activated(i: int) -> void:
	var c = chronicle_list.get_item_metadata(i)
	if c != null and int(c) >= 0:
		fly_to.emit(int(c))


# ---------------------------------------------------------------- search

func _build_search() -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -380
	p.offset_right = -10
	p.offset_top = 54
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Buscar: Estado, pueblo, ciudad o x,y  (Ctrl+F)"
	search_edit.clear_button_enabled = true
	search_edit.text_changed.connect(_on_search)
	search_edit.text_submitted.connect(func(_t: String):
		if search_results.item_count > 0:
			_on_search_pick(0))
	v.add_child(search_edit)
	search_results = ItemList.new()
	search_results.custom_minimum_size = Vector2(0, 160)
	search_results.visible = false
	search_results.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _on_search_pick(i))
	v.add_child(search_results)


func focus_search() -> void:
	search_edit.grab_focus()
	search_edit.select_all()


func _on_search(text: String) -> void:
	search_results.clear()
	_search_targets.clear()
	var t := text.strip_edges().to_lower()
	if t == "":
		search_results.visible = false
		return
	var parts := t.replace(" ", "").split(",")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var cid: int = app.world.cell_id(int(parts[0]), int(parts[1]))
		if cid >= 0:
			_add_result("Celda %s,%s" % [parts[0], parts[1]], "cell", cid)
	var f: HistoryFrame = app.current_frame
	if f != null:
		for id in f.states:
			if str(f.states[id].get("name", "")).to_lower().contains(t):
				_add_result("Estado · %s" % f.states[id]["name"], "state", id)
		for id in f.peoples:
			if str(f.peoples[id].get("name", "")).to_lower().contains(t):
				_add_result("Pueblo · %s" % f.peoples[id]["name"], "people", id)
		for s in f.settlements:
			if str(s.get("name", "")).to_lower().contains(t):
				_add_result("Asentamiento · %s" % s["name"], "settlement", int(s["id"]))
	if search_results.item_count == 0:
		search_results.add_item("Sin resultados" + ("" if f != null else " (no hay entidades históricas en esta sesión; prueba x,y)"), null, false)
	search_results.visible = true


func _add_result(label: String, kind: String, id: int) -> void:
	if search_results.item_count >= 40:
		return
	search_results.add_item(label)
	_search_targets.append([kind, id])


func _on_search_pick(i: int) -> void:
	if i >= _search_targets.size():
		return
	var tg: Array = _search_targets[i]
	entity_requested.emit(tg[0], tg[1])
	search_results.visible = false
	search_edit.release_focus()


# ---------------------------------------------------------------- hover, help, dialogs

func _build_hover_tip() -> void:
	hover_tip = PanelContainer.new()
	hover_tip.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.06, 0.08, 0.9), 4))
	hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tip.visible = false
	add_child(hover_tip)
	hover_label = Label.new()
	hover_label.add_theme_font_size_override("font_size", 12)
	hover_tip.add_child(hover_label)


func set_hover(text: String) -> void:
	hover_tip.visible = text != ""
	hover_label.text = text
	hover_tip.reset_size()


func _process(_dt: float) -> void:
	if hover_tip.visible:
		var m := get_local_mouse_position()
		var s := hover_tip.size
		var vp := size
		hover_tip.position = Vector2(minf(m.x + 18, vp.x - s.x - 6), minf(m.y + 18, vp.y - s.y - 6))


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.custom_minimum_size = Vector2(520, 0)
	help_panel.offset_left = -260
	help_panel.offset_top = -190
	help_panel.visible = false
	add_child(help_panel)
	var v := VBoxContainer.new()
	help_panel.add_child(v)
	v.add_child(UiTheme.heading("Controles", 17))
	for row in [
		["Arrastrar (izq.)", "Desplazar el mapa"], ["Rueda", "Acercar / alejar hacia el cursor"],
		["Arrastrar (der./central)", "Girar e inclinar"], ["W A S D / flechas", "Desplazar"],
		["Q / E · R / F", "Girar · inclinar"], ["Clic", "Seleccionar provincia o asentamiento"],
		["Inicio", "Vista mundial"], ["Ctrl+F", "Buscar"], ["1 – 9", "Mapas rápidos"],
		["Esc", "Quitar selección"], ["F1", "Esta ayuda"], ["Ctrl+Q", "Salir"]]:
		var h := HBoxContainer.new()
		var k := Label.new()
		k.text = row[0]
		k.custom_minimum_size = Vector2(190, 0)
		k.add_theme_color_override("font_color", UiTheme.GOLD)
		h.add_child(k)
		h.add_child(Label.new())
		(h.get_child(1) as Label).text = row[1]
		v.add_child(h)
	v.add_child(HSeparator.new())
	v.add_child(UiTheme.muted("Las provincias son las celdas geográficas del motor (400×200). El relieve está exagerado verticalmente sólo para la vista; la simulación usa las alturas reales. La vegetación es decorativa.", 12))
	var close := Button.new()
	close.text = "Cerrar"
	close.pressed.connect(func(): help_panel.visible = false)
	v.add_child(close)


func _build_world_dialog() -> void:
	world_dialog = ConfirmationDialog.new()
	world_dialog.title = "Generar mundo"
	world_dialog.ok_button_text = "Generar"
	var v := VBoxContainer.new()
	v.add_child(UiTheme.muted("Semilla del mundo (la genera el motor Go con asabiya-snapshot):", 12))
	world_seed_edit = LineEdit.new()
	world_seed_edit.text = "Asabiya"
	v.add_child(world_seed_edit)
	world_dialog.add_child(v)
	world_dialog.confirmed.connect(func(): world_requested.emit(world_seed_edit.text))
	add_child(world_dialog)


func _build_stats() -> void:
	stats_panel = PanelContainer.new()
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.custom_minimum_size = Vector2(460, 0)
	stats_panel.offset_left = -230
	stats_panel.offset_top = -220
	stats_panel.visible = false
	add_child(stats_panel)
	var v := VBoxContainer.new()
	stats_panel.add_child(v)
	stats_body = VBoxContainer.new()
	v.add_child(stats_body)
	var close := Button.new()
	close.text = "Cerrar"
	close.pressed.connect(func(): stats_panel.visible = false)
	v.add_child(close)


func toggle_stats() -> void:
	stats_panel.visible = not stats_panel.visible
	if stats_panel.visible:
		_fill_stats()


func _fill_stats() -> void:
	for c in stats_body.get_children():
		c.queue_free()
	var w: WorldData = app.world
	stats_body.add_child(UiTheme.heading("Estadísticas del mundo", 17))
	stats_body.add_child(UiTheme.muted("Semilla «%s» · %d×%d celdas · relieve fino %s" % [w.world_seed, w.width, w.height, ("%d×%d" % [w.fine_width, w.fine_height]) if w.has_fine else "no incluido"], 12))
	var counts := []
	counts.resize(10)
	counts.fill(0)
	var total_area := 0.0
	for i in w.land_cells:
		counts[int(w.biome[i])] += 1
		total_area += w.area[i]
	stats_body.add_child(Label.new())
	(stats_body.get_child(stats_body.get_child_count() - 1) as Label).text = "Tierra: %d celdas · %s km² · %d masas" % [w.land_cells.size(), _fmt_int(total_area), int(w.header.get("world", {}).get("landmasses", 0))]
	stats_body.add_child(UiTheme.heading("Biomas (celdas de tierra)", 13))
	for b in range(1, 10):
		var h := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = WorldData.BIOME_NAMES_ES[b]
		lbl.custom_minimum_size = Vector2(130, 0)
		h.add_child(lbl)
		var bar := ColorRect.new()
		bar.color = MapLayers.BIOME_LEGEND[b - 1]
		bar.custom_minimum_size = Vector2(240.0 * counts[b] / maxf(1.0, w.land_cells.size()), 12)
		h.add_child(bar)
		h.add_child(UiTheme.muted("%.1f %%" % (100.0 * counts[b] / maxf(1.0, w.land_cells.size())), 11))
		stats_body.add_child(h)
	var f: HistoryFrame = app.current_frame
	stats_body.add_child(UiTheme.heading("Historia", 13))
	if f == null:
		stats_body.add_child(UiTheme.muted("No disponible todavía: el motor no ha enviado datos históricos.", 12))
	else:
		stats_body.add_child(UiTheme.muted("%s · población %s · %d Estados · %d pueblos · %d asentamientos" % [fmt_year(f.year), _fmt_int(f.world_population), f.states.size(), f.peoples.size(), f.settlements.size()], 12))


static func _fmt_int(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var rem := n - 1 - i
		if rem > 0 and rem % 3 == 0 and s[i] != "-":
			out += " "
	return out


func set_status(text: String) -> void:
	status_label.text = text


func set_session(source: HistorySource, world: WorldData) -> void:
	for c in session_badge_box.get_children():
		c.queue_free()
	match source.kind():
		"bridge":
			session_badge_box.add_child(UiTheme.badge(source.label(), UiTheme.OK if source.get("connected") else UiTheme.WARN))
		_:
			session_badge_box.add_child(UiTheme.badge("Sesión real · geografía del motor", UiTheme.OK))
			if source.years().is_empty():
				session_badge_box.add_child(UiTheme.badge("Sin historia todavía", UiTheme.WARN))
	if not world.has_fine:
		session_badge_box.add_child(UiTheme.badge("Relieve grueso", UiTheme.WARN))
	top_seed.text = "Semilla «%s»" % world.world_seed
	top_stats["land"].text = _fmt_int(world.land_cells.size())


func set_frame_stats(frame: HistoryFrame, start_year: int) -> void:
	if frame == null:
		top_year.text = fmt_year(start_year)
		for k in ["population", "states", "peoples"]:
			top_stats[k].text = "—"
			top_stats[k].tooltip_text = "No disponible todavía en el motor"
		return
	top_year.text = fmt_year(frame.year)
	top_stats["population"].text = _fmt_int(frame.world_population) if frame.world_population > 0.0 else "—"
	top_stats["states"].text = str(frame.states.size()) if not frame.states.is_empty() else "—"
	top_stats["peoples"].text = str(frame.peoples.size()) if not frame.peoples.is_empty() else "—"
