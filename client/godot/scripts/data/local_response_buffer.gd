class_name LocalResponseBuffer
extends RefCounted
## One in-flight request permits one NDJSON response. Search each new chunk
## once; never wait for a later chunk to reveal an already received delimiter.
var bytes := PackedByteArray()
var complete := false
var error := ""
var limit := 256 * 1024 * 1024

func append(chunk: PackedByteArray) -> void:
	if error != "": return
	if complete:
		error = "El motor envió datos sin una petición pendiente."
		return
	if chunk.size() > limit - bytes.size():
		error = "La respuesta del motor supera el límite de memoria del cliente."
		return
	var newline := chunk.find(10)
	if newline >= 0 and newline != chunk.size() - 1:
		error = "El motor envió más de un registro para una petición."
		return
	bytes.append_array(chunk)
	complete = newline >= 0

func take_text() -> String:
	var text := bytes.get_string_from_utf8()
	bytes.clear()
	complete = false
	return text
