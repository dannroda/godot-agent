extends "test_case.gd"
## McpServer por HTTP real en 127.0.0.1 (spec §5).

const McpServer := preload("res://addons/godot_agent/mcp/mcp_server.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const TIMEOUT_MS := 5000

var _server: McpServer


func _start() -> McpServer:
	var registry := ToolRegistry.new()
	registry.register(McpTool.create("sum", "read", "Suma", {"a": {"type": "number"}, "b": {"type": "number"}}, ["a", "b"],
		func(args: Dictionary) -> String: return str(int(args.a + args.b))))
	_server = McpServer.new()
	_server.registry = registry
	(Engine.get_main_loop() as SceneTree).root.add_child(_server)
	_server.start(0)
	return _server


func _stop() -> void:
	_server.stop()
	_server.queue_free()


## Devuelve {status, headers (minúscula), body}.
func _request(method: int, path: String, body: String, headers: PackedStringArray) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var client := HTTPClient.new()
	client.connect_to_host(McpServer.HOST, _server.port())
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		client.poll()
		await tree.process_frame
	client.request(method, path, headers, body)
	while client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		client.poll()
		await tree.process_frame
	if not client.has_response():
		return {"status": 0, "headers": {}, "body": ""}
	var data := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
		client.poll()
		data.append_array(client.read_response_body_chunk())
		await tree.process_frame
	var response_headers: Dictionary = {}
	var raw_headers := client.get_response_headers_as_dictionary()
	for key: String in raw_headers:
		response_headers[key.to_lower()] = raw_headers[key]
	var status := client.get_response_code()
	client.close()
	return {"status": status, "headers": response_headers, "body": data.get_string_from_utf8()}


func _auth(extra: PackedStringArray = []) -> PackedStringArray:
	var headers: PackedStringArray = ["Content-Type: application/json", "Authorization: Bearer " + _server.token]
	headers.append_array(extra)
	return headers


func _rpc(id: Variant, method: String, params: Dictionary = {}) -> String:
	var message := {"jsonrpc": "2.0", "method": method, "params": params}
	if id != null:
		message["id"] = id
	return JSON.stringify(message)


func test_http_errors() -> void:
	_start()
	assert_true(_server.port() > 0, "puerto aleatorio")
	assert_eq(_server.http_server_entry().url, "http://127.0.0.1:%d/mcp" % _server.port(), "url de la entrada http")
	var no_token: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(1, "ping"), ["Content-Type: application/json"])
	assert_eq(no_token.status, 401, "sin token → 401")
	var bad_token: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(1, "ping"), ["Authorization: Bearer x"])
	assert_eq(bad_token.status, 401, "token incorrecto → 401")
	var wrong_path: Dictionary = await _request(HTTPClient.METHOD_POST, "/otra", _rpc(1, "ping"), _auth())
	assert_eq(wrong_path.status, 404, "ruta → 404")
	var get_stream: Dictionary = await _request(HTTPClient.METHOD_GET, "/mcp", "", _auth())
	assert_eq(get_stream.status, 405, "GET → 405")
	var origin: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(1, "ping"), _auth(["Origin: http://evil.example"]))
	assert_eq(origin.status, 403, "Origin externo → 403")
	var local_origin: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(1, "ping"), _auth(["Origin: http://localhost:3000"]))
	assert_eq(local_origin.status, 200, "Origin local → 200")
	var bad_json: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", "{", _auth())
	assert_eq(bad_json.status, 400, "JSON inválido → 400")
	var unknown_session: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(1, "ping"), _auth(["Mcp-Session-Id: nada"]))
	assert_eq(unknown_session.status, 404, "sesión desconocida → 404")
	_stop()


func test_mcp_flow() -> void:
	_start()
	var init: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(1, "initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}), _auth())
	assert_eq(init.status, 200, "initialize → 200")
	var session_id := str(init.headers.get("mcp-session-id", ""))
	assert_false(session_id.is_empty(), "Mcp-Session-Id")
	var result: Dictionary = JSON.parse_string(init.body).result
	assert_eq(result.protocolVersion, "2025-03-26", "versión pedida")
	assert_eq(result.serverInfo.name, "godot", "serverInfo")
	var session := PackedStringArray(["Mcp-Session-Id: " + session_id])
	var notification: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(null, "notifications/initialized"), _auth(session))
	assert_eq(notification.status, 202, "notificación → 202")
	var list: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(2, "tools/list"), _auth(session))
	assert_eq(JSON.parse_string(list.body).result.tools[0].name, "sum", "tools/list")
	var call: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(3, "tools/call", {"name": "sum", "arguments": {"a": 2, "b": 3}}), _auth(session))
	var call_result: Dictionary = JSON.parse_string(call.body)
	assert_eq(call_result.id, 3.0, "id de la respuesta")
	assert_eq(call_result.result.content[0].text, "5", "tools/call")
	var unknown_tool: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(4, "tools/call", {"name": "nada"}), _auth(session))
	assert_eq(JSON.parse_string(unknown_tool.body).error.code, -32602.0, "tool desconocida → -32602")
	var unknown_method: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(5, "resources/list"), _auth(session))
	assert_eq(JSON.parse_string(unknown_method.body).error.code, -32601.0, "método desconocido → -32601")
	var old_version: Dictionary = await _request(HTTPClient.METHOD_POST, "/mcp", _rpc(6, "initialize", {"protocolVersion": "1999-01-01"}), _auth())
	assert_eq(JSON.parse_string(old_version.body).result.protocolVersion, McpServer.PROTOCOL_VERSIONS[0], "versión desconocida → la última")
	_stop()


func test_keep_alive_pipelining() -> void:
	_start()
	var peer := StreamPeerTCP.new()
	peer.connect_to_host(McpServer.HOST, _server.port())
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		peer.poll()
		await tree.process_frame
	var one := _rpc(1, "ping")
	var two := _rpc(2, "ping")
	var raw := ""
	for body: String in [one, two]:
		raw += "POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n%s" % [_server.token, body.length(), body]
	peer.put_data(raw.to_utf8_buffer())
	var received := ""
	while received.count("HTTP/1.1 200") < 2 and Time.get_ticks_msec() < deadline:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			received += (peer.get_data(available)[1] as PackedByteArray).get_string_from_utf8()
		await tree.process_frame
	assert_eq(received.count("HTTP/1.1 200"), 2, "dos respuestas en la misma conexión")
	assert_true(received.find("\"id\":1") < received.find("\"id\":2"), "en orden")
	peer.disconnect_from_host()
	_stop()
