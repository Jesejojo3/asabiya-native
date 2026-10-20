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
signal playback_rate_changed(years_per_second: int)
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
var advance_years := 1
var _layer_panel: PanelContainer
var _map_button: Button
var _search_panel: PanelContainer
var _legend_panel: PanelContainer
var _legend_signature: Dictionary = {}
var _session_notice := ""
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
	resized.connect(_fit_layout)
	_fit_layout()


func _fit_layout() -> void:
	if top_stats.has("peoples"):
		top_stats["peoples"].get_parent().visible = size.x >= 1100.0
	top_seed.visible = size.x >= 1000.0


# ---------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG, 0, false))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 54
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	bar.add_child(h)
	h.add_child(UiTheme.heading("Asabiya", 19))
	top_seed = Label.new()
	top_seed.custom_minimum_size.x = 80
	top_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_seed.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_seed.clip_text = true
	top_seed.add_theme_color_override("font_color", UiTheme.MUTED)
	h.add_child(top_seed)
	for spec in [["population", "Población"], ["states", "Estados"], ["peoples", "Pueblos"]]:
		var metric := HBoxContainer.new()
		metric.add_theme_constant_override("separation", 6)
		var caption := UiTheme.muted(spec[1], 12)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		metric.add_child(caption)
		var value := Label.new()
		metric.add_child(value)
		top_stats[spec[0]] = value
		h.add_child(metric)
	# Kept for the stats API, without another permanent counter on the map.
	top_stats["land"] = Label.new()
	top_stats["land"].visible = false
	h.add_child(top_stats["land"])
	session_badge_box = HBoxContainer.new()
	session_badge_box.visible = false
	h.add_child(session_badge_box)
	_map_button = Button.new()
	_map_button.text = "Mapa: Terreno"
	_map_button.toggle_mode = true
	_map_button.focus_mode = Control.FOCUS_NONE
	_map_button.toggled.connect(_toggle_maps)
	h.add_child(_map_button)
	var search := Button.new()
	search.text = "Buscar"
	search.tooltip_text = "Buscar provincias y entidades (Ctrl+F)"
	search.focus_mode = Control.FOCUS_NONE
	search.pressed.connect(focus_search)
	h.add_child(search)
	var menu := MenuButton.new()
	menu.text = "Mundo"
	var pm := menu.get_popup()
	pm.add_item("Generar mundo…", 0)
	pm.add_item("Estadísticas", 1)
	pm.add_item("Centrar mapa (Inicio)", 2)
	pm.add_separator("Calidad gráfica")
	pm.add_radio_check_item("Alta", 10)
	pm.add_radio_check_item("Media", 11)
	pm.add_radio_check_item("Baja", 12)
	pm.add_separator("Relieve")
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
		4: app._request_close()


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
	return speed_option.get_item_id(speed_option.selected)


func stop_playing() -> void:
	_playing = false
	sim_buttons["play"].text = "Continuar"


# ---------------------------------------------------------------- layers

func _build_layer_panel() -> void:
	var p := PanelContainer.new()
	_layer_panel = p
	p.visible = false
	p.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 12
	p.offset_right = 252
	p.offset_top = 64
	p.offset_bottom = -126
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
		b.pressed.connect(func():
			layer_selected.emit(id)
			_toggle_maps(false))
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
	_legend_panel = PanelContainer.new()
	_legend_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend_panel.offset_left = 12
	_legend_panel.offset_right = 252
	_legend_panel.offset_top = -300
	_legend_panel.offset_bottom = -126
	_legend_panel.visible = false
	add_child(_legend_panel)
	var legend_scroll := ScrollContainer.new()
	legend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_legend_panel.add_child(legend_scroll)
	legend_box = VBoxContainer.new()
	legend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend_box.add_theme_constant_override("separation", 4)
	legend_scroll.add_child(legend_box)


func refresh_layers(source: HistorySource, frame: HistoryFrame, current: String) -> void:
	for id in layer_buttons:
		var b: Button = layer_buttons[id]
		var ok := MapLayers.available(id, source, frame)
		b.disabled = not ok
		b.visible = ok
		var d := MapLayers.def(id)
		if ok:
			b.tooltip_text = ""
		else:
			b.tooltip_text = "Requiere el sistema «%s» del motor Go.\nTodavía no está disponible en esta sesión." % d["requires"]
		b.set_pressed_no_signal(id == current)


func _toggle_maps(on: bool) -> void:
	_layer_panel.visible = on
	_map_button.set_pressed_no_signal(on)
	_legend_panel.visible = not on and _legend_signature.get("legend", {}).get("kind", "none") != "none"


func set_legend(title: String, legend: Dictionary) -> void:
	_map_button.text = "Mapa: " + title
	var signature := {"title":title, "legend":legend}
	if signature == _legend_signature: return
	_legend_signature = signature.duplicate(true)
	_legend_panel.visible = not _layer_panel.visible and legend.get("kind", "none") != "none"
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
	info_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	info_panel.offset_left = -364
	info_panel.offset_right = -12
	info_panel.offset_top = 64
	info_panel.offset_bottom = -126
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
## Missing facts are omitted instead of filling the panel with placeholders.
func show_info(title: String, subtitle: String, sections: Array) -> void:
	info_title.text = title
	info_subtitle.text = subtitle
	for c in info_body.get_children():
		c.queue_free()
	for sec in sections:
		var present := []
		for row in sec[1]:
			if row is Control or (row is Array and row.size() > 1 and row[1] != null): present.append(row)
		if present.is_empty(): continue
		info_body.add_child(UiTheme.heading(str(sec[0]), 13))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 3)
		info_body.add_child(grid)
		for row in present:
			if row is Control:
				info_body.add_child(row)
				continue
			var k := UiTheme.muted(str(row[0]), 12)
			k.custom_minimum_size.x = 108
			grid.add_child(k)
			var val: Variant = row[1]
			if val is Callable:
				var b := Button.new()
				b.flat = true
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.clip_text = true
				b.custom_minimum_size.x = 152
				b.text = str(row[2]) if row.size() > 2 else "Ver"
				b.tooltip_text = b.text
				b.pressed.connect(val)
				grid.add_child(b)
				continue
			var l := Label.new()
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(152, 0)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_font_size_override("font_size", 13)
			l.text = str(val)
			grid.add_child(l)
	info_panel.visible = not _search_panel.visible


# ---------------------------------------------------------------- timeline

func _build_timeline() -> void:
	timeline_panel = PanelContainer.new()
	timeline_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG, 0, false))
	timeline_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	timeline_panel.offset_top = -116
	timeline_panel.offset_bottom = 0
	add_child(timeline_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	timeline_panel.add_child(v)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	v.add_child(transport)
	var play := Button.new()
	play.text = "Continuar"
	play.custom_minimum_size.x = 104
	play.tooltip_text = "Simulación continua. Pausar termina el año en curso."
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(func():
		_playing = not _playing
		play.text = "Pausar" if _playing else "Continuar"
		play_toggled.emit(_playing))
	transport.add_child(play)
	sim_buttons["play"] = play
	speed_option = OptionButton.new()
	for rate in [1, 2, 5, 10, 25, 50, 0]:
		speed_option.add_item("Máxima" if rate == 0 else "%d año%s/s" % [rate, "" if rate == 1 else "s"], rate)
	speed_option.select(3)
	speed_option.tooltip_text = "Años por segundo. Máxima utiliza el ritmo que permita el equipo."
	speed_option.focus_mode = Control.FOCUS_NONE
	speed_option.item_selected.connect(func(_index: int): playback_rate_changed.emit(speed()))
	transport.add_child(speed_option)
	var step := Button.new()
	step.text = "1 año"
	step.tooltip_text = "Avanzar un año y permanecer en pausa"
	step.focus_mode = Control.FOCUS_NONE
	step.pressed.connect(func(): advance_requested.emit(1))
	transport.add_child(step)
	sim_buttons["advance"] = step
	var left_space := Control.new()
	left_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transport.add_child(left_space)
	top_year = Label.new()
	top_year.add_theme_font_size_override("font_size", 20)
	top_year.tooltip_text = "Año observado"
	transport.add_child(top_year)
	var right_space := Control.new()
	right_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transport.add_child(right_space)
	var chron := Button.new()
	chron.text = "Crónica"
	chron.toggle_mode = true
	chron.focus_mode = Control.FOCUS_NONE
	chron.toggled.connect(func(on: bool):
		chronicle_panel.visible = on
		if on: _fill_chronicle())
	transport.add_child(chron)
	for zoom_spec in [["−", -2.0, "Alejar"], ["+", 2.0, "Acercar"]]:
		var zoom := Button.new()
		zoom.text = zoom_spec[0]
		zoom.tooltip_text = zoom_spec[2]
		zoom.custom_minimum_size.x = 34
		zoom.focus_mode = Control.FOCUS_NONE
		var amount: float = zoom_spec[1]
		zoom.pressed.connect(func(): app.map_view.camera.zoom_by_steps(amount))
		transport.add_child(zoom)
	var track := HBoxContainer.new()
	v.add_child(track)
	for spec in [["back", "Primero", -100000], ["prev", "Anterior", -1]]:
		var button := Button.new()
		button.text = spec[1]
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		var amount: int = spec[2]
		button.pressed.connect(func(): _step_frames(amount))
		track.add_child(button)
		sim_buttons[spec[0]] = button
	timeline_slider = HSlider.new()
	timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_slider.focus_mode = Control.FOCUS_NONE
	timeline_slider.tooltip_text = "Consultar años recibidos; moverlo pausa la simulación"
	timeline_slider.value_changed.connect(func(x: float):
		var ys: PackedInt32Array = app.source.years()
		if not ys.is_empty(): year_requested.emit(ys[clampi(int(x), 0, ys.size() - 1)]))
	track.add_child(timeline_slider)
	var next := Button.new()
	next.text = "Siguiente"
	next.flat = true
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(func(): _step_frames(1))
	track.add_child(next)
	sim_buttons["next"] = next
	timeline_label = UiTheme.muted("", 11)
	timeline_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	track.add_child(timeline_label)
	status_label = UiTheme.muted("", 11)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.clip_text = true
	status_label.visible = false
	v.add_child(status_label)
	timeline_hint = UiTheme.muted("", 11)
	v.add_child(timeline_hint)

func refresh_timeline(source: HistorySource, year: int) -> void:
	var ys := source.years()
	timeline_slider.editable = ys.size() > 1
	if ys.is_empty():
		timeline_label.text = ""
		timeline_hint.text = "Preparando la historia…" if source is BridgeSource else "Sin historia cargada."
		timeline_hint.visible = true
	else:
		timeline_slider.min_value = 0
		timeline_slider.max_value = maxi(1, ys.size() - 1)
		timeline_slider.step = 1
		timeline_slider.set_value_no_signal(maxi(0, ys.bsearch(year) if ys.has(year) else ys.bsearch(year) - 1))
		timeline_label.text = "En directo" if _playing else ("Pausa" if year == ys[ys.size() - 1] else "Historial")
		timeline_hint.visible = false
	sim_buttons["advance"].disabled = not source.can_advance() or _playing
	# Pausing must remain possible during the first year in flight.
	sim_buttons["play"].disabled = ys.is_empty() or not (source is BridgeSource and (source as BridgeSource).connected)
	sim_buttons["back"].disabled = ys.size() < 2 or year <= ys[0]
	sim_buttons["prev"].disabled = sim_buttons["back"].disabled
	sim_buttons["next"].disabled = ys.size() < 2 or year >= ys[ys.size() - 1]

static func fmt_year(y: int) -> String:
	# Same astronomical-year convention as v0.6 fy: year 0 is 1 BCE.
	return "%d a. C." % (1 - y) if y <= 0 else "%d d. C." % y


# ---------------------------------------------------------------- chronicle

func _build_chronicle() -> void:
	chronicle_panel = PanelContainer.new()
	chronicle_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chronicle_panel.offset_left = 12
	chronicle_panel.offset_right = 512
	chronicle_panel.offset_top = -414
	chronicle_panel.offset_bottom = -126
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
	if _chronicle_events == events: return
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
	if chronicle_panel.visible: _fill_chronicle()


func _fill_chronicle() -> void:
	chronicle_list.clear()
	var f := chronicle_filter.get_item_text(chronicle_filter.selected) if chronicle_filter.item_count > 0 else "Todos"
	if _chronicle_events.is_empty():
		chronicle_list.add_item("Todavía no hay acontecimientos registrados.", null, false)
		return
	for k in range(_chronicle_events.size() - 1, maxi(-1, _chronicle_events.size() - 501), -1):
		var e: Dictionary = _chronicle_events[k]
		if f != "Todos" and str(e.get("kind", "otros")) != f:
			continue
		var idx := chronicle_list.add_item("%s — %s" % [fmt_year(int(e.get("year", 0))), str(e.get("text", ""))])
		chronicle_list.set_item_metadata(idx, {"cell":int(e.get("cell", -1)),"event":int(e.get("id", -1))})


func _on_chronicle_activated(i: int) -> void:
	var value: Variant = chronicle_list.get_item_metadata(i)
	if value is Dictionary:
		if int(value.get("cell", -1)) >= 0: fly_to.emit(int(value["cell"]))
		if int(value.get("event", -1)) >= 0: entity_requested.emit("engine:event", int(value["event"]))


# ---------------------------------------------------------------- search

func _build_search() -> void:
	var p := PanelContainer.new()
	_search_panel = p
	p.visible = false
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -364
	p.offset_right = -12
	p.offset_top = 64
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Estado, pueblo, ciudad o x,y"
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


func dismiss_popovers() -> bool:
	var had_popup := _search_panel.visible or _layer_panel.visible
	_search_panel.hide()
	search_edit.release_focus()
	_toggle_maps(false)
	if had_popup and app.selection.get("kind", "") != "":
		app.select_entity(app.selection["kind"], app.selection["id"], false)
	return had_popup


func focus_search() -> void:
	_search_panel.show()
	info_panel.hide()
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
	_search_panel.hide()
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
	v.add_child(UiTheme.muted("Elige una semilla. Se generará un mundo y comenzará una historia nueva:", 12))
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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	stats_body = VBoxContainer.new()
	stats_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stats_body)
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
		stats_body.add_child(UiTheme.muted("%s · población %s · %d Estados · %d pueblos · %d asentamientos" % [fmt_year(f.year), _fmt_int(f.world_population), f.state_count(), f.peoples.size(), f.settlements.size()], 12))

		if not f.stats.is_empty():
			var census: Dictionary = f.stats[f.stats.size() - 1]
			stats_body.add_child(UiTheme.muted("Último censo: %s · era líder %d" % [fmt_year(int(census.get("year", f.year))), int(census.get("leadingEra", 0))], 12))
		for group in [["war", "Guerras activas"], ["ruler", "Gobernantes"], ["religion", "Religiones"], ["route", "Rutas comerciales"]]:
			stats_body.add_child(UiTheme.heading(group[1], 13))
			var records: Dictionary = f.entity_records.get(group[0], {})
			var shown := 0
			for id: int in records:
				var record: Dictionary = records[id]
				if group[0] == "war" and not record.get("active", false): continue
				if group[0] == "route" and not record.get("active", false): continue
				var button := Button.new()
				button.text = str(record.get("name", "%s #%d" % [group[0], id]))
				var kind_name: String = group[0]
				button.pressed.connect(func() -> void: entity_requested.emit("engine:" + kind_name, id))
				stats_body.add_child(button)
				shown += 1
				if shown >= 20: break


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
	status_label.tooltip_text = text
	status_label.visible = text != ""


func set_session(source: HistorySource, world: WorldData) -> void:
	var notice := ""
	if source is BridgeSource and not (source as BridgeSource).connected:
		notice = "Sin conexión"
	elif not world.has_fine:
		notice = "Relieve simplificado"
	if notice != _session_notice:
		_session_notice = notice
		for child in session_badge_box.get_children(): child.queue_free()
		if notice != "":
			var label := UiTheme.muted(notice, 12)
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			session_badge_box.add_child(label)
	session_badge_box.visible = notice != ""
	top_seed.text = world.world_seed
	top_seed.tooltip_text = "Semilla: " + world.world_seed
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
	top_stats["states"].text = str(frame.state_count())
	top_stats["peoples"].text = str(frame.peoples.size())
