extends "test_case.gd"
## Varias sesiones abiertas a la vez (m7-44): archivos por turno, el juego de a una, la sesión que
## llama a una tool godot.* y el canal entre sesiones.

const SessionCoordinator := preload("res://addons/godot_agent/session/session_coordinator.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const SessionTools := preload("res://addons/godot_agent/mcp/tools/session_tools.gd")

const OPTIONS := [
	{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
	{"optionId": "reject", "name": "Reject", "kind": "reject_once"},
]


func _coordinator() -> SessionCoordinator:
	var coordinator := SessionCoordinator.new()
	coordinator.register("s1", "Session 1")
	coordinator.register("s2", "Session 2")
	return coordinator


func test_files_per_turn() -> void:
	var coordinator := SessionCoordinator.new()
	coordinator.register("s1", "Session 1")
	assert_true(not coordinator.is_shared(), "con una sola no hay nada que coordinar")
	coordinator.register("s2", "Session 2")
	assert_true(coordinator.is_shared(), "dos sesiones")
	assert_eq(coordinator.claim_files("s1", ["res://player.gd"]), {}, "la primera lo toma")
	assert_eq(coordinator.claim_files("s1", ["res://player.gd"]), {}, "la misma puede seguir")
	var abs_path := ProjectSettings.globalize_path("res://player.gd")
	assert_eq(coordinator.claim_files("s2", [abs_path, "res://enemy.gd"]), {abs_path: "s1"}, "la otra no, aunque lo nombre con ruta absoluta")
	assert_eq(coordinator.files_of("s2"), PackedStringArray(), "si una es ajena no toma ninguna")
	assert_eq(coordinator.claim_files("s2", ["res://enemy.gd"]), {}, "otro archivo sí")
	coordinator.release_files("s1")
	assert_eq(coordinator.claim_files("s2", ["res://player.gd"]), {}, "al terminar el turno queda libre")
	coordinator.unregister("s2")
	assert_eq(coordinator.files_of("s2"), PackedStringArray(), "cerrar la sesión suelta lo suyo")
	assert_eq(coordinator.claim_files("s1", ["res://enemy.gd"]), {}, "y otra lo puede tomar")
	assert_eq(SessionCoordinator.paths_in_args({"scene": "res://a.tscn", "paths": ["res://b.gd", 3], "name": "x"}), PackedStringArray(["res://a.tscn", "res://b.gd"]), "rutas en los argumentos")


func test_game_queue() -> void:
	var coordinator := _coordinator()
	var running := [false]
	coordinator.is_game_running = func() -> bool: return running[0]
	assert_eq(await coordinator.acquire_game("s1", 0.1), "", "libre: la toma")
	running[0] = true
	assert_eq(coordinator.game_owner(), "s1", "es suyo mientras corre")
	assert_eq(await coordinator.acquire_game("s2", 0.3), "s1", "la otra espera y vence")
	running[0] = false
	assert_eq(coordinator.game_owner(), "", "cuando se detiene, nadie")


func test_game_waits_for_owner() -> void:
	var coordinator := _coordinator()
	var running := [true]
	coordinator.is_game_running = func() -> bool: return running[0]
	await coordinator.acquire_game("s1", 0.1)
	(Engine.get_main_loop() as SceneTree).create_timer(0.3).timeout.connect(func() -> void: running[0] = false)
	var started := Time.get_ticks_msec()
	assert_eq(await coordinator.acquire_game("s2", 3.0), "", "la toma cuando el juego se detiene")
	assert_true(Time.get_ticks_msec() - started >= 250, "esperó en la cola")
	running[0] = true
	assert_eq(coordinator.game_owner(), "s2", "ahora es de s2")


func test_registry_guard_and_caller() -> void:
	var registry := ToolRegistry.new()
	var seen: Array[String] = []
	registry.register(McpTool.create("write", "edit_files", "Escribe", {"path": {"type": "string"}}, ["path"], func(_args: Dictionary) -> String:
		seen.append(registry.current_caller)
		return "ok"))
	registry.guard = func(caller: String, tool_name: String, args: Dictionary) -> String:
		return "taken by Session 1" if caller == "s2" and tool_name == "write" and args.path == "res://a.gd" else ""
	var authorized: Array[String] = []
	registry.session_authorizer = func(caller: String, group: String, _title: String, _description: String) -> bool:
		authorized.append("%s:%s" % [caller, group])
		return true
	var result: Dictionary = await registry.call_tool("write", {"path": "res://a.gd"}, "s2")
	assert_true(result.isError and str(result.content[0].text).contains("taken by Session 1"), "la guarda la frena con su motivo")
	result = await registry.call_tool("write", {"path": "res://a.gd"})
	assert_true(not result.isError, "la primera sesión pasa")
	assert_eq(seen, ["" as String], "el handler ve quién llama")
	assert_eq(authorized, ["s2:edit_files", ":edit_files"] as Array[String], "permiso con la sesión que llama")
	assert_eq(registry.group_of("write"), "edit_files", "grupo de una tool")


func test_controller_file_guard() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	controller.model.set_harness_mode(SessionModel.HarnessMode.AUTO)
	controller.file_guard = func(paths: PackedStringArray) -> String: return "Session 1" if "/tmp/project/a.gd" in paths else ""
	controller.model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "e1", "title": "Edit a.gd", "kind": "edit", "status": "pending",
		"rawInput": {"file_path": "/tmp/project/a.gd"}})
	var result: Variant = controller.permissions.call(&"on_request_permission", {"sessionId": "s", "toolCall": {"toolCallId": "e1", "kind": "edit"}, "options": OPTIONS})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "otra sesión lo está editando")
	var notices := controller.model.entries().filter(func(entry: Variant) -> bool: return entry.kind == SessionModel.ChatEntry.EntryKind.NOTICE)
	assert_true(not notices.is_empty() and str(notices.back().text).contains("Session 1"), "avisa quién lo tiene")
	assert_true(not await controller.permissions.authorize_fs_write("/tmp/project/a.gd", "", "x"), "tampoco por fs/write_text_file")
	controller.model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "e2", "title": "Edit b.gd", "kind": "edit", "status": "pending",
		"rawInput": {"file_path": "/tmp/project/b.gd"}})
	result = controller.permissions.call(&"on_request_permission", {"sessionId": "s", "toolCall": {"toolCallId": "e2", "kind": "edit"}, "options": OPTIONS})
	assert_eq(str(result.outcome.get("optionId", "")), "allow", "un archivo libre sigue la política del modo")


func test_session_tools() -> void:
	var tools := SessionTools.new()
	var sent: Array = []
	tools.caller = func() -> String: return "s2"
	tools.describe = func(caller: String) -> String: return "seen from %s" % caller
	tools.send = func(caller: String, to: String, message: String) -> String:
		if to != "Session 1":
			return "no such session"
		sent.append([caller, to, message])
		return ""
	var by_name: Dictionary = {}
	for tool: McpTool in tools.tools():
		by_name[tool.name] = tool
	assert_eq(by_name.sessions.handler.call({}).content[0].text, "seen from s2", "sessions, desde quien llama")
	var ok: Dictionary = by_name.session_send.handler.call({"to": "Session 1", "message": " I'm on the HUD "})
	assert_true(not ok.isError, "entregado")
	assert_eq(sent, [["s2", "Session 1", "I'm on the HUD"]], "con el mensaje limpio")
	assert_true(by_name.session_send.handler.call({"to": "Session 9", "message": "hi"}).isError, "a una que no existe, error")
	assert_true(by_name.session_send.handler.call({"to": "Session 1", "message": "  "}).isError, "vacío, error")


func test_notice_for_work_outside_a_turn() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	var model := controller.model
	model.session_id = "s"
	model.set_state(SessionModel.SessionState.READY)
	var notices := func() -> int: return model.entries().filter(func(e: Variant) -> bool: return e.kind == e.EntryKind.NOTICE).size()
	var chunk := func(kind: String, text: String) -> void:
		controller.call(&"_on_session_update", {"sessionId": "s", "update": {"sessionUpdate": kind, "content": {"type": "text", "text": text}}})
	chunk.call("agent_message_chunk", "Got it, ")
	chunk.call("agent_message_chunk", "replying.")
	assert_eq(notices.call(), 1, "un aviso por tanda, con el mensaje que no llegó")
	controller.call(&"_on_session_update", {"sessionId": "s", "update": {"sessionUpdate": "tool_call", "toolCallId": "b1", "title": "Bash", "_meta": {"claudeCode": {"parentToolUseId": "a1"}}}})
	assert_eq(notices.call(), 1, "lo de un subagente no cuenta")
	controller.set(&"_outside_turn_noticed", false)
	chunk.call("user_message_chunk", "from the phone")
	chunk.call("agent_message_chunk", "ok")
	assert_eq(notices.call(), 1, "Remote Control trae el mensaje: sin aviso")
	controller.set(&"_outside_turn_noticed", false)
	model.set_state(SessionModel.SessionState.PROMPTING)
	chunk.call("agent_message_chunk", "in a turn")
	assert_eq(notices.call(), 1, "dentro de un turno pedido, sin aviso")
