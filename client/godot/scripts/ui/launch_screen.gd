class_name LaunchScreen
extends Control
## Launch, progress and failure states share a single persistent hierarchy.
signal session_requested(seed_text: String)
signal retry_requested
signal quit_requested
var message: Label
var seed_edit: LineEdit
var launch: Button
var retry: Button
var progress: ProgressBar
var stage: Label
var _elapsed := 0.0
var _working := false

func build(seed_text: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	var background := ColorRect.new()
	background.color = UiTheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 540
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	panel.add_child(body)
	var eyebrow := UiTheme.muted("ATLAS DE HISTORIA EMERGENTE", 12)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(eyebrow)
	var title := UiTheme.heading("ASABIYA", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	body.add_child(HSeparator.new())
	message = UiTheme.muted("Explora continentes, pueblos y ciudades. Observa cómo cambia el mundo, año a año.", 16)
	message.custom_minimum_size.x = 480
	body.add_child(message)
	seed_edit = LineEdit.new()
	seed_edit.text = seed_text
	seed_edit.placeholder_text = "Semilla del mundo"
	seed_edit.tooltip_text = "El motor Go genera el mundo y calcula toda la historia."
	body.add_child(seed_edit)
	launch = Button.new()
	launch.text = "Explorar un mundo nuevo"
	launch.icon = AtlasIcons.get_icon("home")
	launch.pressed.connect(func():
		var chosen := seed_edit.text.strip_edges()
		if chosen.is_empty(): chosen = "Asabiya"
		show_progress("Iniciando el motor histórico…")
		session_requested.emit(chosen))
	body.add_child(launch)
	progress = ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	progress.custom_minimum_size.y = 4
	progress.hide()
	body.add_child(progress)
	stage = UiTheme.muted("Relieve 3D · historia calculada en Go · observación sin intervención", 11)
	body.add_child(stage)
	retry = Button.new()
	retry.text = "Reiniciar con una sesión nueva"
	retry.hide()
	retry.pressed.connect(func(): retry_requested.emit())
	body.add_child(retry)
	var quit := Button.new()
	quit.text = "Salir"
	quit.flat = true
	quit.pressed.connect(func(): quit_requested.emit())
	body.add_child(quit)

func show_progress(text: String) -> void:
	_working = true
	launch.hide()
	seed_edit.hide()
	retry.hide()
	progress.show()
	message.text = text
	_elapsed = 0.0

func update_message(text: String, failed: bool) -> void:
	message.text = text
	if failed:
		_working = false
		progress.hide()
		stage.text = "No se reintentará ninguna operación histórica automáticamente."
		retry.show()

func _process(dt: float) -> void:
	if not _working: return
	_elapsed += dt
	stage.text = "Preparando mundo y publicaciones · %.0f s · no cierres esta ventana" % _elapsed
