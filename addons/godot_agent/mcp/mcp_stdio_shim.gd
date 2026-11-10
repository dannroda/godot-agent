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
		printerr("mcp_stdio_shim: GODOT_AGENT_MCP_URL or GODOT_AGENT_MCP_TOKEN is missing")
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
			var error := {"code": -32603, "message": "Editor MCP server: HTTP %d %s" % [status, body.left(200)]}
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
		var event_stream := false
		for key: String in response_headers:
			if key.to_lower() == "mcp-session-id":
				_session_id = str(response_headers[key])
			elif key.to_lower() == "content-type":
				event_stream = str(response_headers[key]).begins_with("text/event-stream")
		var data := PackedByteArray()
		var pending := PackedByteArray()
		while _client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
			_client.poll()
			var chunk := _client.read_response_body_chunk()
			if chunk.is_empty():
				OS.delay_msec(POLL_MS)
			elif event_stream:
				# Una tool larga (m11-47): cada evento (progreso y al final la respuesta) sale apenas
				# llega, y el plazo se cuenta desde el último.
				deadline = Time.get_ticks_msec() + TIMEOUT_MS
				pending.append_array(chunk)
				pending = _print_events(pending)
			else:
				data.append_array(chunk)
		if event_stream:
			_client = null  # el server cierra la conexión al terminar el stream
			return [202, ""]
		if status == 404:
			_session_id = ""  # el editor reinició el server: el cliente tiene que reinicializar
		return [status, data.get_string_from_utf8()]
	return [0, "could not connect to the editor"]


## Escribe en stdout el `data` de cada evento SSE completo de `bytes` (los separa una línea vacía;
## los comentarios no) y devuelve los bytes del evento que todavía no terminó. Se decodifica solo
## hasta el último evento completo: un chunk puede cortar un carácter UTF-8.
static func _print_events(bytes: PackedByteArray) -> PackedByteArray:
	var last := -1
	for i in range(bytes.size() - 1, 0, -1):
		if bytes[i] == 10 and (bytes[i - 1] == 10 or (bytes[i - 1] == 13 and i >= 3 and bytes[i - 2] == 10)):
			last = i
			break
	if last < 0:
		return bytes
	var text := bytes.slice(0, last + 1).get_string_from_utf8().replace("\r\n", "\n")
	for event: String in text.split("\n\n", false):
		var lines: PackedStringArray = []
		for line: String in event.split("\n"):
			if line.begins_with("data:"):
				lines.append(line.trim_prefix("data:").strip_edges(true, false))
		if not lines.is_empty():
			print("\n".join(lines))
	return bytes.slice(last + 1)


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
