@tool
extends RefCounted
## Registro de tools `godot.*` (spec §5–6): lista, valida argumentos, aplica la política de
## permisos del lado del server, ejecuta, recorta la salida y lo deja todo en el log (canal mcp).

const McpTool := preload("mcp_tool.gd")
const AgentLog := preload("../core/agent_log.gd")
const EditorContext := preload("../ui/editor_context.gd")

const LOG_SUMMARY_CHARS := 120

var agent_log: AgentLog
## Callable(group: String, title: String, description: String) -> bool (se espera con await).
## Sin authorizer se permite todo (tests).
var authorizer: Callable
var max_output_chars: int = 20000
var max_image_side: int = 1280

var _tools: Dictionary = {}  # name -> McpTool
var _order: PackedStringArray = []
## Objetos dueños de los handlers: un Callable no mantiene vivo a su RefCounted.
var _providers: Array = []


func register(tool: McpTool) -> void:
	if not _tools.has(tool.name):
		_order.append(tool.name)
	_tools[tool.name] = tool


## Registra las tools de un proveedor (objeto con `tools() -> Array`) y lo mantiene vivo.
func register_provider(provider: Object) -> void:
	if not provider in _providers:
		_providers.append(provider)
	for tool: McpTool in provider.call(&"tools"):
		register(tool)


func has_tool(tool_name: String) -> bool:
	return _tools.has(tool_name)


func get_tool(tool_name: String) -> McpTool:
	return _tools.get(tool_name)


func names() -> PackedStringArray:
	return _order


## Resultado de tools/list.
func list() -> Array:
	var result: Array = []
	for tool_name: String in _order:
		result.append((_tools[tool_name] as McpTool).to_mcp())
	return result


## Ejecuta una tool y devuelve siempre un resultado MCP `{content, isError}`.
func call_tool(tool_name: String, args: Variant) -> Dictionary:
	var started := Time.get_ticks_msec()
	var tool: McpTool = _tools.get(tool_name)
	var result: Dictionary
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
		elif not await _authorize(tool, arguments):
			result = McpTool.error(
				"Permission denied for godot.%s (group %s) by the current mode or by the user. Do not retry: explain what you wanted to do and ask the user to change the mode if needed." % [tool.name, tool.group]
			)
		else:
			result = _normalize(await tool.handler.call(arguments))
	result = _limit(result)
	_log_call(tool_name, args, result, Time.get_ticks_msec() - started)
	return result


func _authorize(tool: McpTool, args: Dictionary) -> bool:
	if not authorizer.is_valid():
		return true
	var allowed: Variant = await authorizer.call(tool.group, "godot.%s" % tool.name, tool.describe(args))
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
