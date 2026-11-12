extends "test_case.gd"
## m18-04, de punta a punta con el FsHandler real: la traza de Antigravity al denegar la segunda de
## dos ediciones (la primera ya escrita por fs/write_text_file llega después como failed).

const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")
const FsHandler := preload("res://addons/godot_agent/acp/fs_handler.gd")


func _update(controller: SessionController, update: Dictionary) -> void:
	controller.client.receive_line(JSON.stringify({"jsonrpc": "2.0", "method": "session/update",
		"params": {"sessionId": "s", "update": update}}))


func test_edit_written_then_failed_stays_completed() -> void:
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	var root_dir := ProjectSettings.globalize_path(temp_dir("write_applied"))
	controller.setup(model, log, root_dir)
	var fs := FsHandler.new()
	fs.setup(root_dir, log)
	controller.set_fs_handler(fs)
	model.session_id = "s"
	var target := root_dir.path_join("player.gd")
	_update(controller, {"sessionUpdate": "tool_call", "toolCallId": "a", "title": "Running client_edit_file", "kind": "edit",
		"status": "in_progress", "locations": [{"path": target}],
		"content": [{"type": "diff", "path": target, "oldText": "", "newText": "extends Node\n"}]})
	controller.client.receive_line(JSON.stringify({"jsonrpc": "2.0", "id": 7, "method": "fs/write_text_file",
		"params": {"sessionId": "s", "path": target, "content": "extends Node\n"}}))
	for i in 3:
		await Engine.get_main_loop().process_frame
	if not model.pending_permissions.is_empty():
		var card: SessionModel.PermissionRequest = model.pending_permissions[0]
		card.select(card.option_id_for(PackedStringArray([SessionModel.PermissionRequest.KIND_ALLOW_ONCE])))
		for i in 3:
			await Engine.get_main_loop().process_frame
	assert_eq(FileAccess.get_file_as_string(target), "extends Node\n", "el archivo se escribió")
	assert_eq(model.tool_call("a").write_applied, target, "la edición quedó marcada como aplicada")
	_update(controller, {"sessionUpdate": "tool_call_update", "toolCallId": "a", "status": "failed",
		"rawOutput": "Denied by user (*). (\"denied by pre-tool hook: Denied by user (*).\")"})
	var call := model.tool_call("a")
	assert_eq(call.status, ToolCall.STATUS_COMPLETED, "no se muestra fallida")
	assert_true(call.failure_after_write.contains("Denied by user"), "y guarda el aviso del agente")
	var logged := false
	for entry: Dictionary in log.entries():
		logged = logged or str(entry.get("text", entry)).contains("write applied for tool call a")
	assert_true(logged, "el log del agente lo registra")
