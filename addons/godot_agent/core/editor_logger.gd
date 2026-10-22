@tool
extends Logger
## Logger del editor para ErrorCollector (OS.add_logger). Godot lo llama desde cualquier hilo:
## guarda los errores en una cola con mutex y ErrorCollector la vacía en el hilo principal.

const MAX_PENDING := 1000

var _mutex := Mutex.new()
var _pending: Array = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	if _pending.size() < MAX_PENDING:
		_pending.append([function, file, line, code, rationale, error_type])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## `[function, file, line, code, rationale, error_type]` desde la última vez.
func drain() -> Array:
	_mutex.lock()
	var result := _pending
	_pending = []
	_mutex.unlock()
	return result
