@tool
extends RefCounted
## SessionHistory del completado (spec §16.2d): líneas escritas y aceptadas en esta sesión del
## editor. Es la fuente con más peso por recencia, al estilo de fish: la última línea que empieza
## igual gana. Solo vive en memoria.

const LineIndex := preload("line_index.gd")

const CAPACITY := 400
## Puntaje de la coincidencia más reciente y de las siguientes.
const SCORES: PackedFloat32Array = [0.8, 0.6, 0.5]

var _lines: PackedStringArray = []


func record(line: String) -> void:
	var normalized := LineIndex.normalize(line).strip_edges(false, true)
	if normalized.length() < LineIndex.MIN_LINE or normalized.length() > LineIndex.MAX_LINE:
		return
	var existing := _lines.find(normalized)
	if existing >= 0:
		_lines.remove_at(existing)
	_lines.append(normalized)
	if _lines.size() > CAPACITY:
		_lines = _lines.slice(_lines.size() - CAPACITY)


func size() -> int:
	return _lines.size()


func clear() -> void:
	_lines.clear()


## [{text, score, source}] para `prefix` ya normalizado, la más reciente primero.
func query(prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := _lines.size() - 1
	while i >= 0 and out.size() < SCORES.size():
		var line := _lines[i]
		if line.length() > prefix.length() and line.begins_with(prefix):
			out.append({"text": line.substr(prefix.length()), "score": SCORES[out.size()], "source": "history"})
		i -= 1
	return out
