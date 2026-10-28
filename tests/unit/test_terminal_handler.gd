extends "test_case.gd"
## Terminales ACP (m11-15): terminal/create, output, wait_for_exit, kill, release y política.

const TerminalHandler := preload("res://addons/godot_agent/acp/terminal_handler.gd")
const AcpClient := preload("res://addons/godot_agent/acp/acp_client.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")


func test_utf8_boundary_truncation() -> void:
	# "aé🚀b": 'a' (1B) + 'é' (2B) + '🚀' (4B) + 'b' (1B) = 8 bytes
	var buf := "aé🚀b".to_utf8_buffer()
	assert_eq(buf.size(), 8, "8 bytes UTF-8")
	var no_trunc := TerminalHandler.truncate_utf8_prefix(buf, 8)
	assert_false(bool(no_trunc.truncated), "cabe en 8 bytes")
	assert_eq(no_trunc.text, "aé🚀b", "texto completo")

	# Límite de 4 bytes corta en medio de '🚀' (offset 4 es continuación): salta hasta 'b' (1 byte).
	var mid_emoji := TerminalHandler.truncate_utf8_prefix(buf, 4)
	assert_true(bool(mid_emoji.truncated), "truncado")
	assert_eq(mid_emoji.text, "b", "respeta borde de carácter UTF-8")

	# Límite de 5 bytes empieza justo en el inicio de '🚀' (offset 3): conserva "🚀b".
	var at_emoji := TerminalHandler.truncate_utf8_prefix(buf, 5)
	assert_true(bool(at_emoji.truncated), "truncado en 5")
	assert_eq(at_emoji.text, "🚀b", "conserva emoji entero")


func test_create_wait_output_and_release() -> void:
	if OS.get_name() == "Windows":
		return
	var root := ProjectSettings.globalize_path(temp_dir("term_run")).simplify_path().trim_suffix("/")
	var handler := TerminalHandler.new()
	handler.setup(root, AgentLog.new())
	var created: Variant = await handler.create_terminal({
		"sessionId": "s1",
		"command": "printf 'hola %s' \"$TERM_TEST_VAR\"",
		"cwd": root,
		"env": [{"name": "TERM_TEST_VAR", "value": "mundo"}],
	})
	assert_true(created is Dictionary and str(created.get("terminalId", "")).begins_with("term_"), "terminalId creado")
	var tid := str((created as Dictionary).get("terminalId", ""))
	var exit_res: Variant = await handler.wait_for_exit({"sessionId": "s1", "terminalId": tid})
	assert_eq((exit_res as Dictionary).get("exitCode"), 0, "exitCode 0")
	var out_res: Variant = handler.terminal_output({"sessionId": "s1", "terminalId": tid})
	assert_eq((out_res as Dictionary).get("output"), "hola mundo", "salida capturada con env")
	assert_false(bool((out_res as Dictionary).get("truncated")), "no truncado")
	assert_eq(((out_res as Dictionary).get("exitStatus") as Dictionary).get("exitCode"), 0, "exitStatus incluido")

	var rel_res: Variant = handler.release_terminal({"sessionId": "s1", "terminalId": tid})
	assert_eq(rel_res, {}, "release ok")
	assert_eq(handler.output_of(tid), "hola mundo", "conserva la salida para la tarjeta tras release")
	var after_rel: Variant = handler.terminal_output({"sessionId": "s1", "terminalId": tid})
	assert_true(after_rel is AcpClient.AcpResponse and not after_rel.ok, "terminal/output falla tras release")


func test_kill_running_terminal() -> void:
	if OS.get_name() == "Windows":
		return
	var root := ProjectSettings.globalize_path(temp_dir("term_kill")).simplify_path().trim_suffix("/")
	var handler := TerminalHandler.new()
	handler.setup(root, AgentLog.new())
	var created: Variant = await handler.create_terminal({
		"sessionId": "s1",
		"command": "sleep",
		"args": ["10"],
		"cwd": root,
	})
	var tid := str((created as Dictionary).get("terminalId", ""))
	assert_eq(handler.active_count(), 1, "un proceso corriendo")
	var kill_res: Variant = handler.kill_terminal({"sessionId": "s1", "terminalId": tid})
	assert_eq(kill_res, {}, "kill ok")
	var exit_res: Variant = await handler.wait_for_exit({"sessionId": "s1", "terminalId": tid})
	assert_eq((exit_res as Dictionary).get("signal"), "SIGTERM", "señal SIGTERM al matar")
	handler.release_terminal({"sessionId": "s1", "terminalId": tid})


func test_controller_policy_and_model_sync() -> void:
	var root := ProjectSettings.globalize_path(temp_dir("term_policy")).simplify_path().trim_suffix("/")
	var model := SessionModel.new()
	var controller := SessionController.new()
	var log_sink := AgentLog.new()
	controller.setup(model, log_sink, root)
	var handler := TerminalHandler.new()
	handler.setup(root, log_sink)
	controller.set_terminal_handler(handler)
	assert_true(bool(controller.client_capabilities().get("terminal", false)), "anuncia clientCapabilities.terminal")

	# Fuera del proyecto se rechaza.
	var outside: Variant = await handler.create_terminal({"sessionId": "s1", "command": "pwd", "cwd": "/tmp"})
	assert_true(outside is AcpClient.AcpResponse and not outside.ok, "cwd fuera del proyecto rechazado")

	# Escribir una escena por shell se bloquea en cualquier modo (D48).
	model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
	var write_scene: Variant = await handler.create_terminal({"sessionId": "s1", "command": "echo x > level.tscn", "cwd": root})
	assert_true(write_scene is AcpClient.AcpResponse and not write_scene.ok, "escritura de .tscn bloqueada")

	# En modo Ask se niega la shell.
	model.set_harness_mode(SessionModel.HarnessMode.ASK)
	var denied: Variant = await handler.create_terminal({"sessionId": "s1", "command": "pwd", "cwd": root})
	assert_true(denied is AcpClient.AcpResponse and not denied.ok, "denegado en modo Ask")

	# Sincronización con bloques {type: "terminal", terminalId} del modelo.
	model.apply_update({
		"sessionUpdate": "tool_call",
		"toolCallId": "tc_term",
		"title": "Run command",
		"kind": "execute",
		"status": "in_progress",
		"content": [{"type": "terminal", "terminalId": "term_99"}],
	})
	model.set_terminal_output("term_99", "línea 1\nlínea 2", 0)
	var call := model.tool_call("tc_term")
	assert_eq((call.content[0] as Dictionary).get("output"), "línea 1\nlínea 2", "salida inyectada en el bloque terminal")
	assert_eq((call.content[0] as Dictionary).get("exitCode"), 0, "exitCode inyectado en el bloque terminal")


## Los args se citan como se ejecutan (literal) y las variables del agente siempre se preguntan.
func test_quoting_and_agent_env_ask() -> void:
	assert_eq(TerminalHandler.format_command_line("cp", PackedStringArray(["-b", "--suffix='", "a b", "x.tscn"])), "cp -b '--suffix='\\''' 'a b' x.tscn", "comillas simples POSIX")
	assert_eq(TerminalHandler.shell_quote(""), "''", "arg vacío")
	var root := ProjectSettings.globalize_path(temp_dir("term_env")).simplify_path().trim_suffix("/")
	var model := SessionModel.new()
	var controller := SessionController.new()
	var log_sink := AgentLog.new()
	controller.setup(model, log_sink, root)
	var handler := TerminalHandler.new()
	handler.setup(root, log_sink)
	controller.set_terminal_handler(handler)
	model.set_harness_mode(SessionModel.HarnessMode.AUTO)
	var plain: Variant = await handler.create_terminal({"sessionId": "s1", "command": "ls", "args": ["-la"], "cwd": root})
	assert_true(plain is Dictionary, "ls -la permitido por Auto sin preguntar")
	var results: Array = []
	var run := func() -> void:
		results.append(await handler.create_terminal({"sessionId": "s1", "command": "ls", "args": ["-la"], "cwd": root,
			"env": [{"name": "LD_PRELOAD", "value": "/tmp/x.so"}]}))
	run.call()
	assert_eq(model.pending_permissions.size(), 1, "con env pregunta aunque la regla lo permita")
	var request: PermissionRequest = model.pending_permissions[0]
	assert_true(request.description.begins_with("LD_PRELOAD=/tmp/x.so ls -la"), "la tarjeta muestra las variables")
	assert_true(request.rule_pattern.is_empty(), "sin regla propuesta: no vería las variables")
	request.cancel()
	await Engine.get_main_loop().process_frame
	assert_true(results.size() == 1 and results[0] is AcpClient.AcpResponse and not results[0].ok, "denegado al cancelar")
	handler.stop_all()
