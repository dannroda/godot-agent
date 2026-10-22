extends "test_case.gd"
## SessionModel: merge de chunks, tool calls, plan, variantes desconocidas y cancelación.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")


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
