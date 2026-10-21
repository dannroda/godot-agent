extends Node
## Server HTTP falso para los proveedores LLM del completado (M8c): escucha en 127.0.0.1, guarda
## cada pedido (método, ruta, headers, body JSON) y responde lo configurado por ruta, con una demora
## opcional. Sirve para probar los formatos de Ollama, llama.cpp, Codestral, OpenAI y Gemini sin
## tener ninguno instalado.

## ruta (sin query) -> {status: int, body: Variant (se serializa a JSON), delay_ms: int}
var routes: Dictionary = {}
## [{method, path, query, headers: Dictionary (claves en minúscula), body: Variant}]
var requests: Array[Dictionary] = []
var port: int = 0

var _server: TCPServer = TCPServer.new()
var _clients: Array[Dictionary] = []


func start() -> int:
	for candidate in range(18900, 18999):
		if _server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			return OK
	return ERR_CANT_CREATE


func url() -> String:
	return "http://127.0.0.1:%d" % port


func _exit_tree() -> void:
	for client: Dictionary in _clients:
		(client.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	_server.stop()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "data": PackedByteArray(), "respond_at": -1, "response": PackedByteArray()})
	for client: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		if int(client.respond_at) >= 0:
			if Time.get_ticks_msec() >= int(client.respond_at):
				peer.put_data(client.response)
				peer.disconnect_from_host()
				_clients.erase(client)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			var data: PackedByteArray = client.data
			data.append_array(chunk[1])
			client.data = data
		_try_parse(client)


func _try_parse(client: Dictionary) -> void:
	var data: PackedByteArray = client.data
	var text := data.get_string_from_utf8()
	var header_end := text.find("\r\n\r\n")
	if header_end < 0:
		return
	var head := text.left(header_end).split("\r\n")
	var headers: Dictionary = {}
	for i in range(1, head.size()):
		var colon := head[i].find(":")
		if colon > 0:
			headers[head[i].left(colon).strip_edges().to_lower()] = head[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	var head_bytes := text.left(header_end + 4).to_utf8_buffer().size()
	if data.size() < head_bytes + length:
		return
	var body_text := data.slice(head_bytes, head_bytes + length).get_string_from_utf8()
	var request_line := head[0].split(" ")
	var target := request_line[1] if request_line.size() > 1 else "/"
	var path := target.get_slice("?", 0)
	requests.append({
		"method": request_line[0], "path": path, "query": target.get_slice("?", 1) if target.contains("?") else "",
		"headers": headers, "body": JSON.parse_string(body_text) if not body_text.is_empty() else null,
	})
	var route: Dictionary = routes.get(path, {"status": 404, "body": {"error": "no route " + path}})
	var payload := JSON.stringify(route.get("body", {})).to_utf8_buffer()
	var response := ("HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [int(route.get("status", 200)), payload.size()]).to_utf8_buffer()
	response.append_array(payload)
	client.response = response
	client.respond_at = Time.get_ticks_msec() + int(route.get("delay_ms", 0))
