extends SceneTree
## Integración M1 contra el agente falso: proceso real, stdio, ACP y SessionModel, sin editor.
## Uso: godot --headless --path <repo> --script tests/acp_session_check.gd
## Escenarios: prompt con streaming, cancelación limpia y caída del agente.

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")

const TIMEOUT_S := 20.0
## Un await colgado no debe colgar el test: pasado este tiempo, falla y sale.
const WATCHDOG_S := 90.0

var _failures: PackedStringArray = []
var _checks: int = 0


func _initialize() -> void:
	await process_frame
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		printerr("FAIL acp_session_check: watchdog (%d s)" % WATCHDOG_S)
		quit(1)
	)
	await _scenario_basic()
	await _scenario_cancel()
	await _scenario_crash()
	for failure: String in _failures:
		printerr("FAIL " + failure)
	print("acp_session_check: %d checks, %d fallos (%s)" % [_checks, _failures.size(), Engine.get_version_info().string])
	quit(1 if not _failures.is_empty() else 0)


func _fake_profile(scenario: String) -> AgentProfile:
	return AgentProfile.from_dict({
		"id": "fake",
		"display_name": "Agente falso",
		"command": OS.get_executable_path(),
		"args": [
			"--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario,
		],
	})


func _make(scenario: String) -> Array:
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, ProjectSettings.globalize_path("res://"))
	var ok: bool = await controller.start(_fake_profile(scenario))
	_check(ok, "%s: la sesión arranca (%s)" % [scenario, model.failure_message])
	return [controller, model, log]


func _scenario_basic() -> void:
	print("— basic")
	var made := await _make("basic")
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	_check(model.state == SessionModel.State.READY, "basic: READY")
	_check(not model.session_id.is_empty(), "basic: sessionId")
	_check(model.config_option("model").get("currentValue") == "fake-large", "basic: configOptions")
	await _wait_until(func() -> bool: return model.commands.size() == 2)
	_check(model.commands.size() == 2, "basic: available_commands_update")

	var updates: Array[int] = [0]
	model.entry_updated.connect(func(_e: ChatEntry) -> void: updates[0] += 1)
	var stop_reason: String = await controller.send_prompt("hola")
	_check(stop_reason == "end_turn", "basic: stopReason end_turn (%s)" % stop_reason)
	var agent_text := ""
	var thought_count := 0
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.Kind.AGENT:
			agent_text += entry.text
		elif entry.kind == ChatEntry.Kind.THOUGHT:
			thought_count += 1
	_check(agent_text == "¡Hola! Soy el **agente falso**. Respondo con `streaming`.", "basic: texto unido (%s)" % agent_text)
	_check(updates[0] >= 2, "basic: llegó en streaming (%d updates)" % updates[0])
	_check(thought_count == 1, "basic: un thought")
	_check(model.title == "Saludo de prueba", "basic: título")
	_check(model.usage_used == 1200 and model.usage_size == 200000, "basic: usage")
	_check(model.state == SessionModel.State.READY, "basic: vuelve a READY")
	_check(_log_has(log, "línea ignorada"), "basic: la línea no JSON se loguea")
	_check(_log_has(log, "desconocida, ignorada"), "basic: la variante desconocida se loguea")
	_check(_log_has(log, "fake_agent: prompt") and _log_has(log, "harness_context"), "basic: el primer prompt lleva el contexto del harness")

	# El cambio de modo del harness se refleja en el modo del agente.
	model.set_harness_mode(SessionModel.HarnessMode.ASK)
	await _wait_until(func() -> bool: return model.current_agent_mode == "plan")
	_check(model.current_agent_mode == "plan", "basic: Preguntar → modo plan del agente")

	var changed: bool = await controller.set_config_option("model", "fake-small")
	_check(changed and model.config_option("model").currentValue == "fake-small", "basic: set_config_option")

	var pid := _pid_of(controller)
	controller.stop()
	_check(model.state == SessionModel.State.DISCONNECTED, "basic: DISCONNECTED al detener")
	_check(pid > 0 and not _pid_alive(pid), "basic: el proceso murió")


func _scenario_cancel() -> void:
	print("— cancel")
	var made := await _make("cancel")
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var result: Array = [""]
	var run := func() -> void:
		result[0] = await controller.send_prompt("algo largo")
	run.call()
	await _wait_until(func() -> bool: return model.tool_call("t1") != null)
	await create_timer(0.3).timeout
	controller.cancel()
	_check(model.state == SessionModel.State.CANCELLING, "cancel: CANCELLING")
	await _wait_until(func() -> bool: return result[0] != "")
	_check(result[0] == "cancelled", "cancel: stopReason cancelled (%s)" % result[0])
	_check(model.state == SessionModel.State.READY, "cancel: vuelve a READY")
	_check(model.tool_call("t1").status == "cancelled", "cancel: tool call sin terminar → cancelled")
	var all_text := ""
	for entry: ChatEntry in model.entries():
		all_text += entry.text
	_check(not all_text.contains("no tendría que llegar"), "cancel: no siguió el streaming")
	var second: String = await controller.send_prompt("otra vez")
	_check(second == "end_turn", "cancel: el turno siguiente funciona")
	controller.stop()


func _scenario_crash() -> void:
	print("— crash")
	var made := await _make("crash")
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var result: String = await controller.send_prompt("caete")
	_check(result == "error", "crash: el prompt termina con error (%s)" % result)
	await _wait_until(func() -> bool: return model.state == SessionModel.State.FAILED)
	_check(model.state == SessionModel.State.FAILED, "crash: FAILED")
	var notice: ChatEntry = model.entries().back()
	_check(notice.kind == ChatEntry.Kind.NOTICE and notice.level == ChatEntry.Level.ERROR, "crash: aviso de error")
	_check(notice.actions.size() == 2, "crash: con acciones Reintentar / Ver log")
	# Reintentar reabre una sesión limpia.
	var ok: bool = await controller.start(controller.profile())
	_check(ok and model.state == SessionModel.State.READY, "crash: reintentar")
	controller.stop()


# --- helpers -------------------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _log_has(log: AgentLog, text: String) -> bool:
	for entry: Dictionary in log.entries():
		if str(entry.message).contains(text) or str(entry.raw).contains(text):
			return true
	return false


## OS.is_process_running da error con un pid ya cosechado; se mira /proc (Linux) o `kill -0`.
func _pid_alive(pid: int) -> bool:
	if DirAccess.dir_exists_absolute("/proc/self"):
		return DirAccess.dir_exists_absolute("/proc/%d" % pid)
	return OS.execute("kill", ["-0", str(pid)]) == 0


func _pid_of(controller: SessionController) -> int:
	var process: Variant = controller.get(&"_process")
	return process.pid() if process else 0


func _wait_until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_S * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
