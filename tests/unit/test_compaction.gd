extends "res://tests/unit/test_case.gd"
## m11-60: la compactación como estado propio (compaction_update), con lo que manda claude-agent-acp
## 0.106 capturado en tests/fixtures/acp/compaction_0106.json.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const FIXTURE := "res://tests/fixtures/acp/compaction_0106.json"


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _summary() -> String:
	return SessionModel.compaction_summary(_fixture().live[1].summary)


func test_announces_capability() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	var caps := controller.client_capabilities()
	assert_true(caps.get("session") is Dictionary and caps.session.get("compaction") is Dictionary, "anuncia session.compaction")
	assert_eq(_fixture().client_capabilities.session, caps.session, "como en la captura")


func test_live_updates_make_one_row() -> void:
	var model := SessionModel.new()
	var seen: Array[String] = []
	model.compaction_changed.connect(func(_entry: ChatEntry, status: String) -> void: seen.append(status))
	model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "antes"}})
	assert_true(model.apply_update(_fixture().live[0]), "compaction_update es conocido")
	assert_eq(model.entries().back().text, "Compacting the conversation…", "en curso")
	assert_eq(model.entries().back().details, "", "sin resumen todavía")
	for update: Dictionary in _fixture().live.slice(1):
		model.apply_update(update)
	assert_eq(seen, ["in_progress", "completed", "completed"] as Array[String], "cada estado se avisa")
	assert_eq(model.entries().size(), 2, "una sola fila por compactionId")
	var row: ChatEntry = model.entries().back()
	assert_eq(row.kind, ChatEntry.EntryKind.NOTICE, "una fila de aviso")
	assert_true(row.text.begins_with("Conversation compacted"), "completada")
	assert_eq(row.details, _summary(), "el completed repetido sin summary no borra el resumen")
	assert_true(row.details.contains("lantern"), "el resumen de la captura")
	assert_eq(row.details_title, "Summary the agent kept", "plegado con su título")
	assert_true(row.actions.is_empty(), "el modelo no ofrece el traspaso: eso lo decide el dock")
	model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "después"}})
	assert_eq(model.entries().size(), 3, "lo que sigue va después de la fila, no se pega al mensaje de antes")


func test_failed_and_cancelled() -> void:
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "compaction_update", "compactionId": "a", "status": "in_progress"})
	model.apply_update({"sessionUpdate": "compaction_update", "compactionId": "a", "status": "failed"})
	assert_eq(model.entries().back().text, "The agent couldn't compact the conversation.", "falló")
	assert_eq(model.entries().back().level, ChatEntry.NoticeLevel.WARNING, "como advertencia")
	model.apply_update({"sessionUpdate": "compaction_update", "compactionId": "b", "status": "cancelled"})
	assert_eq(model.entries().back().text, "Compaction cancelled.", "cancelada")
	assert_eq(model.entries().size(), 2, "una fila por compactación")
	model.reset()
	model.apply_update({"sessionUpdate": "compaction_update", "compactionId": "a", "status": "completed"})
	assert_eq(model.entries().size(), 1, "reset olvida las filas viejas")


func test_history_records_final_state_and_replays() -> void:
	var history := SessionHistory.new()
	history.set(&"_meta", {"id": "session-0001", "events_count": 0, "truncated": false})
	for update: Dictionary in _fixture().live:
		history.record_update(update)
	var events: Array = history.get(&"_pending")
	assert_eq(events.size(), 1, "solo el estado final, una vez")
	assert_eq(str(events[0].update.status), "completed", "completed")
	assert_eq(SessionModel.compaction_summary(events[0].update.summary), _summary(), "con el resumen")
	var model := SessionModel.new()
	var replaying: Array[bool] = []
	var watch := func(_entry: ChatEntry, _status: String) -> void: replaying.append(model.replaying)
	model.compaction_changed.connect(watch)
	SessionHistory.replay({"events": [{"type": "user", "text": "hola"}] + events}, model)
	model.compaction_changed.disconnect(watch)  # la lambda tiene al modelo: sin esto no se libera
	assert_eq(model.entries().size(), 2, "la fila vuelve al reabrir")
	assert_eq(model.entries().back().details, _summary(), "con el resumen")
	assert_eq(replaying, [true] as Array[bool], "el dock sabe que es una reproducción")


func test_load_replay_keeps_position() -> void:
	var model := SessionModel.new()
	for update: Dictionary in _fixture().load_replay:
		model.apply_update(update)
	var kinds: Array = model.entries().map(func(entry: ChatEntry) -> int: return entry.kind)
	assert_eq(kinds, [ChatEntry.EntryKind.USER, ChatEntry.EntryKind.AGENT, ChatEntry.EntryKind.NOTICE, ChatEntry.EntryKind.USER, ChatEntry.EntryKind.AGENT], "la compactación queda entre los mensajes")
