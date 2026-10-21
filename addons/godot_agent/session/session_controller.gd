@tool
extends RefCounted
## Comandos de la sesión: conecta el proceso del agente, hace initialize → session/new, manda
## prompts, cancela y cambia opciones. Aplica lo que llega al SessionModel.
## No depende del editor: lo que necesita del editor (contexto, fs, permisos, MCP) se inyecta.

signal connected
signal disconnected

const AgentProcess := preload("../transport/agent_process.gd")
const AcpClient := preload("../acp/acp_client.gd")
const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const AgentLog := preload("../core/agent_log.gd")
const AgentProfile := preload("../core/agent_profile.gd")

const PROTOCOL_VERSION := 1
const CLIENT_NAME := "godot-agent-harness"
const CLIENT_TITLE := "Godot Agent Harness"
const CLIENT_VERSION := "0.1.0"
const SYSTEM_PROMPT_PATH := "res://addons/godot_agent/config/system_prompt.md"

## Acciones que ofrecen los avisos de error (spec §15).
const ACTION_RETRY := "retry"
const ACTION_SHOW_LOG := "show_log"

const MODE_RULES: Dictionary = {
	SessionModel.HarnessMode.ASK: "Solo respondé preguntas: no modifiques archivos, escenas ni settings, y no ejecutes comandos.",
	SessionModel.HarnessMode.REVIEW: "Revisión de solo lectura: no modifiques nada. Reportá los hallazgos en un bloque ```json con {\"findings\":[{\"path\",\"line\",\"severity\":\"bug|order|perf|style\",\"title\",\"body\",\"suggestion\"}]}.",
	SessionModel.HarnessMode.BUILD: "Podés editar escenas y scripts; el usuario aprueba los cambios.",
	SessionModel.HarnessMode.ONESHOT: "Trabajá de forma autónoma hasta cumplir el objetivo; verificá con run_scene, capture_game_frame y get_errors después de cada tarea.",
}
## Modo del agente (si los publica) que corresponde a cada modo del harness.
const AGENT_MODE_FOR: Dictionary = {
	SessionModel.HarnessMode.ASK: ["plan"],
	SessionModel.HarnessMode.REVIEW: ["plan"],
	SessionModel.HarnessMode.BUILD: ["default"],
	SessionModel.HarnessMode.ONESHOT: ["default"],
}

var model: SessionModel
var client: AcpClient
var agent_log: AgentLog
## Directorio de trabajo para session/new (ruta absoluta del proyecto).
var cwd: String = ""
## Callable() -> Array: entradas `mcpServers` para session/new (el server del addon, M3).
var mcp_servers_provider: Callable
## Callable() -> Dictionary: variables para el prompt de sistema ({project_name}, …).
var prompt_variables_provider: Callable

var _process: AgentProcess
var _profile: AgentProfile
var _system_prompt_sent: bool = false
var _connect_generation: int = 0


func setup(session_model: SessionModel, log_sink: AgentLog, working_dir: String) -> void:
	model = session_model
	agent_log = log_sink
	cwd = working_dir
	client = AcpClient.new()
	client.setup(_send_line, agent_log)
	client.set_notification_handler("session/update", _on_session_update)
	model.harness_mode_changed.connect(_on_harness_mode_changed)


func profile() -> AgentProfile:
	return _profile


func is_connected_to_agent() -> bool:
	return _process != null and _process.is_running() and not model.session_id.is_empty()


## Lanza el agente del perfil y abre una sesión. Devuelve true si quedó lista.
func start(agent_profile: AgentProfile) -> bool:
	stop()
	_connect_generation += 1
	var generation := _connect_generation
	_profile = agent_profile
	model.reset()
	model.failure_message = ""
	model.set_state(SessionModel.State.STARTING)
	agent_log.add(AgentLog.CH_PROC, "Lanzando %s: %s" % [agent_profile.display_name, agent_profile.command_line()])

	_process = AgentProcess.new()
	_process.line_received.connect(client.receive_line)
	_process.stderr_received.connect(_on_stderr)
	_process.exited.connect(_on_process_exited.bind(_process))
	if not _process.start(agent_profile.command, agent_profile.args, agent_profile.resolved_env()):
		_fail("No se pudo lanzar el agente: %s" % _process.last_error())
		_process = null
		return false
	agent_log.add(AgentLog.CH_PROC, "Proceso iniciado (pid %d)" % _process.pid())

	var init := await client.request("initialize", {
		"protocolVersion": PROTOCOL_VERSION,
		"clientInfo": {"name": CLIENT_NAME, "title": CLIENT_TITLE, "version": CLIENT_VERSION},
		"clientCapabilities": client_capabilities(),
	})
	if generation != _connect_generation:
		return false
	if not init.ok or not init.result is Dictionary:
		_fail("El agente no respondió a initialize: %s" % init.error_message())
		return false
	model.apply_initialize(init.result)
	var protocol := int(init.result.get("protocolVersion", PROTOCOL_VERSION))
	if protocol != PROTOCOL_VERSION:
		agent_log.add(AgentLog.CH_ACP, "El agente usa la versión de protocolo %d (el cliente pidió %d)" % [protocol, PROTOCOL_VERSION])
	return await open_session(generation)


## session/new sobre el proceso ya inicializado (también sirve para "Nueva sesión").
func open_session(generation: int = _connect_generation) -> bool:
	if _process == null or not _process.is_running():
		return await start(_profile) if _profile else false
	if model.state != SessionModel.State.STARTING:
		model.reset()
		model.set_state(SessionModel.State.STARTING)
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	var result := await client.request("session/new", {"cwd": cwd, "mcpServers": mcp_servers})
	if generation != _connect_generation:
		return false
	if not result.ok or not result.result is Dictionary or not result.result.get("sessionId") is String:
		var detail := result.error_message() if not result.ok else "respuesta sin sessionId"
		if not model.auth_methods.is_empty():
			detail += ". El agente pide autenticarse: %s" % _auth_hint()
		_fail("No se pudo abrir la sesión: %s" % detail)
		return false
	model.apply_session(result.result.sessionId, result.result)
	_system_prompt_sent = false
	model.set_state(SessionModel.State.READY)
	_sync_agent_mode()
	connected.emit()
	return true


## Manda un turno. `extra_blocks` son ContentBlocks de contexto (escena, selección, imagen…).
func send_prompt(text: String, extra_blocks: Array = []) -> String:
	if model.state != SessionModel.State.READY:
		return ""
	var blocks: Array = []
	if not _system_prompt_sent:
		blocks.append({"type": "text", "text": system_prompt()})
		_system_prompt_sent = true
	blocks.append_array(extra_blocks)
	blocks.append({"type": "text", "text": text})
	var attachments: Array[Dictionary] = []
	for block: Variant in extra_blocks:
		if block is Dictionary:
			attachments.append(block)
	model.add_user_message(text, attachments)
	model.set_state(SessionModel.State.PROMPTING)

	var result := await client.request("session/prompt", {"sessionId": model.session_id, "prompt": blocks})
	if not result.ok:
		if model.state in [SessionModel.State.PROMPTING, SessionModel.State.CANCELLING]:
			model.add_notice("El turno terminó con error: %s" % result.error_message(), ChatEntry.Level.ERROR, _error_actions())
			model.finish_turn("error")
		return "error"
	var stop_reason := "end_turn"
	if result.result is Dictionary:
		stop_reason = str(result.result.get("stopReason", stop_reason))
	model.finish_turn(stop_reason)
	return stop_reason


func cancel() -> void:
	if model.state != SessionModel.State.PROMPTING:
		return
	model.set_state(SessionModel.State.CANCELLING)
	client.notify("session/cancel", {"sessionId": model.session_id})


func set_config_option(id: String, value: String) -> bool:
	if model.session_id.is_empty():
		return false
	var result := await client.request("session/set_config_option", {"sessionId": model.session_id, "configId": id, "value": value})
	if not result.ok:
		model.add_notice("No se pudo cambiar '%s': %s" % [id, result.error_message()], ChatEntry.Level.WARNING)
		return false
	if result.result is Dictionary and result.result.get("configOptions") is Array:
		model.config_options = result.result.configOptions
		model.config_options_changed.emit(model.config_options)
	else:
		model.set_config_value(id, value)
	return true


## Mata el proceso y cierra los requests pendientes. Seguro de llamar varias veces.
func stop() -> void:
	_connect_generation += 1
	if _process:
		var process := _process
		_process = null
		process.stop()
		agent_log.add(AgentLog.CH_PROC, "Proceso detenido")
	client.fail_all_pending("Sesión detenida.")
	if model.state != SessionModel.State.DISCONNECTED and model.state != SessionModel.State.FAILED:
		model.set_state(SessionModel.State.DISCONNECTED)
		disconnected.emit()


func client_capabilities() -> Dictionary:
	return {
		"fs": {
			"readTextFile": client.has_request_handler("fs/read_text_file"),
			"writeTextFile": client.has_request_handler("fs/write_text_file"),
		},
		"terminal": false,
	}


func system_prompt() -> String:
	var template := FileAccess.get_file_as_string(SYSTEM_PROMPT_PATH)
	var variables: Dictionary = prompt_variables_provider.call() if prompt_variables_provider.is_valid() else {}
	variables["mode"] = SessionModel.HARNESS_MODE_LABELS[model.harness_mode]
	variables["mode_rules"] = MODE_RULES[model.harness_mode]
	variables["project_path"] = variables.get("project_path", cwd)
	variables["project_name"] = variables.get("project_name", cwd.get_file())
	variables["godot_version"] = variables.get("godot_version", Engine.get_version_info().string)
	return "<harness_context>\n%s\n</harness_context>" % template.format(variables)


# --- internos ------------------------------------------------------------------------------------

func _send_line(line: String) -> bool:
	return _process != null and _process.send_line(line)


func _on_session_update(params: Dictionary) -> void:
	if params.get("sessionId") != model.session_id or not params.get("update") is Dictionary:
		return
	if not model.apply_update(params.update):
		agent_log.add(AgentLog.CH_ACP, "Variante de session/update desconocida, ignorada: %s" % str(params.update.get("sessionUpdate", "?")))


func _on_stderr(line: String) -> void:
	agent_log.add(AgentLog.CH_PROC, line)


func _on_process_exited(code: int, process: AgentProcess) -> void:
	if process != _process:
		return
	_process = null
	process.stop()
	client.fail_all_pending("El agente se cerró (código %d)." % code)
	_fail("El agente se cerró inesperadamente (código %d)." % code)
	disconnected.emit()


func _on_harness_mode_changed(_mode: SessionModel.HarnessMode) -> void:
	_system_prompt_sent = false
	_sync_agent_mode()


## Si el agente publica modos, se elige el que corresponde al modo del harness.
func _sync_agent_mode() -> void:
	if model.session_id.is_empty() or model.agent_modes.is_empty():
		return
	var available: PackedStringArray = []
	for mode: Variant in model.agent_modes:
		if mode is Dictionary:
			available.append(str(mode.get("id", "")))
	for candidate: String in AGENT_MODE_FOR[model.harness_mode]:
		if candidate in available and candidate != model.current_agent_mode:
			var result := await client.request("session/set_mode", {"sessionId": model.session_id, "modeId": candidate})
			if result.ok:
				model.apply_update({"sessionUpdate": "current_mode_update", "currentModeId": candidate})
			return


func _fail(message: String) -> void:
	model.failure_message = message
	agent_log.add(AgentLog.CH_PROC, message)
	model.add_notice(message, ChatEntry.Level.ERROR, _error_actions())
	model.set_state(SessionModel.State.FAILED)


func _error_actions() -> Array[Dictionary]:
	return [{"id": ACTION_RETRY, "label": "Reintentar"}, {"id": ACTION_SHOW_LOG, "label": "Ver log"}]


func _auth_hint() -> String:
	var names: PackedStringArray = []
	for method: Variant in model.auth_methods:
		if method is Dictionary:
			names.append("%s (%s)" % [method.get("name", method.get("id", "?")), method.get("description", "")])
	return ", ".join(names)
