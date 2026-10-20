class_name CommandPanel
extends PanelContainer
## Intent-only intervention editor. All values and rejection reasons come from Go.

signal command_requested(kind: String, payload: Dictionary)
signal context_requested

var armed_omen := ""
var _catalog: Dictionary = {}
var _context: Dictionary = {}
var _status: Label
var _favor: Label
var _sandbox: CheckBox
var _omen_choice: OptionButton
var _omen_info: Label
var _arm: Button
var _apply: Button
var _rules_body: VBoxContainer
var _controls: Dictionary = {}
var _pending := false

func build() -> void:
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -452
	offset_right = -18
	offset_top = 86
	offset_bottom = -85
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title := Label.new()
	title.text = "Intervenir en la historia"
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Cerrar"
	close.pressed.connect(func(): cancel_target(); hide())
	heading.add_child(close)
	_favor = Label.new()
	_favor.text = "Esperando estado del motor Go…"
	body.add_child(_favor)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)

	var omen_tab := VBoxContainer.new()
	omen_tab.name = "Presagios"
	omen_tab.add_theme_constant_override("separation", 9)
	tabs.add_child(omen_tab)
	omen_tab.add_child(_hint("Elige un presagio y después haz clic en una provincia. Go valida el favor, los requisitos y el resultado."))
	_omen_choice = OptionButton.new()
	_omen_choice.item_selected.connect(func(_idx: int): _refresh_omen())
	omen_tab.add_child(_omen_choice)
	_omen_info = _hint("")
	omen_tab.add_child(_omen_info)
	_arm = Button.new()
	_arm.text = "Elegir provincia en el mapa"
	_arm.pressed.connect(_arm_omen)
	omen_tab.add_child(_arm)

	var sandbox_tab := VBoxContainer.new()
	sandbox_tab.name = "Sandbox"
	tabs.add_child(sandbox_tab)
	sandbox_tab.add_child(_hint("Los efectos del sandbox se deciden únicamente en el motor y quedan registrados para el replay."))
	_sandbox = CheckBox.new()
	_sandbox.text = "Activar sandbox"
	_sandbox.toggled.connect(func(on: bool):
		if not _pending:
			command_requested.emit("set_sandbox", {"sandbox": on}))
	sandbox_tab.add_child(_sandbox)

	var rules_tab := VBoxContainer.new()
	rules_tab.name = "Reglas"
	tabs.add_child(rules_tab)
	rules_tab.add_child(_hint("Cambios aplicables al año completo actual. Los parámetros marcados «mundo nuevo» son de solo lectura."))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rules_tab.add_child(scroll)
	_rules_body = VBoxContainer.new()
	_rules_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rules_body)
	_apply = Button.new()
	_apply.text = "Aplicar reglas en Go"
	_apply.pressed.connect(_submit_rules)
	rules_tab.add_child(_apply)

	_status = _hint("Sin intervenciones pendientes.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	tabs.tab_changed.connect(func(_i: int): cancel_target())


func _hint(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func show_editor() -> void:
	show()
	context_requested.emit()


func configure(catalog: Dictionary) -> void:
	_catalog = catalog
	_omen_choice.clear()
	var omens: Array = catalog.get("omens", [])
	for i in range(omens.size()):
		var definition: Dictionary = omens[i]
		_omen_choice.add_item("%s · favor %s" % [str(definition.get("Name", "?")), str(definition.get("Cost", "?"))], i)
	if not omens.is_empty():
		_omen_choice.select(0)
	_refresh_omen()
	for child in _rules_body.get_children():
		child.queue_free()
	_controls.clear()
	for entry in catalog.get("parameters", []):
		if not entry is Dictionary:
			continue
		var definition: Dictionary = entry
		var key := str(definition.get("key", ""))
		if key == "":
			continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var label := Label.new()
		var locked := bool(definition.get("newWorld", false))
		label.text = "%s%s" % [str(definition.get("label", key)), " · mundo nuevo" if locked else ""]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var field := SpinBox.new()
		field.min_value = float(definition.get("min", 0.0))
		field.max_value = float(definition.get("max", 1.0))
		field.step = float(definition.get("step", 0.01))
		field.value = float(definition.get("default", field.min_value))
		field.editable = not locked
		row.add_child(field)
		_controls[key] = field
		_rules_body.add_child(row)
	set_context(_context)


func _refresh_omen() -> void:
	var omens: Array = _catalog.get("omens", [])
	var idx := _omen_choice.selected
	if idx < 0 or idx >= omens.size():
		_omen_info.text = "Catálogo de presagios no disponible."
		_arm.disabled = true
		return
	var definition: Dictionary = omens[idx]
	_omen_info.text = "%s\nRadio: %s km · Requisito: %s" % [
		str(definition.get("desc", "")), str(definition.get("KM", 0)),
		str(definition.get("Needs", "ninguno"))]
	_arm.disabled = _pending or _context.is_empty()


func _arm_omen() -> void:
	var omens: Array = _catalog.get("omens", [])
	var idx := _omen_choice.selected
	if _pending or _context.is_empty() or idx < 0 or idx >= omens.size():
		return
	armed_omen = str((omens[idx] as Dictionary).get("Key", ""))
	if armed_omen != "":
		_status.text = "Presagio preparado. Haz clic en una provincia para solicitarlo a Go."


func cancel_target() -> void:
	armed_omen = ""


func consume_target(cell: int) -> Dictionary:
	if armed_omen == "" or cell < 0:
		return {}
	var payload := {"omen": armed_omen, "cell": cell}
	cancel_target()
	return payload


func set_context(value: Dictionary) -> void:
	if value.is_empty():
		return
	_context = value.duplicate(true)
	var rules: Dictionary = _context.get("rules", {})
	var values: Dictionary = rules.get("values", {})
	_sandbox.set_pressed_no_signal(bool(rules.get("sandbox", false)))
	_favor.text = "Año %d · Favor de Go: %.1f · Secuencia %d" % [
		int(_context.get("year", 0)), float(_context.get("favor", 0.0)),
		int(_context.get("nextSequence", 0))]
	for key in _controls.keys():
		if values.has(key):
			(_controls[key] as SpinBox).value = float(values[key])
	_refresh_omen()


func set_pending(on: bool) -> void:
	_pending = on
	_sandbox.disabled = on
	_apply.disabled = on
	for field in _controls.values():
		(field as SpinBox).editable = not on and not _is_new_world_parameter(_control_key(field))
	_refresh_omen()
	if on:
		_status.text = "Validando intervención con Go…"


func _control_key(field: Variant) -> String:
	for key in _controls.keys():
		if _controls[key] == field:
			return str(key)
	return ""


func _is_new_world_parameter(key: String) -> bool:
	for entry in _catalog.get("parameters", []):
		if entry is Dictionary and str(entry.get("key", "")) == key:
			return bool(entry.get("newWorld", false))
	return false


func _submit_rules() -> void:
	if _pending or _context.is_empty():
		return
	var values: Dictionary = (_context.get("rules", {}) as Dictionary).get("values", {})
	var changed := {}
	for key in _controls.keys():
		if _is_new_world_parameter(str(key)):
			continue
		var v := (_controls[key] as SpinBox).value
		if absf(v - float(values.get(key, v))) > 0.0000001:
			changed[key] = v
	if changed.is_empty():
		_status.text = "No hay cambios respecto a las reglas confirmadas por Go."
		return
	command_requested.emit("change_rules", {"values": changed})


func show_outcome(result: Dictionary) -> void:
	var accepted := bool(result.get("accepted", false))
	if accepted:
		_status.text = "Confirmado por Go · %s · año %s" % [str(result.get("message", "Intervención aplicada")), str(result.get("year", ""))]
	else:
		_status.text = "Go rechazó la intervención: %s" % str(result.get("error", "sin detalle"))
