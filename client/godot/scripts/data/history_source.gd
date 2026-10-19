class_name HistorySource
extends RefCounted
## Abstract provider of historical frames. Implementations:
##   GeographySource — engine snapshot with no history yet (current main)
##   BridgeSource    — live Go engine through the local bridge (contract
##                     proposed in docs/client/API_REQUESTS.md)
## History comes exclusively from the Go engine: the client never generates
## states, peoples, settlements or events. Renderers only consume HistoryFrame
## objects; they never call the engine.

signal frames_changed
signal status_changed(text: String)

## "real" (snapshot) or "bridge" (live engine)
func kind() -> String:
	return "real"


func label() -> String:
	return "Sesión real"


## Systems available from this source (subset of: history, states, peoples,
## religions, population, technology, economy, settlements, wars, routes,
## events, carrying).
func systems() -> PackedStringArray:
	return PackedStringArray()


func has_system(name: String) -> bool:
	return systems().has(name)


func years() -> PackedInt32Array:
	return PackedInt32Array()


func frame(_year: int) -> HistoryFrame:
	return null


## Nearest available frame at or before `year`.
func frame_at(year: int) -> HistoryFrame:
	var ys := years()
	if ys.is_empty():
		return null
	var best := ys[0]
	for y in ys:
		if y <= year:
			best = y
	return frame(best)


func can_advance() -> bool:
	return false


func advance(_years: int) -> void:
	pass


func close() -> void:
	pass
