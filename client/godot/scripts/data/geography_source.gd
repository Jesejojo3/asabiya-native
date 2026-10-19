class_name GeographySource
extends HistorySource
## Real session from an engine snapshot. The current engine on main generates
## geography, climate, drainage and ecology but no population yet, so this
## source provides no historical frames. Panels say so explicitly.

var world: WorldData


func _init(w: WorldData) -> void:
	world = w


func kind() -> String:
	return "real"


func label() -> String:
	return "Sesión real · %s" % world.header.get("session", {}).get("stage", "mundo")


func systems() -> PackedStringArray:
	return world.available
