@tool
extends RefCounted
## Comandos de la sesión: conecta el proceso del agente, hace initialize → session/new, manda
## prompts, cancela y cambia opciones. Aplica lo que llega al SessionModel.
## No depende del editor: lo que necesita del editor (contexto, fs, permisos, MCP) se inyecta.

signal connected
signal disconnected
## Terminó la sincronización del modo del agente con el del harness (session/set_mode).
signal agent_mode_synced
## El usuario agregó una regla del modo Auto desde una tarjeta: hay que guardar la config.
signal shell_rules_changed
## El usuario permitió un MCP server de terceros desde una tarjeta, para el modo y el proyecto: hay
## que guardar la matriz de la config (m7-35).
signal permissions_changed

const AgentProcess := preload("../transport/agent_process.gd")
const AddonVersion := preload("../core/addon_version.gd")
const AcpClient := preload("../acp/acp_client.gd")
const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const ToolCall := preload("tool_call.gd")
const AgentLog := preload("../core/agent_log.gd")
const AgentProfile := preload("../core/agent_profile.gd")
const PermissionPolicy := preload("permission_policy.gd")
const PermissionBroker := preload("permission_broker.gd")
const UsageQuery := preload("usage_query.gd")
const SessionCatalog := preload("session_catalog.gd")
const ElicitationRequest := preload("elicitation_request.gd")
const FsHandler := preload("../acp/fs_handler.gd")
const TerminalHandler := preload("../acp/terminal_handler.gd")
const QuotaMonitor := preload("../core/quota_monitor.gd")
const ReviewStore := preload("../review/review_store.gd")
const SessionHistory := preload("session_history.gd")
const AgentLogin := preload("agent_login.gd")
const EditorBinary := preload("../transport/editor_binary.gd")
const CommandResolver := preload("../transport/command_resolver.gd")
const AgentAdapters := preload("agents/agent_adapters.gd")
const AgentAdapter := preload("agents/agent_adapter.gd")
const ClaudeCli := preload("../extensions/claude_cli.gd")
const TurnSnapshots := preload("turn_snapshots.gd")
const TurnReport := preload("turn_report.gd")
const I18n := preload("../core/i18n.gd")

## Turnos seguidos que la verificación al terminar un turno manda para corregir errores (m11-04).
const MAX_FIX_TURNS := 2
const PROTOCOL_VERSION := 1
const CLIENT_NAME := "godot-agent-harness"
const CLIENT_TITLE := "Godot Agent Harness"
const SYSTEM_PROMPT_PATH := "res://addons/godot_agent/config/system_prompt.md"

## Acciones que ofrecen los avisos de error (spec §15).
const ACTION_RETRY := "retry"
## Aviso de lo que cambió un turno (m11-01, m11-02): ver los cambios y volver atrás. Su `data` es
## `{session, start, end, files}`; lo resuelve el plugin.
const ACTION_TURN_CHANGES := "turn_changes"
const ACTION_TURN_RESTORE := "turn_restore"
## Guardar el reporte del turno (m11-06), con la misma `data`.
const ACTION_TURN_REPORT := "turn_report"
const ACTION_SHOW_LOG := "show_log"
## Errores al lanzar el agente (m12-13): abrir Ajustes › Agentes, o el registro de ACP para
## reinstalar un agente que vino de ahí.
const ACTION_EDIT_AGENT := "edit_agent"
const ACTION_REINSTALL_AGENT := "reinstall_agent"
## Líneas de stderr del agente que muestra el aviso de error.
const STDERR_TAIL := 8
## Login con un método de auth del agente (payload: id del método), pegar el código que da la
## página de login y cancelarlo.
const ACTION_LOGIN := "login"
const ACTION_LOGIN_CODE := "login_code"
const ACTION_LOGIN_CANCEL := "login_cancel"
## Error de ACP cuando el agente necesita que el usuario inicie sesión (`authRequired`). El mismo
## código es el de transporte del AcpClient: se distingue por el mensaje del SDK de ACP.
const AUTH_REQUIRED_CODE := -32000
const AUTH_REQUIRED_MESSAGE := "authentication required"
## Ventana en la que un permiso de edición ya concedido cubre el fs/write_text_file que le sigue
## (el adapter de Claude pide permiso para Edit y después escribe por fs/*).

const MODE_RULES: Dictionary = {
	SessionModel.HarnessMode.ASK: "Only answer questions: do not modify files, scenes or settings, and do not run commands.",
	SessionModel.HarnessMode.REVIEW: "Read-only review: do not modify anything. Report the findings in a ```json block with {\"findings\":[{\"path\",\"line\",\"severity\":\"bug|order|perf|style\",\"title\",\"body\",\"suggestion\"}]} (path relative to the project, line starting at 1). Each block replaces the previous review: include every finding that still applies. Departures from the Godot conventions below are findings too (severity order for structure, style for typing).",
	SessionModel.HarnessMode.BUILD: "You can edit scenes and scripts; the user approves the changes.",
	SessionModel.HarnessMode.AUTO: "You can edit scenes, scripts and project settings and run the game without asking. Shell commands run without asking only if they are on the user's allowlist (read-only ones like ls, grep, git status); any other command waits for the user's approval, so prefer the godot.* and file tools.",
	SessionModel.HarnessMode.ONESHOT: "Work autonomously until the goal is met; verify with run_scene, capture_game_frame and get_errors after each task.",
}
## Modo del agente (si los publica) que corresponde a cada modo del harness.
const AGENT_MODE_FOR: Dictionary = {
	SessionModel.HarnessMode.ASK: ["plan"],
	SessionModel.HarnessMode.REVIEW: ["plan"],
	SessionModel.HarnessMode.BUILD: ["default"],
	SessionModel.HarnessMode.ONESHOT: ["default"],
	SessionModel.HarnessMode.AUTO: ["default"],
}

var model: SessionModel
var client: AcpClient
## Los permisos de la sesión (m13-05): política, reglas de shell, tarjetas y autorizadores.
var permissions := PermissionBroker.new()
var policy: PermissionPolicy:
	get: return permissions.policy
	set(value): permissions.policy = value
## Reglas de shell del modo Auto (D57): el array de project_config, que se modifica en el lugar.
var shell_rules: Array:
	get: return permissions.shell_rules
	set(value): permissions.shell_rules = value
## MCP servers de terceros que el addon le pasa al agente (m7-34), para avisar en el One-shot.
var external_mcp_names: PackedStringArray = []
## Servers de terceros cuyas tools pidieron permiso: server -> true (ver PermissionBroker).
var seen_mcp_servers: Dictionary:
	get: return permissions.seen_mcp_servers
## Formularios y enlaces (`elicitation/create`) que esperan respuesta: id del request ACP -> ElicitationRequest.
var _elicitations_by_acp_id: Dictionary = {}
var fs: FsHandler
var terminal: TerminalHandler
var _closing_previous := false
## Cuenta que informó el agente con _auth/status_update, y de qué perfil.
var _agent_account: Dictionary = {}
var _agent_account_profile: AgentProfile
var agent_log: AgentLog
## Cuota del plan (spec §10.1): estado, ventanas y límite; la UI y el One-shot la leen de acá.
var quota: QuotaMonitor
## Hallazgos de la última revisión (modo Revisar, spec §9.4).
var review: ReviewStore = ReviewStore.new()
## Historial en disco (M7). null = no se graba (tests).
var history: SessionHistory
## Las sesiones del proyecto en el agente: `session/list`, `close` y `delete` (m13-05).
var sessions := SessionCatalog.new()
## Sesiones que informó el agente con `session/list` para este proyecto (m11-16).
var agent_sessions: Array[Dictionary]:
	get: return sessions.agent_sessions
## `usage` del último session/prompt (tokens del turno: inputTokens, outputTokens, cachedReadTokens…).
var last_turn_usage: Dictionary = {}
## Directorio de trabajo para session/new (ruta absoluta del proyecto).
var cwd: String = ""
## Callable() -> Array: entradas `mcpServers` para session/new (el server del addon, M3).
var mcp_servers_provider: Callable
## Callable() -> Dictionary: `_meta` de session/new y session/load (m7-36: las skills del proyecto
## van en `claudeCode.options.skills`). {} = sin `_meta`.
var session_meta_provider: Callable
## Callable() -> Dictionary: variables para el prompt de sistema ({project_name}, …).
var prompt_variables_provider: Callable
## Reglas del modo para el prompt de sistema en lugar de las de MODE_RULES ("" = las del modo).
## Las usa el evaluador del One-shot (D55), que corre en modo One-shot pero solo prueba.
var mode_rules_override: String = ""
## Después de un login exitoso: si devuelve true, ya se ocupó de la sesión (el One-shot retoma la
## suya con la cuenta nueva) y no se abre una sesión nueva.
var after_login: Callable
## Con varias sesiones abiertas (m7-44): `(paths: PackedStringArray) -> String`, "" si esta sesión
## puede escribirlas (y quedan suyas en el turno) o el nombre de la sesión que las está editando.
var file_guard: Callable:
	get: return permissions.file_guard
	set(value): permissions.file_guard = value
## Verificación al terminar un turno de Construir o Auto (m11-04): `(since_unix: int) -> String`,
## los errores de los scripts que cambiaron en el turno o "". Se espera con await. Sin asignar, no
## se verifica.
var turn_verifier: Callable
## Snapshots por turno de Construir o Auto (m11-01); compartidos por las sesiones, cada una con su
## `session_key`. Sin asignar o sin git, no se guardan.
var snapshots: TurnSnapshots
var session_key: String = ""

var _process: AgentProcess
var _profile: AgentProfile
## Lo propio del agente conectado (cuota, cuenta, `_meta`): sale del perfil al arrancar y del
## `agentInfo` después de initialize (m13-04).
var adapter: AgentAdapter = AgentAdapter.new()
## Últimas líneas de stderr del agente (para el aviso de error, m12-13).
var _stderr_tail: PackedStringArray = []
var _system_prompt_sent: bool = false
## Ya se avisó que el agente trabaja fuera de un turno pedido desde el chat (se rearma con cada prompt).
var _outside_turn_noticed: bool = false
## Turnos seguidos que mandó la verificación para corregir errores (se reinicia con cada prompt del
## usuario); al llegar a MAX_FIX_TURNS solo se avisa.
var _fix_turns: int = 0
var _sending_fix: bool = false
## Algo que el agente tiene que saber antes de su próximo turno (el usuario volvió archivos atrás).
var _note_for_agent: String = ""
var _connect_generation: int = 0
var _mode_syncs_running: int = 0
## El último _load_session falló por el agente (sin loadSession o error), no por una cancelación.
var _load_failed: bool = false
var _login: AgentLogin
## Aviso del login en curso (se actualiza con el enlace y el resultado).
var _login_entry: ChatEntry
## El `/usage` o `/status` en curso: sus mensajes no van al chat (m13-05).
var usage_query := UsageQuery.new()
## Request `session/new`, `session/load` o `session/resume` en vuelo (se cancela con `$/cancel_request` si se abre otra).
var _session_request_id: int = 0


func setup(session_model: SessionModel, log_sink: AgentLog, working_dir: String) -> void:
	model = session_model
	agent_log = log_sink
	cwd = working_dir
	client = AcpClient.new()
	client.setup(_send_line, agent_log)
	quota = QuotaMonitor.new()
	quota.setup(agent_log)
	usage_query.setup(client, agent_log)
	sessions.setup(model, client, agent_log)
	client.set_notification_handler("session/update", _on_session_update)
	client.set_notification_handler("_auth/status_update", _on_auth_status_update)
	connected.connect(_query_agent_usage)
	connected.connect(_refresh_agent_sessions)
	permissions.setup(model, client, agent_log, cwd)
	permissions.shell_rules_changed.connect(shell_rules_changed.emit)
	permissions.permissions_changed.connect(permissions_changed.emit)
	client.set_request_handler("session/request_permission", permissions.on_request_permission)
	client.set_request_handler("elicitation/create", _on_create_elicitation)
	client.set_notification_handler("elicitation/complete", _on_complete_elicitation)
	client.incoming_cancelled.connect(_on_incoming_cancelled)
	model.harness_mode_changed.connect(_on_harness_mode_changed)
	model.config_options_changed.connect(_on_config_options_changed)


## fs/read_text_file y fs/write_text_file. Las escrituras pasan por la política (edit_files).
func set_fs_handler(handler: FsHandler) -> void:
	fs = handler
	fs.write_authorizer = permissions.authorize_fs_write
	fs.register(client)


## terminal/* (m11-15). Los comandos pasan por las guardas del proyecto y la política (shell).
func set_terminal_handler(handler: TerminalHandler) -> void:
	terminal = handler
	terminal.command_authorizer = permissions.authorize_terminal_command
	terminal.env_provider = _terminal_base_env
	# Métodos y no lambdas en las señales de lo que es del controller (terminal, model): una lambda
	# lo captura y arma un ciclo que no se libera; en Godot 4.8 terminaba en un double free al salir.
	terminal.output_changed.connect(_on_terminal_output)
	terminal.register(client)

func profile() -> AgentProfile:
	return _profile


func is_connected_to_agent() -> bool:
	return _process != null and _process.is_running() and not model.session_id.is_empty()


## Lanza el agente del perfil y abre una sesión. Devuelve true si quedó lista.
## Con `resume` (un registro de SessionHistory) muestra esa conversación y la reanuda con session/load.
func start(agent_profile: AgentProfile, resume: Dictionary = {}) -> bool:
	stop()
	_connect_generation += 1
	var generation := _connect_generation
	_profile = agent_profile
	adapter = AgentAdapters.for_profile(agent_profile.command, agent_profile.args, agent_profile.id)
	_agent_account = {}  # el proceso nuevo la vuelve a mandar después de initialize
	model.reset()
	model.failure_message = ""
	model.login_required = false
	_stderr_tail.clear()
	model.set_state(SessionModel.SessionState.STARTING)
	agent_log.add(AgentLog.CH_PROC, "Launching %s: %s" % [agent_profile.display_name, agent_profile.command_line()])

	_process = AgentProcess.new()
	_process.line_received.connect(client.receive_line)
	_process.stderr_received.connect(_on_stderr)
	_process.exited.connect(_on_process_exited.bind(_process))
	var base_path := CommandResolver.child_path_for(CommandResolver.resolve(agent_profile.command))
	var env := EditorBinary.child_env(agent_profile.resolved_env(), base_path)
	if not _process.start(agent_profile.command, agent_profile.args, env):
		var error := _process.last_error()
		_process = null
		_fail_agent(I18n.t("Could not start %s") % _agent_name(),
			I18n.t("The command «%s» didn't run: %s. Check the agent's command in Settings › Agents.") % [agent_profile.command, error],
			"Could not start the agent: %s" % error, [{"id": ACTION_EDIT_AGENT, "label": I18n.t("Edit the agent"), "primary": true}, {"id": ACTION_RETRY, "label": I18n.t("Retry")}])
		return false
	agent_log.add(AgentLog.CH_PROC, "Process started (pid %d)" % _process.pid())

	var init := await client.request("initialize", {
		"protocolVersion": PROTOCOL_VERSION,
		"clientInfo": {"name": CLIENT_NAME, "title": CLIENT_TITLE, "version": AddonVersion.version()},
		"clientCapabilities": client_capabilities(),
	})
	if generation != _connect_generation:
		return false
	if not init.ok or not init.result is Dictionary:
		_fail_agent(I18n.t("%s didn't start") % _agent_name(),
			I18n.t("It didn't answer the first message (initialize): %s") % init.error_message(),
			"The agent did not respond to initialize: %s" % init.error_message(), _crash_actions())
		return false
	model.apply_initialize(init.result)
	adapter = AgentAdapters.for_session(_profile.command, _profile.args, _profile.id, model.agent_info)
	var protocol := int(init.result.get("protocolVersion", PROTOCOL_VERSION))
	if protocol != PROTOCOL_VERSION:
		agent_log.add(AgentLog.CH_ACP, "The agent uses protocol version %d (the client asked for %d)" % [protocol, PROTOCOL_VERSION])
	if not resume.is_empty():
		return await _load_session(resume, generation)
	return await open_session(generation)


## Reabre una sesión perdida: con session/load si está en el historial y el agente lo soporta;
## si no, abre una nueva.
func reopen(agent_profile: AgentProfile, lost_id: String) -> bool:
	var record: Dictionary = history.load_record(lost_id) if history and not lost_id.is_empty() else {}
	if not record.is_empty():
		_load_failed = false
		if await start(agent_profile, record):
			return true
		if not _load_failed:  # se canceló (stop, nueva sesión, plugin deshabilitado): no relanzar
			return false
	return await start(agent_profile)


## session/new sobre el proceso ya inicializado (también sirve para "Nueva sesión").
func open_session(generation: int = _connect_generation) -> bool:
	return await _open_session(generation, true)


## Nueva sesión sin cerrar la anterior en el agente (el One-shot vuelve a ella con session/load).
func open_session_keeping_previous() -> bool:
	return await _open_session(_connect_generation, false)


func _open_session(generation: int, close_previous: bool) -> bool:
	if _process == null or not _process.is_running():
		return await start(_profile) if _profile else false
	if _closing_previous:  # un segundo «Nueva sesión» mientras se cierra la anterior
		return false
	_cancel_abandoned_requests()
	if terminal:
		terminal.stop_all()
	var previous_id := model.session_id
	# Antes del await del close: así ningún prompt va a la sesión que se cierra.
	if model.state != SessionModel.SessionState.STARTING:
		model.reset()
		model.set_state(SessionModel.SessionState.STARTING)
	if close_previous and not previous_id.is_empty() and model.supports_close_session():
		_closing_previous = true
		await close_session(previous_id)
		_closing_previous = false
		if generation != _connect_generation:
			return false
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	var req_id := client.next_request_id()
	_session_request_id = req_id
	var result := await client.request("session/new", _with_meta({"cwd": cwd, "mcpServers": mcp_servers}))
	if _session_request_id == req_id:
		_session_request_id = 0
	if generation != _connect_generation or result.error.get("code") == AcpClient.ERR_REQUEST_CANCELLED:
		return false
	if not result.ok or not result.result is Dictionary or not result.result.get("sessionId") is String:
		var detail := result.error_message() if not result.ok else "response without sessionId"
		var login_actions: Array[Dictionary] = []
		var message := I18n.t("Could not open the session: %s") % detail
		if not result.ok and is_auth_required(result.error):
			login_actions = _login_actions()
			if not login_actions.is_empty():
				# Pedir el login no es un error (m12-11): tarjeta neutra, sin código ni «Reintentar».
				agent_log.add(AgentLog.CH_PROC, message)
				model.login_required = true
				_fail(I18n.t("Sign in to %s to continue.") % _agent_name(), login_actions, ChatEntry.NoticeLevel.INFO, false)
				return false
			else:
				message = I18n.t("Could not open the session: %s. The agent asks for authentication: %s") % [detail, _auth_hint()]
		_fail(message, login_actions)
		return false
	model.apply_session(result.result.sessionId, result.result)
	_system_prompt_sent = false
	policy.clear_session()
	permissions.reset()
	if history:
		history.begin(model.session_id, _profile.id, _profile.display_name, cwd)
	model.set_state(SessionModel.SessionState.READY)
	_sync_agent_mode()
	_refresh_account()
	connected.emit()
	return true


## Manda un turno. `extra_blocks` son ContentBlocks de contexto (escena, selección, imagen…).
## En modo Revisar, un bloque `findings` en la respuesta reemplaza la revisión, salvo que
## `collect_findings` sea false (preguntas sobre un hallazgo).
func send_prompt(text: String, extra_blocks: Array = [], collect_findings: bool = true) -> String:
	if usage_query.running:
		await usage_query.done
	if model.state != SessionModel.SessionState.READY:
		return ""
	var turn_started := int(Time.get_unix_time_from_system())
	if not _sending_fix:
		_fix_turns = 0
	var blocks: Array = []
	# Un comando (`/remote-control`, `/compact`, una skill) va solo, sin el contexto del harness ni
	# los adjuntos: el agente solo lo reconoce si el prompt empieza con él, y el adapter de Claude
	# intercepta `/remote-control` solo si es el único bloque. El contexto viaja con el próximo prompt.
	var is_command := is_slash_command(text)
	var includes_system_prompt := not _system_prompt_sent and not is_command
	if includes_system_prompt:
		blocks.append({"type": "text", "text": system_prompt()})
		_system_prompt_sent = true
	if is_command:
		blocks.append({"type": "text", "text": text.strip_edges()})
	else:
		if not _note_for_agent.is_empty():
			blocks.append({"type": "text", "text": _note_for_agent})
			_note_for_agent = ""
		blocks.append_array(extra_blocks)
		blocks.append({"type": "text", "text": text})
	var attachments: Array[Dictionary] = []
	for block: Variant in extra_blocks:
		if block is Dictionary:
			attachments.append(block)
	model.add_user_message(text, attachments)
	_outside_turn_noticed = false
	if history:
		history.record_prompt(text)
	model.set_state(SessionModel.SessionState.PROMPTING)
	var first_new_entry := model.entries().size()
	var turn_start := ""
	if not is_command and snapshots and snapshots.available and model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		turn_start = await snapshots.take(session_key)
	# Si se acaba de cambiar de modo, el turno espera a que el agente esté en el modo que corresponde.
	while _mode_syncs_running > 0:
		await agent_mode_synced
	if model.state != SessionModel.SessionState.PROMPTING:  # cancelado mientras esperaba
		_system_prompt_sent = _system_prompt_sent and not includes_system_prompt
		if model.state == SessionModel.SessionState.CANCELLING:
			model.finish_turn("cancelled")
		_record_turn_end("cancelled")
		return "cancelled"

	var result := await client.request("session/prompt", {"sessionId": model.session_id, "prompt": blocks})
	var turn_text := agent_text_since(first_new_entry)
	if is_command and text.strip_edges().begins_with("/remote-control"):
		_observe_remote_control(turn_text)
	quota.observe_agent_text(turn_text)
	if collect_findings and model.harness_mode == SessionModel.HarnessMode.REVIEW:
		if review.ingest_turn_text(turn_text, cwd):
			_fold_findings(first_new_entry)
	if turn_text.contains("\"playtest\""):
		var playtest: Dictionary = ReviewStore.FindingsParser.parse(turn_text, cwd).playtest
		if not playtest.is_empty():
			var notice := ReviewStore.playtest_notice(playtest)
			model.add_notice(notice.text, notice.level)
	if not result.ok:
		quota.observe_prompt_error(result.error)
		if model.state in [SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]:
			var login_actions: Array[Dictionary] = []
			if is_auth_required(result.error):
				login_actions = _login_actions()
			if not login_actions.is_empty():
				agent_log.add(AgentLog.CH_PROC, "The turn ended with an error: %s" % result.error_message())
				model.add_notice(I18n.t("Sign in to %s again to continue.") % _agent_name(), ChatEntry.NoticeLevel.INFO, login_actions)
			else:
				agent_log.add(AgentLog.CH_ACP, "The turn ended with an error: %s" % result.error_message())
				model.add_notice(I18n.t("The turn ended with an error: %s") % result.error_message(), ChatEntry.NoticeLevel.ERROR, _error_actions())
			model.finish_turn("error")
		_record_turn_end("error")
		return "error"
	var stop_reason := "end_turn"
	if result.result is Dictionary:
		stop_reason = str(result.result.get("stopReason", stop_reason))
		last_turn_usage = result.result.get("usage", {}) if result.result.get("usage") is Dictionary else {}
	if stop_reason == "end_turn" and quota.matching_line(turn_text).is_empty():
		quota.observe_turn_ok()
	model.finish_turn(stop_reason)
	_record_turn_end(stop_reason)
	if not is_command and model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		_report_turn_changes.call_deferred(turn_start, first_new_entry)
	if stop_reason == "end_turn" and not is_command:
		_verify_turn.call_deferred(turn_started)
	_query_agent_usage()
	return stop_reason


## Antigravity (`/usage`) y Codex (`/status`) no mandan la cuota en usage_update: la dice su comando
## local, que no gasta tokens. Se le pide al abrir la sesión y después de cada turno, sin que la
## pregunta ni la respuesta aparezcan en el chat; un prompt del usuario que llega en el medio espera.
func _query_agent_usage() -> void:
	var command := adapter.quota_command(model)
	if command.is_empty() or model.state != SessionModel.SessionState.READY or usage_query.running:
		return
	var text: Variant = await usage_query.run(command, model.session_id, func() -> bool: return _process != null)
	if text is String:
		adapter.read_quota(text, quota, model, _current_model_name())


## Cancela con `$/cancel_request` un `/usage`, `/status` o apertura de sesión que ya no se espera (m11-18).
func _cancel_abandoned_requests() -> void:
	usage_query.cancel_abandoned()
	if _session_request_id > 0:
		var sid := _session_request_id
		_session_request_id = 0
		client.cancel_request(sid)
func _current_model_name() -> String:
	var option := model.config_option("model")
	var value := str(option.get("currentValue", ""))
	for item: Variant in option.get("options", []):
		if item is Dictionary and str(item.get("value", "")) == value:
			return str(item.get("name", value))
	return value


## Cierra la sesión de la cuenta en el agente (ACP `logout`) y lo detiene: la próxima sesión pide
## login. Las credenciales las borra el agente; el addon no las ve.
func logout() -> bool:
	if not model.supports_logout() or not is_connected_to_agent():
		return false
	var result := await client.request("logout", {})
	if not result.ok:
		model.add_notice(I18n.t("Could not sign out: %s") % result.error_message(), ChatEntry.NoticeLevel.ERROR)
		return false
	agent_log.add(AgentLog.CH_PROC, "Signed out")
	var name := _profile.display_name if _profile else str(model.agent_info.get("title", ""))
	quota.forget_account()
	_agent_account = {}
	model.set_account({})
	stop()
	model.add_notice(I18n.t("Signed out of %s. Start a session to sign in with another account.") % name)
	return true


## Al terminar un turno de Construir o Auto, un aviso con lo que dejó: los archivos que cambió (si
## hay snapshot) con las acciones para verlos y volver atrás (m11-02), y «Guardar reporte» con eso y
## las capturas que tomó (m11-06). Sin cambios ni capturas, nada.
func _report_turn_changes(turn_start: String, first_entry: int = -1) -> void:
	var data := {"session": session_key, "start": turn_start, "end": "", "files": [], "first_entry": first_entry}
	var parts: PackedStringArray = []
	var actions: Array[Dictionary] = []
	if not turn_start.is_empty():
		data.end = await snapshots.take(session_key)
		if not str(data.end).is_empty():
			var changes: Dictionary = await snapshots.diff(turn_start, data.end)
			data.files = changes.files
			if not changes.files.is_empty():
				var names := PackedStringArray(changes.files.slice(0, 4).map(func(file: Dictionary) -> String: return str(file.path).get_file()))
				if changes.files.size() > 4:
					names.append("…")
				var summary := I18n.t("This turn changed 1 file (+%d −%d): %s") % [changes.added, changes.removed, ", ".join(names)] if changes.files.size() == 1 else I18n.t("This turn changed %d files (+%d −%d): %s") % [changes.files.size(), changes.added, changes.removed, ", ".join(names)]
				parts.append(summary)
				actions.append({"id": ACTION_TURN_CHANGES, "label": I18n.t("View changes"), "data": data})
				actions.append({"id": ACTION_TURN_RESTORE, "label": I18n.t("Undo turn"), "data": data, "tooltip": I18n.t("Go back to before this turn")})
	var captures: int = TurnReport.collect(model, first_entry).images.size() if first_entry >= 0 else 0
	if captures > 0:
		parts.append(I18n.t("%d captures of the game or the editor.") % captures)
	if parts.is_empty():
		return
	if first_entry >= 0:
		actions.append({"id": ACTION_TURN_REPORT, "label": I18n.t("Save report"), "data": data})
	var entry := model.add_notice(" ".join(parts), ChatEntry.NoticeLevel.INFO, actions)
	entry.footer = true
	model.notify_entry_changed(entry)


## Para el próximo prompt: el agente se entera de que el usuario volvió archivos atrás.
func note_for_agent(text: String) -> void:
	_note_for_agent = text if _note_for_agent.is_empty() else _note_for_agent + "\n" + text


## Después de un turno de Construir o Auto, valida los scripts que cambiaron. Si alguno no parsea,
## se lo devuelve al agente en un turno nuevo (hasta MAX_FIX_TURNS seguidos) o, si no se puede
## (tope, cola del usuario esperando, otro turno en curso), lo deja como aviso en el chat.
func _verify_turn(turn_started: int) -> void:
	if not turn_verifier.is_valid() or not model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		return
	var errors: String = await turn_verifier.call(turn_started)
	if errors.is_empty():
		return
	agent_log.add(AgentLog.CH_PROC, "Check after the turn: scripts with errors\n%s" % errors)
	if _fix_turns < MAX_FIX_TURNS and model.state == SessionModel.SessionState.READY:
		_fix_turns += 1
		model.add_notice(I18n.t("Check after the turn: some scripts don't parse. The agent gets the errors to fix them (%d of %d).") % [_fix_turns, MAX_FIX_TURNS], ChatEntry.NoticeLevel.WARNING)
		_sending_fix = true
		send_prompt("[Automatic check after your turn] These scripts you changed don't parse. Fix them, then check again with godot.validate_scripts:\n" + errors)
		_sending_fix = false
	else:
		model.add_notice(I18n.t("Check after the turn: some scripts don't parse.") + "\n" + errors, ChatEntry.NoticeLevel.WARNING)


## Lo que contestó el adapter a `/remote-control` (claude-agent-acp 0.94, runRemoteControlCommand):
## «Remote Control is active… <link>» o «Remote Control is off…». Un error deja el estado como estaba.
func _observe_remote_control(turn_text: String) -> void:
	var link := RegEx.create_from_string("https://claude\\.ai/code/\\S+").search(turn_text)
	if turn_text.contains("Remote Control is active") and link:
		model.set_remote_control(link.get_string())
		agent_log.add(AgentLog.CH_ACP, "Remote Control on: %s" % link.get_string())
	elif turn_text.contains("Remote Control is off"):
		model.set_remote_control("")
		agent_log.add(AgentLog.CH_ACP, "Remote Control off")


## Prende o apaga Remote Control. El nombre de la sesión en claude.ai es el del proyecto.
func remote_control_command(enable: bool) -> String:
	if not enable:
		return "/remote-control off"
	var project_name := str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	return "/remote-control %s" % (project_name if not project_name.is_empty() else cwd.get_file())


## true si el texto es un comando del agente: empieza con `/` seguido de un nombre (no una ruta).
static func is_slash_command(text: String) -> bool:
	return RegEx.create_from_string("^/[A-Za-z][\\w:.-]*(\\s|$)").search(text.strip_edges()) != null


## Texto del agente en el turno: ahí llegan los avisos de límite (D22) y los bloques de hallazgos.
func agent_text_since(first_entry: int) -> String:
	var parts: PackedStringArray = []
	var entries := model.entries()
	for i in range(first_entry, entries.size()):
		if entries[i].kind == ChatEntry.EntryKind.AGENT:
			parts.append(entries[i].text)
	return "\n".join(parts)


## Los mensajes del turno con el bloque `findings` ya leído lo muestran plegado (m12-38).
func _fold_findings(first_entry: int) -> void:
	var entries := model.entries()
	for i in range(first_entry, entries.size()):
		var entry: ChatEntry = entries[i]
		if entry.kind == ChatEntry.EntryKind.AGENT and entry.text.contains("\"findings\""):
			entry.findings_count = review.findings.size()
			model.entry_updated.emit(entry)


## Cambia el modo del harness y manda el turno cuando el agente ya está en el modo que corresponde.
func send_in_mode(mode: SessionModel.HarnessMode, text: String) -> String:
	if model.harness_mode != mode:
		model.set_harness_mode(mode)
	return await send_prompt(text)


func cancel() -> void:
	if model.state != SessionModel.SessionState.PROMPTING:
		return
	model.set_state(SessionModel.SessionState.CANCELLING)
	client.notify("session/cancel", {"sessionId": model.session_id})
	model.cancel_pending_permissions()


func set_config_option(id: String, value: String) -> bool:
	if model.session_id.is_empty():
		return false
	var result := await client.request("session/set_config_option", {"sessionId": model.session_id, "configId": id, "value": value})
	if not result.ok:
		model.add_notice(I18n.t("Could not change '%s': %s") % [id, result.error_message()], ChatEntry.NoticeLevel.WARNING)
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
	cancel_login()
	if terminal:
		terminal.stop_all()
	if _process:
		var process := _process
		_process = null
		process.stop()
		agent_log.add(AgentLog.CH_PROC, "Process stopped")
	client.fail_all_pending("Session stopped.")
	model.cancel_pending_permissions()
	if history:
		history.end()
	if model.state != SessionModel.SessionState.DISCONNECTED and model.state != SessionModel.SessionState.FAILED:
		model.set_state(SessionModel.SessionState.DISCONNECTED)
		disconnected.emit()


func client_capabilities() -> Dictionary:
	var capabilities := {
		"fs": {
			"readTextFile": client.has_request_handler("fs/read_text_file"),
			"writeTextFile": client.has_request_handler("fs/write_text_file"),
		},
		"terminal": client.has_request_handler("terminal/create"),
		# Login con el comando del agente (claude-agent-acp ofrece entonces «Claude Subscription» y
		# «Anthropic Console»). El agente guarda sus credenciales; el addon no las ve.
		"auth": {"terminal": true},
		# Subagentes nativos (RFD de ACP, m7-43): el agente anuncia cada subagente con su sesión y su
		# estado, que sigue después del tool call que lo lanzó si corre en segundo plano.
		"subagents": {},
	}
	if client.has_request_handler("elicitation/create"):
		capabilities["elicitation"] = {"form": {}, "url": {}}
	return capabilities


static func is_auth_required(error: Dictionary) -> bool:
	return int(error.get("code", 0)) == AUTH_REQUIRED_CODE and str(error.get("message", "")).to_lower().begins_with(AUTH_REQUIRED_MESSAGE)


# --- login (ACP auth) ----------------------------------------------------------------------------

func is_logging_in() -> bool:
	return _login != null and _login.is_running()


## Inicia sesión con el método `method_id` de `authMethods`. Los `terminal` corren el login del
## agente (navegador); los demás se le piden al agente con `authenticate`. Al terminar bien vuelve
## a lanzar el agente para abrir la sesión con las credenciales nuevas.
func login(method_id: String) -> void:
	var method := {}
	for item: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		if item.id == method_id:
			method = item
	if method.is_empty() or _profile == null:
		model.add_notice(I18n.t("The agent does not offer that sign-in method."), ChatEntry.NoticeLevel.WARNING)
		return
	cancel_login()
	var label := AgentLogin.label_of(method)
	agent_log.add(AgentLog.CH_PROC, "Sign-in: %s" % label)
	if not AgentLogin.is_terminal(method):
		_login_entry = model.add_notice(I18n.t("Signing in with %s…") % label)
		var result := await client.request("authenticate", {"methodId": method_id})
		_on_login_finished(result.ok, result.error_message() if not result.ok else "")
		return
	_login = AgentLogin.new()
	_login.url_found.connect(_on_login_url)
	_login.finished.connect(_on_login_finished)
	_login_entry = model.add_notice(I18n.t("Signing in with %s: finish in the browser that just opened.") % label,
		ChatEntry.NoticeLevel.INFO, [{"id": ACTION_LOGIN_CANCEL, "label": I18n.t("Cancel")}])
	var command := AgentLogin.command_for(method, _profile)
	agent_log.add(AgentLog.CH_PROC, "Login: %s %s" % [command.command, " ".join(command.args)])
	_login.start(method, _profile)


## El código que muestra la página de login si el navegador no volvió solo.
func send_login_code(code: String) -> bool:
	if not is_logging_in():
		return false
	agent_log.add(AgentLog.CH_PROC, "Login: code sent")  # nunca el código
	return _login.send_code(code)


func cancel_login() -> void:
	if _login == null:
		return
	var login_run := _login
	_login = null
	if login_run.is_running():
		login_run.cancel()
		if _login_entry:
			_set_login_notice(I18n.t("Sign-in cancelled."), ChatEntry.NoticeLevel.INFO, [])
	_login_entry = null


func _on_login_url(url: String) -> void:
	_set_login_notice(I18n.t("Signing in with %s: finish in the browser. If it did not open, open the link; if the page gives you a code, paste it here.") % AgentLogin.label_of(_login.method),
		ChatEntry.NoticeLevel.INFO, [
			{"id": "open_link", "label": I18n.t("Open link"), "data": url},
			{"id": ACTION_LOGIN_CODE, "label": I18n.t("Paste code…")},
			{"id": ACTION_LOGIN_CANCEL, "label": I18n.t("Cancel")},
		])


func _on_login_finished(ok: bool, message: String) -> void:
	_login = null
	if not ok:
		agent_log.add(AgentLog.CH_PROC, "Login failed: %s" % message)
		_set_login_notice(I18n.t("Could not sign in: %s") % message, ChatEntry.NoticeLevel.ERROR, _login_actions())
		_login_entry = null
		return
	agent_log.add(AgentLog.CH_PROC, "Login complete")
	_login_entry = null
	if after_login.is_valid() and await after_login.call():
		model.add_notice(I18n.t("Signed in."))
		return
	if _profile and await start(_profile):
		model.add_notice(I18n.t("Signed in."))


func _set_login_notice(text: String, level: ChatEntry.NoticeLevel, actions: Array[Dictionary]) -> void:
	if _login_entry == null:
		_login_entry = model.add_notice(text, level, actions)
		return
	_login_entry.text = text
	_login_entry.level = level
	_login_entry.actions = actions
	model.notify_entry_changed(_login_entry)


## Métodos de login que el addon sabe correr: {id, label}. Para «Cambiar de cuenta».
func login_methods() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for method: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		result.append({"id": str(method.id), "label": AgentLogin.label_of(method)})
	return result


## Un botón por método que el addon sabe usar.
## El primer método como botón principal; los demás, en el menú «Otras formas de entrar» (m12-11).
func _login_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for method: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		var action := {"id": ACTION_LOGIN, "label": AgentLogin.label_of(method), "data": str(method.id)}
		if actions.is_empty():
			action["primary"] = true
		else:
			action["more"] = I18n.t("Other ways to sign in")
		actions.append(action)
	return actions


func _agent_name() -> String:
	return _profile.display_name if _profile else I18n.t("the agent")


func system_prompt() -> String:
	var template := FileAccess.get_file_as_string(SYSTEM_PROMPT_PATH)
	var variables: Dictionary = prompt_variables_provider.call() if prompt_variables_provider.is_valid() else {}
	variables["mode"] = SessionModel.HARNESS_MODE_LABELS[model.harness_mode]
	variables["mode_rules"] = mode_rules_override if not mode_rules_override.is_empty() else MODE_RULES[model.harness_mode]
	variables["project_path"] = variables.get("project_path", cwd)
	variables["project_name"] = variables.get("project_name", cwd.get_file())
	variables["godot_version"] = variables.get("godot_version", Engine.get_version_info().string)
	variables["godot_bin"] = variables.get("godot_bin", EditorBinary.path())
	return "<harness_context>\n%s\n</harness_context>" % template.format(variables)


## Pide permiso según la política del modo actual (ver PermissionBroker.authorize).
func authorize(group: String, title: String, description: String, diff: Dictionary = {}, timeout_s: int = 0) -> bool:
	return await permissions.authorize(group, title, description, diff, timeout_s)


## MCP servers de terceros (configurados o ya vistos) que en `mode` preguntan o se niegan.
func mcp_servers_not_allowed(mode: SessionModel.HarnessMode) -> PackedStringArray:
	return permissions.mcp_servers_not_allowed(mode, external_mcp_names)


# --- internos ------------------------------------------------------------------------------------

## El agente retiró un pedido de permiso o formulario: lo contestaron desde Remote Control o ya no hace falta.
func _on_incoming_cancelled(id: Variant) -> void:
	permissions.withdraw(id)
	var elicitation: ElicitationRequest = _elicitations_by_acp_id.get(id)
	if elicitation and elicitation.is_pending():
		elicitation.withdrawn = true
		elicitation.cancel()


## Formulario o enlace del agente (`elicitation/create`, m11-17): muestra la tarjeta y devuelve la respuesta.
func _on_create_elicitation(params: Dictionary) -> Variant:
	var acp_id: Variant = client.handling_id
	var request := ElicitationRequest.from_params(params)
	var invalid: String = request.invalid_reason()
	if not invalid.is_empty():
		agent_log.add(AgentLog.CH_PERM, "elicitation rejected: %s" % invalid)
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, invalid)
	if acp_id != null:
		_elicitations_by_acp_id[acp_id] = request
	model.add_elicitation(request)
	var response: Dictionary = request.response
	if request.is_pending():
		response = await request.resolved
		if not request.withdrawn:
			await PermissionBroker.next_frame()  # como en PermissionBroker.ask_user: fuera de quien respondió
	if acp_id != null and _elicitations_by_acp_id.get(acp_id) == request:
		_elicitations_by_acp_id.erase(acp_id)
	return response


## Notificación `elicitation/complete` (m11-17): cierra el formulario/enlace con ese `elicitationId`.
func _on_complete_elicitation(params: Dictionary) -> void:
	model.complete_elicitation(str(params.get("elicitationId", "")))


func _terminal_base_env() -> Dictionary:
	var profile_env: Dictionary = _profile.resolved_env() if _profile else {}
	var base_path := CommandResolver.child_path_for(CommandResolver.resolve(_profile.command)) if _profile else ""
	return EditorBinary.child_env(profile_env, base_path)


## Pide al CLI de Claude Code con qué cuenta está logueado el perfil (su CLAUDE_CONFIG_DIR) y la
## deja en el modelo. Otros agentes no la informan: queda vacía.
func _refresh_account() -> void:
	var profile := _profile
	if profile == null or not adapter.reads_account_from_cli():
		# La que mandó el agente con _auth/status_update (llega una vez, antes de session/new).
		model.set_account(_agent_account if profile == _agent_account_profile else {})
		return
	var cli := ClaudeCli.new(cwd, profile.resolved_env())
	var account := await cli.auth_status() if cli.is_available() else {}
	if profile == _profile:  # no se cambió de agente mientras tanto
		model.set_account(account)
		if not account.is_empty():
			# Sin el email: el log se pega en reportes de bugs.
			agent_log.add(AgentLog.CH_PROC, "Logged in (%s, %s plan)" % [account.method, account.plan])


## Notificación `_auth/status_update` (extensión ACP de `codex-acp`): actualiza la cuenta del modelo.
func _on_auth_status_update(params: Dictionary) -> void:
	var status: Variant = params.get("authStatus")
	if not status is Dictionary:
		return
	var kind := str(status.get("kind", ""))
	_agent_account_profile = _profile
	if kind == "none":
		_agent_account = {}
		model.set_account({})
		return
	var acc: Dictionary = status.get("account") if status.get("account") is Dictionary else {}
	_agent_account = {
		"email": str(acc.get("email", "")),
		"org": str(acc.get("organization", "")),
		"plan": str(acc.get("plan", "")),
		"method": str(status.get("label", kind)),
	}
	model.set_account(_agent_account)


func _send_line(line: String) -> bool:
	return _process != null and _process.send_line(line)


## Durante session/load el agente vuelve a mandar toda la conversación; acá se descarta, porque
## model.session_id recién se asigna con la respuesta y el dock ya la armó desde el historial.
func _on_session_update(params: Dictionary) -> void:
	if not params.get("update") is Dictionary:
		return
	if params.get("sessionId") != model.session_id:
		if params.get("sessionId") is String and not model.session_id.is_empty():
			model.apply_child_update(params.sessionId, params.update)
		return
	if usage_query.capture(params.update):
		return
	if params.update.get("sessionUpdate") == "usage_update":
		quota.observe_update(params.update)
	elif params.update.get("sessionUpdate") == "session_info_update":
		quota.observe_session_info(params.update)
	_notice_outside_turn(params.update)
	if not model.apply_update(params.update):
		agent_log.add(AgentLog.CH_ACP, "Unknown session/update variant, ignored: %s" % str(params.update.get("sessionUpdate", "?")))
	elif history:
		history.record_update(params.update)


## Claude Code arranca un turno solo cuando le llega un mensaje de otra sesión suya (SendMessage) o
## termina una tarea en segundo plano, y claude-agent-acp (0.98) no reenvía ese mensaje: el chat
## vería la respuesta sin la pregunta. Se avisa una vez hasta el próximo prompt. Un mensaje de Remote
## Control sí llega (user_message_chunk) y no lleva aviso.
func _notice_outside_turn(update: Dictionary) -> void:
	if model.state != SessionModel.SessionState.READY or _outside_turn_noticed or not model.parent_tool_call_id(update).is_empty():
		return
	var kind := str(update.get("sessionUpdate", ""))
	if kind == "user_message_chunk":
		_outside_turn_noticed = true
	elif kind in ["agent_message_chunk", "agent_thought_chunk", "tool_call"]:
		_outside_turn_noticed = true
		model.add_notice(I18n.t("The agent is answering something it received outside this chat (a message from another Claude Code session or a background task that finished): the editor only gets its answer. To see the messages between sessions, ask the agents to use godot.session_send."))


func _record_turn_end(stop_reason: String) -> void:
	if history:
		history.record_turn_end(stop_reason)


## Reanuda una sesión del historial o de `session/list` (m11-16): si hay registro local, arma la
## conversación desde el archivo y usa `session/resume` (sin replay) o `session/load`; si viene solo
## del agente, `session/load` reconstruye la conversación o `session/resume` retoma el contexto.
func _load_session(record: Dictionary, generation: int) -> bool:
	var session_id := str(record.get("id", ""))
	var has_local_events := record.get("events") is Array and not (record.events as Array).is_empty()
	if has_local_events:
		SessionHistory.replay(record, model)
	if not model.can_resume_sessions():
		_load_failed = true
		stop()
		model.add_notice(I18n.t("%s cannot resume sessions (it does not announce session/load): the history stays read-only. Type to start a new session.") % _profile.display_name)
		return false
	var use_resume := (has_local_events and model.supports_resume_session()) or not model.supports_load_session()
	var method := "session/resume" if use_resume else "session/load"
	if not has_local_events and method == "session/load":
		# Sin historial local, dejamos que los updates del replay entren al modelo y al historial.
		model.session_id = session_id
		if history and _profile:
			history.begin(session_id, _profile.id, _profile.display_name, cwd, record)
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	_cancel_abandoned_requests()
	var req_id := client.next_request_id()
	_session_request_id = req_id
	var result := await client.request(method, _with_meta({"sessionId": session_id, "cwd": cwd, "mcpServers": mcp_servers}))
	if _session_request_id == req_id:
		_session_request_id = 0
	if generation != _connect_generation or result.error.get("code") == AcpClient.ERR_REQUEST_CANCELLED:
		return false
	if not result.ok:
		_load_failed = true
		stop()
		model.add_notice(I18n.t("Could not resume the session: %s. The history stays read-only.") % result.error_message(), ChatEntry.NoticeLevel.WARNING)
		return false
	model.apply_session(session_id, result.result if result.result is Dictionary else {})
	var remote_title := str(record.get("title", ""))
	if not remote_title.is_empty() and model.title.is_empty():
		model.apply_update({"sessionUpdate": "session_info_update", "title": remote_title})
	_system_prompt_sent = true  # ya está en el contexto que el agente recuperó
	policy.clear_session()
	permissions.reset()
	if history and _profile and (has_local_events or method == "session/resume"):
		history.begin(session_id, _profile.id, _profile.display_name, cwd, record)
	model.set_state(SessionModel.SessionState.READY)
	var resumed_msg := I18n.t("Session resumed: the agent recovered its context with session/resume.") if use_resume else I18n.t("Session resumed: the agent recovered its context with session/load.")
	model.add_notice(resumed_msg)
	_sync_agent_mode()
	_refresh_account()
	connected.emit()
	return true


## Pide al agente sus sesiones de `filter_cwd` con `session/list` (m11-16).
func list_agent_sessions(filter_cwd: String = cwd) -> Array[Dictionary]:
	return await sessions.list(filter_cwd, _agent_running(), _profile)


func _refresh_agent_sessions() -> void:
	if model.supports_list_sessions():
		await list_agent_sessions(cwd)


## Cierra una sesión en el agente con `session/close` (m11-16) si lo soporta.
func close_session(target_session_id: String = "") -> bool:
	return await sessions.close(target_session_id if not target_session_id.is_empty() else model.session_id, _agent_running())


## Elimina una sesión del historial local y, si es del perfil conectado y el agente soporta
## `session/delete`, también en el agente. Si el agente no la borra, la local queda.
func delete_session(target_session_id: String, session_profile_id: String = "") -> bool:
	var same_agent := _profile != null and (session_profile_id.is_empty() or session_profile_id == _profile.id)
	return await sessions.delete(target_session_id, same_agent and _agent_running(), history)


func _agent_running() -> bool:
	return _process != null and _process.is_running()


func _with_meta(params: Dictionary) -> Dictionary:
	var meta: Dictionary = session_meta_provider.call() if session_meta_provider.is_valid() else {}
	if not meta.is_empty():
		params._meta = meta
	return params


func _on_stderr(line: String) -> void:
	agent_log.add(AgentLog.CH_PROC, line)
	_stderr_tail.append(line)
	if _stderr_tail.size() > STDERR_TAIL:
		_stderr_tail.remove_at(0)


func _on_process_exited(code: int, process: AgentProcess) -> void:
	if process != _process:
		return
	_process = null
	process.stop()
	if terminal:
		terminal.stop_all()
	client.fail_all_pending("The agent exited (code %d)." % code)
	_fail_agent(I18n.t("%s stopped") % _agent_name(),
		I18n.t("The agent's process ended unexpectedly (code %d).") % code,
		"The agent exited unexpectedly (code %d)." % code, _crash_actions())
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
			_mode_syncs_running += 1
			var result := await client.request("session/set_mode", {"sessionId": model.session_id, "modeId": candidate})
			_mode_syncs_running -= 1
			agent_mode_synced.emit()
			if result.ok:
				model.apply_update({"sessionUpdate": "current_mode_update", "currentModeId": candidate})
			return


func _fail(message: String, extra_actions: Array[Dictionary] = [], level := ChatEntry.NoticeLevel.ERROR, with_error_actions := true) -> void:
	model.failure_message = message
	agent_log.add(AgentLog.CH_PROC, message)
	var actions := extra_actions.duplicate()
	if with_error_actions:
		actions.append_array(_error_actions())
	model.add_notice(message, level, actions)
	model.set_state(SessionModel.SessionState.FAILED)


## Error al lanzar o mantener el agente (m12-13): título y causa para personas, las últimas líneas
## de su stderr y la acción que lo arregla. `log_message` va al log y al tooltip del estado.
func _fail_agent(title: String, cause: String, log_message: String, actions: Array[Dictionary]) -> void:
	model.failure_message = log_message
	agent_log.add(AgentLog.CH_PROC, log_message)
	for action: Dictionary in actions:
		if action.id == ACTION_SHOW_LOG:
			action["data"] = agent_log.last_seq()
	var entry := model.add_notice(cause, ChatEntry.NoticeLevel.ERROR, actions)
	entry.title = title
	entry.details = "\n".join(_stderr_tail)
	model.notify_entry_changed(entry)
	model.set_state(SessionModel.SessionState.FAILED)


## Reintentar primero; un agente del registro (binario bajado por el harness) se puede reinstalar.
func _crash_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = [{"id": ACTION_RETRY, "label": I18n.t("Retry"), "primary": true}]
	if _profile and is_registry_binary(_profile.command):
		actions.append({"id": ACTION_REINSTALL_AGENT, "label": I18n.t("Reinstall…")})
	actions.append({"id": ACTION_SHOW_LOG, "label": I18n.t("Open the log below")})
	return actions


## El comando es un binario que bajó el registro de ACP (`<datos del editor>/godot_agent/agents/`).
static func is_registry_binary(command: String) -> bool:
	return command.replace("\\", "/").contains("/godot_agent/agents/")


## «Abrir el log abajo» lleva el `seq` de la última línea del log (la del error): el panel salta ahí (m12-36).
func _error_actions() -> Array[Dictionary]:
	return [{"id": ACTION_RETRY, "label": I18n.t("Retry")}, {"id": ACTION_SHOW_LOG, "label": I18n.t("Open the log below"), "data": agent_log.last_seq()}]


func _auth_hint() -> String:
	var names: PackedStringArray = []
	for method: Variant in model.auth_methods:
		if method is Dictionary:
			names.append("%s (%s)" % [method.get("name", method.get("id", "?")), method.get("description", "")])
	return ", ".join(names)


func _on_terminal_output(terminal_id: String, output: String, exit_code: Variant) -> void:
	model.set_terminal_output(terminal_id, output, exit_code)


func _on_config_options_changed(_options: Array) -> void:
	adapter.model_changed(quota, _current_model_name())
