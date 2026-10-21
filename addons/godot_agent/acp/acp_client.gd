@tool
extends RefCounted
## JSON-RPC 2.0 sobre líneas (ACP). Correlaciona ids, despacha requests y notificaciones entrantes
## a handlers registrados y responde -32601 a lo desconocido. No conoce la UI ni el proceso: recibe
## un Callable para escribir líneas y le pasan las líneas leídas con receive_line().

signal notification_received(method: String, params: Dictionary)
## Una línea que no es JSON-RPC válido (se loguea y se ignora).
signal invalid_line(line: String, reason: String)

const AgentLog := preload("../core/agent_log.gd")

const ERR_PARSE := -32700
const ERR_INVALID_REQUEST := -32600
const ERR_METHOD_NOT_FOUND := -32601
const ERR_INVALID_PARAMS := -32602
const ERR_INTERNAL := -32603
## Error local: el request no se pudo mandar o se cortó la conexión.
const ERR_TRANSPORT := -32000

## Resultado de un request: `ok`, `result` o `error {code, message, data?}`.
class Response:
	extends RefCounted
	var ok: bool = false
	var result: Variant = null
	var error: Dictionary = {}

	static func success(value: Variant) -> Response:
		var response := Response.new()
		response.ok = true
		response.result = value
		return response

	static func failure(code: int, message: String, data: Variant = null) -> Response:
		var response := Response.new()
		response.error = {"code": code, "message": message}
		if data != null:
			response.error["data"] = data
		return response

	func error_message() -> String:
		return "%s (%s)" % [error.get("message", "error"), error.get("code", "?")]


class PendingRequest:
	extends RefCounted
	signal completed(response: Response)
	var method: String


var _send_line: Callable
var _log: AgentLog
var _next_id: int = 1
var _pending: Dictionary = {}  # id (int) -> PendingRequest
## method -> Callable(params: Dictionary) -> Variant. Para requests, el valor devuelto (o awaited)
## es el `result`; si es un Response con ok=false, se responde como error.
var _request_handlers: Dictionary = {}
## method -> Callable(params: Dictionary) -> void
var _notification_handlers: Dictionary = {}


func setup(send_line: Callable, agent_log: AgentLog = null) -> void:
	_send_line = send_line
	_log = agent_log


func set_request_handler(method: String, handler: Callable) -> void:
	_request_handlers[method] = handler


func has_request_handler(method: String) -> bool:
	return _request_handlers.has(method)


func set_notification_handler(method: String, handler: Callable) -> void:
	_notification_handlers[method] = handler


func pending_count() -> int:
	return _pending.size()


## Manda un request y espera la respuesta: `var r: Response = await client.request(...)`.
func request(method: String, params: Dictionary = {}) -> Response:
	var id := _next_id
	_next_id += 1
	var message := {"jsonrpc": "2.0", "id": id, "method": method, "params": params}
	var pending := PendingRequest.new()
	pending.method = method
	_pending[id] = pending
	if not _write(message, "→ %s #%d" % [method, id]):
		_pending.erase(id)
		return Response.failure(ERR_TRANSPORT, "No se pudo enviar '%s' al agente." % method)
	var response: Response = await pending.completed
	return response


func notify(method: String, params: Dictionary = {}) -> bool:
	return _write({"jsonrpc": "2.0", "method": method, "params": params}, "→ %s" % method)


## Cierra todos los requests pendientes con un error (el agente se cayó o se detuvo).
func fail_all_pending(message: String) -> void:
	var pending := _pending
	_pending = {}
	for id: int in pending:
		(pending[id] as PendingRequest).completed.emit(Response.failure(ERR_TRANSPORT, message))


## Procesa una línea leída del agente.
func receive_line(line: String) -> void:
	var text := line.strip_edges()
	if text.is_empty():
		return
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		_log_line(AgentLog.CH_ACP, "← línea ignorada (no es JSON-RPC): %s" % text.left(200), text)
		invalid_line.emit(text, "no es un objeto JSON")
		return
	var message: Dictionary = json.data
	var has_method := message.get("method") is String
	var id: Variant = _normalize_id(message.get("id"))

	if has_method and id != null:
		_handle_request(id, message.method, _params(message), text)
	elif has_method:
		_handle_notification(message.method, _params(message), text)
	elif id != null and (message.has("result") or message.has("error")):
		_handle_response(id, message, text)
	else:
		_log_line(AgentLog.CH_ACP, "← mensaje JSON-RPC inválido", text)
		invalid_line.emit(text, "mensaje JSON-RPC inválido")


func _handle_response(id: Variant, message: Dictionary, raw: String) -> void:
	var pending: PendingRequest = _pending.get(id)
	if pending == null:
		_log_line(AgentLog.CH_ACP, "← respuesta a un id desconocido: %s" % str(id), raw)
		return
	_pending.erase(id)
	var response: Response
	if message.has("error") and message.error is Dictionary:
		var error: Dictionary = message.error
		response = Response.failure(int(error.get("code", ERR_INTERNAL)), str(error.get("message", "")), error.get("data"))
		_log_line(AgentLog.CH_ACP, "← %s #%s error: %s" % [pending.method, str(id), response.error_message()], raw)
	else:
		response = Response.success(message.get("result"))
		_log_line(AgentLog.CH_ACP, "← %s #%s ok" % [pending.method, str(id)], raw)
	pending.completed.emit(response)


func _handle_notification(method: String, params: Dictionary, raw: String) -> void:
	_log_line(AgentLog.CH_ACP, "← %s%s" % [method, _notification_suffix(method, params)], raw)
	var handler: Callable = _notification_handlers.get(method, Callable())
	if handler.is_valid():
		handler.call(params)
	notification_received.emit(method, params)


func _handle_request(id: Variant, method: String, params: Dictionary, raw: String) -> void:
	_log_line(AgentLog.CH_ACP, "← %s #%s" % [method, str(id)], raw)
	var handler: Callable = _request_handlers.get(method, Callable())
	if not handler.is_valid():
		_respond_error(id, ERR_METHOD_NOT_FOUND, "Método no soportado: %s" % method)
		return
	var value: Variant = await handler.call(params)
	if value is Response:
		var response: Response = value
		if response.ok:
			_respond(id, response.result)
		else:
			_respond_error(id, int(response.error.get("code", ERR_INTERNAL)), str(response.error.get("message", "")))
	else:
		_respond(id, value)


func _respond(id: Variant, result: Variant) -> void:
	_write({"jsonrpc": "2.0", "id": id, "result": result}, "→ respuesta #%s" % str(id))


func _respond_error(id: Variant, code: int, message: String) -> void:
	_write({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}, "→ error #%s: %s" % [str(id), message])


func _write(message: Dictionary, summary: String) -> bool:
	var text := JSON.stringify(message)
	_log_line(AgentLog.CH_ACP, summary, text)
	if not _send_line.is_valid():
		return false
	return bool(_send_line.call(text))


func _log_line(channel: StringName, message: String, raw: String) -> void:
	if _log:
		_log.add(channel, message, raw)


## JSON parsea los números como float: los ids enteros se normalizan a int para el mapa.
static func _normalize_id(id: Variant) -> Variant:
	if id is float and is_equal_approx(id, roundf(id)):
		return int(id)
	if id is int or id is String:
		return id
	return null


static func _params(message: Dictionary) -> Dictionary:
	var params: Variant = message.get("params")
	return params if params is Dictionary else {}


static func _notification_suffix(method: String, params: Dictionary) -> String:
	if method == "session/update" and params.get("update") is Dictionary:
		return " · %s" % str(params.update.get("sessionUpdate", "?"))
	return ""
