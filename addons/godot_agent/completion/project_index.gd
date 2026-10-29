@tool
extends RefCounted
## Índice del proyecto para el completado (spec §16.4), armado en un worker de WorkerThreadPool:
## firmas de los scripts, nodos de las escenas, grupos, conexiones de señales y el índice de líneas.
## Solo lee archivos (sin ClassDB, ProjectSettings ni el árbol): lo que necesita el hilo principal lo
## agrega ProjectContext. Una vez publicado no se modifica; el próximo build reutiliza lo que no cambió.

const LineIndex := preload("local/line_index.gd")
const GdLexer := preload("local/gd_lexer.gd")
const NGramModel := preload("local/ngram_model.gd")

const SCRIPT_EXT := "gd"
## C# (m14-08): solo entra al índice de líneas propio; las reglas y el n-gram son de GDScript.
const CSHARP_EXT := "cs"
const SCENE_EXT := "tscn"
## Extensiones que no son recursos cargables.
const SKIP_EXT: PackedStringArray = ["import", "uid", "tmp", "translation", "godot"]
const MAX_FILES := 20000
const FRESH_SECONDS := 2
const ROOT := "."

## ruta -> {mtime, extends, class_name, funcs: PackedStringArray, signals: {nombre: args},
##          groups: PackedStringArray, connects: Array[{emitter, signal, method}], lines: {lines, indents},
##          tokens: PackedStringArray, vars: PackedStringArray, onready: Array[[nombre, referencia]],
##          corpus: bool}
var scripts: Dictionary = {}
## ruta -> {mtime, nodes: Array[{name, path, type, parent, unique, script, instance, groups}],
##          connections: Array[{signal, from, to, method}]}
var scenes: Dictionary = {}
## script -> Array[{scene, node}] (ruta del nodo relativa a la raíz de la escena; "." = raíz)
var script_nodes: Dictionary = {}
## grupo -> cantidad de usos (escenas y código)
var groups: Dictionary = {}
## Todos los recursos cargables (`res://...`), para las reglas de preload/load.
var resources: PackedStringArray = []
## Estilo de los handlers conectados en código: `_on_<señal>` o `_on_<emisor>_<señal>`.
var handler_style: Dictionary = {"signal": 0, "emitter": 0}
var lines: LineIndex = LineIndex.new()
## Las líneas de los .cs del proyecto, aparte: sugerirle GDScript a un .cs no sirve.
var csharp_lines: LineIndex = LineIndex.new()
## ruta -> {mtime, lines} de los .cs.
var csharp: Dictionary = {}
var ngram: NGramModel = NGramModel.new()
## Scripts de las carpetas de corpus extra (fuera del proyecto): ruta -> {mtime, tokens}. Solo
## entrenan el n-gram.
var extra: Dictionary = {}
var build_usec: int = 0
var file_count: int = 0

var _re: Dictionary = {}


## Arma el índice. `options`: {root, exclude: PackedStringArray (prefijos relativos, solo para el
## corpus de líneas), buffers: {ruta: {text, skip_line}}, previous: este script o null, now: unix,
## extra_corpus: PackedStringArray de carpetas absolutas, cancel: [bool]}.
static func build(options: Dictionary) -> RefCounted:
	var started := Time.get_ticks_usec()
	var index := new()
	index._compile()
	var root: String = options.get("root", "res://")
	var previous: RefCounted = options.get("previous")
	var buffers: Dictionary = options.get("buffers", {})
	var exclude: PackedStringArray = options.get("exclude", PackedStringArray())
	# El mtime tiene resolución de 1 s: lo modificado hace muy poco se vuelve a leer siempre.
	var fresh_after := int(float(options.get("now", Time.get_unix_time_from_system()))) - FRESH_SECONDS
	var cancel: Array = options.get("cancel", [false])
	var files: PackedStringArray = []
	_walk(root, files, true, cancel)
	for path: String in files:
		if cancel[0]:
			break
		var ext := path.get_extension().to_lower()
		if ext in SKIP_EXT:
			continue
		index.resources.append(path)
		var mtime := FileAccess.get_modified_time(path)
		if ext == SCRIPT_EXT:
			var corpus := not _excluded(path, root, exclude)
			if buffers.has(path):
				var buffer: Dictionary = buffers[path]
				index.scripts[path] = index._parse_script(str(buffer.text), -1, int(buffer.get("skip_line", -1)), corpus)
			elif previous and mtime < fresh_after and previous.scripts.has(path) and int(previous.scripts[path].mtime) == mtime and bool(previous.scripts[path].corpus) == corpus:
				index.scripts[path] = previous.scripts[path]
			else:
				index.scripts[path] = index._parse_script(FileAccess.get_file_as_string(path), mtime, -1, corpus)
		elif ext == CSHARP_EXT and not _excluded(path, root, exclude):
			if buffers.has(path):
				var buffer: Dictionary = buffers[path]
				index.csharp[path] = {"mtime": -1, "lines": LineIndex.lines_of(str(buffer.text), int(buffer.get("skip_line", -1)), "//")}
			elif previous and mtime < fresh_after and previous.csharp.has(path) and int(previous.csharp[path].mtime) == mtime:
				index.csharp[path] = previous.csharp[path]
			else:
				index.csharp[path] = {"mtime": mtime, "lines": LineIndex.lines_of(FileAccess.get_file_as_string(path), -1, "//")}
		elif ext == SCENE_EXT:
			if previous and mtime < fresh_after and previous.scenes.has(path) and int(previous.scenes[path].mtime) == mtime:
				index.scenes[path] = previous.scenes[path]
			else:
				index.scenes[path] = index._parse_scene(FileAccess.get_file_as_string(path), mtime)
	index.file_count = files.size()
	# Cancelado (`wait()` al deshabilitar el plugin): el resultado se descarta, y el hilo principal
	# espera, así que no se arman las líneas ni el n-gram.
	if cancel[0]:
		return index
	index._link(root, exclude)
	var file_lines: Dictionary = {}
	var mtimes: Dictionary = {}
	for path: String in index.scripts:
		var info: Dictionary = index.scripts[path]
		if info.corpus:
			file_lines[path] = info.lines
			mtimes[path] = info.mtime if int(info.mtime) >= 0 else options.get("now", Time.get_unix_time_from_system())
	index.lines = LineIndex.build(file_lines, mtimes, float(options.get("now", Time.get_unix_time_from_system())))
	if not index.csharp.is_empty():
		var csharp_files: Dictionary = {}
		var csharp_mtimes: Dictionary = {}
		for path: String in index.csharp:
			csharp_files[path] = index.csharp[path].lines
			csharp_mtimes[path] = index.csharp[path].mtime if int(index.csharp[path].mtime) >= 0 else options.get("now", Time.get_unix_time_from_system())
		index.csharp_lines = LineIndex.build(csharp_files, csharp_mtimes, float(options.get("now", Time.get_unix_time_from_system())))
	index._index_extra(options.get("extra_corpus", PackedStringArray()), previous, fresh_after, cancel)
	var token_files: Dictionary = {}
	for path: String in index.scripts:
		if index.scripts[path].corpus:
			token_files[path] = index.scripts[path].tokens
	for path: String in index.extra:
		token_files[path] = index.extra[path].tokens
	index.ngram = NGramModel.build(token_files, previous.ngram if previous else null)
	index._re.clear()
	index.build_usec = Time.get_ticks_usec() - started
	return index


## `.gdignore` saca una carpeta del índice, salvo en la raíz (el fixture de tests lo usa para que
## el editor no lo importe).
static func _walk(dir_path: String, out: PackedStringArray, is_root: bool = false, cancel: Array = [false]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null or out.size() >= MAX_FILES or cancel[0]:
		return
	if not is_root and dir.file_exists(".gdignore"):
		return
	dir.include_hidden = false
	for file: String in dir.get_files():
		out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_walk(dir_path.path_join(sub), out, false, cancel)


## Carpetas de corpus extra (otros proyectos propios, spec §16.2c): solo sus `.gd`, reutilizados
## por mtime como los del proyecto.
func _index_extra(folders: PackedStringArray, previous: RefCounted, fresh_after: int, cancel: Array) -> void:
	for folder: String in folders:
		var files: PackedStringArray = []
		_walk(folder, files, true, cancel)
		for path: String in files:
			if cancel[0] or extra.size() >= MAX_FILES:
				return
			if path.get_extension().to_lower() != SCRIPT_EXT or extra.has(path):
				continue
			var mtime := FileAccess.get_modified_time(path)
			if previous and mtime < fresh_after and previous.extra.has(path) and int(previous.extra[path].mtime) == mtime:
				extra[path] = previous.extra[path]
			else:
				extra[path] = {"mtime": mtime, "tokens": GdLexer.tokenize(FileAccess.get_file_as_string(path))}


static func _excluded(path: String, root: String, exclude: PackedStringArray) -> bool:
	var relative := path.trim_prefix(root).trim_prefix("/")
	for prefix: String in exclude:
		if not prefix.is_empty() and relative.begins_with(prefix.trim_prefix("res://").trim_prefix("/")):
			return true
	return false


func _compile() -> void:
	var patterns := {
		"extends": "^extends\\s+(\"[^\"]+\"|'[^']+'|[\\w.]+)",
		"class_name": "^class_name\\s+(\\w+)(?:\\s+extends\\s+(\"[^\"]+\"|[\\w.]+))?",
		"func": "^(?:static\\s+)?func\\s+(\\w+)\\s*\\(",
		"signal": "^signal\\s+(\\w+)\\s*(\\(([^)]*)\\))?",
		"var": "^(?:@\\w+(?:\\([^)]*\\))?\\s+)*var\\s+(\\w+)",
		"onready": "^@onready\\s+var\\s+(\\w+)[^=]*=\\s*([$%](?:\"[^\"]+\"|[\\w/%.]+))\\s*$",
		"group": "(?:add_to_group|is_in_group|get_nodes_in_group|call_group|get_first_node_in_group|remove_from_group)\\(\\s*(?:[\\w.|]+\\s*,\\s*)?[\"'](\\w+)[\"']",
		"connect": "(?:([$%]\"[^\"]+\"|[$%][\\w/]+|[\\w.]+)\\.)?(\\w+)\\.connect\\(\\s*(\\w+)\\s*[,)]",
		"section": "^\\[(\\w+)\\s*(.*)\\]\\s*$",
		"attr": "(\\w+)=(\"(?:[^\"\\\\]|\\\\.)*\"|\\[[^\\]]*\\]|\\w+\\([^)]*\\)|[^\\s\\]]+)",
		"ext_ref": "ExtResource\\(\\s*\"?([^\")]+)\"?\\s*\\)",
		"string": "\"([^\"]*)\"",
	}
	for key: String in patterns:
		var re := RegEx.new()
		re.compile(patterns[key])
		_re[key] = re


func _parse_script(text: String, mtime: int, skip_line: int, corpus: bool) -> Dictionary:
	var info := {
		"mtime": mtime, "extends": "", "class_name": "", "signals": {}, "connects": [],
		"lines": {}, "tokens": PackedStringArray(), "onready": [], "corpus": corpus,
	}
	# Los Packed*Array son valores: se arman aparte y se guardan al final.
	var funcs := PackedStringArray()
	var groups_found := PackedStringArray()
	var vars := PackedStringArray()
	for line: String in text.split("\n"):
		if line.is_empty() or line.begins_with("\t") or line.begins_with(" ") or line.begins_with("#"):
			continue
		var found: RegExMatch
		if line.begins_with("func") or line.begins_with("static"):
			found = (_re.func as RegEx).search(line)
			if found:
				funcs.append(found.get_string(1))
		elif line.begins_with("@") or line.begins_with("var"):
			found = (_re.var as RegEx).search(line)
			if found:
				vars.append(found.get_string(1))
				var onready := (_re.onready as RegEx).search(line)
				if onready:
					(info.onready as Array).append([onready.get_string(1), onready.get_string(2).replace("\"", "")])
		elif line.begins_with("signal"):
			found = (_re.signal as RegEx).search(line)
			if found:
				# Firma partida en varias líneas: desconocida (null), así no se sugiere un handler
				# con la aridad equivocada.
				var unclosed := found.get_string(2).is_empty() and line.contains("(")
				info.signals[found.get_string(1)] = null if unclosed else found.get_string(3).strip_edges()
		elif line.begins_with("extends") and str(info.extends).is_empty():
			found = (_re.extends as RegEx).search(line)
			if found:
				info.extends = found.get_string(1).trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		elif line.begins_with("class_name"):
			found = (_re.class_name as RegEx).search(line)
			if found:
				info.class_name = found.get_string(1)
				if not found.get_string(2).is_empty() and str(info.extends).is_empty():
					info.extends = found.get_string(2).trim_prefix("\"").trim_suffix("\"")
	if corpus:
		info.lines = LineIndex.lines_of(text, skip_line)
		info.tokens = GdLexer.tokenize(text, skip_line)
		for found: RegExMatch in (_re.group as RegEx).search_all(text):
			groups_found.append(found.get_string(1))
		for found: RegExMatch in (_re.connect as RegEx).search_all(text):
			(info.connects as Array).append({"emitter": found.get_string(1), "signal": found.get_string(2), "method": found.get_string(3)})
	info.funcs = funcs
	info.groups = groups_found
	info.vars = vars
	return info


## Formato .tscn por líneas: ext_resource, node (con script, unique_name_in_owner y groups) y connection.
func _parse_scene(text: String, mtime: int) -> Dictionary:
	var ext: Dictionary = {}  # id -> ruta
	var nodes: Array[Dictionary] = []
	var connections: Array[Dictionary] = []
	var current: Dictionary = {}
	for line: String in text.split("\n"):
		if line.begins_with("["):
			current = {}
			var section := (_re.section as RegEx).search(line)
			if section == null:
				continue
			var attrs := _attrs(section.get_string(2))
			match section.get_string(1):
				"ext_resource":
					ext[str(attrs.get("id", ""))] = str(attrs.get("path", ""))
				"node":
					var parent: String = attrs.get("parent", "")
					var node_name: String = attrs.get("name", "")
					var node_path := ROOT if not attrs.has("parent") else (node_name if parent == ROOT else parent + "/" + node_name)
					current = {
						"name": node_name, "path": node_path, "type": attrs.get("type", ""), "unique": false,
						"script": "", "instance": _ext_path(str(attrs.get("instance", "")), ext),
						"groups": _strings(str(attrs.get("groups", ""))),
					}
					nodes.append(current)
				"connection":
					connections.append({
						"signal": attrs.get("signal", ""), "from": attrs.get("from", ""),
						"to": attrs.get("to", ""), "method": attrs.get("method", ""),
						# Con binds/unbinds el handler no tiene la firma de la señal.
						"exact": not (attrs.has("binds") or attrs.has("unbinds")),
					})
		elif not current.is_empty():
			if line.begins_with("script = "):
				current.script = _ext_path(line.substr(9), ext)
			elif line.begins_with("unique_name_in_owner = true"):
				current.unique = true
	return {"mtime": mtime, "nodes": nodes, "connections": connections}


func _attrs(text: String) -> Dictionary:
	var out: Dictionary = {}
	for found: RegExMatch in (_re.attr as RegEx).search_all(text):
		var value := found.get_string(2)
		if value.begins_with("\"") and value.ends_with("\"") and value.length() >= 2:
			value = value.substr(1, value.length() - 2).c_unescape()
		out[found.get_string(1)] = value
	return out


func _ext_path(value: String, ext: Dictionary) -> String:
	var found := (_re.ext_ref as RegEx).search(value)
	return str(ext.get(found.get_string(1), "")) if found else ""


func _strings(value: String) -> PackedStringArray:
	var out := PackedStringArray()
	for found: RegExMatch in (_re.string as RegEx).search_all(value):
		out.append(found.get_string(1))
	return out


## Datos que cruzan archivos: qué nodos usan cada script, grupos y estilo de los handlers.
func _link(root: String, exclude: PackedStringArray) -> void:
	for scene_path: String in scenes:
		var corpus := not _excluded(scene_path, root, exclude)
		for node: Dictionary in scenes[scene_path].nodes:
			var script_path: String = node.script
			# Escena heredada: la raíz trae el script de la base. Una instancia dentro de otra escena
			# no cuenta: sus hijos y únicos son de su propia escena.
			if script_path.is_empty() and node.path == ROOT and not str(node.instance).is_empty():
				script_path = _root_script(str(node.instance), 0)
			if not script_path.is_empty():
				(script_nodes.get_or_add(script_path, []) as Array).append({"scene": scene_path, "node": node.path})
			if corpus:
				for group: String in node.groups:
					groups[group] = int(groups.get(group, 0)) + 1
	for script_path: String in scripts:
		var info: Dictionary = scripts[script_path]
		for group: String in info.groups:
			groups[group] = int(groups.get(group, 0)) + 1
		for connect: Dictionary in info.connects:
			var method: String = connect.method
			if not method.begins_with("_on_"):
				continue
			if method == "_on_" + str(connect.signal):
				handler_style.signal += 1
			elif method.ends_with("_" + str(connect.signal)):
				handler_style.emitter += 1


## Script de la raíz de una escena instanciada (siguiendo herencia de escenas).
func _root_script(scene_path: String, depth: int) -> String:
	if depth > 8 or not scenes.has(scene_path):
		return ""
	for node: Dictionary in scenes[scene_path].nodes:
		if node.path == ROOT:
			if not str(node.script).is_empty():
				return node.script
			return _root_script(str(node.instance), depth + 1) if not str(node.instance).is_empty() else ""
	return ""


## Tipo de un nodo: el `type` de la escena; si es una instancia, el de la raíz instanciada; si no
## tiene ninguno (nodo de una escena heredada o hijo editable de una instancia), el del mismo nodo en
## la escena de la que viene. "" si no se puede saber.
func node_type(scene_path: String, node: Dictionary, depth: int = 0) -> String:
	if not str(node.type).is_empty():
		return node.type
	if depth > 8:
		return ""
	var instance: String = node.instance
	if not instance.is_empty():
		var instanced_root := _find_node(instance, ROOT)
		return node_type(instance, instanced_root, depth + 1) if not instanced_root.is_empty() else ""
	var path: String = node.path
	if path == ROOT:
		return ""
	# Escena heredada: el mismo nodo en la escena base.
	var root_node := _find_node(scene_path, ROOT)
	if not str(root_node.get("instance", "")).is_empty():
		var base := str(root_node.instance)
		var in_base := _find_node(base, path)
		if not in_base.is_empty():
			return node_type(base, in_base, depth + 1)
	# Hijo editable: el ancestro más cercano que es una instancia.
	var parts := path.split("/")
	for i in range(parts.size() - 1, 0, -1):
		var ancestor := _find_node(scene_path, "/".join(parts.slice(0, i)))
		if not str(ancestor.get("instance", "")).is_empty():
			var inner := _find_node(str(ancestor.instance), "/".join(parts.slice(i)))
			return node_type(str(ancestor.instance), inner, depth + 1) if not inner.is_empty() else ""
	return ""


func _find_node(scene_path: String, node_path: String) -> Dictionary:
	for node: Dictionary in scenes.get(scene_path, {}).get("nodes", []):
		if node.path == node_path:
			return node
	return {}
