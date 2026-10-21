@tool
extends RefCounted
## SuggestionCache (spec §16.1): LRU de resultados por hash de lo que hay alrededor del caret (texto
## del buffer, línea y columna). Guarda también "no hubo sugerencia", así borrar y volver a tipear
## no repite el pedido. Se vacía cuando cambia el índice o la configuración del proveedor.

const CompletionRequest := preload("completion_request.gd")
const CompletionResult := preload("completion_result.gd")

const DEFAULT_CAPACITY := 64

var capacity: int = DEFAULT_CAPACITY
var hits: int = 0
var misses: int = 0
## clave -> CompletionResult o null
var _entries: Dictionary = {}
## Claves de la menos a la más usada.
var _order: PackedStringArray = []


## `generation`: la del proveedor (índice, settings, historial), así un cambio fuera del texto no
## devuelve una sugerencia vieja.
static func key_for(request: CompletionRequest, generation: int = 0) -> String:
	return "%s:%d:%d:%d:%d:%d" % [request.path, request.text.hash(), request.line, request.line_prefix.length(), int(request.manual), generation]


## {found, result}: si estaba, el resultado guardado (null si se guardó que no había sugerencia), y
## lo marca como recién usado.
func lookup(key: String) -> Dictionary:
	if not _entries.has(key):
		misses += 1
		return {"found": false, "result": null}
	hits += 1
	_touch(key)
	return {"found": true, "result": _entries[key]}


func store(key: String, result: CompletionResult) -> void:
	_entries[key] = result
	_touch(key)
	while _order.size() > capacity:
		_entries.erase(_order[0])
		_order.remove_at(0)


func clear() -> void:
	_entries.clear()
	_order.clear()


func size() -> int:
	return _entries.size()


func _touch(key: String) -> void:
	var at := _order.find(key)
	if at >= 0:
		_order.remove_at(at)
	_order.append(key)
