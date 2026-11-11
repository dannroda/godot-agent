@tool
extends RefCounted
## El plan que presenta un agente con modo plan para que se apruebe (m11-22): en Claude Code es el
## request_permission de ExitPlanMode (kind switch_mode, el plan en rawInput.plan; ver
## tests/fixtures/acp/exit_plan_mode_0105.json). La tarjeta ofrece aprobar (pasa a Construir),
## editarlo o seguir planeando con un motivo; lo editado y el motivo vuelven al agente como prompt
## del harness cuando termina el turno que cortó el rechazo.

const LineDiff := preload("../core/line_diff.gd")

const TOOL_NAME := "ExitPlanMode"
const KIND_SWITCH_MODE := "switch_mode"
## La opción de 0.105 que aprueba sin cambiar a auto ni bypass: las ediciones siguen pidiendo permiso.
const DEFAULT_OPTION_ID := "exit-plan-default"


## true si el pedido es un plan a aprobar: la tool ExitPlanMode (por `name`, el `_meta` de Claude
## Code o el ToolCall ya conocido) o un switch_mode que trae el plan.
static func is_plan_request(tool_call: Dictionary, known_tool_name: String = "") -> bool:
	if not plan_text(tool_call).is_empty() and str(tool_call.get("kind", "")) == KIND_SWITCH_MODE:
		return true
	return TOOL_NAME in [str(tool_call.get("name", "")), known_tool_name, _meta_tool_name(tool_call)]


## El texto del plan: rawInput.plan o, si no, el primer bloque de texto del contenido.
static func plan_text(tool_call: Dictionary) -> String:
	var input: Variant = tool_call.get("rawInput")
	if input is Dictionary and input.get("plan") is String and not str(input.plan).strip_edges().is_empty():
		return str(input.plan)
	var content: Variant = tool_call.get("content")
	if content is Array:
		for block: Variant in content:
			if block is Dictionary and block.get("content") is Dictionary and block.content.get("type") == "text":
				var text := str(block.content.get("text", ""))
				if not text.strip_edges().is_empty():
					return text
	return ""


## Solo «aprobar» (la de 0.105, o la primera allow_once) y «rechazar» (reject_once): las de auto,
## bypass y «clear context» se saltean la matriz de Construir o arrancan otra query en el mismo turno.
static func filter_options(options: Array) -> Array:
	var allow: Variant = null
	var reject: Variant = null
	for option: Variant in options:
		if not option is Dictionary:
			continue
		if str(option.get("optionId", "")) == DEFAULT_OPTION_ID:
			allow = option
	for option: Variant in options:
		if not option is Dictionary:
			continue
		var kind := str(option.get("kind", ""))
		if allow == null and kind == "allow_once":
			allow = option
		if reject == null and kind == "reject_once":
			reject = option
	if reject == null:
		for option: Variant in options:
			if option is Dictionary and str(option.get("kind", "")) == "reject_always":
				reject = option
				break
	var result: Array = []
	if allow != null:
		result.append(allow)
	if reject != null:
		result.append(reject)
	return result


## Lo que se le manda al agente con el plan editado: el diff de líneas y el plan entero.
static func edit_feedback(original: String, edited: String) -> String:
	var lines: PackedStringArray = []
	for op: Dictionary in LineDiff.diff(original, edited):
		match op.kind:
			LineDiff.ADD:
				lines.append("+ " + str(op.text))
			LineDiff.REMOVE:
				lines.append("- " + str(op.text))
	return ("I edited your plan instead of approving it. Rework the plan with my changes and present it again for approval (ExitPlanMode); don't start implementing yet.\n\n"
		+ "Changed lines (- removed, + added):\n```diff\n%s\n```\n\nThe plan as I left it:\n\n%s") % ["\n".join(lines), edited.strip_edges()]


## «Seguir planeando» con un motivo.
static func keep_planning_feedback(reason: String) -> String:
	return "I didn't approve your plan. Keep planning and present it again for approval (ExitPlanMode); don't start implementing yet. What to change: %s" % reason.strip_edges()


## «Denegar con motivo» en cualquier tarjeta de permiso: el adapter solo le manda al agente que se
## rechazó; el motivo sale después como prompt.
static func deny_feedback(title: String, reason: String) -> String:
	return "I denied «%s». Reason: %s" % [title.strip_edges(), reason.strip_edges()]


## +N −M entre dos versiones del plan (para el contador del editor y el resultado de la tarjeta).
static func change_counts(original: String, edited: String) -> Dictionary:
	return LineDiff.count(LineDiff.diff(original, edited))


static func _meta_tool_name(tool_call: Dictionary) -> String:
	var meta: Variant = tool_call.get("_meta")
	if meta is Dictionary and meta.get("claudeCode") is Dictionary:
		return str(meta.claudeCode.get("toolName", ""))
	return ""
