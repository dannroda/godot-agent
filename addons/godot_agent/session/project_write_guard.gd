@tool
extends RefCounted
## Escrituras al proyecto que se saltean el editor (D48). El agente tiene que escribir scripts con
## sus herramientas de archivos (el harness las sincroniza con el editor) y escenas con las tools
## `godot.*`. Se rechazan solas, sin tarjeta:
## - comandos de shell que escriben archivos del proyecto: redirecciones, `tee`, `sed -i`, `dd of=`
##   y scripts (python, node, ruby, perl) que abren archivos para escribir;
## - `mv`, `cp`, `rm` (y `git mv`/`git rm`) sobre archivos del proyecto: rompen referencias; van
##   por move_file, copy_file y delete_file (m4-10);
## - escribir a mano `.tscn`, `.tres`, `.uid`, `.import` o `project.godot` con las herramientas de archivos
##   del agente.
## Escribir fuera del proyecto (`/tmp`…) sigue pasando por la política de permisos de siempre.

const PermissionPolicy := preload("permission_policy.gd")

## Archivos que mantiene el editor (o sus tools): no se escriben a mano.
const EDITOR_FILE_EXTENSIONS: PackedStringArray = ["tscn", "tres", "uid", "import"]
## Archivos por nombre que se cambian con tools del editor (m4-09).
const EDITOR_FILE_NAMES: PackedStringArray = ["project.godot"]
const INTERPRETERS: PackedStringArray = ["python", "python3", "node", "ruby", "perl"]
## APIs de escritura de los intérpretes de INTERPRETERS.
const WRITE_APIS: PackedStringArray = [
	"open(", "write_text(", "write_bytes(", "shutil.", "os.remove(", "os.rename(", "os.replace(", "os.unlink(",
	"writeFile", "appendFile", "createWriteStream", "File.write", "IO.write",
]
const SAFE_TARGETS: PackedStringArray = ["/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"]
## Comandos de archivos: para cp solo cuenta el destino (copiar algo del proyecto afuera no lo toca).
const FILE_COMMANDS: PackedStringArray = ["mv", "cp", "rm", "rmdir", "unlink"]
const COMMAND_PREFIXES: PackedStringArray = ["sudo", "command", "builtin", "nice", "time"]


## Qué escribiría `tool_call` en el proyecto por fuera del editor: un archivo, un comando
## recortado, o "" si nada.
static func blocked_target(tool_call: Dictionary, group: String, project_root: String) -> String:
	var raw: Dictionary = tool_call.get("rawInput") if tool_call.get("rawInput") is Dictionary else {}
	if group == PermissionPolicy.GROUP_SHELL:
		return shell_write_target(str(raw.get("command", "")), project_root)
	if group == PermissionPolicy.GROUP_EDIT_FILES:
		for path: String in _edit_paths(tool_call, raw):
			if is_editor_managed(path) and is_inside(path, project_root):
				return path
	return ""


## true si el archivo lo mantiene el editor y no se escribe a mano.
static func is_editor_managed(path: String) -> bool:
	return path.get_extension().to_lower() in EDITOR_FILE_EXTENSIONS or path.get_file() in EDITOR_FILE_NAMES


## Con qué se cambia un archivo que mantiene el editor (para el mensaje al agente).
static func alternative_for(path: String) -> String:
	if path.get_file() == "project.godot":
		return "change project settings with the godot.* tools (set_project_setting, set_input_action, set_autoload)"
	if path.get_extension().to_lower() == "tres":
		return "create and change resources with the godot.* tools (create_resource, set_resource_properties, get_resource)"
	return "create and edit scenes with the godot.* tools (create_scene, add_nodes, set_properties, save_scene); the editor manages .uid and .import files"


## El primer archivo del proyecto que escribe el comando, o "" si no escribe en el proyecto.
static func shell_write_target(command: String, project_root: String) -> String:
	var split := _split_heredocs(command)
	var line := _strip_quotes(str(split.command))
	var targets: PackedStringArray = []
	var redirect := RegEx.create_from_string("(\\d*|&)>>?\\s*([^\\s;&|()<>]+)")
	for match: RegExMatch in redirect.search_all(line):
		if match.get_string(1) == "2" or match.get_string(2).begins_with("&"):
			continue
		targets.append(match.get_string(2))
	var tee := RegEx.create_from_string("\\btee\\s+(?:-\\w+\\s+)*([^\\s;&|()<>]+)")
	for match: RegExMatch in tee.search_all(line):
		targets.append(match.get_string(1))
	var dd := RegEx.create_from_string("\\bof=([^\\s;&|()<>]+)")
	for match: RegExMatch in dd.search_all(line):
		targets.append(match.get_string(1))
	# sed -i / perl -i: los archivos son los argumentos que no son opciones.
	var in_place := RegEx.create_from_string("\\b(?:sed|perl)\\s+([^;&|]*?)(?:-\\w*i\\b|--in-place)([^;&|]*)")
	for match: RegExMatch in in_place.search_all(str(split.command)):
		var files := _path_args(match.get_string(2))
		targets.append_array(files if not files.is_empty() else PackedStringArray(["."]))
	targets.append_array(file_command_targets(line))
	for target: String in targets:
		if is_inside(target, project_root):
			return target
	# Scripts: en un heredoc pasado a un intérprete o en -c/-e.
	var scripts: PackedStringArray = []
	for body: Dictionary in split.bodies:
		if _first_word(str(body.feeds)) in INTERPRETERS:
			scripts.append(str(body.text))
	var inline := RegEx.create_from_string("\\b(?:python3?|node|ruby|perl)\\s+-[ce]\\s+(?:'([^']*)'|\"((?:[^\"\\\\]|\\\\.)*)\")")
	for match: RegExMatch in inline.search_all(str(split.command)):
		scripts.append(match.get_string(1) + match.get_string(2))
	for script: String in scripts:
		var target := _script_write_target(script, project_root)
		if not target.is_empty():
			return target
	return ""


## Rutas que tocan los mv/cp/rm/rmdir/unlink y git mv/git rm de una línea (sin comillas).
static func file_command_targets(line: String) -> PackedStringArray:
	var targets: PackedStringArray = []
	for segment: String in RegEx.create_from_string("[;&|\n]+").sub(line, "\n", true).split("\n", false):
		var words := segment.strip_edges().split(" ", false)
		while not words.is_empty() and (words[0] in COMMAND_PREFIXES or words[0].contains("=")):
			words.remove_at(0)
		if words.is_empty():
			continue
		var command := words[0].get_file()
		var args := words.slice(1)
		if command == "git" and not args.is_empty() and args[0] in ["mv", "rm"]:
			command = args[0]
			args = args.slice(1)
		elif not command in FILE_COMMANDS:
			continue
		var paths: PackedStringArray = []
		var target_dir := ""
		for i: int in args.size():
			if args[i] in ["-t", "--target-directory"] and i + 1 < args.size():
				target_dir = args[i + 1]
			elif args[i].begins_with("--target-directory="):
				target_dir = args[i].get_slice("=", 1)
			elif not args[i].begins_with("-") and (i == 0 or not args[i - 1] in ["-t", "--target-directory"]):
				paths.append(args[i])
		if command == "cp":
			if not target_dir.is_empty():
				targets.append(target_dir)
			elif not paths.is_empty():
				targets.append(paths[paths.size() - 1])
		else:
			targets.append_array(paths)
			if not target_dir.is_empty():
				targets.append(target_dir)
	return targets


## Una ruta relativa cuenta como del proyecto (el agente corre con cwd en el proyecto). Las que
## empiezan con `$` o `~` no se pueden resolver acá y no se bloquean.
static func is_inside(path: String, project_root: String) -> bool:
	var target := path.strip_edges().trim_prefix("file://")
	if target.is_empty() or target in SAFE_TARGETS or target.begins_with("$") or target.begins_with("~"):
		return false
	if target.begins_with("res://"):
		return true
	if not target.begins_with("/"):
		return true
	var root := project_root.trim_suffix("/")
	return target == root or target.begins_with(root + "/")


static func _edit_paths(tool_call: Dictionary, raw: Dictionary) -> PackedStringArray:
	var paths: PackedStringArray = []
	for key: String in ["file_path", "path", "notebook_path"]:
		if raw.get(key) is String:
			paths.append(raw[key])
	if tool_call.get("locations") is Array:
		for location: Variant in tool_call.locations:
			if location is Dictionary and location.get("path") is String:
				paths.append(location.path)
	if tool_call.get("content") is Array:
		for item: Variant in tool_call.content:
			if item is Dictionary and item.get("type") == "diff" and item.get("path") is String:
				paths.append(item.path)
	return paths


## Separa los heredocs: `command` sin sus cuerpos y `bodies` = [{text, feeds}], donde `feeds` es
## el comando de la línea que abre el heredoc.
static func _split_heredocs(command: String) -> Dictionary:
	var opener := RegEx.create_from_string("<<-?\\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\\1")
	var kept: PackedStringArray = []
	var bodies: Array[Dictionary] = []
	var lines := command.split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i]
		kept.append(line)
		i += 1
		for match: RegExMatch in opener.search_all(line):
			var delimiter := match.get_string(2)
			var body: PackedStringArray = []
			while i < lines.size() and lines[i].strip_edges() != delimiter:
				body.append(lines[i])
				i += 1
			i += 1  # el delimitador
			var feeds := line.substr(0, match.get_start()).get_slice("|", line.substr(0, match.get_start()).get_slice_count("|") - 1)
			bodies.append({"text": "\n".join(body), "feeds": feeds.get_slice("&&", feeds.get_slice_count("&&") - 1)})
	return {"command": "\n".join(kept), "bodies": bodies}


## Saca las comillas y neutraliza `<>|;&` adentro (un `>` en un string no es una redirección), sin
## perder la ruta de `> "$TMPDIR/x"`.
static func _strip_quotes(text: String) -> String:
	var result := ""
	var last := 0
	for match: RegExMatch in RegEx.create_from_string("'([^']*)'|\"((?:[^\"\\\\]|\\\\.)*)\"").search_all(text):
		var inner := match.get_string(1) + match.get_string(2)
		for special: String in ["<", ">", "|", ";", "&"]:
			inner = inner.replace(special, "_")
		result += text.substr(last, match.get_start() - last) + inner.replace(" ", "_")
		last = match.get_end()
	return result + text.substr(last)


static func _first_word(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	return words[0].get_file() if not words.is_empty() else ""


static func _path_args(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for word: String in text.split(" ", false):
		var arg := word.strip_edges().trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
		if not arg.begins_with("-") and (arg.contains("/") or arg.contains(".")) and not arg.begins_with("s/") and not arg.begins_with("s|"):
			result.append(arg)
	return result


## Si el script escribe archivos: la primera ruta del proyecto que nombra, "script" si escribe
## sin que se vea a dónde, o "" si no escribe o solo nombra rutas de afuera.
static func _script_write_target(script: String, project_root: String) -> String:
	var writes := RegEx.create_from_string("open\\([^)]*['\"][wax]\\+?b?['\"]").search(script) != null
	for api: String in WRITE_APIS:
		if api != "open(" and script.contains(api):
			writes = true
	if not writes:
		return ""
	var literal := RegEx.create_from_string("['\"]([^'\"\\s]*/[^'\"\\s]*|[^'\"\\s]+\\.(?:gd|tscn|tres|res|cfg|json|md|txt|godot|gdshader|cs|py|csv|ini))['\"]")
	var named := false
	for match: RegExMatch in literal.search_all(script):
		named = true
		if is_inside(match.get_string(1), project_root):
			return match.get_string(1)
	return "" if named else "script"
