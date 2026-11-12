@tool
extends RefCounted
## Segunda opinión de otro agente (m11-28, el Oracle de Amp): una sesión sin pestaña, con el perfil que
## el usuario elige en Settings › Agentes, que lee el proyecto y contesta sin editar nada. La pide el
## agente con godot.ask_second_opinion o el usuario desde el aviso de fin de turno, la tarjeta del plan
## o /second-opinion. Recibe la pregunta, el diff del turno o el plan, y los archivos que se nombren;
## no la conversación principal: un modelo sin ese contexto ve lo que el primero no ve (D55).
##
## Una sola por editor, arrancada con la primera pregunta y reusada (el arranque del otro agente es lo
## caro). Las preguntas van de a una; cada una tiene un tope de tiempo. Solo lectura forzada como el
## evaluador de QA: `policy.restrictions` cubre todos los grupos (read y diagnostics allow, el resto
## deny) y una tarjeta que llegue igual se rechaza sola, porque no hay pestaña donde contestarla.

signal changed

const SessionModel := preload("session_model.gd")
const SessionController := preload("session_controller.gd")
const PermissionPolicy := preload("permission_policy.gd")
const PermissionRequest := preload("permission_request.gd")
const AgentProfile := preload("../core/agent_profile.gd")
const AgentLog := preload("../core/agent_log.gd")
const I18n := preload("../core/i18n.gd")
const ChatEntry := preload("chat_entry.gd")

## El id de sesión del oráculo para el plugin y el server MCP: _controller_of lo resuelve sin pestaña.
const SESSION_ID := "second_opinion"
## Lo que entra del diff del turno; el resto va como lista de archivos para que los lea.
const DIFF_MAX := 30000
const PLAN_MAX := 20000
const QUESTION_MAX := 4000
const TIMEOUT_SEC := 300.0
const DEFAULT_QUESTION := "Review this as a second opinion: risks, bugs, design problems and what you would do differently. Point to file:line where it applies."
const MODE_RULES := "You are a second opinion for another agent working on this Godot project. Read whatever you need, but do not change anything: editing files, scenes or project settings, running the game and shell commands are denied. Answer with your findings, most important first, each pointing to file:line where it applies; say plainly when you agree."

## Grupos que puede usar: leer y diagnosticar. Todo lo demás (también lo que se agregue) se deniega.
const ALLOWED_GROUPS: PackedStringArray = [PermissionPolicy.GROUP_READ, PermissionPolicy.GROUP_DIAGNOSTICS]

var controller: SessionController
var model: SessionModel
## El perfil con el que corre (null hasta la primera pregunta).
var profile: AgentProfile
## La pestaña que hizo la pregunta en curso ("" sin pregunta).
var requested_by: String = ""
var _started_msec: int = 0
var _busy: bool = false
var _queue_waiters: int = 0
var _generation: int = 0


func _init(session_controller: SessionController = null, session_model: SessionModel = null) -> void:
	controller = session_controller
	model = session_model
	if model:
		model.permission_requested.connect(_on_permission_requested)


func is_busy() -> bool:
	return _busy


func age_seconds() -> int:
	return int((Time.get_ticks_msec() - _started_msec) / 1000) if _busy else -1


## «Codex · gpt-5»: el agente y el modelo, para el chip y el aviso.
func agent_label() -> String:
	var name := profile.label() if profile else ""
	var current := _model_name()
	return name if current.is_empty() else "%s · %s" % [name, current]


func _model_name() -> String:
	if model == null:
		return ""
	var option := model.model_option()
	var value := str(option.get("currentValue", ""))
	for item: Variant in option.get("options", []):
		if item is Dictionary and str(item.get("value", "")) == value:
			return str(item.get("name", value))
	return value


## Las restricciones de solo lectura: todos los grupos conocidos, read y diagnostics allow.
static func restrictions() -> Dictionary:
	var result := {}
	for group: String in PermissionPolicy.GROUPS:
		result[group] = PermissionPolicy.ALLOW if group in ALLOWED_GROUPS else PermissionPolicy.DENY
	result[PermissionPolicy.GROUP_OTHER] = PermissionPolicy.DENY
	return result


## El prompt para el oráculo: la pregunta, el plan o el diff (cortado) y los archivos a leer.
## `context`: {plan?: String, diff?: String, files?: PackedStringArray (los del turno), paths?: Array}.
static func build_prompt(question: String, context: Dictionary = {}) -> String:
	var ask := question.strip_edges()
	if ask.is_empty():
		ask = DEFAULT_QUESTION
	ask = ask.left(QUESTION_MAX)
	var parts: PackedStringArray = [ask]
	var plan := str(context.get("plan", "")).strip_edges()
	if not plan.is_empty():
		parts.append("The plan another agent proposes:\n\n" + _cut(plan, PLAN_MAX, "[the plan continues; this is the first part]"))
	var diff := str(context.get("diff", "")).strip_edges()
	var files: Array = context.get("files", [])
	if not diff.is_empty():
		var cut := diff.length() > DIFF_MAX
		var block := "The changes of the other agent's last turn (git diff):\n\n```diff\n%s\n```" % diff.left(DIFF_MAX)
		if cut:
			block += "\n\nThe diff was cut at %d characters. Read the rest of these files yourself: %s" % [DIFF_MAX, ", ".join(PackedStringArray(files))]
		parts.append(block)
	elif not files.is_empty():
		parts.append("Files the other agent changed in its last turn (read them): " + ", ".join(PackedStringArray(files)))
	var paths: PackedStringArray = []
	for path: Variant in context.get("paths", []):
		if str(path).strip_edges() != "":
			paths.append("@" + str(path).strip_edges().trim_prefix("@"))
	if not paths.is_empty():
		parts.append("Also look at: " + " ".join(paths))
	return "\n\n".join(parts)


static func _cut(text: String, limit: int, note: String) -> String:
	return text if text.length() <= limit else text.left(limit) + "\n\n" + note


## Hace la pregunta y espera la respuesta: `{ok, text, tokens, agent, error}`. `requester` es la pestaña
## que la pide (para el chip). Una a la vez: si hay otra en curso, espera su turno.
func ask(question: String, context: Dictionary, agent_profile: AgentProfile, requester: String = "") -> Dictionary:
	if agent_profile == null:
		return {"ok": false, "error": I18n.t("No agent is chosen for second opinions: pick one in Settings › Agents › Second opinion.")}
	if controller == null:
		return {"ok": false, "error": "No session for the second opinion."}
	_queue_waiters += 1
	while _busy:
		await changed
	_queue_waiters -= 1
	_busy = true
	_started_msec = Time.get_ticks_msec()
	requested_by = requester
	_generation += 1
	var generation := _generation
	changed.emit()
	var result := await _ask(question, context, agent_profile, generation)
	_busy = false
	requested_by = ""
	changed.emit()
	return result


func _ask(question: String, context: Dictionary, agent_profile: AgentProfile, generation: int) -> Dictionary:
	var same_profile := profile != null and profile.to_dict() == agent_profile.to_dict()
	if not same_profile and controller.is_connected_to_agent():
		controller.stop()
	profile = agent_profile
	controller.policy.restrictions = restrictions()
	controller.mode_rules_override = MODE_RULES
	model.set_harness_mode(SessionModel.HarnessMode.ASK)
	if not controller.is_connected_to_agent() or model.session_id.is_empty():
		if not await controller.start(agent_profile):
			return {"ok": false, "error": I18n.t("Could not start %s for the second opinion: %s") % [agent_profile.label(), model.failure_message]}
	if generation != _generation:
		return {"ok": false, "error": "Cancelled."}
	_watch_timeout(generation)
	var first := model.entries().size()
	var stop_reason: String = await controller.send_prompt(build_prompt(question, context), [], false)
	if generation != _generation or stop_reason == "cancelled":
		return {"ok": false, "error": I18n.t("The second opinion was cancelled.")}
	var text := controller.agent_text_since(first).strip_edges()
	if text.is_empty():
		return {"ok": false, "error": I18n.t("%s didn't answer (%s).") % [agent_profile.label(), stop_reason if not stop_reason.is_empty() else "no turn"]}
	return {"ok": true, "text": text, "tokens": int(controller.last_turn_usage.get("totalTokens", 0)), "agent": agent_label(), "session_id": model.session_id}


func _watch_timeout(generation: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(TIMEOUT_SEC, true, false, true).timeout
	if generation == _generation and _busy:
		controller.agent_log.add(AgentLog.CH_ACP, "Second opinion: no answer in %d s, cancelled" % int(TIMEOUT_SEC))
		cancel()


## Corta la pregunta en curso.
func cancel() -> void:
	if not _busy:
		return
	_generation += 1
	controller.cancel()
	changed.emit()


## Sin pestaña no hay quien conteste una tarjeta: se rechaza sola (lo que pide escribir ya lo deniega
## la matriz; esto cubre los grupos que preguntan, como los MCP servers de otros programas).
func _on_permission_requested(request: PermissionRequest) -> void:
	if request.is_pending():
		controller.agent_log.add(AgentLog.CH_PERM, "Second opinion: denied «%s» (read only, no tab to ask)" % request.title)
		request.select(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]))


## El aviso «Asking…» pasa a ser la respuesta (m11-28): plegada, con el agente y los tokens, «Send to
## the agent» (en sobre no confiable: el otro agente leyó el proyecto) y «Open the conversation».
static func fill_notice(entry: ChatEntry, result: Dictionary, session: String) -> ChatEntry:
	if not bool(result.get("ok", false)):
		entry.level = ChatEntry.NoticeLevel.WARNING
		entry.text = str(result.get("error", ""))
		entry.actions = []
		return entry
	entry.level = ChatEntry.NoticeLevel.INFO
	entry.title = I18n.t("Second opinion · %s") % result.get("agent", "")
	entry.text = I18n.t("%d tokens. Nothing was sent to the agent of this tab.") % int(result.get("tokens", 0))
	entry.details_title = I18n.t("Answer")
	entry.details = str(result.get("text", ""))
	entry.actions = [
		{"id": SessionController.ACTION_SEND_SECOND_OPINION, "label": I18n.t("Send to the agent"), "primary": true, "data": str(result.get("text", "")),
			"tooltip": I18n.t("The agent of this tab gets the answer as information from another agent, not as instructions.")},
		{"id": SessionController.ACTION_SECOND_OPINION_OPEN, "label": I18n.t("Open the conversation"), "data": {"session": session, "session_id": str(result.get("session_id", ""))}},
	]
	return entry
