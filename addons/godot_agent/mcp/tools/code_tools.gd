@tool
extends RefCounted
## Navegar el código del proyecto desde el editor, sin la shell (m11-83, grupo read): read_function
## lee una función de GDScript por nombre o por una línea (la de un frame de game_stack), con el
## texto sin guardar del Script Editor si lo hay. Idea de Orca (read_gdscript_function).

const McpTool := preload("../mcp_tool.gd")
const UntrustedText := preload("../untrusted_text.gd")
const GdscriptOutline := preload("../gdscript_outline.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const MAX_SOURCE_BYTES := 2 * 1024 * 1024
const MAX_LINES := 300
const MAX_BYTES := 96 * 1024
const MAX_CANDIDATES := 20
## Nombres de funciones que se listan cuando no se encuentra la pedida.
const MAX_LISTED := 60

## `(abs_path: String) -> Variant`: el texto sin guardar del Script Editor, o null. Lo pone el
## plugin (EditorSync.buffer_text); sin él se lee el disco.
var unsaved_buffer: Callable


func tools() -> Array:
	var read := PermissionPolicy.GROUP_READ
	return [
		McpTool.enveloped(McpTool.create("read_function", read,
			"Reads one GDScript function: its signature, the ## comments and annotations above it and its body, with line numbers. By `name` (`jump`, or `Inner.jump` in an inner class) or by a `line` inside it (e.g. a frame of game_stack). Reads the Script Editor's unsaved text when the script has unsaved changes. Cheaper than reading the whole file.",
			{
				"script": {"type": "string", "description": "res://…gd path or a class_name"},
				"name": {"type": "string", "description": "Function name, or Inner.name"},
				"line": {"type": "integer", "description": "A line inside the function (from 1), instead of name"},
				"from": {"type": "integer", "description": "Show from this line on, for a function too long to show whole"},
			}, ["script"], _read_function), McpTool.ENVELOPE_PARTS),
	]


func _read_function(args: Dictionary) -> Dictionary:
	var source := read_script(McpTool.str_arg(args, "script"))
	if source.has("error"):
		return McpTool.error(source.error)
	var wanted := McpTool.str_arg(args, "name").strip_edges()
	var line := McpTool.int_arg(args, "line", 0)
	if wanted.is_empty() and line <= 0:
		return McpTool.error("Pass `name` (the function) or `line` (a line inside it).")
	var declarations := GdscriptOutline.parse(source.text)
	var decl := {}
	if not wanted.is_empty():
		var found := GdscriptOutline.find_functions(declarations, wanted)
		if found.is_empty():
			return McpTool.error("There is no function \"%s\" in %s.%s" % [wanted.left(128), source.path, _function_list(declarations)])
		if found.size() > 1:
			var candidates: PackedStringArray = []
			for candidate: Dictionary in found.slice(0, MAX_CANDIDATES):
				candidates.append("%s (line %d)" % [candidate.qualified, candidate.line])
			return McpTool.error("%d functions are called \"%s\" in %s: %s. Ask for one with its inner class (Inner.name) or a line." % [found.size(), wanted.left(128), source.path, UntrustedText.wrap(", ".join(candidates))])
		decl = found[0]
	else:
		decl = GdscriptOutline.function_at(declarations, line)
		if decl.is_empty():
			return McpTool.error("Line %d of %s is not inside a function.%s" % [line, source.path, _function_list(declarations)])
	return McpTool.text(format_function(source, decl, McpTool.int_arg(args, "from", 0)))


## El texto de la función con sus líneas, y un encabezado que dice de dónde salió.
## `from`: la primera línea a mostrar, para una función que no entra entera.
static func format_function(source: Dictionary, decl: Dictionary, from: int = 0) -> String:
	var lines: PackedStringArray = source.text.split("\n")
	var first: int = clampi(from, decl.start, decl.end) if from > 0 else decl.start
	var last: int = decl.end
	var body: PackedStringArray = []
	var bytes := 0
	var shown_last := first - 1
	for number in range(first, last + 1):
		var text := "%5d  %s" % [number, lines[number - 1].trim_suffix("\r")]
		if number - first >= MAX_LINES or bytes + text.length() > MAX_BYTES:
			break
		body.append(text)
		bytes += text.length() + 1
		shown_last = number
	var header := "%s · %sfunc %s · lines %d-%d" % [source.path, "static " if decl.static else "", decl.qualified, decl.start, last]
	if source.unsaved:
		header += " · from the Script Editor's unsaved text (differs from the file on disk)"
	if shown_last < last:
		header += " · showing %d-%d (too long): call read_function again with from=%d for the rest" % [first, shown_last, shown_last + 1]
	return header + "\n" + UntrustedText.wrap("\n".join(body))


## Los nombres de las funciones del script, para cuando no se encontró la pedida.
static func _function_list(declarations: Array[Dictionary]) -> String:
	var names: PackedStringArray = []
	for decl: Dictionary in declarations:
		if decl.kind == GdscriptOutline.KIND_FUNC:
			names.append(decl.qualified)
	if names.is_empty():
		return " It has no functions."
	var listed := ", ".join(names.slice(0, MAX_LISTED))
	if names.size() > MAX_LISTED:
		listed += "… (%d in total)" % names.size()
	return " Its functions: %s" % UntrustedText.wrap(listed)


## El texto de un script: {path, text, unsaved} o {error}. `script` es una ruta res:// (o relativa
## al proyecto) o un class_name.
func read_script(script: String) -> Dictionary:
	var path := resolve_script_path(script.strip_edges())
	if path.is_empty():
		if script.strip_edges().is_valid_identifier():
			return {"error": "No script of the project has class_name %s. Pass a res://…gd path." % script.strip_edges()}
		return {"error": "`script` is empty: pass a res://…gd path or a class_name."}
	if not path.begins_with("res://") or path.contains(".."):
		return {"error": "\"%s\" is outside the project: read_function reads the project's scripts (res://…)." % script.left(256)}
	if path.get_extension().to_lower() == "cs":
		return {"error": "%s is C#: read_function reads GDScript only. Use find_in_files or read the file." % path}
	if path.contains("::"):
		return {"error": "%s is a built-in script (saved inside a scene): read the scene's script with scene_tree/get_node or open the scene file." % path}
	if path.get_extension().to_lower() != "gd":
		return {"error": "\"%s\" is not a .gd script nor a known class_name." % script.left(256)}
	var absolute := ProjectSettings.globalize_path(path)
	if unsaved_buffer.is_valid():
		var buffer: Variant = unsaved_buffer.call(absolute)
		if buffer is String:
			return {"path": path, "text": buffer, "unsaved": true}
	if not FileAccess.file_exists(path):
		return {"error": "%s does not exist." % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot read %s (%s)." % [path, error_string(FileAccess.get_open_error())]}
	if file.get_length() > MAX_SOURCE_BYTES:
		return {"error": "%s is larger than %d MB." % [path, MAX_SOURCE_BYTES / (1024 * 1024)]}
	return {"path": path, "text": file.get_as_text(), "unsaved": false}


## Una ruta res:// para `script`: tal cual si empieza con res://, la de un class_name, una ruta
## absoluta dentro del proyecto o una relativa a su carpeta. "" si viene vacío o es un nombre que no
## es un class_name del proyecto.
static func resolve_script_path(script: String) -> String:
	if script.is_empty():
		return ""
	if script.begins_with("res://"):
		return script
	if script.is_valid_identifier():
		return class_name_path(script)
	if script.is_absolute_path():
		var local := ProjectSettings.localize_path(script)
		return local if local.begins_with("res://") else script
	return "res://" + script.trim_prefix("./")


## El script de un class_name: el de la lista global y, si todavía no está (un script recién creado
## que el editor escaneó pero cuya clase no registró aún), el que dice el filesystem del editor.
static func class_name_path(wanted: String) -> String:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == wanted:
			return str(entry.get("path", ""))
	if Engine.is_editor_hint():
		return _class_in(EditorInterface.get_resource_filesystem().get_filesystem(), wanted)
	return ""


static func _class_in(dir: EditorFileSystemDirectory, wanted: String) -> String:
	if dir == null:
		return ""
	for i in dir.get_file_count():
		if dir.get_file_script_class_name(i) == wanted:
			return dir.get_file_path(i)
	for i in dir.get_subdir_count():
		var found := _class_in(dir.get_subdir(i), wanted)
		if not found.is_empty():
			return found
	return ""
