@tool
extends RefCounted
## Pedido de permiso pendiente (session/request_permission o una tool MCP en "ask").
## La UI lo resuelve eligiendo una opción; cancelar o el timeout lo resuelven como cancelado.

signal resolved(outcome: Dictionary)

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
## Modo Auto (D57): patrón que la tarjeta propone para «Permitir siempre» ("" = no se ofrece).
var rule_pattern: String = ""
## `{pattern, list}` que el usuario eligió agregar a las listas del modo Auto, o {}.
var rule_to_add: Dictionary = {}


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
