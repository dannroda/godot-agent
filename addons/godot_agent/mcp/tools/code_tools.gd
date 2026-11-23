@tool
extends RefCounted
## Navegar el código del proyecto desde el editor, sin la shell (grupo read):
## - read_function (m11-83): una función de GDScript por nombre o por una línea (la de un frame de
##   game_stack);
## - find_symbols (m11-82): dónde se declara algo (class_name, clases internas, funciones, señales,
##   variables, constantes, enums), por nombre, prefijo o parte;
## - find_references (m11-82): dónde se usa un nombre: en el código de los .gd (llamadas, emit,
##   connect, miembros), en strings que son el nombre justo (connect("hit"), call_deferred("jump")) y
##   en las escenas y recursos (conexiones de señales guardadas, tracks de método de animaciones).
## Todo léxico: sin cargar scripts ni tipos, así que un `jump` de dos clases distintas sale junto.
## Con el texto sin guardar del Script Editor si lo hay.

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
## .gd que se leen como mucho al buscar un class_name en el disco.
const MAX_CLASS_SCAN_FILES := 5000
const MAX_SYMBOLS := 100
const MAX_REFERENCES := 200
const MAX_FILES := 5000
## Pasado este tiempo, una búsqueda devuelve lo que encontró y lo dice.
const SEARCH_BUDGET_MS := 3000
const LINE_CHARS := 200
const ADDONS := "res://addons/"
const KINDS: PackedStringArray = ["class_name", "class", "func", "signal", "var", "const", "enum"]
const SCENE_EXTENSIONS: PackedStringArray = ["tscn", "tres"]

## `(abs_path: String) -> Variant`: el texto sin guardar del Script Editor, o null. Lo pone el
## plugin (EditorSync.buffer_text); sin él se lee el disco.
var unsaved_buffer: Callable
## `(folder: String, extensions: PackedStringArray) -> PackedStringArray`: los archivos res:// del
## proyecto con esas extensiones. Sin él, los del filesystem del editor; los tests ponen el suyo.
var list_files: Callable


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
		McpTool.enveloped(McpTool.create("find_symbols", read,
			"Finds where things are declared in the project's GDScript: class_name, inner classes, functions, signals, variables, constants and enums. Exact names first, then names that start with `query`, then names that contain it (case-insensitive). Returns path:line with the declaration. Leaves out res://addons/ unless `path` is inside it. Includes the Script Editor's unsaved text.",
			{
				"query": {"type": "string", "description": "Name, start or part of a name"},
				"kind": {"type": "string", "enum": Array(KINDS), "description": "Only this kind of declaration"},
				"path": {"type": "string", "description": "res:// folder to search in (default res://)"},
			}, ["query"], _find_symbols), McpTool.ENVELOPE_PARTS),
		McpTool.enveloped(McpTool.create("find_references", read,
			"Finds where a name is used: in GDScript code (calls, .emit, .connect, member access; comments don't count), in strings that are exactly the name (connect(\"hit\"), call_deferred(\"jump\")), and in scenes and resources (saved signal connections, animation method tracks). Each line says what kind of use it is; the declaration is marked too. Lexical: a `jump` of two different classes comes together. Leaves out res://addons/ unless `path` is inside it. Includes the Script Editor's unsaved text.",
			{
				"name": {"type": "string", "description": "The function, signal, variable, class… name (Inner.name takes the last part)"},
				"path": {"type": "string", "description": "res:// folder to search in (default res://)"},
				"scenes": {"type": "boolean", "description": "Also .tscn and .tres (default true)"},
			}, ["name"], _find_references), McpTool.ENVELOPE_PARTS),
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
## que el editor no terminó de registrar), el que dice el filesystem del editor o, si tampoco (en 4.8
## el archivo puede no estar todavía ahí), el .gd del disco que lo declara.
static func class_name_path(wanted: String) -> String:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == wanted:
			return str(entry.get("path", ""))
	if Engine.is_editor_hint():
		var found := _class_in(EditorInterface.get_resource_filesystem().get_filesystem(), wanted)
		if not found.is_empty():
			return found
	var budget := [MAX_CLASS_SCAN_FILES]
	return _class_declared_in("res://", wanted, budget)


## El .gd de `folder` (y sus subcarpetas, sin .godot ni las que tienen .gdignore) que declara
## `class_name <wanted>`, leyendo solo los que lo nombran. `budget` ([int]): archivos que quedan.
static func _class_declared_in(folder: String, wanted: String, budget: Array) -> String:
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() != "gd":
			continue
		budget[0] -= 1
		if budget[0] < 0:
			return ""
		var path := folder.path_join(file)
		var text := FileAccess.get_file_as_string(path)
		if not text.contains(wanted):
			continue
		for decl: Dictionary in GdscriptOutline.parse(text):
			if decl.kind == GdscriptOutline.KIND_CLASS_NAME and decl.name == wanted:
				return path
	for sub: String in DirAccess.get_directories_at(folder):
		var child := folder.path_join(sub)
		if sub.begins_with(".") or FileAccess.file_exists(child.path_join(".gdignore")):
			continue
		var found := _class_declared_in(child, wanted, budget)
		if not found.is_empty():
			return found
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


# --- find_symbols / find_references (m11-82) ----------------------------------------------------

## Los archivos a revisar: {files, error}. Sin `path` dentro de res://addons/, esa carpeta no entra.
func _search_files(args: Dictionary, extensions: PackedStringArray) -> Dictionary:
	var folder := McpTool.str_arg(args, "path", "res://").strip_edges()
	if folder.is_empty():
		folder = "res://"
	if not folder.begins_with("res://") or folder.contains(".."):
		return {"error": "`path` must be a res:// folder (got '%s')." % folder.left(256)}
	if not folder.ends_with("/"):
		folder += "/"
	var listed: PackedStringArray = list_files.call(folder, extensions) if list_files.is_valid() else _editor_files(folder, extensions)
	var skip_addons := not folder.begins_with(ADDONS)
	var files: PackedStringArray = []
	for file: String in listed:
		if skip_addons and file.begins_with(ADDONS):
			continue
		files.append(file)
		if files.size() >= MAX_FILES:
			break
	return {"files": files, "folder": folder, "addons_skipped": skip_addons}


static func _editor_files(folder: String, extensions: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := EditorInterface.get_resource_filesystem().get_filesystem_path(folder.trim_suffix("/") if folder != "res://" else folder)
	if dir != null:
		_collect(dir, extensions, out)
	return out


static func _collect(dir: EditorFileSystemDirectory, extensions: PackedStringArray, out: PackedStringArray) -> void:
	for i in dir.get_file_count():
		if dir.get_file(i).get_extension().to_lower() in extensions:
			out.append(dir.get_file_path(i))
	for i in dir.get_subdir_count():
		_collect(dir.get_subdir(i), extensions, out)


## El texto de un archivo del proyecto (el sin guardar del Script Editor si lo hay), o "" si no se
## puede leer o es muy grande. `unsaved` ([bool]) dice cuál.
func _text_of(path: String, unsaved: Array = []) -> String:
	if unsaved_buffer.is_valid():
		var buffer: Variant = unsaved_buffer.call(ProjectSettings.globalize_path(path))
		if buffer is String:
			unsaved.append(true)
			return buffer
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SOURCE_BYTES:
		return ""
	return file.get_as_text()


func _find_symbols(args: Dictionary) -> Dictionary:
	var query := McpTool.str_arg(args, "query").strip_edges()
	if query.is_empty():
		return McpTool.error("`query` is empty.")
	var kind := McpTool.str_arg(args, "kind")
	if not kind.is_empty() and not kind in KINDS:
		return McpTool.error("`kind` must be one of %s." % ", ".join(KINDS))
	var search := _search_files(args, PackedStringArray(["gd"]))
	if search.has("error"):
		return McpTool.error(search.error)
	var needle := query.to_lower()
	var deadline := Time.get_ticks_msec() + SEARCH_BUDGET_MS
	## [rango, ruta, línea, texto]: rango 0 exacto, 1 empieza así, 2 lo contiene.
	var found: Array = []
	var searched := 0
	var timed_out := false
	for path: String in search.files:
		if Time.get_ticks_msec() > deadline:
			timed_out = true
			break
		searched += 1
		var text := _text_of(path)
		if text.is_empty() or not text.to_lower().contains(needle):
			continue
		var lines := text.split("\n")
		for decl: Dictionary in GdscriptOutline.parse(text):
			if not kind.is_empty() and decl.kind != kind:
				continue
			var decl_name := str(decl.name).to_lower()
			var rank := 0 if decl_name == needle else (1 if decl_name.begins_with(needle) else (2 if decl_name.contains(needle) else -1))
			if rank < 0:
				continue
			var label := "%s %s" % [decl.kind, decl.qualified] if not str(decl.qualified).is_empty() else str(decl.kind)
			found.append([rank, path, decl.line, "%s:%d: %s · %s" % [path, decl.line, label, lines[decl.line - 1].strip_edges().left(LINE_CHARS)]])
	if found.is_empty():
		return McpTool.text("No declarations match \"%s\" in %d scripts of %s%s." % [query.left(128), searched, search.folder, _addons_note(search)] + (" (stopped after %d s)" % (SEARCH_BUDGET_MS / 1000) if timed_out else ""))
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	var shown: PackedStringArray = []
	for entry: Array in found.slice(0, MAX_SYMBOLS):
		shown.append(entry[3])
	var header := "%d declarations match \"%s\" in %d scripts of %s%s" % [found.size(), query.left(128), searched, search.folder, _addons_note(search)]
	if found.size() > shown.size():
		header += "; showing the first %d: narrow it with kind or path" % shown.size()
	if timed_out:
		header += "; stopped after %d s, so some scripts were not searched: narrow it with path" % (SEARCH_BUDGET_MS / 1000)
	return McpTool.text(header + "\n" + UntrustedText.wrap("\n".join(shown)))


func _find_references(args: Dictionary) -> Dictionary:
	var raw := McpTool.str_arg(args, "name").strip_edges()
	var wanted := raw.get_slice(".", raw.get_slice_count(".") - 1)
	if not wanted.is_valid_identifier():
		return McpTool.error("`name` must be an identifier (a function, signal, variable or class name).")
	var extensions := PackedStringArray(["gd"])
	if args.get("scenes", true) != false:
		extensions.append_array(SCENE_EXTENSIONS)
	var search := _search_files(args, extensions)
	if search.has("error"):
		return McpTool.error(search.error)
	var word := RegEx.create_from_string("\\b%s\\b" % wanted)
	var quoted := RegEx.create_from_string("[&^]?([\"'])%s\\1" % wanted)
	var scene_ref := RegEx.create_from_string("\\b(signal|method)=\"%s\"|\"method\": &?\"%s\"" % [wanted, wanted])
	var deadline := Time.get_ticks_msec() + SEARCH_BUDGET_MS
	var hits: PackedStringArray = []
	var total := 0
	var counts := {}
	var searched := 0
	var timed_out := false
	for path: String in search.files:
		if Time.get_ticks_msec() > deadline:
			timed_out = true
			break
		searched += 1
		var text := _text_of(path)
		if not text.contains(wanted):
			continue
		var found: Array = _script_references(text, wanted, word, quoted) if path.get_extension() == "gd" else _scene_references(text, scene_ref)
		for entry: Array in found:
			total += 1
			for use: String in str(entry[1]).split(", "):
				counts[use] = int(counts.get(use, 0)) + 1
			if hits.size() < MAX_REFERENCES:
				hits.append("%s:%d [%s] %s" % [path, entry[0], entry[1], str(entry[2]).strip_edges().left(LINE_CHARS)])
	if total == 0:
		return McpTool.text("No references to %s in %d files of %s%s." % [wanted, searched, search.folder, _addons_note(search)] + (" (stopped after %d s)" % (SEARCH_BUDGET_MS / 1000) if timed_out else ""))
	var summary: PackedStringArray = []
	for use: String in counts:
		summary.append("%s %d" % [use, counts[use]])
	var header := "%d lines reference %s in %d files of %s%s (%s)" % [total, wanted, searched, search.folder, _addons_note(search), ", ".join(summary)]
	if total > hits.size():
		header += "; showing the first %d: narrow it with path" % hits.size()
	if timed_out:
		header += "; stopped after %d s, so some files were not searched: narrow it with path" % (SEARCH_BUDGET_MS / 1000)
	return McpTool.text(header + "\n" + UntrustedText.wrap("\n".join(hits)))


## Las líneas de un .gd que usan `wanted`: [línea, usos, texto]. Usos: declaration, call, emit,
## connect, member, use (en el código) y string (un string que es el nombre justo).
static func _script_references(text: String, wanted: String, word: RegEx, quoted: RegEx) -> Array:
	var scanned := GdscriptOutline.scan(text)
	var declared := {}
	for decl: Dictionary in GdscriptOutline.parse(text):
		if decl.name == wanted:
			declared[decl.line] = true
	var lines: PackedStringArray = scanned.lines
	var result: Array = []
	for i in lines.size():
		var line := lines[i]
		if not line.contains(wanted):
			continue
		var code := GdscriptOutline.code_only(scanned, i)
		var uses: PackedStringArray = []
		for found: RegExMatch in word.search_all(code):
			var use := "declaration" if declared.has(i + 1) else _use_kind(code, found.get_start(), found.get_end())
			if not use in uses:
				uses.append(use)
		for found: RegExMatch in quoted.search_all(line):
			var content := Vector2i(found.get_start(1) + 1, found.get_end() - 1)
			if content in scanned.strings[i] and not "string" in uses:
				uses.append("string")
		if not uses.is_empty():
			result.append([i + 1, ", ".join(uses), line])
	return result


## Qué uso es el nombre en `code` entre `start` y `end`.
static func _use_kind(code: String, start: int, end: int) -> String:
	var after := code.substr(end).strip_edges(true, false)
	if after.begins_with(".emit("):
		return "emit"
	if after.begins_with(".connect(") or after.begins_with(".disconnect("):
		return "connect"
	if after.begins_with("("):
		return "call"
	if start > 0 and code[start - 1] == ".":
		return "member"
	return "use"


## Las líneas de un .tscn/.tres que nombran `wanted` en una conexión de señal guardada o en un track
## de método de una animación.
static func _scene_references(text: String, scene_ref: RegEx) -> Array:
	var result: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		var found := scene_ref.search(lines[i])
		if found == null:
			continue
		var use := "animation method track" if found.get_string(1).is_empty() else ("scene connection (%s)" % found.get_string(1))
		result.append([i + 1, use, lines[i]])
	return result


static func _addons_note(search: Dictionary) -> String:
	return " (without res://addons/)" if search.get("addons_skipped", false) else ""
