extends "test_case.gd"
## AcpClient: framing de líneas, correlación de ids, requests entrantes y errores.

const AcpClient := preload("res://addons/godot_agent/acp/acp_client.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

var _sent: Array[Dictionary] = []


func _capture(line: String) -> bool:
	_sent.append(JSON.parse_string(line))
	return true


func _make_client(log: AgentLog = null) -> AcpClient:
	_sent.clear()
	var client := AcpClient.new()
	client.setup(_capture, log)
	return client


func test_request_ids_correlate_out_of_order() -> void:
	var client := _make_client()
	var results: Dictionary = {}
	var run := func(method: String) -> void:
		var response: AcpClient.AcpResponse = await client.request(method, {})
		results[method] = response
	run.call("a")
	run.call("b")
	assert_eq(_sent.size(), 2, "dos requests enviados")
	assert_eq(int(_sent[0].id), 1, "primer id")
	assert_eq(int(_sent[1].id), 2, "segundo id")
	assert_eq(_sent[0].jsonrpc, "2.0", "jsonrpc")
	# Respuestas en orden inverso, con ids que el JSON entrega como float.
	client.receive_line('{"jsonrpc":"2.0","id":2,"result":{"x":"b"}}')
	client.receive_line('{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"malo"}}')
	assert_true(results.b.ok, "b ok")
	assert_eq(results.b.result.x, "b", "resultado de b")
	assert_false(results.a.ok, "a falla")
	assert_eq(int(results.a.error.code), -32602, "código de error de a")
	assert_eq(client.pending_count(), 0, "sin pendientes")


func test_framing_ignores_blank_and_invalid_lines() -> void:
	var log := AgentLog.new()
	var client := _make_client(log)
	var invalid: Array[String] = []
	client.invalid_line.connect(func(line: String, _reason: String) -> void: invalid.append(line))
	client.receive_line("")
	client.receive_line("   \r")
	client.receive_line("Godot Engine v4.8 - banner")
	client.receive_line("[1,2,3]")
	client.receive_line('{"jsonrpc":"2.0"}')
	assert_eq(invalid.size(), 3, "tres líneas inválidas reportadas")
	assert_eq(log.entries().size(), 3, "las tres quedan en el log")


func test_unknown_request_gets_method_not_found() -> void:
	var client := _make_client()
	client.receive_line('{"jsonrpc":"2.0","id":7,"method":"terminal/create","params":{}}')
	assert_eq(_sent.size(), 1, "una respuesta")
	assert_eq(int(_sent[0].id), 7, "mismo id")
	assert_eq(int(_sent[0].error.code), AcpClient.ERR_METHOD_NOT_FOUND, "-32601")


func test_request_handler_result_and_async() -> void:
	var client := _make_client()
	client.set_request_handler("fs/read_text_file", func(params: Dictionary) -> Variant:
		return {"content": "hola " + str(params.path)}
	)
	client.set_request_handler("slow", func(_params: Dictionary) -> Variant:
		await Engine.get_main_loop().process_frame
		return AcpClient.AcpResponse.failure(-32002, "no existe")
	)
	client.receive_line('{"jsonrpc":"2.0","id":"abc","method":"fs/read_text_file","params":{"path":"x.gd"}}')
	assert_eq(_sent[0].id, "abc", "id string conservado")
	assert_eq(_sent[0].result.content, "hola x.gd", "resultado del handler")
	client.receive_line('{"jsonrpc":"2.0","id":9,"method":"slow","params":{}}')
	assert_eq(_sent.size(), 1, "el handler async todavía no respondió")
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	assert_eq(_sent.size(), 2, "respondió después de un frame")
	assert_eq(int(_sent[1].error.code), -32002, "error del handler")


func test_notifications_dispatch() -> void:
	var client := _make_client()
	var seen: Array = []
	client.set_notification_handler("session/update", func(params: Dictionary) -> void: seen.append(params))
	client.receive_line('{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"plan"}}}')
	client.receive_line('{"jsonrpc":"2.0","method":"_auth/status_update","params":{}}')
	assert_eq(seen.size(), 1, "solo session/update llega al handler")
	assert_eq(_sent.size(), 0, "las notificaciones no se responden")


func test_fail_all_pending() -> void:
	var client := _make_client()
	var results: Array = []
	var run := func() -> void:
		var response: AcpClient.AcpResponse = await client.request("session/prompt", {})
		results.append(response)
	run.call()
	client.fail_all_pending("se cayó")
	assert_eq(results.size(), 1, "el request terminó")
	assert_eq(int(results[0].error.code), AcpClient.ERR_TRANSPORT, "error de transporte")
	assert_eq(client.pending_count(), 0, "sin pendientes")


func test_send_failure_returns_error() -> void:
	var client := AcpClient.new()
	client.setup(func(_line: String) -> bool: return false)
	var response: AcpClient.AcpResponse = await client.request("initialize", {})
	assert_false(response.ok, "falla sin transporte")
	assert_eq(client.pending_count(), 0, "no queda pendiente")
