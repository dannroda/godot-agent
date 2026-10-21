extends SceneTree
## Shim stdio → HTTP para agentes que no soportan MCP por HTTP (spec §4.3). Lee mensajes
## JSON-RPC por stdin (uno por línea), los reenvía por POST al server MCP del editor y escribe las
## respuestas en stdout. URL y token llegan por env (GODOT_AGENT_MCP_URL, GODOT_AGENT_MCP_TOKEN).
## Corre en un proyecto vacío propio (ver StdioShimInstaller): no carga nada del proyecto del
## usuario ni del addon.

const STDIN_BUFFER := 1 << 20
const TIMEOUT_MS := 600000  # una tool puede esperar un permiso del usuario
const POLL_MS := 5

var _thread: Thread
var _done: bool = false
var _host: String = ""
var _port: int = 0
var _path: String = "/mcp"
var _token: String = ""
var _session_id: String = ""
var _client: HTTPClient


func _initialize() -> void:
	var url := OS.get_environment("GODOT_AGENT_MCP_URL")
	_token = OS.get_environment("GODOT_AGENT_MCP_TOKEN")
	var without_scheme := url.trim_prefix("http://")
	var host_port := without_scheme.get_slice("/", 0)
	_host = host_port.get_slice(":", 0)
	_port = int(host_port.get_slice(":", 1))
	_path = "/" + without_scheme.get_slice("/", 1) if without_scheme.contains("/") else "/mcp"
	if _host.is_empty() or _port <= 0 or _token.is_empty():
		printerr("mcp_stdio_shim: faltan GODOT_AGENT_MCP_URL o GODOT_AGENT_MCP_TOKEN")
		quit(2)
		return
	_thread = Thread.new()
	_thread.start(_pump)


func _process(_delta: float) -> bool:
	if _done and _thread:
		_thread.wait_to_finish()
		_thread = null
	return _done


## Thread: stdin → POST → stdout, en orden.
func _pump() -> void:
	while true:
		var line := OS.read_string_from_stdin(STDIN_BUFFER).strip_edges()
		if line.is_empty():
			# El cliente nunca manda líneas vacías: vacío es EOF.
			_done = true
			return
		var message: Variant = JSON.parse_string(line)
		var reply := _post(line)
		var status: int = reply[0]
		var body: String = reply[1]
		if status == 200 and not body.is_empty():
			print(body)
		elif status != 202 and message is Dictionary and message.has("id"):
			var error := {"code": -32603, "message": "Server MCP del editor: HTTP %d %s" % [status, body.left(200)]}
			print(JSON.stringify({"jsonrpc": "2.0", "id": message.id, "error": error}))


## Devuelve [status, body]. status 0 si no se pudo conectar.
func _post(body: String) -> Array:
	for attempt in 2:
		if not _ensure_connected():
			continue
		var headers: PackedStringArray = [
			"Content-Type: application/json",
			"Accept: application/json, text/event-stream",
			"Authorization: Bearer " + _token,
		]
		if not _session_id.is_empty():
			headers.append("Mcp-Session-Id: " + _session_id)
		if _client.request(HTTPClient.METHOD_POST, _path, headers, body) != OK:
			_client = null
			continue
		var deadline := Time.get_ticks_msec() + TIMEOUT_MS
		while _client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
			_client.poll()
			OS.delay_msec(POLL_MS)
		if not _client.has_response():
			_client = null
			continue
		var status := _client.get_response_code()
		var response_headers := _client.get_response_headers_as_dictionary()
		for key: String in response_headers:
			if key.to_lower() == "mcp-session-id":
				_session_id = str(response_headers[key])
		var data := PackedByteArray()
		while _client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
			_client.poll()
			var chunk := _client.read_response_body_chunk()
			if chunk.is_empty():
				OS.delay_msec(POLL_MS)
			else:
				data.append_array(chunk)
		if status == 404:
			_session_id = ""  # el editor reinició el server: el cliente tiene que reinicializar
		return [status, data.get_string_from_utf8()]
	return [0, "no se pudo conectar con el editor"]


func _ensure_connected() -> bool:
	if _client and _client.get_status() == HTTPClient.STATUS_CONNECTED:
		return true
	_client = HTTPClient.new()
	if _client.connect_to_host(_host, _port) != OK:
		_client = null
		return false
	var deadline := Time.get_ticks_msec() + 5000
	while _client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		_client.poll()
		OS.delay_msec(POLL_MS)
	if _client.get_status() != HTTPClient.STATUS_CONNECTED:
		_client = null
		return false
	return true
