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
const ShellCommand := preload("shell_command.gd")
const COMMAND_PREFIXES: PackedStringArray = ["sudo", "command", "builtin", "nice", "time"]
## Palabras de la shell que pueden ir antes de un `cd` en el mismo comando.
const SHELL_KEYWORDS: PackedStringArray = ["{", "!", "then", "else", "do"]


## Qué escribiría `tool_call` en el proyecto por fuera del editor: un archivo, un comando
## recortado, o "" si nada. `start_dir`: dónde corre el comando de shell (por defecto, el proyecto).
static func blocked_target(tool_call: Dictionary, group: String, project_root: String, start_dir: String = "") -> String:
	var raw: Dictionary = tool_call.get("rawInput") if tool_call.get("rawInput") is Dictionary else {}
	if group == PermissionPolicy.GROUP_SHELL:
		# Antigravity dice dónde corre el comando (rawInput.Cwd); Claude Code corre en el proyecto.
		var dir := start_dir
		for key: String in ["Cwd", "cwd"]:
			if dir.is_empty() and raw.get(key) is String:
				dir = raw[key]
		return shell_write_target(ShellCommand.of(raw), project_root, dir)
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


## Por qué se rechazó un comando que escribe `target` (para el agente, en inglés): qué usar en su lugar.
static func rejection_reason(target: String) -> String:
	var alternative := alternative_for(target) if is_editor_managed(target) \
		else "write scripts and text files with your own file tools (the harness syncs them with the editor), and move, copy or delete project files with godot.move_file, godot.copy_file and godot.delete_file"
	return "it writes %s in the project without going through the editor, which the harness rejects in every mode. Instead, %s. Writing outside the project (in /tmp, for example) is not affected; a cd earlier in the same command counts." % [target, alternative]


## El primer archivo del proyecto que escribe el comando, o "" si no escribe en el proyecto. Las
## rutas relativas se resuelven contra el último `cd`/`pushd` del comando (m11-69), empezando en
## `start_dir` (por defecto, el proyecto): `cd /tmp && echo x > f` no escribe el proyecto. Un `cd` que
## no se puede resolver (`cd $T`, `cd ~`, `cd -`) deja sin bloquear las relativas que siguen, igual
## que una ruta con `$` o `~`. Un `cd` dentro de `( … )`, `$( … )` o antes de un `|` no vale después.
## Devuelve la ruta como está en el comando o, después de un `cd`, resuelta.
static func shell_write_target(command: String, project_root: String, start_dir: String = "") -> String:
	var split := _split_heredocs(command)
	var root := project_root.simplify_path()
	var start := resolve(start_dir, root) if not start_dir.is_empty() else root
	if not start.begins_with("/"):
		start = ""  # `~`, `$X`: no se sabe dónde corre
	for segment: Dictionary in shell_segments(_strip_quotes(str(split.command)), start):
		var dir: String = segment.dir
		for target: String in segment_targets(str(segment.text)):
			var resolved := resolve(target, dir)
			if is_inside(resolved, root):
				return target if dir == root else resolved
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


## Los archivos que escribe un comando simple (sin comillas, ver _strip_quotes): redirecciones,
## `tee`, `dd of=`, `sed -i`/`perl -i` y los mv/cp/rm.
static func segment_targets(segment: String) -> PackedStringArray:
	var targets: PackedStringArray = []
	var redirect := RegEx.create_from_string("(\\d*|&)>[>|]?\\s*([^\\s;&|()<>]+)")
	for match: RegExMatch in redirect.search_all(segment):
		if match.get_string(1) == "2" or match.get_string(2).begins_with("&"):
			continue
		targets.append(match.get_string(2))
	var tee := RegEx.create_from_string("\\btee\\s+(?:-\\w+\\s+)*([^\\s;&|()<>]+)")
	for match: RegExMatch in tee.search_all(segment):
		targets.append(match.get_string(1))
	var dd := RegEx.create_from_string("\\bof=([^\\s;&|()<>]+)")
	for match: RegExMatch in dd.search_all(segment):
		targets.append(match.get_string(1))
	# sed -i / perl -i: los archivos son los argumentos que no son opciones.
	var in_place := RegEx.create_from_string("\\b(?:sed|perl)\\s+([^;&|]*?)(?:-\\w*i\\b|--in-place)([^;&|]*)")
	for match: RegExMatch in in_place.search_all(segment):
		var files := _path_args(match.get_string(2))
		targets.append_array(files if not files.is_empty() else PackedStringArray(["."]))
	targets.append_array(file_command_targets(segment))
	return targets


## Parte una línea sin comillas en comandos simples: [{text, dir}], con `dir` la carpeta en la que
## corre cada uno ("" si un `cd` no se pudo resolver). Sigue `cd`, `pushd` y `popd`; cada `( … )` y
## `$( … )` es una subshell con su propia carpeta, y su texto sale como comandos aparte (en el de
## afuera queda `$_`). Lo que corre antes de un `|` también es una subshell.
static func shell_segments(line: String, start_dir: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	# Cada marco: la carpeta, la pila de pushd y el comando que se va armando.
	var frames: Array[Dictionary] = [{"dir": start_dir, "stack": [], "text": ""}]
	var i := 0
	while i < line.length():
		var c := line[i]
		var frame: Dictionary = frames.back()
		var prev := line[i - 1] if i > 0 else ""
		var next := line[i + 1] if i + 1 < line.length() else ""
		if c == "(":
			if prev == "$":
				frame.text += "_"
			_flush_segment(frame, segments, false)
			frames.append({"dir": frame.dir, "stack": frame.stack.duplicate(), "text": ""})
		elif c == ")" and frames.size() > 1:
			_flush_segment(frame, segments, false)
			frames.pop_back()
		elif c == ")" or c == ";" or c == "\n":
			_flush_segment(frame, segments, true)
		elif c == "&" and prev != ">" and next != ">":
			if next == "&":
				i += 1
			_flush_segment(frame, segments, true)
		elif c == "|" and prev != ">":
			if next == "|" or next == "&":
				i += 1
			# a || b: b corre en la misma shell; a | b: a en una subshell.
			_flush_segment(frame, segments, next == "|")
		else:
			frame.text += c
		i += 1
	while not frames.is_empty():
		_flush_segment(frames.pop_back(), segments, false)
	return segments


## Cierra el comando del marco: lo agrega a `segments` y, si `keeps_dir`, aplica su cd/pushd/popd.
static func _flush_segment(frame: Dictionary, segments: Array[Dictionary], keeps_dir: bool) -> void:
	var text: String = str(frame.text).strip_edges()
	frame.text = ""
	if text.is_empty():
		return
	segments.append({"text": text, "dir": frame.dir})
	if not keeps_dir:
		return
	var words := text.split(" ", false)
	while not words.is_empty() and (words[0] in COMMAND_PREFIXES or words[0] in SHELL_KEYWORDS):
		words.remove_at(0)
	if words.is_empty() or not words[0] in ["cd", "pushd", "popd"]:
		return
	var args := Array(words.slice(1)).filter(func(word: String) -> bool: return not word.begins_with("-") or word == "-")
	if words[0] == "popd":
		frame.dir = frame.stack.pop_back() if not frame.stack.is_empty() else ""
		return
	if words[0] == "pushd":
		frame.stack.append(frame.dir)
	var dir := resolve(str(args[0]), str(frame.dir)) if not args.is_empty() else ""
	frame.dir = dir if dir.begins_with("/") else ""


## `path` como ruta absoluta si se puede: relativa contra `dir`; "" si es relativa y `dir` es ""
## (no se sabe dónde corre). `res://`, `$…` y `~…` quedan como están.
static func resolve(path: String, dir: String) -> String:
	var target := path.strip_edges().trim_prefix("file://")
	if target == "-":
		return ""
	if target.is_empty() or target.begins_with("res://") or target.begins_with("$") or target.begins_with("~"):
		return target
	if target.begins_with("/"):
		return target.simplify_path()
	if dir.is_empty():
		return ""
	return dir.path_join(target).simplify_path()


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
	target = target.simplify_path()
	var root := project_root.simplify_path().trim_suffix("/")
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
