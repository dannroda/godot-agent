extends "test_case.gd"
## Los secretos registrados en el Agent Log (el token del server MCP, las keys del entorno) no salen
## por ningún camino (m13-25): lo que manda el agente entra redactado por el AcpClient, los mensajes
## de fallo y el tooltip del estado se redactan, el entorno del agente registra sus keys al arrancar
## y un historial viejo se reproduce sin ellos.

const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AcpClient := preload("res://addons/godot_agent/acp/acp_client.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")

const TOKEN := "tok_0123456789abcdef0123456789abcdef"


func _log_with_secret() -> AgentLog:
	var log := AgentLog.new()
	log.add_secret(TOKEN)
	return log


func test_redact_data_walks_the_structure() -> void:
	var log := _log_with_secret()
	var data := {
		"text": "Bearer %s" % TOKEN,
		"list": [TOKEN, {"deep": "x %s y" % TOKEN}, 3],
		"strings": PackedStringArray([TOKEN, "clean"]),
		"number": 7,
		"nothing": null,
	}
	var out: Dictionary = log.redact_data(data)
	assert_eq(out.text, "Bearer " + AgentLog.REDACTED, "cadena")
	assert_eq(out.list[0], AgentLog.REDACTED, "en un array")
	assert_eq(out.list[1].deep, "x %s y" % AgentLog.REDACTED, "anidado")
	assert_eq(out.list[2], 3, "los números quedan")
	assert_eq(out.strings, PackedStringArray([AgentLog.REDACTED, "clean"]), "PackedStringArray")
	assert_eq(out.nothing, null, "null queda")
	assert_eq(data.text, "Bearer " + TOKEN, "el original no se toca")
	var clean := AgentLog.new()
	assert_eq(clean.redact_data(data), data, "sin secretos, igual")


func test_acp_client_redacts_everything_the_agent_sends() -> void:
	var log := _log_with_secret()
	var client := AcpClient.new()
	client.setup(func(_line: String) -> bool: return true, log)
	var updates: Array = []
	client.set_notification_handler("session/update", func(params: Dictionary) -> void: updates.append(params))
	var requests: Array = []
	client.set_request_handler("session/request_permission", func(params: Dictionary) -> Variant:
		requests.append(params)
		return {"outcome": {"outcome": "selected", "optionId": "allow"}})
	client.receive_line('{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","toolCallId":"t","title":"Bash","content":[{"type":"content","content":{"type":"text","text":"GODOT_AGENT_MCP_TOKEN=%s"}}]}}}' % TOKEN)
	assert_eq(updates.size(), 1, "la notificación llegó")
	var shown: String = updates[0].update.content[0].content.text
	assert_eq(shown, "GODOT_AGENT_MCP_TOKEN=" + AgentLog.REDACTED, "el resultado de la herramienta llega redactado")
	client.receive_line('{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{"sessionId":"s","toolCall":{"toolCallId":"t","title":"curl -H \\"Authorization: Bearer %s\\""},"options":[{"optionId":"allow","name":"Allow","kind":"allow_once"}]}}' % TOKEN)
	await Engine.get_main_loop().process_frame
	assert_eq(requests.size(), 1, "el request llegó")
	assert_false(str(requests[0].toolCall.title).contains(TOKEN), "el título de la tarjeta de permiso no trae el token")
	var results: Array = []
	var run := func() -> void:
		var response: AcpClient.AcpResponse = await client.request("session/new", {})
		results.append(response)
	run.call()
	client.receive_line('{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"bad mcpServers","data":{"details":"headers: Authorization: Bearer %s"}}}' % TOKEN)
	assert_eq(results.size(), 1, "la respuesta llegó")
	var response: AcpClient.AcpResponse = results[0]
	assert_false(response.error_message().contains(TOKEN), "el mensaje de error no trae el token (%s)" % response.error_message())
	assert_true(response.error_message().contains(AgentLog.REDACTED), "sino «secret»")
	for entry: Dictionary in log.entries():
		assert_false(str(entry.raw).contains(TOKEN) or str(entry.message).contains(TOKEN), "el log tampoco")


func test_failure_messages_and_tooltip_are_redacted() -> void:
	var model := SessionModel.new()
	var log := _log_with_secret()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	controller.call(&"_fail", "Could not open the session: invalid header Authorization: Bearer %s" % TOKEN, [] as Array[Dictionary])
	assert_false(model.failure_message.contains(TOKEN), "failure_message (tooltip del estado) sin el token")
	assert_false(model.entries().back().text.contains(TOKEN), "la tarjeta sin el token")
	controller.call(&"_fail_agent", "Agent stopped", "It printed %s and died." % TOKEN, "exited after printing %s" % TOKEN, [] as Array[Dictionary])
	assert_false(model.failure_message.contains(TOKEN), "_fail_agent: failure_message")
	var card: ChatEntry = model.entries().back()
	assert_false(card.text.contains(TOKEN), "_fail_agent: la causa")
	assert_true(card.text.contains(AgentLog.REDACTED), "con «secret» en su lugar")


func test_agent_env_secrets_are_registered_on_start() -> void:
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	var profile := AgentProfile.from_dict({
		"id": "x", "display_name": "X", "command": "/nonexistent/agent-binary-for-tests", "args": [],
		"env": {"MY_API_KEY": "sk-live-0123456789", "OPENAI_TOKEN": "tok-abcdefgh", "SHORT_KEY": "abc", "PLAIN_PATH": "/home/user/project-0123456789"},
	})
	var ok: bool = await controller.start(profile)
	assert_false(ok, "el comando no existe: no arranca")
	assert_eq(log.redact("key sk-live-0123456789 token tok-abcdefgh"), "key %s token %s" % [AgentLog.REDACTED, AgentLog.REDACTED], "las keys del entorno quedaron registradas")
	assert_eq(log.redact("abc"), "abc", "un valor corto no se registra")
	assert_eq(log.redact("/home/user/project-0123456789"), "/home/user/project-0123456789", "una variable que no parece secreta tampoco")
	assert_eq(AgentProfile.secret_env_values({"A_SECRET": "12345678", "B_SECRET": "12345678", "PASSWORD": "pw"}), PackedStringArray(["12345678"]), "sin repetir, sin cortos")


func test_old_history_replays_redacted() -> void:
	var log := _log_with_secret()
	var model := SessionModel.new()
	var record := {
		"title": "Old chat",
		"events": [
			{"type": "user", "text": "run env"},
			{"type": "update", "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Your token is %s" % TOKEN}}},
			{"type": "turn_end", "reason": "end_turn"},
		],
	}
	SessionHistory.replay(log.redact_data(record), model)
	var texts := model.entries().map(func(entry: ChatEntry) -> String: return entry.text)
	assert_true(texts.any(func(text: String) -> bool: return text.contains(AgentLog.REDACTED)), "el mensaje viejo se ve redactado (%s)" % [texts])
	assert_false(texts.any(func(text: String) -> bool: return text.contains(TOKEN)), "y sin el token")
