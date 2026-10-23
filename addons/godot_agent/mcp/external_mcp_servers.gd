@tool
extends RefCounted
## MCP servers de terceros (Blender, Sentry…) que el addon le pasa al agente en `mcpServers` de
## session/new y session/load, junto al suyo (m7-34). Como van por ACP sirven con cualquier
## agente. Un server es un Dictionary:
## `{name, transport: "stdio"|"http", command, args: [], env: {}, url, headers: {}, enabled}`.
## En env, headers y args, `$VAR` o `${VAR}` toman el valor del entorno del editor al abrir la
## sesión: los secretos no se guardan.

const I18n := preload("../core/i18n.gd")

const TRANSPORT_STDIO := "stdio"
const TRANSPORT_HTTP := "http"
const TRANSPORTS: PackedStringArray = [TRANSPORT_STDIO, TRANSPORT_HTTP]
## El nombre del server del addon: las tools llegan como `mcp__godot__*`.
const RESERVED_NAME := "godot"
const TOOL_PREFIX := "mcp__"

static var _variable := RegEx.create_from_string("\\$(?:\\{([A-Za-z_][A-Za-z0-9_]*)\\}|([A-Za-z_][A-Za-z0-9_]*))")
static var _valid_name := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
static var _secret_key := RegEx.create_from_string("(?i)(key|token|secret|password|passwd|authorization|auth)")


static func make(name: String, transport: String = TRANSPORT_STDIO) -> Dictionary:
	return {"name": name, "transport": transport, "command": "", "args": [], "env": {}, "url": "", "headers": {}, "enabled": true}


## Un server guardado (o leído de un archivo), con todos los campos y del tipo esperado.
static func normalize(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	var entry := make(str(source.get("name", "")).strip_edges())
	var transport := str(source.get("transport", TRANSPORT_STDIO))
	entry.transport = transport if transport in TRANSPORTS else TRANSPORT_STDIO
	entry.command = str(source.get("command", "")).strip_edges()
	entry.url = str(source.get("url", "")).strip_edges()
	entry.enabled = bool(source.get("enabled", true))
	if source.get("args") is Array or source.get("args") is PackedStringArray:
		for arg: Variant in source.args:
			entry.args.append(str(arg))
	for field: String in ["env", "headers"]:
		if source.get(field) is Dictionary:
			for key: Variant in source[field]:
				entry[field][str(key)] = str(source[field][key])
	return entry


static func normalize_list(data: Variant) -> Array:
	var result: Array = []
	if data is Array:
		for item: Variant in data:
			var entry := normalize(item)
			if not entry.is_empty():
				result.append(entry)
	return result


## El primer problema de la lista, o "".
static func validate(list: Array) -> String:
	var seen: Dictionary = {}
	for entry: Dictionary in list:
		var name := str(entry.get("name", ""))
		if name.is_empty():
			return I18n.t("MCP: a server has no name.")
		if not _valid_name.search(name):
			return I18n.t("MCP: «%s» can only have letters, digits, - and _.") % name
		if name == RESERVED_NAME:
			return I18n.t("MCP: «godot» is the addon's own server; use another name.")
		if seen.has(name):
			return I18n.t("MCP: two servers are called «%s».") % name
		seen[name] = true
		if entry.get("transport") == TRANSPORT_HTTP:
			var url := str(entry.get("url", ""))
			if not (url.begins_with("http://") or url.begins_with("https://")):
				return I18n.t("MCP: «%s» needs an http:// or https:// URL.") % name
		elif str(entry.get("command", "")).is_empty():
			return I18n.t("MCP: «%s» needs a command.") % name
		for field: String in ["env", "headers"]:
			var values: Dictionary = entry.get(field, {})
			for key: String in values:
				if _secret_key.search(key) and not str(values[key]).is_empty() and not str(values[key]).contains("$"):
					return I18n.t("MCP: «%s» has %s written in. Use $VARIABLE from the environment: the harness doesn't store keys.") % [name, key]
	return ""


## Une la lista del usuario con la del proyecto: si se llaman igual, gana la del proyecto.
static func merge(user_list: Array, project_list: Array) -> Array:
	var by_name: Dictionary = {}
	for entry: Dictionary in user_list:
		by_name[entry.name] = entry
	for entry: Dictionary in project_list:
		by_name[entry.name] = entry
	return by_name.values()


## Entrada `mcpServers` de ACP, o {} si no va (apagado, o http con un agente que no lo soporta).
static func to_acp(entry: Dictionary, supports_http: bool) -> Dictionary:
	if not bool(entry.get("enabled", true)):
		return {}
	if entry.get("transport") == TRANSPORT_HTTP:
		if not supports_http:
			return {}
		return {"type": "http", "name": entry.name, "url": expand(entry.url), "headers": _pairs(entry.headers)}
	var args: Array = []
	for arg: String in entry.args:
		args.append(expand(arg))
	return {"name": entry.name, "command": expand(entry.command), "args": args, "env": _pairs(entry.env)}


## Valores resueltos de env y headers que salieron de una variable: el log los tapa.
static func secret_values(entry: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	for field: String in ["env", "headers"]:
		var values: Dictionary = entry.get(field, {})
		for key: String in values:
			var raw := str(values[key])
			if raw.contains("$"):
				for found: RegExMatch in _variable.search_all(raw):
					var value := OS.get_environment(found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2))
					if value.length() >= 4:
						result.append(value)
	return result


## `$VAR` y `${VAR}` por su valor en el entorno del editor ("" si no está).
static func expand(text: String) -> String:
	if not text.contains("$"):
		return text
	var result := ""
	var last := 0
	for found: RegExMatch in _variable.search_all(text):
		result += text.substr(last, found.get_start() - last)
		result += OS.get_environment(found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2))
		last = found.get_end()
	return result + text.substr(last)


## Servers de un `.mcp.json` (formato de Claude Code y otros: `{"mcpServers": {nombre: {...}}}`).
static func from_mcp_json(text: String) -> Array:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or not (data as Dictionary).get("mcpServers") is Dictionary:
		return []
	var result: Array = []
	var servers: Dictionary = data.mcpServers
	for name: Variant in servers:
		if not servers[name] is Dictionary:
			continue
		var source: Dictionary = servers[name]
		var type := str(source.get("type", ""))
		var entry := normalize({
			"name": str(name),
			"transport": TRANSPORT_HTTP if type in ["http", "sse"] or (type.is_empty() and source.has("url")) else TRANSPORT_STDIO,
			"command": source.get("command", ""),
			"args": source.get("args", []),
			"env": source.get("env", {}),
			"url": source.get("url", ""),
			"headers": source.get("headers", {}),
		})
		result.append(entry)
	return result


## Server de una tool `mcp__<server>__<tool>` que no es del addon, o "".
static func server_of_tool(name: String) -> String:
	if not name.begins_with(TOOL_PREFIX):
		return ""
	var rest := name.trim_prefix(TOOL_PREFIX)
	var separator := rest.find("__")
	if separator <= 0 or separator + 2 >= rest.length():
		return ""
	var server := rest.left(separator)
	return "" if server == RESERVED_NAME else server


## `mcp__blender__get_objects_summary` → `blender.get_objects_summary`; otro nombre queda igual.
static func short_tool_name(name: String) -> String:
	if not name.begins_with(TOOL_PREFIX):
		return name
	var rest := name.trim_prefix(TOOL_PREFIX)
	var separator := rest.find("__")
	if separator <= 0 or separator + 2 >= rest.length():
		return name
	return "%s.%s" % [rest.left(separator), rest.substr(separator + 2)]


## Línea legible para la lista de Settings.
static func describe(entry: Dictionary) -> String:
	if entry.get("transport") == TRANSPORT_HTTP:
		return str(entry.get("url", ""))
	var parts: PackedStringArray = [str(entry.get("command", ""))]
	for arg: Variant in entry.get("args", []):
		parts.append(str(arg))
	return " ".join(parts)


static func _pairs(values: Dictionary) -> Array:
	var result: Array = []
	for key: String in values:
		result.append({"name": key, "value": expand(str(values[key]))})
	return result
