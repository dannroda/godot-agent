extends SceneTree
## Integración M1 contra el agente falso: proceso real, stdio, ACP y SessionModel, sin editor.
## Uso: godot --headless --path <repo> --script tests/acp_session_check.gd
## Escenarios: prompt con streaming, cancelación limpia, caída del agente, permisos, cuota, historial
## y login (ACP auth de tipo terminal).

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const FsHandler := preload("res://addons/godot_agent/acp/fs_handler.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const ShellRules := preload("res://addons/godot_agent/session/shell_rules.gd")
const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const EditorBinary := preload("res://addons/godot_agent/transport/editor_binary.gd")
const TMP_DIR := "res://tests/tmp"

const TIMEOUT_S := 20.0
## Un await colgado no debe colgar el test: pasado este tiempo, falla y sale.
const WATCHDOG_S := 120.0

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
	await _scenario_permissions_build()
	await _scenario_permissions_ask()
	await _scenario_project_writes()
	await _scenario_auto_shell()
	await _scenario_quota()
	await _scenario_history()
	await _scenario_login()
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


func _make(scenario: String, mode: SessionModel.HarnessMode = SessionModel.HarnessMode.BUILD) -> Array:
	var model := SessionModel.new()
	model.harness_mode = mode
	var log := AgentLog.new()
	var controller := SessionController.new()
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	controller.setup(model, log, root)
	var fs := FsHandler.new()
	fs.setup(root, log)
	controller.set_fs_handler(fs)
	var ok: bool = await controller.start(_fake_profile(scenario))
	_check(ok, "%s: la sesión arranca (%s)" % [scenario, model.failure_message])
	return [controller, model, log]


func _scenario_basic() -> void:
	print("— basic")
	var made := await _make("basic")
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	_check(model.state == SessionModel.SessionState.READY, "basic: READY")
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
		if entry.kind == ChatEntry.EntryKind.AGENT:
			agent_text += entry.text
		elif entry.kind == ChatEntry.EntryKind.THOUGHT:
			thought_count += 1
	_check(agent_text == "¡Hola! Soy el **agente falso**. Respondo con `streaming`.", "basic: texto unido (%s)" % agent_text)
	_check(updates[0] >= 2, "basic: llegó en streaming (%d updates)" % updates[0])
	_check(thought_count == 1, "basic: un thought")
	_check(model.title == "Saludo de prueba", "basic: título")
	_check(model.usage_used == 1200 and model.usage_size == 200000, "basic: usage")
	_check(model.state == SessionModel.SessionState.READY, "basic: vuelve a READY")
	_check(_log_has(log, "line ignored"), "basic: la línea no JSON se loguea")
	_check(_log_has(log, "variant, ignored"), "basic: la variante desconocida se loguea")
	_check(_log_has(log, "fake_agent: prompt") and _log_has(log, "harness_context"), "basic: el primer prompt lleva el contexto del harness")
	var godot_bin := OS.get_executable_path()
	_check(_log_has(log, "fake_agent: GODOT=%s" % godot_bin), "basic: el agente recibe el binario del editor en $GODOT")
	_check(_log_has(log, "PATH=%s" % EditorBinary.shim_dir()), "basic: el shim godot va al frente del PATH del agente")
	_check(_log_has(log, "this editor's binary") and _log_has(log, godot_bin.json_escape()), "basic: el system prompt nombra el binario del editor")

	# El cambio de modo del harness se refleja en el modo del agente.
	model.set_harness_mode(SessionModel.HarnessMode.ASK)
	await _wait_until(func() -> bool: return model.current_agent_mode == "plan")
	_check(model.current_agent_mode == "plan", "basic: Preguntar → modo plan del agente")

	var changed: bool = await controller.set_config_option("model", "fake-small")
	_check(changed and model.config_option("model").currentValue == "fake-small", "basic: set_config_option")

	var pid := _pid_of(controller)
	controller.stop()
	_check(model.state == SessionModel.SessionState.DISCONNECTED, "basic: DISCONNECTED al detener")
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
	_check(model.state == SessionModel.SessionState.CANCELLING, "cancel: CANCELLING")
	await _wait_until(func() -> bool: return result[0] != "")
	_check(result[0] == "cancelled", "cancel: stopReason cancelled (%s)" % result[0])
	_check(model.state == SessionModel.SessionState.READY, "cancel: vuelve a READY")
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
	await _wait_until(func() -> bool: return model.state == SessionModel.SessionState.FAILED)
	_check(model.state == SessionModel.SessionState.FAILED, "crash: FAILED")
	var notice: ChatEntry = model.entries().back()
	_check(notice.kind == ChatEntry.EntryKind.NOTICE and notice.level == ChatEntry.NoticeLevel.ERROR, "crash: aviso de error")
	_check(notice.actions.size() == 2, "crash: con acciones Reintentar / Ver log")
	# Reintentar reabre una sesión limpia.
	var ok: bool = await controller.start(controller.profile())
	_check(ok and model.state == SessionModel.SessionState.READY, "crash: reintentar")
	controller.stop()


func _target_path() -> String:
	return ProjectSettings.globalize_path(TMP_DIR + "/perm_target.gd")


func _reset_target() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var file := FileAccess.open(_target_path(), FileAccess.WRITE)
	file.store_string("extends Node\nvar a := 1\n")
	file.close()


## Respuestas que el agente falso recibió a sus requests (las reporta por stderr).
func _agent_responses(log: AgentLog) -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Dictionary in log.entries():
		var message := str(entry.message)
		if message.begins_with("fake_agent: respuesta "):
			result.append(message.trim_prefix("fake_agent: respuesta "))
	return result


func _scenario_permissions_build() -> void:
	print("— permisos (Construir)")
	_reset_target()
	var made := await _make("permissions", SessionModel.HarnessMode.BUILD)
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	var cards: Array[String] = []
	# El "usuario": siempre en esta sesión para la edición, denegar el comando.
	model.permission_requested.connect(func(request: PermissionRequest) -> void:
		cards.append(request.title)
		if request.group == "edit_files":
			request.select.call_deferred(request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]))
		else:
			request.select.call_deferred(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE]))
	)
	var stop_reason: String = await controller.send_prompt("editá")
	_check(stop_reason == "end_turn", "permisos/build: end_turn (%s)" % stop_reason)
	var responses := _agent_responses(log)
	_check(responses.size() == 6, "permisos/build: 6 respuestas (%d)" % responses.size())
	if responses.size() == 6:
		_check(responses[0].contains("\"optionId\":\"allow\""), "permisos/build: 'siempre' se responde como 'una vez' (%s)" % responses[0])
		_check(responses[1] == "{}", "permisos/build: fs/write preautorizado (%s)" % responses[1])
		_check(responses[2].contains("var a := 2") and not responses[2].contains("extends"), "permisos/build: fs/read con line/limit (%s)" % responses[2])
		_check(responses[3].contains("outside the project"), "permisos/build: fs/read fuera del proyecto rechazado (%s)" % responses[3])
		_check(responses[4].contains("\"optionId\":\"allow\""), "permisos/build: segunda edición permitida por la sesión (%s)" % responses[4])
		_check(responses[5].contains("\"optionId\":\"reject\""), "permisos/build: comando denegado por el usuario (%s)" % responses[5])
	_check(cards.size() == 2, "permisos/build: 2 tarjetas (edición y comando): %s" % str(cards))
	_check(FileAccess.get_file_as_string(_target_path()) == "extends Node\nvar a := 2\n", "permisos/build: archivo escrito")
	_check(model.pending_permissions.is_empty(), "permisos/build: sin permisos pendientes")
	controller.stop()


func _scenario_permissions_ask() -> void:
	print("— permisos (Preguntar)")
	_reset_target()
	var made := await _make("permissions", SessionModel.HarnessMode.ASK)
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	var cards: Array[int] = [0]
	model.permission_requested.connect(func(_request: PermissionRequest) -> void: cards[0] += 1)
	var stop_reason: String = await controller.send_prompt("editá")
	_check(stop_reason == "end_turn", "permisos/ask: end_turn (%s)" % stop_reason)
	var responses := _agent_responses(log)
	_check(cards[0] == 0, "permisos/ask: ninguna tarjeta (%d)" % cards[0])
	if responses.size() == 6:
		_check(responses[0].contains("\"optionId\":\"reject\""), "permisos/ask: edición auto-denegada (%s)" % responses[0])
		_check(responses[1].contains("Permission denied"), "permisos/ask: fs/write denegado (%s)" % responses[1])
		_check(responses[2].contains("var a := 1"), "permisos/ask: fs/read sigue andando (%s)" % responses[2])
		_check(responses[5].contains("\"optionId\":\"reject\""), "permisos/ask: comando auto-denegado (%s)" % responses[5])
	else:
		_check(false, "permisos/ask: 6 respuestas (%d)" % responses.size())
	_check(FileAccess.get_file_as_string(_target_path()) == "extends Node\nvar a := 1\n", "permisos/ask: archivo intacto")
	var denied := 0
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.EntryKind.NOTICE and entry.text.begins_with("Denied in Ask mode"):
			denied += 1
	_check(denied >= 3, "permisos/ask: avisos de denegado (%d)" % denied)
	controller.stop()


## Escribir el proyecto por fuera del editor (D48): shell que escribe y escenas a mano se rechazan
## sin tarjeta; un comando que escribe en /tmp y un script siguen la política (One-shot).
func _scenario_project_writes() -> void:
	print("— escrituras por fuera del editor (One-shot)")
	var made := await _make("project_writes", SessionModel.HarnessMode.ONESHOT)
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	var cards: Array[String] = []
	model.permission_requested.connect(func(request: PermissionRequest) -> void:
		cards.append(request.title)
		request.select.call_deferred(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE]))
	)
	var stop_reason: String = await controller.send_prompt("escribí")
	_check(stop_reason == "end_turn", "escrituras: end_turn (%s)" % stop_reason)
	var responses := _agent_responses(log)
	if responses.size() == 6:
		_check(responses[0].contains("\"optionId\":\"reject\""), "escrituras: python con heredoc rechazado (%s)" % responses[0])
		_check(responses[1].contains("\"optionId\":\"reject\""), "escrituras: cat > .tscn rechazado (%s)" % responses[1])
		_check(responses[2].contains("\"optionId\":\"reject\""), "escrituras: Write de una escena rechazado (%s)" % responses[2])
		_check(responses[3].contains("not written by hand"), "escrituras: fs/write de una escena rechazado (%s)" % responses[3])
		_check(responses[4].contains("\"optionId\":\"allow\""), "escrituras: comando que escribe en /tmp sigue la política (%s)" % responses[4])
		_check(responses[5].contains("\"optionId\":\"allow\""), "escrituras: Write de un script permitido en One-shot (%s)" % responses[5])
	else:
		_check(false, "escrituras: 6 respuestas (%d)" % responses.size())
	_check(cards == ["godot --headless > /tmp/godot_agent_out.log"], "escrituras: solo el comando de /tmp pide permiso (%s)" % str(cards))
	var rejected := model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE and entry.text.begins_with("Rejected:"))
	_check(rejected.size() == 3, "escrituras: 3 avisos de rechazo (%d)" % rejected.size())
	_check(not FileAccess.file_exists("res://tests/tmp/boss.tscn"), "escrituras: la escena no se escribió")
	controller.stop()


## Modo Auto (D57): edición y comandos de la allowlist sin tarjeta; rm y una redirección piden
## permiso; «Permitir siempre» agrega la regla, que cubre el comando siguiente.
func _scenario_auto_shell() -> void:
	print("— modo Auto")
	var made := await _make("auto_shell", SessionModel.HarnessMode.AUTO)
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	var rules := ShellRules.default_rules()
	controller.shell_rules = rules
	var saved: Array[int] = [0]
	controller.shell_rules_changed.connect(func() -> void: saved[0] += 1)
	var cards: Array[String] = []
	var proposed: Array[String] = []
	var offered_session: Array[bool] = [false]
	model.permission_requested.connect(func(request: PermissionRequest) -> void:
		cards.append(request.title)
		proposed.append(request.rule_pattern)
		if not request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty():
			offered_session[0] = true
		if request.title == "npm test":
			request.rule_to_add = {"pattern": "npm test *", "list": "allow"}
			request.select.call_deferred(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE]))
		else:
			request.select.call_deferred(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE]))
	)
	var stop_reason: String = await controller.send_prompt("auto")
	_check(stop_reason == "end_turn", "auto: end_turn (%s)" % stop_reason)
	var responses := _agent_responses(log)
	if responses.size() == 6:
		_check(responses[0].contains("\"optionId\":\"allow\""), "auto: ls && git status sin tarjeta (%s)" % responses[0])
		_check(responses[1].contains("\"optionId\":\"reject\""), "auto: rm pide permiso y se rechaza (%s)" % responses[1])
		_check(responses[2].contains("\"optionId\":\"allow\""), "auto: npm test permitido desde la tarjeta (%s)" % responses[2])
		_check(responses[3].contains("\"optionId\":\"allow\""), "auto: la regla nueva cubre npm test -- --watch (%s)" % responses[3])
		_check(responses[4].contains("\"optionId\":\"allow\""), "auto: edición sin tarjeta (%s)" % responses[4])
		_check(responses[5].contains("\"optionId\":\"reject\""), "auto: redirección a un archivo pide permiso (%s)" % responses[5])
	else:
		_check(false, "auto: 6 respuestas (%d)" % responses.size())
	_check(cards == ["rm -rf /tmp/godot_agent_auto", "npm test", "echo hola > /tmp/godot_agent_auto.txt"], "auto: tarjetas solo para rm, npm test y la redirección (%s)" % str(cards))
	_check(proposed == ["", "npm test", ""], "auto: patrones propuestos (%s)" % str(proposed))
	_check(not offered_session[0], "auto: la tarjeta no ofrece «siempre en esta sesión»")
	var added: Array = rules.filter(func(rule: Dictionary) -> bool: return rule.origin == ShellRules.ORIGIN_CARD)
	_check(added.size() == 1 and added[0].pattern == "npm test *" and added[0].list == "allow" and not str(added[0].added).is_empty(), "auto: regla agregada con origen y fecha (%s)" % str(added))
	_check(saved[0] == 1, "auto: se pide guardar la config una vez (%d)" % saved[0])
	var perm_log := "\n".join(log.entries().filter(func(entry: Dictionary) -> bool: return entry.channel == AgentLog.CH_PERM).map(func(entry: Dictionary) -> String: return str(entry.message)))
	_check(perm_log.contains("allowed by Auto mode, on the allowlist (ls *, git status *)"), "auto: el log dice qué regla permitió")
	_check(perm_log.contains("Auto mode asks, «rm -rf /tmp/godot_agent_auto» is on the ask list (rm *)"), "auto: el log dice por qué preguntó")
	_check(perm_log.contains("rule added to the Auto allow list: npm test *"), "auto: el log registra la regla nueva")
	controller.stop()


# --- helpers -------------------------------------------------------------------------------------

## Cuota simulada en la forma de Claude Code (D22): 63 %, 91 % con aviso y después el límite.
func _scenario_quota() -> void:
	print("— quota")
	var made := await _make("quota")
	var controller: SessionController = made[0]
	var model: SessionModel = made[1]
	var log: AgentLog = made[2]
	_check(await controller.send_prompt("tarea 1") == "end_turn", "quota: turno 1")
	var windows: Dictionary = controller.quota.last_rate_limit.get("unifiedWindows", {})
	_check(is_equal_approx(float(windows.get("five_hour", {}).get("utilization", 0.0)), 0.63), "quota: ventana de 5 h al 63 %")
	_check(_log_has(log, "five_hour 63 %"), "quota: resumen en el canal quota")
	_check(controller.quota.state == QuotaMonitor.QuotaState.NORMAL, "quota: estado normal")
	_check(await controller.send_prompt("tarea 2") == "end_turn", "quota: turno 2")
	_check(controller.quota.last_rate_limit.get("status") == "allowed_warning", "quota: aviso al 91 %")
	_check(controller.quota.last_limit_event.is_empty(), "quota: todavía sin límite")
	_check(controller.quota.state == QuotaMonitor.QuotaState.PAUSE_SCHEDULED, "quota: 91 % → pausa programada")
	_check(await controller.send_prompt("tarea 3") == "error", "quota: el turno del límite termina con error")
	_check(controller.quota.last_rate_limit.get("status") == "rejected", "quota: cuota rejected")
	_check(not controller.quota.last_limit_event.is_empty(), "quota: evento de límite registrado")
	_check(controller.quota.state == QuotaMonitor.QuotaState.LIMITED, "quota: limitado")
	var wait := controller.quota.seconds_until_retry()
	_check(wait > 100 and wait <= 120, "quota: reinicio en ~120 s (%d)" % wait)
	_check(_log_has(log, "quota state: pause scheduled → limited"), "quota: transición en el canal")
	_check(_log_has(log, "limit notice in the agent text: You've hit your limit") and _log_has(log, "session/prompt error (limit)"), "quota: texto y error de límite en el canal")
	_check(model.state == SessionModel.SessionState.READY, "quota: la sesión sigue usable")
	controller.stop()


## M7: el historial se graba por turno, sin capturas, y session/load reanuda en el mismo archivo.
func _scenario_history() -> void:
	print("— history")
	var history := SessionHistory.new()
	history.dir = "user://acp_check_history"
	for file: String in DirAccess.get_files_at(history.dir) if DirAccess.dir_exists_absolute(history.dir) else PackedStringArray():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(history.dir.path_join(file)))
	var model := SessionModel.new()
	var controller := SessionController.new()
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	controller.setup(model, AgentLog.new(), root)
	controller.history = history
	_check(await controller.start(_fake_profile("history")), "history: arranca")
	var session_id := model.session_id
	_check(await controller.send_prompt("arreglá la pelota") == "end_turn", "history: turno 1")
	_check(await controller.send_prompt("seguí") == "end_turn", "history: turno 2")
	controller.stop()
	var listed := history.list(root)
	_check(listed.size() == 1 and listed[0].id == session_id and listed[0].title == "Arreglar la pelota" and int(listed[0].turns) == 2, "history: índice %s" % [listed])
	var raw := FileAccess.get_file_as_string(history.dir.path_join(session_id + SessionHistory.EXTENSION))
	_check(not raw.is_empty() and not raw.contains("iVBORw0KGgo") and not raw.contains("rawOutput") and not raw.contains("usage_update"), "history: sin capturas, rawOutput ni uso")
	_check(raw.contains(SessionHistory.IMAGE_PLACEHOLDER) and raw.contains("trimmed in the history") and raw.length() < 20000, "history: marcas de captura y recorte (%d bytes)" % raw.length())
	var record := history.load_record(session_id)
	var first_agent: Array = record.events.filter(func(event: Dictionary) -> bool: return event.type == "update" and event.update.sessionUpdate == "agent_message_chunk")
	_check(not first_agent.is_empty() and first_agent[0].update.content.text == "Reviso la escena.", "history: chunks unidos")
	_check(history.load_record("../../etc/passwd").is_empty(), "history: ids con rutas se rechazan")
	var replay_model := SessionModel.new()
	var during: Array[bool] = []
	var on_call := func(_c: Variant, _g: Variant) -> void: during.append(replay_model.replaying)
	replay_model.tool_call_changed.connect(on_call)
	SessionHistory.replay(record, replay_model)
	replay_model.tool_call_changed.disconnect(on_call)  # la lambda captura el modelo: sin esto, ciclo
	_check(not during.is_empty() and during.all(func(value: bool) -> bool: return value) and not replay_model.replaying, "history: replaying durante el replay y no después")
	# Sin el índice, reanudar igual graba (el registro trae solo la cabecera).
	var bare := record.duplicate()
	for key: String in ["title", "turns", "truncated"]:
		bare.erase(key)
	var other := SessionHistory.new()
	other.dir = "user://acp_check_history_bare"
	other.begin(session_id, "p", "a", root, bare)
	other.record_prompt("hola")
	_check(other.is_recording(), "history: begin sin índice no rompe record_prompt")
	other.end()
	other.flush()

	# Reanudar con session/load: la conversación sale del archivo, no del replay del agente.
	model = SessionModel.new()
	controller = SessionController.new()
	controller.setup(model, AgentLog.new(), root)
	controller.history = history
	_check(await controller.start(_fake_profile("history"), record), "history: session/load reanuda")
	for i in 20:  # deja llegar cualquier update tardío
		await process_frame
	var texts: PackedStringArray = []
	for entry: ChatEntry in model.entries():
		texts.append(entry.text)
	var joined := "\n".join(texts)
	_check(model.session_id == session_id and model.state == SessionModel.SessionState.READY, "history: misma sesión, READY")
	_check(joined.contains("arreglá la pelota") and joined.contains("Segundo turno.") and not joined.contains("replay del agente"), "history: conversación del archivo, sin el replay")
	_check(joined.contains("Session resumed") and model.title == "Arreglar la pelota", "history: aviso y título")
	_check(await controller.send_prompt("tercero") == "end_turn", "history: turno después de reanudar")
	controller.stop()
	listed = history.list()
	_check(listed.size() == 1 and int(listed[0].turns) == 3, "history: sigue en el mismo archivo (%s)" % [listed])

	# reopen (One-shot con la sesión perdida): session/load si se puede, si no una sesión nueva.
	_check(await controller.reopen(_fake_profile("history"), session_id) and model.session_id == session_id, "history: reopen usa session/load")
	controller.stop()
	_check(await controller.reopen(_fake_profile("basic"), session_id) and model.session_id != session_id and model.state == SessionModel.SessionState.READY, "history: reopen sin loadSession abre una nueva")
	controller.stop()

	# Sin session/load: solo lectura.
	model = SessionModel.new()
	controller = SessionController.new()
	controller.setup(model, AgentLog.new(), root)
	_check(not await controller.start(_fake_profile("basic"), history.load_record(session_id)), "history: sin loadSession no reanuda")
	_check(model.state == SessionModel.SessionState.DISCONNECTED and model.entries().size() > 3 and model.entries().back().text.contains("read-only"), "history: queda de solo lectura")
	controller.stop()


## Login: sin credenciales session/new pide autenticarse; el botón corre el login del agente (el
## mismo agente falso con --login), muestra el enlace, manda el código y vuelve a abrir la sesión.
func _scenario_login() -> void:
	print("— login")
	const MARKER := "user://fake_login_ok"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER))
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, ProjectSettings.globalize_path("res://").trim_suffix("/"))
	var ok: bool = await controller.start(_fake_profile("auth"))
	_check(not ok and model.state == SessionModel.SessionState.FAILED, "login: sin login la sesión no abre")
	_check(_log_has(log, "\"auth\":{\"terminal\":true}"), "login: initialize declara auth.terminal")
	var failure: ChatEntry = model.entries().back()
	var login_actions := failure.actions.filter(func(action: Dictionary) -> bool: return action.id == SessionController.ACTION_LOGIN)
	_check(login_actions.size() == 1 and login_actions[0].data == "fake-login" and login_actions[0].label == "Sign in · Cuenta falsa", "login: un botón por método usable (%s)" % [failure.actions])
	_check(failure.text.contains("Sign in to continue"), "login: el aviso lo dice (%s)" % failure.text)
	var link_shown := func() -> bool:
		return model.entries().any(func(entry: ChatEntry) -> bool:
			return entry.actions.any(func(action: Dictionary) -> bool: return action.id == "open_link"))
	# Código equivocado: el login sale con error y se puede reintentar.
	controller.login("fake-login")
	await _wait_until(link_shown)
	_check(link_shown.call(), "login: aparece el enlace")
	_check(controller.send_login_code("nope"), "login: manda el código")
	await _wait_until(func() -> bool: return not controller.is_logging_in() and model.entries().back().level == ChatEntry.NoticeLevel.ERROR)
	var error_notice: ChatEntry = model.entries().back()
	_check(error_notice.text.begins_with("Could not sign in") and not error_notice.text.contains("example.invalid"), "login: error sin el enlace (%s)" % error_notice.text)
	_check(error_notice.actions.any(func(action: Dictionary) -> bool: return action.id == SessionController.ACTION_LOGIN), "login: el error ofrece reintentar")
	_check(not _log_has(log, "nope"), "login: el código no va al log")
	# Código correcto: la sesión se abre sola.
	controller.login("fake-login")
	await _wait_until(link_shown)
	_check(controller.send_login_code("CODE123"), "login: manda el código bueno")
	await _wait_until(func() -> bool: return model.state == SessionModel.SessionState.READY)
	_check(model.state == SessionModel.SessionState.READY and model.entries().back().text == "Signed in.", "login: la sesión abre después del login")
	# Cancelar mata el proceso del login.
	controller.login("fake-login")
	await _wait_until(link_shown)
	var login_run: Object = controller.get(&"_login")
	var login_process: Object = login_run.get(&"_process") if login_run else null
	var login_pid: int = login_process.call(&"pid") if login_process else 0
	controller.cancel_login()
	_check(not controller.is_logging_in() and model.entries().back().text == "Sign-in cancelled.", "login: cancelar")
	await _wait_until(func() -> bool: return login_pid > 0 and not _pid_alive(login_pid))
	_check(login_pid > 0 and not _pid_alive(login_pid), "login: el proceso del login terminó")
	controller.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER))


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
