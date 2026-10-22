@tool
extends RefCounted
## Verificación de M3 dentro del editor: llama a cada tool godot.* por HTTP real contra el server
## del plugin, con la escena de prueba tests/fixtures/main_fixture.tscn abierta, y prueba el shim
## stdio. Devuelve la lista de fallas (vacía si todo anduvo).

const AgentProcess := preload("res://addons/godot_agent/transport/agent_process.gd")
const StdioShimInstaller := preload("res://addons/godot_agent/mcp/stdio_shim_installer.gd")
const SERVER_SCRIPT := "res://addons/godot_agent/mcp/mcp_server.gd"
const FIXTURE_SCENE := "res://tests/fixtures/main_fixture.tscn"
const BAD_SCRIPT := "res://tests/tmp/mcp_bad_script.gd"
const GOOD_SCRIPT := "res://tests/fixtures/fixture_player.gd"
const TIMEOUT_MS := 90000

var failures: PackedStringArray = []
var _tree: SceneTree
var _server: Node
var _session_id: String = ""
var _next_id: int = 1


func run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == SERVER_SCRIPT:
			_server = node
	if _server == null or not _server.call(&"is_listening"):
		failures.append("el server MCP no está escuchando")
		return failures
	print("[mcp-check] server en ", _server.call(&"url"))
	EditorInterface.open_scene_from_path(FIXTURE_SCENE)
	await tree.create_timer(1.0).timeout
	var root := EditorInterface.get_edited_scene_root()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(root.get_node("Player"))
	var file := FileAccess.open(BAD_SCRIPT, FileAccess.WRITE)
	file.store_string("extends Node\n\nfunc _ready() -> void:\n\tprint(undefined_thing)\n")
	file.close()

	var init: Dictionary = await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "mcp-check", "version": "1"}})
	_expect(init.has("result"), "initialize")
	var list: Dictionary = await _rpc("tools/list", {})
	var names: PackedStringArray = []
	for tool: Dictionary in list.get("result", {}).get("tools", []):
		names.append(tool.name)
	print("[mcp-check] tools: ", ", ".join(names))
	for expected: String in ["project_info", "list_files", "scene_tree", "get_node", "editor_state", "get_errors", "validate_scripts", "capture_editor_viewport"]:
		_expect(expected in names, "tools/list incluye %s" % expected)

	var info := await _call_text("project_info", {})
	_expect(info.contains("Godot 4.") and info.contains("Autoloads"), "project_info")
	var files := await _call_text("list_files", {"path": "res://tests/fixtures", "pattern": "*.tscn"})
	_expect(files.contains("main_fixture.tscn  (PackedScene)") and not files.contains(".gd"), "list_files con pattern")
	var tree_text := await _call_text("scene_tree", {})
	print("[mcp-check] scene_tree:\n", tree_text)
	_expect(tree_text.contains("5 nodos"), "scene_tree cuenta 5 nodos")
	_expect(tree_text.contains("Player (CharacterBody2D)") and tree_text.contains("speed=300") and tree_text.contains("grupos=[player]"), "scene_tree: tipo, propiedad exportada y grupo")
	_expect(tree_text.contains("position=Vector2(100, 50)"), "scene_tree: propiedad no default")
	_expect(not tree_text.contains("wait_time=1"), "scene_tree: sin defaults")
	var shallow := await _call_text("scene_tree", {"scene": FIXTURE_SCENE, "depth": 0})
	_expect(shallow.contains("se muestran 1"), "scene_tree con depth 0")
	var node := await _call_text("get_node", {"node_path": "Timer"})
	_expect(node.contains("timeout → Player::_on_timer_timeout") and node.contains("wait_time = 2"), "get_node: conexión y propiedades")
	var missing: Dictionary = await _call("get_node", {"node_path": "Nope"})
	_expect(missing.get("isError", false) and _text(missing).contains("Player"), "get_node inexistente: error con sugerencias")
	var state := await _call_text("editor_state", {})
	_expect(state.contains("main_fixture.tscn") and state.contains("Player (CharacterBody2D)"), "editor_state: escena y selección")

	var marker := "mcp-check-marker-%d" % Time.get_ticks_msec()
	var before := await _call_text("get_errors", {})
	var mark := int(before.get_slice("marca: ", 1).get_slice(" ", 0))
	push_error(marker)
	await _tree.create_timer(0.3).timeout  # margen para que el Logger reciba el error
	var errors := await _call_text("get_errors", {"since": mark})
	var again := await _call_text("get_errors", {"since": int(errors.get_slice("marca: ", 1).get_slice(" ", 0))})
	_expect(not again.contains(marker), "get_errors no repite lo anterior a la marca")
	var validation := await _call_text("validate_scripts", {"paths": [BAD_SCRIPT, GOOD_SCRIPT]})
	print("[mcp-check] validate_scripts:\n", validation)
	_expect(validation.contains("1 con errores") and validation.contains("línea 4") and validation.contains("undefined_thing"), "validate_scripts")
	var capture: Dictionary = await _call("capture_editor_viewport", {"which": "2d"})
	var has_image := false
	for block: Dictionary in capture.get("content", []):
		has_image = has_image or block.get("type") == "image"
	_expect(has_image and not capture.get("isError", true), "capture_editor_viewport 2d")
	var bad_args: Dictionary = await _call("capture_editor_viewport", {"which": "4d"})
	_expect(bad_args.get("isError", false), "enum inválido → isError")

	await _check_shim()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD_SCRIPT))
	return failures


## Shim stdio: initialize + tools/call por stdin, respuestas por stdout.
func _check_shim() -> void:
	var entry := StdioShimInstaller.server_entry("godot", _server.call(&"url"), _server.get(&"token"))
	if entry.is_empty():
		failures.append("shim: no se pudo instalar")
		return
	var env: Dictionary = {}
	for item: Dictionary in entry.env:
		env[item.name] = item.value
	var process := AgentProcess.new()
	var lines: Array[String] = []
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.stderr_received.connect(func(line: String) -> void: print("[mcp-check] shim stderr: ", line))
	if not process.start(entry.command, PackedStringArray(entry.args), env):
		failures.append("shim: no arrancó: %s" % process.last_error())
		return
	process.send_line(JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "shim-check", "version": "1"}}}))
	process.send_line(JSON.stringify({"jsonrpc": "2.0", "method": "notifications/initialized"}))
	process.send_line(JSON.stringify({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "editor_state", "arguments": {}}}))
	var deadline := Time.get_ticks_msec() + 20000
	while lines.size() < 2 and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	process.stop()
	_expect(lines.size() == 2, "shim: dos respuestas (la notificación no responde): %d" % lines.size())
	if lines.size() == 2:
		var first: Variant = JSON.parse_string(lines[0])
		var second: Variant = JSON.parse_string(lines[1])
		_expect(first is Dictionary and first.get("id") == 1.0 and first.has("result"), "shim: initialize")
		_expect(second is Dictionary and str(second).contains("main_fixture.tscn"), "shim: tools/call")


func _call(tool_name: String, arguments: Dictionary) -> Dictionary:
	var reply: Dictionary = await _rpc("tools/call", {"name": tool_name, "arguments": arguments})
	if not reply.has("result"):
		failures.append("%s: sin result (%s)" % [tool_name, str(reply).left(200)])
		return {}
	return reply.result


func _call_text(tool_name: String, arguments: Dictionary) -> String:
	var result: Dictionary = await _call(tool_name, arguments)
	if result.get("isError", false):
		failures.append("%s devolvió error: %s" % [tool_name, _text(result)])
	return _text(result)


static func _text(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for block: Dictionary in result.get("content", []):
		if block.get("type") == "text":
			parts.append(str(block.text))
	return "\n".join(parts)


func _rpc(method: String, params: Dictionary) -> Dictionary:
	var body := JSON.stringify({"jsonrpc": "2.0", "id": _next_id, "method": method, "params": params})
	_next_id += 1
	var headers: PackedStringArray = ["Content-Type: application/json", "Authorization: Bearer " + str(_server.get(&"token"))]
	if not _session_id.is_empty():
		headers.append("Mcp-Session-Id: " + _session_id)
	var client := HTTPClient.new()
	client.connect_to_host("127.0.0.1", int(_server.call(&"port")))
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		client.poll()
		await _tree.process_frame
	client.request(HTTPClient.METHOD_POST, "/mcp", headers, body)
	while client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		client.poll()
		await _tree.process_frame
	var data := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
		client.poll()
		data.append_array(client.read_response_body_chunk())
		await _tree.process_frame
	var response_headers := client.get_response_headers_as_dictionary()
	for key: String in response_headers:
		if key.to_lower() == "mcp-session-id":
			_session_id = str(response_headers[key])
	client.close()
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
