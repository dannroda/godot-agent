@tool
extends RefCounted
## Login del agente con un método de autenticación de ACP de tipo `terminal` (el que ofrecen Zed
## y JetBrains). Corre el comando de login del propio agente sin bloquear el editor: el comando del
## perfil más los `args` del método, o el `_meta.terminal-auth` si lo manda. El agente abre el
## navegador y guarda sus credenciales; el addon nunca las lee. Si el navegador no vuelve solo, la
## página da un código que se pega acá (va al stdin del comando).

signal url_found(url: String)
signal finished(ok: bool, message: String)

const AgentProcess := preload("../transport/agent_process.gd")
const AgentProfile := preload("../core/agent_profile.gd")

## Líneas de salida que se guardan para explicar un error.
const TAIL_LINES := 6

var method: Dictionary = {}
var url: String = ""

var _process: AgentProcess
var _tail: PackedStringArray = []
var _url_regex := RegEx.create_from_string("https?://\\S+")


## Métodos que el addon sabe usar: `terminal` (corre el login del agente) o los del agente
## (default de ACP: el cliente llama `authenticate`). `env_var` necesita que el usuario configure
## una variable en el perfil, y no se ofrece como botón.
static func usable_methods(auth_methods: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in auth_methods:
		if item is Dictionary and item.get("id") is String and str(item.get("type", "agent")) in ["terminal", "agent"]:
			result.append(item)
	return result


static func is_terminal(auth_method: Dictionary) -> bool:
	return str(auth_method.get("type", "")) == "terminal" or _terminal_meta(auth_method) != null


## `{command, args, env}` para correr el login. Con `_meta.terminal-auth` el agente da el comando
## exacto; si no, es el del perfil con los `args` y `env` del método.
static func command_for(auth_method: Dictionary, profile: AgentProfile) -> Dictionary:
	var env := profile.resolved_env()
	if auth_method.get("env") is Dictionary:
		env.merge(auth_method.env, true)
	var meta: Variant = _terminal_meta(auth_method)
	if meta is Dictionary and meta.get("command") is String:
		return {"command": str(meta.command), "args": PackedStringArray(meta.get("args", []) if meta.get("args") is Array else []), "env": env}
	var args := PackedStringArray(profile.args)
	if auth_method.get("args") is Array:
		args.append_array(PackedStringArray(auth_method.args))
	return {"command": profile.command, "args": args, "env": env}


static func label_of(auth_method: Dictionary) -> String:
	return str(auth_method.get("name", auth_method.get("id", "")))


static func _terminal_meta(auth_method: Dictionary) -> Variant:
	var meta: Variant = auth_method.get("_meta")
	return meta.get("terminal-auth") if meta is Dictionary and meta.get("terminal-auth") is Dictionary else null


func start(auth_method: Dictionary, profile: AgentProfile) -> bool:
	cancel()
	method = auth_method
	url = ""
	_tail.clear()
	var command := command_for(auth_method, profile)
	_process = AgentProcess.new()
	_process.line_received.connect(_on_line)
	_process.stderr_received.connect(_on_line)
	_process.exited.connect(_on_exited.bind(_process))
	if not _process.start(command.command, command.args, command.env):
		var message := _process.last_error()
		_process = null
		finished.emit(false, message)
		return false
	return true


func is_running() -> bool:
	return _process != null and _process.is_running()


## El código que da la página de login cuando el navegador no vuelve solo.
func send_code(code: String) -> bool:
	return is_running() and not code.strip_edges().is_empty() and _process.send_line(code.strip_edges())


func cancel() -> void:
	if _process == null:
		return
	var process := _process
	_process = null
	process.stop()


func _on_line(line: String) -> void:
	var text := line.strip_edges()
	if text.is_empty():
		return
	_tail.append(text)
	if _tail.size() > TAIL_LINES:
		_tail.remove_at(0)
	if url.is_empty():
		var found := _url_regex.search(text)
		if found:
			url = found.get_string()
			url_found.emit(url)


func _on_exited(code: int, process: AgentProcess) -> void:
	if process != _process:
		return  # cancelado
	_process = null
	process.stop()
	if code == 0:
		finished.emit(true, "")
	else:
		var detail := "\n".join(_tail).replace(url, "<enlace>") if not url.is_empty() else "\n".join(_tail)
		finished.emit(false, "el login terminó con código %d%s" % [code, (": " + detail) if not detail.is_empty() else ""])
