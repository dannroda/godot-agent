@tool
extends RefCounted
## Pedido de permiso pendiente (session/request_permission o una tool MCP en "ask").
## La UI lo resuelve eligiendo una opción; cancelar o el timeout lo resuelven como cancelado.

signal resolved(outcome: Dictionary)
## Cambió algo que la tarjeta muestra (los criterios verificados de un plan, m11-23).
signal changed

const KIND_ALLOW_ONCE := "allow_once"
const KIND_ALLOW_ALWAYS := "allow_always"
const KIND_REJECT_ONCE := "reject_once"
const KIND_REJECT_ALWAYS := "reject_always"

var title: String = ""
var description: String = ""
var group: String = ""
## `[{optionId, name, kind}]` tal como las mandó el agente.
var options: Array = []
var tool_call_id: String = ""
## Diff a mostrar en la tarjeta: `{path, oldText, newText}` o {}.
var diff: Dictionary = {}
## {} mientras está pendiente; después `{outcome: "selected", optionId}` o `{outcome: "cancelled"}`.
var outcome: Dictionary = {}
## Kind de la opción elegida ("" si se canceló).
var chosen_kind: String = ""
## El agente retiró el pedido (`$/cancel_request`): lo contestaron desde Remote Control (m7-21).
var withdrawn: bool = false
## Modo Auto (D57): patrón que la tarjeta propone para «Permitir siempre» ("" = no se ofrece).
var rule_pattern: String = ""
## `{pattern, list}` que el usuario eligió agregar a las listas del modo Auto, o {}.
var rule_to_add: Dictionary = {}
## MCP server de terceros (m7-35): la tarjeta ofrece permitirlo siempre en este modo y proyecto, con
## este texto en el botón ("" = no se ofrece).
var persist_label: String = ""
## El usuario eligió permitir el grupo en este modo, guardado en la matriz del proyecto.
var persist_allow: bool = false
## Plan a aprobar (m11-22, ExitPlanMode): el texto que presentó el agente ("" = tarjeta común).
var plan_text: String = ""
## El plan como lo dejó el usuario con «Editar» ("" = no lo editó).
var edited_plan: String = ""
## «Denegar con motivo» / «Seguir planeando…»: lo que escribió el usuario ("" = sin motivo).
var deny_reason: String = ""
## El plan se aprobó con «Aprobar y construir» (el harness pasó a Construir).
var plan_approved: bool = false
## El plan vino en un bloque ```plan al final del turno (m11-58): la tarjeta es del harness y no
## contesta ningún pedido del agente.
var from_block: bool = false
## Si se verifican jugando los criterios del plan al aprobarlo (m11-23): la casilla de la tarjeta.
## -1 = el usuario no la tocó y vale el setting del proyecto; 0 no; 1 sí.
var verify_criteria: int = -1
## Cuántos criterios juega una corrida (el setting), para que la tarjeta diga el costo.
var criteria_max: int = 6
## Lo que salió de verificar cada criterio: [{name, goal, status, summary, evidence}] (la tarjeta lo muestra).
var criteria_results: Array = []


func is_plan() -> bool:
	return not plan_text.is_empty()


## Rechaza con el motivo del usuario: la tarjeta lo muestra y sale como prompt al terminar el turno.
func deny_with_reason(reason: String) -> void:
	if not is_pending() or reason.strip_edges().is_empty():
		return
	deny_reason = reason.strip_edges()
	select(option_id_for([KIND_REJECT_ONCE, KIND_REJECT_ALWAYS]))


## Rechaza el plan con la versión editada: el agente recibe el diff y lo vuelve a presentar.
func submit_edited_plan(text: String) -> void:
	if not is_pending() or not is_plan() or text.strip_edges() == plan_text.strip_edges():
		return
	edited_plan = text
	select(option_id_for([KIND_REJECT_ONCE, KIND_REJECT_ALWAYS]))


func is_pending() -> bool:
	return outcome.is_empty()


func select(option_id: String) -> void:
	if not is_pending():
		return
	for option: Variant in options:
		if option is Dictionary and str(option.get("optionId", "")) == option_id:
			chosen_kind = str(option.get("kind", ""))
	outcome = {"outcome": "selected", "optionId": option_id}
	resolved.emit(outcome)


func cancel() -> void:
	if not is_pending():
		return
	outcome = {"outcome": "cancelled"}
	resolved.emit(outcome)


func was_allowed() -> bool:
	return chosen_kind in [KIND_ALLOW_ONCE, KIND_ALLOW_ALWAYS]


## Primera opción con alguno de los kinds dados, o "".
func option_id_for(kinds: PackedStringArray) -> String:
	for kind: String in kinds:
		for option: Variant in options:
			if option is Dictionary and str(option.get("kind", "")) == kind:
				return str(option.get("optionId", ""))
	return ""


## Opciones estándar para pedidos propios del harness (fs/write, tools MCP).
static func default_options() -> Array:
	return [
		{"optionId": "allow_once", "name": "Allow once", "kind": KIND_ALLOW_ONCE},
		{"optionId": "allow_always", "name": "Always allow in this session", "kind": KIND_ALLOW_ALWAYS},
		{"optionId": "reject_once", "name": "Deny", "kind": KIND_REJECT_ONCE},
	]
