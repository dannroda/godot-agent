@tool
extends RefCounted
## Una tool MCP `godot.*` (spec §6): nombre, descripción, inputSchema, grupo de permisos y el
## handler que la ejecuta en el hilo principal.
##
## El handler recibe los argumentos (Dictionary) y devuelve, o hace await y devuelve:
## - un resultado MCP `{content: [...], isError: bool}` (ver `text`, `error`, `image`);
## - un String (se envuelve como texto) o una Image (se envuelve como imagen).

const PermissionPolicy := preload("../session/permission_policy.gd")

const UntrustedText := preload("untrusted_text.gd")

## Sobres de texto no confiable (m11-45): la tool envuelve partes de su resultado, o el registry
## envuelve todo el texto de un resultado bueno. Las dos suman UntrustedText.NOTE a la descripción.
const ENVELOPE_NONE := 0
const ENVELOPE_PARTS := 1
const ENVELOPE_ALL := 2

## Tope de la descripción por defecto (la de la tarjeta de permiso).
const DESCRIBE_MAX_LINES := 8
const DESCRIBE_MAX_VALUE := 120

## Anotaciones MCP (spec 2025-06-18, ToolAnnotations) según el grupo de permisos (m11-47): salen
## del mismo dato que decide qué se pregunta, así no se desincronizan. Claude Code corre en paralelo
## las tools readOnlyHint y repite una vez, si se cortó la conexión, las readOnlyHint o
## idempotentHint. Un grupo que no está acá (other, mcp:…) no lleva anotaciones: los defaults de la
## spec son los prudentes (puede escribir y borrar). openWorldHint es false salvo en addons (baja
## código de internet); `hints` lo cambia en una tool.
const GROUP_HINTS: Dictionary = {
	PermissionPolicy.GROUP_READ: {"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true},
	PermissionPolicy.GROUP_DIAGNOSTICS: {"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true},
	PermissionPolicy.GROUP_EDIT_SCENE: {"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false},
	PermissionPolicy.GROUP_EDIT_FILES: {"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false},
	PermissionPolicy.GROUP_PROJECT: {"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false},
	# Corre el juego y lo cambia en vivo; los archivos del proyecto no.
	PermissionPolicy.GROUP_RUN: {"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false},
	PermissionPolicy.GROUP_SHELL: {"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false},
	PermissionPolicy.GROUP_PROJECT_TOOLS: {"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false},
	PermissionPolicy.GROUP_ADDONS: {"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": true},
	PermissionPolicy.GROUP_SESSIONS_MESSAGE: {"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
	PermissionPolicy.GROUP_SECOND_OPINION: {"readOnlyHint": true, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
}

var name: String = ""
var description: String = ""
var input_schema: Dictionary = {"type": "object", "properties": {}}
var group: String = ""
var handler: Callable
## Callable(args) -> String: descripción corta de la llamada para la tarjeta de permiso y el log.
var describer: Callable
## Callable(args) -> String: el grupo de permiso de una llamada cuando depende de los argumentos
## (copiar desde fuera del proyecto pide como un comando de shell). Sin él, `group`.
var group_resolver: Callable
## Anotaciones MCP que esta tool cambia respecto de las de su grupo (GROUP_HINTS): una tool del grupo
## read que manda un mensaje no es de solo lectura, una que consulta internet es openWorldHint.
var hints: Dictionary = {}
## Callable(args) -> PackedStringArray: las rutas res:// que escribe una llamada (m11-39), para los
## modos del proyecto que limitan archivos. Una lista vacía: no escribe nada del proyecto. Sin él, una
## tool de un grupo que escribe se rechaza en esos modos (no se puede revisar).
var write_targets: Callable
var envelope: int = ENVELOPE_NONE


static func create(tool_name: String, tool_group: String, tool_description: String, properties: Dictionary, required: PackedStringArray, tool_handler: Callable) -> RefCounted:
	var tool := new()
	tool.name = tool_name
	tool.group = tool_group
	tool.description = tool_description
	tool.input_schema = {"type": "object", "properties": properties, "additionalProperties": false}
	if not required.is_empty():
		tool.input_schema["required"] = Array(required)
	tool.handler = tool_handler
	return tool


## `tool` con `tool_hints` encima de las anotaciones de su grupo (para armarla en una expresión).
static func with_hints(tool: RefCounted, tool_hints: Dictionary) -> RefCounted:
	tool.hints = tool_hints
	return tool


func group_of(args: Dictionary) -> String:
	if group_resolver.is_valid():
		var resolved := str(group_resolver.call(args))
		if not resolved.is_empty():
			return resolved
	return group


## `tool` con lo que escribe (ver write_targets); para encadenar.
static func writing(tool: RefCounted, targets: Callable) -> RefCounted:
	tool.write_targets = targets
	return tool


## La tool con sobres para lo que devuelve (ENVELOPE_PARTS o ENVELOPE_ALL); para encadenar.
static func enveloped(tool: RefCounted, mode: int) -> RefCounted:
	tool.envelope = mode
	return tool


func to_mcp() -> Dictionary:
	var entry := {"name": name, "description": full_description(), "inputSchema": input_schema}
	var tool_annotations := annotations()
	if not tool_annotations.is_empty():
		entry["annotations"] = tool_annotations
	return entry


## Las anotaciones MCP de la tool: las de su grupo con `hints` encima. Vacío si el grupo no tiene.
func annotations() -> Dictionary:
	if not GROUP_HINTS.has(group) and hints.is_empty():
		return {}
	var result: Dictionary = (GROUP_HINTS.get(group, {}) as Dictionary).duplicate()
	if not result.has("openWorldHint"):
		result["openWorldHint"] = false
	result.merge(hints, true)
	return result


func full_description() -> String:
	return description + (UntrustedText.NOTE if envelope != ENVELOPE_NONE else "")


func describe(args: Dictionary) -> String:
	if describer.is_valid():
		return str(describer.call(args))
	# Una línea por argumento («node_path: World/Sun»): el JSON en una línea no se leía en la tarjeta.
	# Un diccionario se abre un nivel: «properties.light_energy: 1.2».
	var flat: Array = []
	for key: Variant in args:
		if args[key] is Dictionary and not (args[key] as Dictionary).is_empty():
			for sub: Variant in args[key]:
				flat.append(["%s.%s" % [key, sub], args[key][sub]])
		else:
			flat.append([str(key), args[key]])
	var lines: PackedStringArray = []
	for pair: Array in flat:
		if lines.size() == DESCRIBE_MAX_LINES:
			lines.append("…")
			break
		var text := str(pair[1]) if pair[1] is String else JSON.stringify(pair[1])
		lines.append("%s: %s" % [pair[0], text.left(DESCRIBE_MAX_VALUE) + ("…" if text.length() > DESCRIBE_MAX_VALUE else "")])
	return "\n".join(lines)


## Valida los argumentos contra el schema (required y tipos básicos). Devuelve "" si están bien,
## o un mensaje accionable.
func validate(args: Dictionary) -> String:
	var properties: Dictionary = input_schema.get("properties", {})
	for key: String in input_schema.get("required", []):
		if not args.has(key) or args[key] == null:
			return "Missing required argument '%s'." % key
	for key: Variant in args:
		if not properties.has(key):
			return "Unknown argument '%s'. Valid: %s." % [key, ", ".join(PackedStringArray(properties.keys()))]
		var expected: String = str(properties[key].get("type", ""))
		if args[key] == null or expected.is_empty():
			continue
		if not _matches_type(args[key], expected):
			return "The argument '%s' must be %s." % [key, expected]
		var allowed: Variant = properties[key].get("enum")
		if allowed is Array and not args[key] in allowed:
			return "The argument '%s' must be one of: %s." % [key, ", ".join(PackedStringArray(allowed))]
	return ""


static func _matches_type(value: Variant, expected: String) -> bool:
	match expected:
		"string":
			return value is String
		"integer":
			return value is int or (value is float and is_equal_approx(value, roundf(value)))
		"number":
			return value is int or value is float
		"boolean":
			return value is bool
		"object":
			return value is Dictionary
		"array":
			return value is Array
	return true


# --- resultados ----------------------------------------------------------------------------------

static func text(value: String) -> Dictionary:
	return {"content": [{"type": "text", "text": value}], "isError": false}


static func error(message: String) -> Dictionary:
	return {"content": [{"type": "text", "text": message}], "isError": true}


static func image(img: Image, caption: String = "") -> Dictionary:
	var content: Array = []
	if not caption.is_empty():
		content.append({"type": "text", "text": caption})
	content.append({"type": "image", "mimeType": "image/png", "data": Marshalls.raw_to_base64(img.save_png_to_buffer())})
	return {"content": content, "isError": false}


## Argumento entero con default (JSON trae los números como float).
static func int_arg(args: Dictionary, key: String, default_value: int) -> int:
	var value: Variant = args.get(key)
	return int(value) if value is int or value is float else default_value


static func str_arg(args: Dictionary, key: String, default_value: String = "") -> String:
	var value: Variant = args.get(key)
	return value if value is String else default_value
