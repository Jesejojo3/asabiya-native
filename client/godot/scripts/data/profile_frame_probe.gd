class_name ProfileFrameProbe
extends Node
## Created only when profiling is enabled; no gameplay or rendering work.
var profiler: PerformanceTrace

func _process(_dt: float) -> void:
	profiler.finish_process_frame()
