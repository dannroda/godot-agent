@tool
extends RefCounted
## Fuente de verdad de la sesión: entradas (con merge de chunks), tool calls por id, plan, modos,
## opciones de configuración, comandos, uso de tokens y estado. Emite señales granulares.
## No hace IO: el SessionController le aplica lo que llega por ACP.

signal state_changed(state: SessionState)
signal entry_added(entry: ChatEntry)
signal entry_updated(entry: ChatEntry)
signal entry_removed(entry: ChatEntry)
signal entries_cleared
signal tool_call_changed(call: ToolCall, group: ChatEntry)
signal plan_changed(plan: Array)
signal usage_changed(used: int, size: int)
signal agent_modes_changed(current_id: String, modes: Array)
signal config_options_changed(options: Array)
signal commands_changed(commands: Array)
signal title_changed(title: String)
signal harness_mode_changed(mode: HarnessMode)
## Remote Control de Claude Code (m7-21): link de la sesión en claude.ai, o "" si está apagado.
signal remote_control_changed(url: String)
## La cuenta del agente cambió (ver `account`).
signal account_changed
signal turn_finished(stop_reason: String)
signal permission_requested(request: PermissionRequest)
signal elicitation_requested(request: ElicitationRequest)

const ChatEntry := preload("chat_entry.gd")
const ToolCall := preload("tool_call.gd")
const PermissionRequest := preload("permission_request.gd")
const ElicitationRequest := preload("elicitation_request.gd")
const I18n := preload("../core/i18n.gd")

enum SessionState {
	DISCONNECTED,  ## sin proceso
	STARTING,  ## proceso lanzado, initialize / session/new en curso
	READY,  ## sesión abierta, esperando un prompt
	PROMPTING,  ## turno en curso
	CANCELLING,  ## session/cancel enviado, esperando el stopReason
	FAILED,  ## el agente no arrancó o se cayó
}

## Modos del harness (spec §7). Viven del lado del cliente.
## AUTO va al final para no cambiar los valores de los demás (D57); en la UI se muestra después de BUILD.
enum HarnessMode { ASK, REVIEW, BUILD, ONESHOT, AUTO }

const HARNESS_MODE_LABELS: Dictionary = {
	HarnessMode.ASK: "Ask",  # i18n
	HarnessMode.REVIEW: "Review",  # i18n
	HarnessMode.BUILD: "Build",  # i18n
	HarnessMode.AUTO: "Auto",  # i18n
	HarnessMode.ONESHOT: "One-shot",  # i18n
}

var state: SessionState = SessionState.DISCONNECTED
var session_id: String = ""
var title: String = ""
var harness_mode: HarnessMode = HarnessMode.BUILD
var remote_control_url: String = ""
var agent_info: Dictionary = {}
## Con qué cuenta está logueado el agente (Claude Code): `{email, org, plan, method}`, o {} si no se
## sabe. Es del proceso, no de la conversación: reset() no la borra.
var account: Dictionary = {}
var agent_capabilities: Dictionary = {}
var auth_methods: Array = []
var current_agent_mode: String = ""
var agent_modes: Array = []
var config_options: Array = []
var commands: Array = []
var plan: Array = []
var usage_used: int = 0
var usage_size: int = 0
var last_stop_reason: String = ""
## Mensaje del último error de conexión (estado FAILED).
var failure_message: String = ""
## true mientras se vuelve a armar una conversación del historial: las señales no son eventos nuevos
## (nada de sincronizar archivos, checkpoints ni playtests).
var replaying: bool = false

var pending_permissions: Array[PermissionRequest] = []
var pending_elicitations: Array[ElicitationRequest] = []

var _entries: Array[ChatEntry] = []
var _tool_calls: Dictionary = {}  # toolCallId -> ToolCall
## Tool calls que son la pregunta de una tarjeta de elicitation (AskUserQuestion): no van en el
## grupo de herramientas, la tarjeta ya los muestra (m12-40).
var _question_calls: Dictionary = {}  # toolCallId -> true
var _group_of_call: Dictionary = {}  # toolCallId -> ChatEntry (TOOL_GROUP)
## Subagentes nativos de ACP (m7-43): sesión del hijo -> {state, title, description, launch}, con
## `launch` el tool call de Agent/Task que lo lanzó (lo dice el session_message de su prompt).
var _subagent_sessions: Dictionary = {}
## Salida de cada terminal ACP (m11-15): terminalId -> {output: String, exit_code: Variant}.
var _terminal_outputs: Dictionary = {}
var _plan_entry: ChatEntry
var _next_entry_id: int = 1


func entries() -> Array[ChatEntry]:
	return _entries


func tool_call(id: String) -> ToolCall:
	return _tool_calls.get(id)


## El tool call godot.* más reciente con ese nombre y esos argumentos que todavía no tiene paso de
## undo asociado (para unir la acción del server MCP con el tool call que ve el agente).
func find_godot_tool_call(tool_name: String, args: Dictionary) -> ToolCall:
	var found: ToolCall = null
	for id: String in _tool_calls:
		var call: ToolCall = _tool_calls[id]
		if call.godot_tool_name() == tool_name and call.undo_info.is_empty() and call.godot_arguments() is Dictionary and call.godot_arguments() == args:
			found = call
	return found


## Avisa a la UI que cambió algo local de un tool call (p. ej. su paso de undo).
func touch_tool_call(call: ToolCall) -> void:
	_emit_tool_call_changed(call)


func is_busy() -> bool:
	return state in [SessionState.PROMPTING, SessionState.CANCELLING]


func set_state(value: SessionState) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)


func set_remote_control(url: String) -> void:
	if url == remote_control_url:
		return
	remote_control_url = url
	remote_control_changed.emit(url)


func set_account(value: Dictionary) -> void:
	if value != account:
		account = value
		account_changed.emit()


## true si el agente publica el comando `/remote-control` (claude-agent-acp con un SDK que lo soporta).
func supports_remote_control() -> bool:
	return commands.any(func(command: Variant) -> bool: return command is Dictionary and command.get("name") == "remote-control")


func set_harness_mode(value: HarnessMode) -> void:
	if harness_mode == value:
		return
	harness_mode = value
	harness_mode_changed.emit(value)


## Limpia la conversación (nueva sesión). Conserva el modo del harness.
func reset() -> void:
	session_id = ""
	title = ""
	plan = []
	commands = []
	usage_used = 0
	usage_size = 0
	last_stop_reason = ""
	_entries.clear()
	_tool_calls.clear()
	_question_calls.clear()
	_group_of_call.clear()
	_subagent_sessions.clear()
	_terminal_outputs.clear()
	_plan_entry = null
	cancel_pending_permissions()
	set_remote_control("")
	entries_cleared.emit()
	title_changed.emit(title)
	plan_changed.emit(plan)
	commands_changed.emit(commands)
	usage_changed.emit(usage_used, usage_size)


## Resultado de `initialize`.
func apply_initialize(result: Dictionary) -> void:
	agent_info = result.get("agentInfo", {}) if result.get("agentInfo") is Dictionary else {}
	agent_capabilities = result.get("agentCapabilities", {}) if result.get("agentCapabilities") is Dictionary else {}
	auth_methods = result.get("authMethods", []) if result.get("authMethods") is Array else []


## Resultado de `session/new` (o `session/load`).
func apply_session(new_session_id: String, result: Dictionary) -> void:
	session_id = new_session_id
	if result.get("modes") is Dictionary:
		_apply_modes(result.modes.get("currentModeId", ""), result.modes.get("availableModes", []))
	if result.get("configOptions") is Array:
		config_options = result.configOptions
		config_options_changed.emit(config_options)


func supports_image() -> bool:
	var prompt_caps: Variant = agent_capabilities.get("promptCapabilities")
	return prompt_caps is Dictionary and bool(prompt_caps.get("image", false))


func supports_embedded_context() -> bool:
	var prompt_caps: Variant = agent_capabilities.get("promptCapabilities")
	return prompt_caps is Dictionary and bool(prompt_caps.get("embeddedContext", false))


func supports_http_mcp() -> bool:
	var mcp_caps: Variant = agent_capabilities.get("mcpCapabilities")
	return mcp_caps is Dictionary and bool(mcp_caps.get("http", false))


## ACP `logout` (agentCapabilities.auth.logout): Claude Code y Antigravity lo anuncian.
func supports_logout() -> bool:
	var auth: Variant = agent_capabilities.get("auth")
	return auth is Dictionary and auth.get("logout") is Dictionary


func supports_load_session() -> bool:
	return bool(agent_capabilities.get("loadSession", false))


func supports_list_sessions() -> bool:
	var caps: Variant = agent_capabilities.get("sessionCapabilities")
	return caps is Dictionary and caps.get("list") is Dictionary


func supports_resume_session() -> bool:
	var caps: Variant = agent_capabilities.get("sessionCapabilities")
	return caps is Dictionary and caps.get("resume") is Dictionary


func supports_close_session() -> bool:
	var caps: Variant = agent_capabilities.get("sessionCapabilities")
	return caps is Dictionary and caps.get("close") is Dictionary


func supports_delete_session() -> bool:
	var caps: Variant = agent_capabilities.get("sessionCapabilities")
	return caps is Dictionary and caps.get("delete") is Dictionary


func can_resume_sessions() -> bool:
	return supports_load_session() or supports_resume_session()


## Opción de configuración por id (`model`, `mode`…) o {}.
func config_option(id: String) -> Dictionary:
	for option: Variant in config_options:
		if option is Dictionary and option.get("id") == id:
			return option
	return {}


func set_config_value(id: String, value: String) -> void:
	for option: Variant in config_options:
		if option is Dictionary and option.get("id") == id:
			option["currentValue"] = value
	config_options_changed.emit(config_options)


# --- entradas ------------------------------------------------------------------------------------

func add_user_message(text: String, attachments: Array[Dictionary] = []) -> ChatEntry:
	var entry := _new_entry(ChatEntry.EntryKind.USER)
	entry.text = text
	entry.attachments = attachments
	return _push(entry)


func add_notice(text: String, level: ChatEntry.NoticeLevel = ChatEntry.NoticeLevel.INFO, actions: Array[Dictionary] = []) -> ChatEntry:
	var entry := _new_entry(ChatEntry.EntryKind.NOTICE)
	entry.text = text
	entry.level = level
	entry.actions = actions
	return _push(entry)


## Agrega una entrada ya armada (p. ej. una tarjeta de permiso, M2).
func add_entry(entry: ChatEntry) -> ChatEntry:
	entry.id = _next_entry_id
	_next_entry_id += 1
	if entry.created_unix == 0.0:
		entry.created_unix = Time.get_unix_time_from_system()
	return _push(entry)


## Agrega una tarjeta de permiso. Se actualiza sola cuando el pedido se resuelve.
func add_permission(request: PermissionRequest) -> ChatEntry:
	var entry := _new_entry(ChatEntry.EntryKind.PERMISSION)
	entry.permission = request
	entry.text = request.title
	pending_permissions.append(request)
	request.resolved.connect(func(_outcome: Dictionary) -> void:
		pending_permissions.erase(request)
		entry_updated.emit(entry)
	, CONNECT_ONE_SHOT)
	_push(entry)
	permission_requested.emit(request)
	return entry


## Agrega una tarjeta de formulario o enlace del agente (`elicitation/create`, m11-17).
func add_elicitation(request: ElicitationRequest) -> ChatEntry:
	var entry := _new_entry(ChatEntry.EntryKind.ELICITATION)
	entry.elicitation = request
	entry.text = request.message
	pending_elicitations.append(request)
	_hide_question_call(request)
	request.resolved.connect(func(_response: Dictionary) -> void:
		pending_elicitations.erase(request)
		entry_updated.emit(entry)
	, CONNECT_ONE_SHOT)
	_push(entry)
	elicitation_requested.emit(request)
	return entry


## El tool call que originó la pregunta (mismo toolCallId o, si el agente no lo manda, uno sin
## terminar del último grupo con el mismo título) sale del grupo de herramientas.
func _hide_question_call(request: ElicitationRequest) -> void:
	var id := request.tool_call_id
	if id.is_empty():
		var group: ChatEntry = _entries.back() if not _entries.is_empty() else null
		if group == null or group.kind != ChatEntry.EntryKind.TOOL_GROUP:
			for i in range(_entries.size() - 1, -1, -1):
				if _entries[i].kind == ChatEntry.EntryKind.TOOL_GROUP:
					group = _entries[i]
					break
		if group == null or group.kind != ChatEntry.EntryKind.TOOL_GROUP:
			return
		for candidate_id: String in group.tool_call_ids:
			var candidate: ToolCall = _tool_calls.get(candidate_id)
			if candidate and not candidate.is_finished() and candidate.title.strip_edges() == request.message.strip_edges():
				id = candidate_id
		if id.is_empty():
			return
	_question_calls[id] = true
	var call: ToolCall = _tool_calls.get(id)
	if call and call.parent_id.is_empty():
		_detach(call)


## Notificación `elicitation/complete` (m11-17): el flujo por URL con ese `elicitation_id` terminó.
func complete_elicitation(elicitation_id: String) -> void:
	if elicitation_id.is_empty():
		return
	for entry: ChatEntry in _entries:
		if entry.kind == ChatEntry.EntryKind.ELICITATION and entry.elicitation != null:
			var req: ElicitationRequest = entry.elicitation
			if req.elicitation_id == elicitation_id and req.mode == ElicitationRequest.MODE_URL:
				req.completed_by_agent = true
				# El usuario no abrió el enlace desde acá: se cierra sin decir que aceptó.
				if req.is_pending():
					req.cancel()
				else:
					entry_updated.emit(entry)


## Al cancelar el turno, los permisos y formularios pendientes se responden como cancelados (spec §4.1).
func cancel_pending_permissions() -> void:
	for request: PermissionRequest in pending_permissions.duplicate():
		request.cancel()
	for elicitation: ElicitationRequest in pending_elicitations.duplicate():
		elicitation.cancel()


func notify_entry_changed(entry: ChatEntry) -> void:
	entry_updated.emit(entry)


# --- session/update ------------------------------------------------------------------------------

## Aplica un `update` de session/update. Devuelve false si la variante es desconocida.
## Lo que hace un subagente (Claude Code lo marca con `_meta.claudeCode.parentToolUseId`) no va a la
## conversación principal: sus tool calls y su texto quedan en el tool call que lo lanzó.
func apply_update(update: Dictionary) -> bool:
	var kind := str(update.get("sessionUpdate", ""))
	var parent := parent_tool_call_id(update)
	if not parent.is_empty():
		match kind:
			"agent_message_chunk":
				_append_subagent_text(parent, update)
				return true
			"agent_thought_chunk", "user_message_chunk", "plan":
				return true
			"tool_call":
				_apply_tool_call(update, true, parent)
				return true
			"tool_call_update":
				_apply_tool_call(update, false, parent)
				return true
	match kind:
		"agent_message_chunk":
			_append_chunk(ChatEntry.EntryKind.AGENT, update)
		"agent_thought_chunk":
			_append_chunk(ChatEntry.EntryKind.THOUGHT, update)
		"user_message_chunk":
			_append_chunk(ChatEntry.EntryKind.USER, update)
		"tool_call":
			_apply_tool_call(update, true)
		"tool_call_update":
			_apply_tool_call(update, false)
		"plan":
			_apply_plan(update.get("entries", []) if update.get("entries") is Array else [])
		"available_commands_update":
			commands = update.get("availableCommands", []) if update.get("availableCommands") is Array else []
			commands_changed.emit(commands)
		"current_mode_update":
			_apply_modes(str(update.get("currentModeId", "")), agent_modes)
		"config_option_update", "config_options_update":
			if update.get("configOptions") is Array:
				config_options = update.configOptions
				config_options_changed.emit(config_options)
		"session_info_update":
			if update.get("title") is String:
				title = update.title
				title_changed.emit(title)
		"usage_update":
			usage_used = int(update.get("used", usage_used))
			usage_size = int(update.get("size", usage_size))
			usage_changed.emit(usage_used, usage_size)
		"subagent_update":
			_apply_subagent_update(update)
		"session_message":
			_link_subagent(update)
		_:
			return false
	return true


## true si `session_id` es la sesión de un subagente que anunció el agente.
func is_subagent_session(session_id: String) -> bool:
	return _subagent_sessions.has(session_id)


## Aplica un update de la sesión de un subagente: va al tool call que lo lanzó, como los que marca
## `parentToolUseId`. false si la sesión no es de un subagente conocido.
func apply_child_update(session_id: String, update: Dictionary) -> bool:
	var info: Dictionary = _subagent_sessions.get(session_id, {})
	if info.is_empty():
		return false
	var kind := str(update.get("sessionUpdate", ""))
	if kind in ["subagent_update", "session_message"]:
		return apply_update(update)
	if not kind in ["agent_message_chunk", "agent_thought_chunk", "user_message_chunk", "plan", "tool_call", "tool_call_update"]:
		return true
	if parent_tool_call_id(update).is_empty():
		if str(info.launch).is_empty():
			return true
		update = update.duplicate()
		var meta: Dictionary = (update.get("_meta") as Dictionary).duplicate(true) if update.get("_meta") is Dictionary else {}
		var claude: Dictionary = meta.get("claudeCode") if meta.get("claudeCode") is Dictionary else {}
		claude["parentToolUseId"] = info.launch
		meta["claudeCode"] = claude
		update["_meta"] = meta
	return apply_update(update)


## Anuncio o cambio de estado de un subagente (`subagent_update`, sessionId = el del hijo).
func _apply_subagent_update(update: Dictionary) -> void:
	var child := str(update.get("sessionId", ""))
	if child.is_empty():
		return
	if not _subagent_sessions.has(child):
		_subagent_sessions[child] = {"state": "", "title": "", "description": "", "launch": ""}
	var info: Dictionary = _subagent_sessions[child]
	if update.get("state") is Dictionary:
		info.state = str((update.state as Dictionary).get("state", ""))
	for key: String in ["title", "description"]:
		if update.get(key) is String:
			info[key] = update[key]
	_sync_subagent(child)


## El prompt de un lanzamiento llega como session_message con el id del tool call de Agent/Task.
func _link_subagent(update: Dictionary) -> void:
	var child := str(update.get("recipientSessionId", ""))
	var launch := str(update.get("messageId", ""))
	if not _subagent_sessions.has(child) or not _tool_calls.has(launch):
		return
	_subagent_sessions[child].launch = launch
	_sync_subagent(child)


func _sync_subagent(child: String) -> void:
	var info: Dictionary = _subagent_sessions[child]
	var call: ToolCall = _tool_calls.get(str(info.launch))
	if call == null:
		return
	call.subagent_session_id = child
	call.subagent_state = info.state
	_emit_tool_call_changed(call)


## Fin del turno (resultado de session/prompt).
func finish_turn(stop_reason: String) -> void:
	last_stop_reason = stop_reason
	if stop_reason == "cancelled":
		cancel_unfinished_tool_calls()
	match stop_reason:
		"max_tokens":
			add_notice(I18n.t("The agent cut the response short: it hit the token limit."), ChatEntry.NoticeLevel.WARNING)
		"max_turn_requests":
			add_notice(I18n.t("The agent hit the maximum number of requests per turn."), ChatEntry.NoticeLevel.WARNING)
		"refusal":
			add_notice(I18n.t("The agent refused to continue with this request."), ChatEntry.NoticeLevel.WARNING)
		"cancelled":
			add_notice(I18n.t("Turn cancelled."))
	if state in [SessionState.PROMPTING, SessionState.CANCELLING]:
		set_state(SessionState.READY)
	turn_finished.emit(stop_reason)


## Al cancelar: los tool calls sin terminar quedan `cancelled` (spec §4.1).
func cancel_unfinished_tool_calls() -> void:
	for id: String in _tool_calls:
		var call: ToolCall = _tool_calls[id]
		if not call.is_finished():
			call.set_status(ToolCall.STATUS_CANCELLED)
			_emit_tool_call_changed(call)


func _append_chunk(kind: ChatEntry.EntryKind, update: Dictionary) -> void:
	var text := content_to_text(update.get("content"))
	if text.is_empty():
		return
	var message_id := str(update.get("messageId", "")) if update.get("messageId") != null else ""
	var last: ChatEntry = _entries.back() if not _entries.is_empty() else null
	if last and last.kind == kind and (message_id.is_empty() or last.message_id.is_empty() or last.message_id == message_id):
		last.text += text
		if last.message_id.is_empty():
			last.message_id = message_id
		entry_updated.emit(last)
		return
	var entry := _new_entry(kind)
	entry.text = text
	entry.message_id = message_id
	_push(entry)


func _apply_tool_call(data: Dictionary, is_new: bool, parent: String = "") -> void:
	var id := str(data.get("toolCallId", ""))
	if id.is_empty():
		return
	var call: ToolCall = _tool_calls.get(id)
	if call == null:
		# Un update de un id desconocido también crea el tool call (ACP lo permite).
		call = _new_tool_call(id, parent)
	else:
		if is_new:
			call.content = []
		if not parent.is_empty() and call.parent_id.is_empty():
			# Un pedido de permiso puede llegar antes que el update que dice de qué subagente es.
			_reparent(call, parent)
	call.apply(data)
	_apply_terminal_meta(data)
	_sync_terminal_blocks(call)
	_emit_tool_call_changed(call)


## Actualiza la salida de un terminal ACP (m11-15) y refresca los tool calls que lo muestran.
func set_terminal_output(terminal_id: String, output: String, exit_code: Variant = null) -> void:
	if terminal_id.is_empty():
		return
	var current: Dictionary = _terminal_outputs.get(terminal_id, {})
	var resolved_exit: Variant = exit_code if exit_code != null else current.get("exit_code")
	_terminal_outputs[terminal_id] = {"output": output, "exit_code": resolved_exit}
	for call_id: String in _tool_calls:
		var call: ToolCall = _tool_calls[call_id]
		if _sync_terminal_blocks(call):
			_emit_tool_call_changed(call)


func _apply_terminal_meta(data: Dictionary) -> void:
	var meta: Variant = data.get("_meta")
	if not meta is Dictionary:
		return
	var exit_code: Variant = null
	if meta.get("terminal_exit") is Dictionary:
		exit_code = (meta.terminal_exit as Dictionary).get("exit_code")
	if meta.get("terminal_output") is Dictionary:
		var out: Dictionary = meta.terminal_output
		set_terminal_output(str(out.get("terminal_id", "")), str(out.get("data", "")), exit_code)
	elif meta.get("terminal_output_delta") is Dictionary:
		var delta: Dictionary = meta.terminal_output_delta
		var tid := str(delta.get("terminal_id", ""))
		var prev := str((_terminal_outputs.get(tid, {}) as Dictionary).get("output", ""))
		set_terminal_output(tid, prev + str(delta.get("data", "")), exit_code)


func _sync_terminal_blocks(call: ToolCall) -> bool:
	var changed := false
	for i in call.content.size():
		var block: Variant = call.content[i]
		if not block is Dictionary or block.get("type") != "terminal":
			continue
		var tid := str(block.get("terminalId", ""))
		if tid.is_empty() or not _terminal_outputs.has(tid):
			continue
		var info: Dictionary = _terminal_outputs[tid]
		var out := str(info.get("output", ""))
		var code: Variant = info.get("exit_code")
		if block.get("output") != out or block.get("exitCode") != code:
			var updated: Dictionary = (block as Dictionary).duplicate()
			updated["output"] = out
			if code != null:
				updated["exitCode"] = code
			call.content[i] = updated
			changed = true
	return changed


## Un tool call nuevo: dentro del subagente `parent` o, sin padre, en el grupo del final de la
## conversación (o en uno nuevo).
func _new_tool_call(id: String, parent: String) -> ToolCall:
	var call := ToolCall.new()
	call.id = id
	call.started_msec = Time.get_ticks_msec()
	_tool_calls[id] = call
	_attach(call, parent)
	return call


func _attach(call: ToolCall, parent: String) -> void:
	if not parent.is_empty() and parent != call.id and not _is_descendant(parent, call.id):
		var owner: ToolCall = _tool_calls.get(parent)
		if owner == null:
			owner = _new_tool_call(parent, "")
		call.parent_id = parent
		owner.child_ids.append(call.id)
		_set_group(call, _group_of_call.get(parent))
		return
	if _question_calls.has(call.id):
		return
	var group: ChatEntry = _entries.back() if not _entries.is_empty() else null
	if group == null or group.kind != ChatEntry.EntryKind.TOOL_GROUP:
		group = _push(_new_entry(ChatEntry.EntryKind.TOOL_GROUP))
	group.tool_call_ids.append(call.id)
	_set_group(call, group)


## Pasa un tool call de la conversación principal al subagente `parent`.
func _reparent(call: ToolCall, parent: String) -> void:
	if parent == call.id or _is_descendant(parent, call.id):
		return
	_detach(call)
	_attach(call, parent)


## Saca un tool call de su grupo (y el grupo, si queda vacío).
func _detach(call: ToolCall) -> void:
	var group: ChatEntry = _group_of_call.get(call.id)
	_group_of_call.erase(call.id)
	if group and group.tool_call_ids.has(call.id):
		group.tool_call_ids.remove_at(group.tool_call_ids.find(call.id))
		if group.tool_call_ids.is_empty():
			_entries.erase(group)
			entry_removed.emit(group)
		else:
			entry_updated.emit(group)


## true si `id` es `ancestor` o está dentro de sus subagentes.
func _is_descendant(id: String, ancestor: String) -> bool:
	var current: ToolCall = _tool_calls.get(id)
	var steps := 0
	while current and steps < 64:
		if current.id == ancestor:
			return true
		current = _tool_calls.get(current.parent_id)
		steps += 1
	return false


## La vista de un subagente vive en el grupo de su tool call: sus hijos avisan a ese grupo.
func _set_group(call: ToolCall, group: ChatEntry) -> void:
	if group:
		_group_of_call[call.id] = group
	else:
		_group_of_call.erase(call.id)
	for child_id: String in call.child_ids:
		var child: ToolCall = _tool_calls.get(child_id)
		if child:
			_set_group(child, group)


func _append_subagent_text(parent: String, update: Dictionary) -> void:
	var text := content_to_text(update.get("content"))
	if text.is_empty():
		return
	var call: ToolCall = _tool_calls.get(parent)
	if call == null:
		call = _new_tool_call(parent, "")
	call.append_subagent_text(text)
	_emit_tool_call_changed(call)


func _emit_tool_call_changed(call: ToolCall) -> void:
	var owner_group: ChatEntry = _group_of_call.get(call.id)
	tool_call_changed.emit(call, owner_group)
	if owner_group:
		entry_updated.emit(owner_group)


func _apply_plan(entries_data: Array) -> void:
	plan = entries_data
	if _plan_entry == null or _entries.is_empty() or _entries.back() != _plan_entry:
		# El plan se muestra donde aparece por última vez en la conversación.
		if _plan_entry:
			_entries.erase(_plan_entry)
			entry_removed.emit(_plan_entry)
		_plan_entry = _new_entry(ChatEntry.EntryKind.PLAN)
		_plan_entry.plan = plan
		_push(_plan_entry)
	else:
		_plan_entry.plan = plan
		entry_updated.emit(_plan_entry)
	plan_changed.emit(plan)


func _apply_modes(current_id: String, modes: Variant) -> void:
	current_agent_mode = current_id
	agent_modes = modes if modes is Array else []
	agent_modes_changed.emit(current_agent_mode, agent_modes)


func _new_entry(kind: ChatEntry.EntryKind) -> ChatEntry:
	var entry := ChatEntry.new()
	entry.id = _next_entry_id
	_next_entry_id += 1
	entry.kind = kind
	entry.created_unix = Time.get_unix_time_from_system()
	return entry


func _push(entry: ChatEntry) -> ChatEntry:
	_entries.append(entry)
	entry_added.emit(entry)
	return entry


## Subagentes (Agent/Task) que siguen trabajando, en el orden en que arrancaron.
func running_subagents() -> Array[ToolCall]:
	var running: Array[ToolCall] = []
	for id: String in _tool_calls:
		var call: ToolCall = _tool_calls[id]
		if call.is_subagent() and call.is_working():
			running.append(call)
	running.sort_custom(func(a: ToolCall, b: ToolCall) -> bool: return a.started_msec < b.started_msec)
	return running


## Id del tool call de Agent/Task cuyo subagente mandó este update (`_meta.claudeCode.parentToolUseId`
## del adaptador de Claude Code), o "".
static func parent_tool_call_id(update: Dictionary) -> String:
	var meta: Variant = update.get("_meta")
	if not meta is Dictionary or not meta.get("claudeCode") is Dictionary:
		return ""
	var parent: Variant = meta.claudeCode.get("parentToolUseId")
	return parent if parent is String else ""


## Texto de un ContentBlock de ACP. Los bloques no textuales se resumen.
static func content_to_text(block: Variant) -> String:
	if not block is Dictionary:
		return ""
	match str(block.get("type", "")):
		"text":
			return str(block.get("text", ""))
		"image":
			return I18n.t("[image]")
		"audio":
			return "[audio]"
		"resource_link":
			return "[%s](%s)" % [block.get("name", block.get("uri", "")), block.get("uri", "")]
		"resource":
			var resource: Variant = block.get("resource")
			if resource is Dictionary and resource.get("text") is String:
				return str(resource.text)
			return I18n.t("[resource]")
	return ""
