@tool
extends RefCounted
## Los permisos de una sesión (m13-05, A2): decide con la política del modo, las reglas de shell del
## modo Auto y las guardas del proyecto; lo que hay que preguntar va como tarjeta al SessionModel y
## espera la respuesta. Atiende `session/request_permission` y los autorizadores de fs/* y terminal/*.
## Lo arma el SessionController, que sigue exponiendo `policy`, `shell_rules` y `authorize`.

## El usuario agregó una regla del modo Auto desde una tarjeta: hay que guardar la config.
signal shell_rules_changed
## El usuario permitió un MCP server de terceros desde una tarjeta, para el modo y el proyecto.
signal permissions_changed
## Un rechazo con algo para decirle al agente (m11-22): un motivo o el plan editado. `text` sale como
## prompt del harness con la etiqueta `label` apenas termine el turno, aunque termine cancelled.
signal reject_feedback(text: String, label: String)

const AcpClient := preload("../acp/acp_client.gd")
const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const ToolCall := preload("tool_call.gd")
const AgentLog := preload("../core/agent_log.gd")
const PermissionPolicy := preload("permission_policy.gd")
const PermissionRequest := preload("permission_request.gd")
const Preauthorizations := preload("preauthorizations.gd")
const ShellRules := preload("shell_rules.gd")
const ShellCommand := preload("shell_command.gd")
## Opción «siempre en esta sesión» que agrega el harness cuando el agente no la ofrece.
const HARNESS_ALLOW_ALWAYS := "godot_agent_allow_always"
const ProjectWriteGuard := preload("project_write_guard.gd")
const GodotWindowGuard := preload("godot_window_guard.gd")
const TerminalHandler := preload("../acp/terminal_handler.gd")
const LineDiff := preload("../core/line_diff.gd")
const EditorBinary := preload("../transport/editor_binary.gd")
const I18n := preload("../core/i18n.gd")
const PlanApproval := preload("plan_approval.gd")
const HarnessPrompts := preload("harness_prompts.gd")
const ProjectModes := preload("../core/project_modes.gd")

var policy: PermissionPolicy = PermissionPolicy.new()
## Reglas de shell del modo Auto (D57): el array de project_config, que se modifica en el lugar.
var shell_rules: Array = ShellRules.default_rules()
## Servers de terceros cuyas tools pidieron permiso (también los que el agente carga de su propia
## configuración): server -> true. Settings los muestra en la matriz.
var seen_mcp_servers: Dictionary = {}
## Con varias sesiones abiertas (m7-44): ver SessionController.file_guard.
var file_guard: Callable
var model: SessionModel
var client: AcpClient
var agent_log: AgentLog
var cwd: String = ""
## Pedidos de permiso del agente que esperan respuesta: id del request ACP -> PermissionRequest.
var _permissions_by_acp_id: Dictionary = {}
var _preauth := Preauthorizations.new()
## Subagentes que el harness dejó arrancar (toolCallId -> true): cuentan para el límite aunque el
## agente todavía no los haya pasado a in_progress.
var _approved_subagents: Dictionary = {}


func setup(session_model: SessionModel, acp_client: AcpClient, log_sink: AgentLog, working_dir: String) -> void:
	model = session_model
	client = acp_client
	agent_log = log_sink
	cwd = working_dir


## Sesión nueva: se olvidan las preautorizaciones y los subagentes permitidos.
func reset() -> void:
	_preauth.clear()
	_approved_subagents.clear()


## El agente retiró un pedido (`$/cancel_request`): lo contestaron desde Remote Control o ya no hace falta.
func withdraw(acp_id: Variant) -> void:
	var request: PermissionRequest = _permissions_by_acp_id.get(acp_id)
	if request and request.is_pending():
		request.withdrawn = true
		_log_perm("withdrawn by the agent (answered from Remote Control or no longer needed): %s" % request.title)
		request.cancel()


## Pide permiso según la política del modo actual. `ask` muestra una tarjeta y espera.
## Devuelve true si se permitió. `timeout_s` > 0 deniega si nadie responde a tiempo.
func authorize(group: String, title: String, description: String, diff: Dictionary = {}, timeout_s: int = 0) -> bool:
	var decision := decide(group)
	if decision == PermissionPolicy.ALLOW:
		_log_perm("allowed by %s mode: %s" % [_mode_label(), title])
		return true
	if decision == PermissionPolicy.DENY:
		_notify_denied(group, title)
		return false
	var request := PermissionRequest.new()
	# La tarjeta es solo para mirar (la respuesta es sí o no): sin los secretos del harness (m13-25).
	# Lo que se autoriza (el archivo, el comando) sigue siendo el original de quien llamó.
	request.title = agent_log.redact(title) if agent_log else title
	request.description = agent_log.redact(description) if agent_log else description
	request.group = group
	request.diff = agent_log.redact_data(diff) if agent_log else diff
	request.options = PermissionRequest.default_options()
	if mode_forces_ask(group):
		request.options = without_always(request.options)
	var outcome := await _ask_user(request, timeout_s)
	_emit_feedback(request)
	return outcome.get("outcome") == "selected" and request.was_allowed()


## La decisión de la política para `group` en el modo actual, con la capa del modo del proyecto
## (m11-39) encima: nunca da más permisos que el base. Con archivos limitados, lo que corre código que
## puede escribir cualquier cosa (la shell, las tools del proyecto, los MCP servers de terceros)
## pregunta siempre, también con base Auto; `shell: "deny"` niega la shell.
func decide(group: String) -> String:
	var decision := policy.decide(group, model.harness_mode)
	if decision == PermissionPolicy.DENY or model.project_mode.is_empty():
		return decision
	if group == PermissionPolicy.GROUP_SHELL and ProjectModes.shell_denied(model.project_mode):
		return PermissionPolicy.DENY
	if mode_forces_ask(group):
		return PermissionPolicy.ASK
	return decision


## true si el modo del proyecto obliga a preguntar en `group` (ver decide): sin «siempre» ni reglas de Auto.
func mode_forces_ask(group: String) -> bool:
	return runs_unchecked_code(group) and ProjectModes.shell_always_asks(model.project_mode) \
		and policy.decide(group, model.harness_mode) != PermissionPolicy.DENY


## Grupos que corren código cuyas escrituras el harness no ve.
static func runs_unchecked_code(group: String) -> bool:
	return group in [PermissionPolicy.GROUP_SHELL, PermissionPolicy.GROUP_PROJECT_TOOLS] or PermissionPolicy.is_mcp_group(group)


## La ruta de `paths` que el modo del proyecto no deja escribir, o "" si pasan todas (o el modo no
## limita archivos). Sin rutas, con límite, la escritura no se puede revisar: se rechaza (falla cerrada).
func mode_refused_write(paths: PackedStringArray) -> String:
	if not ProjectModes.limits_files(model.project_mode):
		return ""
	if paths.is_empty():
		return "?"
	return ProjectModes.first_refused(model.project_mode, paths, cwd)


## Avisa en el chat que el modo del proyecto rechazó una escritura y devuelve el motivo para el agente.
func notify_mode_refusal(title: String, path: String) -> String:
	var mode := model.project_mode
	var shown := ProjectSettings.localize_path(path) if path != "?" else I18n.t("a file the harness can't see")
	_log_perm("rejected by project mode %s, writes %s: %s" % [mode.get("name", ""), shown, title])
	model.add_notice(I18n.t("Rejected: mode «%s» only edits %s, and «%s» writes %s. Switch to another mode in the composer to edit it.") % [
		mode.get("name", ""), ", ".join(mode.get("editable", PackedStringArray())), title.left(80), shown], ChatEntry.NoticeLevel.WARNING)
	return mode_refusal_text(model.project_mode, shown)


## El motivo para el agente, en inglés, como los demás resultados de tools.
static func mode_refusal_text(mode: Dictionary, shown: String) -> String:
	return "Rejected by the project mode «%s»: it only lets you write %s, and this writes %s. Do not retry or work around it (no shell, no other tool): work inside those files, or tell the user what you need and ask them to switch mode." % [
		mode.get("name", ""), ", ".join(mode.get("editable", PackedStringArray())), shown]


func on_request_permission(params: Dictionary) -> Variant:
	var acp_id: Variant = client.handling_id
	var tool_call: Dictionary = params.get("toolCall", {}) if params.get("toolCall") is Dictionary else {}
	var options: Array = params.get("options", []) if params.get("options") is Array else []
	# Lo que se muestra (el tool call del modelo, el título, la descripción, el diff) sin los secretos
	# del harness (m13-25); los chequeos de abajo y la respuesta al agente usan el original.
	var shown: Dictionary = agent_log.redact_data(tool_call) if agent_log else tool_call
	if tool_call.get("toolCallId") is String:
		var update: Dictionary = shown.duplicate()
		update["sessionUpdate"] = "tool_call_update"
		var session_id := str(params.get("sessionId", ""))
		if session_id == model.session_id or not model.apply_child_update(session_id, update):
			model.apply_update(update)
	var request := PermissionRequest.new()
	request.tool_call_id = str(tool_call.get("toolCallId", ""))
	request.options = options
	request.group = PermissionPolicy.group_for_tool_call(tool_call)
	var call := model.tool_call(request.tool_call_id)
	if call and call.tool_name in ToolCall.SUBAGENT_TOOLS:
		request.group = PermissionPolicy.GROUP_SUBAGENTS
	request.title = call.display_name() if call else str(shown.get("title", I18n.t("Agent tool")))
	var subagent: ToolCall = model.tool_call(call.parent_id) if call and not call.parent_id.is_empty() else null
	if subagent:
		request.title = I18n.t("%s · subagent «%s»") % [request.title, subagent.display_name()]
	request.description = _describe_tool_call(shown, call)
	request.diff = _first_diff(shown, call)
	if PlanApproval.is_plan_request(shown, call.tool_name if call else ""):
		return await _ask_plan(request, shown, options)

	# Escribir el proyecto por fuera del editor (shell, escenas a mano) se rechaza en todo modo (D48).
	var checked := tool_call.duplicate()
	if not checked.get("rawInput") is Dictionary and call and call.raw_input is Dictionary:
		checked["rawInput"] = call.raw_input
	var blocked := ProjectWriteGuard.blocked_target(checked, request.group, cwd)
	if not blocked.is_empty() and not PermissionPolicy.is_godot_mcp_tool(tool_call):
		_notify_blocked_write(request.title, blocked)
		return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
	# Godot con ventana desde la shell: abre el juego aparte en vez de correrlo en el editor (m7-30).
	if request.group == PermissionPolicy.GROUP_SHELL and checked.get("rawInput") is Dictionary:
		var launch := GodotWindowGuard.windowed_launch(ShellCommand.of(checked.rawInput), EditorBinary.path())
		if not launch.is_empty():
			_log_perm("rejected, opens Godot in its own window: %s" % launch)
			model.add_notice(I18n.t("Rejected: «%s» opens Godot in its own window. Command-line Godot only runs with --headless; to see the game, the agent runs it from the editor (godot.run_scene) and captures it (godot.capture_game_frame).") % launch.left(80), ChatEntry.NoticeLevel.WARNING)
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
	if request.group == PermissionPolicy.GROUP_EDIT_FILES and _file_taken(Preauthorizations.write_paths(request, call)):
		return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
	# Fuera de los archivos del modo del proyecto (m11-39): se rechaza siempre, sin tarjeta. Las godot.*
	# las revisa el precheck del registro.
	if request.group == PermissionPolicy.GROUP_EDIT_FILES and not PermissionPolicy.is_godot_mcp_tool(tool_call):
		var refused := mode_refused_write(Preauthorizations.write_paths(request, call))
		if not refused.is_empty():
			notify_mode_refusal(request.title, refused)
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
	var forced := mode_forces_ask(request.group) and not PermissionPolicy.is_godot_mcp_tool(tool_call)
	var decision := decide(request.group)
	if PermissionPolicy.is_mcp_group(request.group):
		var server := request.group.trim_prefix(PermissionPolicy.GROUP_MCP_PREFIX)
		seen_mcp_servers[server] = true
		request.persist_label = I18n.t("Always allow «%s» in %s mode, in this project") % [server, I18n.t(_mode_label())]
	if PermissionPolicy.is_godot_mcp_tool(tool_call):
		decision = PermissionPolicy.ALLOW  # el server MCP aplica la política al ejecutar la tool
	elif decision == PermissionPolicy.ASK and request.group == PermissionPolicy.GROUP_SHELL and model.harness_mode == SessionModel.HarnessMode.AUTO and not forced:
		var command := ShellCommand.of(checked.get("rawInput"))
		var verdict := ShellRules.classify(command, shell_rules)
		if verdict.decision == ShellRules.ALLOW:
			_log_perm("allowed by Auto mode, %s: %s" % [verdict.reason, command])
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS]))
		_log_perm("Auto mode asks, %s: %s" % [verdict.reason, command])
		# En lugar de «siempre en esta sesión» (todo el grupo shell), la tarjeta propone una regla.
		request.rule_pattern = ShellRules.suggest_pattern(command, shell_rules)
		if agent_log and agent_log.redact(request.rule_pattern) != request.rule_pattern:
			# Una regla con un secreto (m13-28): la tarjeta lo mostraría y Ajustes lo guardaría en disco.
			_log_perm("no rule suggested: the command pattern has a secret")
			request.rule_pattern = ""
		request.options = options.filter(func(option: Variant) -> bool: return not (option is Dictionary and option.get("kind") == PermissionRequest.KIND_ALLOW_ALWAYS))
	if request.group == PermissionPolicy.GROUP_SUBAGENTS and decision != PermissionPolicy.DENY:
		if _subagent_limit_reached(request.tool_call_id):
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
		if decision == PermissionPolicy.ALLOW:
			_approved_subagents[request.tool_call_id] = true
	match decision:
		PermissionPolicy.ALLOW:
			_log_perm("allowed by %s mode: %s" % [_mode_label(), request.title])
			_preauth.grant(request, call)
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS]))
		PermissionPolicy.DENY:
			_notify_denied(request.group, request.title)
			return _selected_or_cancelled(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))
	if forced:
		_log_perm("project mode %s asks: %s" % [model.project_mode.get("name", ""), request.title])
		request.options = without_always(request.options)
		request.persist_label = ""
	else:
		_offer_session_allow(request)
	var outcome := await _ask_user(request, 0)
	_emit_feedback(request)
	if not request.rule_to_add.is_empty():
		_add_shell_rule(request.rule_to_add)
	if request.persist_allow and request.was_allowed():
		policy.set_matrix_value(request.group, model.harness_mode, PermissionPolicy.ALLOW)
		_log_perm("%s allowed in %s mode, saved in the project matrix" % [request.group, _mode_label()])
		permissions_changed.emit()
	if outcome.get("outcome") != "selected":
		return {"outcome": {"outcome": "cancelled"}}
	if request.was_allowed():
		_preauth.grant(request, call)
		if request.group == PermissionPolicy.GROUP_SUBAGENTS:
			_approved_subagents[request.tool_call_id] = true
		# "Siempre" queda en la memoria de la sesión del harness; al agente se le responde
		# "una vez" para que no lo guarde en sus settings en disco (spec §4.2).
		var once := request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE])
		return _selected_or_cancelled(once if not once.is_empty() else str(outcome.optionId))
	var reject_once := request.option_id_for([PermissionRequest.KIND_REJECT_ONCE])
	return _selected_or_cancelled(reject_once if not reject_once.is_empty() else str(outcome.optionId))


## El plan del modo plan del agente (m11-22): siempre se pregunta, en todo modo y sin timeout (lo
## decidió el usuario: editar un plan largo lleva tiempo). Solo «aprobar» y «rechazar»; aprobar lo
## contesta SessionController.approve_plan, que antes pasa el harness a Construir.
func _ask_plan(request: PermissionRequest, shown: Dictionary, options: Array) -> Dictionary:
	request.plan_text = PlanApproval.plan_text(shown)
	if request.plan_text.is_empty():
		request.plan_text = request.title  # sin texto no hay qué editar, pero sigue siendo el plan
	request.title = I18n.t("Plan ready to build")
	request.description = ""
	request.group = PermissionPolicy.GROUP_OTHER
	request.options = PlanApproval.filter_options(options)
	if not request.tool_call_id.is_empty():
		model.mark_plan_card(request.tool_call_id)
	var known := PackedStringArray(options.map(func(option: Variant) -> String: return str(option.get("optionId", "")) if option is Dictionary else ""))
	_log_perm("plan to approve (%d lines); options offered %s of %s" % [request.plan_text.count("\n") + 1, request.options.map(func(o: Dictionary) -> String: return str(o.get("optionId", ""))), known])
	var outcome := await _ask_user(request, 0)
	_emit_feedback(request)
	if outcome.get("outcome") != "selected":
		return {"outcome": {"outcome": "cancelled"}}
	return _selected_or_cancelled(str(outcome.optionId))


## Después de un rechazo con motivo o con el plan editado, el texto para el agente (ver reject_feedback).
func _emit_feedback(request: PermissionRequest) -> void:
	if request.outcome.get("outcome") != "selected" or request.was_allowed():
		return
	if request.is_plan() and not request.edited_plan.is_empty():
		reject_feedback.emit(PlanApproval.edit_feedback(request.plan_text, request.edited_plan), HarnessPrompts.PLAN_EDIT)
	elif request.is_plan() and not request.deny_reason.is_empty():
		reject_feedback.emit(PlanApproval.keep_planning_feedback(request.deny_reason), HarnessPrompts.PLAN_KEEP_PLANNING)
	elif not request.deny_reason.is_empty():
		reject_feedback.emit(PlanApproval.deny_feedback(request.title, request.deny_reason), HarnessPrompts.DENY_REASON)


## Algunos agentes (Antigravity) solo ofrecen «una vez»: el harness suma «Siempre en esta sesión»,
## que guarda él (al agente se le contesta «una vez», como con cualquier «siempre», m17-24).
## La shell nunca: «siempre» abriría todos los comandos, también los de «siempre preguntar» y en
## cualquier modo (revisión m17). Ahí la tarjeta sale sin «siempre» y, en Auto, propone una regla.
func _offer_session_allow(request: PermissionRequest) -> void:
	if request.group == PermissionPolicy.GROUP_SHELL:
		request.options = without_always(request.options)
		return
	if request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE]).is_empty() or not request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty():
		return
	var options := request.options.duplicate()
	options.append({"optionId": HARNESS_ALLOW_ALWAYS, "name": I18n.t("Always allow in this session"), "kind": PermissionRequest.KIND_ALLOW_ALWAYS})
	request.options = options


static func without_always(options: Array) -> Array:
	return options.filter(func(option: Variant) -> bool: return not (option is Dictionary and option.get("kind") == PermissionRequest.KIND_ALLOW_ALWAYS))


func _ask_user(request: PermissionRequest, timeout_s: int) -> Dictionary:
	var acp_id: Variant = client.handling_id
	if acp_id != null:
		_permissions_by_acp_id[acp_id] = request
	_log_perm("asking the user: %s" % request.title)
	model.add_permission(request)
	if timeout_s > 0:
		var tree := Engine.get_main_loop() as SceneTree
		tree.create_timer(timeout_s).timeout.connect(func() -> void:
			if request.is_pending():
				_log_perm("no answer in %d s, denied: %s" % [timeout_s, request.title])
				request.cancel()
		)
	var outcome: Dictionary = request.outcome
	if request.is_pending():
		outcome = await request.resolved
		# `resolved` llega dentro de quien respondió (un clic, stop()): lo que sigue (guardar la
		# escena, editar nodos) va en el frame siguiente. Godot 4.8 se cayó en
		# BaseButton::on_action_event al guardar dentro del clic (m12-39, m13-02). Si lo retiró
		# el agente ($/cancel_request) no hay clic y la respuesta tiene que salir ya.
		if not request.withdrawn:
			await next_frame()
	if acp_id != null and _permissions_by_acp_id.get(acp_id) == request:
		_permissions_by_acp_id.erase(acp_id)
	# La shell no se abre entera para la sesión (ver _offer_session_allow).
	if request.chosen_kind == PermissionRequest.KIND_ALLOW_ALWAYS and request.group != PermissionPolicy.GROUP_SHELL:
		policy.grant_for_session(request.group)
	_log_perm("%s: %s" % [_outcome_label(request), request.title])
	return outcome


## Regla elegida en una tarjeta («Permitir siempre»): queda en las listas con su origen y fecha.
func _add_shell_rule(rule: Dictionary) -> void:
	var pattern := ShellRules.normalize(str(rule.get("pattern", "")))
	if pattern.is_empty():
		return
	for existing: Variant in shell_rules:
		if existing is Dictionary and existing.get("pattern") == pattern and existing.get("list") == rule.get("list"):
			return
	shell_rules.append(ShellRules.make_rule(pattern, str(rule.get("list", ShellRules.LIST_ALLOW)), ShellRules.ORIGIN_CARD, ShellRules.today()))
	_log_perm("rule added to the Auto %s list: %s" % [rule.get("list", ShellRules.LIST_ALLOW), pattern])
	shell_rules_changed.emit()


func authorize_fs_write(path: String, old_text: String, new_text: String) -> bool:
	if _file_taken(PackedStringArray([path])):
		return false
	if not mode_refused_write(PackedStringArray([path])).is_empty():
		notify_mode_refusal(I18n.t("Write %s") % path.get_file(), path)
		return false
	if _preauth.consume_write(path):
		return true
	var counts := LineDiff.count(LineDiff.diff(old_text, new_text))
	var description := "%s · +%d −%d" % [path.trim_prefix(cwd + "/"), counts.added, counts.removed]
	return await authorize(
		PermissionPolicy.GROUP_EDIT_FILES, I18n.t("Write %s") % path.get_file(), description,
		{"path": path, "oldText": old_text, "newText": new_text}
	)


## Con variables de entorno del agente siempre se pregunta y la tarjeta las muestra: cambian lo que
## hace el comando (LD_PRELOAD, GIT_CONFIG_*, PATH…) sin que se vea en la línea que revisan las reglas.
func authorize_terminal_command(command_line: String, working_dir: String, env: Dictionary = {}) -> String:
	var blocked := ProjectWriteGuard.blocked_target({"kind": "execute", "rawInput": {"command": command_line}}, PermissionPolicy.GROUP_SHELL, working_dir if not working_dir.is_empty() else cwd)
	if not blocked.is_empty():
		_notify_blocked_write(command_line, blocked)
		return "%s is not written by hand: %s." % [blocked, ProjectWriteGuard.alternative_for(blocked)]
	var launch := GodotWindowGuard.windowed_launch(command_line, EditorBinary.path())
	if not launch.is_empty():
		_log_perm("rejected, opens Godot in its own window: %s" % launch)
		model.add_notice(I18n.t("Rejected: «%s» opens Godot in its own window. Command-line Godot only runs with --headless; to see the game, the agent runs it from the editor (godot.run_scene) and captures it (godot.capture_game_frame).") % launch.left(80), ChatEntry.NoticeLevel.WARNING)
		return "Command-line Godot only runs with --headless: %s" % launch
	if env.is_empty() and _preauth.consume_command(command_line):
		return ""
	var forced := mode_forces_ask(PermissionPolicy.GROUP_SHELL)
	var decision := decide(PermissionPolicy.GROUP_SHELL)
	if decision == PermissionPolicy.ALLOW and env.is_empty():
		_log_perm("allowed by %s mode: %s" % [_mode_label(), command_line])
		return ""
	if decision == PermissionPolicy.DENY:
		_notify_denied(PermissionPolicy.GROUP_SHELL, command_line)
		return "Permission denied in %s mode: %s" % [_mode_label(), command_line]
	if not env.is_empty():
		_log_perm("asks, the agent sets environment variables (%s): %s" % [", ".join(PackedStringArray(env.keys())), command_line])
	elif forced:
		_log_perm("project mode %s asks: %s" % [model.project_mode.get("name", ""), command_line])
	elif model.harness_mode == SessionModel.HarnessMode.AUTO:
		var verdict := ShellRules.classify(command_line, shell_rules)
		if verdict.decision == ShellRules.ALLOW:
			_log_perm("allowed by Auto mode, %s: %s" % [verdict.reason, command_line])
			return ""
		_log_perm("Auto mode asks, %s: %s" % [verdict.reason, command_line])
	var request := PermissionRequest.new()
	request.group = PermissionPolicy.GROUP_SHELL
	request.title = I18n.t("Terminal")
	request.description = command_line
	if not env.is_empty():
		var assignments: PackedStringArray = []
		for key: Variant in env:
			assignments.append("%s=%s" % [key, TerminalHandler.shell_quote(str(env[key]))])
		request.description = "%s %s" % [" ".join(assignments), command_line]
	if not working_dir.is_empty() and working_dir.simplify_path().trim_suffix("/") != cwd.simplify_path().trim_suffix("/"):
		request.description += "\n" + I18n.t("in %s") % working_dir
	# Sin «siempre en esta sesión»: abriría toda la shell (revisión m17).
	request.options = without_always(PermissionRequest.default_options())
	if model.harness_mode == SessionModel.HarnessMode.AUTO and env.is_empty() and not forced:  # una regla no ve las variables
		request.rule_pattern = ShellRules.suggest_pattern(command_line, shell_rules)
	var outcome := await _ask_user(request, 0)
	_emit_feedback(request)
	if not request.rule_to_add.is_empty():
		_add_shell_rule(request.rule_to_add)
	if outcome.get("outcome") == "selected" and request.was_allowed():
		return ""
	return "Permission denied by the user or the current mode: %s" % command_line


## true (y lo avisa) si lanzar otro subagente pasa el límite del modo (m7-43).
func _subagent_limit_reached(tool_call_id: String) -> bool:
	var limit := policy.subagent_limit(model.harness_mode)
	if limit <= 0:
		return false
	# Cuentan los que el agente informa trabajando y, sin informe, los que corren o ya se permitieron
	# (un pedido pendiente que se rechaza no arranca).
	var running := model.running_subagents().filter(func(call: ToolCall) -> bool:
		return call.id != tool_call_id and (not call.subagent_state.is_empty() or call.status == ToolCall.STATUS_IN_PROGRESS or _approved_subagents.has(call.id)))
	if running.size() < limit:
		return false
	_log_perm("rejected, %d subagents already running (limit %d in %s mode)" % [running.size(), limit, _mode_label()])
	model.add_notice(I18n.t("A subagent was not started: %d already running, the limit in %s mode (Settings → Permissions).") % [running.size(), I18n.t(_mode_label())], ChatEntry.NoticeLevel.WARNING)
	return true


## true (y lo avisa) si otra sesión abierta está editando alguno de `paths` (m7-44).
func _file_taken(paths: PackedStringArray) -> bool:
	if not file_guard.is_valid() or paths.is_empty():
		return false
	var owner: String = file_guard.call(paths)
	if owner.is_empty():
		return false
	var names := ", ".join(Array(paths).map(func(path: String) -> String: return path.get_file()))
	_log_perm("rejected, %s is being edited by %s" % [names, owner])
	model.add_notice(I18n.t("Rejected: %s is being edited by «%s». It's free again when that session's turn ends.") % [names, owner], ChatEntry.NoticeLevel.WARNING)
	return true


func _notify_denied(group: String, title: String) -> void:
	var group_label: String = PermissionPolicy.GROUP_LABELS.get(group, group)
	_log_perm("denied in %s mode (%s): %s" % [_mode_label(), group_label, title])
	var shown_group := I18n.t(group_label) if PermissionPolicy.GROUP_LABELS.has(group) else group
	model.add_notice(I18n.t("Denied in %s mode (%s): %s") % [model.mode_display(), shown_group, title], ChatEntry.NoticeLevel.WARNING)


func _notify_blocked_write(title: String, target: String) -> void:
	_log_perm("rejected, writes %s outside the editor: %s" % [target, title])
	model.add_notice(I18n.t("Rejected: «%s» writes %s without going through the editor. Scripts go through the agent's file tools; scenes and project settings through the godot.* tools.") % [title.left(80), target], ChatEntry.NoticeLevel.WARNING)


## MCP servers de terceros (configurados o ya vistos) que en `mode` preguntan o se niegan: en el
## One-shot, cada tool de esos frena el run hasta que alguien conteste.
func mcp_servers_not_allowed(mode: SessionModel.HarnessMode, external_mcp_names: PackedStringArray) -> PackedStringArray:
	var names: Dictionary = {}
	for name: String in external_mcp_names:
		names[name] = true
	names.merge(seen_mcp_servers)
	var result: PackedStringArray = []
	for name: String in names:
		if policy.decide(PermissionPolicy.mcp_group(name), mode) != PermissionPolicy.ALLOW:
			result.append(name)
	result.sort()
	return result


static func _selected_or_cancelled(option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {"outcome": {"outcome": "cancelled"}}
	return {"outcome": {"outcome": "selected", "optionId": option_id}}


static func _describe_tool_call(tool_call: Dictionary, call: Variant) -> String:
	var input: Variant = tool_call.get("rawInput", call.raw_input if call else null)
	if not ShellCommand.of(input).is_empty():
		return ShellCommand.of(input)
	if input is Dictionary:
		for key: String in ["file_path", "path", "url", "pattern", "description"]:
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


## Un frame del árbol (sin árbol, en algunos tests, no espera).
static func next_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame
