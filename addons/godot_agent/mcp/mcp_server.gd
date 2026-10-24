@tool
extends Node
## Server MCP del addon (spec §5): HTTP/1.1 mínimo sobre TCPServer en 127.0.0.1, token Bearer,
## `POST /mcp` con JSON-RPC y respuestas JSON (Streamable HTTP sin SSE).
## La red se atiende con polling no bloqueante en `_process` (D16): cada request corre en el hilo
## principal y una conexión procesa sus requests en orden.

signal started(port: int)
signal stopped

const HttpParser := preload("http_parser.gd")
const AddonVersion := preload("../core/addon_version.gd")
const ToolRegistry := preload("tool_registry.gd")
const AgentLog := preload("../core/agent_log.gd")

const HOST := "127.0.0.1"
const ENDPOINT := "/mcp"
const SERVER_NAME := "godot"
const SERVER_TITLE := "Godot Agent Harness"
## Versiones de MCP que se aceptan; si el cliente pide otra, se responde la primera.
const PROTOCOL_VERSIONS: PackedStringArray = ["2025-06-18", "2025-03-26", "2024-11-05"]
const MAX_CONNECTIONS := 16
## Conexiones sin actividad que se cierran (s).
const IDLE_TIMEOUT_S := 300.0
const INSTRUCTIONS := "Tools of the open Godot editor. Use res:// paths and NodePaths relative to the scene root (\".\" is the root). To change open scenes use these tools; do not edit the .tscn by hand."


class McpConnection:
	extends RefCounted
	var peer: StreamPeerTCP
	var parser := HttpParser.new()
	var queue: Array = []
	var busy: bool = false
	var close_after: bool = false
	var last_activity_msec: int = 0


var registry: ToolRegistry
var agent_log: AgentLog
## Token Bearer: se genera en cada start().
var token: String = ""

var _server: TCPServer
var _port: int = 0
var _connections: Array[McpConnection] = []
var _sessions: Dictionary = {}  # Mcp-Session-Id -> {client, protocolVersion}
## Tokens de las otras sesiones del agente abiertas a la vez (m7-44): token -> id de la sesión. El
## de `token` es el de la primera (id "").
var _session_tokens: Dictionary = {}


## En _init y no en _ready: el plugin lo agrega en su _enter_tree y llama a start() antes de que
## corra el _ready del hijo (que llega recién con el ready del plugin).
func _init() -> void:
	set_process(false)


## Escucha en 127.0.0.1:`port` (0 = aleatorio). Devuelve OK o el error de listen.
func start(port: int = 0) -> Error:
	stop()
	token = _random_hex(24)
	_server = TCPServer.new()
	var error := _server.listen(port, HOST)
	if error != OK:
		_log("could not listen on %s:%d: %s" % [HOST, port, error_string(error)])
		_server = null
		return error
	_port = _server.get_local_port()
	set_process(true)
	_log("MCP server listening on %s" % url())
	started.emit(_port)
	return OK


func stop() -> void:
	for connection: McpConnection in _connections:
		connection.peer.disconnect_from_host()
	_connections.clear()
	_sessions.clear()
	if _server:
		_server.stop()
		_server = null
		_log("MCP server stopped")
		stopped.emit()
	_port = 0
	set_process(false)


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func port() -> int:
	return _port


func url() -> String:
	return "http://%s:%d%s" % [HOST, _port, ENDPOINT]


## Entrada `mcpServers` de tipo http para session/new (spec §4.3), con el token de la sesión.
func http_server_entry(session_token: String = "") -> Dictionary:
	return {
		"type": "http",
		"name": SERVER_NAME,
		"url": url(),
		"headers": [{"name": "Authorization", "value": "Bearer " + (session_token if not session_token.is_empty() else token)}],
	}


## Token propio de otra sesión del agente: las tools que llama con él saben de qué sesión vienen.
func session_token(session: String) -> String:
	for existing: String in _session_tokens:
		if _session_tokens[existing] == session:
			return existing
	var new_token := _random_hex(24)
	_session_tokens[new_token] = session
	return new_token


func remove_session_token(session: String) -> void:
	for existing: String in _session_tokens.keys():
		if _session_tokens[existing] == session:
			_session_tokens.erase(existing)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _connections.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
			continue
		var connection := McpConnection.new()
		connection.peer = peer
		connection.last_activity_msec = Time.get_ticks_msec()
		_connections.append(connection)
	for connection: McpConnection in _connections.duplicate():
		_poll(connection)


func _poll(connection: McpConnection) -> void:
	var peer := connection.peer
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		_connections.erase(connection)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := peer.get_available_bytes()
	if available > 0:
		connection.last_activity_msec = Time.get_ticks_msec()
		var data: Array = peer.get_partial_data(available)
		if data[0] == OK:
			connection.queue.append_array(connection.parser.feed(data[1]))
		if connection.parser.error_status != 0:
			_send(connection, connection.parser.error_status, _error_body(-32600, connection.parser.error_message), {})
			_close(connection)
			return
	if not connection.busy and not connection.queue.is_empty():
		_serve(connection)
	elif not connection.busy and Time.get_ticks_msec() - connection.last_activity_msec > IDLE_TIMEOUT_S * 1000.0:
		_close(connection)


## Atiende los requests en cola de una conexión, uno por vez (pueden esperar un permiso).
func _serve(connection: McpConnection) -> void:
	connection.busy = true
	while not connection.queue.is_empty() and _connections.has(connection):
		var request: HttpParser.ParsedRequest = connection.queue.pop_front()
		var reply: Dictionary = await _handle(request)
		if not _connections.has(connection):
			break
		_send(connection, reply.status, reply.get("body", PackedByteArray()), reply.get("headers", {}))
		if not request.keep_alive() or reply.get("close", false):
			_close(connection)
			break
	connection.busy = false


func _send(connection: McpConnection, status: int, body: PackedByteArray, headers: Dictionary) -> void:
	if not body.is_empty() and not headers.has("Content-Type"):
		headers["Content-Type"] = "application/json"
	connection.peer.put_data(HttpParser.response(status, body, headers))


func _close(connection: McpConnection) -> void:
	connection.peer.disconnect_from_host()
	_connections.erase(connection)


# --- HTTP → JSON-RPC -----------------------------------------------------------------------------

## Devuelve `{status, body?, headers?, close?}`.
func _handle(request: HttpParser.ParsedRequest) -> Dictionary:
	var path := request.path.split("?")[0]
	if not _origin_allowed(request.header("origin")):
		return {"status": 403, "body": _error_body(-32600, "Origin not allowed"), "close": true}
	if path != ENDPOINT:
		return {"status": 404, "body": _error_body(-32600, "The only path is %s" % ENDPOINT)}
	var caller: Variant = _caller(request.header("authorization"))
	if caller == null:
		_log("request rejected: invalid token")
		return {"status": 401, "headers": {"WWW-Authenticate": "Bearer"}, "body": _error_body(-32600, "Invalid token")}
	if request.method != "POST":
		# Sin SSE en v1: GET (stream) y DELETE (fin de sesión) no se soportan.
		return {"status": 405, "headers": {"Allow": "POST"}}
	var session_id := request.header("mcp-session-id")
	if not session_id.is_empty() and not _sessions.has(session_id):
		return {"status": 404, "body": _error_body(-32600, "Unknown MCP session: initialize again")}
	var json := JSON.new()
	if json.parse(request.body_text()) != OK:
		return {"status": 400, "body": _error_body(-32700, "Invalid JSON: %s" % json.get_error_message())}
	var message: Variant = json.data
	var headers: Dictionary = {}
	if message is Array:
		var replies: Array = []
		for item: Variant in message:
			var reply: Variant = await _dispatch(item, headers, session_id, caller)
			if reply != null:
				replies.append(reply)
		if replies.is_empty():
			return {"status": 202, "headers": headers}
		return {"status": 200, "headers": headers, "body": JSON.stringify(replies).to_utf8_buffer()}
	var single: Variant = await _dispatch(message, headers, session_id, caller)
	if single == null:
		return {"status": 202, "headers": headers}
	return {"status": 200, "headers": headers, "body": JSON.stringify(single).to_utf8_buffer()}


## Un mensaje JSON-RPC → respuesta (Dictionary) o null si era notificación o respuesta.
func _dispatch(message: Variant, headers: Dictionary, session_id: String, caller: String = "") -> Variant:
	if not message is Dictionary or message.get("jsonrpc") != "2.0":
		return _rpc_error(null, -32600, "Invalid JSON-RPC request")
	var id: Variant = message.get("id")
	var method: Variant = message.get("method")
	if not method is String:
		return null  # respuesta a algo que no pedimos: se ignora
	var params: Dictionary = message.get("params", {}) if message.get("params") is Dictionary else {}
	if id is float and is_equal_approx(id, roundf(id)):
		id = int(id)
	if not message.has("id"):
		_log("← %s" % method)
		return null
	match method:
		"initialize":
			var requested := str(params.get("protocolVersion", ""))
			var version := requested if requested in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0]
			var new_id := session_id if not session_id.is_empty() else _random_hex(16)
			var client: Dictionary = params.get("clientInfo", {}) if params.get("clientInfo") is Dictionary else {}
			_sessions[new_id] = {"client": client, "protocolVersion": version}
			headers["Mcp-Session-Id"] = new_id
			_log("initialize from %s %s (MCP %s)" % [client.get("name", "?"), client.get("version", ""), version])
			return _rpc_result(id, {
				"protocolVersion": version,
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": SERVER_NAME, "title": SERVER_TITLE, "version": AddonVersion.version()},
				"instructions": INSTRUCTIONS,
			})
		"ping":
			return _rpc_result(id, {})
		"tools/list":
			return _rpc_result(id, {"tools": registry.list() if registry else []})
		"tools/call":
			if registry == null:
				return _rpc_error(id, -32603, "No tool registry")
			var tool_name: Variant = params.get("name")
			if not tool_name is String or not registry.has_tool(tool_name):
				return _rpc_error(id, -32602, "Unknown tool: %s" % tool_name)
			var result: Variant = await registry.call_tool(tool_name, params.get("arguments", {}), caller)
			if not result is Dictionary or not result.get("content") is Array:
				# call_tool se cortó por un error de script: igual se responde.
				result = {"content": [{"type": "text", "text": "Internal harness error while running %s. Check the editor's Output panel." % tool_name}], "isError": true}
			return _rpc_result(id, result)
	return _rpc_error(id, -32601, "Unsupported method: %s" % method)


func _rpc_result(id: Variant, result: Variant) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


func _rpc_error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


func _error_body(code: int, message: String) -> PackedByteArray:
	return JSON.stringify(_rpc_error(null, code, message)).to_utf8_buffer()


## Protección contra DNS rebinding: sin Origin (clientes no navegador) o con origen local.
static func _origin_allowed(origin: String) -> bool:
	if origin.is_empty() or origin == "null":
		return true
	var host := origin.get_slice("://", 1).get_slice("/", 0)
	if host.begins_with("["):
		host = host.get_slice("]", 0) + "]"
	else:
		host = host.get_slice(":", 0)
	return host in ["127.0.0.1", "localhost", "[::1]"]


## La sesión del header `Authorization: Bearer <token>` ("" la primera), o null si no es válido.
func _caller(header: String) -> Variant:
	if token.is_empty() or not header.begins_with("Bearer "):
		return null
	var given := header.substr(7).strip_edges()
	if _same(given, token):
		return ""
	for existing: String in _session_tokens:
		if _same(given, existing):
			return _session_tokens[existing]
	return null


## Comparación en tiempo constante.
static func _same(given: String, expected_text: String) -> bool:
	var a := given.to_utf8_buffer()
	var expected := expected_text.to_utf8_buffer()
	if a.size() != expected.size():
		return false
	var diff := 0
	for i in expected.size():
		diff |= a[i] ^ expected[i]
	return diff == 0


static func _random_hex(byte_count: int) -> String:
	return Crypto.new().generate_random_bytes(byte_count).hex_encode()


func _log(message: String) -> void:
	if agent_log:
		agent_log.add(AgentLog.CH_MCP, message)
