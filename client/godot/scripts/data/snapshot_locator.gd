class_name SnapshotLocator
extends RefCounted
## Finds or creates world snapshots. Looks next to the executable first (the
## distributed layout), then in the user data folder, then in the repository.

const EXPORTER_WIN := "asabiya-snapshot.exe"
const EXPORTER_UNIX := "asabiya-snapshot"


static func search_dirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	var exe_dir := OS.get_executable_path().get_base_dir()
	dirs.append(exe_dir.path_join("worlds"))
	dirs.append(OS.get_user_data_dir().path_join("worlds"))
	if OS.has_feature("editor") or not OS.has_feature("template"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../../build/worlds").simplify_path())
	return dirs


static func list_worlds() -> PackedStringArray:
	var out := PackedStringArray()
	for d in search_dirs():
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.get_extension() == "asw":
				out.append(d.path_join(f))
	return out


static func find_default() -> String:
	var all := list_worlds()
	for p in all:
		if p.get_file() == "Asabiya.asw":
			return p
	if not all.is_empty():
		return all[0]
	# nothing yet: try to generate the default world with the exporter
	var r := generate("Asabiya")
	return r.get("path", "")


static func exporter_path() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var names := [EXPORTER_WIN] if OS.get_name() == "Windows" else [EXPORTER_UNIX, EXPORTER_WIN]
	var dirs := [exe_dir, exe_dir.path_join("bin")]
	if not OS.has_feature("template"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../../build/bin").simplify_path())
	for d in dirs:
		for n in names:
			var p: String = d.path_join(n)
			if FileAccess.file_exists(p):
				return p
	return ""


## Runs the Go exporter synchronously (≈2 s). Returns {path} or {error}.
static func generate(seed_text: String) -> Dictionary:
	var exe := exporter_path()
	if exe == "":
		return {"error": "No se encontró %s junto al ejecutable." % EXPORTER_WIN}
	var dir := OS.get_user_data_dir().path_join("worlds")
	DirAccess.make_dir_recursive_absolute(dir)
	var safe := seed_text.validate_filename().replace(" ", "_")
	if safe == "":
		safe = "mundo"
	var out := dir.path_join(safe + ".asw")
	var output := []
	var code := OS.execute(exe, ["--seed", seed_text, "--out", out], output, true)
	if code != 0:
		return {"error": "El exportador falló (%d): %s" % [code, "".join(output)]}
	return {"path": out}
