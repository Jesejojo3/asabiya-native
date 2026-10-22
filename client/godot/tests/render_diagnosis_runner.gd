extends SceneTree
## Editor/source entry point for diagnostics/render_diagnosis.gd. Also runs an
## UNMODIFIED PR #22 checkout: pass --harness /absolute/path/render_diagnosis.gd
## after `--` (the kit does) when that tree has no diagnostics/ folder.

func _initialize() -> void:
	var raw := OS.get_cmdline_user_args()
	var path := "res://diagnostics/render_diagnosis.gd"
	var at := raw.find("--harness")
	if at >= 0 and at + 1 < raw.size(): path = raw[at + 1]
	var harness: Script = load(path)
	if harness == null:
		printerr("RENDER_DIAGNOSIS_ERROR Cannot load harness ", path)
		quit(1)
		return
	root.add_child.call_deferred(harness.new())
