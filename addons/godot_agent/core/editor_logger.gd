@tool
extends Logger
## Logger del editor para ErrorCollector (OS.add_logger). Godot lo llama desde cualquier hilo:
## guarda los errores, y lo que se imprime (m11-72, para get_output), en colas con mutex que
## ErrorCollector vacía en el hilo principal.

const MAX_PENDING := 1000

var _mutex := Mutex.new()
var _pending: Array = []
var _messages: Array = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	if _pending.size() < MAX_PENDING:
		_pending.append([function, file, line, code, rationale, error_type])
	_mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	_mutex.lock()
	if _messages.size() < MAX_PENDING:
		_messages.append([message, error])
	_mutex.unlock()


## `[message, error]` impresos desde la última vez (print, print_rich, printerr de editor y plugins).
func drain_messages() -> Array:
	_mutex.lock()
	var result := _messages
	_messages = []
	_mutex.unlock()
	return result


## `[function, file, line, code, rationale, error_type]` desde la última vez.
func drain() -> Array:
	_mutex.lock()
	var result := _pending
	_pending = []
	_mutex.unlock()
	return result
