extends SceneTree
## Prueba m7-31 (manual, gasta tokens): habla con Claude Code en stream-json desde GDScript, sin
## claude-agent-acp ni Node. Levanta el server MCP del addon con las tools de lectura y una tool
## `permission` propia de la prueba, lanza `claude -p --input-format stream-json --output-format
## stream-json …` con AgentProcess y recorre lo que el adapter hace hoy: initialize, una tool
## godot.*, una tool de Claude que pide permiso (por el protocolo de control, `can_use_tool`),
## cambio de modelo y de modo, una imagen, cancelar a mitad de turno y `--resume` en un proceso
## nuevo con el permiso por una tool MCP (`--permission-prompt-tool mcp__godot__permission`).
## Cada línea que llega queda en tests/tmp/stream_json_probe/events.jsonl y al final se imprime un
## resumen por tipo de evento. Decisión: D62 en docs/decisions.md. Uso:
##   godot --headless --path <repo> --script tests/stream_json_probe.gd [-- <modelo>]

const TestUserDir := preload("res://tests/test_user_dir.gd")
const McpServer := preload("res://addons/godot_agent/mcp/mcp_server.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const ReadTools := preload("res://addons/godot_agent/mcp/tools/read_tools.gd")
const AgentProcess := preload("res://addons/godot_agent/transport/agent_process.gd")

const TIMEOUT_S := 600.0
const TURN_TIMEOUT_S := 180.0
const OUT_DIR := "res://tests/tmp/stream_json_probe"
## PNG de 8x8 rojo, armado en _ready_image().
var _png_base64: String = ""

var _server: McpServer
var _proc: AgentProcess
var _events: Array[Dictionary] = []
var _counts: Dictionary = {}  # clave del evento -> cantidad
var _samples: Dictionary = {}  # clave del evento -> primera línea (recortada)
var _log: FileAccess
var _run: String = ""
var _next_request: int = 0
var _permission_log: Array[String] = []
var _notes: Array[String] = []
var _stderr: Array[String] = []


func _initialize() -> void:
	TestUserDir.apply()
	await process_frame
	create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		printerr("FAIL stream_json_probe: timeout")
		_finish(1)
	)
	var args := OS.get_cmdline_user_args()
	var model: String = args[0] if not args.is_empty() else "haiku"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open(OUT_DIR + "/events.jsonl", FileAccess.WRITE)
	var sandbox := OS.get_user_data_dir() + "/stream_json_probe_sandbox"
	DirAccess.make_dir_recursive_absolute(sandbox)
	DirAccess.remove_absolute(sandbox + "/probe.txt")
	_png_base64 = _red_png()
	_start_mcp()

	var version := []
	OS.execute("claude", ["--version"], version)
	_note("claude --version: %s" % str(version[0]).strip_edges())

	# --- Run A: permisos por el protocolo de control (lo que usa el Agent SDK) ---
	_run = "A"
	if not _launch(sandbox, model, ["--permission-prompt-tool", "stdio"]):
		_finish(1)
		return
	var init: Dictionary = await _control({"subtype": "initialize", "hooks": null})
	_note("initialize: keys=%s" % str((init.get("response", {}) as Dictionary).keys()))
	var info: Dictionary = init.get("response", {})
	_note("  models: %s" % ", ".join((info.get("models", []) as Array).map(func(m: Variant) -> String: return str((m as Dictionary).get("value", m)) if m is Dictionary else str(m))))
	_note("  commands: %d (%s…)" % [(info.get("commands", []) as Array).size(), ", ".join((info.get("commands", []) as Array).slice(0, 8).map(func(c: Variant) -> String: return str((c as Dictionary).get("name", c)) if c is Dictionary else str(c)))])
	_note("  account: %s" % JSON.stringify(_redact(info.get("account", {}))))
	for key: String in ["current_permission_mode", "capabilities", "session_state", "remote_control_available", "remote_control_auto_enable", "fast_mode_state"]:
		_note("  %s: %s" % [key, JSON.stringify(info.get(key)).left(300)])

	var t1: Dictionary = await _turn("Call the godot project_info tool and reply with only the project name.")
	_note("T1 godot tool: %s · %s" % [t1.get("subtype"), str(t1.get("result", "")).left(80)])
	var t2: Dictionary = await _turn("Use the Write tool to create a file named probe.txt containing the single word hola. Do nothing else.")
	_note("T2 Write con permiso: %s · probe.txt existe: %s" % [t2.get("subtype"), FileAccess.file_exists(sandbox + "/probe.txt")])

	var set_model: Dictionary = await _control({"subtype": "set_model", "model": "sonnet"})
	_note("set_model sonnet: %s" % JSON.stringify(set_model).left(200))
	var set_mode: Dictionary = await _control({"subtype": "set_permission_mode", "mode": "acceptEdits"})
	_note("set_permission_mode acceptEdits: %s" % JSON.stringify(set_mode).left(200))

	var t3: Dictionary = await _turn_content([
		{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": _png_base64}},
		{"type": "text", "text": "What color is this image? Answer with one word."},
	])
	_note("T3 imagen: %s · %s · modelo del turno: %s" % [t3.get("subtype"), str(t3.get("result", "")).left(40), _last_assistant_model()])

	var from := _events.size()
	_send_user([{"type": "text", "text": "Write the numbers from 1 to 300 in words, one per line. No tools."}])
	var delta: Dictionary = await _wait(func(e: Dictionary) -> bool: return e.get("type") == "stream_event" and str((e.get("event", {}) as Dictionary).get("type")) == "content_block_delta", from, TURN_TIMEOUT_S)
	var interrupt_sent_ms := Time.get_ticks_msec()
	var interrupt: Dictionary = await _control({"subtype": "interrupt"})
	var t4: Dictionary = await _wait(func(e: Dictionary) -> bool: return e.get("type") == "result", from, TURN_TIMEOUT_S)
	_note("T4 interrupt (primer delta: %s): %s · result %s en %d ms · is_error=%s" % [not delta.is_empty(), JSON.stringify(interrupt).left(120), t4.get("subtype"), Time.get_ticks_msec() - interrupt_sent_ms, t4.get("is_error")])
	var t5: Dictionary = await _turn("Reply with the single word: ok")
	_note("T5 sigue la sesión después de interrumpir: %s · %s" % [t5.get("subtype"), str(t5.get("result", "")).left(40)])
	var t_slash: Dictionary = await _turn("/context")
	_note("T/ comando /context: %s · %s" % [t_slash.get("subtype"), str(t_slash.get("result", "")).left(160).replace("\n", " ")])
	var sub_from := _events.size()
	var t_sub: Dictionary = await _turn("Use the Task tool to launch one general-purpose subagent whose only job is to reply with the words sub ok. Then tell me what it said.")
	var sub_events := _events.slice(sub_from).filter(func(e: Dictionary) -> bool: return e.get("parent_tool_use_id") != null)
	_note("T7 subagente: %s · eventos con parent_tool_use_id: %d · %s" % [t_sub.get("subtype"), sub_events.size(), ", ".join(sub_events.map(func(e: Dictionary) -> String: return _key(e)).slice(0, 6))])
	var session_id := str(t1.get("session_id", ""))
	_proc.stop()
	await create_timer(0.5).timeout

	# --- Run B: --resume en un proceso nuevo, permisos por una tool MCP ---
	_run = "B"
	if not _launch(sandbox, model, ["--resume", session_id, "--permission-prompt-tool", "mcp__godot__permission"]):
		_finish(1)
		return
	var t6: Dictionary = await _turn("Use the Edit tool to replace hola with chau in probe.txt. Then tell me which word the file had before, from your memory of this conversation.")
	var content := FileAccess.get_file_as_string(sandbox + "/probe.txt")
	_note("T6 resume + permiso por MCP: %s · session_id igual: %s · probe.txt=%s · %s" % [t6.get("subtype"), str(t6.get("session_id")) == session_id, content.strip_edges(), str(t6.get("result", "")).left(120)])
	_proc.stop()

	_report()
	_finish(0)


func _start_mcp() -> void:
	var registry := ToolRegistry.new()
	registry.register_provider(ReadTools.new())
	# Tool de permisos para --permission-prompt-tool: Claude manda {tool_name, input, tool_use_id}
	# y espera un texto con {"behavior": "allow", "updatedInput": …} o {"behavior": "deny", "message": …}.
	registry.register(McpTool.create("permission", "read", "Permission prompt for Claude Code tools (stream-json probe).",
		{"tool_name": {"type": "string"}, "input": {"type": "object"}, "tool_use_id": {"type": "string"}}, ["tool_name", "input"],
		func(args: Dictionary) -> String:
			_permission_log.append("[%s] mcp permission: %s %s" % [_run, args.get("tool_name"), JSON.stringify(args.get("input", {})).left(120)])
			return JSON.stringify({"behavior": "allow", "updatedInput": args.get("input", {})})))
	_server = McpServer.new()
	_server.registry = registry
	root.add_child(_server)
	_server.start(0)


func _launch(sandbox: String, model: String, extra: PackedStringArray) -> bool:
	var mcp := {"mcpServers": {"godot": {"type": "http", "url": _server.url(), "headers": {"Authorization": "Bearer " + _server.token}}}}
	var args: PackedStringArray = [
		"-c", "cd \"$0\" && exec claude \"$@\"", sandbox,
		"-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
		"--include-partial-messages", "--model", model,
		"--mcp-config", JSON.stringify(mcp), "--strict-mcp-config",
		"--setting-sources", "project",
		"--allowedTools", "mcp__godot__project_info", "--forward-subagent-text",
	]
	args.append_array(extra)
	_proc = AgentProcess.new()
	_proc.line_received.connect(_on_line)
	_proc.stderr_received.connect(func(line: String) -> void: _stderr.append("[%s] %s" % [_run, line]))
	if not _proc.start("/bin/sh", args):
		printerr("FAIL no arrancó: ", _proc.last_error())
		return false
	_note("[%s] lanzado: claude %s" % [_run, " ".join(args.slice(3)).replace(_server.token, "<token>")])
	return true


func _on_line(line: String) -> void:
	_log.store_line(line.replace(_server.token, "<token>"))
	var parsed: Variant = JSON.parse_string(line)
	if not parsed is Dictionary:
		_count("(no json)", line)
		return
	var message: Dictionary = parsed
	message["_run"] = _run
	_events.append(message)
	_count(_key(message), line)
	if message.get("type") == "control_request":
		var request: Dictionary = message.get("request", {})
		if request.get("subtype") == "can_use_tool":
			_permission_log.append("[%s] can_use_tool: %s %s" % [_run, request.get("tool_name"), JSON.stringify(request.get("input", {})).left(120)])
			_proc.send_line(JSON.stringify({"type": "control_response", "response": {
				"subtype": "success", "request_id": message.get("request_id"),
				"response": {"behavior": "allow", "updatedInput": request.get("input", {})},
			}}))


func _key(message: Dictionary) -> String:
	var type := str(message.get("type", "?"))
	match type:
		"stream_event":
			var event: Dictionary = message.get("event", {})
			var key := "stream_event/" + str(event.get("type"))
			if event.has("delta"):
				key += "/" + str((event.delta as Dictionary).get("type"))
			elif event.has("content_block"):
				key += "/" + str((event.content_block as Dictionary).get("type"))
			return key
		"assistant", "user":
			var content: Variant = (message.get("message", {}) as Dictionary).get("content", [])
			if content is String:
				return "%s/string%s" % [type, "/replay" if message.get("isReplay", false) else ""]
			var blocks: Array = content
			var kinds: PackedStringArray = []
			for block: Variant in blocks:
				if block is Dictionary and not str(block.get("type")) in kinds:
					kinds.append(str(block.get("type")))
			return "%s/%s" % [type, ",".join(kinds)]
		"control_request":
			return "control_request/" + str((message.get("request", {}) as Dictionary).get("subtype"))
		"control_response":
			return "control_response/" + str((message.get("response", {}) as Dictionary).get("subtype"))
	return type + ("/" + str(message.subtype) if message.has("subtype") else "")


func _count(key: String, line: String) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1
	if not _samples.has(key):
		_samples[key] = line.replace(_server.token, "<token>").left(400)


func _send_user(content: Array) -> void:
	_proc.send_line(JSON.stringify({"type": "user", "message": {"role": "user", "content": content}, "parent_tool_use_id": null, "session_id": ""}))


func _turn(text: String) -> Dictionary:
	return await _turn_content([{"type": "text", "text": text}])


func _turn_content(content: Array) -> Dictionary:
	var from := _events.size()
	_send_user(content)
	return await _wait(func(e: Dictionary) -> bool: return e.get("type") == "result", from, TURN_TIMEOUT_S)


## Manda un control_request y espera su control_response (devuelve el `response` o {}).
func _control(request: Dictionary) -> Dictionary:
	_next_request += 1
	var request_id := "probe_%d" % _next_request
	var from := _events.size()
	_proc.send_line(JSON.stringify({"type": "control_request", "request_id": request_id, "request": request}))
	var reply: Dictionary = await _wait(func(e: Dictionary) -> bool:
		return e.get("type") == "control_response" and str((e.get("response", {}) as Dictionary).get("request_id")) == request_id, from, 30.0)
	return reply.get("response", {"subtype": "timeout"})


func _wait(predicate: Callable, from: int, timeout_s: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	var index := from
	while Time.get_ticks_msec() < deadline:
		while index < _events.size():
			if predicate.call(_events[index]):
				return _events[index]
			index += 1
		if not _proc.is_running():
			_note("[%s] el proceso terminó esperando" % _run)
			return {}
		await process_frame
	_note("[%s] timeout esperando" % _run)
	return {}


func _last_assistant_model() -> String:
	for i in range(_events.size() - 1, -1, -1):
		if _events[i].get("type") == "assistant":
			return str((_events[i].get("message", {}) as Dictionary).get("model", "?"))
	return "?"


func _redact(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = "<redacted>" if str(key).to_lower().contains("email") or str(key).to_lower().contains("org") else _redact(value[key])
		return out
	return value


func _red_png() -> String:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	return Marshalls.raw_to_base64(image.save_png_to_buffer())


func _note(text: String) -> void:
	_notes.append(text)
	print(text)


func _report() -> void:
	print("\n== permisos ==")
	for line: String in _permission_log:
		print("  ", line)
	print("\n== eventos por tipo ==")
	var keys := _counts.keys()
	keys.sort()
	for key: String in keys:
		print("  %4d  %s" % [_counts[key], key])
	print("\n== primera línea de cada tipo ==")
	for key: String in keys:
		print("  ", key, "\n      ", _samples[key])
	var results := _events.filter(func(e: Dictionary) -> bool: return e.get("type") == "result")
	if not results.is_empty():
		var last: Dictionary = results.back()
		print("\n== último result ==\n  usage: %s\n  modelUsage: %s\n  cost: %s" % [JSON.stringify(last.get("usage")), JSON.stringify(last.get("modelUsage")).left(400), last.get("total_cost_usd")])
	if not _stderr.is_empty():
		print("\n== stderr ==")
		for line: String in _stderr.slice(0, 20):
			print("  ", line.left(200))
	print("\nlog: ", ProjectSettings.globalize_path(OUT_DIR + "/events.jsonl"))


func _finish(code: int) -> void:
	if _proc:
		_proc.stop()
	if _log:
		_log.close()
	if _server:
		_server.stop()
	quit(code)
