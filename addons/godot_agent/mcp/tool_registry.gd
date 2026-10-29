@tool
extends RefCounted
## Registro de tools `godot.*` (spec §5–6): lista, valida argumentos, aplica la política de
## permisos del lado del server, ejecuta, recorta la salida y lo deja todo en el log (canal mcp).
## Con `compact` (m3-09, D56), tools/list trae solo el núcleo tipado; las demás ("extendidas") se
## descubren con `godot.methods` y se llaman con `godot.run(method, params)`, con su validación y
## su permiso. Llamarlas por su nombre sigue funcionando.

const McpTool := preload("mcp_tool.gd")
const AgentLog := preload("../core/agent_log.gd")
const EditorContext := preload("../ui/editor_context.gd")

const LOG_SUMMARY_CHARS := 120
## Tools que ya traen en su resultado los errores nuevos: solo avanzan la marca (m14-02).
const REPORTS_ERRORS: PackedStringArray = ["get_errors", "validate_scripts", "run_scene", "game_tree", "game_get", "game_set", "game_call", "game_wait", "game_input"]
## Errores que se listan en el aviso; los demás se cuentan.
const NEW_ERRORS_SHOWN := 5
const METHODS_TOOL := "methods"
const RUN_TOOL := "run"

var agent_log: AgentLog
## Callable(group: String, title: String, description: String) -> bool (se espera con await).
## Sin authorizer se permite todo (tests).
var authorizer: Callable
## Con varias sesiones abiertas (m7-44): `(caller, group, title, description) -> bool` con la sesión
## que llama ("" la primera). Si es válido, reemplaza a `authorizer`.
var session_authorizer: Callable
## `(caller, tool_name, args) -> String`: "" deja correr la tool; si no, el motivo por el que otra
## sesión la impide (edita ese archivo, tiene el juego). Puede esperar (la cola del juego).
var guard: Callable
## `(caller, tool_name) -> String`: un rechazo que no depende del usuario (una sesión en una copia
## aparte no puede usar las tools que editan el editor, m11-09). Corre antes de pedir permiso, para
## no mostrar una tarjeta que igual se rechazaría.
var precheck: Callable
## La sesión que llama a la tool en curso, para los handlers que la necesitan (godot.sessions):
## vale al empezar el handler, antes de su primer await.
var current_caller: String = ""
var max_output_chars: int = 20000
var max_image_side: int = 1280
## tools/list solo con el núcleo, más `methods` y `run` para las extendidas.
var compact: bool = false
## Errores nuevos en cada respuesta (m14-02): `() -> int`, la marca actual del ErrorCollector, y
## `(since: int) -> Array[Dictionary]`, sus entradas desde ahí. Sin asignar, no se avisa.
var error_mark: Callable
var errors_since: Callable
var _error_marks: Dictionary = {}  # caller -> marca de la última respuesta

var _tools: Dictionary = {}  # name -> McpTool
var _order: PackedStringArray = []
## Objetos dueños de los handlers: un Callable no mantiene vivo a su RefCounted.
var _providers: Array = []
var _extended: Dictionary = {}  # name -> true


func register(tool: McpTool) -> void:
	if not _tools.has(tool.name):
		_order.append(tool.name)
	_tools[tool.name] = tool


## Registra las tools de un proveedor (objeto con `tools() -> Array`) y lo mantiene vivo.
## `extended`: sus tools no van en tools/list con `compact`.
func register_provider(provider: Object, extended: bool = false) -> void:
	if not provider in _providers:
		_providers.append(provider)
	for tool: McpTool in provider.call(&"tools"):
		register(tool)
		if extended:
			_extended[tool.name] = true


## Tools sueltas que pasan a extendidas (las de un proveedor que es núcleo en parte).
func mark_extended(tool_names: PackedStringArray) -> void:
	for tool_name: String in tool_names:
		_extended[tool_name] = true


func is_extended(tool_name: String) -> bool:
	return _extended.has(tool_name)


func has_tool(tool_name: String) -> bool:
	return _tools.has(tool_name) or (tool_name in [METHODS_TOOL, RUN_TOOL] and not _extended.is_empty())


func get_tool(tool_name: String) -> McpTool:
	return _tools.get(tool_name)


func names() -> PackedStringArray:
	return _order


## Resultado de tools/list.
func list() -> Array:
	var result: Array = []
	for tool_name: String in _order:
		if not (compact and _extended.has(tool_name)):
			result.append((_tools[tool_name] as McpTool).to_mcp())
	if compact and not _extended.is_empty():
		result.append(_methods_tool().to_mcp())
		result.append(_run_tool().to_mcp())
	return result


## Grupo de permisos de una tool, o "" si no existe.
func group_of(tool_name: String) -> String:
	var tool: McpTool = _tools.get(tool_name)
	return tool.group if tool else ""


## Corre una tool para lo que pide el usuario desde la UI (las menciones @errors, @game… del
## composer, m11-08): sin permiso ni guard, porque no la llama el agente. Devuelve el texto del
## resultado (con el tope de max_output_chars) o "" si no existe.
func run_for_user(tool_name: String, args: Dictionary) -> String:
	var tool: McpTool = _tools.get(tool_name)
	if tool == null or not tool.handler.is_valid():
		return ""
	var result := _limit(_normalize(await tool.handler.call(args)))
	var texts: PackedStringArray = []
	for block: Variant in result.content:
		if block is Dictionary and block.get("type") == "text":
			texts.append(str(block.text))
	return "\n".join(texts)


## Ejecuta una tool y devuelve siempre un resultado MCP `{content, isError}`.
func call_tool(tool_name: String, args: Variant, caller: String = "") -> Dictionary:
	var started := Time.get_ticks_msec()
	var result: Dictionary
	var error_mark_before: int = _error_marks.get(caller, error_mark.call()) if error_mark.is_valid() else -1
	if tool_name == METHODS_TOOL and not _tools.has(METHODS_TOOL):
		result = _limit(_methods(args if args is Dictionary else {}))
		_log_call(tool_name, args, result, Time.get_ticks_msec() - started)
		return result
	if tool_name == RUN_TOOL and not _tools.has(RUN_TOOL):
		var invalid_run := _run_tool().validate(args if args is Dictionary else {})
		if not invalid_run.is_empty() or not args is Dictionary:
			result = McpTool.error(invalid_run if not invalid_run.is_empty() else "The arguments must be a JSON object.")
			_log_call(tool_name, args, result, Time.get_ticks_msec() - started)
			return result
		if not _tools.has(str(args.method)):
			result = McpTool.error("There is no method '%s'. godot.methods lists them." % args.method)
			_log_call(tool_name, args, result, Time.get_ticks_msec() - started)
			return result
		tool_name = str(args.method)
		args = args.get("params", {}) if args.get("params") != null else {}
	var tool: McpTool = _tools.get(tool_name)
	if tool == null:
		result = McpTool.error("There is no tool '%s'. Available: %s." % [tool_name, ", ".join(_order)])
	elif not (args is Dictionary or args == null):
		result = McpTool.error("The arguments must be a JSON object.")
	else:
		var arguments: Dictionary = args if args is Dictionary else {}
		var invalid := tool.validate(arguments)
		if not invalid.is_empty():
			result = McpTool.error(invalid)
		elif not tool.handler.is_valid():
			result = McpTool.error("The tool godot.%s is not available (the addon was reloaded). Retry in a moment." % tool.name)
		elif precheck.is_valid() and not str(precheck.call(caller, tool.name)).is_empty():
			result = McpTool.error(str(precheck.call(caller, tool.name)))
		elif not await _authorize(tool, arguments, caller):
			result = McpTool.error(
				"Permission denied for godot.%s (group %s) by the current mode or by the user. Do not retry: explain what you wanted to do and ask the user to change the mode if needed." % [tool.name, tool.group_of(arguments)]
			)
		else:
			var blocked: String = await guard.call(caller, tool.name, arguments) if guard.is_valid() else ""
			if blocked.is_empty():
				current_caller = caller
				result = _normalize(await tool.handler.call(arguments))
			else:
				result = McpTool.error(blocked)
	if error_mark.is_valid():
		if not tool_name in REPORTS_ERRORS:
			result = _with_new_errors(result, errors_since.call(error_mark_before))
		_error_marks[caller] = error_mark.call()
	result = _limit(result)
	_log_call(tool_name, args, result, Time.get_ticks_msec() - started)
	return result


## El aviso de errores y warnings que aparecieron desde la respuesta anterior a esta sesión: así el
## agente se entera en la misma tool, sin esperar al fin del turno ni llamar a get_errors.
static func _with_new_errors(result: Dictionary, entries: Array) -> Dictionary:
	var found := entries.filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "error")
	var warnings := entries.filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "warning").size()
	if found.is_empty() and warnings == 0:
		return result
	var counts: PackedStringArray = []
	if not found.is_empty():
		counts.append("%d error%s" % [found.size(), "" if found.size() == 1 else "s"])
	if warnings > 0:
		counts.append("%d warning%s" % [warnings, "" if warnings == 1 else "s"])
	var lines: PackedStringArray = ["New in the editor since your previous godot.* call: %s (get_errors shows all of them):" % ", ".join(counts)]
	for entry: Dictionary in found.slice(0, NEW_ERRORS_SHOWN):
		var file := str(entry.get("file", ""))
		var location := ("%s:%d" % [file, int(entry.line)] if int(entry.get("line", 0)) > 0 else file) if not file.is_empty() else str(entry.get("source", ""))
		lines.append("- %s — %s" % [location, str(entry.get("message", "")).strip_edges().left(300)])
	if found.size() > NEW_ERRORS_SHOWN:
		lines.append("- … and %d more" % (found.size() - NEW_ERRORS_SHOWN))
	var with_notice := result.duplicate()
	var content: Array = (result.get("content", []) as Array).duplicate()
	content.append({"type": "text", "text": "\n".join(lines)})
	with_notice["content"] = content
	return with_notice


# --- descubrimiento (m3-09) --------------------------------------------------------------------------

func _methods_tool() -> McpTool:
	return McpTool.create(METHODS_TOOL, "read",
		"Lists the extra godot methods that are not in your tool list (tilemaps, animation, resources, moving files, project settings and input actions, Godot API docs, the running game…): one line each. Call them with godot.run. Pass `method` to see its full description and parameters, or `query` to filter.",
		{"method": {"type": "string"}, "query": {"type": "string"}}, [], Callable()) as McpTool


func _run_tool() -> McpTool:
	return McpTool.create(RUN_TOOL, "read",
		"Runs an extra godot method (see godot.methods): `method` is its name and `params` its arguments object. The method's own permissions apply.",
		{"method": {"type": "string"}, "params": {"type": "object"}}, ["method"], Callable()) as McpTool


func _methods(args: Dictionary) -> Dictionary:
	var wanted := str(args.get("method", "")) if args.get("method") != null else ""
	if not wanted.is_empty():
		var tool: McpTool = _tools.get(wanted)
		if tool == null:
			return McpTool.error("There is no method '%s'. godot.methods without arguments lists them." % wanted)
		var lines: PackedStringArray = ["%s (permission group %s)" % [tool.name, tool.group], tool.description, "Parameters (JSON schema):", JSON.stringify(tool.input_schema)]
		lines.append("Call: godot.run with {\"method\": \"%s\", \"params\": {…}}." % tool.name)
		return McpTool.text("\n".join(lines))
	var query := (str(args.get("query", "")) if args.get("query") != null else "").to_lower()
	var lines: PackedStringArray = []
	for tool_name: String in _order:
		if not _extended.has(tool_name):
			continue
		var tool: McpTool = _tools[tool_name]
		if not query.is_empty() and not tool_name.contains(query) and not tool.description.to_lower().contains(query):
			continue
		var params: PackedStringArray = []
		var required: Array = tool.input_schema.get("required", [])
		for param: String in (tool.input_schema.get("properties", {}) as Dictionary):
			params.append(param if param in required else param + "?")
		lines.append("- %s(%s): %s" % [tool_name, ", ".join(params), _first_sentence(tool.description)])
	if lines.is_empty():
		return McpTool.text("No method matches '%s'." % query)
	lines.insert(0, "Extra methods (call with godot.run {method, params}; godot.methods {method} shows the details):")
	return McpTool.text("\n".join(lines))


static func _first_sentence(text: String) -> String:
	var end := text.find(". ")
	return text.left(end + 1) if end >= 0 else text


func _authorize(tool: McpTool, args: Dictionary, caller: String = "") -> bool:
	var allowed: Variant = true
	var group := tool.group_of(args)
	if session_authorizer.is_valid():
		allowed = await session_authorizer.call(caller, group, "godot.%s" % tool.name, tool.describe(args))
	elif authorizer.is_valid():
		allowed = await authorizer.call(group, "godot.%s" % tool.name, tool.describe(args))
	return allowed == true


## Lo que devolvió el handler → resultado MCP. null (error de script en el handler) → error.
func _normalize(value: Variant) -> Dictionary:
	if value is Dictionary and value.get("content") is Array:
		var result: Dictionary = value
		if not result.has("isError"):
			result["isError"] = false
		return result
	if value is String:
		return McpTool.text(value)
	if value is Image:
		return McpTool.image(value)
	return McpTool.error("The tool failed without a result (internal harness error). Check the editor's Output panel.")


## Recorta el texto total a `max_output_chars` y reescala imágenes a `max_image_side`.
func _limit(result: Dictionary) -> Dictionary:
	var remaining := max_output_chars
	var content: Array = []
	for block: Variant in result.get("content", []):
		if not block is Dictionary:
			continue
		var item: Dictionary = block
		match str(item.get("type", "")):
			"text":
				var text := str(item.get("text", ""))
				if text.length() > remaining:
					var cut := maxi(remaining, 0)
					text = text.left(cut) + "\n…[output truncated: %d of %d characters. Request less (depth, path, pattern) to see the rest]" % [cut, text.length()]
				remaining -= text.length()
				content.append({"type": "text", "text": text})
			"image":
				content.append(_limit_image(item))
			_:
				content.append(item)
	result["content"] = content
	return result


func _limit_image(block: Dictionary) -> Dictionary:
	var bytes := Marshalls.base64_to_raw(str(block.get("data", "")))
	var image := Image.new()
	if str(block.get("mimeType", "")) != "image/png" or image.load_png_from_buffer(bytes) != OK:
		return block
	if maxi(image.get_width(), image.get_height()) <= max_image_side:
		return block
	image = EditorContext.fit_image(image, max_image_side)
	return {"type": "image", "mimeType": "image/png", "data": Marshalls.raw_to_base64(image.save_png_to_buffer())}


func _log_call(tool_name: String, args: Variant, result: Dictionary, msec: int) -> void:
	if agent_log == null:
		return
	var summary := ""
	var raw_content: Array = []
	for block: Dictionary in result.get("content", []):
		if block.get("type") == "image":
			raw_content.append({"type": "image", "mimeType": block.get("mimeType"), "bytes": str(block.get("data", "")).length() * 3 / 4})
			if summary.is_empty():
				summary = "[image]"
			continue
		raw_content.append(block)
		if block.get("type") == "text" and summary.is_empty():
			summary = str(block.text).replace("\n", " ").left(LOG_SUMMARY_CHARS)
	var status := "error" if result.get("isError", false) else "ok"
	var tool: McpTool = _tools.get(tool_name)
	var call_text := tool.describe(args) if tool and args is Dictionary else ""
	agent_log.add(AgentLog.CH_MCP, "godot.%s(%s) · %d ms · %s: %s" % [tool_name, call_text, msec, status, summary], JSON.stringify({"arguments": args, "isError": result.get("isError", false), "content": raw_content}))
