extends "test_case.gd"
## UsageQuery (m13-05): el comando de cuota corre como un turno oculto y devuelve su texto.

const AcpClient := preload("res://addons/godot_agent/acp/acp_client.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const UsageQuery := preload("res://addons/godot_agent/session/usage_query.gd")

var _sent: Array[Dictionary] = []


func _capture(line: String) -> bool:
	_sent.append(JSON.parse_string(line))
	return true


func test_hidden_turn_returns_its_text() -> void:
	var client := AcpClient.new()
	client.setup(_capture)
	var query := UsageQuery.new()
	query.setup(client, AgentLog.new())
	var results: Array = []
	var run := func() -> void: results.append(await query.run("/usage", "s1", func() -> bool: return true))
	run.call()
	assert_true(query.running, "corriendo")
	assert_eq(_sent[0].params.prompt[0].text, "/usage", "manda el comando como prompt")
	assert_true(query.capture({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Weekly: 18%"}}), "el texto no va al chat")
	assert_true(query.capture({"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": "x"}}), "el pensamiento tampoco")
	assert_false(query.capture({"sessionUpdate": "usage_update"}), "lo demás sigue su camino")
	client.receive_line('{"jsonrpc":"2.0","id":%d,"result":{"stopReason":"end_turn"}}' % int(_sent[0].id))
	assert_eq(results, ["Weekly: 18%"], "devuelve solo el texto del agente")
	assert_false(query.running, "terminó")
	assert_false(query.capture({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "hola"}}), "después, el texto vuelve al chat")
	run.call()
	client.receive_line('{"jsonrpc":"2.0","id":%d,"error":{"code":-32603,"message":"no"}}' % int(_sent[1].id))
	assert_eq(results[1], null, "un error da null: no se lee la cuota")
