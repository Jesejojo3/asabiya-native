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
signal fast_forward_requested(years_count: int, publish_every: int)
signal playback_rate_changed(years_per_second: int)
signal fly_to(cell: int)
signal focus_cell(cell: int)
signal entity_requested(kind: String, id: int)
signal world_requested(seed_text: String)
signal deselect_requested
signal setting_changed(key: String, value: Variant)

const LEGACY_ERAS := ["Foraging","Neolithic","Bronze Age","Iron Age","Classical","Medieval","Gunpowder age","Age of Sail"]

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
var chronicle_query: LineEdit
var chronicle_matches: Label
var figures_panel: PanelContainer
var disasters_panel: PanelContainer
var disaster_query: LineEdit
var disaster_sort: OptionButton
var cataclysm_list: ItemList
var outbreak_list: ItemList
var cataclysm_title: Label
var outbreak_title: Label
var figure_filter: OptionButton
var figure_query: LineEdit
var figure_list: ItemList
var search_edit: LineEdit
var search_results: ItemList
var hover_tip: PanelContainer
var hover_label: Label
var status_label: Label
var help_panel: PanelContainer
var fast_dialog: ConfirmationDialog
var fast_years: SpinBox
var fast_interval: OptionButton
var _throughput_started := 0
var _throughput_initial_year := 0
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
var _nav: Array[Dictionary] = []
var _nav_index := -1
var _navigating := false
var _info_signature: Array = []
var _info_entity: Dictionary = {}
var _section_tabs: TabBar
var _section_nodes: Array[Control] = []
var _info_scroll: ScrollContainer
var _section_key := ""
var _notice: PanelContainer
var _notice_text: Label
var _notice_recover: Button
var _scale_label: Label
var _scale_buttons: Array[Button] = []
var _layer_signature: Array = []
var _top_bar: PanelContainer
var _rail: VBoxContainer
var _scale_bar: PanelContainer
var _welcome: PanelContainer
var _reduced_motion := false
var _fade: Tween
var _transport_busy := false
var _transport_live := false
var _transport_connected := false
var _search_timer: Timer


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
	_build_figures()
	_build_disasters()
	_build_search()
	_build_hover_tip()
	_build_help()
	_build_world_dialog()
	_build_fast_dialog()
	_build_stats()
	_build_atlas_navigation()
	_build_notice()
	resized.connect(_fit_layout)
	_fit_layout()


func _fit_layout() -> void:
	if top_stats.has("peoples"):
		top_stats["peoples"].get_parent().visible = size.x >= 1250.0
		top_stats["population"].get_parent().visible = size.x >= 1050.0
	top_seed.visible = size.x >= 1380.0
	var inspector_width := clampf(size.x * 0.27, 320.0, 390.0)
	info_panel.offset_right = 76.0 + inspector_width
	_search_panel.offset_left = -minf(390.0, size.x - 100.0)
	help_panel.custom_minimum_size.x = minf(520.0, size.x - 48.0)
	if stats_body != null:
		(stats_body.get_parent() as ScrollContainer).custom_minimum_size.y = clampf(size.y - 260.0, 180.0, 480.0)
	if _welcome != null:
		_welcome.visible = size.x >= 1250.0 and not info_panel.visible

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	_top_bar = bar
	bar.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG, 0, false))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 68
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	bar.add_child(h)
	h.add_child(UiTheme.heading("ASABIYA", 23))
	top_seed = Label.new()
	top_seed.custom_minimum_size.x = 80
	top_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_seed.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_seed.clip_text = true
	top_seed.add_theme_color_override("font_color", UiTheme.MUTED)
	h.add_child(top_seed)
	var stretch := Control.new()
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(stretch)
	for spec in [["population", "Población"], ["states", "Estados"], ["peoples", "Pueblos"]]:
		var metric := VBoxContainer.new()
		metric.add_theme_constant_override("separation", 0)
		var caption := UiTheme.muted(spec[1], 12)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		metric.add_child(caption)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", 17)
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
	_map_button.text = "Terreno"
	_map_button.icon = AtlasIcons.get_icon("atlas")
	_map_button.toggle_mode = true
	_map_button.focus_mode = Control.FOCUS_NONE
	_map_button.toggled.connect(_toggle_maps)
	h.add_child(_map_button)
	var search := Button.new()
	search.text = "Buscar"
	search.icon = AtlasIcons.get_icon("search")
	search.tooltip_text = "Buscar provincias y entidades (Ctrl+F)"
	search.focus_mode = Control.FOCUS_NONE
	search.pressed.connect(focus_search)
	h.add_child(search)
	var menu := MenuButton.new()
	menu.text = "Menú"
	menu.icon = AtlasIcons.get_icon("menu")
	var pm := menu.get_popup()
	pm.add_item("Generar mundo…", 0)
	pm.add_item("Estadísticas", 1)
	pm.add_item("Figuras históricas", 6)
	pm.add_item("Epidemias y cataclismos", 7)
	pm.add_item("Simulación rápida…", 5)
	pm.add_item("Centrar mapa (Inicio)", 2)
	pm.add_separator("Interfaz")
	pm.add_check_item("Reducir animaciones", 30)
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
		30:
			_reduced_motion = not _reduced_motion
			var popup := (sim_buttons["menu"] as MenuButton).get_popup()
			popup.set_item_checked(popup.get_item_index(30), _reduced_motion)
			if _reduced_motion and _fade != null: _fade.kill()
			info_panel.modulate.a = 1.0
		0: world_dialog.popup_centered(Vector2i(420, 160))
		1: toggle_stats()
		6: _toggle_figures(not figures_panel.visible)
		7: _toggle_disasters(not disasters_panel.visible)
		5:
			if app.source.can_advance(): fast_dialog.popup_centered_clamped(Vector2i(440, 260), 0.75)
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
	sim_buttons["play"].icon = AtlasIcons.get_icon("play")


# ---------------------------------------------------------------- layers

func _build_layer_panel() -> void:
	var p := PanelContainer.new()
	_layer_panel = p
	p.visible = false
	p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -310
	p.offset_right = -16
	p.offset_top = 130
	p.offset_bottom = -154
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
	_legend_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_legend_panel.offset_left = -276
	_legend_panel.offset_right = -16
	_legend_panel.offset_top = -338
	_legend_panel.offset_bottom = -154
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
	var signature := [source, frame, current]
	if signature == _layer_signature: return
	_layer_signature = signature
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
	if on:
		chronicle_panel.hide()
		sim_buttons["chronicle"].set_pressed_no_signal(false)
		figures_panel.hide()
		disasters_panel.hide()
		_search_panel.hide()
	_layer_panel.visible = on
	_map_button.set_pressed_no_signal(on)
	_legend_panel.visible = not on and not chronicle_panel.visible and not figures_panel.visible and not disasters_panel.visible and not _search_panel.visible and _legend_signature.get("legend", {}).get("kind", "none") != "none"


func set_legend(title: String, legend: Dictionary) -> void:
	_map_button.text = title
	var signature := {"title":title, "legend":legend}
	if signature == _legend_signature: return
	_legend_signature = signature.duplicate(true)
	_legend_panel.visible = not _layer_panel.visible and not chronicle_panel.visible and not figures_panel.visible and not disasters_panel.visible and not _search_panel.visible and legend.get("kind", "none") != "none"
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
	info_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	info_panel.offset_left = 76
	info_panel.offset_right = 426
	info_panel.offset_top = 130
	info_panel.offset_bottom = -154
	info_panel.visible = false
	add_child(info_panel)
	var v := VBoxContainer.new()
	info_panel.add_child(v)
	var navigation := HBoxContainer.new()
	v.add_child(navigation)
	for spec in [["back", "Ficha anterior"], ["forward", "Ficha siguiente"], ["focus", "Localizar en el mapa"]]:
		var b := Button.new()
		b.icon = AtlasIcons.get_icon(spec[0])
		b.tooltip_text = spec[1]
		b.custom_minimum_size = Vector2(32, 32)
		var key: String = spec[0]
		b.pressed.connect(func():
			if key == "focus": app.focus_selection()
			else: _navigate(-1 if key == "back" else 1))
		sim_buttons["nav_" + key] = b
		navigation.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	var close := Button.new()
	close.icon = AtlasIcons.get_icon("close")
	close.tooltip_text = "Cerrar ficha (Esc)"
	close.pressed.connect(func(): deselect_requested.emit())
	navigation.add_child(close)
	info_title = UiTheme.heading("", 23)
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info_title)
	info_subtitle = UiTheme.muted("", 12)
	v.add_child(info_subtitle)
	_section_tabs = TabBar.new()
	_section_tabs.scrolling_enabled = true
	_section_tabs.clip_tabs = true
	_section_tabs.tab_changed.connect(_show_section)
	v.add_child(_section_tabs)
	_info_scroll = ScrollContainer.new()
	_info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_info_scroll)
	info_body = VBoxContainer.new()
	info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_scroll.add_child(info_body)
	v.add_child(UiTheme.muted("Observaciones del motor Go · sin intervención causal", 10))

func hide_info() -> void:
	info_panel.hide()
	if _welcome != null: _welcome.visible = size.x >= 1250.0

func show_info(title: String, subtitle: String, sections: Array) -> void:
	# A detail reply or status refresh need not rebuild an unchanged inspector.
	var entity: Dictionary = app.selection.duplicate()
	var signature := [entity, title, subtitle]
	for sec: Array in sections:
		var values := [sec[0]]
		for row: Variant in sec[1]:
			if row is Label: values.append(row.text)
			elif row is Array and row.size() > 1 and row[1] != null:
				values.append([row[0], str(row[2]) if row[1] is Callable and row.size() > 2 else str(row[1])])
		signature.append(values)
	if signature == _info_signature:
		for sec: Array in sections:
			for row: Variant in sec[1]:
				if row is Control and not row.is_inside_tree(): row.free()
		info_panel.visible = true
		if _welcome != null: _welcome.hide()
		return
	var changed_entity := entity != _info_entity or info_title.text != title
	_info_entity = entity
	var previous_section := _section_key
	_info_signature = signature
	info_title.text = title
	info_subtitle.text = subtitle
	for c in info_body.get_children():
		info_body.remove_child(c)
		c.queue_free()
	_section_nodes.clear()
	_section_tabs.clear_tabs()
	for sec: Array in sections:
		var present := []
		for row: Variant in sec[1]:
			if row is Control or (row is Array and row.size() > 1 and row[1] != null): present.append(row)
		if present.is_empty(): continue
		var section := VBoxContainer.new()
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_body.add_child(section)
		_section_nodes.append(section)
		_section_tabs.add_tab(str(sec[0]))
		section.add_child(UiTheme.heading(str(sec[0]), 17))
		for row: Variant in present:
			if row is Control:
				section.add_child(row)
				continue
			var fact := VBoxContainer.new()
			fact.add_theme_constant_override("separation", 2)
			section.add_child(fact)
			fact.add_child(UiTheme.muted(str(row[0]).to_upper(), 10))
			var val: Variant = row[1]
			if val is Callable:
				var b := Button.new()
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.text = str(row[2]) if row.size() > 2 else "Ver"
				b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				b.tooltip_text = b.text + " · abrir ficha sin mover el mapa"
				b.icon = AtlasIcons.get_icon("forward")
				b.pressed.connect(val)
				fact.add_child(b)
			else:
				var l := Label.new()
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.text = str(val)
				fact.add_child(l)
			section.add_child(HSeparator.new())
	var selected := 0
	if not changed_entity:
		for i in _section_tabs.tab_count:
			if _section_tabs.get_tab_title(i) == previous_section: selected = i
	_section_tabs.current_tab = selected
	_show_section(selected)
	info_panel.show()
	if _welcome != null: _welcome.hide()
	if changed_entity and not _reduced_motion:
		if _fade != null: _fade.kill()
		info_panel.modulate.a = 0.35
		_fade = create_tween()
		_fade.tween_property(info_panel, "modulate:a", 1.0, 0.16)

func _build_timeline() -> void:
	timeline_panel = PanelContainer.new()
	timeline_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG, 0, false))
	timeline_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	timeline_panel.offset_left = 16
	timeline_panel.offset_right = -16
	timeline_panel.offset_top = -138
	timeline_panel.offset_bottom = -16
	add_child(timeline_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	timeline_panel.add_child(v)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	v.add_child(transport)
	var play := Button.new()
	play.text = "Continuar"
	play.icon = AtlasIcons.get_icon("play")
	play.custom_minimum_size.x = 104
	play.tooltip_text = "Simulación continua. Pausar termina el año en curso."
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(func():
		_playing = not _playing
		play.text = "Pausar" if _playing else "Continuar"
		play.icon = AtlasIcons.get_icon("pause" if _playing else "play")
		play_toggled.emit(_playing))
	transport.add_child(play)
	sim_buttons["play"] = play
	speed_option = OptionButton.new()
	for rate in [1, 2, 5, 10, 25, 50, 0]:
		speed_option.add_item("Máxima" if rate == 0 else "%d año%s/s" % [rate, "" if rate == 1 else "s"], rate)
	speed_option.select(3)
	speed_option.tooltip_text = "Límite de observación, no rendimiento garantizado. Máxima publica cada año sin demora artificial. Para omitir estados visuales intermedios usa Menú → Simulación rápida."
	speed_option.focus_mode = Control.FOCUS_NONE
	speed_option.item_selected.connect(func(_index: int): playback_rate_changed.emit(speed()))
	transport.add_child(speed_option)
	var step := Button.new()
	step.text = "1 año"
	step.icon = AtlasIcons.get_icon("step")
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
	chron.icon = AtlasIcons.get_icon("chronicle")
	chron.toggle_mode = true
	chron.focus_mode = Control.FOCUS_NONE
	chron.toggled.connect(func(on: bool):
		_toggle_chronicle(on))
	transport.add_child(chron)
	sim_buttons["chronicle"] = chron
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
		timeline_label.text = "EN DIRECTO" if _playing else ("PAUSA" if year == ys[ys.size() - 1] else "ARCHIVO")
		if source is BridgeSource and (source as BridgeSource).busy:
			timeline_label.text = "CALCULANDO…" if _playing else "FINALIZANDO AÑO"
		if source is BridgeSource and (source as BridgeSource).is_fast_forward(): timeline_label.text = "RÁPIDO" if _playing else "FINALIZANDO AÑO"
		timeline_slider.tooltip_text = "Años recibidos: %s — %s. Caché limitada; no es un archivo completo." % [fmt_year(ys[0]), fmt_year(ys[ys.size() - 1])]
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
	chronicle_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	chronicle_panel.offset_left = -460
	chronicle_panel.offset_right = -16
	chronicle_panel.offset_top = 130
	chronicle_panel.offset_bottom = -154
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
	chronicle_query = LineEdit.new()
	chronicle_query.placeholder_text = "Buscar en la crónica o en sus causas"
	chronicle_query.clear_button_enabled = true
	chronicle_query.text_changed.connect(func(_text: String): _fill_chronicle())
	v.add_child(chronicle_query)
	chronicle_matches = UiTheme.muted("", 11)
	v.add_child(chronicle_matches)
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
	var query := chronicle_query.text.strip_edges().to_lower()
	if _chronicle_events.is_empty():
		chronicle_matches.text = "0 acontecimientos"
		chronicle_list.add_item("Todavía no hay acontecimientos registrados.", null, false)
		return
	var matches := 0
	# Search the entire *retained* Go publication, not just its newest 500.
	# Display a bounded 300 rows as in the original HTML chronicle.
	for k in range(_chronicle_events.size() - 1, -1, -1):
		var e: Dictionary = _chronicle_events[k]
		if f != "Todos" and str(e.get("kind", "otros")) != f:
			continue
		var entry_text := str(e.get("text", ""))
		var context := str(e.get("why", ""))
		if not query.is_empty() and not entry_text.to_lower().contains(query) and not context.to_lower().contains(query):
			continue
		matches += 1
		if matches > 300:
			continue
		var idx := chronicle_list.add_item("%s — %s" % [fmt_year(int(e.get("year", 0))), entry_text])
		chronicle_list.set_item_metadata(idx, {"cell":int(e.get("cell", -1)),"event":int(e.get("id", -1))})
	chronicle_matches.text = "%d coincidencias%s" % [matches, " · mostrando 300" if matches > 300 else ""]
	if matches == 0:
		chronicle_list.add_item("No hay acontecimientos que coincidan.", null, false)


func _on_chronicle_activated(i: int) -> void:
	var value: Variant = chronicle_list.get_item_metadata(i)
	if value is Dictionary:
		if int(value.get("cell", -1)) >= 0: fly_to.emit(int(value["cell"]))
		if int(value.get("event", -1)) >= 0: entity_requested.emit("engine:event", int(value["event"]))


# ---------------------------------------------------------------- historical figures (HTML v0.6 figures pane)

func _build_figures() -> void:
	figures_panel = PanelContainer.new()
	figures_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	figures_panel.offset_left = -460
	figures_panel.offset_right = -16
	figures_panel.offset_top = 130
	figures_panel.offset_bottom = -154
	figures_panel.visible = false
	add_child(figures_panel)
	var v := VBoxContainer.new()
	figures_panel.add_child(v)
	v.add_child(UiTheme.heading("Figuras históricas", 17))
	figure_filter = OptionButton.new()
	for label in ["Todas", "Gobernantes", "Profetas y reformadores", "Fundadores y usurpadores", "Sabios y estudiosos"]:
		figure_filter.add_item(label)
	figure_filter.item_selected.connect(func(_index: int): _fill_figures())
	v.add_child(figure_filter)
	figure_query = LineEdit.new()
	figure_query.placeholder_text = "Buscar por nombre o título"
	figure_query.clear_button_enabled = true
	figure_query.text_changed.connect(func(_text: String): _fill_figures())
	v.add_child(figure_query)
	figure_list = ItemList.new()
	figure_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	figure_list.item_activated.connect(_on_figure_activated)
	figure_list.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _on_figure_activated(i))
	v.add_child(figure_list)


static func _figure_score(f: Dictionary, religions: Dictionary) -> float:
	# Display ranking from v0.6 figScore: no changes to simulation state.
	var deeds: Array = f.get("deeds", [])
	var score := float(f.get("conquests", 0)) * 1.5 + float(f.get("realmCells", 0))
	score += deeds.size() * 4.0 + float(f.get("works", 0)) * 12.0
	if bool(f.get("exceptional", false)):
		score += 5.0
	var religion_id := int(f.get("religionId", -1))
	if religion_id >= 0 and religions.has(religion_id):
		var religion: Dictionary = religions[religion_id]
		score += 10.0 * sqrt(maxf(0.0, float(religion.get("peakCells", 0))))
		var states: Array = religion.get("stateIds", [])
		score += minf(100.0, float(states.size())) * 0.5
	return score


func _fill_figures() -> void:
	figure_list.clear()
	var f: HistoryFrame = app.current_frame
	if f == null:
		figure_list.add_item("Inicia una historia para consultar figuras.", null, false)
		return
	var query := figure_query.text.strip_edges().to_lower()
	var filter_id := figure_filter.selected
	var ranked := []
	var religions: Dictionary = f.entity_records.get("religion", {})
	var records: Dictionary = f.entity_records.get("figure", {})
	for id in records:
		var fields: Dictionary = records[id]
		var kind := str(fields.get("kind", ""))
		var accepted := filter_id == 0 or (filter_id == 1 and kind == "ruler") \
			or (filter_id == 2 and kind in ["prophet", "reformer"]) \
			or (filter_id == 3 and kind in ["founder", "usurper"]) \
			or (filter_id == 4 and kind in ["sage", "scholar"])
		if not accepted:
			continue
		var name := str(fields.get("name", ""))
		var title := str(fields.get("title", ""))
		if not query.is_empty() and not name.to_lower().contains(query) and not title.to_lower().contains(query):
			continue
		ranked.append({"id":int(id), "fields":fields, "score":_figure_score(fields, religions)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) == float(b["score"]):
			return int(a["id"]) < int(b["id"])
		return float(a["score"]) > float(b["score"]))
	for i in mini(120, ranked.size()):
		var item: Dictionary = ranked[i]
		var fields: Dictionary = item["fields"]
		var label := str(fields.get("name", ""))
		if fields.has("born"):
			label += " · " + fmt_year(int(fields["born"]))
		if str(fields.get("title", "")) != "":
			label += " · " + str(fields["title"])
		var row := figure_list.add_item(label)
		figure_list.set_item_metadata(row, int(item["id"]))
	if figure_list.item_count == 0:
		figure_list.add_item("No hay figuras que coincidan con este filtro.", null, false)


func _on_figure_activated(index: int) -> void:
	if index < 0 or index >= figure_list.item_count or figure_list.is_item_disabled(index):
		return
	var id: Variant = figure_list.get_item_metadata(index)
	if id == null:
		return
	figures_panel.hide()
	entity_requested.emit("engine:figure", int(id))


func _toggle_figures(on: bool) -> void:
	figures_panel.visible = on
	if on:
		disasters_panel.hide()
		_toggle_maps(false)
		_toggle_chronicle(false)
		_search_panel.hide()
		_legend_panel.hide()
		_fill_figures()
	else:
		_legend_panel.visible = not _layer_panel.visible and not chronicle_panel.visible and not _search_panel.visible and _legend_signature.get("legend", {}).get("kind", "none") != "none"


# ---------------------------------------------------------------- epidemics and cataclysms (HTML v0.6 plague pane)

func _build_disasters() -> void:
	disasters_panel = PanelContainer.new()
	disasters_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	disasters_panel.offset_left = -460
	disasters_panel.offset_right = -16
	disasters_panel.offset_top = 130
	disasters_panel.offset_bottom = -154
	disasters_panel.visible = false
	add_child(disasters_panel)
	var v := VBoxContainer.new()
	disasters_panel.add_child(v)
	v.add_child(UiTheme.heading("Epidemias y cataclismos", 17))
	disaster_query = LineEdit.new()
	disaster_query.placeholder_text = "Buscar por nombre o lugar"
	disaster_query.clear_button_enabled = true
	disaster_query.text_changed.connect(func(_text: String): _fill_disasters())
	v.add_child(disaster_query)
	cataclysm_title = UiTheme.heading("Cataclismos", 13)
	v.add_child(cataclysm_title)
	cataclysm_list = ItemList.new()
	cataclysm_list.custom_minimum_size.y = 115
	cataclysm_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cataclysm_list.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _on_disaster_activated(cataclysm_list, i))
	cataclysm_list.item_activated.connect(func(i: int): _on_disaster_activated(cataclysm_list, i))
	v.add_child(cataclysm_list)
	var sort_line := HBoxContainer.new()
	outbreak_title = UiTheme.heading("Epidemias", 13)
	sort_line.add_child(outbreak_title)
	disaster_sort = OptionButton.new()
	disaster_sort.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disaster_sort.add_item("Más mortíferas")
	disaster_sort.add_item("Más recientes")
	disaster_sort.item_selected.connect(func(_index: int): _fill_disasters())
	sort_line.add_child(disaster_sort)
	v.add_child(sort_line)
	outbreak_list = ItemList.new()
	outbreak_list.custom_minimum_size.y = 115
	outbreak_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outbreak_list.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _on_disaster_activated(outbreak_list, i))
	outbreak_list.item_activated.connect(func(i: int): _on_disaster_activated(outbreak_list, i))
	v.add_child(outbreak_list)


func _fill_disasters() -> void:
	cataclysm_list.clear()
	outbreak_list.clear()
	var frame: HistoryFrame = app.current_frame
	if frame == null:
		cataclysm_list.add_item("Todavía no hay historia disponible.", null, false)
		outbreak_list.add_item("Todavía no hay historia disponible.", null, false)
		return
	var query := disaster_query.text.strip_edges().to_lower()
	for kind in ["cataclysm", "outbreak"]:
		var found := []
		var records: Dictionary = frame.entity_records.get(kind, {})
		for ident in records:
			var fields: Dictionary = records[ident]
			var year := int(fields.get("year", fields.get("start", frame.year)))
			if year > frame.year:
				continue
			var name := str(fields.get("name", ""))
			var place := str(fields.get("place", ""))
			if not query.is_empty() and not name.to_lower().contains(query) and not place.to_lower().contains(query):
				continue
			found.append({"id":int(ident),"fields":fields,"year":year,"deaths":float(fields.get("deaths", 0.0))})
		var most_deadly := kind == "outbreak" and disaster_sort.selected == 0
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if most_deadly and float(a["deaths"]) != float(b["deaths"]):
				return float(a["deaths"]) > float(b["deaths"])
			if int(a["year"]) != int(b["year"]):
				return int(a["year"]) > int(b["year"])
			return int(a["id"]) > int(b["id"]))
		var target: ItemList = cataclysm_list if kind == "cataclysm" else outbreak_list
		var limit := 80 if kind == "cataclysm" else 100
		for i in mini(found.size(), limit):
			var entry: Dictionary = found[i]
			var fields: Dictionary = entry["fields"]
			var name := str(fields.get("name", ""))
			if name == "":
				name = str(fields.get("kind", "Cataclismo")) if kind == "cataclysm" else "Epidemia"
			var label := "%s · %s" % [fmt_year(entry["year"]), name]
			if fields.has("deaths"):
				label += " · %s muertes" % _fmt_int(float(entry["deaths"]))
			if kind == "outbreak" and not bool(fields.get("done", true)):
				label += " · activa"
			var index := target.add_item(label)
			var cell_key := "cellId" if kind == "cataclysm" else "originCellId"
			target.set_item_metadata(index, {"kind":kind,"id":entry["id"],"cell":int(fields.get(cell_key, -1))})
		if target.item_count == 0:
			target.add_item("Sin registros que coincidan.", null, false)
		if kind == "cataclysm":
			cataclysm_title.text = "Cataclismos · %d" % found.size()
		else:
			outbreak_title.text = "Epidemias · %d" % found.size()


func _on_disaster_activated(target: ItemList, index: int) -> void:
	if index < 0 or index >= target.item_count or target.is_item_disabled(index):
		return
	var entry: Variant = target.get_item_metadata(index)
	if not entry is Dictionary:
		return
	disasters_panel.hide()
	var cell := int(entry.get("cell", -1))
	if cell >= 0 and cell < app.world.cell_count():
		# Focus the camera only; selecting a province here would race the
		# asynchronous detail query against the disaster inspector.
		focus_cell.emit(cell)
	entity_requested.emit("engine:" + str(entry["kind"]), int(entry["id"]))


func _toggle_disasters(on: bool) -> void:
	disasters_panel.visible = on
	if on:
		_toggle_maps(false)
		_toggle_chronicle(false)
		figures_panel.hide()
		_search_panel.hide()
		_legend_panel.hide()
		_fill_disasters()
	else:
		_legend_panel.visible = not _layer_panel.visible and not chronicle_panel.visible and not figures_panel.visible and not _search_panel.visible and _legend_signature.get("legend", {}).get("kind", "none") != "none"


# ---------------------------------------------------------------- search

func _build_search() -> void:
	var p := PanelContainer.new()
	_search_panel = p
	p.visible = false
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -390
	p.offset_right = -16
	p.offset_top = 130
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	search_edit = LineEdit.new()
	v.add_child(UiTheme.heading("Explorar el atlas", 21))
	search_edit.placeholder_text = "Estado, pueblo, religión, ciudad o x,y"
	search_edit.clear_button_enabled = true
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.14
	add_child(_search_timer)
	_search_timer.timeout.connect(func(): _on_search(search_edit.text))
	search_edit.text_changed.connect(func(_text: String): _search_timer.start())
	search_edit.text_submitted.connect(func(_t: String):
		_search_timer.stop()
		_on_search(search_edit.text)
		if search_results.item_count > 0:
			_on_search_pick(0))
	v.add_child(search_edit)
	search_results = ItemList.new()
	search_results.custom_minimum_size = Vector2(0, 220)
	search_results.visible = false
	search_results.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _on_search_pick(i))
	v.add_child(search_results)


func dismiss_popovers() -> bool:
	var had_popup := _search_panel.visible or _layer_panel.visible or chronicle_panel.visible or figures_panel.visible or disasters_panel.visible or _notice.visible
	disasters_panel.hide()
	figures_panel.hide()
	_toggle_chronicle(false)
	_notice.hide()
	_search_panel.hide()
	search_edit.release_focus()
	_toggle_maps(false)
	return had_popup


func focus_search() -> void:
	_search_panel.show()
	disasters_panel.hide()
	figures_panel.hide()
	_toggle_maps(false)
	_toggle_chronicle(false)
	_on_search(search_edit.text)
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
		for id in f.religions:
			if str(f.religions[id].get("name", "")).to_lower().contains(t):
				_add_result("Religión · %s" % f.religions[id]["name"], "engine:religion", id)
		for s in f.settlements:
			if str(s.get("name", "")).to_lower().contains(t):
				_add_result("Asentamiento · %s" % s["name"], "settlement", int(s["id"]))
		# The HTML v0.6 inspector exposes historical figures, rulers, wars,
		# migrations, routes, epidemics, omens and cataclysms. The Go bridge
		# already publishes them, but they were not discoverable from the atlas.
		# Search cached entity records only on a user query, never each frame.
		for spec in [
			["figure", "Figura histórica"], ["ruler", "Gobernante"],
			["war", "Guerra"], ["migration", "Migración"],
			["route", "Ruta comercial"], ["outbreak", "Epidemia"],
			["omen", "Presagio"], ["cataclysm", "Cataclismo"]
		]:
			if search_results.item_count >= 40:
				break
			var entity_kind: String = spec[0]
			var records: Dictionary = f.entity_records.get(entity_kind, {})
			for entity_id in records:
				if search_results.item_count >= 40:
					break
				var fields: Dictionary = records[entity_id]
				var name := str(fields.get("name", ""))
				# Some native entities intentionally lack a generated name.
				# Derive only an ID/type label; never synthesize historical lore.
				if name.is_empty():
					match entity_kind:
						"omen": name = "Presagio %s #%d" % [str(fields.get("type", "")), int(entity_id)]
						"route": name = "Ruta comercial #%d" % int(entity_id)
						"outbreak": name = "Epidemia #%d" % int(entity_id)
						"cataclysm": name = "%s #%d" % [str(fields.get("kind", "Cataclismo")), int(entity_id)]
				if name.is_empty():
					continue
				var title := str(fields.get("title", "")) if entity_kind == "figure" else ""
				if name.to_lower().contains(t) or title.to_lower().contains(t):
					_add_result("%s · %s" % [spec[1], name], "engine:" + entity_kind, int(entity_id))
		# Extinct polities and peoples no longer appear on the live map,
		# but remain valid historical entities exposed by the Go catalog.
		for spec in [["polity", "Estado histórico"], ["people", "Pueblo histórico"]]:
			if search_results.item_count >= 40:
				break
			var entity_kind: String = spec[0]
			var records: Dictionary = f.entity_records.get(entity_kind, {})
			for entity_id in records:
				if search_results.item_count >= 40:
					break
				var fields: Dictionary = records[entity_id]
				if fields.get("alive", true):
					continue
				var name := str(fields.get("name", ""))
				if not name.is_empty() and name.to_lower().contains(t):
					_add_result("%s · %s" % [spec[1], name], "engine:" + entity_kind, int(entity_id))
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
	_toggle_maps(false)
	app.select_entity(tg[0], tg[1], false)
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
	if app.source is BridgeSource:
		var bridge := app.source as BridgeSource
		if bridge.busy != _transport_busy or bridge.is_live() != _transport_live or bridge.connected != _transport_connected:
			_transport_busy = bridge.busy
			_transport_live = bridge.is_live()
			_transport_connected = bridge.connected
			refresh_timeline(app.source, app.current_year)
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
		["Inicio", "Vista continental"], ["Espacio", "Continuar / pausar"], ["Alt + ← / →", "Ficha anterior / siguiente"], ["Ctrl+F", "Buscar"], ["1 – 9", "Mapas rápidos"],
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
	world_dialog.title = "Iniciar una nueva sesión"
	world_dialog.ok_button_text = "Generar"
	var v := VBoxContainer.new()
	v.add_child(UiTheme.muted("La sesión actual se cerrará; no se guarda ni se recupera su historia. Elige una semilla para comenzar un mundo nuevo:", 12))
	world_seed_edit = LineEdit.new()
	world_seed_edit.text = app.world.world_seed
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
			stats_body.add_child(UiTheme.muted("Último censo: %s · era líder %s" % [fmt_year(int(census.get("year", f.year))), era_name(int(census.get("leadingEra", 0)))], 12))
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
	if status_label.text == text: return
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
	if disasters_panel.visible:
		_fill_disasters()

func _icon_button(icon: String, hint: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = AtlasIcons.get_icon(icon)
	button.tooltip_text = hint
	button.custom_minimum_size = Vector2(42, 42)
	button.pressed.connect(action)
	return button


func _build_atlas_navigation() -> void:
	var rail := PanelContainer.new()
	rail.position = Vector2(16, 130)
	var rail_style := UiTheme.panel_style(UiTheme.BG, 4)
	rail_style.set_content_margin_all(6)
	rail.add_theme_stylebox_override("panel", rail_style)
	add_child(rail)
	_rail = VBoxContainer.new()
	rail.add_child(_rail)
	_rail.add_child(_icon_button("atlas", "Mapas temáticos", func(): _toggle_maps(not _layer_panel.visible)))
	_rail.add_child(_icon_button("search", "Buscar entidades · Ctrl+F", focus_search))
	_rail.add_child(_icon_button("chronicle", "Crónica histórica", func(): _toggle_chronicle(not chronicle_panel.visible)))
	_rail.add_child(_icon_button("people", "Figuras históricas del mundo", func(): _toggle_figures(not figures_panel.visible)))
	_rail.add_child(_icon_button("chronicle", "Epidemias y cataclismos", func(): _toggle_disasters(not disasters_panel.visible)))
	_rail.add_child(HSeparator.new())
	_rail.add_child(_icon_button("home", "Vista continental · Inicio", func(): app.map_view.camera.set_scale_view(0)))
	_scale_bar = PanelContainer.new()
	_scale_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_scale_bar.offset_left = -434
	_scale_bar.offset_right = -16
	_scale_bar.offset_top = 76
	var scale_style := UiTheme.panel_style(UiTheme.BG, 4)
	scale_style.set_content_margin_all(6)
	_scale_bar.add_theme_stylebox_override("panel", scale_style)
	add_child(_scale_bar)
	var scales := HBoxContainer.new()
	_scale_bar.add_child(scales)
	for i in 3:
		var b := Button.new()
		b.text = ["Continente", "Región", "Provincia"][i]
		b.tooltip_text = ["Visión global del mundo", "Territorios y relieve", "Acercar al foco actual; selecciona una provincia para localizarla"][i]
		b.toggle_mode = true
		b.pressed.connect(func(): app.map_view.camera.set_scale_view(i))
		scales.add_child(b)
		_scale_buttons.append(b)
	_scale_label = UiTheme.muted("N ↑", 11)
	_scale_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_scale_label.custom_minimum_size.x = 46
	scales.add_child(_scale_label)
	_welcome = PanelContainer.new()
	_welcome.position = Vector2(92, 130)
	_welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_welcome)
	var welcome_text := VBoxContainer.new()
	welcome_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_welcome.add_child(welcome_text)
	welcome_text.add_child(UiTheme.heading("Un mundo por descubrir", 20))
	welcome_text.add_child(UiTheme.muted("Selecciona una provincia · rueda para acercarte\nCtrl+F para buscar · Espacio para pausar", 12))
	sim_buttons["nav_back"].disabled = true
	sim_buttons["nav_forward"].disabled = true


func set_view_scale(zoom: float, yaw: float) -> void:
	var scale_index := 0 if zoom >= 0.78 else (1 if zoom >= 0.45 else 2)
	for i in _scale_buttons.size():
		_scale_buttons[i].set_pressed_no_signal(i == scale_index)
	_scale_label.text = "N %+.0f°" % rad_to_deg(yaw)


func remember_selection(kind: String, id: int) -> void:
	if _navigating: return
	var entry := {"kind":kind, "id":id}
	if _nav_index >= 0 and _nav[_nav_index] == entry: return
	_nav.resize(_nav_index + 1)
	_nav.append(entry)
	if _nav.size() > 32: _nav.pop_front()
	_nav_index = _nav.size() - 1
	_update_nav()


func _update_nav() -> void:
	sim_buttons["nav_back"].disabled = _nav_index <= 0
	sim_buttons["nav_forward"].disabled = _nav_index >= _nav.size() - 1


func _navigate(delta: int) -> void:
	var index := _nav_index + delta
	if index < 0 or index >= _nav.size(): return
	_nav_index = index
	_navigating = true
	var entry: Dictionary = _nav[index]
	app.select_entity(entry["kind"], entry["id"], false)
	_navigating = false
	_update_nav()


func _show_section(index: int) -> void:
	for i in _section_nodes.size(): _section_nodes[i].visible = i == index
	if index >= 0 and index < _section_tabs.tab_count:
		_section_key = _section_tabs.get_tab_title(index)
	_info_scroll.scroll_vertical = 0


func _toggle_chronicle(on: bool) -> void:
	chronicle_panel.visible = on
	sim_buttons["chronicle"].set_pressed_no_signal(on)
	if on:
		disasters_panel.hide()
		figures_panel.hide()
		_toggle_maps(false)
		_search_panel.hide()
		_legend_panel.hide()
		_fill_chronicle()
	else:
		_legend_panel.visible = not _layer_panel.visible and not chronicle_panel.visible and not figures_panel.visible and not disasters_panel.visible and not _search_panel.visible and _legend_signature.get("legend", {}).get("kind", "none") != "none"


func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.offset_left = -300
	_notice.offset_right = 300
	_notice.offset_top = 76
	_notice.visible = false
	add_child(_notice)
	var v := VBoxContainer.new()
	_notice.add_child(v)
	_notice_text = UiTheme.muted("", 13)
	_notice_text.add_theme_color_override("font_color", UiTheme.WARN)
	v.add_child(_notice_text)
	var actions := HBoxContainer.new()
	v.add_child(actions)
	_notice_recover = Button.new()
	_notice_recover.text = "Nueva sesión…"
	_notice_recover.pressed.connect(func():
		world_seed_edit.text = app.world.world_seed
		world_dialog.popup_centered(Vector2i(460, 200)))
	actions.add_child(_notice_recover)
	var close := Button.new()
	close.text = "Entendido"
	close.pressed.connect(func(): _notice.hide())
	actions.add_child(close)


func show_request_error(op: String, code: String, message: String) -> void:
	_notice_text.text = "Consulta no disponible · %s\n%s\nLa simulación continúa. Puedes seguir explorando." % [code, message]
	_notice_text.tooltip_text = op
	_notice_recover.hide()
	_notice.show()


func show_session_error(message: String) -> void:
	stop_playing()
	_notice_text.text = "Sesión interrumpida\n%s\nSe conserva la última vista. No se repetirá ningún avance incierto." % message
	_notice_recover.show()
	_notice.show()

static func fmt_era(index: int, names: Array = []) -> String:
	if index >= 0 and index < names.size() and names[index] is String and not names[index].strip_edges().is_empty():
		return str(names[index])
	if index >= 0 and index < LEGACY_ERAS.size():
		return LEGACY_ERAS[index]
	return "No disponible"


func era_name(index: int) -> String:
	var names: Array = (app.source as BridgeSource).era_names if app.source is BridgeSource else []
	return fmt_era(index, names)

func _build_fast_dialog() -> void:
	fast_dialog = ConfirmationDialog.new()
	fast_dialog.title = "Simulación rápida · años completos"
	fast_dialog.ok_button_text = "Calcular"
	fast_dialog.cancel_button_text = "Cancelar"
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 350
	# Fixed lines avoid an autowrap minimum-height feedback loop on first open:
	# the label can be measured before its container has received a width.
	var description := UiTheme.muted("Se calculan todos los años en orden.\nEl mapa se actualiza al intervalo elegido.\nPuedes pausar al terminar el año actual.", 13)
	box.add_child(description)
	box.add_child(UiTheme.muted("Años que calcular", 12))
	fast_years = SpinBox.new()
	fast_years.min_value = 1
	fast_years.max_value = 10000
	fast_years.value = 1000
	box.add_child(fast_years)
	box.add_child(UiTheme.muted("Publicar un estado visual cada…", 12))
	fast_interval = OptionButton.new()
	for years_count in [1,10,25,50,100]: fast_interval.add_item("%d años calculados" % years_count, years_count)
	fast_interval.select(3)
	box.add_child(fast_interval)
	for child: Node in box.get_children():
		if child is Label: child.autowrap_mode = TextServer.AUTOWRAP_OFF
	fast_dialog.add_child(box)
	fast_dialog.confirmed.connect(func():
		if not app.source.can_advance(): return
		_playing = true
		sim_buttons["play"].text = "Pausar"
		sim_buttons["play"].icon = AtlasIcons.get_icon("pause")
		_throughput_started = Time.get_ticks_usec()
		_throughput_initial_year = (app.source as BridgeSource).calculated_year if app.source is BridgeSource else app.current_year
		fast_forward_requested.emit(int(fast_years.value),fast_interval.get_selected_id()))
	add_child(fast_dialog)

func set_annual_progress(calculated: int, visualized: int, remaining: int) -> void:
	var seconds := (Time.get_ticks_usec() - _throughput_started) / 1000000.0
	var rate := maxf(0.0,calculated - _throughput_initial_year) / maxf(seconds,0.001)
	set_status("Rápido · calculado %s · mapa %s · quedan %d · %.1f años/s reales" % [fmt_year(calculated),fmt_year(visualized),remaining,rate])
