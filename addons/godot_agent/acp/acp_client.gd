@tool
extends RefCounted
## JSON-RPC 2.0 sobre líneas (ACP). Correlaciona ids, despacha requests y notificaciones entrantes
## a handlers registrados y responde -32601 a lo desconocido. No conoce la UI ni el proceso: recibe
## un Callable para escribir líneas y le pasan las líneas leídas con receive_line().

signal notification_received(method: String, params: Dictionary)
## Una línea que no es JSON-RPC válido (se loguea y se ignora).
signal invalid_line(line: String, reason: String)
## El agente retiró un request que nos hizo (`$/cancel_request`): con Remote Control, un permiso
## contestado desde el celular (m7-21).
signal incoming_cancelled(id: Variant)

const AgentLog := preload("../core/agent_log.gd")

const ERR_PARSE := -32700
const ERR_INVALID_REQUEST := -32600
const ERR_METHOD_NOT_FOUND := -32601
const ERR_INVALID_PARAMS := -32602
const ERR_INTERNAL := -32603
## Request cancelado con `$/cancel_request` (ACP / LSP).
const ERR_REQUEST_CANCELLED := -32800
## Error local: el request no se pudo mandar o se cortó la conexión.
const ERR_TRANSPORT := -32000

## Resultado de un request: `ok`, `result` o `error {code, message, data?}`.
class AcpResponse:
	extends RefCounted
	var ok: bool = false
	var result: Variant = null
	var error: Dictionary = {}

	static func success(value: Variant) -> AcpResponse:
		var response := AcpResponse.new()
		response.ok = true
		response.result = value
		return response

	static func failure(code: int, message: String, data: Variant = null) -> AcpResponse:
		var response := AcpResponse.new()
		response.error = {"code": code, "message": message}
		if data != null:
			response.error["data"] = data
		return response

	## Con `data.details` (o `data` texto), el detalle va al final: «Internal error» solo no dice nada.
	func error_message() -> String:
		var text := "%s (%s)" % [error.get("message", "error"), error.get("code", "?")]
		var data: Variant = error.get("data")
		var details: Variant = data.get("details") if data is Dictionary else data
		return text + ": " + str(details) if details is String and not details.is_empty() else text


class PendingRequest:
	extends RefCounted
	signal completed(response: AcpResponse)
	var method: String


var _send_line: Callable
var _log: AgentLog
var _next_id: int = 1
var _pending: Dictionary = {}  # id (int) -> PendingRequest
var _cancelled_outgoing: Dictionary = {}  # id (int) -> true
var _incoming: Dictionary = {}  # id (Variant) -> true (requests entrantes en vuelo)
var _cancelled_incoming: Dictionary = {}  # id (Variant) -> true
## Id del último request saliente enviado con `request()`, disponible antes de que termine su await.
var last_request_id: int = 0
## method -> Callable(params: Dictionary) -> Variant. Para requests, el valor devuelto (o awaited)
## es el `result`; si es un Response con ok=false, se responde como error.
var _request_handlers: Dictionary = {}
## method -> Callable(params: Dictionary) -> void
var _notification_handlers: Dictionary = {}
## Id del request entrante cuyo handler se está llamando: el handler lo lee al empezar, antes del
## primer await, para asociarlo con lo que crea.
var handling_id: Variant = null


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


func next_request_id() -> int:
	return _next_id


## Manda un request y espera la respuesta: `var r: Response = await client.request(...)`.
func request(method: String, params: Dictionary = {}) -> AcpResponse:
	var id := _next_id
	_next_id += 1
	last_request_id = id
	var message := {"jsonrpc": "2.0", "id": id, "method": method, "params": params}
	var pending := PendingRequest.new()
	pending.method = method
	_pending[id] = pending
	if not _write(message, "→ %s #%d" % [method, id]):
		_pending.erase(id)
		return AcpResponse.failure(ERR_TRANSPORT, "Could not send '%s' to the agent." % method)
	var response: AcpResponse = await pending.completed
	return response


## Cancela un request saliente en vuelo mandando `$/cancel_request` al agente y despertando su await
## con `ERR_REQUEST_CANCELLED` (-32800). Si la respuesta llega igual más tarde, se ignora.
func cancel_request(id: int) -> bool:
	var pending: PendingRequest = _pending.get(id)
	if pending == null:
		return false
	_pending.erase(id)
	_cancelled_outgoing[id] = true
	notify("$/cancel_request", {"requestId": id})
	pending.completed.emit(AcpResponse.failure(ERR_REQUEST_CANCELLED, "Request cancelled."))
	return true


## true si el agente mandó `$/cancel_request` para el request entrante `id`.
func is_incoming_cancelled(id: Variant) -> bool:
	return _cancelled_incoming.has(id)


func notify(method: String, params: Dictionary = {}) -> bool:
	return _write({"jsonrpc": "2.0", "method": method, "params": params}, "→ %s" % method)


## Cierra todos los requests pendientes con un error (el agente se cayó o se detuvo).
func fail_all_pending(message: String) -> void:
	var pending := _pending
	_pending = {}
	_cancelled_outgoing.clear()
	_incoming.clear()
	_cancelled_incoming.clear()
	for id: int in pending:
		(pending[id] as PendingRequest).completed.emit(AcpResponse.failure(ERR_TRANSPORT, message))


## Procesa una línea leída del agente.
func receive_line(line: String) -> void:
	var text := line.strip_edges()
	if text.is_empty():
		return
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		_log_line(AgentLog.CH_ACP, "← line ignored (not JSON-RPC): %s" % text.left(200), text)
		invalid_line.emit(text, "not a JSON object")
		return
	var message: Dictionary = json.data
	var has_method := message.get("method") is String
	var id: Variant = _normalize_id(message.get("id"))

	if has_method and id != null:
		_handle_request(id, message.method, _params(message), text)
		# Solo vale mientras el handler corre sin suspenderse: después, otro código (una tool MCP,
		# otro request) lo leería creyendo que es suyo.
		handling_id = null
	elif has_method:
		_handle_notification(message.method, _params(message), text)
	elif id != null and (message.has("result") or message.has("error")):
		_handle_response(id, message, text)
	else:
		_log_line(AgentLog.CH_ACP, "← invalid JSON-RPC message", text)
		invalid_line.emit(text, "invalid JSON-RPC message")


func _handle_response(id: Variant, message: Dictionary, raw: String) -> void:
	if _cancelled_outgoing.erase(id):
		_log_line(AgentLog.CH_ACP, "← response to cancelled request #%s ignored" % str(id), raw)
		return
	var pending: PendingRequest = _pending.get(id)
	if pending == null:
		_log_line(AgentLog.CH_ACP, "← response to an unknown id: %s" % str(id), raw)
		return
	_pending.erase(id)
	var response: AcpResponse
	if message.has("error") and message.error is Dictionary:
		var error: Dictionary = message.error
		response = AcpResponse.failure(int(error.get("code", ERR_INTERNAL)), str(error.get("message", "")), error.get("data"))
		_log_line(AgentLog.CH_ACP, "← %s #%s error: %s" % [pending.method, str(id), response.error_message()], raw)
	else:
		response = AcpResponse.success(message.get("result"))
		_log_line(AgentLog.CH_ACP, "← %s #%s ok" % [pending.method, str(id)], raw)
	pending.completed.emit(response)


func _handle_notification(method: String, params: Dictionary, raw: String) -> void:
	_log_line(AgentLog.CH_ACP, "← %s%s" % [method, _notification_suffix(method, params)], raw)
	if method == "$/cancel_request":
		var req_id: Variant = _normalize_id(params.get("requestId"))
		if req_id != null and _incoming.has(req_id):
			_cancelled_incoming[req_id] = true
		incoming_cancelled.emit(req_id)
		# La marca queda hasta que el handler termina (_handle_request la borra): lo que sigue
		# después de un await la consulta con is_incoming_cancelled().
		if req_id != null and _incoming.erase(req_id):
			_respond_error(req_id, ERR_REQUEST_CANCELLED, "Request cancelled.")
	var handler: Callable = _notification_handlers.get(method, Callable())
	if handler.is_valid():
		handler.call(params)
	notification_received.emit(method, params)


func _handle_request(id: Variant, method: String, params: Dictionary, raw: String) -> void:
	_log_line(AgentLog.CH_ACP, "← %s #%s" % [method, str(id)], raw)
	var handler: Callable = _request_handlers.get(method, Callable())
	if not handler.is_valid():
		_respond_error(id, ERR_METHOD_NOT_FOUND, "Method not supported: %s" % method)
		return
	_incoming[id] = true
	handling_id = id
	var value: Variant = await handler.call(params)
	var was_cancelled := _cancelled_incoming.erase(id)
	if not _incoming.erase(id):
		return
	if value is AcpResponse:
		var response: AcpResponse = value
		if response.ok:
			_respond(id, response.result)
		elif was_cancelled:
			_respond_error(id, ERR_REQUEST_CANCELLED, "Request cancelled.")
		else:
			_respond_error(id, int(response.error.get("code", ERR_INTERNAL)), str(response.error.get("message", "")))
	elif was_cancelled and value == null:
		_respond_error(id, ERR_REQUEST_CANCELLED, "Request cancelled.")
	else:
		_respond(id, value)


func _respond(id: Variant, result: Variant) -> void:
	_write({"jsonrpc": "2.0", "id": id, "result": result}, "→ response #%s" % str(id))


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
