@tool
extends RefCounted
## fs/read_text_file y fs/write_text_file (spec §4.2). No depende del editor: el buffer del
## Script Editor, la autorización de escritura y la sincronización posterior se inyectan.

const AcpClient := preload("acp_client.gd")
const AgentLog := preload("../core/agent_log.gd")

## Carpetas del proyecto donde el agente nunca escribe.
const FORBIDDEN_DIRS: PackedStringArray = [".godot", ".git"]
## Extensiones que maneja el editor (spec §8.3): se permite, pero se avisa en el log.
const EDITOR_MANAGED_EXTENSIONS: PackedStringArray = ["uid", "import"]

var project_root: String = ""
var extra_roots: PackedStringArray = []
var agent_log: AgentLog
## Callable(abs_path: String) -> Variant: texto del buffer si está abierto con cambios sin guardar,
## o null para leer del disco.
var buffer_reader: Callable
## Callable(abs_path: String, old_text: String, new_text: String) -> bool (puede ser async).
var write_authorizer: Callable
## Callable(abs_path: String, old_text: String, new_text: String) -> void, tras escribir a disco.
var after_write: Callable


func setup(root: String, log_sink: AgentLog) -> void:
	project_root = root.simplify_path().trim_suffix("/")
	agent_log = log_sink


func register(client: AcpClient) -> void:
	client.set_request_handler("fs/read_text_file", read_text_file)
	client.set_request_handler("fs/write_text_file", write_text_file)


func read_text_file(params: Dictionary) -> Variant:
	var path := str(params.get("path", ""))
	var check := _check_path(path, false)
	if not check.is_empty():
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, check)
	var text: Variant = buffer_reader.call(path) if buffer_reader.is_valid() else null
	var source := "editor buffer"
	if text == null:
		if not FileAccess.file_exists(path):
			_log("read %s: does not exist" % path)
			return AcpClient.AcpResponse.failure(AcpClient.ERR_INTERNAL, "File not found: %s" % path)
		text = FileAccess.get_file_as_string(path)
		source = "disk"
		if FileAccess.get_open_error() != OK:
			return AcpClient.AcpResponse.failure(AcpClient.ERR_INTERNAL, "Cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())])
	var content := slice_lines(str(text), params.get("line"), params.get("limit"))
	_log("read %s (%s, %d characters)" % [_short(path), source, content.length()])
	return {"content": content}


func write_text_file(params: Dictionary) -> Variant:
	var path := str(params.get("path", ""))
	var check := _check_path(path, true)
	if not check.is_empty():
		_log("write rejected: %s" % check)
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, check)
	if not params.get("content") is String:
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, "Missing 'content'.")
	var new_text: String = params.content
	var old_text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if path.get_extension() in EDITOR_MANAGED_EXTENSIONS:
		_log("warning: the agent writes %s (the editor handles it)" % _short(path))
	if write_authorizer.is_valid():
		var allowed: bool = await write_authorizer.call(path, old_text, new_text)
		if not allowed:
			_log("write denied: %s" % _short(path))
			return AcpClient.AcpResponse.failure(AcpClient.ERR_INTERNAL, "Permission denied by the user or the current mode: %s" % path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INTERNAL, "Cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(new_text)
	file.close()
	_log("write %s (%d characters)" % [_short(path), new_text.length()])
	if after_write.is_valid():
		after_write.call(path, old_text, new_text)
	return {}


## "" si la ruta es válida; si no, el motivo.
func _check_path(path: String, for_write: bool) -> String:
	if path.is_empty() or not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):
		return "The path must be absolute: %s" % path
	var normalized := path.simplify_path()
	if not _inside(normalized, project_root):
		for root: String in extra_roots:
			if _inside(normalized, root.simplify_path().trim_suffix("/")):
				return ""
		return "Path outside the project: %s" % path
	if for_write:
		var relative := normalized.substr(project_root.length() + 1)
		for dir: String in FORBIDDEN_DIRS:
			if relative == dir or relative.begins_with(dir + "/"):
				return "The agent cannot write inside %s/: %s" % [dir, path]
	return ""


static func _inside(path: String, root: String) -> bool:
	return not root.is_empty() and (path == root or path.begins_with(root + "/"))


## `line` es 1-based; `limit`, la cantidad de líneas. Sin ninguno, el texto entero.
static func slice_lines(text: String, line: Variant, limit: Variant) -> String:
	if line == null and limit == null:
		return text
	var lines := text.split("\n")
	var start := maxi(int(line) - 1, 0) if line != null else 0
	var count := int(limit) if limit != null else lines.size()
	return "\n".join(lines.slice(start, start + maxi(count, 0)))


func _short(path: String) -> String:
	return path.trim_prefix(project_root + "/")


func _log(message: String) -> void:
	if agent_log:
		agent_log.add(AgentLog.CH_FS, message)
