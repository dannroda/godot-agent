@tool
extends RefCounted
## Pedido de información estructurada del agente (m11-17, ACP `elicitation/create`).
## Puede ser un formulario (`mode == "form"`, con `requestedSchema`) o un enlace (`mode == "url"`).

signal resolved(response: Dictionary)

const MODE_FORM := "form"
const MODE_URL := "url"

const ACTION_ACCEPT := "accept"
const ACTION_DECLINE := "decline"
const ACTION_CANCEL := "cancel"

var mode: String = MODE_FORM
var message: String = ""
var requested_schema: Dictionary = {}
var elicitation_id: String = ""
var url: String = ""
var session_id: String = ""
var tool_call_id: String = ""
## {} mientras está pendiente; después `{action: "accept", content?: Dictionary}`,
## `{action: "decline"}` o `{action: "cancel"}`.
var response: Dictionary = {}
## El agente avisó con `elicitation/complete` que el flujo por URL terminó.
var completed_by_agent: bool = false
## El agente retiró el pedido con `$/cancel_request`.
var withdrawn: bool = false


static func from_params(params: Dictionary) -> RefCounted:
	var req := new()
	req.mode = str(params.get("mode", MODE_FORM))
	req.message = str(params.get("message", ""))
	if params.get("requestedSchema") is Dictionary:
		req.requested_schema = params.requestedSchema
	if params.get("elicitationId") is String:
		req.elicitation_id = str(params.elicitationId)
	if params.get("url") is String:
		req.url = str(params.url)
	if params.get("sessionId") is String:
		req.session_id = str(params.sessionId)
	if params.get("toolCallId") is String:
		req.tool_call_id = str(params.toolCallId)
	return req


## Motivo por el que el pedido no se puede mostrar ("" si está bien): modo desconocido, o un enlace
## sin id o que no es http(s) (un file:// o una ruta abriría un archivo local con el programa del sistema).
func invalid_reason() -> String:
	if mode == MODE_FORM:
		return ""
	if mode != MODE_URL:
		return "Unsupported elicitation mode: %s" % mode
	if elicitation_id.is_empty():
		return "Missing 'elicitationId'."
	if not is_web_url(url):
		return "The url must be http or https: %s" % url
	return ""


static func is_web_url(text: String) -> bool:
	var lower := text.strip_edges().to_lower()
	return (lower.begins_with("https://") or lower.begins_with("http://")) and lower.length() > lower.find("//") + 2


func is_pending() -> bool:
	return response.is_empty()


func accept(content: Dictionary = {}) -> void:
	if not is_pending():
		return
	if mode == MODE_FORM:
		response = {"action": ACTION_ACCEPT, "content": content}
	else:
		response = {"action": ACTION_ACCEPT}
	resolved.emit(response)


func decline() -> void:
	if not is_pending():
		return
	response = {"action": ACTION_DECLINE}
	resolved.emit(response)


func cancel() -> void:
	if not is_pending():
		return
	response = {"action": ACTION_CANCEL}
	resolved.emit(response)


func schema_title() -> String:
	return str(requested_schema.get("title", "")) if requested_schema.get("title") is String else ""


func schema_description() -> String:
	return str(requested_schema.get("description", "")) if requested_schema.get("description") is String else ""


func properties() -> Dictionary:
	var props: Variant = requested_schema.get("properties")
	return props if props is Dictionary else {}


func field_names() -> PackedStringArray:
	var result: PackedStringArray = []
	for key: Variant in properties():
		result.append(str(key))
	return result


func field_schema(field_name: String) -> Dictionary:
	var props := properties()
	var prop: Variant = props.get(field_name)
	return prop if prop is Dictionary else {}


func required_fields() -> PackedStringArray:
	var result: PackedStringArray = []
	var req: Variant = requested_schema.get("required")
	if req is Array:
		for item: Variant in req:
			if item is String:
				result.append(item)
	return result


func is_required(field_name: String) -> bool:
	return field_name in required_fields()


## Valores iniciales de cada propiedad según `default` o su tipo.
func default_values() -> Dictionary:
	var values: Dictionary = {}
	var props := properties()
	for key: Variant in props:
		var name := str(key)
		var prop: Dictionary = props[key] if props[key] is Dictionary else {}
		if prop.has("default") and prop.get("default") != null:
			values[name] = prop.get("default")
			continue
		match str(prop.get("type", "string")):
			"boolean":
				values[name] = false
			"integer":
				values[name] = int(prop.get("minimum", 0)) if prop.get("minimum") != null else 0
			"number":
				values[name] = float(prop.get("minimum", 0.0)) if prop.get("minimum") != null else 0.0
			"array":
				values[name] = []
			_:
				var choices := enum_choices(prop)
				if not choices.is_empty() and is_required(name):
					values[name] = str(choices[0].value)
				else:
					values[name] = ""
	return values


## Devuelve "" si todos los campos obligatorios están completos, o el nombre del primero que falta.
func validate(values: Dictionary) -> String:
	var props := properties()
	for req_name: String in required_fields():
		var prop: Dictionary = props.get(req_name, {}) if props.get(req_name) is Dictionary else {}
		var label := str(prop.get("title", req_name))
		if not values.has(req_name):
			return label
		var val: Variant = values[req_name]
		if val == null or (val is String and str(val).strip_edges().is_empty()):
			return label
		if val is Array and (val as Array).is_empty():
			return label
	for key: Variant in props:
		var name := str(key)
		var prop: Dictionary = props[key] if props[key] is Dictionary else {}
		var label := str(prop.get("title", name))
		var val: Variant = values.get(name)
		# JSON trae todos los números como float.
		if val is String and _is_number(prop.get("minLength")) and str(val).length() < int(prop.minLength):
			if not str(val).is_empty() or is_required(name):
				return label
		if val is Array and _is_number(prop.get("minItems")) and (val as Array).size() < int(prop.minItems):
			if not (val as Array).is_empty() or is_required(name):
				return label
	return ""


## Opciones de un campo enum (`enum`/`oneOf` en `string`, o `items.enum`/`items.anyOf` en `array`):
## `[{value: String, label: String, description: String}]`.
static func enum_choices(prop: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Dictionary = prop
	if str(prop.get("type", "")) == "array" and prop.get("items") is Dictionary:
		source = prop.items
	if source.get("oneOf") is Array:
		for item: Variant in source.oneOf:
			if item is Dictionary and item.get("const") != null:
				var val := str(item.get("const"))
				result.append({
					"value": val,
					"label": str(item.get("title", val)),
					"description": str(item.get("description", "")) if item.get("description") is String else "",
				})
	elif source.get("anyOf") is Array:
		for item: Variant in source.anyOf:
			if item is Dictionary and item.get("const") != null:
				var val := str(item.get("const"))
				result.append({
					"value": val,
					"label": str(item.get("title", val)),
					"description": str(item.get("description", "")) if item.get("description") is String else "",
				})
	elif source.get("enum") is Array:
		for item: Variant in source.get("enum"):
			var val := str(item)
			result.append({"value": val, "label": val, "description": ""})
	return result


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
