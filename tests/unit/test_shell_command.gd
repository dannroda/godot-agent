extends "test_case.gd"
## Comandos de shell con el formato de cada agente (m17-24): Antigravity manda rawInput.CommandLine
## (y command_line) y solo ofrece «una vez».

const ShellCommand := preload("res://addons/godot_agent/session/shell_command.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

const OPTIONS := [
	{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
	{"optionId": "reject", "name": "Reject", "kind": "reject_once"},
]


func test_command_keys() -> void:
	assert_eq(ShellCommand.of({"command": "ls"}), "ls", "Claude Code")
	assert_eq(ShellCommand.of({"CommandLine": "cat a", "Cwd": "/x"}), "cat a", "Antigravity")
	assert_eq(ShellCommand.of({"command_line": "cat b"}), "cat b", "Antigravity, update")
	assert_eq(ShellCommand.of({"command": ["git", "status"]}), "git status", "lista de argumentos")
	assert_eq(ShellCommand.of({"path": "a.gd"}), "", "sin comando")
	assert_eq(ShellCommand.of(null), "", "sin rawInput")


func _ask(controller: SessionController, id: String, raw: Dictionary) -> Variant:
	return await controller.permissions.call(&"on_request_permission", {"sessionId": "s", "toolCall": {"toolCallId": id, "kind": "execute", "title": "x", "rawInput": raw}, "options": OPTIONS})


func test_antigravity_shell_permissions() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	controller.model.set_harness_mode(SessionModel.HarnessMode.AUTO)
	var result: Variant = await _ask(controller, "x1", {"CommandLine": "cat a.tres b.gdshader", "Cwd": "/tmp/project"})
	assert_eq(str(result.outcome.get("optionId", "")), "allow", "cat está en la allowlist: pasa sin tarjeta")
	assert_true(controller.model.pending_permissions.is_empty(), "sin tarjeta")
	result = await _ask(controller, "x2", {"command_line": "echo hi > /tmp/project/main.tscn"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "escribir una escena desde la shell se bloquea también con command_line")

	# Auto, un comando fuera de la allowlist: la tarjeta propone una regla.
	var answers: Array = []
	var ask_rule := func() -> void: answers.append(await _ask(controller, "x3", {"CommandLine": "npm test"}))
	ask_rule.call()
	assert_eq(controller.model.pending_permissions.size(), 1, "npm test pregunta")
	var request: PermissionRequest = controller.model.pending_permissions[0]
	assert_eq(request.rule_pattern, "npm test", "propone la regla con el comando de Antigravity")
	assert_true(request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty(), "en Auto no abre toda la shell")
	request.select("reject")
	var tree := Engine.get_main_loop() as SceneTree
	for i in 3:
		await tree.process_frame

	# Build: pregunta, y la tarjeta trae «siempre en esta sesión» aunque el agente no lo ofrezca.
	controller.model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	var ask_build := func() -> void: answers.append(await _ask(controller, "x4", {"CommandLine": "npm run build"}))
	ask_build.call()
	assert_eq(controller.model.pending_permissions.size(), 1, "en Build pregunta")
	request = controller.model.pending_permissions[0]
	var always := request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS])
	assert_false(always.is_empty(), "ofrece recordar: %s" % [request.options])
	request.select(always)
	for i in 3:
		await tree.process_frame
	assert_eq(answers.size(), 2, "las dos tarjetas respondieron")
	assert_eq(str(answers[1].outcome.get("optionId", "")), "allow", "al agente se le contesta «una vez»")
	result = await _ask(controller, "x5", {"CommandLine": "npm run lint"})
	assert_eq(str(result.outcome.get("optionId", "")), "allow", "el resto de la sesión ya no pregunta")
