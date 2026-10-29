@tool
extends RefCounted
## Una tool MCP `godot.*` (spec §6): nombre, descripción, inputSchema, grupo de permisos y el
## handler que la ejecuta en el hilo principal.
##
## El handler recibe los argumentos (Dictionary) y devuelve, o hace await y devuelve:
## - un resultado MCP `{content: [...], isError: bool}` (ver `text`, `error`, `image`);
## - un String (se envuelve como texto) o una Image (se envuelve como imagen).

## Tope de la descripción por defecto (la de la tarjeta de permiso).
const DESCRIBE_MAX_LINES := 8
const DESCRIBE_MAX_VALUE := 120

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


func group_of(args: Dictionary) -> String:
	if group_resolver.is_valid():
		var resolved := str(group_resolver.call(args))
		if not resolved.is_empty():
			return resolved
	return group


func to_mcp() -> Dictionary:
	return {"name": name, "description": description, "inputSchema": input_schema}


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
