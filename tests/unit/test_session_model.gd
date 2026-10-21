extends "test_case.gd"
## SessionModel: merge de chunks, tool calls, plan, variantes desconocidas y cancelación.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")


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
	assert_eq(model.entries()[0].kind, ChatEntry.Kind.THOUGHT, "primero el thought")
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
	assert_eq(group.kind, ChatEntry.Kind.TOOL_GROUP, "grupo de tools")
	assert_eq(group.tool_call_ids, PackedStringArray(["a", "b"]), "ids en orden")
	assert_eq(model.tool_call("a").status, "completed", "a completado")
	assert_eq(model.tool_call("b").diffs().size(), 1, "b tiene un diff")
	assert_eq(model.tool_call("a").title, "Read", "el update conserva el título")
	# Un mensaje en el medio corta el grupo.
	model.apply_update(_chunk("agent_message_chunk", "listo", "m9"))
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "c", "title": "Bash", "status": "in_progress"})
	assert_eq(model.entries().size(), 4, "un update de id nuevo abre otro grupo")


func test_cancel_marks_unfinished_tool_calls() -> void:
	var model := SessionModel.new()
	model.set_state(SessionModel.State.PROMPTING)
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "a", "status": "completed"})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "b", "status": "in_progress"})
	model.finish_turn("cancelled")
	assert_eq(model.tool_call("a").status, ToolCall.STATUS_COMPLETED, "a sigue completado")
	assert_eq(model.tool_call("b").status, ToolCall.STATUS_CANCELLED, "b cancelado")
	assert_eq(model.state, SessionModel.State.READY, "vuelve a READY")
	assert_eq(model.entries().back().kind, ChatEntry.Kind.NOTICE, "aviso de cancelación")


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
	assert_eq(model.entries().back().kind, ChatEntry.Kind.PLAN, "plan al final")
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
	assert_eq(SessionModel.content_to_text({"type": "image", "data": ""}), "[imagen]", "image")
	assert_eq(SessionModel.content_to_text({"type": "resource_link", "uri": "file:///x", "name": "x"}), "[x](file:///x)", "link")
	assert_eq(SessionModel.content_to_text("raro"), "", "no dict")
