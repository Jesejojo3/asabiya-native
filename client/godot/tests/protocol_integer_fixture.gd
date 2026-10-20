extends SceneTree
## Serialization-only contract fixture; does not instantiate the game or renderer.
## Run with --headless --path client/godot --script res://tests/protocol_integer_fixture.gd
## -- --output ABSOLUTE_PATH/internal/interop/testdata/godot-integer-requests.json

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--output":
		push_error("Expected --output PATH")
		quit(1)
		return
	# Like world_config loaded from asabiya.json, JSON.parse_string returns
	# float-valued JSON numbers. No pre-serialization int casts hide the issue.
	var fixtures: Variant = JSON.parse_string('''[
		{"schema":"asabiya/local-v1","id":"world","session":0,"op":"create_world","payload":{"world":{"seed":"Asabiya","width":400,"height":200,"detail":4,"landFraction":0.33}}},
		{"schema":"asabiya/local-v1","id":"command","session":2,"op":"apply_command","payload":{"schema":"asabiya/command-v1","profile":"native","sequence":1,"targetYear":-9000,"kind":"change_rules","cell":12,"values":{"volcano":0.125}}},
		{"schema":"asabiya/local-v1","id":"province","session":2,"op":"get_province","payload":{"id":12}},
		{"schema":"asabiya/local-v1","id":"layer","session":2,"op":"get_historical_layer","payload":{"year":-9000}},
		{"schema":"asabiya/local-v1","id":"entity","session":2,"op":"get_entity","payload":{"kind":"polity","id":12}},
		{"schema":"asabiya/local-v1","id":"source","session":0,"op":"create_world","payload":{"source":{"kind":"earth","climate":{"dry":0.038},"assets":[{"role":"earth-html","path":"resources/legacy-v0.6.html","bytes":1553001}]}}}
	]''')
	var serialized := JSON.stringify(fixtures, "\t")
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Array or parsed.size() != 6 or parsed[0]["payload"]["world"]["detail"] != 4.0:
		push_error("Godot JSON round trip failed")
		quit(1)
		return
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write protocol fixture")
		quit(1)
		return
	file.store_string(serialized + "\n")
	file.close()
	print("Godot serialization contract: 6 fixtures written; round trip passed")
	quit(0)
