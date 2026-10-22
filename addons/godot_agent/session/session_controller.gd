@tool
extends RefCounted
## Comandos de la sesión: conecta el proceso del agente, hace initialize → session/new, manda
## prompts, cancela y cambia opciones. Aplica lo que llega al SessionModel.
## No depende del editor: lo que necesita del editor (contexto, fs, permisos, MCP) se inyecta.

signal connected
signal disconnected
## Terminó la sincronización del modo del agente con el del harness (session/set_mode).
signal agent_mode_synced

const AgentProcess := preload("../transport/agent_process.gd")
const AcpClient := preload("../acp/acp_client.gd")
const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const ToolCall := preload("tool_call.gd")
const AgentLog := preload("../core/agent_log.gd")
const AgentProfile := preload("../core/agent_profile.gd")
const PermissionPolicy := preload("permission_policy.gd")
const PermissionRequest := preload("permission_request.gd")
const FsHandler := preload("../acp/fs_handler.gd")
const LineDiff := preload("../core/line_diff.gd")
const QuotaMonitor := preload("../core/quota_monitor.gd")
const ReviewStore := preload("../review/review_store.gd")
const SessionHistory := preload("session_history.gd")
const AgentLogin := preload("agent_login.gd")
const EditorBinary := preload("../transport/editor_binary.gd")
const CommandResolver := preload("../transport/command_resolver.gd")
const I18n := preload("../core/i18n.gd")

const PROTOCOL_VERSION := 1
const CLIENT_NAME := "godot-agent-harness"
const CLIENT_TITLE := "Godot Agent Harness"
const CLIENT_VERSION := "0.1.0"
const SYSTEM_PROMPT_PATH := "res://addons/godot_agent/config/system_prompt.md"

## Acciones que ofrecen los avisos de error (spec §15).
const ACTION_RETRY := "retry"
const ACTION_SHOW_LOG := "show_log"
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
const PREAUTHORIZED_WRITE_MS := 120000

const MODE_RULES: Dictionary = {
	SessionModel.HarnessMode.ASK: "Only answer questions: do not modify files, scenes or settings, and do not run commands.",
	SessionModel.HarnessMode.REVIEW: "Read-only review: do not modify anything. Report the findings in a ```json block with {\"findings\":[{\"path\",\"line\",\"severity\":\"bug|order|perf|style\",\"title\",\"body\",\"suggestion\"}]} (path relative to the project, line starting at 1). Each block replaces the previous review: include every finding that still applies.",
	SessionModel.HarnessMode.BUILD: "You can edit scenes and scripts; the user approves the changes.",
	SessionModel.HarnessMode.ONESHOT: "Work autonomously until the goal is met; verify with run_scene, capture_game_frame and get_errors after each task.",
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
var policy: PermissionPolicy = PermissionPolicy.new()
var fs: FsHandler
var agent_log: AgentLog
## Cuota del plan (spec §10.1): estado, ventanas y límite; la UI y el One-shot la leen de acá.
var quota: QuotaMonitor
## Hallazgos de la última revisión (modo Revisar, spec §9.4).
var review: ReviewStore = ReviewStore.new()
## Historial en disco (M7). null = no se graba (tests).
var history: SessionHistory
## `usage` del último session/prompt (tokens del turno: inputTokens, outputTokens, cachedReadTokens…).
var last_turn_usage: Dictionary = {}
## Directorio de trabajo para session/new (ruta absoluta del proyecto).
var cwd: String = ""
## Callable() -> Array: entradas `mcpServers` para session/new (el server del addon, M3).
var mcp_servers_provider: Callable
## Callable() -> Dictionary: variables para el prompt de sistema ({project_name}, …).
var prompt_variables_provider: Callable
## Después de un login exitoso: si devuelve true, ya se ocupó de la sesión (el One-shot retoma la
## suya con la cuenta nueva) y no se abre una sesión nueva.
var after_login: Callable

var _process: AgentProcess
var _profile: AgentProfile
var _system_prompt_sent: bool = false
var _connect_generation: int = 0
var _preauthorized_writes: Dictionary = {}  # ruta absoluta -> vencimiento (msec)
var _mode_syncs_running: int = 0
## El último _load_session falló por el agente (sin loadSession o error), no por una cancelación.
var _load_failed: bool = false
var _login: AgentLogin
## Aviso del login en curso (se actualiza con el enlace y el resultado).
var _login_entry: ChatEntry


func setup(session_model: SessionModel, log_sink: AgentLog, working_dir: String) -> void:
	model = session_model
	agent_log = log_sink
	cwd = working_dir
	client = AcpClient.new()
	client.setup(_send_line, agent_log)
	quota = QuotaMonitor.new()
	quota.setup(agent_log)
	client.set_notification_handler("session/update", _on_session_update)
	client.set_request_handler("session/request_permission", _on_request_permission)
	model.harness_mode_changed.connect(_on_harness_mode_changed)


## fs/read_text_file y fs/write_text_file. Las escrituras pasan por la política (edit_files).
func set_fs_handler(handler: FsHandler) -> void:
	fs = handler
	fs.write_authorizer = _authorize_fs_write
	fs.register(client)

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
	model.reset()
	model.failure_message = ""
	model.set_state(SessionModel.SessionState.STARTING)
	agent_log.add(AgentLog.CH_PROC, "Launching %s: %s" % [agent_profile.display_name, agent_profile.command_line()])

	_process = AgentProcess.new()
	_process.line_received.connect(client.receive_line)
	_process.stderr_received.connect(_on_stderr)
	_process.exited.connect(_on_process_exited.bind(_process))
	var base_path := CommandResolver.child_path_for(CommandResolver.resolve(agent_profile.command))
	var env := EditorBinary.child_env(agent_profile.resolved_env(), base_path)
	if not _process.start(agent_profile.command, agent_profile.args, env):
		_fail(I18n.t("Could not start the agent: %s") % _process.last_error())
		_process = null
		return false
	agent_log.add(AgentLog.CH_PROC, "Process started (pid %d)" % _process.pid())

	var init := await client.request("initialize", {
		"protocolVersion": PROTOCOL_VERSION,
		"clientInfo": {"name": CLIENT_NAME, "title": CLIENT_TITLE, "version": CLIENT_VERSION},
		"clientCapabilities": client_capabilities(),
	})
	if generation != _connect_generation:
		return false
	if not init.ok or not init.result is Dictionary:
		_fail(I18n.t("The agent did not respond to initialize: %s") % init.error_message())
		return false
	model.apply_initialize(init.result)
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
	if _process == null or not _process.is_running():
		return await start(_profile) if _profile else false
	if model.state != SessionModel.SessionState.STARTING:
		model.reset()
		model.set_state(SessionModel.SessionState.STARTING)
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	var result := await client.request("session/new", {"cwd": cwd, "mcpServers": mcp_servers})
	if generation != _connect_generation:
		return false
	if not result.ok or not result.result is Dictionary or not result.result.get("sessionId") is String:
		var detail := result.error_message() if not result.ok else "response without sessionId"
		var login_actions: Array[Dictionary] = []
		var message := I18n.t("Could not open the session: %s") % detail
		if not result.ok and is_auth_required(result.error):
			login_actions = _login_actions()
			if not login_actions.is_empty():
				message = I18n.t("Could not open the session: %s. Sign in to continue.") % detail
			else:
				message = I18n.t("Could not open the session: %s. The agent asks for authentication: %s") % [detail, _auth_hint()]
		_fail(message, login_actions)
		return false
	model.apply_session(result.result.sessionId, result.result)
	_system_prompt_sent = false
	policy.clear_session()
	_preauthorized_writes.clear()
	if history:
		history.begin(model.session_id, _profile.id, _profile.display_name, cwd)
	model.set_state(SessionModel.SessionState.READY)
	_sync_agent_mode()
	connected.emit()
	return true


## Manda un turno. `extra_blocks` son ContentBlocks de contexto (escena, selección, imagen…).
## En modo Revisar, un bloque `findings` en la respuesta reemplaza la revisión, salvo que
## `collect_findings` sea false (preguntas sobre un hallazgo).
func send_prompt(text: String, extra_blocks: Array = [], collect_findings: bool = true) -> String:
	if model.state != SessionModel.SessionState.READY:
		return ""
	var blocks: Array = []
	var includes_system_prompt := not _system_prompt_sent
	if includes_system_prompt:
		blocks.append({"type": "text", "text": system_prompt()})
		_system_prompt_sent = true
	blocks.append_array(extra_blocks)
	blocks.append({"type": "text", "text": text})
	var attachments: Array[Dictionary] = []
	for block: Variant in extra_blocks:
		if block is Dictionary:
			attachments.append(block)
	model.add_user_message(text, attachments)
	if history:
		history.record_prompt(text)
	model.set_state(SessionModel.SessionState.PROMPTING)
	var first_new_entry := model.entries().size()
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
	quota.observe_agent_text(turn_text)
	if collect_findings and model.harness_mode == SessionModel.HarnessMode.REVIEW:
		review.ingest_turn_text(turn_text, cwd)
	if not result.ok:
		quota.observe_prompt_error(result.error)
		if model.state in [SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]:
			var actions: Array[Dictionary] = []
			if is_auth_required(result.error):
				actions = _login_actions()
			actions.append_array(_error_actions())
			model.add_notice(I18n.t("The turn ended with an error: %s") % result.error_message(), ChatEntry.NoticeLevel.ERROR, actions)
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
	return stop_reason


## Texto del agente en el turno: ahí llegan los avisos de límite (D22) y los bloques de hallazgos.
func agent_text_since(first_entry: int) -> String:
	var parts: PackedStringArray = []
	var entries := model.entries()
	for i in range(first_entry, entries.size()):
		if entries[i].kind == ChatEntry.EntryKind.AGENT:
			parts.append(entries[i].text)
	return "\n".join(parts)


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
	return {
		"fs": {
			"readTextFile": client.has_request_handler("fs/read_text_file"),
			"writeTextFile": client.has_request_handler("fs/write_text_file"),
		},
		"terminal": false,
		# Login con el comando del agente (claude-agent-acp ofrece entonces «Claude Subscription» y
		# «Anthropic Console»). El agente guarda sus credenciales; el addon no las ve.
		"auth": {"terminal": true},
	}


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
func _login_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for method: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		actions.append({"id": ACTION_LOGIN, "label": I18n.t("Sign in · %s") % AgentLogin.label_of(method), "data": str(method.id)})
	return actions


func system_prompt() -> String:
	var template := FileAccess.get_file_as_string(SYSTEM_PROMPT_PATH)
	var variables: Dictionary = prompt_variables_provider.call() if prompt_variables_provider.is_valid() else {}
	variables["mode"] = SessionModel.HARNESS_MODE_LABELS[model.harness_mode]
	variables["mode_rules"] = MODE_RULES[model.harness_mode]
	variables["project_path"] = variables.get("project_path", cwd)
	variables["project_name"] = variables.get("project_name", cwd.get_file())
	variables["godot_version"] = variables.get("godot_version", Engine.get_version_info().string)
	variables["godot_bin"] = variables.get("godot_bin", EditorBinary.path())
	return "<harness_context>\n%s\n</harness_context>" % template.format(variables)


## Pide permiso según la política del modo actual. `ask` muestra una tarjeta y espera.
## Devuelve true si se permitió. `timeout_s` > 0 deniega si nadie responde a tiempo.
func authorize(group: String, title: String, description: String, diff: Dictionary = {}, timeout_s: int = 0) -> bool:
	var decision := policy.decide(group, model.harness_mode)
	if decision == PermissionPolicy.ALLOW:
		_log_perm("allowed by %s mode: %s" % [_mode_label(), title])
		return true
	if decision == PermissionPolicy.DENY:
		_notify_denied(group, title)
		return false
	var request := PermissionRequest.new()
	request.title = title
	request.description = description
	request.group = group
	request.diff = diff
	request.options = PermissionRequest.default_options()
	var outcome := await _ask_user(request, timeout_s)
	return outcome.get("outcome") == "selected" and request.was_allowed()


# --- internos ------------------------------------------------------------------------------------

func _on_request_permission(params: Dictionary) -> Variant:
	var tool_call: Dictionary = params.get("toolCall", {}) if params.get("toolCall") is Dictionary else {}
	var options: Array = params.get("options", []) if params.get("options") is Array else []
	if tool_call.get("toolCallId") is String:
		var update := tool_call.duplicate()
		update["sessionUpdate"] = "tool_call_update"
		model.apply_update(update)
	var request := PermissionRequest.new()
	request.tool_call_id = str(tool_call.get("toolCallId", ""))
	request.options = options
	request.group = PermissionPolicy.group_for_tool_call(tool_call)
	var call := model.tool_call(request.tool_call_id)
	request.title = call.display_name() if call else str(tool_call.get("title", I18n.t("Agent tool")))
	var subagent: ToolCall = model.tool_call(call.parent_id) if call and not call.parent_id.is_empty() else null
	if subagent:
		request.title = I18n.t("%s · subagent «%s»") % [request.title, subagent.display_name()]
	request.description = _describe_tool_call(tool_call, call)
	request.diff = _first_diff(tool_call, call)

	var decision := policy.decide(request.group, model.harness_mode)
	if PermissionPolicy.is_godot_mcp_tool(tool_call):
		decision = PermissionPolicy.ALLOW  # el server MCP aplica la política al ejecutar la tool
	match decision:
		PermissionPolicy.ALLOW:
			_log_perm("allowed by %s mode: %s" % [_mode_label(), request.title])
			_preauthorize(request, call)
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS]))
		PermissionPolicy.DENY:
			_notify_denied(request.group, request.title)
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
	var outcome := await _ask_user(request, 0)
	if outcome.get("outcome") != "selected":
		return {"outcome": {"outcome": "cancelled"}}
	if request.was_allowed():
		_preauthorize(request, call)
		# "Siempre" queda en la memoria de la sesión del harness; al agente se le responde
		# "una vez" para que no lo guarde en sus settings en disco (spec §4.2).
		var once := request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE])
		return _selected_or_cancelled(once if not once.is_empty() else str(outcome.optionId))
	var reject_once := request.option_id_for([PermissionRequest.KIND_REJECT_ONCE])
	return _selected_or_cancelled(reject_once if not reject_once.is_empty() else str(outcome.optionId))


func _ask_user(request: PermissionRequest, timeout_s: int) -> Dictionary:
	_log_perm("asking the user: %s" % request.title)
	model.add_permission(request)
	if timeout_s > 0:
		var tree := Engine.get_main_loop() as SceneTree
		tree.create_timer(timeout_s).timeout.connect(func() -> void:
			if request.is_pending():
				_log_perm("no answer in %d s, denied: %s" % [timeout_s, request.title])
				request.cancel()
		)
	var outcome: Dictionary = request.outcome if not request.is_pending() else await request.resolved
	if request.chosen_kind == PermissionRequest.KIND_ALLOW_ALWAYS:
		policy.grant_for_session(request.group)
	_log_perm("%s: %s" % [_outcome_label(request), request.title])
	return outcome


func _authorize_fs_write(path: String, old_text: String, new_text: String) -> bool:
	var expiry: int = _preauthorized_writes.get(path, 0)
	if expiry > Time.get_ticks_msec():
		_preauthorized_writes.erase(path)
		return true
	var counts := LineDiff.count(LineDiff.diff(old_text, new_text))
	var description := "%s · +%d −%d" % [path.trim_prefix(cwd + "/"), counts.added, counts.removed]
	return await authorize(
		PermissionPolicy.GROUP_EDIT_FILES, I18n.t("Write %s") % path.get_file(), description,
		{"path": path, "oldText": old_text, "newText": new_text}
	)


## Un permiso de edición concedido cubre la escritura por fs/* que le sigue al mismo archivo.
func _preauthorize(request: PermissionRequest, call: Variant) -> void:
	if request.group != PermissionPolicy.GROUP_EDIT_FILES:
		return
	var paths: PackedStringArray = []
	if not request.diff.is_empty():
		paths.append(str(request.diff.get("path", "")))
	if call and call.raw_input is Dictionary:
		for key: String in ["file_path", "path", "notebook_path"]:
			if call.raw_input.get(key) is String:
				paths.append(call.raw_input[key])
	if call:
		for location: Variant in call.locations:
			if location is Dictionary and location.get("path") is String:
				paths.append(location.path)
	for path: String in paths:
		if not path.is_empty():
			_preauthorized_writes[path.simplify_path()] = Time.get_ticks_msec() + PREAUTHORIZED_WRITE_MS


func _notify_denied(group: String, title: String) -> void:
	var group_label: String = PermissionPolicy.GROUP_LABELS.get(group, group)
	_log_perm("denied in %s mode (%s): %s" % [_mode_label(), group_label, title])
	var shown_group := I18n.t(group_label) if PermissionPolicy.GROUP_LABELS.has(group) else group
	model.add_notice(I18n.t("Denied in %s mode (%s): %s") % [I18n.t(_mode_label()), shown_group, title], ChatEntry.NoticeLevel.WARNING)


static func _selected_or_cancelled(option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {"outcome": {"outcome": "cancelled"}}
	return {"outcome": {"outcome": "selected", "optionId": option_id}}


static func _describe_tool_call(tool_call: Dictionary, call: Variant) -> String:
	var input: Variant = tool_call.get("rawInput", call.raw_input if call else null)
	if input is Dictionary:
		for key: String in ["command", "file_path", "path", "url", "pattern", "description"]:
			if input.get(key) is String and not str(input[key]).is_empty():
				return str(input[key])
	return str(tool_call.get("kind", call.kind if call else ""))


static func _first_diff(tool_call: Dictionary, call: Variant) -> Dictionary:
	var content: Variant = tool_call.get("content", call.content if call else [])
	if content is Array:
		for block: Variant in content:
			if block is Dictionary and block.get("type") == "diff":
				return block
	return {}


func _mode_label() -> String:
	return SessionModel.HARNESS_MODE_LABELS[model.harness_mode]


static func _outcome_label(request: PermissionRequest) -> String:
	if request.outcome.get("outcome") != "selected":
		return "cancelled"
	return "allowed" if request.was_allowed() else "denied"


func _log_perm(message: String) -> void:
	agent_log.add(AgentLog.CH_PERM, message)


func _send_line(line: String) -> bool:
	return _process != null and _process.send_line(line)


## Durante session/load el agente vuelve a mandar toda la conversación; acá se descarta, porque
## model.session_id recién se asigna con la respuesta y el dock ya la armó desde el historial.
func _on_session_update(params: Dictionary) -> void:
	if params.get("sessionId") != model.session_id or not params.get("update") is Dictionary:
		return
	if params.update.get("sessionUpdate") == "usage_update":
		quota.observe_update(params.update)
	if not model.apply_update(params.update):
		agent_log.add(AgentLog.CH_ACP, "Unknown session/update variant, ignored: %s" % str(params.update.get("sessionUpdate", "?")))
	elif history:
		history.record_update(params.update)


func _record_turn_end(stop_reason: String) -> void:
	if history:
		history.record_turn_end(stop_reason)


## Reanuda una sesión del historial: la conversación sale del archivo y session/load le devuelve
## al agente su contexto. Sin soporte de session/load el historial queda de solo lectura.
func _load_session(record: Dictionary, generation: int) -> bool:
	var session_id := str(record.get("id", ""))
	SessionHistory.replay(record, model)
	if not model.supports_load_session():
		_load_failed = true
		stop()
		model.add_notice(I18n.t("%s cannot resume sessions (it does not announce session/load): the history stays read-only. Type to start a new session.") % _profile.display_name)
		return false
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	var result := await client.request("session/load", {"sessionId": session_id, "cwd": cwd, "mcpServers": mcp_servers})
	if generation != _connect_generation:
		return false
	if not result.ok:
		_load_failed = true
		stop()
		model.add_notice(I18n.t("Could not resume the session: %s. The history stays read-only.") % result.error_message(), ChatEntry.NoticeLevel.WARNING)
		return false
	model.apply_session(session_id, result.result if result.result is Dictionary else {})
	_system_prompt_sent = true  # ya está en el contexto que el agente recuperó
	policy.clear_session()
	_preauthorized_writes.clear()
	if history:
		history.begin(session_id, _profile.id, _profile.display_name, cwd, record)
	model.set_state(SessionModel.SessionState.READY)
	model.add_notice(I18n.t("Session resumed: the agent recovered its context with session/load."))
	_sync_agent_mode()
	connected.emit()
	return true


func _on_stderr(line: String) -> void:
	agent_log.add(AgentLog.CH_PROC, line)


func _on_process_exited(code: int, process: AgentProcess) -> void:
	if process != _process:
		return
	_process = null
	process.stop()
	client.fail_all_pending("The agent exited (code %d)." % code)
	_fail(I18n.t("The agent exited unexpectedly (code %d).") % code)
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


func _fail(message: String, extra_actions: Array[Dictionary] = []) -> void:
	model.failure_message = message
	agent_log.add(AgentLog.CH_PROC, message)
	var actions := extra_actions.duplicate()
	actions.append_array(_error_actions())
	model.add_notice(message, ChatEntry.NoticeLevel.ERROR, actions)
	model.set_state(SessionModel.SessionState.FAILED)


func _error_actions() -> Array[Dictionary]:
	return [{"id": ACTION_RETRY, "label": I18n.t("Retry")}, {"id": ACTION_SHOW_LOG, "label": I18n.t("Show log")}]


func _auth_hint() -> String:
	var names: PackedStringArray = []
	for method: Variant in model.auth_methods:
		if method is Dictionary:
			names.append("%s (%s)" % [method.get("name", method.get("id", "?")), method.get("description", "")])
	return ", ".join(names)
