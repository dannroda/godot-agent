extends SceneTree
## Prueba manual contra Claude Code real (m7-43, gasta tokens): con la regla `ask` de Agent en las
## settings de la sesión, cada subagente pide permiso al harness; en Construir con límite 1, el
## agente lanza dos a la vez y uno solo arranca. El que arranca se ve con su sesión (subagentes
## nativos de ACP): sus tool calls dentro de la tarjeta y su estado hasta que termina. Uso:
##   godot --headless --path <repo> --script tests/subagents_session_check.gd

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")

const TIMEOUT_S := 400.0
const PROMPT := "In a single message, launch two general-purpose subagents in parallel with the Agent tool: one reads addons/godot_agent/plugin.cfg with the Read tool and reports its version line, the other reads project.godot with the Read tool and reports its config/name line. If one of them is rejected, do not retry it and do not do its work yourself. Then reply with what each one reported, or \"rejected\" for one that did not run."


func _initialize() -> void:
	await process_frame
	create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		printerr("FAIL subagents_session_check: timeout")
		quit(1))
	var model := SessionModel.new()
	var log := AgentLog.new()
	var decisions: Array[String] = []
	log.entry_added.connect(func(entry: Dictionary) -> void:
		if entry.channel == AgentLog.CH_PERM:
			print("  [perm] ", entry.message)
			decisions.append(str(entry.message)))
	var controller := SessionController.new()
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	controller.setup(model, log, project)
	controller.session_meta_provider = func() -> Dictionary:
		return {"claudeCode": {"options": {"settings": {"permissions": {"ask": Array(PermissionPolicy.SUBAGENT_ASK_RULES)}}}}}
	controller.policy.subagent_limits = {"build": 1}
	model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	# Otra tool que pida permiso no debe colgar la prueba.
	model.permission_requested.connect(func(request: PermissionRequest) -> void:
		print("  [card] ", request.title)
		request.select(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE])))
	var states: Array[String] = []
	model.tool_call_changed.connect(func(call: SessionModel.ToolCall, _group: ChatEntry) -> void:
		if not call.subagent_state.is_empty() and (states.is_empty() or states.back() != call.subagent_state):
			states.append(call.subagent_state))
	var profile: AgentProfile = AgentProfile.from_dict(AgentProfile.defaults()[0])
	if not await controller.start(profile):
		printerr("FAIL no arrancó: ", model.failure_message)
		quit(1)
		return
	var stop_reason: String = await controller.send_prompt(PROMPT)
	print("fin del turno: ", stop_reason)
	var agent_text := ""
	var notices: Array[String] = []
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.EntryKind.AGENT:
			agent_text = entry.text
		elif entry.kind == ChatEntry.EntryKind.NOTICE:
			notices.append(entry.text)
	print("respuesta: ", agent_text.strip_edges().left(400))
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.EntryKind.TOOL_GROUP:
			for id: String in entry.tool_call_ids:
				var call := model.tool_call(id)
				print("  tool %s [%s] %s · %s · %s · sesión %s %s · %d tools" % [call.tool_name, call.status, call.title, str(call.raw_output).left(120),
					call.subagent_text.left(120), call.subagent_session_id, call.subagent_state, call.child_ids.size()])
	var launched := model.running_subagents()
	print("estados: ", states)
	controller.stop()
	var asked := decisions.filter(func(line: String) -> bool: return line.contains("subagent") or line.contains("Task") or line.contains("Agent"))
	var failures: PackedStringArray = []
	if not decisions.any(func(line: String) -> bool: return line.begins_with("allowed by Build mode")):
		failures.append("ningún subagente pidió permiso y se permitió: %s" % [decisions])
	if not decisions.any(func(line: String) -> bool: return line.contains("subagents already running")):
		failures.append("el segundo no se rechazó por el límite (¿no fueron a la vez?): %s" % [decisions])
	if not notices.any(func(text: String) -> bool: return text.contains("subagent was not started")):
		failures.append("no hubo aviso en el chat: %s" % [notices])
	if not "running" in states or states.back() != "idle":
		failures.append("no se vio el estado del subagente (running … idle): %s" % [states])
	if not launched.is_empty():
		failures.append("quedaron subagentes trabajando: %s" % [launched.map(func(call: SessionModel.ToolCall) -> String: return call.id)])
	var with_tools := false
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.EntryKind.TOOL_GROUP:
			for id: String in entry.tool_call_ids:
				var call := model.tool_call(id)
				with_tools = with_tools or (not call.subagent_session_id.is_empty() and not call.child_ids.is_empty())
	if not with_tools:
		failures.append("las tools del subagente no quedaron en su tarjeta")
	if failures.is_empty():
		print("PASS subagents_session_check: %d decisiones de permiso de subagentes" % asked.size())
		quit(0)
	else:
		printerr("FAIL subagents_session_check:\n  " + "\n  ".join(failures))
		quit(1)
