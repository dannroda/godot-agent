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

const FsHandler := preload("res://addons/godot_agent/acp/fs_handler.gd")

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
	assert_true(str(requests[0].toolCall.title).contains(TOKEN), "un request del agente llega tal cual al handler (la tarjeta redacta su copia)")
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


## Lo que el agente pide hacer con el proyecto se ejecuta tal cual: si escribe la key del usuario en
## un .env o la pasa en un comando, redactarla rompería el archivo o el comando.
func test_acp_client_leaves_project_actions_intact() -> void:
	var log := _log_with_secret()
	var client := AcpClient.new()
	client.setup(func(_line: String) -> bool: return true, log)
	var written: Array = []
	client.set_request_handler("fs/write_text_file", func(params: Dictionary) -> Variant:
		written.append(params)
		return {})
	var commands: Array = []
	client.set_request_handler("terminal/create", func(params: Dictionary) -> Variant:
		commands.append(params)
		return {"terminalId": "t1"})
	client.receive_line('{"jsonrpc":"2.0","id":3,"method":"fs/write_text_file","params":{"sessionId":"s","path":"/p/.env","content":"API_KEY=%s\n"}}' % TOKEN)
	client.receive_line('{"jsonrpc":"2.0","id":4,"method":"terminal/create","params":{"sessionId":"s","command":"curl","args":["-H","Authorization: Bearer %s"]}}' % TOKEN)
	await Engine.get_main_loop().process_frame
	assert_eq(written.size(), 1, "la escritura llegó")
	assert_eq(str(written[0].content), "API_KEY=%s\n" % TOKEN, "el archivo se escribe con la key tal cual")
	assert_eq(commands.size(), 1, "el comando llegó")
	assert_eq(str(commands[0].args[1]), "Authorization: Bearer %s" % TOKEN, "el comando corre con la key tal cual")
	for entry: Dictionary in log.entries():
		assert_false(str(entry.raw).contains(TOKEN), "pero el log los guarda redactados")
	assert_true(AcpClient.is_incoming_request({"id": 1, "method": "fs/read_text_file"}), "fs/* es un request del agente")
	assert_true(AcpClient.is_incoming_request({"id": 1, "method": "session/request_permission"}), "un permiso también")
	assert_false(AcpClient.is_incoming_request({"method": "session/update"}), "una notificación no")
	assert_false(AcpClient.is_incoming_request({"id": 1, "result": {}}), "una respuesta no")


## La tarjeta de permiso muestra el tool call sin el secreto; lo que se le responde al agente y lo
## que chequean las reglas sale del original.
func test_permission_card_shows_a_redacted_copy() -> void:
	var model := SessionModel.new()
	var log := _log_with_secret()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	model.session_id = "s"
	var options := [{"optionId": "allow", "name": "Allow", "kind": "allow_once"}, {"optionId": "reject", "name": "Reject", "kind": "reject_once"}]
	var params := {"sessionId": "s", "toolCall": {"toolCallId": "c1", "kind": "execute", "title": "curl -H 'Authorization: Bearer %s' https://api" % TOKEN,
		"rawInput": {"command": "curl -H 'Authorization: Bearer %s' https://api" % TOKEN}}, "options": options}
	var results: Array = []
	var run := func() -> void:
		results.append(await controller.permissions.on_request_permission(params))
	run.call()
	await Engine.get_main_loop().process_frame
	assert_eq(model.pending_permissions.size(), 1, "la tarjeta espera al usuario")
	var request: SessionModel.PermissionRequest = model.pending_permissions[0]
	assert_false(request.title.contains(TOKEN) or request.description.contains(TOKEN), "título y descripción sin el token (%s · %s)" % [request.title, request.description])
	assert_true((request.title + request.description).contains(AgentLog.REDACTED), "con «secret» en su lugar")
	var call: SessionModel.ToolCall = model.tool_call("c1")
	assert_true(call != null and not call.title.contains(TOKEN), "el tool call del chat tampoco")
	assert_eq(str(params.toolCall.rawInput.command).count(TOKEN), 1, "los params originales quedan intactos")
	request.select("allow")
	await Engine.get_main_loop().process_frame
	assert_eq(results.size(), 1, "la respuesta salió")
	assert_eq(str(results[0].outcome.optionId), "allow", "con la opción elegida")


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



## m13-28: el formulario de elicitation se muestra sin el token (mensaje, títulos, descripciones), pero
## el default y la opción que vuelven al agente son los reales. Una propiedad que se llama «title» no
## se redacta entera.
func test_elicitation_form_shows_a_redacted_copy() -> void:
	var model := SessionModel.new()
	var log := _log_with_secret()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	model.session_id = "s"
	var schema := {"type": "object", "title": "Config %s" % TOKEN, "properties": {
		"title": {"type": "string", "description": "Header «Bearer %s»" % TOKEN, "default": "Bearer %s" % TOKEN},
		"scope": {"type": "string", "enum": ["read-%s" % TOKEN, "write"], "enumNames": ["Read %s" % TOKEN, "Write"]},
	}}
	var request_line := JSON.stringify({"jsonrpc": "2.0", "id": 21, "method": "elicitation/create", "params": {"sessionId": "s", "mode": "form", "message": "Use the key %s?" % TOKEN, "requestedSchema": schema}})
	var sent: Array[String] = []
	controller.client.setup(func(line: String) -> bool:
		sent.append(line)
		return true, log)
	controller.client.receive_line(request_line)
	await Engine.get_main_loop().process_frame
	assert_eq(model.pending_elicitations.size(), 1, "el formulario espera al usuario")
	var request: Object = model.pending_elicitations[0]
	var shown := str(request.get(&"message")) + JSON.stringify(request.get(&"requested_schema").get("title")) + JSON.stringify(request.get(&"requested_schema").properties.title.description) + JSON.stringify(request.get(&"requested_schema").properties.scope.enumNames)
	assert_false(shown.contains(TOKEN), "mensaje, títulos, descripciones y enumNames sin el token: %s" % shown)
	assert_eq(shown.count(AgentLog.REDACTED), 4, "con «secret» en su lugar")
	var props: Dictionary = request.get(&"requested_schema").properties
	assert_eq(str(props.title.default), "Bearer %s" % TOKEN, "el default (lo que se manda si no lo cambia) queda real")
	assert_eq(str(props.scope.enum[0]), "read-%s" % TOKEN, "las opciones que vuelven al agente quedan reales")
	request.call(&"accept", {"title": props.title.default, "scope": props.scope.enum[0]})
	for i in 3:
		await Engine.get_main_loop().process_frame
	var reply: Array = sent.filter(func(line: String) -> bool: return line.contains("\"id\":21"))
	assert_eq(reply.size(), 1, "la respuesta salió")
	assert_true(reply.size() == 1 and reply[0].contains("read-%s" % TOKEN) and reply[0].contains("Bearer %s" % TOKEN), "con los valores reales")



## m13-28: el tool call de una tool godot.* llega al modelo redactado y el server MCP del harness
## recibe los args reales: el paso de undo se une igual con su tool call (plugin._match_pending_undo).
func test_godot_tool_call_matches_with_a_secret_in_its_args() -> void:
	var model := SessionModel.new()
	var log := _log_with_secret()
	var client := AcpClient.new()
	client.setup(func(_line: String) -> bool: return true, log)
	client.set_notification_handler("session/update", func(params: Dictionary) -> void: model.apply_update(params.update))
	model.session_id = "s"
	var args := {"path": "res://config.gd", "text": "const KEY := \"%s\"" % TOKEN}
	client.receive_line(JSON.stringify({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s", "update": {"sessionUpdate": "tool_call", "toolCallId": "g1", "title": "mcp__godot__write_script", "kind": "edit", "rawInput": args}}}))
	assert_true(model.tool_call("g1") != null and not JSON.stringify(model.tool_call("g1").raw_input).contains(TOKEN), "el modelo lo tiene redactado")
	assert_eq(model.find_godot_tool_call("write_script", args), null, "con los args reales, sin redactar, no lo encuentra (el bug)")
	assert_eq(model.find_godot_tool_call("write_script", args, log.redact_data), model.tool_call("g1"), "redactando los args para comparar, sí")


## m13-28: en Auto, la tarjeta no propone una regla de shell que tenga un secreto: la mostraría y
## Ajustes la guardaría en disco.
func test_no_shell_rule_with_a_secret() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), _log_with_secret(), "/tmp/project")
	controller.model.set_harness_mode(SessionModel.HarnessMode.AUTO)
	controller.model.session_id = "s"
	var options := [{"optionId": "allow", "name": "Allow", "kind": "allow_once"}, {"optionId": "reject", "name": "Reject", "kind": "reject_once"}]
	var ask := func(id: String, command: String) -> void:
		await controller.permissions.on_request_permission({"sessionId": "s", "toolCall": {"toolCallId": id, "kind": "execute", "title": "x", "rawInput": {"command": command}}, "options": options})
	ask.call("r1", "npm test")
	assert_eq(controller.model.pending_permissions.size(), 1, "npm test pregunta")
	assert_eq(controller.model.pending_permissions[0].rule_pattern, "npm test", "y propone la regla")
	controller.model.pending_permissions[0].select("reject")
	for i in 3:
		await Engine.get_main_loop().process_frame
	ask.call("r2", "%s --login" % TOKEN)
	assert_eq(controller.model.pending_permissions.size(), 1, "un comando que empieza con el token pregunta")
	var request: SessionModel.PermissionRequest = controller.model.pending_permissions[0]
	assert_eq(request.rule_pattern, "", "sin regla propuesta")
	assert_false(request.title.contains(TOKEN) or request.description.contains(TOKEN), "y la tarjeta no muestra el token")
	request.select("reject")
	for i in 3:
		await Engine.get_main_loop().process_frame


## De punta a punta con el FsHandler real: el archivo que el agente pide escribir lleva la key tal
## cual; lo que se muestra de esa escritura (la notificación del tool call) llega redactado.
func test_agent_file_write_keeps_the_real_value() -> void:
	var model := SessionModel.new()
	var log := _log_with_secret()
	var controller := SessionController.new()
	var root_dir := ProjectSettings.globalize_path(temp_dir("secret_fs_write"))
	controller.setup(model, log, root_dir)
	var fs := FsHandler.new()
	fs.setup(root_dir, log)
	controller.set_fs_handler(fs)
	model.session_id = "s"
	var target := root_dir.path_join(".env")
	controller.client.receive_line('{"jsonrpc":"2.0","id":9,"method":"fs/write_text_file","params":{"sessionId":"s","path":"%s","content":"ANTHROPIC_API_KEY=%s\\n"}}' % [target, TOKEN])
	for i in 3:
		await Engine.get_main_loop().process_frame
	# La escritura pide permiso: la tarjeta muestra el diff sin la key, y se acepta.
	assert_eq(model.pending_permissions.size(), 1, "la tarjeta de permiso de la escritura")
	var card: SessionModel.PermissionRequest = model.pending_permissions[0]
	assert_false(JSON.stringify(card.diff).contains(TOKEN), "el diff de la tarjeta no trae la key")
	assert_true(str(card.diff.get("newText", "")).contains(AgentLog.REDACTED), "sino «secret»")
	card.select(card.option_id_for(PackedStringArray([SessionModel.PermissionRequest.KIND_ALLOW_ONCE])))
	for i in 3:
		await Engine.get_main_loop().process_frame
	assert_true(FileAccess.file_exists(target), "el archivo se escribió")
	assert_eq(FileAccess.get_file_as_string(target), "ANTHROPIC_API_KEY=%s\n" % TOKEN, "con la key de verdad")
	controller.client.receive_line('{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","toolCallId":"w1","title":"Write .env","kind":"edit","content":[{"type":"diff","path":"%s","oldText":"","newText":"ANTHROPIC_API_KEY=%s"}]}}}' % [target, TOKEN])
	var call: SessionModel.ToolCall = model.tool_call("w1")
	assert_true(call != null, "el tool call llegó al modelo")
	assert_false(JSON.stringify(call.content).contains(TOKEN), "el diff que se muestra no trae la key")
	assert_true(JSON.stringify(call.content).contains(AgentLog.REDACTED), "sino «secret»")
	for entry: Dictionary in log.entries():
		assert_false(str(entry.raw).contains(TOKEN), "el log guarda el request redactado")


## m13-25: una key exportada en el entorno del editor le llega al agente aunque el perfil no la nombre
## (hereda el entorno entero): queda registrada al arrancar y se enmascara en el log y en el chat.
func test_inherited_api_key_is_registered_on_start() -> void:
	var key := "sk-inherited-0123456789"
	OS.set_environment("ANTHROPIC_API_KEY", key)
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	var profile := AgentProfile.from_dict({"id": "claude-code", "display_name": "Claude Code", "command": "/nonexistent/claude-agent-acp", "args": [], "env": {}})
	var ok: bool = await controller.start(profile)
	OS.unset_environment("ANTHROPIC_API_KEY")
	assert_false(ok, "el comando no existe: no arranca")
	assert_eq(controller.adapter.api_key_variable(), "ANTHROPIC_API_KEY", "el adapter de Claude nombra su API key")
	assert_eq(log.redact("key " + key), "key " + AgentLog.REDACTED, "la key heredada quedó registrada en el log")
	var updates: Array = []
	controller.client.set_notification_handler("session/update", func(params: Dictionary) -> void: updates.append(params))
	controller.client.receive_line(JSON.stringify({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s",
		"update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "mi key es " + key}}}}))
	assert_eq(updates.size(), 1, "la notificación llegó")
	assert_eq(str(updates[0].update.content.text), "mi key es " + AgentLog.REDACTED, "lo que el agente dice llega al chat con «secret»")
	for entry: Dictionary in log.entries():
		assert_false(str(entry.raw).contains(key) or str(entry.message).contains(key), "el log tampoco la tiene")
	assert_eq(AgentProfile.inherited_secret_values(PackedStringArray(["", "GODOT_AGENT_NO_SUCH_VARIABLE_FOR_TESTS"])), PackedStringArray(), "sin nombre o sin variable: nada")
	OS.set_environment("ANTHROPIC_API_KEY", "abc")
	assert_eq(AgentProfile.inherited_secret_values(PackedStringArray(["ANTHROPIC_API_KEY"])), PackedStringArray(), "un valor corto no cuenta")
	OS.unset_environment("ANTHROPIC_API_KEY")
