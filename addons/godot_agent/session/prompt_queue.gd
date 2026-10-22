@tool
extends RefCounted
## Prompts que el usuario escribió mientras el agente trabajaba. Se mandan de a uno al terminar
## cada turno con end_turn. Si el turno termina de otra forma (cancelado, error, límite) la cola se
## pausa: no se manda nada solo hasta que el usuario lo pida. Cada item guarda el contexto adjunto
## (escena, selección, captura) tal como estaba al encolarlo.

signal changed

## `[{text, blocks}]`, en orden de envío.
var items: Array[Dictionary] = []
var paused: bool = false
var pause_reason: String = ""


func add(text: String, blocks: Array = []) -> void:
	items.append({"text": text, "blocks": blocks})
	changed.emit()


func size() -> int:
	return items.size()


func is_empty() -> bool:
	return items.is_empty()


## Saca el item `index` y lo devuelve ({} si no existe).
func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var item := items[index]
	items.remove_at(index)
	if items.is_empty():
		_unpause()
	changed.emit()
	return item


## El próximo a mandar ({} si no hay o está en pausa).
func take_next() -> Dictionary:
	if paused or items.is_empty():
		return {}
	return remove_at(0)


func clear() -> void:
	if items.is_empty() and not paused:
		return
	items.clear()
	_unpause()
	changed.emit()


func pause(reason: String) -> void:
	if items.is_empty():
		return
	paused = true
	pause_reason = reason
	changed.emit()


func resume() -> void:
	if not paused:
		return
	_unpause()
	changed.emit()


func _unpause() -> void:
	paused = false
	pause_reason = ""
