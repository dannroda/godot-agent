extends Node
## El registro de tools del MCP de la app aparte (m20-06): las godot.* del editor abierto en la carpeta.
## Cada llamada se autoriza acá, con el modo y la tarjeta de la pestaña que la hace (el editor no tiene
## cómo), y recién después va al editor con el token que publicó (m20-05), que ningún agente ve.

const McpPublication := preload("../mcp/mcp_publication.gd")

## La carpeta del proyecto: la que el editor tiene abierta.
var project: String = ""
## (caller, info) -> String, con await: "" si la pestaña `caller` la deja correr; si no, el motivo para
## el agente. `info` es lo que describe el editor: {group, title, description, targets}.
var authorize: Callable

## describe contesta enseguida: si no, el editor está colgado y el turno no se queda esperando.
const DESCRIBE_TIMEOUT_S := 10.0

var _names: PackedStringArray = []


func list() -> Array:
	var reply := await _post({"method": "tools/list", "params": {}})
	var tools: Array = reply.get("result", {}).get("tools", []) if reply.get("result") is Dictionary else []
	_names = PackedStringArray(tools.map(func(tool: Variant) -> String: return str(tool.get("name", "")) if tool is Dictionary else ""))
	return tools


## Sin lista todavía (el editor se abrió después de tools/list), la llamada lo averigua.
func has_tool(tool_name: String) -> bool:
	return _names.is_empty() or tool_name in _names


func call_tool(tool_name: String, args: Variant, caller: String = "") -> Dictionary:
	var arguments: Dictionary = args if args is Dictionary else {}
	var described := await _post({"method": "godot_agent/describe", "params": {"name": tool_name, "arguments": arguments}}, DESCRIBE_TIMEOUT_S)
	if described.has("error"):
		return _error(str(described.error.get("message", "")) if described.error is Dictionary else str(described.error))
	var info: Dictionary = described.get("result", {})
	if info.is_empty():
		return _error("There is no tool '%s' in the editor." % tool_name)
	var refused: String = await authorize.call(caller, info) if authorize.is_valid() else "No tab of the harness can approve this call."
	if not refused.is_empty():
		return _error(refused)
	var reply := await _post({"method": "tools/call", "params": {"name": tool_name, "arguments": arguments}})
	if reply.get("result") is Dictionary:
		return reply.result
	return _error(str(reply.error.get("message", "")) if reply.get("error") is Dictionary else "The editor did not answer.")


## La respuesta JSON-RPC del editor, o {error} si no está abierto o no contestó. Sin plazo por defecto:
## una tool puede tardar con razón (un playtest).
func _post(message: Dictionary, timeout_s: float = 0.0) -> Dictionary:
	var editor := McpPublication.read(project)
	if editor.is_empty():
		return {"error": {"message": "The Godot editor is no longer open on this project: its godot.* tools are not available. Use your own tools, or ask the user to open the editor."}}
	var request := HTTPRequest.new()
	request.timeout = timeout_s
	add_child(request)
	message["jsonrpc"] = "2.0"
	message["id"] = 1
	request.request(editor.url, ["Content-Type: application/json", "Accept: application/json", "Authorization: Bearer " + editor.token], HTTPClient.METHOD_POST, JSON.stringify(message))
	var response: Array = await request.request_completed
	request.queue_free()
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8()) if response[0] == HTTPRequest.RESULT_SUCCESS else null
	if parsed is Dictionary:
		return parsed
	if response[0] == HTTPRequest.RESULT_TIMEOUT:
		return {"error": {"message": "The Godot editor did not answer in %d s: it may be busy or frozen. Try again later, or ask the user to check the editor." % timeout_s}}
	return {"error": {"message": "The editor did not answer (HTTP %d)." % response[1]}}


static func _error(text: String) -> Dictionary:
	return {"content": [{"type": "text", "text": text}], "isError": true}
