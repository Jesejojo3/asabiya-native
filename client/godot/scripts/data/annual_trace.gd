class_name AnnualTrace
extends RefCounted
## Single-thread-owner, bounded monotonic trace; disabled without the environment.
var _file: FileAccess
var _records := 0
func _init(component: String) -> void:
	var directory := OS.get_environment("ASABIYA_THROUGHPUT_DIR")
	if directory == "": return
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return
	_file = FileAccess.open(directory.path_join("%s-%d.jsonl" % [component, OS.get_process_id()]), FileAccess.WRITE)
	if _file != null: record("environment", 0, {"godot":Engine.get_version_info().get("string"),"os":OS.get_name(),"cpu":OS.get_processor_name()})
func begin() -> int: return Time.get_ticks_usec() if _file != null and _records < 4096 else 0
func record(stage: String, start: int, fields: Dictionary = {}) -> void:
	if _file == null or _records >= 4096: return
	var now := Time.get_ticks_usec()
	fields["stage"] = stage
	fields["elapsedUs"] = now - start if start > 0 else 0
	fields["ticksUs"] = now
	_file.store_line(JSON.stringify(fields))
	_records += 1
	if _records % 32 == 0: _file.flush()
