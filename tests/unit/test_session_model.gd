extends "test_case.gd"
## SessionModel: merge de chunks, tool calls, plan, variantes desconocidas y cancelación.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")


func _chunk(kind: String, text: String, message_id: Variant = null) -> Dictionary:
	var update := {"sessionUpdate": kind, "content": {"type": "text", "text": text}}
	if message_id != null:
		update["messageId"] = message_id
	return update


func test_chunks_merge_by_message() -> void:
	var model := SessionModel.new()
	var updated: Array[int] = []
	model.entry_updated.connect(func(entry: ChatEntry) -> void: updated.append(entry.id))
	model.apply_update(_chunk("agent_message_chunk", "Ho", "m1"))
	model.apply_update(_chunk("agent_message_chunk", "la", "m1"))
	model.apply_update(_chunk("agent_message_chunk", " mundo"))
	assert_eq(model.entries().size(), 1, "una sola entrada")
	assert_eq(model.entries()[0].text, "Hola mundo", "texto unido")
	assert_eq(updated.size(), 2, "dos actualizaciones")
	model.apply_update(_chunk("agent_message_chunk", "Otro", "m2"))
	assert_eq(model.entries().size(), 2, "otro messageId abre otra entrada")


func test_thought_and_message_alternate() -> void:
	var model := SessionModel.new()
	model.apply_update(_chunk("agent_thought_chunk", "pienso"))
	model.apply_update(_chunk("agent_thought_chunk", " más"))
	model.apply_update(_chunk("agent_message_chunk", "respuesta"))
	assert_eq(model.entries().size(), 2, "thought + mensaje")
	assert_eq(model.entries()[0].kind, ChatEntry.EntryKind.THOUGHT, "primero el thought")
	assert_eq(model.entries()[0].text, "pienso más", "thought unido")


func test_tool_calls_group_and_update() -> void:
	var model := SessionModel.new()
	model.apply_update(_chunk("agent_message_chunk", "Voy a leer"))
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "a", "title": "Read", "kind": "read", "status": "pending"})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "b", "title": "Edit", "kind": "edit", "status": "pending"})
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "a", "status": "completed"})
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "b", "status": "in_progress",
		"content": [{"type": "diff", "path": "/p/x.gd", "oldText": "a", "newText": "b"}]})
	assert_eq(model.entries().size(), 2, "mensaje + un grupo")
	var group: ChatEntry = model.entries()[1]
	assert_eq(group.kind, ChatEntry.EntryKind.TOOL_GROUP, "grupo de tools")
	assert_eq(group.tool_call_ids, PackedStringArray(["a", "b"]), "ids en orden")
	assert_eq(model.tool_call("a").status, "completed", "a completado")
	assert_eq(model.tool_call("b").diffs().size(), 1, "b tiene un diff")
	assert_eq(model.tool_call("a").title, "Read", "el update conserva el título")
	# Un mensaje en el medio corta el grupo.
	model.apply_update(_chunk("agent_message_chunk", "listo", "m9"))
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "c", "title": "Bash", "status": "in_progress"})
	assert_eq(model.entries().size(), 4, "un update de id nuevo abre otro grupo")


## Claude Code marca lo que hace un subagente con `_meta.claudeCode.parentToolUseId`: sus tool calls y su
## texto quedan dentro del tool call de Agent, no en la conversación principal.
func test_subagent_updates_nest_under_agent_call() -> void:
	var model := SessionModel.new()
	var sub := func(update: Dictionary, parent: String) -> Dictionary:
		update["_meta"] = {"claudeCode": {"parentToolUseId": parent}}
		return update
	model.apply_update(_chunk("agent_message_chunk", "Delego", "m1"))
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "agent", "title": "Buscar usos", "kind": "think", "status": "in_progress",
		"rawInput": {"description": "Buscar usos", "subagent_type": "Explore", "prompt": "..."}, "_meta": {"claudeCode": {"toolName": "Agent"}}})
	model.apply_update(sub.call({"sessionUpdate": "tool_call", "toolCallId": "r1", "title": "Read", "kind": "read", "status": "pending"}, "agent"))
	model.apply_update(sub.call(_chunk("agent_message_chunk", "Encontré dos.", "s1"), "agent"))
	model.apply_update(sub.call(_chunk("agent_thought_chunk", "pienso", "s1"), "agent"))
	model.apply_update(sub.call({"sessionUpdate": "plan", "entries": [{"content": "del subagente", "status": "pending"}]}, "agent"))
	model.apply_update(sub.call({"sessionUpdate": "tool_call_update", "toolCallId": "r1", "status": "completed"}, "agent"))
	assert_eq(model.entries().size(), 2, "mensaje + un grupo: nada del subagente suelto")
	assert_eq(model.entries()[0].text, "Delego", "el texto del subagente no entra al mensaje principal")
	assert_eq(model.plan.size(), 0, "el plan del subagente no reemplaza el principal")
	var group: ChatEntry = model.entries()[1]
	assert_eq(group.tool_call_ids, PackedStringArray(["agent"]), "el grupo tiene solo el Agent")
	var agent := model.tool_call("agent")
	assert_true(agent.is_subagent(), "Agent es subagente")
	assert_eq(agent.child_ids, PackedStringArray(["r1"]), "Read dentro del subagente")
	assert_eq(agent.subagent_text, "Encontré dos.", "texto del subagente (sin el thought)")
	assert_eq(model.tool_call("r1").parent_id, "agent", "padre del Read")
	assert_eq(model.tool_call("r1").status, ToolCall.STATUS_COMPLETED, "el update del hijo se aplica")
	# El cambio de un hijo avisa al grupo del subagente.
	var touched: Array[ChatEntry] = []
	model.tool_call_changed.connect(func(_call: ToolCall, owner: ChatEntry) -> void: touched.append(owner))
	model.apply_update(sub.call({"sessionUpdate": "tool_call_update", "toolCallId": "r1", "title": "Read x.gd"}, "agent"))
	assert_true(touched.size() == 1 and touched[0] == group, "el hijo avisa con el grupo del Agent")
	# Un pedido de permiso puede crear el tool call antes de saber de qué subagente es.
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "e1", "title": "Edit", "status": "pending"})
	assert_eq(group.tool_call_ids, PackedStringArray(["agent", "e1"]), "el Edit aparece primero suelto")
	model.apply_update(sub.call({"sessionUpdate": "tool_call", "toolCallId": "e1", "title": "Edit", "status": "in_progress"}, "agent"))
	assert_eq(group.tool_call_ids, PackedStringArray(["agent"]), "y pasa al subagente")
	assert_eq(agent.child_ids, PackedStringArray(["r1", "e1"]), "en orden")
	# Un padre que no se vio crea su tool call; un ciclo no se arma.
	model.apply_update(sub.call({"sessionUpdate": "tool_call", "toolCallId": "x1", "status": "pending"}, "ghost"))
	assert_eq(model.tool_call("ghost").child_ids, PackedStringArray(["x1"]), "padre desconocido")
	model.apply_update(sub.call({"sessionUpdate": "tool_call_update", "toolCallId": "agent"}, "r1"))
	assert_eq(agent.parent_id, "", "un hijo no puede ser padre de su subagente")
	# Al cancelar también se marcan los hijos.
	model.apply_update(sub.call({"sessionUpdate": "tool_call", "toolCallId": "r2", "status": "in_progress"}, "agent"))
	model.finish_turn("cancelled")
	assert_eq(model.tool_call("r2").status, ToolCall.STATUS_CANCELLED, "hijo cancelado")


## El historial guarda la marca del subagente y el replay vuelve a armar lo mismo.
func test_subagent_history_round_trip() -> void:
	var history := SessionHistory.new()
	history.begin("s", "p", "Agente", "/tmp")
	var updates: Array[Dictionary] = [
		{"sessionUpdate": "tool_call", "toolCallId": "agent", "title": "Buscar", "status": "in_progress", "_meta": {"claudeCode": {"toolName": "Agent", "extra": 1}}},
		{"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Uno "}, "_meta": {"claudeCode": {"parentToolUseId": "agent"}}},
		{"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "dos"}, "_meta": {"claudeCode": {"parentToolUseId": "agent"}}},
		{"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Listo"}},
		{"sessionUpdate": "tool_call", "toolCallId": "r1", "title": "Read", "status": "completed", "_meta": {"claudeCode": {"parentToolUseId": "agent"}}},
	]
	for update: Dictionary in updates:
		history.record_update(update)
	var events: Array = history.get(&"_pending")
	assert_eq(events.size(), 4, "los chunks del subagente se unen entre sí y no con los del principal")
	assert_eq(events[0].update._meta, {"claudeCode": {"toolName": "Agent"}}, "del _meta queda solo lo necesario")
	var model := SessionModel.new()
	SessionHistory.replay({"events": events}, model)
	assert_eq(model.entries().size(), 2, "grupo + mensaje principal")
	assert_true(model.tool_call("agent").is_subagent(), "Agent sigue siendo subagente")
	assert_eq(model.tool_call("agent").subagent_text, "Uno dos", "texto del subagente")
	assert_eq(model.tool_call("agent").child_ids, PackedStringArray(["r1"]), "hijo")


func test_cancel_marks_unfinished_tool_calls() -> void:
	var model := SessionModel.new()
	model.set_state(SessionModel.SessionState.PROMPTING)
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "a", "status": "completed"})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "b", "status": "in_progress"})
	model.finish_turn("cancelled")
	assert_eq(model.tool_call("a").status, ToolCall.STATUS_COMPLETED, "a sigue completado")
	assert_eq(model.tool_call("b").status, ToolCall.STATUS_CANCELLED, "b cancelado")
	assert_eq(model.state, SessionModel.SessionState.READY, "vuelve a READY")
	assert_eq(model.entries().back().kind, ChatEntry.EntryKind.NOTICE, "aviso de cancelación")


func test_plan_replaces_and_moves() -> void:
	var model := SessionModel.new()
	var removed: Array = []
	model.entry_removed.connect(func(entry: ChatEntry) -> void: removed.append(entry))
	model.apply_update({"sessionUpdate": "plan", "entries": [{"content": "uno", "status": "pending"}]})
	model.apply_update({"sessionUpdate": "plan", "entries": [{"content": "uno", "status": "completed"}, {"content": "dos", "status": "pending"}]})
	assert_eq(model.entries().size(), 1, "el plan se reemplaza en el lugar")
	assert_eq(model.entries()[0].plan.size(), 2, "plan nuevo")
	model.apply_update(_chunk("agent_message_chunk", "texto"))
	model.apply_update({"sessionUpdate": "plan", "entries": [{"content": "tres", "status": "in_progress"}]})
	assert_eq(model.entries().size(), 2, "el plan se mueve al final")
	assert_eq(model.entries().back().kind, ChatEntry.EntryKind.PLAN, "plan al final")
	assert_eq(removed.size(), 1, "se avisó que salió de su lugar viejo")


func test_misc_updates_and_unknown_variant() -> void:
	var model := SessionModel.new()
	assert_true(model.apply_update({"sessionUpdate": "usage_update", "used": 41000, "size": 200000}), "usage")
	assert_eq(model.usage_used, 41000, "used")
	assert_true(model.apply_update({"sessionUpdate": "session_info_update", "title": "Oleadas"}), "title")
	assert_eq(model.title, "Oleadas", "título")
	assert_true(model.apply_update({"sessionUpdate": "available_commands_update", "availableCommands": [{"name": "x"}]}), "commands")
	assert_eq(model.commands.size(), 1, "comandos")
	assert_false(model.apply_update({"sessionUpdate": "algo_nuevo"}), "variante desconocida")
	assert_false(model.apply_update({}), "sin sessionUpdate")
	assert_eq(model.entries().size(), 0, "nada agregado")


func test_content_to_text() -> void:
	assert_eq(SessionModel.content_to_text({"type": "text", "text": "a"}), "a", "text")
	assert_eq(SessionModel.content_to_text({"type": "image", "data": ""}), "[image]", "image")
	assert_eq(SessionModel.content_to_text({"type": "resource_link", "uri": "file:///x", "name": "x"}), "[x](file:///x)", "link")
	assert_eq(SessionModel.content_to_text("raro"), "", "no dict")


## Por godot.run (D56) la tool y sus argumentos son los del método: así el ↶ deshacer de la tarjeta
## y la cuenta del One-shot ven la tool real.
func test_godot_run_unwraps_method() -> void:
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "r", "title": "mcp__godot__run", "kind": "other", "status": "completed",
		"rawInput": {"method": "tilemap_set_cells", "params": {"node_path": "Ground", "cells": []}}})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "d", "title": "mcp__godot__add_node", "kind": "other", "status": "completed",
		"rawInput": {"type": "Node2D"}})
	var run: ToolCall = model.tool_call("r")
	assert_eq(run.godot_tool_name(), "tilemap_set_cells", "nombre del método")
	assert_eq(run.godot_arguments(), {"node_path": "Ground", "cells": []}, "params del método")
	assert_eq(model.tool_call("d").godot_tool_name(), "add_node", "las demás, igual que antes")
	assert_eq(model.tool_call("d").godot_arguments(), {"type": "Node2D"}, "argumentos directos")
	assert_eq(model.find_godot_tool_call("tilemap_set_cells", {"node_path": "Ground", "cells": []}), run, "el deshacer encuentra la llamada por el método")


func test_supports_logout() -> void:
	var model := SessionModel.new()
	model.apply_initialize({"agentCapabilities": {"auth": {"logout": {}}}})
	assert_true(model.supports_logout(), "auth.logout anunciado")
	model.apply_initialize({"agentCapabilities": {"auth": {}}})
	assert_false(model.supports_logout(), "sin logout")
	model.apply_initialize({})
	assert_false(model.supports_logout(), "sin capacidades")


func test_session_capabilities_and_merge() -> void:
	var model := SessionModel.new()
	assert_false(model.can_resume_sessions(), "sin capacidades no reanuda")
	model.apply_initialize({
		"agentCapabilities": {
			"loadSession": false,
			"sessionCapabilities": {
				"list": {},
				"resume": {},
				"close": {},
				"delete": {},
			},
		},
	})
	assert_true(model.supports_list_sessions(), "sessionCapabilities.list")
	assert_true(model.supports_resume_session(), "sessionCapabilities.resume")
	assert_true(model.supports_close_session(), "sessionCapabilities.close")
	assert_true(model.supports_delete_session(), "sessionCapabilities.delete")
	assert_true(model.can_resume_sessions(), "reanuda con sessionCapabilities.resume aunque loadSession sea false")

	var profile := AgentProfile.new()
	profile.id = "claude"
	profile.display_name = "Claude Code"
	var norm := SessionController.normalize_agent_session({
		"sessionId": "sess_remote",
		"cwd": "/tmp/proj",
		"title": "Desde CLI",
		"updatedAt": "2026-04-20T12:00:00Z",
	}, profile)
	assert_eq(norm.id, "sess_remote", "id normalizado")
	assert_eq(norm.title, "Desde CLI", "título normalizado")
	assert_eq(norm.agent, "Claude Code", "agente normalizado")
	assert_true(int(norm.updated) > 0, "updatedAt parseado a unix")

	var local: Array[Dictionary] = [
		{"id": "s1", "title": "", "updated": 100, "turns": 3},
		{"id": "s2", "title": "Local 2", "updated": 300, "turns": 1},
	]
	var remote: Array[Dictionary] = [
		{"id": "s1", "title": "Título del agente", "updated": 250, "turns": 0},
		{"id": "s3", "title": "Remota 3", "updated": 200, "turns": 0},
	]
	var merged := SessionController.merge_session_lists(local, remote, 10)
	assert_eq(merged.size(), 3, "3 sesiones sin duplicar s1")
	assert_eq(merged[0].id, "s2", "más reciente primero (300)")
	assert_eq(merged[1].id, "s1", "s1 con fecha actualizada del agente (250)")
	assert_eq(merged[1].title, "Título del agente", "completa título vacío con el del agente")
	assert_eq(merged[2].id, "s3", "incluye sesión solo remota (200)")
