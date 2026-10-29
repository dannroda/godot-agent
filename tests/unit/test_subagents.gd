extends "test_case.gd"
## Subagentes de Claude Code (m7-43): su grupo de permisos, el límite por modo y los que están en curso.

const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

const M := SessionModel.HarnessMode
const OPTIONS := [
	{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
	{"optionId": "reject", "name": "Reject", "kind": "reject_once"},
]


func _agent_call(id: String, status: String, parent: String = "") -> Dictionary:
	var meta := {"toolName": "Agent"}
	if not parent.is_empty():
		meta.parentToolUseId = parent
	return {"sessionUpdate": "tool_call", "toolCallId": id, "title": "Task", "kind": "think", "status": status,
		"rawInput": {"description": "Look around", "prompt": "Find x", "subagent_type": "Explore"}, "_meta": {"claudeCode": meta}}


func _controller(mode: SessionModel.HarnessMode) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	controller.model.set_harness_mode(mode)
	return controller


func _ask(controller: SessionController, id: String) -> String:
	controller.model.apply_update(_agent_call(id, "pending"))
	var result: Variant = controller.permissions.call(&"on_request_permission", {"sessionId": "s", "toolCall": {"toolCallId": id, "title": "Task"}, "options": OPTIONS})
	return str(result.outcome.get("optionId", "")) if result is Dictionary else "card"


func test_group_and_defaults() -> void:
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "think", "_meta": {"claudeCode": {"toolName": "Agent"}}}), "subagents", "Agent")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "think", "_meta": {"claudeCode": {"toolName": "Task"}}}), "subagents", "Task, el nombre viejo")
	var policy := PermissionPolicy.new()
	for mode: int in [M.ASK, M.REVIEW, M.BUILD, M.ONESHOT, M.AUTO]:
		assert_eq(policy.decide("subagents", mode), "allow", "permitidos por defecto, como antes (%d)" % mode)
		assert_eq(policy.subagent_limit(mode), 0, "sin límite por defecto (%d)" % mode)
	policy.subagent_limits = {"build": 2, "ask": -3, "auto": "x"}
	assert_eq([policy.subagent_limit(M.BUILD), policy.subagent_limit(M.ASK), policy.subagent_limit(M.AUTO)], [2, 0, 0], "límites, sin negativos")


func test_running_subagents() -> void:
	var model := SessionModel.new()
	model.apply_update(_agent_call("a1", "in_progress"))
	model.apply_update(_agent_call("a2", "in_progress"))
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "r1", "title": "Read x", "kind": "read", "status": "in_progress",
		"_meta": {"claudeCode": {"parentToolUseId": "a1"}}})
	model.apply_update(_agent_call("a3", "completed"))
	assert_eq(model.running_subagents().map(func(call: SessionModel.ToolCall) -> String: return call.id), ["a1", "a2"], "los que no terminaron, sin sus tools")
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a1", "status": "completed"})
	assert_eq(model.running_subagents().size(), 1, "al terminar deja de contar")


func test_limit_rejects_one_more() -> void:
	var controller := _controller(M.BUILD)
	controller.policy.subagent_limits = {"build": 2}
	assert_eq(_ask(controller, "a1"), "allow", "el primero")
	controller.model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a1", "status": "in_progress"})
	assert_eq(_ask(controller, "a2"), "allow", "el segundo")
	controller.model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a2", "status": "in_progress"})
	assert_eq(_ask(controller, "a3"), "reject", "el tercero pasa el límite")
	var notices := controller.model.entries().filter(func(entry: Variant) -> bool: return entry.kind == SessionModel.ChatEntry.EntryKind.NOTICE)
	assert_true(not notices.is_empty() and str(notices.back().text).contains("2 already running"), "avisa en el chat")
	controller.model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a1", "status": "completed"})
	assert_eq(_ask(controller, "a4"), "allow", "cuando uno termina, hay lugar")


func test_mode_decides() -> void:
	var controller := _controller(M.ASK)
	controller.policy.overrides = {"subagents": {"ask": "deny"}}
	assert_eq(_ask(controller, "a1"), "reject", "denegados en el modo")
	controller.model.set_harness_mode(M.BUILD)
	assert_eq(_ask(controller, "a2"), "allow", "otro modo, permitidos")
	controller.policy.overrides = {"subagents": {"build": "ask"}}
	assert_eq(_ask(controller, "a3"), "card", "ask muestra la tarjeta")


## Subagentes nativos de ACP: el anuncio y el prompt que liga la sesión del hijo a su tool call.
func _announce(model: SessionModel, launch: String, child: String) -> void:
	model.apply_update({"sessionUpdate": "subagent_update", "sessionId": child, "title": "Explore", "description": "Look around",
		"capabilities": {"cancel": {}}, "state": {"state": "running"}})
	model.apply_update({"sessionUpdate": "session_message", "messageId": launch, "senderSessionId": "s", "recipientSessionId": child,
		"content": [{"type": "text", "text": "Find x"}]})


func test_native_subagent_sessions() -> void:
	var model := SessionModel.new()
	model.apply_update(_agent_call("a1", "in_progress"))
	assert_true(not model.is_subagent_session("c1"), "sin anunciar")
	_announce(model, "a1", "c1")
	var call := model.tool_call("a1")
	assert_eq([call.subagent_session_id, call.subagent_state], ["c1", "running"], "ligado a su tool call")
	assert_true(model.apply_child_update("c1", {"sessionUpdate": "tool_call", "toolCallId": "g1", "title": "Glob", "kind": "search", "status": "in_progress"}), "update del hijo")
	assert_eq(model.tool_call("g1").parent_id, "a1", "su tool call va dentro del lanzamiento")
	model.apply_child_update("c1", {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "found 3"}})
	assert_eq(call.subagent_text, "found 3", "su texto también")
	assert_true(not model.apply_child_update("zz", {"sessionUpdate": "tool_call", "toolCallId": "g2"}), "otra sesión no se aplica")
	assert_true(model.tool_call("g2") == null, "ni crea tool calls")
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a1", "status": "completed", "rawOutput": "Async agent launched successfully"})
	assert_eq(model.running_subagents().size(), 1, "en segundo plano sigue trabajando después del tool call")
	model.apply_update({"sessionUpdate": "subagent_update", "sessionId": "c1", "state": {"state": "idle", "stopReason": "end_turn"}})
	assert_eq(model.running_subagents().size(), 0, "idle: terminó")


func test_limit_counts_native_state() -> void:
	var controller := _controller(M.BUILD)
	controller.policy.subagent_limits = {"build": 1}
	assert_eq(_ask(controller, "a1"), "allow", "el primero")
	_announce(controller.model, "a1", "c1")
	controller.model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a1", "status": "completed"})
	assert_eq(_ask(controller, "a2"), "reject", "el primero sigue en segundo plano")
	controller.model.apply_update({"sessionUpdate": "subagent_update", "sessionId": "c1", "state": {"state": "idle", "stopReason": "end_turn"}})
	assert_eq(_ask(controller, "a3"), "allow", "terminó: hay lugar")


func test_child_permission_request_goes_to_launch() -> void:
	var controller := _controller(M.BUILD)
	controller.model.apply_update(_agent_call("a1", "in_progress"))
	_announce(controller.model, "a1", "c1")
	controller.permissions.call(&"on_request_permission", {"sessionId": "c1", "toolCall": {"toolCallId": "b1", "title": "ls", "kind": "execute", "status": "pending",
		"rawInput": {"command": "ls"}}, "options": OPTIONS})
	assert_eq(controller.model.tool_call("b1").parent_id, "a1", "el pedido del hijo queda en la tarjeta del subagente")
	assert_true("subagents" in controller.client_capabilities(), "declara subagentes nativos")
