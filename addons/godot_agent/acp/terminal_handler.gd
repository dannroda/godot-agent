@tool
extends RefCounted
## Terminales del cliente ACP (m11-15): `terminal/create`, `terminal/output`,
## `terminal/wait_for_exit`, `terminal/kill` y `terminal/release`.
## Corre los comandos con AgentProcess en modo raw (sin threads, D35) y pasa por la política del
## modo actual del harness y las guardas de escritura del proyecto y de ventana de Godot.

signal output_changed(terminal_id: String, output: String, exit_code: Variant)
signal terminal_exited(terminal_id: String)

const AcpClient := preload("acp_client.gd")
const AgentLog := preload("../core/agent_log.gd")
const AgentProcess := preload("../transport/agent_process.gd")
const CommandResolver := preload("../transport/command_resolver.gd")

## Tope por defecto de bytes retenidos por terminal si el agente no indica `outputByteLimit`.
const DEFAULT_BYTE_LIMIT := 262144
## Cantidad de salidas ya liberadas que se conservan para mostrarlas en las tarjetas del chat.
const MAX_RELEASED_OUTPUTS := 32

var project_root: String = ""
var extra_roots: PackedStringArray = []
var agent_log: AgentLog
## Callable(command_line: String, working_dir: String) -> String (puede ser async).
## Devuelve "" si se autorizó, o el motivo si se rechazó o denegó.
var command_authorizer: Callable
## Callable() -> Dictionary: variables de entorno base para los comandos (PATH, GODOT, las del perfil…).
var env_provider: Callable

var _client: AcpClient
var _next_id: int = 1
var _terminals: Dictionary = {}  # terminal_id -> Dictionary
var _released_outputs: Dictionary = {}  # terminal_id -> {output, exit_code}
var _released_order: PackedStringArray = []


func setup(root: String, log_sink: AgentLog) -> void:
	project_root = root.simplify_path().trim_suffix("/")
	agent_log = log_sink


func register(client: AcpClient) -> void:
	_client = client
	client.set_request_handler("terminal/create", create_terminal)
	client.set_request_handler("terminal/output", terminal_output)
	client.set_request_handler("terminal/wait_for_exit", wait_for_exit)
	client.set_request_handler("terminal/kill", kill_terminal)
	client.set_request_handler("terminal/release", release_terminal)


func create_terminal(params: Dictionary) -> Variant:
	var acp_id: Variant = _client.handling_id if _client else null
	var command := str(params.get("command", "")).strip_edges()
	if command.is_empty():
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, "Missing 'command'.")
	var args := _to_string_array(params.get("args"))
	var working_dir := str(params.get("cwd", "")).strip_edges() if params.get("cwd") is String else ""
	if working_dir.is_empty():
		working_dir = project_root
	var cwd_check := _check_cwd(working_dir)
	if not cwd_check.is_empty():
		_log("terminal rejected: %s" % cwd_check)
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, cwd_check)
	var command_line := format_command_line(command, args)
	if command_authorizer.is_valid():
		var reason: String = await command_authorizer.call(command_line, working_dir)
		if _client and acp_id != null and _client.is_incoming_cancelled(acp_id):
			return AcpClient.AcpResponse.failure(AcpClient.ERR_REQUEST_CANCELLED, "Request cancelled")
		if not reason.is_empty():
			_log("terminal denied: %s" % reason)
			return AcpClient.AcpResponse.failure(AcpClient.ERR_INTERNAL, reason)
	var byte_limit := DEFAULT_BYTE_LIMIT
	if params.get("outputByteLimit") != null:
		byte_limit = maxi(0, int(params.outputByteLimit))
	var launch := _launch_command(command, args, working_dir)
	var child_env := _build_env(params.get("env"), str(launch[0]))
	var process := AgentProcess.new()
	process.raw_mode = true
	var terminal_id := "term_%d" % _next_id
	_next_id += 1
	var entry := {
		"id": terminal_id,
		"session_id": str(params.get("sessionId", "")),
		"command_line": command_line,
		"process": process,
		"output": PackedByteArray(),
		"byte_limit": byte_limit,
		"truncated": false,
		"exited": false,
		"exit_code": null,
		"exit_signal": null,
		"killed": false,
	}
	process.output_received.connect(_on_output.bind(terminal_id))
	process.exited.connect(_on_exited.bind(terminal_id))
	if not process.start(str(launch[0]), launch[1] as PackedStringArray, child_env):
		var err := process.last_error()
		_log("terminal could not start '%s': %s" % [command_line, err])
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INTERNAL, err)
	_terminals[terminal_id] = entry
	_log("terminal %s started (pid %d): %s" % [terminal_id, process.pid(), command_line])
	return {"terminalId": terminal_id}


func terminal_output(params: Dictionary) -> Variant:
	var terminal_id := str(params.get("terminalId", ""))
	if not _terminals.has(terminal_id):
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, "Unknown terminalId: %s" % terminal_id)
	var entry: Dictionary = _terminals[terminal_id]
	var response: Dictionary = {
		"output": (entry.output as PackedByteArray).get_string_from_utf8(),
		"truncated": bool(entry.truncated),
	}
	if bool(entry.exited):
		response["exitStatus"] = _exit_status(entry)
	return response


func wait_for_exit(params: Dictionary) -> Variant:
	var acp_id: Variant = _client.handling_id if _client else null
	var terminal_id := str(params.get("terminalId", ""))
	if not _terminals.has(terminal_id):
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, "Unknown terminalId: %s" % terminal_id)
	var entry: Dictionary = _terminals[terminal_id]
	var tree := Engine.get_main_loop() as SceneTree
	while not bool(entry.exited) and _terminals.has(terminal_id):
		if _client and acp_id != null and _client.is_incoming_cancelled(acp_id):
			return AcpClient.AcpResponse.failure(AcpClient.ERR_REQUEST_CANCELLED, "Request cancelled")
		if tree == null:
			break
		await tree.process_frame
	if _client and acp_id != null and _client.is_incoming_cancelled(acp_id):
		return AcpClient.AcpResponse.failure(AcpClient.ERR_REQUEST_CANCELLED, "Request cancelled")
	return _exit_status(entry)


func kill_terminal(params: Dictionary) -> Variant:
	var terminal_id := str(params.get("terminalId", ""))
	if not _terminals.has(terminal_id):
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, "Unknown terminalId: %s" % terminal_id)
	var entry: Dictionary = _terminals[terminal_id]
	_terminate_entry(entry)
	_log("terminal %s killed" % terminal_id)
	return {}


func release_terminal(params: Dictionary) -> Variant:
	var terminal_id := str(params.get("terminalId", ""))
	if not _terminals.has(terminal_id):
		return {}
	var entry: Dictionary = _terminals[terminal_id]
	_terminate_entry(entry)
	_remember_released(terminal_id, (entry.output as PackedByteArray).get_string_from_utf8(), entry.exit_code)
	_terminals.erase(terminal_id)
	_log("terminal %s released" % terminal_id)
	return {}


## Mata todos los procesos de terminal activos (al detener la sesión o cerrar el plugin).
func stop_all() -> void:
	for terminal_id: String in _terminals.keys():
		var entry: Dictionary = _terminals[terminal_id]
		_terminate_entry(entry)
		_remember_released(terminal_id, (entry.output as PackedByteArray).get_string_from_utf8(), entry.exit_code)
	_terminals.clear()


## Texto de salida actual (o recordado tras `release`) de `terminal_id`.
func output_of(terminal_id: String) -> String:
	if _terminals.has(terminal_id):
		var entry: Dictionary = _terminals[terminal_id]
		return (entry.output as PackedByteArray).get_string_from_utf8()
	if _released_outputs.has(terminal_id):
		return str((_released_outputs[terminal_id] as Dictionary).get("output", ""))
	return ""


func active_count() -> int:
	var count := 0
	for terminal_id: String in _terminals:
		if not bool((_terminals[terminal_id] as Dictionary).exited):
			count += 1
	return count


## Trunca `buffer` desde el principio para que quede dentro de `byte_limit`, avanzando hasta el
## primer inicio válido de carácter UTF-8. Devuelve `{bytes, text, truncated}`.
static func truncate_utf8_prefix(buffer: PackedByteArray, byte_limit: int) -> Dictionary:
	if byte_limit <= 0:
		return {"bytes": PackedByteArray(), "text": "", "truncated": not buffer.is_empty()}
	if buffer.size() <= byte_limit:
		return {"bytes": buffer, "text": buffer.get_string_from_utf8(), "truncated": false}
	var offset := buffer.size() - byte_limit
	while offset < buffer.size() and (buffer[offset] & 0xC0) == 0x80:
		offset += 1
	var kept := buffer.slice(offset)
	return {"bytes": kept, "text": kept.get_string_from_utf8(), "truncated": true}


static func format_command_line(command: String, args: PackedStringArray) -> String:
	if args.is_empty():
		return command
	var parts: PackedStringArray = [command]
	for arg: String in args:
		if arg.find(" ") >= 0 or arg.find("\"") >= 0:
			parts.append("\"%s\"" % arg.replace("\"", "\\\""))
		else:
			parts.append(arg)
	return " ".join(parts)


func _on_output(chunk: PackedByteArray, terminal_id: String) -> void:
	if not _terminals.has(terminal_id):
		return
	var entry: Dictionary = _terminals[terminal_id]
	var combined: PackedByteArray = entry.output
	combined.append_array(chunk)
	var limit: int = int(entry.byte_limit)
	if combined.size() > limit:
		var trimmed := truncate_utf8_prefix(combined, limit)
		entry.output = trimmed.bytes
		entry.truncated = true
	else:
		entry.output = combined
	output_changed.emit(terminal_id, (entry.output as PackedByteArray).get_string_from_utf8(), entry.exit_code)


func _on_exited(code: int, terminal_id: String) -> void:
	if not _terminals.has(terminal_id):
		return
	var entry: Dictionary = _terminals[terminal_id]
	if bool(entry.exited):
		return
	entry.exited = true
	if not bool(entry.killed):
		entry.exit_code = code
	var process: AgentProcess = entry.process
	process.stop()
	var text := (entry.output as PackedByteArray).get_string_from_utf8()
	output_changed.emit(terminal_id, text, entry.exit_code)
	terminal_exited.emit(terminal_id)
	_log("terminal %s exited (code %s, signal %s)" % [terminal_id, str(entry.exit_code), str(entry.exit_signal)])


func _terminate_entry(entry: Dictionary) -> void:
	if bool(entry.exited):
		return
	entry.killed = true
	entry.exit_signal = "SIGTERM"
	entry.exited = true
	var process: AgentProcess = entry.process
	if process:
		process.stop()
	var terminal_id := str(entry.id)
	output_changed.emit(terminal_id, (entry.output as PackedByteArray).get_string_from_utf8(), entry.exit_code)
	terminal_exited.emit(terminal_id)


func _remember_released(terminal_id: String, output: String, exit_code: Variant) -> void:
	_released_outputs[terminal_id] = {"output": output, "exit_code": exit_code}
	if not terminal_id in _released_order:
		_released_order.append(terminal_id)
	while _released_order.size() > MAX_RELEASED_OUTPUTS:
		var oldest: String = _released_order[0]
		_released_order.remove_at(0)
		_released_outputs.erase(oldest)


static func _exit_status(entry: Dictionary) -> Dictionary:
	return {
		"exitCode": entry.exit_code,
		"signal": entry.exit_signal,
	}


func _check_cwd(path: String) -> String:
	if path.is_empty():
		return ""
	if not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):
		return "The cwd must be an absolute path: %s" % path
	if project_root.is_empty():
		return ""
	var normalized := path.simplify_path().trim_suffix("/")
	if _inside(normalized, project_root):
		return ""
	for root: String in extra_roots:
		if _inside(normalized, root.simplify_path().trim_suffix("/")):
			return ""
	return "Working directory outside the project: %s" % path


static func _inside(path: String, root: String) -> bool:
	return not root.is_empty() and (path == root or path.begins_with(root + "/"))


func _launch_command(command: String, args: PackedStringArray, working_dir: String) -> Array:
	var direct := CommandResolver.resolve(command)
	var is_shell_expr := args.is_empty() and (direct.is_empty() or command.find(" ") >= 0 or command.find("|") >= 0 or command.find("&") >= 0 or command.find(";") >= 0 or command.find(">") >= 0 or command.find("<") >= 0 or command.find("$") >= 0)
	if OS.get_name() == "Windows":
		var cmd_part := command if is_shell_expr else _quote_windows(direct if not direct.is_empty() else command)
		if not is_shell_expr:
			var parts: PackedStringArray = [cmd_part]
			for arg: String in args:
				parts.append(_quote_windows(arg))
			cmd_part = " ".join(parts)
		if not working_dir.is_empty():
			cmd_part = "cd /d %s && %s" % [_quote_windows(working_dir), cmd_part]
		return ["cmd.exe", PackedStringArray(["/c", cmd_part])]
	if is_shell_expr:
		if working_dir.is_empty():
			return ["/bin/sh", PackedStringArray(["-c", command])]
		return ["/bin/sh", PackedStringArray(["-c", "cd \"$1\" && shift && eval \"$1\"", "sh", working_dir, command])]
	var executable := direct if not direct.is_empty() else command
	if working_dir.is_empty():
		return [executable, args]
	var wrapped := PackedStringArray(["-c", "cd \"$1\" && shift && exec \"$@\"", "sh", working_dir, executable])
	wrapped.append_array(args)
	return ["/bin/sh", wrapped]


func _build_env(raw_env: Variant, launch_cmd: String) -> Dictionary:
	var result: Dictionary = env_provider.call() if env_provider.is_valid() else {}
	if not result.has("PATH"):
		var resolved := CommandResolver.resolve(launch_cmd)
		result["PATH"] = CommandResolver.child_path_for(resolved if not resolved.is_empty() else launch_cmd)
	if raw_env is Array:
		for item: Variant in raw_env:
			if item is Dictionary and item.get("name") is String:
				result[str(item.name)] = str(item.get("value", ""))
	elif raw_env is Dictionary:
		for key: Variant in raw_env:
			result[str(key)] = str(raw_env[key])
	return result


static func _to_string_array(raw: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if raw is Array or raw is PackedStringArray:
		for item: Variant in raw:
			result.append(str(item))
	return result


static func _quote_windows(text: String) -> String:
	return "\"%s\"" % text.replace("\"", "\\\"")


func _log(message: String) -> void:
	if agent_log:
		agent_log.add(AgentLog.CH_PROC, message)
