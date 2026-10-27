@tool
extends RefCounted
## El CLI de Claude Code para la ventana Extensions (m7-37): plugins, marketplaces y MCP servers
## salen de `claude plugin … --json` y `claude mcp list`. Corre con AgentProcess (sin threads, D35)
## en la carpeta del proyecto, para que `.mcp.json` y el scope local sean los de este proyecto.
## Si `claude` no está en el PATH, usa el que trae el adaptador ACP en la cache de npx.

const AgentProcess := preload("../transport/agent_process.gd")
const CommandResolver := preload("../transport/command_resolver.gd")

## Lo que puede tardar un comando antes de cortarlo (un install clona un repo).
const DEFAULT_TIMEOUT_MS := 180000
const AUTH_TIMEOUT_MS := 20000

## Ruta del ejecutable ("" si no se encontró).
var path: String = ""
## Carpeta donde corren los comandos (la del proyecto).
var cwd: String = ""
## Entorno extra (el del perfil del agente: CLAUDE_CONFIG_DIR y demás).
var env: Dictionary = {}
## Procesos en curso: un cierre del editor o de la ventana los mata.
var _running: Array[AgentProcess] = []


func _init(project_dir: String = "", extra_env: Dictionary = {}) -> void:
	cwd = project_dir
	env = extra_env
	path = find()


func is_available() -> bool:
	return not path.is_empty()


## `claude` del PATH (o de las carpetas habituales); si no, el binario del SDK que baja npx con el
## adaptador (`@anthropic-ai/claude-agent-sdk-<plataforma>/claude`), el más nuevo.
static func find() -> String:
	var on_path := CommandResolver.resolve("claude")
	if not on_path.is_empty():
		return on_path
	var npx := _npx_cache_dir()
	if npx.is_empty() or not DirAccess.dir_exists_absolute(npx):
		return ""
	var best := ""
	var best_time := 0
	var binary := "claude.exe" if OS.get_name() == "Windows" else "claude"
	for entry: String in DirAccess.get_directories_at(npx):
		var scope := npx.path_join(entry).path_join("node_modules/@anthropic-ai")
		if not DirAccess.dir_exists_absolute(scope):
			continue
		for package: String in DirAccess.get_directories_at(scope):
			if not package.begins_with("claude-agent-sdk-"):
				continue
			var candidate := scope.path_join(package).path_join(binary)
			var modified := FileAccess.get_modified_time(candidate) if FileAccess.file_exists(candidate) else 0
			if modified > best_time:
				best = candidate
				best_time = modified
	return best


## `{code, stdout, stderr, timed_out}`. Espera frames hasta que el proceso termine.
func run(args: PackedStringArray, timeout_ms: int = DEFAULT_TIMEOUT_MS) -> Dictionary:
	if path.is_empty():
		return {"code": -1, "stdout": "", "stderr": "Claude Code CLI not found.", "timed_out": false}
	var process := AgentProcess.new()
	var out: PackedStringArray = []
	var err: PackedStringArray = []
	var state := {"done": false, "code": -1}
	process.line_received.connect(func(line: String) -> void: out.append(line))
	process.stderr_received.connect(func(line: String) -> void: err.append(line))
	process.exited.connect(func(code: int) -> void:
		state.code = code
		state.done = true)
	var launch := _launch_command(args)
	var child_env := env.duplicate()
	child_env["PATH"] = CommandResolver.child_path_for(path)
	child_env["NO_COLOR"] = "1"
	if not process.start(launch[0], launch[1], child_env):
		return {"code": -1, "stdout": "", "stderr": process.last_error(), "timed_out": false}
	_running.append(process)
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not state.done and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var timed_out: bool = not state.done
	process.stop()
	_running.erase(process)
	return {"code": state.code, "stdout": "\n".join(out), "stderr": "\n".join(err), "timed_out": timed_out}


## La cuenta con la que está logueado (`claude auth status`, con el CLAUDE_CONFIG_DIR del perfil):
## `{email, org, plan, method}`, o {} si no hay sesión iniciada o el CLI no contestó.
func auth_status() -> Dictionary:
	var result := await run(["auth", "status", "--json"], AUTH_TIMEOUT_MS)
	return parse_auth_status(result.stdout) if result.code == 0 else {}


static func parse_auth_status(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or data.get("loggedIn") != true:
		return {}
	var field := func(key: String) -> String: return str(data[key]) if data.get(key) is String else ""
	return {"email": field.call("email"), "org": field.call("orgName"), "plan": field.call("subscriptionType"), "method": field.call("authMethod")}


## Mata lo que esté corriendo (al cerrar la ventana o el editor).
func stop_all() -> void:
	for process: AgentProcess in _running.duplicate():
		process.stop()
	_running.clear()


## execute_with_pipe no recibe cwd: en Unix pasa por `sh -c 'cd … && exec …'`; en Windows por
## `cmd /c`.
func _launch_command(args: PackedStringArray) -> Array:
	if cwd.is_empty():
		return [path, args]
	if OS.get_name() == "Windows":
		var parts: PackedStringArray = ["cd", "/d", _quote_windows(cwd), "&&", _quote_windows(path)]
		for arg: String in args:
			parts.append(_quote_windows(arg))
		return ["cmd.exe", PackedStringArray(["/c", " ".join(parts)])]
	var wrapped: PackedStringArray = ["-c", "cd \"$1\" && shift && exec \"$@\"", "sh", cwd, path]
	wrapped.append_array(args)
	return ["/bin/sh", wrapped]


static func _quote_windows(text: String) -> String:
	return "\"%s\"" % text.replace("\"", "\\\"")


static func _npx_cache_dir() -> String:
	if OS.get_name() == "Windows":
		var local := OS.get_environment("LOCALAPPDATA")
		return "" if local.is_empty() else local.path_join("npm-cache/_npx")
	var cache := OS.get_environment("npm_config_cache")
	if not cache.is_empty():
		return cache.path_join("_npx")
	return OS.get_environment("HOME").path_join(".npm/_npx")
