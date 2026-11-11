@tool
extends RefCounted
## Las tools propias del proyecto (m11-46): cada `<carpeta>/<nombre>.gd` (res://agent_tools/ por
## defecto) es godot.<nombre>, un método extendido (godot.methods / godot.run) del grupo de permisos
## «Project tools».
##
## Es código que el agente dispara dentro del editor, y viene con el proyecto: solo se carga en una
## máquina donde se aprobó ese código exacto (MachineApproval, como los checks y los MCP servers del
## proyecto). La clave cubre el texto de la tool y el de todos los demás .gd de la carpeta (los
## helpers: archivos con `_` adelante y subcarpetas), así que cambiar cualquiera, también si lo hace
## el agente, la deja frenada hasta aprobarla de nuevo. Una tool sin aprobar nunca se carga: load()
## ya compila el script y corre sus static; de ella solo se lee el texto para la clave.
##
## refresh() vuelve a mirar la carpeta (barato: lee y hashea unos pocos archivos) y recarga lo que
## cambió, sin caché, para que una tool editada se use en la llamada siguiente.

const McpTool := preload("mcp_tool.gd")
const MachineApproval := preload("../core/machine_approval.gd")
const PermissionPolicy := preload("../session/permission_policy.gd")
const AgentToolContext := preload("../api/agent_tool_context.gd")

const DEFAULT_DIR := "res://agent_tools"
const STATE_READY := "ready"
const STATE_HELD := "held"
const STATE_ERROR := "error"
## Líneas del código que muestra «Aprobar…».
const PREVIEW_LINES := 40
const NAME_PATTERN := "^[a-z][a-z0-9_]*$"

var dir: String = DEFAULT_DIR
## La carpeta del proyecto principal (no la de una copia aparte): arma la clave.
var project_dir: String = ""
## `(key) -> bool`: la tienda de aprobaciones de esta máquina.
var is_approved: Callable
## `(name) -> bool`: los nombres que ya usa el addon.
var reserved: Callable
var undo_redo: EditorUndoRedoManager
## `(text)`: una línea en el log del harness.
var log_line: Callable

## nombre → `{name, path, key, state, error, description, tool, source}`.
var _entries: Dictionary = {}


## La carpeta de Settings, o la de siempre si está vacía o no sirve (ver normalize_dir).
static func resolve_dir(configured: String) -> String:
	var value := normalize_dir(configured)
	return value if not value.is_empty() else DEFAULT_DIR


## `configured` como ruta res:// ("tools/agent/" → "res://tools/agent"), o "" si está vacía o apunta
## adonde no puede: la raíz del proyecto, fuera de él, el addon o una carpeta con punto (.godot).
static func normalize_dir(configured: String) -> String:
	var value := configured.strip_edges().trim_prefix("res://").trim_prefix("/").trim_suffix("/")
	if value.is_empty() or ".." in value.split("/") or value.begins_with(".") or value.begins_with("addons/godot_agent"):
		return ""
	return ("res://" + value).simplify_path()


## El texto aprobado de una tool: su ruta, su código y el de los helpers de la carpeta.
static func approval_key(project: String, path: String, source: String, helpers: String) -> String:
	return MachineApproval.key(project, "project-tool %s\n%s\n%s" % [path, source.sha256_text(), helpers])


## La entrada de export_presets.cfg que deja la carpeta afuera ("agent_tools/*").
static func export_filter(tools_dir: String) -> String:
	return tools_dir.trim_prefix("res://") + "/*"


## Vuelve a mirar la carpeta. true si cambió algo (una tool nueva, editada, borrada, aprobada).
func refresh() -> bool:
	var before := _signature()
	var files := _scan()
	var helpers := _helpers_hash(files.helpers)
	var seen: Dictionary = {}
	for path: String in files.tools:
		var tool_name := path.get_file().get_basename()
		seen[tool_name] = true
		var source := FileAccess.get_file_as_string(path)
		var key := approval_key(project_dir, path, source, helpers)
		var approved: bool = is_approved.is_valid() and bool(is_approved.call(key))
		var current: Dictionary = _entries.get(tool_name, {})
		if current.get("key") == key and (current.get("state") != STATE_HELD) == approved and current.get("path") == path:
			continue
		_entries[tool_name] = _entry(tool_name, path, source, key, approved)
	for tool_name: String in _entries.keys():
		if not seen.has(tool_name):
			_entries.erase(tool_name)
	var changed := _signature() != before
	if changed and log_line.is_valid():
		log_line.call("project tools: %s" % _signature())
	return changed


## Las tools cargadas y listas.
func tools() -> Array:
	var result: Array = []
	for tool_name: String in _sorted_names():
		if _entries[tool_name].state == STATE_READY:
			result.append(_entries[tool_name].tool)
	return result


## Todas, para la pestaña Tools: `{name, path, state, error, description, key}`.
func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tool_name: String in _sorted_names():
		var entry: Dictionary = _entries[tool_name]
		result.append({"name": entry.name, "path": entry.path, "state": entry.state, "error": entry.error, "description": entry.description, "key": entry.key})
	return result


## Las frenadas, como las pide «Aprobar…»: `[{name, command, key}]`; `command` es la ruta y el código.
func held() -> Array:
	var result: Array = []
	for tool_name: String in _sorted_names():
		var entry: Dictionary = _entries[tool_name]
		if entry.state == STATE_HELD:
			result.append({"name": entry.name, "command": preview(entry.path, entry.source), "key": entry.key})
	return result


## Lo que muestra el diálogo: la ruta y las primeras líneas del código.
static func preview(path: String, source: String) -> String:
	var lines := source.split("\n")
	var shown := "\n".join(lines.slice(0, PREVIEW_LINES))
	if lines.size() > PREVIEW_LINES:
		shown += "\n… (%d lines)" % lines.size()
	return "%s\n%s" % [path, shown]


func _entry(tool_name: String, path: String, source: String, key: String, approved: bool) -> Dictionary:
	var entry := {"name": tool_name, "path": path, "key": key, "state": STATE_HELD, "error": "", "description": "", "tool": null, "source": source}
	if not RegEx.create_from_string(NAME_PATTERN).search(tool_name):
		entry.state = STATE_ERROR
		entry.error = "The file name is the tool name: use lowercase letters, digits and _ (build_level.gd)."
		return entry
	if reserved.is_valid() and bool(reserved.call(tool_name)):
		entry.state = STATE_ERROR
		entry.error = "godot.%s already exists in the addon: rename the file." % tool_name
		return entry
	if not approved:
		return entry
	var loaded := _load(tool_name, path)
	if loaded.has("error"):
		entry.state = STATE_ERROR
		entry.error = loaded.error
		return entry
	entry.state = STATE_READY
	entry.tool = loaded.tool
	entry.description = (loaded.tool as McpTool).description
	return entry


## Carga una tool aprobada, sin caché (CACHE_MODE_IGNORE_DEEP también recarga sus helpers).
## `{tool}` o `{error}`.
func _load(tool_name: String, path: String) -> Dictionary:
	var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDScript
	if script == null or not script.can_instantiate():
		return {"error": "The script doesn't compile: open it in the Script Editor to see the error."}
	if not script.is_tool():
		return {"error": "Add @tool as the first line: the tool runs inside the editor."}
	if not script.get_global_name().is_empty():
		return {"error": "Remove class_name: a global class would point the exported game to this tool, which is not exported."}
	var instance: Object = script.new()
	if instance == null or not instance.has_method(&"_run") or not instance.has_method(&"_parameters"):
		return {"error": "The script must extend \"res://addons/godot_agent/api/agent_tool.gd\"."}
	var description := str(instance.call(&"_description")).strip_edges()
	if description.is_empty():
		return {"error": "_description() is empty: the agent needs to know what the tool does."}
	var parameters: Variant = instance.call(&"_parameters")
	var schema_error := _schema_error(parameters)
	if not schema_error.is_empty():
		return {"error": schema_error}
	var properties: Dictionary = (parameters as Dictionary).get("properties", {})
	var required := PackedStringArray((parameters as Dictionary).get("required", []))
	var tool: McpTool = McpTool.create(tool_name, PermissionPolicy.GROUP_PROJECT_TOOLS,
		"%s (Project tool %s.)" % [description, path], properties, required, Callable())
	var ctx := AgentToolContext.new()
	ctx.undo_redo = undo_redo
	ctx.project_dir = project_dir
	ctx.tool_name = tool_name
	ctx._log = log_line
	tool.handler = _handler(instance, ctx)
	tool.describer = _describer(path, McpTool.create(tool_name, "", "", properties, required, Callable()) as McpTool)
	McpTool.enveloped(tool, McpTool.ENVELOPE_ALL)
	return {"tool": tool}


## El primer problema del schema que devolvió _parameters(), o "".
static func _schema_error(parameters: Variant) -> String:
	if not parameters is Dictionary:
		return "_parameters() must return a Dictionary: {\"properties\": {...}, \"required\": [...]}."
	var properties: Variant = (parameters as Dictionary).get("properties", {})
	if not properties is Dictionary:
		return "_parameters().properties must be a Dictionary of JSON schemas."
	for param: Variant in properties:
		if not properties[param] is Dictionary:
			return "_parameters().properties.%s must be a JSON schema (a Dictionary like {\"type\": \"string\"})." % param
	var required: Variant = (parameters as Dictionary).get("required", [])
	if not (required is Array or required is PackedStringArray):
		return "_parameters().required must be an Array of names."
	for param: Variant in required:
		if not (properties as Dictionary).has(param):
			return "_parameters().required names '%s', which is not in properties." % param
	return ""


## Static: el lambda no captura al loader (la tool lo guardaría y el loader guarda la tool).
static func _handler(instance: Object, ctx: RefCounted) -> Callable:
	return func(args: Dictionary) -> Variant:
		return result_of(await instance.call(&"_run", args, ctx))


static func _describer(path: String, plain: McpTool) -> Callable:
	return func(args: Dictionary) -> String:
		var text := plain.describe(args)
		return path + ("\n" + text if not text.is_empty() else "")


## Lo que devolvió _run() → lo que entiende el registro. null (un error de script, o un _run sin
## return) queda null: el registro lo da como error.
static func result_of(value: Variant) -> Variant:
	if value == null or value is String or value is Image:
		return value
	if value is Dictionary and (value as Dictionary).get("content") is Array:
		return value
	if value is Dictionary or value is Array:
		return JSON.stringify(value, "  ")
	return str(value)


## Los .gd de la carpeta: las tools (arriba, sin `_` adelante) y los helpers (todos los demás).
func _scan() -> Dictionary:
	var result := {"tools": PackedStringArray(), "helpers": PackedStringArray()}
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() != "gd":
			continue
		var path := dir.path_join(file)
		if file.begins_with("_"):
			result.helpers.append(path)
		else:
			result.tools.append(path)
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), result.helpers)
	result.tools.sort()
	result.helpers.sort()
	return result


static func _collect(path: String, into: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() == "gd":
			into.append(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_collect(path.path_join(sub), into)


static func _helpers_hash(paths: PackedStringArray) -> String:
	var parts: PackedStringArray = []
	for path: String in paths:
		parts.append("%s %s" % [path, FileAccess.get_file_as_string(path).sha256_text()])
	return "\n".join(parts).sha256_text()


func _sorted_names() -> Array:
	var names := _entries.keys()
	names.sort()
	return names


func _signature() -> String:
	var parts: PackedStringArray = []
	for tool_name: String in _sorted_names():
		parts.append("%s=%s" % [tool_name, _entries[tool_name].state])
		parts.append(str(_entries[tool_name].key).left(8))
	return " ".join(parts)
